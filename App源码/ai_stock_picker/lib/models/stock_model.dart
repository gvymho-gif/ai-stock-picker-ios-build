/// 股票数据模型 - 定义所有API响应的数据结构
/// 所有字段都有默认值，防止JSON解析异常

/// 推荐股票模型
class StockRecommendation {
  final String symbol;           // 股票代码
  final String name;             // 股票名称
  final double price;            // 当前价格
  final double changePct;        // 涨跌幅(%)
  final String action;           // 建议: buy/hold/avoid
  final double score;            // AI综合评分 0-1
  final double shortTermWinRate; // 短期胜率 0-1
  final String trend;            // 趋势: bullish/bearish/neutral
  final String reason;           // 分析逻辑说明
  final List<String> risk;       // 风险提示列表
  final Map<String, dynamic>? detail;              // 评分详情
  final Map<String, dynamic>? technicalIndicators; // 技术指标
  final String? dataSource;      // 数据来源

  StockRecommendation({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePct,
    required this.action,
    required this.score,
    required this.shortTermWinRate,
    required this.trend,
    required this.reason,
    required this.risk,
    this.detail,
    this.technicalIndicators,
    this.dataSource,
  });

  /// 从JSON创建，所有字段都有安全默认值
  factory StockRecommendation.fromJson(Map<String, dynamic> json) {
    return StockRecommendation(
      symbol: (json['symbol'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      price: _toDouble(json['price'], 0.0),
      changePct: _toDouble(json['change_pct'], 0.0),
      action: _validAction(json['action']),
      score: _toDouble(json['score'], 0.0).clamp(0.0, 1.0),
      shortTermWinRate: _toDouble(json['short_term_win_rate'], 0.0).clamp(0.0, 1.0),
      trend: _validTrend(json['trend']),
      reason: (json['reason'] ?? '') as String,
      risk: _toStringList(json['risk']),
      detail: json['detail'] as Map<String, dynamic>?,
      technicalIndicators: json['technical_indicators'] as Map<String, dynamic>?,
      dataSource: json['data_source'] as String?,
    );
  }

  // ---- 便捷属性 ----

  /// 行动建议的中文标签
  String get actionLabel {
    switch (action) {
      case 'buy': return '买入';
      case 'avoid': return '回避';
      case 'hold': return '观望';
      default: return '观望';
    }
  }

  /// 趋势的中文标签
  String get trendLabel {
    switch (trend) {
      case 'bullish': return '看多';
      case 'bearish': return '看空';
      case 'neutral': return '中性';
      default: return '中性';
    }
  }

  /// 评分显示文本
  String get scoreLabel => '${(score * 100).toStringAsFixed(0)}分';

  /// 胜率显示文本
  String get winRateLabel => '${(shortTermWinRate * 100).toStringAsFixed(0)}%';
}

/// 选股结果响应
class SelectionResponse {
  final String timestamp;     // 查询时间
  final String market;        // 市场名称
  final int totalAnalyzed;    // 分析的股票总数
  final List<StockRecommendation> recommendations; // 推荐列表
  final String disclaimer;    // 免责声明

  SelectionResponse({
    required this.timestamp,
    required this.market,
    required this.totalAnalyzed,
    required this.recommendations,
    required this.disclaimer,
  });

  factory SelectionResponse.fromJson(Map<String, dynamic> json) {
    return SelectionResponse(
      timestamp: (json['timestamp'] ?? '') as String,
      market: (json['market'] ?? '') as String,
      totalAnalyzed: (json['total_analyzed'] ?? 0) as int,
      recommendations: _parseList(json['recommendations'],
          (e) => StockRecommendation.fromJson(e as Map<String, dynamic>)),
      disclaimer: (json['disclaimer'] ?? '') as String,
    );
  }
}

/// 股票详情
class StockDetail {
  final String symbol;
  final String name;
  final double price;
  final double changePct;
  final dynamic marketCap;
  final String? marketCapDisplay;
  final dynamic peRatio;
  final dynamic roe;
  final dynamic revenueGrowth;
  final dynamic eps;
  final Map<String, dynamic>? technicalIndicators;
  final Map<String, dynamic>? aiAnalysis;
  final String? dataSource;
  final String disclaimer;

  StockDetail({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePct,
    this.marketCap,
    this.marketCapDisplay,
    this.peRatio,
    this.roe,
    this.revenueGrowth,
    this.eps,
    this.technicalIndicators,
    this.aiAnalysis,
    this.dataSource,
    this.disclaimer = '',
  });

  factory StockDetail.fromJson(Map<String, dynamic> json) {
    return StockDetail(
      symbol: (json['symbol'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      price: _toDouble(json['price'], 0.0),
      changePct: _toDouble(json['change_pct'], 0.0),
      marketCap: json['market_cap'],
      marketCapDisplay: json['market_cap_display'] as String?,
      peRatio: json['pe_ratio'],
      roe: json['roe'],
      revenueGrowth: json['revenue_growth'],
      eps: json['eps'],
      technicalIndicators: json['technical_indicators'] as Map<String, dynamic>?,
      aiAnalysis: json['ai_analysis'] as Map<String, dynamic>?,
      dataSource: json['data_source'] as String?,
      disclaimer: (json['disclaimer'] ?? '') as String,
    );
  }
}

/// 回测结果
class BacktestResult {
  final String symbol;
  final double winRate;
  final String avgReturn;
  final String maxDrawdown;
  final int totalTrades;

  BacktestResult({
    required this.symbol,
    required this.winRate,
    required this.avgReturn,
    required this.maxDrawdown,
    required this.totalTrades,
  });

  factory BacktestResult.fromJson(Map<String, dynamic> json) {
    return BacktestResult(
      symbol: (json['symbol'] ?? '') as String,
      winRate: _toDouble(json['win_rate'], 0.0).clamp(0.0, 1.0),
      avgReturn: (json['avg_return'] ?? '0%') as String,
      maxDrawdown: (json['max_drawdown'] ?? '0%') as String,
      totalTrades: (json['total_trades'] ?? 0) as int,
    );
  }
}

// ============ 工具函数 ============

/// 安全将动态值转为double
double _toDouble(dynamic value, double defaultValue) {
  if (value == null) return defaultValue;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  try {
    return double.parse(value.toString());
  } catch (_) {
    return defaultValue;
  }
}

/// 校验action字段值
String _validAction(dynamic value) {
  const valid = {'buy', 'hold', 'avoid'};
  final str = value?.toString() ?? 'hold';
  return valid.contains(str) ? str : 'hold';
}

/// 校验trend字段值
String _validTrend(dynamic value) {
  const valid = {'bullish', 'bearish', 'neutral'};
  final str = value?.toString() ?? 'neutral';
  return valid.contains(str) ? str : 'neutral';
}

/// 安全将动态值转为List<String>
List<String> _toStringList(dynamic value) {
  if (value == null) return ['市场系统性风险不可忽视'];
  if (value is List) {
    final list = value.map((e) => e.toString()).toList();
    return list.isEmpty ? ['市场系统性风险不可忽视'] : list;
  }
  return ['市场系统性风险不可忽视'];
}

/// 安全解析列表
List<T> _parseList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value == null) return [];
  if (value is! List) return [];
  try {
    return value
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  } catch (_) {
    return [];
  }
}
