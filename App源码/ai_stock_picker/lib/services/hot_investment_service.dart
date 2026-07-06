/// 热点投资服务 - 虚拟跟单管理
///
/// 核心能力：
/// 1. 虚拟建仓（一键买入前三只标的）
/// 2. 止盈止损自动检查（+10%止盈 / 硬止损%止损）

import 'dart:math';
/// 3. 交易日追踪（最长5个交易日强制清仓）
/// 4. 数据持久化（SharedPreferences + JSON）

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/hot_investment_model.dart';
import '../models/hot_track_model.dart';
import 'local_data_service.dart';
import 'trading_day_cloud_service.dart';
import 'backup_service.dart';
import 'jianguoyun_service.dart';
import '../models/trading_day_record.dart';
import '../utils/trading_day_utils.dart';

class HotInvestmentService extends ChangeNotifier {
  // 单例模式：所有页面共享同一实例，保证数据一致性
  static final HotInvestmentService _instance = HotInvestmentService._internal();
  factory HotInvestmentService() => _instance;
  HotInvestmentService._internal();
  // 可继承的命名构造函数，供子类使用
  HotInvestmentService.createInstance();

  // 可覆盖的 getter — 子类可替换限额和存储key
  String get portfoliosKey => 'hot_investment_portfolios';
  String get calendarArchiveKey => 'hot_invest_calendar_archive';
  double get maxStockInvest => 30000.0;        // 每只股票上限
  double get maxPortfolioInvest => 90000.0;     // 组合上限（3只×30000）
  String get investmentType => '热点投资';       // 日志前缀
  DateTime get firstTradeDate => DateTime(2026, 6, 15);  // 首个建仓日，子类可覆盖

  static const double _kStopProfitRate = 0.10;  // +10% 止盈
  static const int _kMaxTradingDays = 5;        // 最长5个交易日
  static const int _kAutoCheckIntervalSeconds = 30; // 交易时段自动检查间隔

  final LocalDataService _api = LocalDataService();
  List<HotInvestmentPortfolio> _portfolios = [];
  List<Map<String, dynamic>> _calendarArchive = []; // 永久归档
  bool _loaded = false;
  Timer? _autoCheckTimer; // 交易时段定时止盈止损检查

  List<HotInvestmentPortfolio> get portfolios => List.unmodifiable(_portfolios);

  /// 运行中的组合（含pending待激活）
  List<HotInvestmentPortfolio> get holdingPortfolios =>
      _portfolios.where((p) => p.status == PortfolioStatus.holding || p.status == PortfolioStatus.pending).toList();

  /// 日历归档数据（永久保存，不受组合删除影响）
  List<Map<String, dynamic>> get calendarArchive => List.unmodifiable(_calendarArchive);

  /// 已结清的组合
  List<HotInvestmentPortfolio> get settledPortfolios =>
      _portfolios.where((p) => p.status == PortfolioStatus.settled).toList();

  // ============================================================
  // 交易时段定时止盈止损检查
  // ============================================================

  /// 启动交易时段定时检查
  /// 09:30-15:05 每30秒自动执行止盈止损检查
  void _startAutoCheck() {
    _stopAutoCheck();
    // 立即执行一次
    _autoCheckPortfolios();
    // 每30秒在交易时段执行一次止盈止损检查
    _autoCheckTimer = Timer.periodic(
      Duration(seconds: _kAutoCheckIntervalSeconds),
      (_) => _autoCheckPortfolios(),
    );
  }

  /// 停止定时检查
  void _stopAutoCheck() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = null;
  }

  /// 交易时段内自动执行止盈止损检查
  /// 非交易时段跳过，避免不必要的网络请求和计算
  /// ★ 9:30起才执行止盈止损（9:15-9:30为集合竞价，价格不稳定易误触发）
  Future<void> _autoCheckPortfolios() async {
    final now = DateTime.now();
    // 判断是否在正式交易时段（9:30 ~ 15:05）
    // ★ 不从9:20开始：9:20-9:30是集合竞价阶段，价格不稳定，容易误触发止盈止损
    final hour = now.hour;
    final minute = now.minute;
    final isTradingHours = (hour == 9 && minute >= 30) ||
        (hour >= 10 && hour < 15) ||
        (hour == 15 && minute <= 0); // ★ 15:00收盘

    // 非交易时段跳过
    if (!isTradingHours) return;

    // 无运行中组合则跳过
    final hasActive = _portfolios.any(
      (p) => p.status == PortfolioStatus.holding || p.status == PortfolioStatus.pending
    );
    if (!hasActive) return;

    try {
      final changedIds = await checkAllPortfolios();
      if (changedIds.isNotEmpty) {
        debugPrint('[热点投资] 自动止盈止损检查触发结算: ${changedIds.join(",")}');
      }
    } catch (e) {
      debugPrint('[热点投资] 自动止盈止损检查异常: $e');
    }
  }

  // ============================================================
  // 持久化
  // ============================================================

  /// 从本地加载所有组合 + 归档
  Future<void> load() async {
    if (_loaded) return;
    await _loadFromDisk();
  }

  /// 强制重新从本地加载数据（绕过 _loaded 缓存）
  /// 用于 App 从后台恢复时，同步后台 isolate 的变更
  Future<void> forceReload() async {
    _stopAutoCheck();
    _loaded = false;
    await _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(portfoliosKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonStr);
        _portfolios = jsonList
          .map((j) => HotInvestmentPortfolio.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
      }
      // 加载日历归档
      final archiveStr = prefs.getString(calendarArchiveKey);
      if (archiveStr != null && archiveStr.isNotEmpty) {
        final archiveList = json.decode(archiveStr) as List<dynamic>;
        _calendarArchive = archiveList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        // ★★★ 加载端去重清理：移除 portfolioName+stockCode+sellTime 完全相同的重复记录 ★★★
        final seenArchiveKeys = <String>{};
        final dedupedArchive = <Map<String, dynamic>>[];
        for (final entry in _calendarArchive) {
          final key = '${entry["portfolioName"]}_${entry["stockCode"]}_${entry["sellTime"]}';
          if (seenArchiveKeys.contains(key)) continue;
          seenArchiveKeys.add(key);
          dedupedArchive.add(entry);
        }
        if (dedupedArchive.length < _calendarArchive.length) {
          debugPrint('[$investmentType] 归档加载端去重: ${_calendarArchive.length} → ${dedupedArchive.length} 条');
          _calendarArchive = dedupedArchive;
          await _saveArchive();
        }
      }

      // ★ 数据检查：记录非交易时段建仓的异常持仓（仅日志，不回退）
      final anomalyCount = _fixErroneouslyActivatedPortfolios();
      if (anomalyCount > 0) {
        debugPrint('[$investmentType] 检测到 $anomalyCount 个持仓的buyTime不在正式交易时段(9:30-15:05)，已保留不回退');
      }

      // ★★★ 修复活跃组合中的T+1同日违规结算 ★★★
      // 例如：今天9:30激活，9:40就被止盈——违反T+1同日买卖规则
      final fixedActive = _fixSameDayViolationsInActive();
      if (fixedActive > 0) {
        debugPrint('[$investmentType] 恢复了 $fixedActive 个活跃组合中违反T+1的同日结算持仓');
        await _save();
      }

      // ★★★ 数据修复：从归档中恢复被错误结算的组合 ★★★
      final fixedSettled = _fixErroneouslySettledFromArchive();
      if (fixedSettled > 0) {
        debugPrint('[$investmentType] 从归档中恢复了 $fixedSettled 个被错误结算的组合');
        await _save();
        await _saveArchive();
      }
    } catch (e) {
      debugPrint('[热点投资] 加载失败: $e');
    }
    _loaded = true;
    notifyListeners();
    // 加载完成后启动交易时段定时止盈止损检查
    _startAutoCheck();
  }

  /// 检测并记录非交易时段建仓的异常持仓（仅记录日志，不做回退）
  ///
  /// ★ v2.0.2 重要修改：不再自动回退 buyPrice>0 且 shares>0 的持仓
  ///   原因：旧版本允许9:20建仓，9:20-9:30之间正常建仓的持仓数据是真实的，
  ///   强制回退会丢失真实的建仓价格和股数数据（如霍尔木兹海峡组合）。
  ///   现在 activatePendingPortfolio 已有三重交易时段保护（9:30+交易日+交易时段），
  ///   不会再出现非交易时段误激活，因此无需自动回退。
  ///
  ///   仍保留此函数用于日志监控，方便排查是否有新的误激活情况。
  int _fixErroneouslyActivatedPortfolios() {
    int anomalyCount = 0;

    for (final portfolio in _portfolios) {
      if (portfolio.status != PortfolioStatus.holding) continue;

      for (final pos in portfolio.positions) {
        if (pos.status == PositionStatus.holding && pos.buyPrice > 0 && pos.shares > 0) {
          // 已成功建仓的持仓：只记录日志，不回退
          if (!_wasActivatedDuringTradingHours(pos.buyTime)) {
            anomalyCount++;
            debugPrint('[$investmentType] ⚠️ ${pos.stockName}(${pos.stockCode}) buyTime=${pos.buyTime} 不在正式交易时段(9:30-15:05)，但已成功建仓(buyPrice=${pos.buyPrice}, shares=${pos.shares})，保留不回退');
          }
        }
      }
    }

    return anomalyCount; // 仅返回异常数量，不触发保存
  }

  /// ★★★ 修复活跃组合中违反T+1的同日结算持仓 ★★★
  ///
  /// 场景：组合今天9:30激活，10:00就被止盈/止损——buyTime和sellTime在同一天
  /// 违反了A股T+1规则（建仓日不允许卖出）
  ///
  /// 修复：将sellPrice/sellTime清空，status恢复为holding，保留buyPrice/buyTime/shares
  ///
  /// 返回修复的持仓数量
  int _fixSameDayViolationsInActive() {
    int fixedCount = 0;
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    for (int i = 0; i < _portfolios.length; i++) {
      final portfolio = _portfolios[i];
      // 只检查holding和pending状态的组合，已settled的在归档修复中处理
      if (portfolio.status != PortfolioStatus.holding && portfolio.status != PortfolioStatus.pending) continue;

      bool changed = false;
      final fixedPositions = <VirtualPosition>[];

      for (final pos in portfolio.positions) {
        // 只处理已结算的持仓（stopProfit/stopLoss/timeLiquidated）
        if (pos.status == PositionStatus.holding || pos.status == PositionStatus.unfilled) {
          fixedPositions.add(pos);
          continue;
        }

        // 检查是否 buyTime 和 sellTime 在同一天 → T+1违规
        final buyDate = DateTime(pos.buyTime.year, pos.buyTime.month, pos.buyTime.day);
        bool isSameDayViolation = false;

        if (pos.sellTime != null) {
          final sellDate = DateTime(pos.sellTime!.year, pos.sellTime!.month, pos.sellTime!.day);
          if (buyDate == sellDate) {
            isSameDayViolation = true;
          }
        }

        if (!isSameDayViolation) {
          fixedPositions.add(pos);
          continue;
        }

        // ★ 恢复为holding：保留buyPrice/buyTime/shares，清除卖出信息
        changed = true;
        fixedPositions.add(VirtualPosition(
          stockCode: pos.stockCode,
          stockName: pos.stockName,
          buyPrice: pos.buyPrice,
          buyTime: pos.buyTime,
          investedAmount: pos.investedAmount,
          shares: pos.shares,
          status: PositionStatus.holding, // ★ 恢复为持仓
          stopLossPercent: pos.stopLossPercent,
        ));
        fixedCount++;
        debugPrint('[$investmentType] 🔧 恢复同日违规结算: ${pos.stockName}(${pos.stockCode}) buyTime=${pos.buyTime} sellTime=${pos.sellTime} → 恢复为holding');
      }

      if (changed) {
        // 恢复组合状态为holding（如果有holding持仓）
        final hasHolding = fixedPositions.any((p) => p.status == PositionStatus.holding);
        _portfolios[i] = portfolio.copyWith(
          positions: fixedPositions,
          status: hasHolding ? PortfolioStatus.holding : _portfolios[i].status,
          totalReturn: 0,
          settledAt: null,
        );
      }
    }

    return fixedCount;
  }

  /// ★★★ 从归档中恢复被错误结算的组合 ★★★
  ///
  /// 两种错误场景：
  /// 1. 集合竞价阶段错误结算：sellTime 在今天且在9:30之前（价格不稳定误触发）
  /// 2. T+1 违规同日结算：buyTime 和 sellTime 在同一天（当天激活当天就卖了）
  ///
  /// 修复逻辑：
  /// 1. 从 calendarArchive 中找出符合条件的错误记录
  /// 2. 按组合名（portfolioName）聚合，重建为 holding 状态的活跃组合
  /// 3. 从归档中删除这些错误记录
  ///
  /// 返回恢复的组合数量
  int _fixErroneouslySettledFromArchive() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todayDate = DateTime(now.year, now.month, now.day);

    final erroneouslySettled = <Map<String, dynamic>>[];
    final remainingArchive = <Map<String, dynamic>>[];
    int reasonBefore930 = 0;
    int reasonSameDay = 0;

    for (final entry in _calendarArchive) {
      final sellTimeStr = entry['sellTime']?.toString();
      if (sellTimeStr == null) {
        remainingArchive.add(entry);
        continue;
      }

      try {
        final sellTime = DateTime.parse(sellTimeStr);
        final sellDate = DateTime(sellTime.year, sellTime.month, sellTime.day);

        // 只处理今天的错误结算
        if (sellDate != todayDate) {
          remainingArchive.add(entry);
          continue;
        }

        bool isError = false;

        // 原因1：今天且在9:30之前被结算（集合竞价误触发）
        final sellTimeMinutes = sellTime.hour * 60 + sellTime.minute;
        if (sellTimeMinutes < 9 * 60 + 30) {
          isError = true;
          reasonBefore930++;
        }

        // 原因2：buyTime 和 sellTime 在同一天（T+1违规，当天激活当天就卖了）
        if (!isError) {
          final buyTimeStr = entry['buyTime']?.toString();
          if (buyTimeStr != null) {
            try {
              final buyTime = DateTime.parse(buyTimeStr);
              final buyDate = DateTime(buyTime.year, buyTime.month, buyTime.day);
              if (buyDate == todayDate) {
                isError = true;
                reasonSameDay++;
              }
            } catch (_) {}
          }
        }

        if (isError) {
          erroneouslySettled.add(entry);
        } else {
          remainingArchive.add(entry);
        }
      } catch (_) {
        remainingArchive.add(entry);
      }
    }

    if (erroneouslySettled.isEmpty) return 0;

    debugPrint('[$investmentType] 发现 ${erroneouslySettled.length} 条错误归档记录 (9:30前:$reasonBefore930, 同日买卖:$reasonSameDay)，准备恢复');

    // 按 portfolioName + hotTrackTitle 聚合，重建组合
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final entry in erroneouslySettled) {
      final key = '${entry['portfolioName']}_${entry['hotTrackTitle']}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    int restoredCount = 0;
    for (final groupEntry in grouped.entries) {
      final entries = groupEntry.value;
      // 重建持仓列表：恢复为 holding 状态
      final positions = <VirtualPosition>[];
      double totalInvested = 0;
      final portfolioName = entries.first['portfolioName']?.toString() ?? groupEntry.key;
      final hotTrackTitle = entries.first['hotTrackTitle']?.toString() ?? '';

      for (final entry in entries) {
        final buyPrice = (entry['buyPrice'] as num?)?.toDouble() ?? 0;
        final shares = (entry['shares'] as num?)?.toInt() ?? 0;
        final investedAmount = (entry['investedAmount'] as num?)?.toDouble() ?? 0;
        final stopLossPercent = min((entry['stopLossPercent'] as num?)?.toDouble() ?? 0.05, 0.05);
        DateTime buyTime;
        try {
          buyTime = entry['buyTime'] != null ? DateTime.parse(entry['buyTime'].toString()) : now;
        } catch (_) {
          buyTime = now;
        }

        if (buyPrice > 0 && shares > 0) {
          positions.add(VirtualPosition(
            stockCode: entry['stockCode']?.toString() ?? '',
            stockName: entry['stockName']?.toString() ?? '',
            buyPrice: buyPrice,
            buyTime: buyTime,
            investedAmount: investedAmount,
            shares: shares,
            status: PositionStatus.holding, // ★ 恢复为持仓
            stopLossPercent: stopLossPercent,
          ));
          totalInvested += investedAmount;
        }
      }

      if (positions.isEmpty) continue;

      // 重建组合
      final portfolio = HotInvestmentPortfolio(
        id: const Uuid().v4().toString().substring(0, 8), // 新ID（原ID已被删除）
        name: portfolioName,
        hotTrackTitle: hotTrackTitle,
        createdAt: positions.first.buyTime,
        status: PortfolioStatus.holding,
        positions: positions,
        totalInvested: totalInvested,
      );

      _portfolios.insert(0, portfolio);
      restoredCount++;
      debugPrint('[$investmentType] 恢复组合: $portfolioName (${positions.length}只股票, 投入¥$totalInvested)');
    }

    // 从归档中删除错误记录
    _calendarArchive = remainingArchive;

    return restoredCount;
  }

  /// 判断某个时间点是否在A股正式交易时段内（9:30~15:00 且为交易日）
  static bool _wasActivatedDuringTradingHours(DateTime time) {
    // 1. 必须是交易日
    if (!TradingDayUtils.isSecuritiesTradingDay(time)) {
      return false;
    }
    // 2. 必须在正式交易时段内（9:30~15:00）
    final minutes = time.hour * 60 + time.minute;
    final amStart = 9 * 60 + 30;
    final amEnd = 11 * 60 + 30;
    final pmStart = 13 * 60;
    final pmEnd = 15 * 60; // ★ 15:00收盘
    return (minutes >= amStart && minutes <= amEnd) ||
           (minutes >= pmStart && minutes <= pmEnd);
  }

  /// 保存到本地
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _portfolios.map((p) => p.toJson()).toList();
      await prefs.setString(portfoliosKey, json.encode(jsonList));
      notifyListeners();
    } catch (e) {
      debugPrint('[热点投资] 保存失败: $e');
    }
  }

  /// 保存归档到本地
  Future<void> _saveArchive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(calendarArchiveKey, json.encode(_calendarArchive));
    } catch (e) {
      debugPrint('[热点投资] 归档保存失败: $e');
    }
  }

  // ============================================================
  // 组合管理
  // ============================================================

  /// 获取指定组合
  HotInvestmentPortfolio? getPortfolio(String id) {
    try {
      return _portfolios.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 更新组合
  Future<void> updatePortfolio(HotInvestmentPortfolio updated) async {
    final idx = _portfolios.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      _portfolios[idx] = updated;
      await _save();
    }
  }

  /// 删除组合
  Future<void> deletePortfolio(String id) async {
    _portfolios.removeWhere((p) => p.id == id);
    await _save();
  }

  /// 替换所有组合数据（用于云端恢复）
  Future<void> replacePortfolios(List<HotInvestmentPortfolio> newPortfolios) async {
    _portfolios = List.from(newPortfolios);
    await _save();
  }

  /// 替换日历归档（用于云端恢复）
  Future<void> replaceCalendarArchive(List<Map<String, dynamic>> newArchive) async {
    _calendarArchive = List.from(newArchive);
    await _saveArchive();
  }

  // ============================================================
  // 一键买入
  // ============================================================

  /// 从热点追踪结果一键创建虚拟投资组合
  /// 买入前3只标的，每只固定30000元上限
  /// ★ 非交易时段（9:30-15:00之外）只创建 pending 待激活状态，等下一个交易日9:30后自动买入
  /// ★ 只有在 9:30-15:00 交易时段内才直接实时买入
  Future<HotInvestmentPortfolio> createPortfolioFromHotTrack({
    required HotTrackResult result,
  }) async {
    if (!result.isActionable) {
      throw Exception('当前热点不满足建仓条件（需要S/A级+GO信号）');
    }
    if (result.targets.length < 3) {
      throw Exception('标的数量不足，需要至少3只股票');
    }

    final targets = result.targets.take(3).toList();
    final now = DateTime.now();
    final isTradeDay = await _isTradingDay(now);

    // ★ 判断当前是否在正式交易时段（9:30~15:00）
    // 只有交易时段内才直接买入，否则创建 pending 待激活
    final minutes = now.hour * 60 + now.minute;
    final isTradingHours = isTradeDay && (
        (now.hour == 9 && now.minute >= 30) ||
        (now.hour >= 10 && now.hour < 15) ||
        (now.hour == 15 && now.minute <= 0)  // ★ 15:00收盘，不含15:05
    );

    // 解析硬止损百分比
    final stopLossPercent = _parseStopLossPercent(result.executionParams?.hardStopLoss);

    if (!isTradingHours) {
      // ★ 非交易时段（包括非交易日、交易日的非交易时段如20:00）：
      // 创建 pending 待激活组合，等下一个交易日 9:30 后自动买入
      final positions = targets.map((t) => VirtualPosition(
        stockCode: t.code,
        stockName: t.name,
        buyPrice: 0,           // 占位，交易日激活时填入
        buyTime: now,           // 记录创建时间，实际买入时间在激活时更新
        investedAmount: 0,     // 占位
        shares: 0,
        status: PositionStatus.unfilled,
        stopLossPercent: stopLossPercent,
      )).toList();

      final dateStr = '${now.month}/${now.day}';
      final name = '${_truncateTitle(result.newsTitle, 10)}·$dateStr';

      final portfolio = HotInvestmentPortfolio(
        id: const Uuid().v4().toString().substring(0, 8),
        name: name,
        hotTrackTitle: result.newsTitle,
        newsRating: result.ratingLabel,
        createdAt: now,
        status: PortfolioStatus.pending,
        positions: positions,
        totalInvested: 0,
      );

      _portfolios.insert(0, portfolio);
      await _save();
      debugPrint('[$investmentType] 非交易时段创建待激活组合，等下一个交易日9:30后自动买入');
      return portfolio;
    }

    // 交易时段（9:30-15:00交易日）：直接实时买入
    final positions = <VirtualPosition>[];
    double totalInvested = 0;

    for (final target in targets) {
      try {
        final quote = await _api.fetchQuickQuote(target.code);
        final price = (quote?['price'] as num?)?.toDouble() ?? 0;
        if (price <= 0) {
          debugPrint('[热点投资] ${target.name}(${target.code}) 无法获取价格，跳过');
          continue;
        }

        final rawShares = (maxStockInvest / price).floor();
        final shares = (rawShares ~/ 100) * 100;
        if (shares < 100) {
          debugPrint('[热点投资] ${target.name}(${target.code}) 价格过高(¥$price)，跳过');
          continue;
        }

        final actualInvest = shares * price;
        final name = quote?['name']?.toString() ?? target.name;

        positions.add(VirtualPosition(
          stockCode: target.code,
          stockName: name,
          buyPrice: price,
          buyTime: now,
          investedAmount: actualInvest,
          shares: shares,
          stopLossPercent: stopLossPercent,
        ));

        totalInvested += actualInvest;
      } catch (e) {
        debugPrint('[热点投资] ${target.name}(${target.code}) 买入失败: $e');
      }
    }

    if (positions.isEmpty) {
      throw Exception('所有标的均无法完成虚拟建仓');
    }

    final dateStr = '${now.month}/${now.day}';
    final name = '${_truncateTitle(result.newsTitle, 10)}·$dateStr';

    final portfolio = HotInvestmentPortfolio(
      id: const Uuid().v4().toString().substring(0, 8),
      name: name,
      hotTrackTitle: result.newsTitle,
      newsRating: result.ratingLabel,
      createdAt: now,
      positions: positions,
      totalInvested: totalInvested,
    );

    _portfolios.insert(0, portfolio);
    await _save();
    return portfolio;
  }

  /// 激活pending组合（交易日自动触发）
  /// 以最快方式获取实时价格完成建仓
  Future<HotInvestmentPortfolio?> activatePendingPortfolio(HotInvestmentPortfolio portfolio) async {
    if (portfolio.status != PortfolioStatus.pending) return null;

    final now = DateTime.now();
    final isTradeDay = await _isTradingDay(now);
    if (!isTradeDay) return null; // 仍然不是交易日

    // ★ 必须在正式交易时段内才能激活买入（9:30~15:00）
    // 防止凌晨/深夜/集合竞价等非交易时段误触发建仓
    final minutes = now.hour * 60 + now.minute;
    final isTradingHours = (now.hour == 9 && now.minute >= 30) ||
        (now.hour >= 10 && now.hour < 15) ||
        (now.hour == 15 && now.minute <= 0); // ★ 15:00收盘
    if (!isTradingHours) return null;

    final updatedPositions = <VirtualPosition>[];
    double totalInvested = 0;
    bool allFilled = true;

    for (final pos in portfolio.positions) {
      if (pos.status != PositionStatus.unfilled) {
        updatedPositions.add(pos);
        if (pos.investedAmount > 0) totalInvested += pos.investedAmount;
        continue;
      }

      try {
        final quote = await _api.fetchQuickQuote(pos.stockCode);
        if (quote == null) { allFilled = false; updatedPositions.add(pos); continue; }
        final price = (quote['price'] as num?)?.toDouble() ?? 0;
        if (price <= 0) { allFilled = false; updatedPositions.add(pos); continue; }

        final rawShares = (maxStockInvest / price).floor();
        final shares = (rawShares ~/ 100) * 100;
        if (shares < 100) { allFilled = false; updatedPositions.add(pos); continue; }

        final actualInvest = shares * price;
        final name = quote['name']?.toString() ?? pos.stockName;

        updatedPositions.add(VirtualPosition(
          stockCode: pos.stockCode,
          stockName: name,
          buyPrice: price,
          buyTime: now,
          investedAmount: actualInvest,
          shares: shares,
          stopLossPercent: pos.stopLossPercent,
        ));

        totalInvested += actualInvest;
        debugPrint('[热点投资] 激活建仓 ${pos.stockName} @ ¥$price x $shares股');
      } catch (_) {
        allFilled = false;
        updatedPositions.add(pos);
      }
    }

    final updated = portfolio.copyWith(
      positions: updatedPositions,
      totalInvested: totalInvested,
      status: allFilled ? PortfolioStatus.holding : PortfolioStatus.pending,
    );

    await updatePortfolio(updated);
    debugPrint('[热点投资] 组合 ${portfolio.id} 激活完成，投入 ¥$totalInvested');
    return updated;
  }

  // ============================================================
  // 止盈止损检查 & 自动结算
  // ============================================================

  /// 检查并执行止盈止损（对所有运行中&待激活的组合）
  /// 返回发生变动的组合ID列表
  /// ★ 超过5个交易日的过期持仓允许盘后 (15:05-次日09:30) 也触发强制平仓检查
  Future<List<String>> checkAllPortfolios() async {
    // 非交易时段(09:30前/15:05后)不执行常规检查
    // ★ 但如果有超过5交易日的过期持仓，仍然允许触发强制平仓
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final inTradingWindow = minutes >= 9 * 60 + 30 && minutes <= 15 * 60 + 5;

    final changedIds = <String>[];
    final portfolios = List<HotInvestmentPortfolio>.from(
      _portfolios.where((p) => p.status == PortfolioStatus.holding || p.status == PortfolioStatus.pending)
    );

    // 检查是否有已超过5交易日的过期持仓
    bool hasOverdue = false;
    if (!inTradingWindow) {
      for (final portfolio in portfolios) {
        if (portfolio.status != PortfolioStatus.holding) continue;
        for (final pos in portfolio.positions) {
          if (pos.status != PositionStatus.holding) continue;
          final tradingDays = await _countTradingDays(pos.buyTime, now);
          if (tradingDays > _kMaxTradingDays) {
            hasOverdue = true;
            break;
          }
        }
        if (hasOverdue) break;
      }
    }

    // 不在交易时段且无过期持仓 → 跳过
    if (!inTradingWindow && !hasOverdue) return [];

    for (final portfolio in portfolios) {
      // 先尝试激活pending组合
      HotInvestmentPortfolio current = portfolio;
      if (current.status == PortfolioStatus.pending) {
        final activated = await activatePendingPortfolio(current);
        if (activated != null) {
          current = activated;
          changedIds.add(activated.id);
        }
        // 激活失败（仍非交易日）则跳过
        if (current.status != PortfolioStatus.holding) continue;
      }

      // 检查止盈止损
      final updated = await checkPortfolio(current);
      if (updated != null) {
        final idx = _portfolios.indexWhere((p) => p.id == updated.id);
        if (idx >= 0) {
          _portfolios[idx] = updated;
          changedIds.add(updated.id);
        }
      }
    }

    if (changedIds.isNotEmpty) {
      await _save();
      // 自动清除已完全结算的组合（归档+删除）
      for (final id in changedIds) {
        await _autoCleanupIfFullySettled(id);
      }
    }
    return changedIds;
  }

  /// 检查单个组合的止盈止损/时间清仓
  /// 返回更新后的组合，无变化返回 null
  /// 遵循A股T+1：建仓日不检查卖出
  /// 非交易日（周末/节假日）不触发时间清仓，避免非交易日误清仓
  Future<HotInvestmentPortfolio?> checkPortfolio(HotInvestmentPortfolio portfolio) async {
    bool changed = false;
    final updatedPositions = <VirtualPosition>[];
    final now = DateTime.now();
    // 非交易日不触发任何结算操作
    final isTradeDay = _isSecuritiesTradingDay(now);

    for (final pos in portfolio.positions) {
      // 未成交的跳过（等待交易日激活）
      if (pos.status == PositionStatus.unfilled) {
        updatedPositions.add(pos);
        continue;
      }

      // 已结算的直接保留
      if (pos.status != PositionStatus.holding) {
        updatedPositions.add(pos);
        continue;
      }

      // 非交易日不检查任何卖出条件（止盈/止损/时间清仓）
      if (!isTradeDay) {
        updatedPositions.add(pos);
        continue;
      }

      // A股T+1：建仓日不触发卖出检查
      // ★ _countTradingDays 包含起始日和结束日（含首尾），首日计为1
      //   例如 buyTime=今天 → count=1 → 1<=1 skip（建仓日当天不卖出）
      //   例如 buyTime=昨天 → count=2 → 2>1 允许检查（T+1第二天可卖出）
      final tradingDaysSinceBuy = await _countTradingDays(pos.buyTime, now);
      if (tradingDaysSinceBuy <= 1) {
        updatedPositions.add(pos);
        continue;
      }

      try {
        final quote = await _api.fetchQuickQuote(pos.stockCode);
        final currentPrice = (quote?['price'] as num?)?.toDouble() ?? 0;
        if (currentPrice <= 0) {
          updatedPositions.add(pos);
          continue;
        }

        // 检查止盈 (+10%)
        if (pos.wouldStopProfit(currentPrice)) {
          updatedPositions.add(pos.settle(
            newStatus: PositionStatus.stopProfit,
            sellPrice: currentPrice,
            sellTime: now,
          ));
          changed = true;
          debugPrint('[热点投资] ${pos.stockName} T+${tradingDaysSinceBuy} 触发止盈！建仓价:${pos.buyPrice} 当前价:$currentPrice');
          continue;
        }

        // 检查止损
        if (pos.wouldStopLoss(currentPrice)) {
          updatedPositions.add(pos.settle(
            newStatus: PositionStatus.stopLoss,
            sellPrice: currentPrice,
            sellTime: now,
          ));
          changed = true;
          debugPrint('[热点投资] ${pos.stockName} T+${tradingDaysSinceBuy} 触发止损！硬止损:${(pos.stopLossPercent * 100).toStringAsFixed(1)}%');
          continue;
        }

        // 检查时间清仓 (第5个交易日14:55后强制平仓)
        // ★ 超过5个交易日后，09:30开盘即可平仓，不再��到14:55
        if (tradingDaysSinceBuy >= _kMaxTradingDays) {
          final currentMinutes = now.hour * 60 + now.minute;
          final forceLiquidateTime = 14 * 60 + 55; // 14:55
          // 第5天：需等到14:55才平仓；第6天起：09:30即可平仓
          final shouldLiquidate = tradingDaysSinceBuy > _kMaxTradingDays
              ? currentMinutes >= 9 * 60 + 30  // 超过5天，开盘即可清仓
              : currentMinutes >= forceLiquidateTime; // 第5天等14:55
          if (shouldLiquidate) {
            updatedPositions.add(pos.settle(
              newStatus: PositionStatus.timeLiquidated,
              sellPrice: currentPrice,
              sellTime: now,
            ));
            changed = true;
            debugPrint('[$investmentType] ${pos.stockName} T+${tradingDaysSinceBuy} 触发时间清仓！(强制平仓)');
            continue;
          } else {
            debugPrint('[$investmentType] ${pos.stockName} T+${tradingDaysSinceBuy} 已达上限但未到${tradingDaysSinceBuy > _kMaxTradingDays ? "09:30" : "14:55"}，等待强制平仓');
          }
        }

        updatedPositions.add(pos);
      } catch (_) {
        updatedPositions.add(pos);
      }
    }

    if (!changed) return null;

    final allSettled = updatedPositions.every((p) => p.status != PositionStatus.holding && p.status != PositionStatus.unfilled);
    final totalReturn = updatedPositions
      .where((p) => p.returnAmount != null)
      .fold<double>(0, (sum, p) => sum + p.returnAmount!);

    return portfolio.copyWith(
      positions: updatedPositions,
      totalReturn: totalReturn,
      status: allSettled ? PortfolioStatus.settled : PortfolioStatus.holding,
      settledAt: allSettled ? now : null,
    );
  }

  /// 获取持仓中股票的实时快照（不触发结算）
  /// 使用轻量行情接口 fetchQuickQuote，不走 searchStock 的完整AI分析流程
  /// 并发获取所有持仓行情，单只失败不影响其他
  /// 并发失败时串行重试一次
  Future<Map<String, Map<String, dynamic>>> getPositionQuotes(List<VirtualPosition> positions) async {
    final holding = positions.where((p) => p.status == PositionStatus.holding).toList();
    if (holding.isEmpty) return {};

    final result = <String, Map<String, dynamic>>{};
    final failed = <VirtualPosition>[];

    // 第一轮：并发获取
    final futures = holding.map((pos) async {
      try {
        final quote = await _api.fetchQuickQuote(pos.stockCode);
        if (quote != null && _safeQuotePrice(quote) > 0) {
          result[pos.stockCode] = quote;
        } else {
          failed.add(pos);
        }
      } catch (_) {
        failed.add(pos);
      }
    });
    await Future.wait(futures);

    // 第二轮：失败的串行重试（避免并发网络拥塞）
    for (final pos in failed) {
      try {
        final quote = await _api.fetchQuickQuote(pos.stockCode);
        if (quote != null && _safeQuotePrice(quote) > 0) {
          result[pos.stockCode] = quote;
        } else {
          debugPrint('[热点投资] ⚠️ ${pos.stockName}(${pos.stockCode}) 行情获取失败，重试仍无数据');
        }
      } catch (e) {
        debugPrint('[热点投资] ⚠️ ${pos.stockName}(${pos.stockCode}) 行情重试失败: $e');
      }
    }

    return result;
  }

  static double _safeQuotePrice(Map<String, dynamic> quote) {
    return (quote['price'] as num?)?.toDouble() ?? 0;
  }

  // ============================================================
  // 手动强制结算
  // ============================================================

  /// 手动强制结算整个组合（以当前市价清仓所有持仓）
  Future<HotInvestmentPortfolio> forceSettle(String portfolioId) async {
    final portfolio = getPortfolio(portfolioId);
    if (portfolio == null) throw Exception('组合不存在');

    final now = DateTime.now();
    final updatedPositions = <VirtualPosition>[];

    for (final pos in portfolio.positions) {
      if (pos.status != PositionStatus.holding) {
        updatedPositions.add(pos);
        continue;
      }
      try {
        final quote = await _api.fetchQuickQuote(pos.stockCode);
        final currentPrice = (quote?['price'] as num?)?.toDouble() ?? pos.buyPrice;
        updatedPositions.add(pos.settle(
          newStatus: PositionStatus.timeLiquidated, // 标记为手动清仓
          sellPrice: currentPrice,
          sellTime: now,
        ));
      } catch (_) {
        updatedPositions.add(pos.settle(
          newStatus: PositionStatus.timeLiquidated,
          sellPrice: pos.buyPrice,
          sellTime: now,
        ));
      }
    }

    final totalReturn = updatedPositions
      .where((p) => p.returnAmount != null)
      .fold<double>(0, (sum, p) => sum + p.returnAmount!);

    final updated = portfolio.copyWith(
      positions: updatedPositions,
      status: PortfolioStatus.settled,
      settledAt: now,
      totalReturn: totalReturn,
    );

    await updatePortfolio(updated);
    // 手动强制结算后自动归档+删除
    await _autoCleanupIfFullySettled(updated.id);
    return updated;
  }

  // ============================================================
  // 自动清除 + 永久归档
  // ============================================================

  /// 组合全部结算后：将持仓记录写入永久归档（去重），然后从列表中删除组合
  Future<void> _autoCleanupIfFullySettled(String portfolioId) async {
    final portfolio = getPortfolio(portfolioId);
    if (portfolio == null) return;
    if (portfolio.status != PortfolioStatus.settled) return;
    if (portfolio.positions.every((p) => p.status == PositionStatus.holding || p.status == PositionStatus.unfilled)) return;

    // ★★★ 写端去重：构建 existingKeys Set，避免同一组合重复归档 ★★★
    final existingKeys = _calendarArchive
        .map((e) => '${e["portfolioName"]}_${e["stockCode"]}_${e["sellTime"]}')
        .toSet();
    int addedCount = 0;

    // 写入归档
    for (final pos in portfolio.positions) {
      if (pos.sellTime == null) continue;
      final key = '${portfolio.name}_${pos.stockCode}_${pos.sellTime!.toIso8601String()}';
      if (existingKeys.contains(key)) continue;
      existingKeys.add(key);

      _calendarArchive.add({
        'stockCode': pos.stockCode,
        'stockName': pos.stockName,
        'buyPrice': pos.buyPrice,
        'buyTime': pos.buyTime.toIso8601String(),
        'sellPrice': pos.sellPrice,
        'sellTime': pos.sellTime!.toIso8601String(),
        'returnAmount': pos.returnAmount,
        'returnRate': pos.returnRate,
        'shares': pos.shares,
        'investedAmount': pos.investedAmount,
        'status': pos.status.name,
        'stopLossPercent': pos.stopLossPercent,
        'portfolioName': portfolio.name,
        'hotTrackTitle': portfolio.hotTrackTitle,
      });
      addedCount++;
    }
    await _saveArchive();

    // 从活跃列表中删除
    _portfolios.removeWhere((p) => p.id == portfolioId);
    await _save();

    debugPrint('[$investmentType] 组合 $portfolioId 已全部结算，归档${addedCount}条新记录，并从列表删除');
  }

  // ============================================================
  // 云端同步 — 合并到统一备份文件，避免删库重建冲突
  // ============================================================

  /// 上传所有热点投资组合到 Gitee 云端
  /// 策略：下载云端现有文件 → 合并热点投资数据 → 上传完整文件
  /// 这样不会覆盖收益统计和交易日记录数据
  Future<Map<String, dynamic>> uploadToCloud() async {
    final token = await BackupService.getGiteeToken();
    if (token == null || token.isEmpty) {
      return {'ok': false, 'error': '请先在设置页配置 Gitee 私人令牌'};
    }

    final repo = await BackupService.getFullRepoPath();
    if (repo == null) {
      return {'ok': false, 'error': '获取仓库路径失败，请重新保存令牌'};
    }

    try {
      // 1. 先下载云端现有备份（如果有的话），保留其他模块数据
      Map<String, dynamic> combinedData = {
        'version': 3,
        'backupTime': DateTime.now().toIso8601String(),
      };

      final existingContent = await BackupService.restoreFromGitee(token, repo);
      if (existingContent != null) {
        try {
          final decoded = json.decode(existingContent);
          // 兼容 Map<String, dynamic> 和 Map<dynamic, dynamic>
          Map<String, dynamic> existing;
          if (decoded is Map<String, dynamic>) {
            existing = decoded;
          } else if (decoded is Map) {
            existing = Map<String, dynamic>.from(decoded);
          } else {
            existing = {};
          }
          // 保留收益统计数据
          if (existing.containsKey('expertPerformance')) {
            combinedData['expertPerformance'] = existing['expertPerformance'];
          }
          if (existing.containsKey('expertPerformanceCount')) {
            combinedData['expertPerformanceCount'] = existing['expertPerformanceCount'];
          }
          // 保留交易日记录数据
          if (existing.containsKey('tradingDayRecords')) {
            combinedData['tradingDayRecords'] = existing['tradingDayRecords'];
          }
          if (existing.containsKey('tradingDayCount')) {
            combinedData['tradingDayCount'] = existing['tradingDayCount'];
          }
          // 保留旧版 history 格式兼容
          if (existing.containsKey('history') && !existing.containsKey('expertPerformance')) {
            combinedData['history'] = existing['history'];
            combinedData['recordCount'] = existing['recordCount'];
          }
          debugPrint('[热点投资] 已合并云端现有数据（v${existing['version']}）');
        } catch (e) {
          debugPrint('[热点投资] 解析云端现有数据失败，将创建全新备份: $e');
        }
      }

      // 2. 写入热点投资数据
      combinedData['hotInvestmentPortfolios'] = _portfolios.map((p) => p.toJson()).toList();
      combinedData['hotInvestmentCount'] = _portfolios.length;
      combinedData['hotInvestmentCalendarArchive'] = _calendarArchive;
      combinedData['hotInvestmentArchiveCount'] = _calendarArchive.length;

      final jsonStr = const JsonEncoder.withIndent('  ').convert(combinedData);

      debugPrint('[热点投资] 开始上传合并备份（${_portfolios.length}个组合 + ${_calendarArchive.length}条归档）...');
      final result = await BackupService.backupToGiteeWithDetail(token, repo, jsonStr);
      debugPrint('[热点投资] 上传结果: ${result['ok']}');
      return result;
    } catch (e) {
      debugPrint('[热点投资] 上传异常: $e');
      return {'ok': false, 'error': '上传异常: $e'};
    }
  }

  /// 从 Gitee 云端下载热点投资组合并覆盖本地数据
  /// 从统一备份文件中提取热点投资数据，不影响其他模块
  Future<Map<String, dynamic>> downloadFromCloud() async {
    final token = await BackupService.getGiteeToken();
    if (token == null || token.isEmpty) {
      return {'ok': false, 'error': '请先在设置页配置 Gitee 私人令牌'};
    }

    final repo = await BackupService.getFullRepoPath();
    if (repo == null) {
      return {'ok': false, 'error': '获取仓库路径失败，请重新保存令牌'};
    }

    try {
      debugPrint('[热点投资] 开始从云端下载 (repo=$repo)...');
      final content = await BackupService.restoreFromGitee(token, repo);

      if (content == null) {
        debugPrint('[热点投资] restoreFromGitee 返回 null');
        return {'ok': false, 'error': '云端暂无备份数据'};
      }

      debugPrint('[热点投资] 云端内容长度: ${content.length} 字符');

      final decoded = json.decode(content);
      debugPrint('[热点投资] JSON 解析成功, 类型: ${decoded.runtimeType}');

      // 兼容各种格式：decoded 可能是 Map<String, dynamic> 或 Map<dynamic, dynamic>
      Map<String, dynamic> data;
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      } else {
        debugPrint('[热点投资] JSON 根类型不是 Map: ${decoded.runtimeType}');
        return {'ok': false, 'error': '云端备份格式不包含热点投资数据 (类型: ${decoded.runtimeType})'};
      }

      debugPrint('[热点投资] data keys: ${data.keys.toList()}');

      // 从合并文件中提取热点投资数据
      if (!data.containsKey('hotInvestmentPortfolios')) {
        debugPrint('[热点投资] data 中没有 hotInvestmentPortfolios 键');
        return {'ok': false, 'error': '云端备份中暂无热点投资数据（请先在热点投资页上传）'};
      }

      final raw = data['hotInvestmentPortfolios'];
      debugPrint('[热点投资] raw 类型: ${raw.runtimeType}, 是否List: ${raw is List}');

      if (raw is! List) {
        return {'ok': false, 'error': '云端热点投资数据格式错误 (类型: ${raw.runtimeType})'};
      }

      if (raw.isEmpty) {
        return {'ok': false, 'error': '云端热点投资数据为空（0个组合）'};
      }

      // 逐条解析，单条失败不影响其他数据
      final parsed = <HotInvestmentPortfolio>[];
      int failCount = 0;
      for (int i = 0; i < raw.length; i++) {
        try {
          final map = Map<String, dynamic>.from(raw[i] as Map);
          parsed.add(HotInvestmentPortfolio.fromJson(map));
        } catch (e) {
          failCount++;
          debugPrint('[热点投资] 第${i}条组合解析失败: $e');
        }
      }

      if (parsed.isEmpty) {
        return {'ok': false, 'error': '云端数据全部解析失败（${failCount}/${raw.length}条）'};
      }

      _portfolios = parsed;
      debugPrint('[热点投资] 成功解析 ${parsed.length} 个组合（${failCount > 0 ? "$failCount条失败" : "无失败"}）');

      // 恢复日历归档
      if (data.containsKey('hotInvestmentCalendarArchive')) {
        final archiveRaw = data['hotInvestmentCalendarArchive'];
        if (archiveRaw is List && archiveRaw.isNotEmpty) {
          final archiveParsed = <Map<String, dynamic>>[];
          for (final e in archiveRaw) {
            try {
              archiveParsed.add(Map<String, dynamic>.from(e as Map));
            } catch (_) {}
          }
          _calendarArchive = archiveParsed;
          debugPrint('[热点投资] 恢复了 ${archiveParsed.length} 条归档');
        }
      }

      // 保存到本地
      await _save();
      await _saveArchive();

      final count = _portfolios.length;
      debugPrint('[热点投资] 云端下载成功（$count个组合）');
      notifyListeners(); // 通知 UI 刷新
      return {'ok': true, 'count': count};
    } catch (e, stackTrace) {
      debugPrint('[热点投资] 下载异常: $e');
      debugPrint('[热点投资] 堆栈: $stackTrace');
      return {'ok': false, 'error': '下载异常: $e'};
    }
  }

  /// 检查云端是否有热点投资备份
  static Future<bool> hasCloudBackup() async {
    final token = await BackupService.getGiteeToken();
    if (token == null || token.isEmpty) return false;

    final repo = await BackupService.getFullRepoPath();
    if (repo == null) return false;

    return await BackupService.hasGiteeBackup(token, repo);
  }

  // ============================================================
  // 坚果云 WebDAV 备份
  // ============================================================

  /// 🥜 上传到坚果云
  Future<Map<String, dynamic>> uploadToJianguoyun() async {
    final jsonStr = exportToLocalJson();
    return await JianguoyunService.upload(investmentType, jsonStr);
  }

  /// 📥 从坚果云下载
  Future<Map<String, dynamic>> downloadFromJianguoyun() async {
    try {
      debugPrint('[$investmentType] 开始坚果云下载...');
      final r = await JianguoyunService.downloadWithDetails(investmentType);
      debugPrint('[$investmentType] 坚果云下载返回: ok=${r['ok']}, statusCode=${r['statusCode']}, error=${r['error']}');

      if (r['ok'] != true) {
        // 先尝试列出云端文件进行诊断
        final listing = await JianguoyunService.listFiles();
        debugPrint('[$investmentType] 云端文件列表: ${listing['files']}');
        return {'ok': false, 'error': '下载失败: ${r['error'] ?? "坚果云暂无数据"} (HTTP ${r['statusCode']})'};
      }
      final content = r['content'] as String?;
      if (content == null || content.isEmpty) {
        return {'ok': false, 'error': '备份文件为空'};
      }

      debugPrint('[$investmentType] 下载内容长度: ${content.length} 字符');
      final count = await importFromLocalJson(content);
      if (count != null) {
        debugPrint('[$investmentType] 导入成功: $count 个组合');
        return {'ok': true, 'count': count};
      }
      debugPrint('[$investmentType] 导入失败: importFromLocalJson 返回 null');
      return {'ok': false, 'error': '数据格式不正确，请检查备份文件内容'};
    } catch (e) {
      debugPrint('[$investmentType] 坚果云下载异常: $e');
      return {'ok': false, 'error': '下载异常: $e'};
    }
  }

  /// 检查坚果云是否有备份
  static Future<bool> hasJianguoyunBackup(String moduleName) async {
    return await JianguoyunService.hasBackup(moduleName);
  }

  // ============================================================
  // 本地备份导入导出
  // ============================================================

  /// 导出现有数据为 JSON 字符串（供用户复制保存到本地文件）
  /// 包含：全部投资组合 + 日历归档
  String exportToLocalJson() {
    final data = {
      'type': investmentType,
      'version': 1,
      'exportTime': DateTime.now().toIso8601String(),
      'portfolioCount': _portfolios.length,
      'archiveCount': _calendarArchive.length,
      'portfolios': _portfolios.map((p) => p.toJson()).toList(),
      'calendarArchive': _calendarArchive,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 从 JSON 字符串导入数据（用户粘贴备份内容）
  /// 会替换当前所有投资组合和日历归档
  /// 返回导入的组合数量，失败返回 null
  Future<int?> importFromLocalJson(String jsonStr) async {
    try {
      debugPrint('[$investmentType] 开始解析 JSON, 长度: ${jsonStr.length}');
      final decoded = json.decode(jsonStr);

      // ★ 兼容两种格式：
      // 格式A: {"type":"热点投资","portfolios":[...], "calendarArchive":[...]}  (标准导出格式)
      // 格式B: [{"id":...,...}]  (直接是 portfolios 列表)
      final Map<String, dynamic> data;

      if (decoded is Map) {
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else {
          data = Map<String, dynamic>.from(decoded as Map);
        }
        debugPrint('[$investmentType] JSON 是 Map 格式, keys: ${data.keys.toList()}');
      } else if (decoded is List) {
        // 直接是列表格式，包装为 Map
        debugPrint('[$investmentType] JSON 是 List 格式, 长度: ${(decoded as List).length}');
        data = {'portfolios': decoded as List};
      } else {
        debugPrint('[$investmentType] JSON 格式不支持: ${decoded.runtimeType}');
        return null;
      }

      // 校验：必须包含 portfolios 字段
      final raw = data['portfolios'];
      if (raw is! List) {
        debugPrint('[$investmentType] portfolios 字段不存在或不是 List: ${raw?.runtimeType}');
        return null;
      }

      debugPrint('[$investmentType] portfolios 列表长度: ${raw.length}');
      final parsed = <HotInvestmentPortfolio>[];
      final errors = <String>[];
      for (final item in raw) {
        try {
          parsed.add(HotInvestmentPortfolio.fromJson(Map<String, dynamic>.from(item as Map)));
        } catch (e) {
          errors.add(e.toString());
          debugPrint('[$investmentType] 本地导入：跳过一条无效记录: $e');
        }
      }

      debugPrint('[$investmentType] 成功解析 ${parsed.length} 个组合, 失败 ${errors.length} 个');

      // ★ 修复：即使 parsed 为空，如果有 calendarArchive 数据也应该保存
      // 不再 return null，而是返回 0（表示没有组合但有归档数据）
      if (parsed.isEmpty && !data.containsKey('calendarArchive')) {
        debugPrint('[$investmentType] 无 portfolios 且无 calendarArchive，返回 null');
        return null;
      }

      if (parsed.isNotEmpty) {
        _portfolios = parsed;
      }
      debugPrint('[$investmentType] 本地导入成功：${parsed.length} 个组合');

      // 恢复日历归档
      if (data.containsKey('calendarArchive') && data['calendarArchive'] is List) {
        final archiveList = (data['calendarArchive'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _calendarArchive = archiveList;
        debugPrint('[$investmentType] 本地导入成功：${archiveList.length} 条归档');
      }

      await _save();
      await _saveArchive();
      notifyListeners();
      return parsed.length;
    } catch (e) {
      debugPrint('[$investmentType] 本地导入失败: $e');
      return null;
    }
  }

  // ============================================================
  // 工具方法
  // ============================================================

  /// 热点投资硬止损上限：5%
  static const double kHardStopLossCap = 0.05;

  /// 从硬止损文本解析百分比，并强制不超过硬止损上限 5%
  /// "买入价-3%" → 0.03, "止损-8%" → 0.05（截断）, 默认 0.05
  static double _parseStopLossPercent(String? text) {
    double raw;
    if (text == null || text.isEmpty) {
      raw = 0.05;
    } else {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(text);
      if (match != null) {
        final val = double.tryParse(match.group(1)!) ?? 5;
        raw = val / 100.0;
      } else {
        // 支持纯数字格式如 "-4" "5"
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
        if (numMatch != null) {
          final val = double.tryParse(numMatch.group(1)!) ?? 5;
          raw = val / 100.0;
        } else {
          raw = 0.05;
        }
      }
    }
    // 硬止损上限：最高不超过 5%，低于 5% 按实际建议
    if (raw > kHardStopLossCap) {
      debugPrint('[热点投资] 止损比例 ${(raw * 100).toStringAsFixed(1)}% 超过硬上限 ${(kHardStopLossCap * 100).toStringAsFixed(0)}%，已截断');
      return kHardStopLossCap;
    }
    return raw;
  }

  /// 截断标题
  static String _truncateTitle(String title, int maxLen) {
    if (title.length <= maxLen) return title;
    return '${title.substring(0, maxLen)}...';
  }

  /// 判断某日是否为交易日（排除周末+节假日）
  static Future<bool> _isTradingDay(DateTime date) async {
    // 周末直接跳过
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    // 排除A股节假日
    if (!_isSecuritiesTradingDay(date)) {
      return false;
    }
    return true;
  }

  /// A股节假日列表（2026年，与日历组件保持一致）
  static const Set<String> _kHolidayDates = {
    '2026-01-01',
    '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-21', '2026-02-22',
    '2026-04-04', '2026-04-05', '2026-04-06',
    '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
    '2026-06-19', '2026-06-20', '2026-06-21',
    '2026-09-25', '2026-09-26', '2026-09-27',
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    '2026-10-05', '2026-10-06', '2026-10-07',
  };

  /// 判断某日是否为证券交易日（排除周末+节假日）
  static bool _isSecuritiesTradingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (_kHolidayDates.contains(dateStr)) {
      return false;
    }
    return true;
  }

  /// 计算从建仓到现在的证券交易日数（排除周末+节假日）
  static Future<int> _countTradingDays(DateTime from, DateTime to) async {
    int count = 0;
    var current = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);

    while (!current.isAfter(end)) {
      if (_isSecuritiesTradingDay(current)) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }
}
