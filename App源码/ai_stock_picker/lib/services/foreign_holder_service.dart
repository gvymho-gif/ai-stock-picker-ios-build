/// 外资持股数据服务
/// 获取QFII、外资银行、外资机构、北向资金等持股数据
/// 数据源：东方财富数据中心（沪深港通持股）

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class ForeignHolderService {
  static const int _timeoutSeconds = 30;
  static final http.Client _client = http.Client();

  /// 外资持股数据缓存（内存缓存，有效期5分钟）
  static Map<String, Map<String, dynamic>>? _cache;
  static DateTime? _cacheTime;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// 获取外资持股数据（全市场）
  /// 返回格式: {股票代码: {holders: [...], total_ratio: 总持股比例, change_ratio: 变动比例}}
  static Future<Map<String, Map<String, dynamic>>> fetchForeignHoldings({
    bool forceRefresh = false,
  }) async {
    // 检查缓存
    if (!forceRefresh && _cache != null && _cacheTime != null) {
      final elapsed = DateTime.now().difference(_cacheTime!);
      if (elapsed < _cacheExpiry) {
        print('外资持股: 使用缓存数据，${_cache!.length}只股票');
        return _cache!;
      }
    }

    final result = <String, Map<String, dynamic>>{};

    try {
      // 1. 获取最新交易日期
      final tradeDate = await _fetchLatestTradeDate();
      print('外资持股: 最新交易日期 $tradeDate');

      // 2. 获取北向资金持股数据（今日排行 + 5日排行）
      final northToday = await _fetchNorthboundData(tradeDate, '1');
      final north5Day = await _fetchNorthboundData(tradeDate, '5');

      // 合并北向资金数据
      for (final entry in northToday.entries) {
        final code = entry.key;
        final data = entry.value;
        final data5 = north5Day[code];

        result[code] = {
          'holders': [
            {
              'type': '北向资金',
              'name': '陆股通',
              'ratio': _safeDouble(data['ratio']),
              'change': _safeDouble(data['change']),
            },
          ],
          'total_ratio': _safeDouble(data['ratio']),
          'change_ratio': _safeDouble(data['change']),
          'change_5day': _safeDouble(data5?['change'] ?? 0),
          'trade_date': tradeDate,
        };
      }
      print('北向资金: 获取${northToday.length}只股票');

      // 3. 获取QFII/外资机构季度持股数据
      final qfiiData = await _fetchQFIIHoldings();
      for (final entry in qfiiData.entries) {
        final code = entry.key;
        final data = entry.value;
        if (!result.containsKey(code)) {
          result[code] = {
            'holders': [],
            'total_ratio': 0.0,
            'change_ratio': 0.0,
            'change_5day': 0.0,
            'trade_date': tradeDate,
          };
        }
        result[code]!['holders'].add({
          'type': data['type'] ?? 'QFII',
          'name': data['name'] ?? '',
          'ratio': _safeDouble(data['ratio']),
          'change': _safeDouble(data['change']),
        });
        result[code]!['total_ratio'] = (result[code]!['total_ratio'] as double) + _safeDouble(data['ratio']);
        result[code]!['change_ratio'] = (result[code]!['change_ratio'] as double) + _safeDouble(data['change']);
      }
      print('QFII/外资机构: 获取${qfiiData.length}只股票');

      // 更新缓存
      _cache = result;
      _cacheTime = DateTime.now();
      
      print('外资持股: 共${result.length}只股票有外资持股记录');
    } catch (e) {
      print('外资持股数据获取错误: $e');
    }

    return result;
  }

  /// 从东方财富页面获取最新交易日期
  static Future<String> _fetchLatestTradeDate() async {
    try {
      final resp = await _client.get(
        Uri.parse('https://data.eastmoney.com/hsgtcg/list.html'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final html = resp.body;
        // 匹配页面中的日期格式（YYYY-MM-DD）
        final dateMatch = RegExp(r'（(\d{4}-\d{2}-\d{2})）').firstMatch(html);
        if (dateMatch != null) {
          return dateMatch.group(1)!;
        }
      }
    } catch (e) {
      print('获取最新日期失败: $e');
    }
    // 回退：使用今天日期或空字符串（API会返回最新数据）
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 获取北向资金持股数据（东方财富数据中心）
  /// [tradeDate] 交易日期 YYYY-MM-DD
  /// [intervalType] "1"=今日, "3"=3日, "5"=5日, "10"=10日, "M"=月, "Q"=季
  static Future<Map<String, Map<String, dynamic>>> _fetchNorthboundData(
    String tradeDate,
    String intervalType,
  ) async {
    final result = <String, Map<String, dynamic>>{};

    try {
      final filterStr = '(TRADE_DATE=\'$tradeDate\')(INTERVAL_TYPE="$intervalType")';
      
      int page = 1;
      int totalPages = 1;
      
      while (page <= totalPages && page <= 5) {
        final url = 'https://datacenter-web.eastmoney.com/api/data/v1/get'
            '?reportName=RPT_MUTUAL_STOCK_NORTHSTA'
            '&columns=ALL'
            '&pageSize=5000'
            '&pageNumber=$page'
            '&sortTypes=-1'
            '&sortColumns=ADD_MARKET_CAP'
            '&source=WEB'
            '&client=WEB'
            '&filter=${Uri.encodeComponent(filterStr)}';

        final resp = await _client.get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
            'Accept': 'application/json',
            'Referer': 'https://data.eastmoney.com/',
          },
        ).timeout(const Duration(seconds: _timeoutSeconds));

        if (resp.statusCode != 200) {
          print('北向资金接口返回${resp.statusCode}');
          break;
        }

        final json = jsonDecode(resp.body);
        if (json['result'] == null || json['result']['data'] == null) {
          print('北向资金数据为空，日期=$tradeDate interval=$intervalType');
          break;
        }

        if (page == 1) {
          totalPages = json['result']['pages'] ?? 1;
        }

        final data = json['result']['data'] as List;
        for (final item in data) {
          final m = item as Map<String, dynamic>;
          final code = m['SECURITY_CODE']?.toString() ?? '';
          if (code.isEmpty) continue;

          final holdRatio = _safeDouble(m['HOLD_SHARES_RATIO']);
          final addSharesAmp = _safeDouble(m['ADD_SHARES_AMP']);
          final freeCapRatioChg = _safeDouble(m['FREECAP_RATIO_CHG']);

          result[code] = {
            'ratio': holdRatio,
            'change': addSharesAmp != 0 ? addSharesAmp : freeCapRatioChg,
            'add_shares': _safeDouble(m['ADD_SHARES_REPAIR']),
            'add_market_cap': _safeDouble(m['ADD_MARKET_CAP']),
            'total_ratio': _safeDouble(m['TOTAL_SHARES_RATIO']),
          };
        }
        
        page++;
        // 短暂延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      print('北向资金数据获取失败: $e');
    }

    return result;
  }

  /// 获取QFII/外资机构持股数据（新浪财经-机构持股）
  static Future<Map<String, Map<String, dynamic>>> _fetchQFIIHoldings() async {
    final result = <String, Map<String, dynamic>>{};

    try {
      // 计算最新季度参数（如 20261 = 2026年一季报）
      final now = DateTime.now();
      int year = now.year;
      int quarter;
      if (now.month <= 3) {
        quarter = 4; year -= 1; // 去年年报
      } else if (now.month <= 6) {
        quarter = 1; // 今年一季报
      } else if (now.month <= 9) {
        quarter = 2; // 今年中报
      } else {
        quarter = 3; // 今年三季报
      }
      final symbol = '$year$quarter';
      
      final url = 'https://vip.stock.finance.sina.com.cn/q/go.php/vComStockHold/kind/jgcg/index.phtml'
          '?p=1&num=10000&reportdate=$year&quarter=$quarter';

      final resp = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
          'Accept': 'text/html',
          'Referer': 'https://vip.stock.finance.sina.com.cn/',
        },
      ).timeout(const Duration(seconds: _timeoutSeconds));

      if (resp.statusCode != 200) {
        print('新浪机构持股接口返回${resp.statusCode}');
        return result;
      }

      // 解析HTML表格
      final html = resp.body;
      final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);
      
      for (final rowMatch in rows) {
        final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
            .allMatches(rowMatch.group(1)!)
            .map((m) => _stripHtml(m.group(1) ?? ''))
            .toList();
        
        if (cells.length >= 8) {
          final code = cells[0].trim();
          // 过滤外资类型
          final name = cells[1].trim();
          final instCount = _safeDouble(cells[2]);
          final instChange = _safeDouble(cells[3]);
          final holdRatio = _safeDouble(cells[4]);
          final holdChange = _safeDouble(cells[5]);
          final freeRatio = _safeDouble(cells[6]);
          final freeChange = _safeDouble(cells[7]);

          if (code.isEmpty || code.length != 6) continue;
          if (holdRatio <= 0) continue;

          result[code] = {
            'type': 'QFII/外资机构',
            'name': name,
            'ratio': freeRatio > 0 ? freeRatio : holdRatio,
            'change': freeChange != 0 ? freeChange : holdChange,
            'inst_count': instCount,
            'inst_change': instChange,
          };
        }
      }
    } catch (e) {
      print('QFII数据获取失败: $e');
    }

    return result;
  }

  /// 去除HTML标签
  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();
  }

  /// 获取单只股票的外资持股详情
  static Future<Map<String, dynamic>?> getStockForeignHolding(String code) async {
    try {
      final allData = await fetchForeignHoldings();
      return allData[code];
    } catch (e) {
      print('获取${code}外资持股失败: $e');
      return null;
    }
  }

  /// 获取北向/南向资金净流入额（实时）
  /// 数据源1：东方财富 push2 kamtbs.rtmin 分时数据接口
  /// 数据源2（回退）：东方财富 push2 kamt/get 日度汇总接口
  /// 返回: { 'north_net': 北向净流入(亿元), 'south_net': 南向净流入(亿元), 'north_available': 北向数据是否可用 }
  static Future<Map<String, dynamic>> fetchNorthSouthFlow() async {
    // 优先使用V2接口（支持北向成交总额）
    return fetchNorthSouthFlowV2();
  }

  /// 方案3：使用 kamt/get 接口获取北向成交总额
  /// 交易所2024年8月起停止盘中实时披露北向净流入，但当日成交总额(buySellAmt)仍有值
  /// 显示"北向成交 XXX.X亿"替代原来的"北向净流入"
  /// 返回: {
  ///   'north_net': 北向净流入(亿元, 不可用时为0),
  ///   'south_net': 南向净流入(亿元),
  ///   'north_available': 北向成交额数据是否可用,
  ///   'north_total_amount': 北向当日成交总额(亿元),
  ///   'north_is_total': true 表示显示的是成交总额而非净流入
  /// }
  static Future<Map<String, dynamic>> fetchNorthSouthFlowV2() async {
    double northNet = 0.0;
    double southNet = 0.0;
    double northTotalAmount = 0.0;
    bool northAvailable = false;

    try {
      final url = 'https://push2.eastmoney.com/api/qt/kamt/get'
          '?fields1=f1,f2,f3,f4,f5,f6,f7,f8'
          '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63,f64'
          '&ut=b2884a393a59ad64002292a3e90d46a5';

      final resp = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
          'Accept': '*/*',
          'Referer': 'https://data.eastmoney.com/',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final data = json['data'] as Map<String, dynamic>?;
        if (data != null) {
          // 北向资金 = hk2sh(沪股通) + hk2sz(深股通)
          final hk2sh = data['hk2sh'] as Map<String, dynamic>?;
          final hk2sz = data['hk2sz'] as Map<String, dynamic>?;

          if (hk2sh != null && hk2sz != null) {
            // 北向成交总额 = hk2sh.buySellAmt + hk2sz.buySellAmt (单位: 万元)
            final shBuySell = _safeDouble(hk2sh['buySellAmt']);
            final szBuySell = _safeDouble(hk2sz['buySellAmt']);
            northTotalAmount = (shBuySell + szBuySell) / 10000; // 万元→亿元

            // 北向净流入（目前为0，因为交易所不再披露）
            final shNetBuy = _safeDouble(hk2sh['netBuyAmt']);
            final szNetBuy = _safeDouble(hk2sz['netBuyAmt']);
            northNet = (shNetBuy + szNetBuy) / 10000; // 万元→亿元

            // 成交总额 > 0 则数据可用
            northAvailable = northTotalAmount > 0;
          }

          // 南向资金 = sh2hk(沪港通) + sz2hk(深港通)
          final sh2hk = data['sh2hk'] as Map<String, dynamic>?;
          final sz2hk = data['sz2hk'] as Map<String, dynamic>?;

          if (sh2hk != null && sz2hk != null) {
            final shNetBuy = _safeDouble(sh2hk['netBuyAmt']);
            final szNetBuy = _safeDouble(sz2hk['netBuyAmt']);
            southNet = (shNetBuy + szNetBuy) / 10000; // 万元→亿元
          }
        }
      }
    } catch (e) {
      print('kamt/get接口获取失败: $e');
    }

    print('南北向资金: 北向成交${northTotalAmount.toStringAsFixed(1)}亿(可用=$northAvailable) 北向净流入${northNet.toStringAsFixed(2)}亿 南向${southNet.toStringAsFixed(2)}亿');
    return {
      'north_net': northNet,
      'south_net': southNet,
      'north_available': northAvailable,
      'north_total_amount': northTotalAmount,
      'north_is_total': true, // 标记：北向显示的是成交总额
    };
  }

  /// 清除缓存
  static void clearCache() {
    _cache = null;
    _cacheTime = null;
  }

  static double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s = v.toString();
    if (s == '-' || s.isEmpty || s == '--') return 0.0;
    return double.tryParse(s) ?? 0.0;
  }
}

/// 外资类型枚举
enum ForeignHolderType {
  qfii('QFII', '合格境外机构投资者'),
  rqfii('RQFII', '人民币合格境外机构投资者'),
  foreignBank('外资银行', '外资银行'),
  foreignEnterprise('外资企业', '外资企业机构'),
  overseasFund('海外基金', '大型海外基金'),
  northbound('北向资金', '陆股通/沪深股通'),
  all('全部外资', '所有外资持股');

  final String code;
  final String label;
  const ForeignHolderType(this.code, this.label);
}

/// 外资持股筛选条件
class ForeignHolderFilter {
  /// 是否只看有外资持股的股票
  final bool hasForeignHolder;
  
  /// 外资类型筛选（null表示不限）
  final ForeignHolderType? holderType;
  
  /// 持股比例范围（0-100%）
  final double minRatio;
  final double maxRatio;
  
  /// 持股变动比例范围（-100% ~ 100%）
  final double minChangeRatio;
  final double maxChangeRatio;

  const ForeignHolderFilter({
    this.hasForeignHolder = false,
    this.holderType,
    this.minRatio = 0,
    this.maxRatio = 100,
    this.minChangeRatio = -100,
    this.maxChangeRatio = 100,
  });

  ForeignHolderFilter copyWith({
    bool? hasForeignHolder,
    ForeignHolderType? holderType,
    double? minRatio,
    double? maxRatio,
    double? minChangeRatio,
    double? maxChangeRatio,
    bool clearHolderType = false,
  }) {
    return ForeignHolderFilter(
      hasForeignHolder: hasForeignHolder ?? this.hasForeignHolder,
      holderType: clearHolderType ? null : (holderType ?? this.holderType),
      minRatio: minRatio ?? this.minRatio,
      maxRatio: maxRatio ?? this.maxRatio,
      minChangeRatio: minChangeRatio ?? this.minChangeRatio,
      maxChangeRatio: maxChangeRatio ?? this.maxChangeRatio,
    );
  }

  bool get hasFilter => hasForeignHolder || holderType != null;

  String get description {
    if (!hasFilter) return '';
    final parts = <String>[];
    if (hasForeignHolder) parts.add('外资持股');
    if (holderType != null && holderType != ForeignHolderType.all) {
      parts.add(holderType!.label);
    }
    if (minRatio > 0 || maxRatio < 100) {
      parts.add('持股${minRatio.toStringAsFixed(1)}-${maxRatio.toStringAsFixed(1)}%');
    }
    if (minChangeRatio > -100 || maxChangeRatio < 100) {
      if (minChangeRatio >= 0) {
        parts.add('增持≥${minChangeRatio.toStringAsFixed(1)}%');
      } else if (maxChangeRatio <= 0) {
        parts.add('减持≤${maxChangeRatio.toStringAsFixed(1)}%');
      }
    }
    return parts.join(' · ');
  }
}
