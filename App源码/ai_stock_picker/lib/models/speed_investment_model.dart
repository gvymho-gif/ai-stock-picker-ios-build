/// 极速投资模块 - 数据模型
///
/// T+1买入/T+2卖出，每交易日20:00从A股游资+隔夜导航各取3只合成6只
/// 每只上限2万，总上限12万。当天买次日卖，严格日结。

import 'dart:math';
import '../utils/trading_day_utils.dart';

/// 持仓状态
enum SpeedPositionStatus { holding, settled }

/// 组合状态
enum SpeedPortfolioStatus { pending, active, settled }

/// 单只股票的虚拟持仓
class SpeedPosition {
  final String stockCode;
  final String stockName;
  final double buyPrice;         // T日09:30实际买入价（pending时为0）
  final DateTime? buyTime;       // T日09:30实际买入时间（pending时为null）
  final double investedAmount;   // 实际投入金额 ≤20000
  final int shares;              // 持有股数（pending时为0）
  final double plannedAmount;    // 计划投入金额（选股日设定，pending阶段展示用）
  final SpeedPositionStatus status;
  final double? sellPrice;
  final DateTime? sellTime;
  final double? returnAmount;
  final double? returnRate;      // 0-1

  const SpeedPosition({
    required this.stockCode,
    required this.stockName,
    this.buyPrice = 0,
    this.buyTime,
    this.investedAmount = 0,
    this.shares = 0,
    this.plannedAmount = 20000,
    this.status = SpeedPositionStatus.holding,
    this.sellPrice,
    this.sellTime,
    this.returnAmount,
    this.returnRate,
  });

  /// 当日卖出后结算的盈亏金额
  /// ★ returnAmount 在 v2.0.6+ 已经是"利润"（profit = sell_total - invested）
  double get settledPnl =>
      (returnAmount != null) ? returnAmount! : 0;

  Map<String, dynamic> toJson() => {
    'stockCode': stockCode,
    'stockName': stockName,
    'buyPrice': buyPrice,
    'buyTime': buyTime?.toIso8601String(),
    'investedAmount': investedAmount,
    'shares': shares,
    'plannedAmount': plannedAmount,
    'status': status.name,
    'sellPrice': sellPrice,
    'sellTime': sellTime?.toIso8601String(),
    'returnAmount': returnAmount,
    'returnRate': returnRate,
  };

  factory SpeedPosition.fromJson(Map<String, dynamic> json) => SpeedPosition(
    stockCode: json['stockCode'] as String? ?? '',
    stockName: json['stockName'] as String? ?? '',
    buyPrice: (json['buyPrice'] as num?)?.toDouble() ?? 0,
    buyTime: json['buyTime'] != null ? DateTime.parse(json['buyTime'] as String) : null,
    investedAmount: (json['investedAmount'] as num?)?.toDouble() ?? 0,
    shares: (json['shares'] as num?)?.toInt() ?? 0,
    plannedAmount: (json['plannedAmount'] as num?)?.toDouble() ?? 20000,
    status: SpeedPositionStatus.values.firstWhere((e) => e.name == json['status'], orElse: () => SpeedPositionStatus.holding),
    sellPrice: (json['sellPrice'] as num?)?.toDouble(),
    sellTime: json['sellTime'] != null ? DateTime.parse(json['sellTime'] as String) : null,
    returnAmount: (json['returnAmount'] as num?)?.toDouble(),
    returnRate: (json['returnRate'] as num?)?.toDouble(),
  );
}

/// 每日投资组合（6只股票一组的交易日记录）
class SpeedPortfolio {
  final String id;                      // 唯一标识
  final DateTime createTime;            // 创建时间（选股时间，即20:00）
  final List<SpeedPosition> positions;  // 6只持仓
  final SpeedPortfolioStatus status;    // 组合状态
  final double totalInvested;           // 总投入金额
  final List<String> sourceLabels;      // 数据来源（每只股票来自哪个模块）
  final double? totalReturn;            // 已结算时的总利润
  final double? returnRate;             // 收益率

  const SpeedPortfolio({
    required this.id,
    required this.createTime,
    required this.positions,
    this.status = SpeedPortfolioStatus.active,
    this.totalInvested = 0,
    this.sourceLabels = const [],
    this.totalReturn,
    this.returnRate,
    this.storedBuyDate,    // ★ JSON 中的 buyDate 字段（优先于 computed）
    this.storedSellDate,   // ★ JSON 中的 sellDate 字段（优先于 computed）
  });

  /// 买入日期 — 优先用 JSON 存储的 buyDate，没有才从 createTime 算
  DateTime get buyDate {
    if (storedBuyDate != null) return storedBuyDate!;
    return nextTradingDay(createTime);
  }

  /// 卖出日期 — 优先用 JSON 存储的 sellDate，没有才从 createTime 算
  DateTime get sellDate {
    if (storedSellDate != null) return storedSellDate!;
    return nextTradingDay(buyDate);
  }

  /// JSON 中传入的 buyDate 字符串（YYYY-MM-DD）
  final DateTime? storedBuyDate;
  /// JSON 中传入的 sellDate 字符串（YYYY-MM-DD）
  final DateTime? storedSellDate;

  /// 是否已全部结算
  bool get isAllSettled => positions.every((p) => p.status == SpeedPositionStatus.settled);

  /// 当天平均结算收益率 (%) = 总盈亏金额 / 总投入 × 100
  double get avgSettledReturn {
    final settled = positions.where((p) => p.status == SpeedPositionStatus.settled).toList();
    if (settled.isEmpty) return 0;
    double totalPnl = 0;       // Σ(returnAmount) ★ returnAmount 已经是利润
    double totalInvested = 0;  // Σ(investedAmount)
    for (final p in settled) {
      totalPnl += p.returnAmount ?? 0;
      totalInvested += p.investedAmount;
    }
    if (totalInvested <= 0) return 0;
    return totalPnl / totalInvested * 100;
  }

  /// 总盈亏金额
  double get totalPnl {
    return positions.where((p) => p.status == SpeedPositionStatus.settled)
        .fold<double>(0, (sum, p) => sum + p.settledPnl);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createTime': createTime.toIso8601String(),
    'buyDate': buyDateStr,          // ★ 序列化至云端
    'sellDate': sellDateStr,        // ★ 序列化至云端
    'positions': positions.map((p) => p.toJson()).toList(),
    'status': status.name,
    'totalInvested': totalInvested,
    'sourceLabels': sourceLabels,
    'totalReturn': totalReturn,     // ★ 同步收益
    'returnRate': returnRate,       // ★ 同步收益率
  };

  /// buyDate 的字符串形式（YYYY-MM-DD），用于序列化
  String get buyDateStr {
    final bd = buyDate;
    return '${bd.year}-${bd.month.toString().padLeft(2, '0')}-${bd.day.toString().padLeft(2, '0')}';
  }

  /// sellDate 的字符串形式（YYYY-MM-DD），用于序列化
  String get sellDateStr {
    final sd = sellDate;
    return '${sd.year}-${sd.month.toString().padLeft(2, '0')}-${sd.day.toString().padLeft(2, '0')}';
  }

  factory SpeedPortfolio.fromJson(Map<String, dynamic> json) {
    final posList = (json['positions'] as List<dynamic>?) ?? [];
    DateTime? storedBuyDate;
    DateTime? storedSellDate;
    // ★ 从 JSON 读取 buyDate/sellDate（优先使用存储的值）
    try { storedBuyDate = DateTime.tryParse(json['buyDate'] as String? ?? ''); } catch (_) {}
    try { storedSellDate = DateTime.tryParse(json['sellDate'] as String? ?? ''); } catch (_) {}
    return SpeedPortfolio(
      id: json['id'] as String? ?? '',
      createTime: DateTime.parse(json['createTime'] as String? ?? DateTime.now().toIso8601String()),
      positions: posList.map((p) => SpeedPosition.fromJson(p as Map<String, dynamic>)).toList(),
      status: SpeedPortfolioStatus.values.firstWhere((e) => e.name == json['status'], orElse: () => SpeedPortfolioStatus.active),
      totalInvested: (json['totalInvested'] as num?)?.toDouble() ?? 0,
      sourceLabels: (json['sourceLabels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      totalReturn: (json['totalReturn'] as num?)?.toDouble(),
      returnRate: (json['returnRate'] as num?)?.toDouble(),
      storedBuyDate: storedBuyDate,
      storedSellDate: storedSellDate,
    );
  }

  /// 取下一个证券交易日（使用内置交易日历，排除周末+节假日）
  static DateTime nextTradingDay(DateTime dt) {
    var d = DateTime(dt.year, dt.month, dt.day).add(const Duration(days: 1));
    while (!TradingDayUtils.isSecuritiesTradingDay(d)) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day, 9, 30); // 返回09:30
  }
}

/// 收益日历 - 每日结算记录
class SpeedSettlementRecord {
  final String date;              // YYYY-MM-DD
  final String portfolioId;       // 对应组合ID
  final double settledReturn;     // 当天结算收益率%（前一天组合的卖出收益）
  final double floatingReturn;    // 当天浮动收益率%（当天新买入的持仓浮动）
  final double totalReturn;       // 当天总收益（结算+浮动，但浮动仅展示）

  const SpeedSettlementRecord({
    required this.date,
    required this.portfolioId,
    this.settledReturn = 0,
    this.floatingReturn = 0,
    this.totalReturn = 0,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'portfolioId': portfolioId,
    'settledReturn': settledReturn,
    'floatingReturn': floatingReturn,
    'totalReturn': totalReturn,
  };

  factory SpeedSettlementRecord.fromJson(Map<String, dynamic> json) => SpeedSettlementRecord(
    date: json['date'] as String? ?? '',
    portfolioId: json['portfolioId'] as String? ?? '',
    settledReturn: (json['settledReturn'] as num?)?.toDouble() ?? 0,
    floatingReturn: (json['floatingReturn'] as num?)?.toDouble() ?? 0,
    totalReturn: (json['totalReturn'] as num?)?.toDouble() ?? 0,
  );
}

/// 极速投资统计数据
class SpeedStatistics {
  final int totalDays;            // 总交易天数
  final int settledDays;          // 已结算天数
  final double cumulativeReturn;  // 累计收益%
  final double avgDailyReturn;    // 日均收益%
  final double totalPnl;          // 总盈亏金额
  final int winDays;              // 盈利天数
  final int lossDays;             // 亏损天数
  final double winRate;           // 盈利率
  final double maxSingleReturn;   // 单日最大收益%
  final double maxSingleLoss;     // 单日最大亏损%

  const SpeedStatistics({
    this.totalDays = 0,
    this.settledDays = 0,
    this.cumulativeReturn = 0,
    this.avgDailyReturn = 0,
    this.totalPnl = 0,
    this.winDays = 0,
    this.lossDays = 0,
    this.winRate = 0,
    this.maxSingleReturn = 0,
    this.maxSingleLoss = 0,
  });

  factory SpeedStatistics.compute(List<SpeedSettlementRecord> records) {
    if (records.isEmpty) return const SpeedStatistics();

    final settled = records.where((r) => r.settledReturn != 0 || r.date == records.first.date).toList();
    if (settled.isEmpty) return SpeedStatistics(totalDays: records.length);

    double cumReturn = 0;
    int winDays = 0;
    int lossDays = 0;
    double maxRet = -999;
    double maxLoss = 999;

    for (final r in records) {
      cumReturn += r.settledReturn;
      if (r.settledReturn > 0) winDays++;
      else if (r.settledReturn < 0) lossDays++;
      if (r.settledReturn > maxRet) maxRet = r.settledReturn;
      if (r.settledReturn < maxLoss && r.settledReturn != 0) maxLoss = r.settledReturn;
    }

    // 日均收益 = 累计结算收益 / 总交易天数（含建仓日）
    // 总交易天数 = 从首个建仓日到最近结算日之间的交易日数
    int totalTradingDays = records.length; // 默认用记录数
    if (records.isNotEmpty) {
      final firstDate = DateTime.parse(records.first.date);
      final lastDate = DateTime.parse(records.last.date);
      totalTradingDays = TradingDayUtils.countTradingDays(firstDate, lastDate);
      if (totalTradingDays < 1) totalTradingDays = 1; // 至少1天
    }

    return SpeedStatistics(
      totalDays: totalTradingDays,
      settledDays: records.where((r) => r.settledReturn != 0).length,
      cumulativeReturn: cumReturn,
      avgDailyReturn: cumReturn / totalTradingDays,
      totalPnl: 0,
      winDays: winDays,
      lossDays: lossDays,
      winRate: (winDays + lossDays) > 0 ? winDays / (winDays + lossDays) : 0,
      maxSingleReturn: maxRet == -999 ? 0 : maxRet,
      maxSingleLoss: maxLoss == 999 ? 0 : maxLoss,
    );
  }
}
