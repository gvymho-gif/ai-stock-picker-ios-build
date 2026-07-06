/// 后台常驻服务 —— 全模块实时同步
///
/// 使用 flutter_background_service 保持前台常驻服务，即使 App 完全退出
/// 也能在 A 股交易时段持续运行。
///
/// 同步模块：
/// 1. 热点投资止盈止损检查（交易时段每 3 秒）
/// 2. 专家选股表现实时涨跌幅刷新（交易时段每 3 秒）
/// 3. 收盘后自动冻结并保存数据
///
/// 前后台通信：
/// - 后台 → 前台：service.invoke('data_changed', {module, changedIds})
/// - 前台 → 后台：service.invoke('check_now')
/// - App 恢复前台：forceReload 所有持久化模块

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'hot_investment_service.dart';
import 'lite_investment_service.dart';
import 'expert_performance_service.dart';
import 'local_data_service.dart';
import 'server_config_service.dart';
import '../utils/trading_day_utils.dart';

class BackgroundStockService {
  static final BackgroundStockService _instance = BackgroundStockService._();
  factory BackgroundStockService() => _instance;
  BackgroundStockService._();

  static const int _notificationId = 888;
  static const int _checkIntervalSeconds = 3;

  final FlutterBackgroundService _service = FlutterBackgroundService();

  /// 初始化并启动后台服务（App 启动时调用一次）
  Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: 'stock_monitor_channel',
        initialNotificationTitle: '蓝图极智',
        initialNotificationContent: '止盈止损监控已就绪',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onBackground,
      ),
    );
  }

  /// 启动后台监控
  Future<bool> start() async {
    final running = await _service.isRunning();
    if (!running) {
      return _service.startService();
    }
    return true;
  }

  /// 检查是否正在运行
  Future<bool> isRunning() async {
    return _service.isRunning();
  }

  /// 监听后台数据变化（前台 UI 调用）
  Stream<Map<String, dynamic>?> onDataChanged() {
    return _service.on('data_changed');
  }

  /// 通知后台服务立即执行一次检查
  void triggerCheck() {
    _service.invoke('check_now');
  }

  /// 触发一次云端收益历史同步（前台UI可直接调用）
  void triggerPerformanceSync() {
    _service.invoke('sync_performance');
  }
}

/// 后台服务入口（运行在独立 isolate 中，必须是顶层函数）
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final hotService = HotInvestmentService();
  hotService.forceReload();
  await hotService.load();

  final liteService = LiteInvestmentService();
  liteService.forceReload();
  await liteService.load();

  final api = LocalDataService();
  Timer? checkTimer;
  bool isInTradingHours = false;
  bool hasFrozenToday = false;
  int refreshCount = 0;

  debugPrint('[后台服务] 启动，热点组合: ${hotService.holdingPortfolios.length}, 轻量组合: ${liteService.holdingPortfolios.length}');

  /// 判断是否在 A 股正式交易时段 (9:30-15:00 交易日)
  /// ★ 9:30开盘，15:00收盘，集合竞价阶段不执行止盈止损
  bool isTradingTime() {
    final now = DateTime.now();
    if (!TradingDayUtils.isSecuritiesTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    // 上午 9:30-11:30, 下午 13:00-15:00
    final amStart = 9 * 60 + 30;
    final amEnd = 11 * 60 + 30;
    final pmStart = 13 * 60;
    final pmEnd = 15 * 60; // ★ 15:00收盘
    return (minutes >= amStart && minutes <= amEnd) ||
           (minutes >= pmStart && minutes <= pmEnd);
  }

/// 判断是否在结算窗口 (9:30-15:05)
/// ★ 9:30起才刷新行情数据（集合竞价阶段价格不稳定）
bool isSettlementWindow() {
    final now = DateTime.now();
    if (!TradingDayUtils.isSecuritiesTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= 9 * 60 + 30 && minutes <= 15 * 60 + 5;
  }

  /// 判断是否过了冻结时间 (19:30 后)
  bool isPostSettlement() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    return minutes >= 19 * 60 + 30;
  }

  /// 通知前台数据已变更
  void notifyForeground(String module, List<String> changedIds) {
    service.invoke('data_changed', {
      'module': module,
      'changedIds': changedIds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 执行专家选股表现实时刷新
  /// ★ 非交易日（周末+节假日）不执行任何刷新
  Future<void> refreshExpertPerformance() async {
    // ★ 非交易日不刷新，避免非交易日数据被写入
    if (!TradingDayUtils.isSecuritiesTradingDay(DateTime.now())) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('expert_performance_history');
      if (historyJson == null) return;

      final List<dynamic> jsonList = jsonDecode(historyJson);
      if (jsonList.isEmpty) return;

      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // 确定当前显示哪天记录
      String displayDate;
      if (now.hour >= 20) {
        displayDate = today;
      } else {
        final yesterday = now.subtract(const Duration(days: 1));
        displayDate = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      }

      // 找到活跃记录
      var activeRecord = jsonList.firstWhere(
        (j) => j['date'] == displayDate,
        orElse: () => jsonList.first,
      );
      if (activeRecord == null) return;

      final stocks = activeRecord['stocks'] as List<dynamic>?;
      if (stocks == null || stocks.isEmpty) return;

      // 并行请求所有股票实时行情
      bool anyUpdated = false;
      final futures = stocks.map((stockJson) async {
        try {
          final code = stockJson['code'] as String;
          final stockData = await api.searchStock(code);
          if (stockData.isNotEmpty) {
            final changePct = (stockData['change_pct'] as num?)?.toDouble() ?? 0;
            if (changePct != 0) {
              return MapEntry(code, changePct);
            } else {
              // 回退计算
              final currentPrice = (stockData['price'] as num?)?.toDouble() ?? 0;
              final startPrice = (stockJson['startPrice'] as num?)?.toDouble() ?? 0;
              if (currentPrice > 0 && startPrice > 0) {
                return MapEntry(code, (currentPrice - startPrice) / startPrice * 100);
              }
            }
          }
        } catch (_) {}
        return null;
      }).toList();

      final results = await Future.wait(futures);

      // 更新股票涨跌幅
      double totalChange = 0;
      int upCount = 0;
      int downCount = 0;
      for (int i = 0; i < results.length; i++) {
        final result = results[i];
        if (result != null) {
          stocks[i]['changePercent'] = result.value;
          anyUpdated = true;
          totalChange += result.value;
          if (result.value > 0) upCount++;
          if (result.value < 0) downCount++;
        } else {
          final cp = (stocks[i]['changePercent'] as num?)?.toDouble() ?? 0;
          totalChange += cp;
          if (cp > 0) upCount++;
          if (cp < 0) downCount++;
        }
      }

      if (anyUpdated) {
        activeRecord['dailyAvgChange'] = totalChange / stocks.length;
        activeRecord['upCount'] = upCount;
        activeRecord['downCount'] = downCount;
        activeRecord['isSettled'] = false;

        await prefs.setString('expert_performance_history', jsonEncode(jsonList));
        await prefs.setString('expert_performance_last_update', DateTime.now().toIso8601String());

        notifyForeground('expert_performance', []);
      }
    } catch (e) {
      debugPrint('[后台服务] 专家表现刷新异常: $e');
    }
  }

  /// 19:30 后冻结当日数据
  /// ★ 非交易日不执行冻结
  Future<void> freezeExpertPerformance() async {
    // ★ 非交易日不冻结
    if (!TradingDayUtils.isSecuritiesTradingDay(DateTime.now())) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('expert_performance_history');
      if (historyJson == null) return;

      final List<dynamic> jsonList = jsonDecode(historyJson);
      if (jsonList.isEmpty) return;

      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      var found = false;
      for (final record in jsonList) {
        if (record['date'] == today) {
          if (record['isSettled'] != true) {
            record['isSettled'] = true;
            found = true;
          }
          break;
        }
      }

      if (found) {
        await prefs.setString('expert_performance_history', jsonEncode(jsonList));
        debugPrint('[后台服务] 专家表现数据已冻结: $today');
        notifyForeground('expert_performance', []);
      }
    } catch (e) {
      debugPrint('[后台服务] 冻结专家表现异常: $e');
    }
  }

  /// 从百度云服务器同步收益统计历史数据
  /// 每天 19:30 自动执行，同时 App 启动时也会执行一次
  /// 会将云端 performance.json 的数据合并到本地 expert_performance_history
  Future<void> syncPerformanceFromCloud({bool forceAll = false}) async {
    try {
      final serverUrl = await ServerConfigService.getServerUrl();
      final token = await ServerConfigService.getToken();
      if (serverUrl.isEmpty || token.isEmpty) {
        debugPrint('[后台服务] 云端同步跳过：服务器未配置');
        return;
      }

      final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      final url = Uri.parse('$baseUrl/api/portfolio/performance');
      debugPrint('[后台服务] 从云端同步收益历史: $url');

      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('[后台服务] 云端同步失败: HTTP ${response.statusCode}');
        return;
      }

      final body = json.decode(utf8.decode(response.bodyBytes));
      // 服务器返回格式: {"type":"performance","data":{"type":"performance","data":[...]}}
      // 或者直接是 {"type":"performance","data":[...]}
      List<dynamic>? cloudList;
      if (body is Map) {
        final data = body['data'];
        if (data is List) {
          cloudList = data;
        } else if (data is Map) {
          final innerData = data['data'];
          if (innerData is List) {
            cloudList = innerData;
          }
        }
      }

      if (cloudList == null || cloudList.isEmpty) {
        debugPrint('[后台服务] 云端暂无收益历史数据');
        return;
      }

      // 读取本地已有记录
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('expert_performance_history');
      final List<dynamic> localList = historyJson != null && historyJson.isNotEmpty
          ? jsonDecode(historyJson)
          : [];

      final existingDates = localList.map((j) => j['date'].toString()).toSet();
      int newCount = 0;

      for (var item in cloudList) {
        if (item is! Map) continue;
        final date = item['date']?.toString();
        if (date == null || date.isEmpty) continue;

        // 云端是 list 格式，包装成 API 格式再通过 fromJson 解析
        // 如果是 dict 格式（含 date/stocks/dailyAvgChange 等字段），直接使用
        if (item['stocks'] == null) continue;

        // 如果本地已有该日期且非 forceAll，跳过
        if (existingDates.contains(date) && !forceAll) continue;

        // 云端数据格式与 App 端 DailyExpertPerformance.toJson() 一致
        // 直接存入，但需要规范化 isSettled 字段
        final Map<String, dynamic> record = Map<String, dynamic>.from(item);
        if (!record.containsKey('isSettled')) {
          record['isSettled'] = true;
        }

        // 移除已有的同日期记录（如果有）
        if (existingDates.contains(date)) {
          localList.removeWhere((j) => j['date'] == date);
        }

        localList.add(record);
        newCount++;
      }

      if (newCount > 0) {
        // 按日期排序（最新在前）
        localList.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

        await prefs.setString('expert_performance_history', jsonEncode(localList));
        await prefs.setString('expert_performance_last_update', DateTime.now().toIso8601String());
        debugPrint('[后台服务] 云端同步完成: 新增 $newCount 天收益记录');
        notifyForeground('expert_performance', []);
      } else {
        debugPrint('[后台服务] 云端同步: 无新数据');
      }
    } catch (e) {
      debugPrint('[后台服务] 云端同步异常: $e');
    }
  }

  /// 主循环 tick
  void tick() {
    final trading = isTradingTime();
    final inSettlement = isSettlementWindow();
    final postSettlement = isPostSettlement();

    if (trading) {
      if (!isInTradingHours) {
        isInTradingHours = true;
        hasFrozenToday = false;
        debugPrint('[后台服务] 进入交易时段，开始实时监控');
      }

      // 1. 热点投资止盈止损检查
      hotService.checkAllPortfolios().then((changedIds) {
        if (changedIds.isNotEmpty) {
          debugPrint('[后台服务] 热点止盈止损触发: ${changedIds.join(",")}');
          notifyForeground('hot_investment', changedIds);
        }
      }).catchError((e) {
        debugPrint('[后台服务] 热点止盈止损检查异常: $e');
      });

      // 2. 轻量投资止盈止损检查
      liteService.checkAllPortfolios().then((changedIds) {
        if (changedIds.isNotEmpty) {
          debugPrint('[后台服务] 轻量止盈止损触发: ${changedIds.join(",")}');
          notifyForeground('lite_investment', changedIds);
        }
      }).catchError((e) {
        debugPrint('[后台服务] 轻量止盈止损检查异常: $e');
      });

      // 3. 专家选股表现实时刷新
      refreshExpertPerformance();

      // 每 30 秒保存一次（10 次 tick = 30 秒）
      refreshCount++;
      if (refreshCount % 10 == 0) {
        // 数据已在 refreshExpertPerformance 中保存
      }
    } else {
      if (isInTradingHours) {
        isInTradingHours = false;
        debugPrint('[后台服务] 退出交易时段');
      }

      // 19:30 后冻结数据 + 云端同步收益历史（仅执行一次）
      if (postSettlement && !hasFrozenToday) {
        hasFrozenToday = true;
        freezeExpertPerformance();
        syncPerformanceFromCloud(forceAll: false);
      }
    }

    // 交易时段 3 秒，结算窗口内 3 秒，其他每小时
    final nextInterval = (trading || inSettlement)
        ? const Duration(seconds: BackgroundStockService._checkIntervalSeconds)
        : const Duration(hours: 1);

    checkTimer?.cancel();
    checkTimer = Timer(nextInterval, tick);
  }

  // 监听前台发来的立即检查指令
  service.on('check_now').listen((event) {
    debugPrint('[后台服务] 收到前台立即检查指令');
    // ★ 非交易日（周末/节假日）不触发任何检查和刷新
    final now = DateTime.now();
    if (!TradingDayUtils.isSecuritiesTradingDay(now)) {
      debugPrint('[后台服务] 非交易日，跳过所有检查');
      return;
    }
    // ★ 非交易时段（9:30~15:00之外）不触发止盈止损和建仓
    final minutes = now.hour * 60 + now.minute;
    final isTradingHours = (now.hour == 9 && now.minute >= 30) ||
        (now.hour >= 10 && now.hour < 15) ||
        (now.hour == 15 && now.minute <= 0); // ★ 15:00收盘
    if (!isTradingHours) {
      debugPrint('[后台服务] 非交易时段，跳过止盈止损检查');
      return;
    }
    hotService.checkAllPortfolios().then((changedIds) {
      if (changedIds.isNotEmpty) {
        notifyForeground('hot_investment', changedIds);
      }
    }).catchError((e) {
      debugPrint('[后台服务] 热点立即检查异常: $e');
    });
    liteService.checkAllPortfolios().then((changedIds) {
      if (changedIds.isNotEmpty) {
        notifyForeground('lite_investment', changedIds);
      }
    }).catchError((e) {
      debugPrint('[后台服务] 轻量立即检查异常: $e');
    });
    refreshExpertPerformance();
  });

  // 监听停止指令
  service.on('stop').listen((event) {
    checkTimer?.cancel();
    service.stopSelf();
  });

  // 监听云端同步指令
  service.on('sync_performance').listen((event) {
    debugPrint('[后台服务] 收到云端同步指令');
    syncPerformanceFromCloud(forceAll: true);
  });

  // 启动主循环
  tick();

  // 启动时立即从云端同步一次收益历史（异步执行，不阻塞主循环）
  syncPerformanceFromCloud(forceAll: false);
}

/// iOS 后台回调
@pragma('vm:entry-point')
Future<bool> _onBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ 非交易日或非交易时段不执行任何检查
  final now = DateTime.now();
  if (!TradingDayUtils.isSecuritiesTradingDay(now)) return true;
  final minutes = now.hour * 60 + now.minute;
  // ★ 9:30起才执行止盈止损（15:00收盘）
  final isTradingHours = (now.hour == 9 && now.minute >= 30) ||
      (now.hour >= 10 && now.hour < 15) ||
      (now.hour == 15 && now.minute <= 0);
  if (!isTradingHours) return true;

  final hotService = HotInvestmentService();
  hotService.forceReload();
  await hotService.load();
  final changedIds = await hotService.checkAllPortfolios();
  if (changedIds.isNotEmpty) {
    service.invoke('data_changed', {
      'module': 'hot_investment',
      'changedIds': changedIds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  return true;
}
