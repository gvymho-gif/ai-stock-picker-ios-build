/// 热点投资模块 - 虚拟跟单数据模型
///
/// 基于专家选股→热点追踪的快捷虚拟建仓入口
/// 三只股票一组，最长持有5个交易日

import 'dart:math';

/// 持仓状态
enum PositionStatus { unfilled, holding, stopProfit, stopLoss, timeLiquidated }

/// 组合状态
enum PortfolioStatus { pending, holding, settled }

/// 虚拟持仓
class VirtualPosition {
  final String stockCode;       // 股票代码
  final String stockName;       // 股票名称
  final double buyPrice;        // 虚拟建仓价
  final DateTime buyTime;       // 建仓时间
  final double investedAmount;  // 实际投入金额（≤30000）
  final int shares;             // 持有股数（100股起，向下取整到整百）
  final PositionStatus status;  // 持仓状态
  final double? sellPrice;      // 卖出价格
  final DateTime? sellTime;     // 卖出时间
  final double? returnAmount;   // 回报金额
  final double? returnRate;     // 回报率 (0-1)
  final double stopLossPercent; // 硬止损百分比 (0-1, 如0.04=4%)

  const VirtualPosition({
    required this.stockCode,
    required this.stockName,
    required this.buyPrice,
    required this.buyTime,
    required this.investedAmount,
    required this.shares,
    this.status = PositionStatus.holding,
    this.sellPrice,
    this.sellTime,
    this.returnAmount,
    this.returnRate,
    this.stopLossPercent = 0.05,
  });

  // ---- 计算属性 ----

  /// 当前估值的回报率（基于给定最新价格）
  double currentReturnRate(double currentPrice) {
    return (currentPrice - buyPrice) / buyPrice;
  }

  /// 当前估值的盈亏金额
  double currentReturnAmount(double currentPrice) {
    return (currentPrice - buyPrice) * shares;
  }

  /// 是否触发止盈 (≥ +10%)
  bool wouldStopProfit(double currentPrice) {
    return currentReturnRate(currentPrice) >= 0.10;
  }

  /// 是否触发止损
  bool wouldStopLoss(double currentPrice) {
    return currentReturnRate(currentPrice) <= -stopLossPercent;
  }

  // ---- 序列化 ----

  Map<String, dynamic> toJson() => {
    'stockCode': stockCode,
    'stockName': stockName,
    'buyPrice': buyPrice,
    'buyTime': buyTime.toIso8601String(),
    'investedAmount': investedAmount,
    'shares': shares,
    'status': status.name,
    'sellPrice': sellPrice,
    'sellTime': sellTime?.toIso8601String(),
    'returnAmount': returnAmount,
    'returnRate': returnRate,
    'stopLossPercent': stopLossPercent,
  };

  factory VirtualPosition.fromJson(Map<String, dynamic> json) => VirtualPosition(
    stockCode: json['stockCode']?.toString() ?? '',
    stockName: json['stockName']?.toString() ?? '',
    buyPrice: (json['buyPrice'] as num?)?.toDouble() ?? 0,
    buyTime: json['buyTime'] != null ? DateTime.parse(json['buyTime'] as String) : DateTime.now(),
    investedAmount: (json['investedAmount'] as num?)?.toDouble() ?? 0,
    shares: (json['shares'] as num?)?.toInt() ?? 0,
    status: PositionStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => PositionStatus.holding,
    ),
    sellPrice: json['sellPrice'] != null ? (json['sellPrice'] as num).toDouble() : null,
    sellTime: json['sellTime'] != null ? DateTime.parse(json['sellTime'] as String) : null,
    returnAmount: json['returnAmount'] != null ? (json['returnAmount'] as num).toDouble() : null,
    returnRate: json['returnRate'] != null ? (json['returnRate'] as num).toDouble() : null,
    stopLossPercent: min((json['stopLossPercent'] as num?)?.toDouble() ?? 0.05, 0.05),
  );

  /// 创建已结算的副本
  VirtualPosition settle({
    required PositionStatus newStatus,
    required double sellPrice,
    required DateTime sellTime,
  }) {
    final amount = (sellPrice - buyPrice) * shares;
    final rate = (sellPrice - buyPrice) / buyPrice;
    return VirtualPosition(
      stockCode: stockCode,
      stockName: stockName,
      buyPrice: buyPrice,
      buyTime: buyTime,
      investedAmount: investedAmount,
      shares: shares,
      status: newStatus,
      sellPrice: sellPrice,
      sellTime: sellTime,
      returnAmount: amount,
      returnRate: rate,
      stopLossPercent: stopLossPercent,
    );
  }
}

/// 热点投资组合
class HotInvestmentPortfolio {
  final String id;
  final String name;
  final String hotTrackTitle;       // 关联热点新闻标题
  final String? newsRating;         // S/A 评级
  final DateTime createdAt;
  final PortfolioStatus status;
  final List<VirtualPosition> positions;
  final double totalInvested;       // 实际总投入
  final double totalReturn;         // 实际总回报（仅 settled 时有效）
  final DateTime? settledAt;

  const HotInvestmentPortfolio({
    required this.id,
    required this.name,
    required this.hotTrackTitle,
    this.newsRating,
    required this.createdAt,
    this.status = PortfolioStatus.holding,
    this.positions = const [],
    this.totalInvested = 0,
    this.totalReturn = 0,
    this.settledAt,
  });

  // ---- 计算属性 ----

  /// 持仓中的股票数
  int get holdingCount => positions.where((p) => p.status == PositionStatus.holding).length;

  /// 是否全部结算
  bool get isFullySettled => positions.every((p) => p.status != PositionStatus.holding);

  /// 当前总市值（基于给定价格映射）
  double currentMarketValue(Map<String, double> prices) {
    double total = 0;
    for (final p in positions) {
      if (p.status == PositionStatus.holding && prices.containsKey(p.stockCode)) {
        total += prices[p.stockCode]! * p.shares;
      }
    }
    return total;
  }

  /// 当前浮动盈亏
  double currentFloatingPnl(Map<String, double> prices) {
    return currentMarketValue(prices) - positions
      .where((p) => p.status == PositionStatus.holding)
      .fold<double>(0, (sum, p) => sum + p.investedAmount);
  }

  // ---- 序列化 ----

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hotTrackTitle': hotTrackTitle,
    'newsRating': newsRating,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'positions': positions.map((p) => p.toJson()).toList(),
    'totalInvested': totalInvested,
    'totalReturn': totalReturn,
    'settledAt': settledAt?.toIso8601String(),
  };

  factory HotInvestmentPortfolio.fromJson(Map<String, dynamic> json) => HotInvestmentPortfolio(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    hotTrackTitle: json['hotTrackTitle']?.toString() ?? '',
    newsRating: json['newsRating']?.toString(),
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now(),
    status: PortfolioStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => PortfolioStatus.holding,
    ),
    positions: (json['positions'] as List<dynamic>?)
      ?.map((e) => VirtualPosition.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList() ?? [],
    totalInvested: (json['totalInvested'] as num?)?.toDouble() ?? 0,
    totalReturn: (json['totalReturn'] as num?)?.toDouble() ?? 0,
    settledAt: json['settledAt'] != null ? DateTime.parse(json['settledAt'] as String) : null,
  );

  /// 更新部分字段
  HotInvestmentPortfolio copyWith({
    String? id,
    String? name,
    String? hotTrackTitle,
    String? newsRating,
    DateTime? createdAt,
    PortfolioStatus? status,
    List<VirtualPosition>? positions,
    double? totalInvested,
    double? totalReturn,
    DateTime? settledAt,
  }) => HotInvestmentPortfolio(
    id: id ?? this.id,
    name: name ?? this.name,
    hotTrackTitle: hotTrackTitle ?? this.hotTrackTitle,
    newsRating: newsRating ?? this.newsRating,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    positions: positions ?? this.positions,
    totalInvested: totalInvested ?? this.totalInvested,
    totalReturn: totalReturn ?? this.totalReturn,
    settledAt: settledAt ?? this.settledAt,
  );
}
