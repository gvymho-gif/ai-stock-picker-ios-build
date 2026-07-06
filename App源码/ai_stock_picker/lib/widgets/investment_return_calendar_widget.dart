/// 投资收益日历组件
///
/// 聚合所有持仓的每日收益+持仓标记+今日浮动盈亏，以月历形式展示。
/// 同时融合交易日记录数据，用统一简洁风格呈现。
/// 默认折叠，点击展开查看完整日历。点击任意日期可查看当天详细交易数据。
/// ▲ 红 = 盈利  /  ▼ 绿 = 亏损  /  ● = 交易日

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../services/hot_investment_service.dart';
import '../services/local_data_service.dart';
import '../models/hot_investment_model.dart';
import '../models/speed_investment_model.dart';

import '../services/speed_investment_service.dart';

class InvestmentReturnCalendarWidget extends StatefulWidget {
  final HotInvestmentService? hotService;
  final SpeedInvestmentService? speedService;

  const InvestmentReturnCalendarWidget({Key? key, this.hotService, this.speedService}) : super(key: key);

  @override
  State<InvestmentReturnCalendarWidget> createState() => _InvestmentReturnCalendarWidgetState();
}

class _InvestmentReturnCalendarWidgetState extends State<InvestmentReturnCalendarWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late DateTime _currentMonth;
  late AnimationController _arrowController;
  late Animation<double> _arrowTurns;

  // 行情状态
  final LocalDataService _api = LocalDataService();
  Map<String, Map<String, dynamic>> _liveQuotes = {}; // 增量合并的行情数据
  Timer? _refreshTimer;
  bool _loadingQuotes = false;

  // 交易日缓存：从 TradingDayCloudService 加载的已知交易日日期集合
  Set<String> _knownTradingDates = {};
  bool _tradingDatesLoaded = false;

  // 通用数据访问 — 支持热点/轻量/速度投资
  List<dynamic> get _portfolios =>
      widget.hotService?.portfolios ?? widget.speedService!.portfolios;
  List<Map<String, dynamic>> get _calendarArchive =>
      widget.hotService?.calendarArchive ?? widget.speedService!.calendarArchive;
  DateTime? get _firstTradeDate =>
      widget.hotService?.firstTradeDate ?? widget.speedService!.firstTradeDate;
  bool get _isSpeedMode => widget.speedService != null;

  /// 跨模型判断持仓状态是否为"持有中"
  bool _isHolding(dynamic pos) {
    try {
      final status = pos.status;
      if (_isSpeedMode) {
        return status.toString() == 'SpeedPositionStatus.holding';
      }
      return status == PositionStatus.holding;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _arrowController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _arrowTurns = Tween<double>(begin: 0.0, end: 0.5).animate(_arrowController);
    _loadKnownTradingDates();
  }

  /// 从本地存储加载交易日记录，用于排除节假日
  Future<void> _loadKnownTradingDates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('trading_day_records');
      if (jsonStr == null || jsonStr.isEmpty) {
        _tradingDatesLoaded = true;
        return;
      }
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final dates = <String>{};
      for (final j in jsonList) {
        final date = j is Map ? j['date']?.toString() : null;
        if (date != null) dates.add(date);
      }
      _knownTradingDates = dates;
      _tradingDatesLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {
      _tradingDatesLoaded = true;
    }
  }

  @override
  void dispose() {
    _arrowController.dispose();
    _stopRefresh();
    super.dispose();
  }

  // ================================================================
  // 展开/折叠 + 定时刷新
  // ================================================================

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _arrowController.forward();
        _startRefresh();
      } else {
        _arrowController.reverse();
        _stopRefresh();
      }
    });
  }

  void _startRefresh() {
    _stopRefresh();
    _refreshQuotes();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshQuotes());
  }

  void _stopRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _refreshQuotes() async {
    if (_loadingQuotes) return;
    _loadingQuotes = true;
    try {
      final codes = <String>{};
      for (final p in _portfolios) {
        for (final pos in p.positions) {
          if (_isHolding(pos)) {
            codes.add(pos.stockCode);
          }
        }
      }
      if (codes.isEmpty) {
        if (mounted && _liveQuotes.isNotEmpty) setState(() => _liveQuotes = {});
        return;
      }
      // 使用轻量行情API + 增量合并，避免网络波动闪烁
      final newQuotes = <String, Map<String, dynamic>>{};
      for (final code in codes) {
        try {
          final quote = await _api.fetchQuickQuote(code);
          if (quote != null && _safePrice(quote) > 0) {
            newQuotes[code] = quote;
          }
        } catch (_) {}
      }
      if (mounted) {
        final updated = Map<String, Map<String, dynamic>>.from(_liveQuotes);
        updated.addAll(newQuotes); // 增量合并：只覆盖成功获取的
        setState(() => _liveQuotes = updated);
      }
    } finally {
      _loadingQuotes = false;
    }
  }

  static double _safePrice(Map<String, dynamic> quote) {
    return (quote['price'] as num?)?.toDouble() ?? 0;
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  // ================================================================
  // 数据聚合
  // ================================================================

  Map<String, _DayReturn> _aggregateReturns() {
    final result = <String, _DayReturn>{};
    final now = DateTime.now();
    final todayKey = _dateKey(now);

    if (_isSpeedMode) {
      // ── 极速投资日历数据聚合 ──
      //
      // 业务规范：
      // - 建仓日(buyDate)：只有买入没有卖出，结算收益=0%，仅显示浮动
      // - 卖出日(sellDate)：卖出前一天的股票，结算收益计入当天；同时新买入的显示浮动
      // - 已结算的组合：从 calendarArchive 取结算数据
      // - 活跃组合：取浮动收益（实时价格 - 买入价）
      // - 待买入组合：buyDate标记为持仓日，无收益数据

      // 1. 已结算记录（来自归档）
      for (final entry in _calendarArchive) {
        final dateStr = entry['date'] as String? ?? '';
        if (dateStr.isEmpty) continue;
        final ret = (entry['return'] as num?)?.toDouble() ?? 0.0;
        final key = dateStr;
        final existing = result[key];
        if (existing != null) {
          existing.settledReturn += ret;
          existing.settledCount++;
        } else {
          // 极速投资 ret 是百分比（如2.5），settledCost=-1标记百分比模式
          result[key] = _DayReturn(ret, -1, 1, 0, 0);
        }
      }

      // 2. 活跃(active)组合：结算收益 + 浮动收益
      for (final portfolio in _portfolios) {
        if (portfolio.status != SpeedPortfolioStatus.active) continue;
        final buyDateKey = _dateKey(portfolio.buyDate);
        final sellDateKey = _dateKey(portfolio.sellDate);

        // 建仓日：结算收益=0（只有买入无卖出），标记为持仓
        if (result[buyDateKey] == null) {
          result[buyDateKey] = _DayReturn(0, 0, 0, 0, 0); // settledCount=0表示无结算
        }

        // 活跃组合的浮动收益（当前持仓盈亏显示在卖出日当天）
        for (final pos in portfolio.positions) {
          if (pos.status != SpeedPositionStatus.holding) continue;
          final quote = _liveQuotes[pos.stockCode];
          final price = quote != null ? _safePrice(quote) : 0.0;
          if (price > 0 && pos.buyPrice > 0) {
            final floatingPnl = (price - pos.buyPrice) * pos.shares;
            final existing = result[sellDateKey];
            if (existing != null) {
              existing.floatingReturn += floatingPnl;
              existing.floatingCount++;
            } else {
              result[sellDateKey] = _DayReturn(0, 0, 0, floatingPnl, 1);
            }
          }
        }
      }

      // 3. 待买入(pending)组合：标记建仓日为持仓日
      for (final portfolio in _portfolios) {
        if (portfolio.status != SpeedPortfolioStatus.pending) continue;
        final buyDateKey = _dateKey(portfolio.buyDate);
        if (result[buyDateKey] == null) {
          result[buyDateKey] = _DayReturn(0, 0, 0, 0, 0);
        }
      }

      return result;
    }

    // ── 热点/轻量投资：已结算收益 ──
    // 活跃组合中的已结算持仓（仅统计交易日结算）
    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        if (pos.sellTime == null || pos.returnAmount == null) continue;
        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status == PositionStatus.unfilled) continue;
        // 仅统计在交易日发生的结算
        if (!_isSecuritiesTradingDay(pos.sellTime!)) continue;
        final key = _dateKey(pos.sellTime!);
        final existing = result[key];
        if (existing != null) {
          existing.settledReturn += pos.returnAmount!;
          existing.settledCost += pos.investedAmount;
          existing.settledCount++;
        } else {
          result[key] = _DayReturn(pos.returnAmount!, pos.investedAmount, 1, 0, 0);
        }
      }
    }

    // 永久归档中的历史结算记录（仅统计交易日结算）
    for (final entry in _calendarArchive) {
      final sellTime = DateTime.parse(entry['sellTime'] as String);
      // 仅统计在交易日发生的结算
      if (!_isSecuritiesTradingDay(sellTime)) continue;
      final returnAmount = (entry['returnAmount'] as num?)?.toDouble() ?? 0;
      final investedAmt = (entry['investedAmount'] as num?)?.toDouble() ?? 0;
      final key = _dateKey(sellTime);
      final existing = result[key];
      if (existing != null) {
        existing.settledReturn += returnAmount;
        existing.settledCost += investedAmt;
        existing.settledCount++;
      } else {
        result[key] = _DayReturn(returnAmount, investedAmt, 1, 0, 0);
      }
    }

    // ── 今日浮动盈亏（未实现）──
    // 仅计入今日，与已结算收益分开存储
    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status != PositionStatus.holding) continue;
        final quote = _liveQuotes[pos.stockCode];
        final price = quote != null ? _safePrice(quote) : 0.0;
        if (price <= 0) continue;

        final priceDiff = price - pos.buyPrice;
        double floatingPnl;
        if (priceDiff.abs() < 0.001 && quote != null) {
          final changePct = (quote['change_pct'] as num?)?.toDouble() ?? 0.0;
          floatingPnl = changePct / 100 * pos.investedAmount;
        } else {
          floatingPnl = priceDiff * pos.shares;
        }

        final existing = result[todayKey];
        if (existing != null) {
          existing.floatingReturn += floatingPnl;
          existing.floatingCount++;
        } else {
          result[todayKey] = _DayReturn(0, 0, 0, floatingPnl, 1);
        }
      }
    }

    return result;
  }

  Set<String> _aggregateHoldingDates() {
    final result = <String>{};
    final now = DateTime.now();

    if (_isSpeedMode) {
      // 速度投资：active/settled 组合标记持仓日期范围
      for (final portfolio in _portfolios) {
        if (portfolio.status == SpeedPortfolioStatus.pending) continue;
        final start = DateTime(portfolio.buyDate.year, portfolio.buyDate.month, portfolio.buyDate.day);
        final end = DateTime(portfolio.sellDate.year, portfolio.sellDate.month, portfolio.sellDate.day);
        var cursor = start;
        while (!cursor.isAfter(end)) {
          if (_isSecuritiesTradingDay(cursor)) {
            result.add(_dateKey(cursor));
          }
          cursor = cursor.add(const Duration(days: 1));
        }
      }
      return result;
    }

    // ── 热点/轻量：活跃组合的持仓范围 ──
    // 仅标记证券交易日（排除周末+节假日），非交易日不显示持仓标记
    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status == PositionStatus.unfilled) continue;
        if (pos.investedAmount <= 0) continue; // 未投入不标记
        final start = pos.buyTime;
        final end = pos.sellTime ?? now;
        var cursor = DateTime(start.year, start.month, start.day);
        final endDate = DateTime(end.year, end.month, end.day);
        while (!cursor.isAfter(endDate)) {
          if (_isSecuritiesTradingDay(cursor)) {
            result.add(_dateKey(cursor));
          }
          cursor = cursor.add(const Duration(days: 1));
        }
      }
    }

    // 归档中的历史持仓范围（仅标记交易日）
    for (final entry in _calendarArchive) {
      final buyTime = DateTime.parse(entry['buyTime'] as String);
      final sellTime = DateTime.parse(entry['sellTime'] as String);
      var cursor = DateTime(buyTime.year, buyTime.month, buyTime.day);
      final endDate = DateTime(sellTime.year, sellTime.month, sellTime.day);
      while (!cursor.isAfter(endDate)) {
        if (_isSecuritiesTradingDay(cursor)) {
          result.add(_dateKey(cursor));
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    return result;
  }

  _TodayPnl? _calcTodayPnl() {
    // 非交易日不计算持仓浮动盈亏（周末/节假日不显示浮动数据）
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!_isSecuritiesTradingDay(today)) return null;

    double totalCost = 0;
    double totalMarket = 0;
    int holdingCount = 0;

    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        // 与 _getDayPositions 保持完全一致的过滤条件
        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status == PositionStatus.unfilled) continue;
        if (pos.investedAmount <= 0) continue;
        final buyDate = DateTime(pos.buyTime.year, pos.buyTime.month, pos.buyTime.day);
        final endDate = pos.sellTime != null
            ? DateTime(pos.sellTime!.year, pos.sellTime!.month, pos.sellTime!.day)
            : today;
        if (today.isBefore(buyDate) || today.isAfter(endDate)) continue;

        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status != PositionStatus.holding) continue;
        final quote = _liveQuotes[pos.stockCode];
        final price = quote != null ? _safePrice(quote) : 0.0;
        if (price <= 0) continue;
        totalCost += pos.investedAmount;
        totalMarket += price * pos.shares;
        holdingCount++;
      }
    }

    if (holdingCount == 0 || totalCost == 0) return null;
    final pnl = totalMarket - totalCost;
    final pnlRate = pnl / totalCost;
    return _TodayPnl(pnl, pnlRate, holdingCount);
  }

  /// 获取某一天的所有详细交易数据（含活跃组合 + 永久归档）
  List<_DayPositionDetail> _getDayPositions(String dateKey) {
    final target = _parseDateKey(dateKey);
    final result = <_DayPositionDetail>[];

    // ── 极速投资分支：按组合级别日期范围匹配 ──
    if (_isSpeedMode) {
      for (final portfolio in _portfolios) {
        // 仅 active/settled 状态的组合出现在日历详情中
        if (portfolio.status == SpeedPortfolioStatus.pending) continue;

        final pBuyDate = DateTime(portfolio.buyDate.year, portfolio.buyDate.month, portfolio.buyDate.day);
        final pSellDate = DateTime(portfolio.sellDate.year, portfolio.sellDate.month, portfolio.sellDate.day);
        // 目标日期不在组合持仓范围内 → 跳过
        if (target.isBefore(pBuyDate) || target.isAfter(pSellDate)) continue;

        final sellDateKey = _dateKey(portfolio.sellDate);

        for (final pos in portfolio.positions) {
          // pending 组合的 positions 没有实际数据，跳过
          if (pos.investedAmount <= 0 && pos.status == SpeedPositionStatus.holding) continue;

          final settledOnDate = pos.status == SpeedPositionStatus.settled && dateKey == sellDateKey;
          final speedLabel = pos.status == SpeedPositionStatus.settled ? '已结算' : '持仓中';

          result.add(_DayPositionDetail(
            stockName: pos.stockName,
            stockCode: pos.stockCode,
            buyPrice: pos.buyPrice > 0 ? pos.buyPrice : (pos.plannedAmount > 0 ? 0 : 0),
            buyTime: pos.buyTime ?? portfolio.buyDate,
            investedAmount: pos.investedAmount > 0 ? pos.investedAmount : pos.plannedAmount,
            shares: pos.shares > 0 ? pos.shares : (pos.buyPrice > 0 ? (pos.plannedAmount / pos.buyPrice / 100).floor() * 100 : 0),
            status: PositionStatus.holding, // 占位，实际用 speedStatusLabel
            sellPrice: pos.sellPrice,
            sellTime: pos.sellTime,
            returnAmount: pos.returnAmount,
            returnRate: pos.returnRate,
            stopLossPercent: 0.05,
            portfolioName: '极速投资 ${portfolio.createTime.month}/${portfolio.createTime.day}',
            settledOnThisDate: settledOnDate,
            currentPrice: _liveQuotes.containsKey(pos.stockCode) ? _safePrice(_liveQuotes[pos.stockCode]!) : null,
            isSpeedMode: true,
            speedStatusLabel: speedLabel,
          ));
        }
      }
      return result;
    }

    // ── 热点/轻量投资分支 ──
    // 活跃组合 — 排除unfilled（未建仓不出现在详情中）
    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        if (pos.status == PositionStatus.unfilled) continue;
        if (pos.investedAmount <= 0) continue;
        final buyDate = DateTime(pos.buyTime.year, pos.buyTime.month, pos.buyTime.day);
        final endDate = pos.sellTime != null
            ? DateTime(pos.sellTime!.year, pos.sellTime!.month, pos.sellTime!.day)
            : DateTime.now();

        if (target.isBefore(buyDate) || target.isAfter(endDate)) continue;

        result.add(_DayPositionDetail(
          stockName: pos.stockName,
          stockCode: pos.stockCode,
          buyPrice: pos.buyPrice,
          buyTime: pos.buyTime,
          investedAmount: pos.investedAmount,
          shares: pos.shares,
          status: pos.status,
          sellPrice: pos.sellPrice,
          sellTime: pos.sellTime,
          returnAmount: pos.returnAmount,
          returnRate: pos.returnRate,
          stopLossPercent: pos.stopLossPercent,
          portfolioName: portfolio.name,
          settledOnThisDate: pos.sellTime != null && _dateKey(pos.sellTime!) == dateKey,
          currentPrice: _liveQuotes.containsKey(pos.stockCode) ? _safePrice(_liveQuotes[pos.stockCode]!) : null,
        ));
      }
    }

    // 永久归档
    for (final entry in _calendarArchive) {
      final buyTime = DateTime.parse(entry['buyTime'] as String);
      final sellTime = DateTime.parse(entry['sellTime'] as String);
      final buyDate = DateTime(buyTime.year, buyTime.month, buyTime.day);
      final endDate = DateTime(sellTime.year, sellTime.month, sellTime.day);

      if (target.isBefore(buyDate) || target.isAfter(endDate)) continue;

      final entryStatus = PositionStatus.values.firstWhere(
        (e) => e.name == entry['status'],
        orElse: () => PositionStatus.stopProfit,
      );
      final sellOnThisDate = _dateKey(sellTime) == dateKey;

      result.add(_DayPositionDetail(
        stockName: entry['stockName'] as String,
        stockCode: entry['stockCode'] as String,
        buyPrice: (entry['buyPrice'] as num).toDouble(),
        buyTime: buyTime,
        investedAmount: (entry['investedAmount'] as num?)?.toDouble() ?? 0,
        shares: entry['shares'] as int,
        status: entryStatus,
        sellPrice: entry['sellPrice'] != null ? (entry['sellPrice'] as num).toDouble() : null,
        sellTime: sellTime,
        returnAmount: entry['returnAmount'] != null ? (entry['returnAmount'] as num).toDouble() : null,
        returnRate: entry['returnRate'] != null ? (entry['returnRate'] as num).toDouble() : null,
        stopLossPercent: (entry['stopLossPercent'] as num?)?.toDouble() ?? 0.05,
        portfolioName: entry['portfolioName'] as String? ?? '历史组合',
        settledOnThisDate: sellOnThisDate,
        currentPrice: null, // 归档数据无实时行情
      ));
    }

    return result;
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  DateTime _parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  // ================================================================
  // 日期详情弹窗
  // ================================================================

  void _showDayDetail(String dateKey, int dayNum) {
    final positions = _getDayPositions(dateKey);
    if (positions.isEmpty) return;

    // 预计算所有组合摘要数据
    final grouped = <String, List<_DayPositionDetail>>{};
    for (final p in positions) {
      grouped.putIfAbsent(p.portfolioName, () => []).add(p);
    }

    final groupSummaries = _buildGroupSummaries(grouped);

    final colors = AppColors.of(context);
    final dt = _parseDateKey(dateKey);
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[dt.weekday - 1];
    final dateLabel = '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} 星期$weekday';

    final grandTotal = groupSummaries.values
        .fold<double>(0, (sum, s) => sum + s.settled); // settled 已统一为实际盈亏

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        // 状态变量放在 StatefulBuilder 外部，避免每次重绘被重置
        String? selectedGroup;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void showDetail(String groupName) {
              setSheetState(() => selectedGroup = groupName);
            }
            void backToSummary() {
              setSheetState(() => selectedGroup = null);
            }

            return DraggableScrollableSheet(
              initialChildSize: selectedGroup == null ? 0.55 : 0.75,
              minChildSize: 0.35,
              maxChildSize: 0.85,
              expand: false,
              builder: (ctx, scrollController) {
                if (selectedGroup != null) {
                  return _buildGroupDetailView(
                    colors, dateLabel, selectedGroup!,
                    grouped[selectedGroup]!, groupSummaries[selectedGroup]!,
                    scrollController, backToSummary, grandTotal,
                  );
                }
                return _buildPortfolioSummaryView(
                  colors, dateLabel, grouped, groupSummaries,
                  scrollController, showDetail, grandTotal,
                );
              },
            );
          },
        );
      },
    );
  }

  /// 计算所有组合的摘要数据
  Map<String, _GroupSummary> _buildGroupSummaries(
    Map<String, List<_DayPositionDetail>> grouped,
  ) {
    final summaries = <String, _GroupSummary>{};
    for (final entry in grouped.entries) {
      double settled = 0;
      double settledCost = 0;
      double floating = 0;
      int settledCount = 0;
      int holdingCount = 0;
      double cost = 0;
      for (final p in entry.value) {
        if (p.settledOnThisDate) {
          // 不同模块的 returnAmount 语义不同：
          // - 极速投资(v2.0.6+)：returnAmount 已经是利润 = sell_total - invested
          // - 极速投资(老数据)：returnAmount 是总回款，需减去投入
          // - 热点/轻量投资：直接是实际盈亏
          if (p.isSpeedMode) {
            // ★ 修复：returnAmount 已经是利润，直接累加
            settled += p.returnAmount ?? 0;
          } else {
            settled += p.returnAmount ?? 0;
          }
          settledCost += p.investedAmount;
          settledCount++;
        } else {
          if (p.currentPrice != null && p.currentPrice! > 0) {
            final priceDiff = p.currentPrice! - p.buyPrice;
            if (priceDiff.abs() < 0.001) {
              final quote = _liveQuotes[p.stockCode];
              final changePct = quote != null ? ((quote['change_pct'] as num?)?.toDouble() ?? 0.0) : 0.0;
              floating += changePct / 100 * p.investedAmount;
            } else {
              floating += priceDiff * p.shares;
            }
            cost += p.investedAmount;
          }
          holdingCount++;
        }
      }
      summaries[entry.key] = _GroupSummary(
        settled: settled, settledCost: settledCost, settledCount: settledCount,
        floating: floating, holdingCount: holdingCount,
        floatingRate: cost > 0 ? floating / cost : 0,
      );
    }
    return summaries;
  }

  /// 第一级：组合摘要列表
  Widget _buildPortfolioSummaryView(
    AppColorScheme colors,
    String dateLabel,
    Map<String, List<_DayPositionDetail>> grouped,
    Map<String, _GroupSummary> summaries,
    ScrollController scrollController,
    void Function(String) onTapGroup,
    double grandTotal,
  ) {
    return Column(children: [
      Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: colors.textHint.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // 日期标题 + 总合计
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(children: [
          Icon(Icons.calendar_today, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(dateLabel,
            style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (grandTotal != 0)
            Text(
              '${grandTotal >= 0 ? "▲" : "▼"}${_fmtAmount(grandTotal)}',
              style: TextStyle(
                color: grandTotal >= 0 ? colors.up : colors.down,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
        ]),
      ),

      if (grouped.length > 1)
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.lg, top: AppSpacing.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${grouped.length}个投资组合',
              style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
          ),
        ),

      const SizedBox(height: AppSpacing.md),

      // 组合摘要卡片列表
      Expanded(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          children: [
            for (final entry in grouped.entries)
              _buildPortfolioSummaryCard(colors, entry.key, summaries[entry.key]!, onTapGroup),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    ]);
  }

  /// 组合摘要卡片（可点击进入明细）
  Widget _buildPortfolioSummaryCard(
    AppColorScheme colors,
    String name,
    _GroupSummary summary,
    void Function(String) onTap,
  ) {
    // 组合摘要：settled 已统一为实际盈亏
    final totalReturn = summary.settled;
    final totalCost = summary.settledCost;
    final isProfit = totalReturn >= 0;
    final totalRate = totalCost > 0 ? totalReturn / totalCost : 0.0;

    final parts = <String>[];
    if (summary.settledCount > 0) {
      parts.add('结算 ${summary.settledCount}笔');
    }
    if (summary.holdingCount > 0) {
      parts.add('持仓 ${summary.holdingCount}只');
    }

    return GestureDetector(
      onTap: () => onTap(name),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.hotInvestAccent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.border.withOpacity(0.3)),
        ),
        child: Row(children: [
          // 左侧：组合名 + 子信息
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.whatshot, size: 14, color: colors.hotInvestAccent),
                const SizedBox(width: 6),
                Text(name,
                  style: AppText.body2.copyWith(
                    color: colors.textPrimary, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
              const SizedBox(height: 4),
              Text(parts.join(' · '),
                style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
            ]),
          ),

          // 右侧：实际盈亏金额 + 收益率
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isProfit ? "+" : ""}${_fmtAmount(totalReturn)}',
              style: TextStyle(
                color: isProfit ? colors.up : colors.down,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '收益率 ${isProfit ? "+" : ""}${(totalRate * 100).abs().toStringAsFixed(2)}%',
              style: TextStyle(
                color: isProfit ? colors.up : colors.down,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),

          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: colors.textHint),
        ]),
      ),
    );
  }

  /// 第二级：单个组合的明细视图
  Widget _buildGroupDetailView(
    AppColorScheme colors,
    String dateLabel,
    String groupName,
    List<_DayPositionDetail> positions,
    _GroupSummary summary,
    ScrollController scrollController,
    VoidCallback onBack,
    double grandTotal,
  ) {
    return Column(children: [
      Container(
        margin: const EdgeInsets.only(top: AppSpacing.sm),
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: colors.textHint.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // 标题行：返回 + 组合名 + 组合合计
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.arrow_back_ios, size: 16, color: colors.primary),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(groupName,
              style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (grandTotal != 0)
            Text(
              '${grandTotal >= 0 ? "▲" : "▼"}${_fmtAmount(grandTotal)}',
              style: TextStyle(
                color: grandTotal >= 0 ? colors.up : colors.down,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
        ]),
      ),

      const SizedBox(height: AppSpacing.md),

      // 明细列表
      Expanded(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          children: [
            _buildPortfolioGroup(colors, groupName, positions, summary),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    ]);
  }

  Widget _buildPortfolioGroup(
    AppColorScheme colors,
    String portfolioName,
    List<_DayPositionDetail> positions,
    _GroupSummary summary,
  ) {
    final hasSettled = summary.settledCount > 0;
    final hasHolding = summary.holdingCount > 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 组合标题行
      _buildPortfolioHeader(colors, portfolioName, summary),
      const SizedBox(height: AppSpacing.sm),

      // 持仓卡片列表
      ...positions.map((p) => _buildDetailCard(p, colors)),

      // 当日结算小结
      if (hasSettled && hasHolding) ...[
        const SizedBox(height: AppSpacing.xs),
        _buildGroupSummaryLine(colors, summary),
      ],
    ]);
  }

  Widget _buildPortfolioHeader(AppColorScheme colors, String name, _GroupSummary summary) {
    final hasSettled = summary.settledCount > 0;
    final hasHolding = summary.holdingCount > 0;

    final List<Widget> badges = [];
    if (hasSettled) {
      final settledPnl = summary.settled; // 已统一为实际盈亏
      final isProfit = settledPnl >= 0;
      badges.add(_buildBadge(
        '${isProfit ? "+" : ""}${_fmtAmount(settledPnl)}',
        isProfit ? colors.up : colors.down,
        colors,
      ));
    }
    if (hasHolding) {
      badges.add(_buildBadge(
        '${summary.holdingCount}只持仓',
        colors.hotInvestAccent,
        colors,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.hotInvestAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(children: [
        Icon(Icons.whatshot, size: 16, color: colors.hotInvestAccent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(name,
            style: AppText.body2.copyWith(
              color: colors.textPrimary, fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...badges,
      ]),
    );
  }

  Widget _buildBadge(String text, Color color, AppColorScheme colors) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(
        color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildGroupSummaryLine(AppColorScheme colors, _GroupSummary summary) {
    final isProfit = summary.floating >= 0;
    return Row(children: [
      Text('持仓浮动: ',
        style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
      Text('${isProfit ? "▲" : "▼"}${summary.floatingRate.abs().toStringAsFixed(2)}%',
        style: TextStyle(
          color: isProfit ? colors.up : colors.down,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        )),
      const SizedBox(width: 6),
      Text(_fmtAmount(summary.floating),
        style: TextStyle(
          color: isProfit ? colors.up : colors.down,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        )),
    ]);
  }

  Widget _buildDetailCard(_DayPositionDetail p, AppColorScheme colors) {
    final isSettled = p.settledOnThisDate;
    // returnAmount 语义：
    // - 极速投资(v2.0.6+)：returnAmount 已经是利润 = sell_total - invested
    // - 热点/轻量投资：直接是真实盈亏
    final pnl = isSettled
        ? (p.isSpeedMode
            ? (p.returnAmount ?? 0)
            : (p.returnAmount ?? 0))
        : _calcCardPnl(p);
    final pnlRate = isSettled
        ? (p.returnRate ?? 0)
        : (p.buyPrice > 0 ? pnl / p.investedAmount : 0.0);
    final isProfit = pnl >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 第一行：股票名 + 代码
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(p.stockName,
                style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(width: AppSpacing.xs),
              Text(p.stockCode,
                style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
            ]),
          ),
          // 状态标签
          if (p.isSpeedMode && p.speedStatusLabel != null)
            _buildStatusChip(p.speedStatusLabel!, isProfit ? colors.up : colors.down, colors)
          else if (isSettled)
            _buildStatusChip(_statusLabel(p.status), isProfit ? colors.up : colors.down, colors)
          else
            _buildStatusChip('持仓中', colors.hotInvestAccent, colors),
        ]),
        const SizedBox(height: AppSpacing.sm),

        // 分隔线
        Divider(color: colors.border.withOpacity(0.3), height: 1),
        const SizedBox(height: AppSpacing.sm),

        // 字段信息（表格样式）
        _buildInfoRow('建仓价', '¥${p.buyPrice.toStringAsFixed(2)}', colors),
        const SizedBox(height: 4),
        if (isSettled && p.sellPrice != null) ...[
          _buildInfoRow('结算价', '¥${p.sellPrice!.toStringAsFixed(2)}', colors),
          const SizedBox(height: 4),
        ],
        _buildInfoRow('投入总金额', '¥${p.investedAmount.toStringAsFixed(0)}', colors),
        const SizedBox(height: 4),
        _buildInfoRow('股数', '${p.shares}股', colors),
        const SizedBox(height: 4),
        _buildInfoRow(
          '回报率',
          '${isProfit ? "▲" : "▼"}${(pnlRate * 100).abs().toStringAsFixed(2)}%${isSettled ? "" : "（浮动）"}',
          colors,
          valueColor: isProfit ? colors.up : colors.down,
        ),
        const SizedBox(height: 4),
        _buildInfoRow(
          isSettled ? '结算金额' : '浮动盈亏',
          '${isProfit ? "+" : ""}${_fmtAmount(pnl)}',
          colors,
          valueColor: isProfit ? colors.up : colors.down,
        ),
      ]),
    );
  }

  /// 信息行：标签 + 值
  Widget _buildInfoRow(String label, String value, AppColorScheme colors, {Color? valueColor}) {
    return Row(children: [
      SizedBox(
        width: 80,
        child: Text(label,
          style: AppText.caption.copyWith(color: colors.textHint, fontSize: 12)),
      ),
      Text(value,
        style: TextStyle(
          color: valueColor ?? colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        )),
    ]);
  }

  /// 计算单只持仓的浮动盈亏金额
  double _calcCardPnl(_DayPositionDetail p) {
    final price = p.currentPrice;
    if (price == null || price <= 0) return 0;
    final priceDiff = price - p.buyPrice;
    if (priceDiff.abs() < 0.001) {
      final quote = _liveQuotes[p.stockCode];
      final changePct = quote != null ? ((quote['change_pct'] as num?)?.toDouble() ?? 0.0) : 0.0;
      return changePct / 100 * p.investedAmount;
    }
    return priceDiff * p.shares;
  }

  Widget _buildStatusChip(String label, Color color, AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  String _statusLabel(PositionStatus s) {
    switch (s) {
      case PositionStatus.stopProfit: return '止盈';
      case PositionStatus.stopLoss: return '止损';
      case PositionStatus.timeLiquidated: return '到期清仓';
      case PositionStatus.unfilled: return '待激活';
      default: return '已结算';
    }
  }

  // ================================================================
  // Build 主入口
  // ================================================================

  /// 计算全量累计数据（供标题栏使用，跨月份累计）
  /// 返回 {monthReturnRate, monthTotalReturnAmount}
  Map<String, double> _calcMonthSummary() {
    final dayReturns = _aggregateReturns();
    final kFirstTradeDate = _firstTradeDate ??
        (_isSpeedMode && _portfolios.isNotEmpty
            ? (_portfolios.first as dynamic).createTime as DateTime?
            : null);
    if (kFirstTradeDate == null) return {'monthReturnRate': 0.0, 'monthTotalReturnAmount': 0.0};

    double sumDailyRates = 0.0;
    double monthTotalReturnAmount = 0.0;
    bool hasSettledData = false;

    // 非速度模式：遍历所有交易日，不限制月份
    if (!_isSpeedMode) {
      for (final entry in dayReturns.entries) {
        monthTotalReturnAmount += entry.value.settledReturn;
        if (entry.value.settledCost > 0) {
          sumDailyRates += entry.value.settledReturn / entry.value.settledCost;
          hasSettledData = true;
        }
      }
    } else {
      // 速度模式：从所有已结算日获取百分比累加
      for (final entry in dayReturns.entries) {
        sumDailyRates += entry.value.settledReturn; // 已是百分比值
        hasSettledData = true;
      }
      // 从所有已结算 position 获取实际盈亏金额（不限月份）
      // ★ 修复：pos.returnAmount 在 v2.0.6+ 已经是"利润"（profit = sell_total - invested）
      //    所以直接累加即可，不要再减 investedAmount
      for (final portfolio in _portfolios) {
        if (portfolio.status != SpeedPortfolioStatus.settled) continue;
        for (final pos in portfolio.positions) {
          if (pos.status != SpeedPositionStatus.settled) continue;
          if (pos.sellTime == null) continue;
          if (pos.returnAmount != null) {
            monthTotalReturnAmount += pos.returnAmount!;
            hasSettledData = true;
          }
        }
      }
    }

    final monthReturnRate = _isSpeedMode ? sumDailyRates : sumDailyRates * 100;
    return {'monthReturnRate': monthReturnRate, 'monthTotalReturnAmount': monthTotalReturnAmount};
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dayReturns = _aggregateReturns();
    final holdingDates = _aggregateHoldingDates();

    // 提前计算当月汇总（供标题栏使用）
    final monthSummary = _calcMonthSummary();
    final monthReturnRate = monthSummary['monthReturnRate']!;
    final monthTotalReturnAmount = monthSummary['monthTotalReturnAmount']!;
    final isProfit = monthTotalReturnAmount >= 0;
    final isMonthlyProfit = monthReturnRate >= 0;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        elevation: 1,
        shadowColor: colors.primary.withOpacity(0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 折叠标题栏 — 含总收益数据
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _toggleExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(children: [
                  Icon(Icons.calendar_month, size: 18, color: colors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('投资收益日历',
                    style: AppText.body1.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    )),
                  const Spacer(),
                  // 总收益：百分比 + 金额
                  if (isProfit || monthTotalReturnAmount < 0)
                    Text(
                      '${isMonthlyProfit ? "▲" : "▼"}${monthReturnRate.abs().toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: isMonthlyProfit ? colors.up : colors.down,
                        fontSize: 13, fontWeight: FontWeight.w900,
                      ),
                    ),
                  const SizedBox(width: 4),
                  if (isProfit || monthTotalReturnAmount < 0)
                    Text(
                      '${isProfit ? "+" : ""}${_fmtAmount(monthTotalReturnAmount)}',
                      style: TextStyle(
                        color: isProfit ? colors.up : colors.down,
                        fontSize: 13, fontWeight: FontWeight.w900,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  RotationTransition(
                    turns: _arrowTurns,
                    child: Icon(Icons.keyboard_arrow_down,
                      size: 20, color: colors.textHint),
                  ),
                ]),
              ),
            ),

            // 展开内容
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _buildCalendarContent(colors, dayReturns, holdingDates),
              crossFadeState:
                  _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarContent(
    AppColorScheme colors,
    Map<String, _DayReturn> dayReturns,
    Set<String> holdingDates,
  ) {
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final startOffset = firstWeekday - 1;

    final today = DateTime.now();
    final todayKey = _dateKey(today);
    final todayPnl = _calcTodayPnl();

    // 计算当月热投统计
    // 用户规则：
    //   日收益率 = 当日已结算盈亏 / 当日已结算成本  （无结算日 = 0%）
    //   月收益率 = Σ(日收益率) / 当月天数  （无结算日记为0%参与平均）
    //   日均回报率 = 月收益率 / 有结算天数（实际交易天数）
    final monthStr = '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';

    double monthSettled = 0.0;
    int monthSettledDays = 0;
    double monthFloating = 0.0;
    bool hasFloating = false;
    // 累计该月每日收益率（小数，无结算日为 0.0）
    double sumDailyRates = 0.0;

    for (final entry in dayReturns.entries) {
      if (!entry.key.startsWith(monthStr)) continue;
      monthSettled += entry.value.settledReturn;
      if (_isSpeedMode) {
        // 极速投资：settledReturn 已是百分比值，直接累加
        sumDailyRates += entry.value.settledReturn;
      } else {
        // 热点/轻量：日收益率 = 当日已结算盈亏 / 当日已结算成本
        final dayRate = entry.value.settledCost > 0
            ? entry.value.settledReturn / entry.value.settledCost
            : 0.0;
        sumDailyRates += dayRate;
      }
      if (entry.value.settledCount > 0) monthSettledDays++;
      if (entry.value.floatingCount > 0) {
        monthFloating += entry.value.floatingReturn;
        hasFloating = true;
      }
    }

    final monthTotalReturn = monthSettled;

    // 速度投资：从已结算组合的 position 中获取实际盈亏金额
    double monthTotalReturnAmount = monthSettled; // 非速度模式 monthSettled 本身就是金额
    if (_isSpeedMode) {
      monthTotalReturnAmount = 0.0;
      for (final portfolio in _portfolios) {
        if (portfolio.status != SpeedPortfolioStatus.settled) continue;
        for (final pos in portfolio.positions) {
          if (pos.status != SpeedPositionStatus.settled) continue;
          if (pos.sellTime == null) continue;
          final sellDateStr = '${pos.sellTime!.year}-${pos.sellTime!.month.toString().padLeft(2, '0')}';
          if (sellDateStr != monthStr) continue;
          if (pos.returnAmount != null) {
            // ★ 修复：returnAmount 已经是利润
            monthTotalReturnAmount += pos.returnAmount!;
          }
        }
      }
    }

    // 首个建仓日：热点/轻量从 service.firstTradeDate 拿，速度从 portfolios.createTime 拿
    final now = DateTime.now();
    final kFirstTradeDate = _firstTradeDate ??
        (_isSpeedMode && _portfolios.isNotEmpty
            ? (_portfolios.first as dynamic).createTime as DateTime?
            : null);
    if (kFirstTradeDate == null) return const SizedBox.shrink(); // 无任何数据

    // 当月交易日天数：从首个交易日到今天（排除周末）
    int tradingDaysInMonth;
    if (_currentMonth.year < kFirstTradeDate.year ||
        (_currentMonth.year == kFirstTradeDate.year &&
         _currentMonth.month < kFirstTradeDate.month)) {
      // 在首个交易日之前的月份：无交易
      tradingDaysInMonth = 0;
    } else if (_currentMonth.year == now.year && _currentMonth.month == now.month) {
      // 当前月：从首个交易日到今天
      final startDate = (_currentMonth.year == kFirstTradeDate.year &&
                         _currentMonth.month == kFirstTradeDate.month)
          ? kFirstTradeDate
          : DateTime(_currentMonth.year, _currentMonth.month, 1);
      tradingDaysInMonth = _countTradingDays(startDate, now);
    } else if (_currentMonth.year > now.year ||
        (_currentMonth.year == now.year && _currentMonth.month > now.month)) {
      tradingDaysInMonth = 0; // 未来月份
    } else {
      // 过去的月份：从起始日到月末
      final startDate = (_currentMonth.year == kFirstTradeDate.year &&
                         _currentMonth.month == kFirstTradeDate.month)
          ? kFirstTradeDate
          : DateTime(_currentMonth.year, _currentMonth.month, 1);
      final monthEnd = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
      tradingDaysInMonth = _countTradingDays(startDate, monthEnd);
    }

    // 月回报率 / 日均回报率
    // 极速投资：settledReturn 已是百分比值，不需转换
    // 热点/轻量：日收益率（小数）→ 月回报率 = Σ × 100
    final monthReturnRate = _isSpeedMode ? sumDailyRates : sumDailyRates * 100;

    // 持仓成本 = 当前未结算（holding）仓位的投入总额
    final holdingCost = _calcHoldingCost();

    // 日均回报率 = 月回报率 / 当月交易日天数（实际交易天数）
    final dailyAvgRate = tradingDaysInMonth > 0
        ? monthReturnRate / tradingDaysInMonth
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMonthNav(colors),
          const SizedBox(height: AppSpacing.sm),

          // 当月统计（参考交易日日历风格）
          if (monthSettledDays > 0 || hasFloating)
            _buildMonthStatsBar(colors, monthTotalReturn, monthTotalReturnAmount, holdingCost, monthReturnRate, dailyAvgRate, hasFloating, monthFloating),

          _buildWeekdayHeaders(colors),
          const SizedBox(height: AppSpacing.xs),
          _buildDayGrid(colors, daysInMonth, startOffset, dayReturns, holdingDates, todayKey, todayPnl),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  /// A股节假日列表（2026年示例，可按需扩展）
  /// 格式：yyyy-MM-dd
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

  /// 判断某日是否为证券交易日
  /// 规则：排除周末 + 排除A股节假日
  /// 注意：已知交易日记录可能不完整（如建仓日未创建交易日记录），
  ///       不能用来否定工作日，否则会误排除实际交易日
  bool _isSecuritiesTradingDay(DateTime date) {
    // 1. 排除周末
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    // 2. 排除A股节假日
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (_kHolidayDates.contains(dateStr)) {
      return false;
    }
    // 3. 工作日（排除节假日后）视为交易日
    return true;
  }

  /// 计算两个日期之间的证券交易日天数（排除周末+节假日）
  int _countTradingDays(DateTime from, DateTime to) {
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

  /// 计算持仓成本：仅累加当前 holding 状态仓位的投入总额
  /// 随着止盈/止损结算，已结算仓位从成本中自动扣除
  double _calcHoldingCost() {
    double total = 0;
    for (final portfolio in _portfolios) {
      for (final pos in portfolio.positions) {
        if (_isSpeedMode) { if (!_isHolding(pos)) continue; }
        else if (pos.status != PositionStatus.holding) continue;
        if (pos.investedAmount <= 0) continue;
        total += pos.investedAmount;
      }
    }
    return total;
  }

  /// 当月统计栏 — 日均回报率 + 月回报率
  /// monthReturnRate: 月收益率（日收益率算术平均）
  /// dailyAvgRate: 日均回报率 = 月收益率 / 有结算的天数
  /// holdingCost: 持仓成本（当前未结算仓位总投入）
  /// totalReturnAmount: 总收益金额（速度模式从 position 获取，非速度模式=totalReturn）
  Widget _buildMonthStatsBar(AppColorScheme colors, double totalReturn, double totalReturnAmount, double holdingCost, double monthReturnRate, double dailyAvgRate, bool hasFloating, double floatingReturn) {
    final isProfit = totalReturnAmount >= 0;
    final isMonthlyProfit = monthReturnRate >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isProfit
            ? colors.up.withOpacity(0.08)
            : colors.down.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：日均回报率 + 月回报率
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('日均 ',
              style: AppText.caption.copyWith(color: colors.textSecondary, fontSize: 12)),
            Text(
              '${isMonthlyProfit ? "▲" : "▼"}${dailyAvgRate.abs().toStringAsFixed(3)}%',
              style: TextStyle(
                color: isMonthlyProfit ? colors.up : colors.down,
                fontSize: 16, fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 16, color: colors.textSecondary.withOpacity(0.3)),
            const SizedBox(width: 10),
            Text('月回报 ',
              style: AppText.caption.copyWith(color: colors.textSecondary, fontSize: 12)),
            Text(
              '${isMonthlyProfit ? "▲" : "▼"}${monthReturnRate.abs().toStringAsFixed(2)}%',
              style: TextStyle(
                color: isMonthlyProfit ? colors.up : colors.down,
                fontSize: 16, fontWeight: FontWeight.w800,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // 第二行：持仓成本 + 浮动标记（总收益已移至标题栏）
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('持仓资金 ',
              style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
            Text(
              _fmtAmount(holdingCost),
              style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            if (hasFloating)
              Text('  (另有${floatingReturn >= 0 ? "+" : ""}${_fmtAmount(floatingReturn)}浮动未计入)',
                style: AppText.caption.copyWith(color: colors.textSecondary, fontSize: 10)),
          ]),
        ],
      ),
    );
  }

  // ================================================================
  // 日历格子
  // ================================================================

  Widget _buildMonthNav(AppColorScheme colors) {
    final monthLabel = '${_currentMonth.year}年${_currentMonth.month}月';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _prevMonth,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Icon(Icons.chevron_left, size: 20, color: colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Text(monthLabel,
          style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(width: AppSpacing.lg),
        GestureDetector(
          onTap: _nextMonth,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeaders(AppColorScheme colors) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: weekdays.map((d) {
        final isWeekend = d == '六' || d == '日';
        return Expanded(
          child: Center(
            child: Text(d,
              style: AppText.caption.copyWith(
                color: isWeekend ? colors.down.withOpacity(0.7) : colors.textSecondary,
                fontSize: 11, fontWeight: FontWeight.w600,
              )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDayGrid(
    AppColorScheme colors,
    int daysInMonth,
    int startOffset,
    Map<String, _DayReturn> dayReturns,
    Set<String> holdingDates,
    String todayKey,
    _TodayPnl? todayPnl,
  ) {
    final cells = <Widget>[];

    for (int i = 0; i < startOffset; i++) {
      cells.add(const Expanded(child: SizedBox.shrink()));
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final dateKey = '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final dayData = dayReturns[dateKey];
      final isHolding = holdingDates.contains(dateKey);
      final isToday = dateKey == todayKey;
      cells.add(Expanded(child: _buildDayCell(
        colors, day, dateKey, dayData, isHolding, isToday,
        todayPnl: isToday ? todayPnl : null,
      )));
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final end = (i + 7).clamp(0, cells.length);
      final rowCells = cells.sublist(i, end).toList();
      // 最后一行不足 7 列时填充空白占位，保证对齐
      while (rowCells.length < 7) {
        rowCells.add(const Expanded(child: SizedBox.shrink()));
      }
      rows.add(Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(children: rowCells),
      ));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _buildDayCell(
    AppColorScheme colors,
    int day,
    String dateKey,
    _DayReturn? dayData,
    bool isHolding,
    bool isToday, {
    _TodayPnl? todayPnl,
  }) {
    // 日历格子金额：仅含已结算（止盈/止损）收益，浮动不计
    final hasReturn = dayData != null && dayData.settledCount > 0;
    final totalReturn = dayData?.settledReturn ?? 0;
    final isProfit = hasReturn && totalReturn >= 0;
    final isLoss = hasReturn && totalReturn < 0;

    // 日期解析
    final dt = _parseDateKey(dateKey);
    final isWeekend = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
    // 是否为证券交易日（排除周末+节假日）
    final isTradingDay = _isSecuritiesTradingDay(dt);

    // 是否有热点投资数据可点击（非交易日不可点击）
    final hasData = isTradingDay && (hasReturn || isHolding);

    // 背景色 — 仅交易日且仅有热点投资数据时显示
    Color? bgColor;
    if (isTradingDay) {
      if (isProfit) {
        bgColor = colors.up.withOpacity(0.12);
      } else if (isLoss) {
        bgColor = colors.down.withOpacity(0.12);
      } else if (isHolding) {
        bgColor = colors.hotInvestAccent.withOpacity(0.08);
      }
    }

    // 文字颜色
    Color dayColor;
    if (isToday) {
      dayColor = colors.primary;
    } else if (isWeekend || !isTradingDay) {
      dayColor = colors.textHint;
    } else {
      dayColor = colors.textSecondary;
    }

    // 底部文字 — 仅交易日显示已结算收益（浮动收益不计入）
    String? bottomText;
    Color? bottomColor;
    String? pctText;
    if (isTradingDay) {
      if (hasReturn) {
        // 有结算收益
        if (dayData!.settledCost < 0) {
          // 极速投资百分比模式：settledReturn 直接是百分比值
          bottomText = '${totalReturn >= 0 ? '+' : ''}${totalReturn.toStringAsFixed(2)}%';
          bottomColor = isProfit ? colors.up : colors.down;
        } else {
          // 热点/轻量投资金额模式
          bottomText = _fmtAmount(totalReturn);
          bottomColor = isProfit ? colors.up : colors.down;
          // 当天收益率百分比 = 当日已结算盈亏 / 当日已结算成本 × 100%
          if (dayData.settledCost > 0) {
            final pct = dayData.settledReturn / dayData.settledCost * 100;
            pctText = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
          }
        }
      } else if (isHolding) {
        // 交易日有持仓但无结算（如建仓日）→ 显示 0 和 0%
        bottomText = '0';
        pctText = '0.0%';
        bottomColor = colors.textHint;
      }
      // 非交易日或有持仓无结算的情况以上已覆盖，其余不显示
    }

    return GestureDetector(
      onTap: hasData ? () => _showDayDetail(dateKey, day) : null,
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: isToday
              ? Border.all(color: colors.primary, width: 1.5)
              : null,
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                style: TextStyle(
                  color: dayColor,
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                )),
              if (bottomText != null) ...[
                const SizedBox(height: 1),
                Text(bottomText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: bottomColor,
                    height: 1.1,
                  )),
                if (pctText != null) ...[
                  const SizedBox(height: 0.5),
                  Text(pctText,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: bottomColor,
                      height: 1.1,
                    )),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // 工具
  // ================================================================

  static String _fmtAmount(double amount) {
    final abs = amount.abs();
    if (abs >= 10000) return '${(amount / 10000).toStringAsFixed(1)}w';
    if (abs >= 1000) return '${(amount / 1000).toStringAsFixed(1)}k';
    return amount.toStringAsFixed(0);
  }
}

// ================================================================
// 辅助数据类
// ================================================================

class _DayReturn {
  double settledReturn;  // 已结算收益总额
  double settledCost;    // 已结算股票的总购买成本（用于计算日收益率）
  int settledCount;      // 已结算笔数
  double floatingReturn; // 浮动盈亏（仅今日）
  int floatingCount;     // 浮动持仓数（仅今日）
  _DayReturn(this.settledReturn, this.settledCost, this.settledCount, this.floatingReturn, this.floatingCount);
}

class _TodayPnl {
  final double pnl;
  final double pnlRate;
  final int holdingCount;
  const _TodayPnl(this.pnl, this.pnlRate, this.holdingCount);
}

/// 组合分组摘要（用于弹窗标题栏）
class _GroupSummary {
  final double settled;
  final double settledCost;
  final int settledCount;
  final double floating;
  final int holdingCount;
  final double floatingRate;
  const _GroupSummary({
    required this.settled,
    required this.settledCost,
    required this.settledCount,
    required this.floating,
    required this.holdingCount,
    required this.floatingRate,
  });
}

class _DayPositionDetail {
  final String stockName;
  final String stockCode;
  final double buyPrice;
  final DateTime buyTime;
  final double investedAmount;
  final int shares;
  final PositionStatus status;
  final double? sellPrice;
  final DateTime? sellTime;
  final double? returnAmount;
  final double? returnRate;
  final double stopLossPercent;
  final String portfolioName;
  final bool settledOnThisDate;
  final double? currentPrice;
  final bool isSpeedMode;           // 极速投资标识
  final String? speedStatusLabel;   // 极速投资状态标签

  const _DayPositionDetail({
    required this.stockName,
    required this.stockCode,
    required this.buyPrice,
    required this.buyTime,
    required this.investedAmount,
    required this.shares,
    required this.status,
    this.sellPrice,
    this.sellTime,
    this.returnAmount,
    this.returnRate,
    required this.stopLossPercent,
    required this.portfolioName,
    required this.settledOnThisDate,
    this.currentPrice,
    this.isSpeedMode = false,
    this.speedStatusLabel,
  });
}
