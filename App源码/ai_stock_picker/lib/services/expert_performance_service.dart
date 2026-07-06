/// 收益统计服务
///
/// 追踪"A股游资"与"隔夜导航"两大专家选股板块的即时获利能力
/// 每日循环：20:00创建新记录（锁定6只+起始价）→ 次日19:00结算 → 20:00新一轮
/// 有效期：创建日20:00 ~ 次日19:00

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/expert_stock_service.dart';
import '../services/local_data_service.dart';
import 'backup_service.dart';
import 'trading_day_cloud_service.dart';
import '../models/trading_day_record.dart';
import '../utils/trading_day_utils.dart';

class DailyExpertPerformance {
  String date; // 交易日期 YYYY-MM-DD
  List<StockPerformance> stocks; // 6只股票表现
  double dailyAvgChange; // 当日平均涨跌幅
  int upCount; // 上涨数量
  int downCount; // 下跌数量
  bool isSettled; // 是否已结算

  DailyExpertPerformance({
    required this.date,
    required this.stocks,
    this.dailyAvgChange = 0.0,
    this.upCount = 0,
    this.downCount = 0,
    this.isSettled = false,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'stocks': stocks.map((s) => s.toJson()).toList(),
        'dailyAvgChange': dailyAvgChange,
        'upCount': upCount,
        'downCount': downCount,
        'isSettled': isSettled,
      };

  factory DailyExpertPerformance.fromJson(Map<String, dynamic> json) {
    final stocksList = (json['stocks'] as List)
        .map((s) => StockPerformance.fromJson(s))
        .toList();
    return DailyExpertPerformance(
      date: json['date'],
      stocks: stocksList,
      dailyAvgChange: json['dailyAvgChange']?.toDouble() ?? 0.0,
      upCount: json['upCount'] ?? 0,
      downCount: json['downCount'] ?? 0,
      isSettled: json['isSettled'] ?? false,
    );
  }
}

/// 单只股票表现
class StockPerformance {
  final String name; // 股票名称
  String code; // 股票代码（格式：600000.SS / 000001.SZ），可被修正
  final double startPrice; // T日20:00起始价
  double settlementPrice; // T+1日15:05结算价
  double changePercent; // 涨跌幅
  String strategy; // 来源策略（A股游资 / 隔夜导航）

  StockPerformance({
    required this.name,
    required this.code,
    required this.startPrice,
    this.settlementPrice = 0.0,
    this.changePercent = 0.0,
    this.strategy = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'code': code,
        'startPrice': startPrice,
        'settlementPrice': settlementPrice,
        'changePercent': changePercent,
        'strategy': strategy,
      };

  factory StockPerformance.fromJson(Map<String, dynamic> json) =>
      StockPerformance(
        name: json['name'],
        code: json['code'],
        startPrice: json['startPrice']?.toDouble() ?? 0.0,
        settlementPrice: json['settlementPrice']?.toDouble() ?? 0.0,
        changePercent: json['changePercent']?.toDouble() ?? 0.0,
        strategy: json['strategy']?.toString() ?? '',
      );
}

class ExpertPerformanceService {
  static const String _storageKey = 'expert_performance_history';
  static const String _lastUpdateKey = 'expert_performance_last_update';
  static const String _kGiteeTokenKey = 'gitee_token';
  static const String _kGiteeRepoKey = 'gitee_repo_name';

  /// 获取专家选股收益历史记录
  /// ★ 自动过滤并清理非交易日（周末+节假日）的脏数据
  static Future<List<DailyExpertPerformance>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final allRecords = jsonList.map((json) => DailyExpertPerformance.fromJson(json)).toList();

      // ★ 源头清理：过滤掉非交易日记录，并持久化清理结果
      final cleanRecords = allRecords
          .where((r) => !TradingDayUtils.isNonTradingDayStr(r.date))
          .toList();

      // 如果有脏数据被清理，写回干净的数据
      if (cleanRecords.length != allRecords.length) {
        final removedDates = allRecords
            .where((r) => TradingDayUtils.isNonTradingDayStr(r.date))
            .map((r) => r.date)
            .toList();
        print('[收益统计] 清理非交易日脏数据: $removedDates');
        await prefs.setString(
          _storageKey,
          jsonEncode(cleanRecords.map((r) => r.toJson()).toList()),
        );
      }

      return cleanRecords;
    } catch (e) {
      return [];
    }
  }

  /// 从百度云服务器同步收益统计历史数据
  /// 拉取云端 performance.json 并合并到本地 SharedPreferences
  /// [forceAll] = true 时覆盖本地同日期数据，false 时只补充缺失日期
  static Future<int> syncPerformanceFromCloud({bool forceAll = false}) async {
    try {
      // 读取服务器配置
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('server_url');
      final token = prefs.getString('server_token');
      if (serverUrl == null || serverUrl.isEmpty || token == null || token.isEmpty) {
        return 0;
      }

      final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final url = Uri.parse('$baseUrl/api/portfolio/performance');

      final response = await http.Client().get(url, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return 0;

      final body = json.decode(utf8.decode(response.bodyBytes));
      List<dynamic>? cloudList;
      if (body is Map) {
        final data = body['data'];
        if (data is List) {
          cloudList = data;
        } else if (data is Map) {
          final innerData = data['data'];
          if (innerData is List) cloudList = innerData;
        }
      }

      if (cloudList == null || cloudList.isEmpty) return 0;

      // 读本地已有
      final historyJson = prefs.getString(_storageKey);
      final List<dynamic> localList = historyJson != null && historyJson.isNotEmpty
          ? jsonDecode(historyJson)
          : [];
      final existingDates = localList.map((j) => j['date'].toString()).toSet();
      int newCount = 0;

      for (var item in cloudList) {
        if (item is! Map) continue;
        final date = item['date']?.toString();
        if (date == null || date.isEmpty) continue;
        if (item['stocks'] == null) continue;
        if (existingDates.contains(date) && !forceAll) continue;

        final Map<String, dynamic> record = Map<String, dynamic>.from(item);
        if (!record.containsKey('isSettled')) record['isSettled'] = true;

        if (existingDates.contains(date)) {
          localList.removeWhere((j) => j['date'] == date);
        }
        localList.add(record);
        newCount++;
      }

      if (newCount > 0) {
        localList.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
        await prefs.setString(_storageKey, jsonEncode(localList));
        await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
        print('[收益统计] 云端同步: 新增 $newCount 天记录');
      }
      return newCount;
    } catch (e) {
      print('[收益统计] 云端同步异常: $e');
      return -1;
    }
  }

  /// 保存当日收益记录
  static Future<void> saveDailyRecord(DailyExpertPerformance record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await getHistory();

      // 检查是否已存在该日期的记录
      history.removeWhere((r) => r.date == record.date);
      history.add(record);

      // 按日期排序（最新的在前面）
      history.sort((a, b) => b.date.compareTo(a.date));

      // 最多保存90天数据
      if (history.length > 90) {
        history.removeRange(90, history.length);
      }

      await prefs.setString(
        _storageKey,
        jsonEncode(history.map((r) => r.toJson()).toList()),
      );

      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());
    } catch (e) {
      print('保存专家选股收益记录失败: $e');
    }
  }

  /// 获取累计平均收益率（周期统计）
  static double getCumulativeReturn(List<DailyExpertPerformance> history) {
    if (history.isEmpty) return 0.0;

    double totalChange = 0;
    int settledCount = 0;
    for (var record in history) {
      if (record.isSettled) {
        totalChange += record.dailyAvgChange;
        settledCount++;
      }
    }

    if (settledCount == 0) return 0.0;
    return totalChange / settledCount;
  }

  /// 检查今天是否是交易日（简化版，实际应该调用API）
  static bool isTradingDay() {
    final now = DateTime.now();
    // 使用统一的交易日工具：排除周末 + 排除A股节假日
    return TradingDayUtils.isSecuritiesTradingDay(now);
  }

  /// 获取今天的日期字符串
  static String getTodayString() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd').format(now);
  }

  /// 获取昨天的日期字符串
  static String getYesterdayString() {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    return DateFormat('yyyy-MM-dd').format(yesterday);
  }

  /// 将code转换为标准格式 (如 600000.SS / 000001.SZ)
  /// 兼容多种输入格式：纯数字、sh600000、600000.SH、600000.SS 等
  static String _normalizeCode(String code, String symbol) {
    // 提取纯数字部分
    String numCode = code;
    String exchSuffix = '';

    if (code.contains('.')) {
      final parts = code.split('.');
      numCode = parts[0];
      exchSuffix = parts[1].toUpperCase();
    } else if (code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj')) {
      // 格式如 sh600000
      final prefix = code.substring(0, 2).toLowerCase();
      numCode = code.substring(2);
      exchSuffix = prefix == 'sh' ? 'SS' : prefix == 'sz' ? 'SZ' : 'BJ';
    }

    // 如果已有明确的后缀，直接使用（统一转为项目格式）
    if (exchSuffix == 'SS' || exchSuffix == 'SH') return '$numCode.SS';
    if (exchSuffix == 'SZ') return '$numCode.SZ';
    if (exchSuffix == 'BJ') return '$numCode.BJ';

    // 从symbol推断交易所后缀
    final symLower = symbol.toLowerCase();
    if (symLower.startsWith('sh')) {
      return '$numCode.SS';
    } else if (symLower.startsWith('sz')) {
      return '$numCode.SZ';
    } else if (symLower.startsWith('bj')) {
      return '$numCode.BJ';
    }

    // 如果symbol为空，用代码首位推断
    // 6开头=上交所(SS)，0/3开头=深交所(SZ)，8/4开头=北交所(BJ)
    if (numCode.startsWith('6')) {
      return '$numCode.SS';
    } else if (numCode.startsWith('0') || numCode.startsWith('3')) {
      return '$numCode.SZ';
    } else if (numCode.startsWith('8') || numCode.startsWith('4')) {
      return '$numCode.BJ';
    }

    // 兜底：默认SS
    return '$numCode.SS';
  }

  /// 自动获取今日选股并保存起始价（每晚20:00调用，次日19:00结算）
  static Future<bool> autoCreateTodayRecord() async {
    try {
      if (!isTradingDay()) {
        print('今天不是交易日，跳过');
        return false;
      }

      final today = getTodayString();

      // 检查今天是否已有记录
      final history = await getHistory();
      if (history.any((r) => r.date == today)) {
        print('今天已有记录，跳过');
        return false;
      }

      // 获取"A股游资"选股结果
      final hotMoneyService = ExpertStockService();
      print('[专家收益] 开始获取A股游资选股...');
      final hotMoneyResult = await hotMoneyService.runSpeedAssassin();
      final hotMoneyStocks = _extractTop3Stocks(hotMoneyResult, 'A股游资');
      print('[专家收益] A股游资获取到 ${hotMoneyStocks.length} 只股票');

      // 获取"隔夜导航"选股结果
      print('[专家收益] 开始获取隔夜导航选股...');
      final overnightResult = await hotMoneyService.runOvernightNavigator();
      final overnightStocks = _extractTop3Stocks(overnightResult, '隔夜导航');
      print('[专家收益] 隔夜导航获取到 ${overnightStocks.length} 只股票');

      if (hotMoneyStocks.isEmpty && overnightStocks.isEmpty) {
        print('[专家收益] 未获取到任何选股结果');
        return false;
      }

      // 合并6只股票（标记来源策略）
      final allStocks = <Map<String, dynamic>>[
        ...hotMoneyStocks.map((s) { s['strategy_tag'] = 'A股游资'; return s; }),
        ...overnightStocks.map((s) { s['strategy_tag'] = '隔夜导航'; return s; }),
      ];

      // 获取起始价（当前价格）
      final api = LocalDataService();
      final stocks = <StockPerformance>[];

      for (var stockData in allStocks) {
        final rawCode = stockData['code']?.toString() ?? '';
        final symbol = stockData['symbol']?.toString() ?? '';
        final name = stockData['name']?.toString() ?? '';
        final strategyTag = stockData['strategy_tag']?.toString() ?? '';

        if (rawCode.isEmpty) continue;

        // 标准化代码格式
        final code = _normalizeCode(rawCode, symbol);
        print('[专家收益] 获取价格: $name($code), rawCode=$rawCode, symbol=$symbol, strategy=$strategyTag');

        // 获取实时价格
        try {
          final price = await api.getPrice(code);
          if (price > 0) {
            stocks.add(StockPerformance(
              name: name,
              code: code,
              startPrice: price,
              strategy: strategyTag,
            ));
            print('[专家收益] $name($code) 起始价=$price');
          } else {
            print('[专家收益] $name($code) 价格为0，跳过');
          }
        } catch (e) {
          print('[专家收益] 获取 $name($code) 价格失败: $e');
        }
      }

      if (stocks.isEmpty) {
        print('[专家收益] 未成功获取任何股票价格');
        return false;
      }

      // 保存记录（未结算）
      final record = DailyExpertPerformance(
        date: today,
        stocks: stocks,
        isSettled: false,
      );

      await saveDailyRecord(record);
      print('[专家收益] 成功创建今日记录: $today, 股票数: ${stocks.length}');
      // 创建成功后自动备份
      autoBackup();
      return true;
    } catch (e) {
      print('[专家收益] 自动创建今日记录失败: $e');
      return false;
    }
  }

  /// 删除今日记录（用于强制刷新）
  static Future<bool> deleteTodayRecord() async {
    try {
      final today = getTodayString();
      final history = await getHistory();
      final hadRecord = history.any((r) => r.date == today);
      if (!hadRecord) return false;

      history.removeWhere((r) => r.date == today);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(history.map((r) => r.toJson()).toList()),
      );
      print('[专家收益] 已删除今日记录: $today');
      return true;
    } catch (e) {
      print('[专家收益] 删除今日记录失败: $e');
      return false;
    }
  }

  /// 强制重建今日记录（删除旧记录 → 重新获取选股 → 保存新记录）
  static Future<bool> forceRecreateTodayRecord() async {
    try {
      // 先删除今日旧记录
      await deleteTodayRecord();
      // 重新创建
      return await autoCreateTodayRecord();
    } catch (e) {
      print('[专家收益] 强制重建今日记录失败: $e');
      return false;
    }
  }

  /// 自动结算未结算的记录（结算所有未结算或"假结算"的非今天记录）
  /// "假结算"指 isSettled=true 但所有股票的 changePercent=0（旧版BUG导致）
  /// 19:30前昨天的记录允许重新结算（API收盘数据可能需要时间更新）
  /// ⚠️ 今天新创建的记录：不处理（还没到收盘时间）
  static Future<bool> autoSettleYesterdayRecord() async {
    try {
      // ★ 非交易日不结算
      if (!isTradingDay()) {
        print('[专家收益] 非交易日，跳过结算');
        return false;
      }

      // 获取历史记录，查找所有需要结算的记录
      final history = await getHistory();
      final today = getTodayString();
      final yesterday = getYesterdayString();
      final now = DateTime.now();
      final isBeforeSettlementDeadline = now.hour < 19 || (now.hour == 19 && now.minute < 30);

      final needSettleRecords = history.where((r) {
        if (r.date == today) {
          // 今天的记录：不处理（新创建的记录，还没到收盘）
          return false;
        }
        if (r.date == yesterday) {
          // 昨天的记录：19:30前允许重新结算
          return isBeforeSettlementDeadline;
        }
        // 更早的记录
        if (!r.isSettled) return true; // 未结算
        // 已结算但涨跌幅全为0 → 假结算，需要重新结算
        if (r.stocks.every((s) => s.changePercent == 0)) return true;
        return false;
      }).toList();

      if (needSettleRecords.isEmpty) {
        print('[专家收益] 未找到需要结算的记录');
        return false;
      }

      print('[专家收益] 发现 ${needSettleRecords.length} 条需要结算的记录');

      // 结算所有需要结算的记录
      final api = LocalDataService();
      bool anySettled = false;

      for (var record in needSettleRecords) {
        double totalChange = 0;
        int upCount = 0;
        int downCount = 0;
        int successCount = 0;

        for (var stock in record.stocks) {
          try {
            // 使用 searchStock 获取完整行情数据，直接用API返回的涨跌幅
            // 避免因 startPrice 与昨收价不一致导致涨跌幅与实际不符
            final stockData = await api.searchStock(stock.code);
            if (stockData.isNotEmpty) {
              final currentPrice = _safeDoubleVal(stockData['price']);
              final changePct = _safeDoubleVal(stockData['change_pct']);

              if (currentPrice > 0 && stock.startPrice > 0) {
                stock.settlementPrice = currentPrice;
                // 优先使用API直接返回的涨跌幅（基于昨收价计算，与盘中显示一致）
                // 仅在API未返回涨跌幅时才用 startPrice 自行计算
                if (changePct != 0) {
                  stock.changePercent = changePct;
                } else {
                  stock.changePercent =
                      (currentPrice - stock.startPrice) / stock.startPrice * 100;
                }
                totalChange += stock.changePercent;
                if (stock.changePercent > 0) {
                  upCount++;
                } else if (stock.changePercent < 0) {
                  downCount++;
                }
                successCount++;
              } else {
                totalChange += 0;
                print('[专家收益] ${stock.name}(${stock.code}) 价格异常: 现价=$currentPrice, 起始价=${stock.startPrice}');
              }
            } else {
              totalChange += 0;
              print('[专家收益] ${stock.name}(${stock.code}) 获取行情数据失败');
            }
          } catch (e) {
            totalChange += 0;
            print('[专家收益] 获取 ${stock.name}(${stock.code}) 结算价失败: $e');
          }
        }

        if (successCount > 0 && record.stocks.isNotEmpty) {
          // 平均收益率 = 6只股票涨跌幅之和 / 6（失败的股票算0%）
          record.dailyAvgChange = totalChange / record.stocks.length;
          record.upCount = upCount;
          record.downCount = downCount;
          record.isSettled = true;
          await saveDailyRecord(record);
          anySettled = true;
          print('[专家收益] 成功结算记录: ${record.date}, 平均涨跌: ${record.dailyAvgChange.toStringAsFixed(2)}%, 成功: $successCount/${record.stocks.length}');

          // ★ 同步更新交易日记录（结算时用API最新数据更新）
          try {
            final existingRecords = await TradingDayCloudService.getLocalRecords();
            TradingDayRecord? existingTrading;
            for (var r in existingRecords) {
              if (r.date == record.date) { existingTrading = r; break; }
            }
            
            final codes = record.stocks.map((s) => s.code).toList();
            final names = record.stocks.map((s) => s.name).toList();
            final changes = record.stocks.map((s) => s.changePercent).toList();
            
            if (existingTrading == null) {
              // 没有该日期的交易日记录 → 创建新记录
              final tradingRecord = TradingDayRecord(
                date: record.date,
                stockCodes: codes,
                stockNames: names,
                stockChanges: changes,
                totalChangePercent: record.dailyAvgChange * record.stocks.length,
                avgChangePercent: record.dailyAvgChange,
                notes: '自动结算同步',
              );
              await TradingDayCloudService.addRecord(tradingRecord);
              print('[专家收益] 交易日记录已创建: ${record.date}');
            } else {
              // 已有记录 → 用结算结果更新涨跌数据，保留用户AI点评
              final updatedTrading = TradingDayRecord(
                date: existingTrading.date,
                stockCodes: codes.isNotEmpty ? codes : existingTrading.stockCodes,
                stockNames: names.isNotEmpty ? names : existingTrading.stockNames,
                stockChanges: changes.isNotEmpty ? changes : existingTrading.stockChanges,
                totalChangePercent: record.dailyAvgChange * record.stocks.length,
                avgChangePercent: record.dailyAvgChange,
                notes: existingTrading.notes,
                reviewContent: existingTrading.reviewContent,
                reviewGeneratedAt: existingTrading.reviewGeneratedAt,
              );
              await TradingDayCloudService.addRecord(updatedTrading);
              print('[专家收益] 交易日记录已同步更新: ${record.date}');
            }
          } catch (e) {
            print('[专家收益] 交易日记录同步失败: $e');
          }

          // 结算成功后自动备份
          autoBackup();
        } else {
          print('[专家收益] ${record.date} 所有股票价格获取失败，暂不结算');
        }
      }

      return anySettled;
    } catch (e) {
      print('[专家收益] 自动结算记录失败: $e');
      return false;
    }
  }

  /// 从ExpertStockService返回结果中提取前3名股票
  /// 会标记来源策略，方便排查
  static List<Map<String, dynamic>> _extractTop3Stocks(
    Map<String, dynamic> result,
    String strategyName,
  ) {
    try {
      final stocks = result['stocks'] as List?;
      if (stocks == null || stocks.isEmpty) {
        final error = result['error']?.toString() ?? '';
        print('[专家收益] $strategyName 返回空列表, error=$error');
        return [];
      }

      print('[专家收益] $strategyName 返回 ${stocks.length} 只股票');

      // 取前3名
      final top3 = stocks.take(3).toList();
      final result2 = top3.cast<Map<String, dynamic>>();

      // 打印提取的股票信息用于调试
      for (var s in result2) {
        final name = s['name']?.toString() ?? '';
        final code = s['code']?.toString() ?? '';
        final symbol = s['symbol']?.toString() ?? '';
        print('[专家收益] $strategyName Top3: $name code=$code symbol=$symbol');
      }

      return result2;
    } catch (e) {
      print('[专家收益] 提取 $strategyName 股票列表失败: $e');
      return [];
    }
  }

  /// 自动备份（结算或创建记录后调用）
  /// 同时备份到 Gitee（如果已配置 Token）和本地文件
  /// 使用合并格式（version 2），包含收益统计+交易日记录
  static Future<void> autoBackup() async {
    try {
      final history = await getHistory();
      if (history.isEmpty) return;

      // 构建合并备份（version 2格式）
      final json = await _buildCombinedBackupJson(history);

      // 1. 备份到 Gitee（使用完整路径 用户名/仓库名）
      final token = await getGiteeToken();
      if (token != null && token.isNotEmpty) {
        final repo = await BackupService.getFullRepoPath();
        if (repo != null) {
          await BackupService.backupToGitee(token, repo, json);
        } else {
          print('[专家收益] 获取 Gitee 仓库路径失败（Token 无效或网络异常）');
        }
      }

      // 2. 备份到本地文件
      await BackupService.exportToLocal(json);
      print('[专家收益] 自动备份完成');
    } catch (e) {
      print('[专家收益] 自动备份失败: $e');
    }
  }

  /// 构建合并备份JSON（包含收益统计+交易日记录）
  static Future<String> _buildCombinedBackupJson(List<DailyExpertPerformance> history) async {
    // 获取交易日记录
    List<Map<String, dynamic>> tradingJsonList = [];
    try {
      final tradingRecords = await TradingDayCloudService.getLocalRecords();
      tradingJsonList = tradingRecords.map((r) => r.toJson()).toList();
    } catch (e) {
      print('[专家收益] 获取交易日记录失败: $e');
    }

    final data = {
      'version': 2,
      'backupTime': DateTime.now().toIso8601String(),
      'expertPerformanceCount': history.length,
      'tradingDayCount': tradingJsonList.length,
      'expertPerformance': history.map((r) => r.toJson()).toList(),
      'tradingDayRecords': tradingJsonList,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 构建备份 JSON（公开方法，供 widget 调用）
  static String buildBackupJson(List<DailyExpertPerformance> history) {
    final data = {
      'version': 1,
      'backupTime': DateTime.now().toIso8601String(),
      'recordCount': history.length,
      'history': history.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 从备份 JSON 恢复历史记录
  /// 兼容 version 1（history字段）和 version 2（expertPerformance字段）
  static Future<bool> restoreFromBackupJson(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr);
      List<dynamic>? historyList;
      if (data is Map) {
        // version 2 格式：expertPerformance
        if (data['expertPerformance'] is List) {
          historyList = data['expertPerformance'] as List<dynamic>;
        }
        // version 1 格式：history
        else if (data['history'] is List) {
          historyList = data['history'] as List<dynamic>;
        }
      } else if (data is List) {
        historyList = data;
      }
      if (historyList == null || historyList.isEmpty) return false;

      final history = historyList.map((j) => DailyExpertPerformance.fromJson(j)).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(history.map((r) => r.toJson()).toList()),
      );
      print('[专家收益] 从备份恢复成功，记录数: ${history.length}');
      return true;
    } catch (e) {
      print('[专家收益] 从备份恢复失败: $e');
      return false;
    }
  }

  /// 安全转 double
  static double _safeDoubleVal(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  /// 获取 Gitee Token（从 SharedPreferences）
  static Future<String?> getGiteeToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGiteeTokenKey);
  }

  /// 获取仓库名
  static Future<String> getRepoName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGiteeRepoKey) ?? 'ai-stock-picker-backup';
  }

  /// 保存 Gitee Token
  static Future<void> saveGiteeToken(String token, {String repoName = 'ai-stock-picker-backup'}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGiteeTokenKey, token);
    await prefs.setString(_kGiteeRepoKey, repoName);
  }

  // ===================== 沪深300指数数据 =====================

  /// 获取沪深300日K涨跌幅数据
  /// 返回 Map<日期字符串(YYYY-MM-DD), 涨跌幅百分比>
  /// 数据源：新浪财经日K线 → 东方财富 fallback
  static Future<Map<String, double>> fetchHS300DailyChanges() async {
    final result = <String, double>{};
    // 主源：新浪财经
    try {
      final client = http.Client();
      try {
        final url = 'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=sh000300&scale=240&ma=no&datalen=200';
        final resp = await client.get(Uri.parse(url),
          headers: {'Referer': 'https://finance.sina.com.cn', 'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body.trimLeft().startsWith('[')) {
          final List<dynamic> klines = jsonDecode(resp.body) as List;
          klines.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
          String? prevCloseStr;
          for (final k in klines) {
            final day = k['day'] as String;
            final close = double.tryParse(k['close'].toString()) ?? 0;
            if (prevCloseStr != null) {
              final prevClose = double.tryParse(prevCloseStr) ?? 0;
              if (prevClose > 0 && close > 0) {
                result[day] = (close - prevClose) / prevClose * 100;
              }
            }
            prevCloseStr = k['close'].toString();
          }
          if (result.isNotEmpty) {
            debugPrint('[指数数据] 沪深300新浪源: ${result.length}条');
            return result;
          }
        } else {
          debugPrint('[指数数据] 沪深300新浪源异常: status=${resp.statusCode}, body=${resp.body.substring(0, 50)}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[指数数据] 沪深300新浪源失败: $e');
    }
    // 备用源：东方财富
    if (result.isEmpty) {
      try {
        result.addAll(await _fetchIndexDailyChangesEastMoney('1.000300'));
        if (result.isNotEmpty) debugPrint('[指数数据] 沪深300东方财富fallback: ${result.length}条');
      } catch (e) {
        debugPrint('[指数数据] 沪深300东方财富fallback失败: $e');
      }
    }
    return result;
  }

  // ===================== 中证1000指数数据 =====================

  /// 获取中证1000日K涨跌幅数据
  /// 返回 Map<日期字符串(YYYY-MM-DD), 涨跌幅百分比>
  /// 数据源：新浪财经日K线 → 东方财富 fallback
  static Future<Map<String, double>> fetchZZ1000DailyChanges() async {
    final result = <String, double>{};
    // 主源：新浪财经
    try {
      final client = http.Client();
      try {
        final url = 'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=sh000852&scale=240&ma=no&datalen=200';
        final resp = await client.get(Uri.parse(url),
          headers: {'Referer': 'https://finance.sina.com.cn', 'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body.trimLeft().startsWith('[')) {
          final List<dynamic> klines = jsonDecode(resp.body) as List;
          klines.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
          String? prevCloseStr;
          for (final k in klines) {
            final day = k['day'] as String;
            final close = double.tryParse(k['close'].toString()) ?? 0;
            if (prevCloseStr != null) {
              final prevClose = double.tryParse(prevCloseStr) ?? 0;
              if (prevClose > 0 && close > 0) {
                result[day] = (close - prevClose) / prevClose * 100;
              }
            }
            prevCloseStr = k['close'].toString();
          }
          if (result.isNotEmpty) {
            debugPrint('[指数数据] 中证1000新浪源: ${result.length}条');
            return result;
          }
        } else {
          debugPrint('[指数数据] 中证1000新浪源异常: status=${resp.statusCode}, body=${resp.body.substring(0, 50)}');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[指数数据] 中证1000新浪源失败: $e');
    }
    // 备用源：东方财富
    if (result.isEmpty) {
      try {
        result.addAll(await _fetchIndexDailyChangesEastMoney('1.000852'));
        if (result.isNotEmpty) debugPrint('[指数数据] 中证1000东方财富fallback: ${result.length}条');
      } catch (e) {
        debugPrint('[指数数据] 中证1000东方财富fallback失败: $e');
      }
    }
    return result;
  }

  /// 东方财富指数日K fallback
  /// secid格式: '1.000300'(沪深300), '1.000852'(中证1000)
  static Future<Map<String, double>> _fetchIndexDailyChangesEastMoney(String secid) async {
    final result = <String, double>{};
    final client = http.Client();
    try {
      // 东方财富日K线API
      final url = 'https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=$secid&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61&klt=101&fqt=1&beg=20250801&end=20500101&lmt=200';
      final resp = await client.get(Uri.parse(url),
        headers: {'Referer': 'https://quote.eastmoney.com', 'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200 || resp.body.isEmpty) return result;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return result;
      final klines = data['klines'] as List<dynamic>?;
      if (klines == null || klines.isEmpty) return result;

      String? prevCloseStr;
      for (final line in klines) {
        final parts = (line as String).split(',');
        if (parts.length < 4) continue;
        final day = parts[0]; // 日期 YYYY-MM-DD
        final close = double.tryParse(parts[2]) ?? 0; // 收盘价
        if (prevCloseStr != null) {
          final prevClose = double.tryParse(prevCloseStr) ?? 0;
          if (prevClose > 0 && close > 0) {
            result[day] = (close - prevClose) / prevClose * 100;
          }
        }
        prevCloseStr = parts[2];
      }
    } finally {
      client.close();
    }
    return result;
  }

  /// 日期字符串加1天：'2026-06-09' → '2026-06-10'
  /// 自动跳过周末和A股节假日
  static String nextDay(String dateStr) {
    final d = DateTime.parse(dateStr);
    var next = DateTime(d.year, d.month, d.day + 1);
    // 跳过周末 + A股节假日
    while (_isNonTradingDay(next)) {
      next = next.add(const Duration(days: 1));
    }
    return next.toString().substring(0, 10);
  }

  /// A股非交易日判断：周末或节假日
  static bool _isNonTradingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return true;
    }
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return _kHolidayDates.contains(dateStr);
  }

  static const Set<String> _kHolidayDates = {
    // 2026年元旦
    '2026-01-01',
    // 2026年春节（2月16日除夕~2月22日初六）
    '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-21', '2026-02-22',
    // 2026年清明节（4月4日~4月6日）
    '2026-04-04', '2026-04-05', '2026-04-06',
    // 2026年劳动节（5月1日~5月5日）
    '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
    // 2026年端午节（6月19日~6月21日）
    '2026-06-19', '2026-06-20', '2026-06-21',
    // 2026年中秋节（9月25日~9月27日）
    '2026-09-25', '2026-09-26', '2026-09-27',
    // 2026年国庆节+中秋（10月1日~10月7日）
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    '2026-10-05', '2026-10-06', '2026-10-07',
  };
}
