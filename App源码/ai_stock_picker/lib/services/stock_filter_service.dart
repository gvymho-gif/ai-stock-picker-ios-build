/// 股票筛选服务
/// 实现全市场股票筛选功能 - 真实数据
/// v2.2: 修复股息率筛选不匹配问题
///   - 删除push2 API f187方案(实测f187=净利率，非股息率；且push2从服务器不可达)
///   - 改用东方财富BonusFinancing API逐只并发计算股息率(与个股详情页一致)
///   - 先预筛选再查股息率，大幅减少请求数量

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/filter_criteria.dart';
import 'foreign_holder_service.dart';

class StockFilterService {
  static const int _timeoutSeconds = 20;
  static final http.Client _client = http.Client();
  static const MethodChannel _codecChannel = MethodChannel('com.aistockpicker/codec');
  static bool _channelReady = true;

  /// 执行全市场筛选
  Future<List<Map<String, dynamic>>> filterStocks(
    FilterCriteria criteria, {
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      // 1. 获取外资持股数据（如果启用了外资筛选）
      Map<String, Map<String, dynamic>>? foreignHoldings;
      if (criteria.market == 'A' && criteria.foreignHolderFilter != null && criteria.foreignHolderFilter!.hasFilter) {
        onProgress?.call(0, 55);
        foreignHoldings = await ForeignHolderService.fetchForeignHoldings();
      }

      // 2. 获取股票列表和数据
      final stocks = await _fetchStockData(criteria.market, onProgress);
      
      if (stocks.isEmpty) {
        print('警告：未获取到任何股票数据');
        return [];
      }

      // 3. 合并外资持股数据
      if (foreignHoldings != null) {
        for (final stock in stocks) {
          final code = stock['code']?.toString() ?? '';
          final foreignData = foreignHoldings[code];
          stock['foreign_holding'] = foreignData;
          stock['foreign_ratio'] = foreignData?['total_ratio'] ?? 0.0;
          stock['foreign_change'] = foreignData?['change_ratio'] ?? 0.0;
        }
      }
      
      // 4. A股补充：批量获取财务指标（ROE/营收增速/净利润增速/股息率）
      if (criteria.market == 'A') {
        final needFinancial = criteria.roeRange != null || 
            criteria.revenueGrowthRange != null || 
            criteria.profitGrowthRange != null;
        final needDividend = criteria.dividendYieldRange != null;
        
        if (needFinancial) {
          onProgress?.call(51, 55);
          final financialData = await _fetchAFinancialData();
          int merged = 0;
          for (final stock in stocks) {
            final code = stock['code']?.toString() ?? '';
            final fData = financialData[code];
            if (fData != null) {
              stock['roe'] = fData['roe'];
              stock['revenue_growth'] = fData['revenue_growth'];
              stock['profit_growth'] = fData['profit_growth'];
              merged++;
            }
          }
          print('财务数据合并完成: $merged/${stocks.length}只股票有数据');
        }
        
        if (needDividend) {
          onProgress?.call(53, 55);
          // 先用其他条件预筛选，减少需要查询股息率的股票数
          final preFiltered = _applyFiltersExceptDividend(stocks, criteria);
          print('股息率预筛选: ${stocks.length}只 → ${preFiltered.length}只待查');
          // 使用BonusFinancing API逐只并发计算股息率（与个股详情页一致）
          await _fetchDividendYieldPerStock(preFiltered);
          final withDy = preFiltered.where((s) => s['dividend_yield'] != null).length;
          print('股息率查询完成: $withDy/${preFiltered.length}只有数据');
        }
      }
      
      // 5. 应用筛选条件
      final filtered = _applyFilters(stocks, criteria);
      
      // 6. 按评分排序
      filtered.sort((a, b) => (_safeDouble(b['filter_score'])).compareTo(_safeDouble(a['filter_score'])));
      
      return filtered.take(100).toList();
    } catch (e) {
      print('筛选错误: $e');
      return [];
    }
  }

  /// 获取股票数据
  Future<List<Map<String, dynamic>>> _fetchStockData(
    String market,
    void Function(int, int)? onProgress,
  ) async {
    if (market == 'A') {
      return _fetchAStockData(onProgress);
    } else if (market == 'HK') {
      return _fetchHKStockData(onProgress);
    } else if (market == 'US') {
      return _fetchUSStockData(onProgress);
    }
    return [];
  }

  /// A股：使用新浪行情API分页获取全市场数据
  Future<List<Map<String, dynamic>>> _fetchAStockData(void Function(int, int)? onProgress) async {
    final result = <Map<String, dynamic>>[];
    const int totalPages = 50; // 50页 * 100只 = 5000只
    
    try {
      for (int page = 1; page <= totalPages; page++) {
        onProgress?.call(page, totalPages);
        
        try {
          final resp = await _client.get(
            Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=$page&num=100&sort=changepercent&asc=0&node=hs_a'),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
              'Accept': 'application/json',
              'Referer': 'https://finance.sina.com.cn',
            },
          ).timeout(const Duration(seconds: _timeoutSeconds));
          
          if (resp.statusCode != 200) continue;
          if (resp.body.isEmpty || resp.body == 'null' || resp.body == '[]') continue;
          
          final data = json.decode(resp.body) as List;
          
          for (final item in data) {
            final m = item as Map<String, dynamic>;
            final sym = m['symbol']?.toString() ?? '';
            if (sym.isEmpty) continue;
            
            final code = sym.replaceAll('sh', '').replaceAll('sz', '').replaceAll('bj', '');
            final name = m['name']?.toString() ?? '';
            
            // 排除ST股和北交所
            if (name.contains('ST') || name.contains('*ST')) continue;
            if (sym.contains('bj')) continue;
            
            final pe = _safeDouble(m['per']);
            final mktcap = _safeDouble(m['mktcap']); // 万元
            
            result.add({
              'symbol': code,
              'code': code,
              'name': name,
              'price': _safeDouble(m['trade']),
              'change_pct': _safeDouble(m['changepercent']),
              'pe': pe,
              'pb': _safeDouble(m['pb']),
              'mktcap': mktcap,
              'nmc': _safeDouble(m['nmc']),
              'turnoverratio': _safeDouble(m['turnoverratio']),
              'volume': _safeDouble(m['volume']),
            });
          }
          
          // 每获取5页暂停一下，避免请求过快
          if (page % 5 == 0) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } catch (e) {
          print('A股第$page页获取失败: $e');
          continue;
        }
      }
      
      print('A股共获取${result.length}只股票');
    } catch (e) {
      print('A股数据获取错误: $e');
    }
    
    return result;
  }

  // ============ A股补充数据获取 ============
  
  /// A股批量获取财务指标(ROE/营收增速/净利润增速)
  /// 使用东方财富datacenter API，3页×5000条获取约6600只股票
  /// 按REPORT_DATE降序排列，去重后每只股票取最新一期数据
  Future<Map<String, Map<String, dynamic>>> _fetchAFinancialData() async {
    final result = <String, Map<String, dynamic>>{};
    
    try {
      for (int page = 1; page <= 3; page++) {
        try {
          final resp = await _client.get(
            Uri.parse('https://datacenter.eastmoney.com/securities/api/data/get'
                '?type=RPT_F10_FINANCE_MAINFINADATA'
                '&sty=SECURITY_CODE,ROEJQ,TOTALOPERATEREVETZ,PARENTNETPROFITTZ'
                '&ps=5000&p=$page&sr=-1&st=REPORT_DATE&source=HSF10&client=PC'),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
              'Referer': 'https://emweb.securities.eastmoney.com',
            },
          ).timeout(const Duration(seconds: 15));
          
          if (resp.statusCode != 200 || resp.body.isEmpty) continue;
          
          final raw = json.decode(resp.body);
          if (raw is! Map<String, dynamic>) continue;
          if (raw['success'] != true) continue;
          
          final data = raw['result']?['data'];
          if (data is! List) continue;
          
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final code = item['SECURITY_CODE']?.toString() ?? '';
            // 去重：只取每只股票的最新一期数据（按REPORT_DATE降序，先到的最新）
            if (code.isEmpty || result.containsKey(code)) continue;
            
            final roeJq = _safeDouble(item['ROEJQ']);
            final revGrowth = _safeDouble(item['TOTALOPERATEREVETZ']);
            final profitGrowth = _safeDouble(item['PARENTNETPROFITTZ']);
            
            result[code] = {
              'roe': roeJq,                           // 百分比(如15.23表示15.23%)
              'revenue_growth': revGrowth,             // 百分比
              'profit_growth': profitGrowth,           // 百分比
            };
          }
          
          print('财务数据第${page}页: 获取${data.length}条, 累计唯一${result.length}只');
          
          // 如果返回数据不足5000条，说明没有更多了
          if (data.length < 5000) break;
          
          // 页间延迟，避免请求过快
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          print('财务数据第${page}页获取失败: $e');
          continue;
        }
      }
      
      print('A股财务数据: 共${result.length}只股票');
    } catch (e) {
      print('A股财务数据获取错误: $e');
    }
    
    return result;
  }
  
  /// 并发获取股息率（东方财富分红融资API）
  /// 与个股详情页local_data_service._fetchDividendYield()使用相同API和算法
  /// 先预筛选减少数量，再分批并发请求，提高效率
  Future<void> _fetchDividendYieldPerStock(List<Map<String, dynamic>> stocks) async {
    final toFetch = stocks.where((s) => s['dividend_yield'] == null).take(500).toList();
    if (toFetch.isEmpty) return;

    const batchSize = 20; // 每批并发请求数
    int fetched = 0;

    for (int i = 0; i < toFetch.length; i += batchSize) {
      final end = i + batchSize > toFetch.length ? toFetch.length : i + batchSize;
      final batch = toFetch.sublist(i, end);

      // 并发请求
      final futures = batch.map((stock) => _fetchSingleDividendYield(stock)).toList();
      final results = await Future.wait(futures);
      fetched += results.where((r) => r).length;

      // 批间延迟，避免请求过快
      if (end < toFetch.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    print('股息率并发查询: 已获取$fetched/${toFetch.length}只');
  }

  /// 获取单只股票的股息率
  /// 使用东方财富BonusFinancing API，汇总最近12个月每股派息/当前股价
  /// 计算逻辑与个股详情页local_data_service._fetchDividendYield()完全一致
  Future<bool> _fetchSingleDividendYield(Map<String, dynamic> stock) async {
    final code = stock['code']?.toString() ?? '';
    if (code.isEmpty) return false;

    try {
      final prefix = code.startsWith('6') || code.startsWith('9') ? 'SH' : 'SZ';
      final resp = await _client.get(
        Uri.parse('https://emweb.securities.eastmoney.com/PC_HSF10/BonusFinancing/PageAjax?code=$prefix$code'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
          'Referer': 'https://emweb.securities.eastmoney.com/',
        },
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode != 200 || resp.body.isEmpty) return false;

      final raw = json.decode(resp.body);
      if (raw is! Map<String, dynamic>) return false;

      final fhyx = raw['fhyx'];
      if (fhyx is! List || fhyx.isEmpty) return false;

      final price = _safeDouble(stock['price']);
      if (price <= 0) return false;

      // 汇总最近12个月的每股派息（与个股详情页算法一致）
      final now = DateTime.now();
      final oneYearAgo = now.subtract(const Duration(days: 365));
      double totalDps = 0;

      for (final item in fhyx) {
        if (item is! Map<String, dynamic>) continue;
        final profile = item['IMPL_PLAN_PROFILE']?.toString() ?? '';
        final noticeDateStr = item['NOTICE_DATE']?.toString() ?? '';
        final progress = item['ASSIGN_PROGRESS']?.toString() ?? '';

        if (!progress.contains('实施')) continue;

        DateTime? noticeDate;
        try {
          noticeDate = DateTime.parse(noticeDateStr.substring(0, 10));
        } catch (_) { continue; }

        if (noticeDate.isBefore(oneYearAgo)) break;

        final match = RegExp(r'10派([\d.]+)元').firstMatch(profile);
        if (match != null) {
          totalDps += _safeDouble(match.group(1)) / 10;
        }
      }

      if (totalDps > 0) {
        stock['dividend_yield'] = _round(totalDps / price * 100, 2);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
  
  /// 预筛选：应用除股息率外的所有筛选条件
  /// 用于在逐只查询股息率前减少待查股票数量
  List<Map<String, dynamic>> _applyFiltersExceptDividend(
    List<Map<String, dynamic>> stocks,
    FilterCriteria criteria,
  ) {
    // 创建一个不含股息率筛选的临时条件
    final tempCriteria = FilterCriteria(
      market: criteria.market,
      peRange: criteria.peRange,
      pbRange: criteria.pbRange,
      roeRange: criteria.roeRange,
      revenueGrowthRange: criteria.revenueGrowthRange,
      profitGrowthRange: criteria.profitGrowthRange,
      // dividendYieldRange 设为null
      marketCapLevel: criteria.marketCapLevel,
      floatMarketCapLevel: criteria.floatMarketCapLevel,
      minListingYears: criteria.minListingYears,
      turnoverRange: criteria.turnoverRange,
      pctFrom52WeekHigh: criteria.pctFrom52WeekHigh,
      changePctRange: criteria.changePctRange,
      volumeRange: criteria.volumeRange,
      foreignHolderFilter: criteria.foreignHolderFilter,
    );
    
    return _applyFilters(stocks, tempCriteria);
  }

  /// 港股：使用腾讯API获取热门港股数据
  Future<List<Map<String, dynamic>>> _fetchHKStockData(void Function(int, int)? onProgress) async {
    final result = <Map<String, dynamic>>[];
    
    // 港股热门股票代码（按行业分类，覆盖主要股票）
    final hkCodes = [
      // 科技互联网
      '00700', '09988', '09618', '03690', '01810', '09999', '09888', '09961', '02015', '09866',
      // 金融
      '01299', '02318', '03988', '01288', '00005', '00939', '02388', '02628', '01339', '00962',
      // 消费
      '02313', '02269', '02020', '01177', '01579', '06862', '06060', '01658', '01918', '01785',
      // 地产
      '01109', '00001', '00012', '00083', '00123', '00141', '00199', '00059', '00106', '00144',
      // 医药
      '02269', '01093', '01099', '01186', '02015', '02238', '02162', '02367', '02501', '02552',
      // 汽车
      '02333', '01733', '01211', '01755', '02338', '02015', '09868', '03818', '01958', '02018',
      // 能源公用
      '00857', '00386', '00941', '00358', '01072', '00364', '01898', '01088', '00883', '00669',
      // 工业
      '02608', '02382', '00316', '00347', '01065', '01053', '01357', '00392', '01243', '01071',
      // 物流贸易
      '01161', '01359', '00268', '00144', '00984', '01193', '00569', '00285', '00493', '00683',
      // 传媒娱乐
      '01060', '02498', '00112', '00410', '00551', '00867', '01610', '09922', '09923', '03888',
    ];
    
    onProgress?.call(1, 3);
    
    final hkNames = _getHKStockNames();
    
    try {
      // 分批获取数据，每批50只
      for (int i = 0; i < hkCodes.length; i += 50) {
        final batch = hkCodes.sublist(i, i + 50 > hkCodes.length ? hkCodes.length : i + 50);
        final codesParam = batch.map((c) => 'hk$c').join(',');
        
        try {
          final resp = await _client.get(
            Uri.parse('https://qt.gtimg.cn/q=$codesParam'),
            headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 12)'},
          ).timeout(const Duration(seconds: _timeoutSeconds));
          
          if (resp.statusCode != 200) continue;
          
          final text = await _decodeGbk(resp.bodyBytes);
          final lines = text.split(';');
          
          for (final line in lines) {
            if (line.isEmpty) continue;
            final match = RegExp(r'v_([a-z0-9]+)="([^"]*)"').firstMatch(line);
            if (match == null) continue;
            
            final code = match.group(1) ?? '';
            final val = match.group(2) ?? '';
            if (val.isEmpty) continue;
            
            final f = val.split('~');
            if (f.length < 50) continue;
            
            final codeNum = code.replaceAll('hk', '');
            final name = hkNames[codeNum] ?? f[1].trim();
            
            result.add({
              'symbol': codeNum,
              'code': codeNum,
              'name': name,
              'price': _safeDouble(f[4]),
              'change_pct': _safeDouble(f[33]),
              'pe': _safeDouble(f[40]),
              'pb': _safeDouble(f[47]),
              'mktcap': _safeDouble(f[44]) * 10000,
              'week52_high': _safeDouble(f[48]),
              'week52_low': _safeDouble(f[49]),
            });
          }
        } catch (e) {
          print('港股批次${i~/50}获取失败: $e');
        }
      }
      
      print('港股共获取${result.length}只股票');
    } catch (e) {
      print('港股数据获取错误: $e');
    }
    
    onProgress?.call(3, 3);
    return result;
  }

  /// 美股：使用腾讯API获取热门美股数据
  Future<List<Map<String, dynamic>>> _fetchUSStockData(void Function(int, int)? onProgress) async {
    final result = <Map<String, dynamic>>[];
    
    // 美股热门股票代码（按行业分类）
    final usCodes = [
      // 科技龙头
      'AAPL', 'MSFT', 'NVDA', 'GOOG', 'GOOGL', 'AMZN', 'META', 'TSLA', 'AVGO', 'ORCL',
      // 半导体
      'AMD', 'INTC', 'QCOM', 'TXN', 'MU', 'AMAT', 'LRCX', 'KLAC', 'NVDA', 'MRVL',
      // 软件
      'CRM', 'ADBE', 'NOW', 'INTU', 'SNOW', 'DDOG', 'MDB', 'ZS', 'CRWD', 'NET',
      // 金融
      'BRK.B', 'JPM', 'V', 'MA', 'BAC', 'WFC', 'GS', 'MS', 'BLK', 'SCHW',
      // 医疗
      'UNH', 'JNJ', 'LLY', 'PFE', 'MRK', 'ABBV', 'TMO', 'ABT', 'DHR', 'BMY',
      // 消费
      'WMT', 'COST', 'HD', 'NKE', 'MCD', 'SBUX', 'TGT', 'LOW', 'TJX', 'PG',
      // 工业
      'CAT', 'DE', 'HON', 'UPS', 'BA', 'RTX', 'LMT', 'GE', 'MMM', 'UNP',
      // 能源
      'XOM', 'CVX', 'COP', 'SLB', 'EOG', 'PSX', 'VLO', 'MPC', 'OXY', 'FANG',
      // 通信
      'VZ', 'T', 'TMUS', 'CMCSA', 'CHTR', 'T-Mobile', 'DISH', 'ATUS', 'CABO', 'LBRCE',
      // 中概股
      'BABA', 'JD', 'PDD', 'BIDU', 'NIO', 'BILI', 'TME', 'IQ', 'TAL', 'EDU',
      'FUTU', 'TIGR', 'XPEV', 'LI', 'ZK', 'MPNGY', 'BZ', 'YMM', 'DIDI', 'NTES',
      // 其他热门
      'NFLX', 'DIS', 'PYPL', 'SQ', 'COIN', 'RKLB', 'ASTR', 'SPCE', 'PLTR', 'SOFI',
    ];
    
    onProgress?.call(1, 3);
    
    final usNames = _getUSStockNames();
    
    try {
      // 分批获取数据，每批50只
      for (int i = 0; i < usCodes.length; i += 50) {
        final batch = usCodes.sublist(i, i + 50 > usCodes.length ? usCodes.length : i + 50);
        final codesParam = batch.map((c) => 'us$c').join(',');
        
        try {
          final resp = await _client.get(
            Uri.parse('https://qt.gtimg.cn/q=$codesParam'),
            headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 12)'},
          ).timeout(const Duration(seconds: _timeoutSeconds));
          
          if (resp.statusCode != 200) continue;
          
          final text = await _decodeGbk(resp.bodyBytes);
          final lines = text.split(';');
          
          for (final line in lines) {
            if (line.isEmpty) continue;
            final match = RegExp(r'v_([a-z0-9]+)="([^"]*)"').firstMatch(line);
            if (match == null) continue;
            
            final code = match.group(1) ?? '';
            final val = match.group(2) ?? '';
            if (val.isEmpty) continue;
            
            final f = val.split('~');
            if (f.length < 50) continue;
            
            final codeNum = code.replaceAll('us', '');
            final name = usNames[codeNum] ?? f[1].trim();
            
            result.add({
              'symbol': codeNum,
              'code': codeNum,
              'name': name,
              'price': _safeDouble(f[3]),
              'change_pct': _safeDouble(f[33]),
              'pe': _safeDouble(f[40]),
              'pb': _safeDouble(f[47]),
              'mktcap': _safeDouble(f[45]) * 10000,
            });
          }
        } catch (e) {
          print('美股批次${i~/50}获取失败: $e');
        }
      }
      
      print('美股共获取${result.length}只股票');
    } catch (e) {
      print('美股数据获取错误: $e');
    }
    
    onProgress?.call(3, 3);
    return result;
  }

  /// 应用筛选条件
  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> stocks,
    FilterCriteria criteria,
  ) {
    // 检查是否启用了任何筛选条件（包含新增的营收增速/净利润增速/股息率）
    final hasFilters = criteria.peRange != null ||
        criteria.pbRange != null ||
        criteria.roeRange != null ||
        criteria.revenueGrowthRange != null ||
        criteria.profitGrowthRange != null ||
        criteria.dividendYieldRange != null ||
        criteria.turnoverRange != null ||
        criteria.pctFrom52WeekHigh != null ||
        criteria.changePctRange != null ||
        criteria.volumeRange != null ||
        criteria.marketCapLevel != null ||
        (criteria.foreignHolderFilter != null && criteria.foreignHolderFilter!.hasFilter);
    
    if (!hasFilters) {
      // 没有筛选条件，返回所有股票（按市值排序）
      final sorted = List<Map<String, dynamic>>.from(stocks);
      sorted.sort((a, b) => _safeDouble(b['mktcap']).compareTo(_safeDouble(a['mktcap'])));
      for (var stock in sorted) {
        stock['filter_score'] = 50.0;
      }
      return sorted;
    }
    
    return stocks.where((stock) {
      double score = 50.0;
      
      // PE筛选
      if (criteria.peRange != null) {
        final pe = _safeDouble(stock['pe']);
        // PE必须大于0且在范围内
        if (pe <= 0) return false;
        if (pe < criteria.peRange!.start || pe > criteria.peRange!.end) return false;
        // PE越低得分越高
        if (pe < 15) score += 20;
        else if (pe < 30) score += 10;
        else if (pe < 50) score += 5;
      }
      
      // PB筛选
      if (criteria.pbRange != null) {
        final pb = _safeDouble(stock['pb']);
        if (pb <= 0) return false;
        if (pb < criteria.pbRange!.start || pb > criteria.pbRange!.end) return false;
        if (pb < 2) score += 10;
      }
      
      // ROE筛选
      if (criteria.roeRange != null) {
        final roe = _safeDouble(stock['roe']);
        // ROE为0说明无数据，如果用户要求ROE>0则过滤掉
        if (roe <= 0 && criteria.roeRange!.start > 0) return false;
        if (roe < criteria.roeRange!.start || roe > criteria.roeRange!.end) return false;
        if (roe > 15) score += 25;
        else if (roe > 10) score += 15;
      }
      
      // 营收增速筛选
      if (criteria.revenueGrowthRange != null) {
        final revGrowth = _safeDouble(stock['revenue_growth']);
        // 营收增速为0可能无数据，如果用户要求>0则过滤
        if (revGrowth == 0 && criteria.revenueGrowthRange!.start > 0) return false;
        if (revGrowth < criteria.revenueGrowthRange!.start || revGrowth > criteria.revenueGrowthRange!.end) return false;
        // 营收增速高加分
        if (revGrowth > 30) score += 20;
        else if (revGrowth > 15) score += 10;
        else if (revGrowth > 5) score += 5;
      }
      
      // 净利润增速筛选
      if (criteria.profitGrowthRange != null) {
        final profitGrowth = _safeDouble(stock['profit_growth']);
        if (profitGrowth == 0 && criteria.profitGrowthRange!.start > 0) return false;
        if (profitGrowth < criteria.profitGrowthRange!.start || profitGrowth > criteria.profitGrowthRange!.end) return false;
        if (profitGrowth > 20) score += 15;
        else if (profitGrowth > 10) score += 8;
      }
      
      // 股息率筛选
      if (criteria.dividendYieldRange != null) {
        final dividendYield = _safeDouble(stock['dividend_yield']);
        // 股息率为0可能无数据或无分红，如果用户要求>0则过滤
        if (dividendYield <= 0 && criteria.dividendYieldRange!.start > 0) return false;
        if (dividendYield < criteria.dividendYieldRange!.start || dividendYield > criteria.dividendYieldRange!.end) return false;
        // 高股息加分
        if (dividendYield > 4) score += 20;
        else if (dividendYield > 2) score += 10;
      }
      
      // 市值筛选
      if (criteria.marketCapLevel != null) {
        final mktcap = _safeDouble(stock['mktcap']) / 10000; // 万元转亿
        switch (criteria.marketCapLevel!) {
          case 'small':
            if (mktcap > 100) return false;
            score += 5;
            break;
          case 'mid':
            if (mktcap < 100 || mktcap > 500) return false;
            break;
          case 'large':
            if (mktcap < 500) return false;
            score += 10;
            break;
        }
      }
      
      // 换手率筛选
      if (criteria.turnoverRange != null) {
        final turnover = _safeDouble(stock['turnoverratio']);
        if (turnover < criteria.turnoverRange!.start || turnover > criteria.turnoverRange!.end) return false;
      }
      
      // 距52周高筛选
      if (criteria.pctFrom52WeekHigh != null) {
        final price = _safeDouble(stock['price']);
        final week52High = _safeDouble(stock['week52_high']);
        if (price > 0 && week52High > 0) {
          final pct = (week52High - price) / week52High * 100;
          if (pct < criteria.pctFrom52WeekHigh!.start || pct > criteria.pctFrom52WeekHigh!.end) return false;
          // 超跌股加分
          if (pct > 40) score += 15;
          else if (pct > 30) score += 10;
        }
      }
      
      // 涨跌幅筛选
      if (criteria.changePctRange != null) {
        final chg = _safeDouble(stock['change_pct']);
        if (chg < criteria.changePctRange!.start || chg > criteria.changePctRange!.end) return false;
      }
      
      // 成交量筛选（万手）
      if (criteria.volumeRange != null) {
        final volume = _safeDouble(stock['volume']) / 100; // 手转万手
        if (volume < criteria.volumeRange!.start || volume > criteria.volumeRange!.end) return false;
        // 成交量大加分
        if (volume > 100) score += 10;
        else if (volume > 50) score += 5;
      }
      
      // 外资持股筛选
      if (criteria.foreignHolderFilter != null && criteria.foreignHolderFilter!.hasFilter) {
        final foreignData = stock['foreign_holding'] as Map<String, dynamic>?;
        final foreignFilter = criteria.foreignHolderFilter!;
        
        // 只看有外资持股的股票
        if (foreignFilter.hasForeignHolder && foreignData == null) {
          return false;
        }
        
        final foreignRatio = _safeDouble(stock['foreign_ratio']);
        final foreignChange = _safeDouble(stock['foreign_change']);
        
        // 持股比例范围筛选
        if (foreignRatio < foreignFilter.minRatio || foreignRatio > foreignFilter.maxRatio) {
          return false;
        }
        
        // 持股变动范围筛选
        if (foreignChange < foreignFilter.minChangeRatio || foreignChange > foreignFilter.maxChangeRatio) {
          return false;
        }
        
        // 外资持股加分
        if (foreignRatio > 5) score += 20;
        else if (foreignRatio > 2) score += 15;
        else if (foreignRatio > 0.5) score += 10;
        
        // 增持加分
        if (foreignChange > 0.5) score += 15;
        else if (foreignChange > 0) score += 5;
      }
      
      stock['filter_score'] = score;
      return true;
    }).toList();
  }

  // ============ 工具方法 ============

  static Future<String> _decodeGbk(List<int> bytes) async {
    if (bytes.isEmpty) return '';
    try {
      if (_channelReady) {
        final result = await _codecChannel.invokeMethod<String>('decodeGbk', {'bytes': bytes});
        if (result != null && result.isNotEmpty) return result;
      }
    } catch (_) { _channelReady = false; }
    try { return utf8.decode(bytes); } catch (_) {}
    try { return String.fromCharCodes(bytes); } catch (_) {}
    return '';
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s = v.toString();
    if (s == '-' || s.isEmpty || s == '--') return 0.0;
    return double.tryParse(s) ?? 0.0;
  }
  
  double _round(double value, int places) {
    final mod = math.pow(10, places);
    return (value * mod).round() / mod;
  }

  /// 港股代码-中文名称映射
  Map<String, String> _getHKStockNames() {
    return {
      '00700': '腾讯控股', '09988': '阿里巴巴', '09618': '京东集团', '03690': '美团',
      '01810': '小米集团', '09999': '网易', '09888': '百度集团', '09961': '携程集团',
      '02015': '理想汽车', '09866': '蔚来', '01299': '友邦保险', '02318': '中国平安',
      '03988': '中国银行', '01288': '农业银行', '00005': '汇丰控股', '00939': '建设银行',
      '02388': '中银香港', '02628': '中国人寿', '01339': '中信证券', '00962': '中信建投',
      '02313': '申洲国际', '02269': '药明生物', '02020': '安踏体育', '01177': '中国生物制药',
      '01579': '颐海国际', '06862': '海底捞', '06060': '众安在线', '01658': '山东黄金',
      '01918': '融创中国', '01785': '希慎兴', '01109': '华润置地', '00001': '长和',
      '00012': '恒基地产', '00083': '信和置业', '00123': '越秀地产', '00141': '中国恒大',
      '00199': '德信中国', '00059': '天虹纺织', '00106': '中信资源', '00144': '招商局港口',
      '01093': '石药集团', '01099': '国药控股', '01186': '中国中药', '02238': '广汽集团',
      '02162': '康希诺生物', '02367': '复星医药', '02501': '先声药业', '02552': '亚盛医药',
      '02333': '长城汽车', '01733': '恒大汽车', '01211': '比亚迪股份', '01755': '吉利汽车',
      '02338': '潍柴动力', '09868': '小鹏汽车', '03818': '中通快递', '01958': '雅迪控股',
      '02018': '瑞声科技', '00857': '中国石油', '00386': '中国石化', '00941': '中国移动',
      '00358': '江西铜业', '01072': '东方电气', '00364': '紫金矿业', '01898': '中煤能源',
      '01088': '中国神华', '00883': '中海油', '00669': '长城汽车', '02608': '金山软件',
      '02382': '舜宇光学', '00316': '东方海外', '00347': '鞍钢股份', '01065': '天津创业环保',
      '01053': '重庆钢铁', '01357': '美图公司', '00392': '北京控股', '01243': '创维集团',
      '01071': '华电国际', '01161': '中通快递', '01359': '中国飞鹤', '00268': '金蝶国际',
      '00144': '招商局港口', '00984': '粤海投资', '01193': '华南城', '00569': '现代牧业',
      '00285': '比亚迪电子', '00493': '国美零售', '00683': '嘉里物流', '01060': '阿里巴巴',
      '02498': '快手', '00112': '恒生银行', '00410': 'SOHO中国', '00551': '裕元集团',
      '00867': '康师傅', '01610': '雅生活', '09922': '百度', '09923': '哔哩哔哩',
      '03888': '金山科技',
    };
  }

  /// 美股代码-中文名称映射
  Map<String, String> _getUSStockNames() {
    return {
      'AAPL': '苹果公司', 'MSFT': '微软', 'NVDA': '英伟达', 'GOOG': '谷歌',
      'GOOGL': '谷歌A', 'AMZN': '亚马逊', 'META': 'Meta', 'TSLA': '特斯拉',
      'AVGO': '博通', 'ORCL': '甲骨文', 'AMD': '超微半导体', 'INTC': '英特尔',
      'QCOM': '高通', 'TXN': '德州仪器', 'MU': '美光科技', 'AMAT': '应用材料',
      'LRCX': '泛林半导体', 'KLAC': '科磊', 'MRVL': '美满电子', 'CRM': '赛富时',
      'ADBE': 'Adobe', 'NOW': 'ServiceNow', 'INTU': 'Intuit', 'SNOW': 'Snowflake',
      'DDOG': 'Datadog', 'MDB': 'MongoDB', 'ZS': 'Zscaler', 'CRWD': 'CrowdStrike',
      'NET': 'Cloudflare', 'BRK.B': '伯克希尔B', 'JPM': '摩根大通', 'V': 'Visa',
      'MA': '万事达', 'BAC': '美国银行', 'WFC': '富国银行', 'GS': '高盛',
      'MS': '摩根士丹利', 'BLK': '贝莱德', 'SCHW': '嘉信理财', 'UNH': '联合健康',
      'JNJ': '强生', 'LLY': '礼来', 'PFE': '辉瑞', 'MRK': '默沙东',
      'ABBV': '艾伯维', 'TMO': '赛默飞', 'ABT': '雅培', 'DHR': '丹纳赫',
      'BMY': '百时美施贵宝', 'WMT': '沃尔玛', 'COST': '开市客', 'HD': '家得宝',
      'NKE': '耐克', 'MCD': '麦当劳', 'SBUX': '星巴克', 'TGT': '塔吉特',
      'LOW': '劳氏', 'TJX': 'TJX', 'PG': '宝洁', 'CAT': '卡特彼勒',
      'DE': '迪尔', 'HON': '霍尼韦尔', 'UPS': 'UPS快递', 'BA': '波音',
      'RTX': '雷神技术', 'LMT': '洛克希德马丁', 'GE': 'GE航天', 'MMM': '3M',
      'UNP': '联合太平洋', 'XOM': '埃克森美孚', 'CVX': '雪佛龙', 'COP': '康菲石油',
      'SLB': '斯伦贝谢', 'EOG': '依欧格', 'PSX': 'Phillips 66', 'VLO': '瓦莱罗',
      'MPC': 'Marathon', 'OXY': '西方石油', 'FANG': 'Diamondback', 'VZ': '威瑞森',
      'T': 'AT&T', 'TMUS': 'T-Mobile', 'CMCSA': '康卡斯特', 'CHTR': '特许通讯',
      'NFLX': '奈飞', 'DIS': '迪士尼', 'PYPL': 'PayPal', 'SQ': 'Block',
      'COIN': 'Coinbase', 'PLTR': 'Palantir', 'SOFI': 'SoFi', 'BABA': '阿里巴巴',
      'JD': '京东', 'PDD': '拼多多', 'BIDU': '百度', 'NIO': '蔚来',
      'BILI': '哔哩哔哩', 'TME': '腾讯音乐', 'IQ': '爱奇艺', 'TAL': '好未来',
      'EDU': '新东方', 'FUTU': '富途控股', 'TIGR': '老虎证券', 'XPEV': '小鹏汽车',
      'LI': '理想汽车', 'NTES': '网易', 'RKLB': 'Rocket Lab',
    };
  }
}
