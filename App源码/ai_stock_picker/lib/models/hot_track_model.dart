/// 热点追踪模块 - 数据模型
///
/// AI决策引擎输出结构化模型

/// 决策信号
enum ActionSignal { go, reject, wait }

/// 新闻评级
enum NewsRating { s, a, b, c }

/// 热点追踪结果
class HotTrackResult {
  final ActionSignal actionSignal;
  final NewsRating newsRating;
  final String coreLogic;       // 核心炒作逻辑
  final List<TargetStock> targets; // 核心标的池
  final ExecutionParams? executionParams; // 量化执行参数
  final String newsTitle;       // 触发新闻标题
  final String newsTime;        // 新闻时间
  final String rawAIResponse;   // AI原始回复

  const HotTrackResult({
    required this.actionSignal,
    required this.newsRating,
    required this.coreLogic,
    required this.targets,
    this.executionParams,
    required this.newsTitle,
    required this.newsTime,
    required this.rawAIResponse,
  });

  /// 信号颜色标识
  String get signalLabel {
    switch (actionSignal) {
      case ActionSignal.go: return 'GO';
      case ActionSignal.reject: return 'REJECT';
      case ActionSignal.wait: return 'WAIT';
    }
  }

  /// 评级标签
  String get ratingLabel {
    switch (newsRating) {
      case NewsRating.s: return 'S';
      case NewsRating.a: return 'A';
      case NewsRating.b: return 'B';
      case NewsRating.c: return 'C';
    }
  }

  /// 是否可狙击
  bool get isActionable => actionSignal == ActionSignal.go && (newsRating == NewsRating.s || newsRating == NewsRating.a);
}

/// 核心标的
class TargetStock {
  final String code;       // 股票代码
  String name;              // 股票名称（可被行情API校验更正）
  final String reason;     // 选股理由
  final double marketCap;  // 流通市值（亿元）
  double? price;            // 实时价格
  double? changePct;        // 涨跌幅%
  double? turnover;         // 换手率

  TargetStock({
    required this.code,
    required this.name,
    required this.reason,
    required this.marketCap,
    this.price,
    this.changePct,
    this.turnover,
  });

  /// 格式化代码为标准格式（SH.600xxx / SZ.000xxx）
  String get symbol {
    if (code.startsWith('6')) return 'SH.$code';
    if (code.startsWith('0') || code.startsWith('3')) return 'SZ.$code';
    if (code.startsWith('8') || code.startsWith('4')) return 'BJ.$code';
    return code;
  }
}

/// 量化执行参数
class ExecutionParams {
  final double minBidVolumeMultiplier; // 集合竞价量倍率
  final double openingPriceMin;        // 开盘涨幅下限%
  final double openingPriceMax;        // 开盘涨幅上限%
  final String triggerAction;          // 触发动作
  final String hardStopLoss;           // 硬止损

  const ExecutionParams({
    required this.minBidVolumeMultiplier,
    required this.openingPriceMin,
    required this.openingPriceMax,
    required this.triggerAction,
    required this.hardStopLoss,
  });

  /// 开盘涨幅区间描述
  String get openingRange => '>${openingPriceMin.toStringAsFixed(0)}% 且 <${openingPriceMax.toStringAsFixed(0)}%';
}
