/// AI查询意图解析结果 — 由NLPService解析生成
class AIQueryIntent {
  final QueryIntentType intent;
  final List<String> stockCodes;
  final List<String> sectors;
  final List<String> indicators;
  final List<StockCondition> conditions;
  final bool isAboutMarket;
  final bool isAboutComparison;
  final String timeRange;
  final String rawQuestion;

  const AIQueryIntent({
    required this.intent,
    this.stockCodes = const [],
    this.sectors = const [],
    this.indicators = const [],
    this.conditions = const [],
    this.isAboutMarket = false,
    this.isAboutComparison = false,
    this.timeRange = '',
    this.rawQuestion = '',
  });

  /// 问题是否与个股相关
  bool get isStockRelated => stockCodes.isNotEmpty;

  /// 需要注入的数据类型
  List<DataType> get requiredDataTypes {
    final types = <DataType>{};
    switch (intent) {
      case QueryIntentType.stockPick:
        types.addAll([DataType.marketIndex, DataType.sectorRanking, DataType.marketSentiment]);
        if (conditions.isNotEmpty) types.add(DataType.stockFilter);
        break;
      case QueryIntentType.stockDiagnose:
        types.addAll([DataType.stockDetail, DataType.technicalIndicators, DataType.financialReport]);
        if (sectors.isNotEmpty) types.add(DataType.sectorAnalysis);
        break;
      case QueryIntentType.marketOverview:
        types.addAll([DataType.marketIndex, DataType.sectorRanking, DataType.capitalFlow, DataType.marketSentiment]);
        break;
      case QueryIntentType.sectorAnalysis:
        types.addAll([DataType.sectorRanking, DataType.sectorAnalysis, DataType.hotNews]);
        break;
      case QueryIntentType.newsQuery:
        types.addAll([DataType.hotNews, DataType.marketIndex]);
        break;
      case QueryIntentType.comparison:
        types.addAll([DataType.stockDetail, DataType.technicalIndicators, DataType.financialReport]);
        break;
      case QueryIntentType.knowledge:
        types.add(DataType.knowledgeBase);
        break;
      case QueryIntentType.unknown:
        // 通用问题只注入大盘指数+市场情绪，避免无关数据淹没AI
        types.addAll([DataType.marketIndex, DataType.marketSentiment]);
        break;
    }
    if (isAboutMarket) {
      types.addAll([DataType.marketIndex, DataType.capitalFlow]);
    }
    return types.toList();
  }

  @override
  String toString() =>
      'AIQueryIntent(intent: $intent, stocks: $stockCodes, sectors: $sectors, indicators: $indicators, conditions: ${conditions.length})';
}

/// 问题意图类型
enum QueryIntentType {
  stockPick,       // 智能选股
  stockDiagnose,   // 个股诊股
  marketOverview,  // 大盘分析
  sectorAnalysis,  // 板块/行业分析
  newsQuery,       // 资讯查询
  comparison,      // 股票对比
  knowledge,       // 基础知识
  unknown,         // 未知/通用
}

/// 数据注入类型（语义路由时使用）
enum DataType {
  stockDetail,         // 个股详情
  technicalIndicators, // 技术指标
  financialReport,     // 财报数据
  marketIndex,         // 大盘指数
  sectorRanking,       // 板块排行
  sectorAnalysis,      // 板块分析
  capitalFlow,         // 北向/南向资金
  marketSentiment,     // 市场情绪
  hotNews,            // 热点新闻
  stockFilter,         // 股票筛选条件
  knowledgeBase,       // 知识库检索
}

/// 股票筛选条件槽位
class StockCondition {
  final String field;
  final String operator;
  final String value;

  const StockCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  String toDisplayString() {
    final opMap = {'<': '小于', '>': '大于', '<=': '不超过', '>=': '不低于'};
    final op = opMap[operator] ?? operator;
    final fieldMap = {
      'PE': '市盈率', 'PB': '市净率', 'ROE': 'ROE',
      '市值': '总市值', '利润增速': '净利润增长率',
      '营收增速': '营收增长率', '股息率': '股息率',
      '换手率': '换手率', '成交量': '成交量',
    };
    final f = fieldMap[field] ?? field;
    if (operator == '放量') return '$f放量';
    return '$f$op$value';
  }

  @override
  String toString() => 'StockCondition($field $operator $value)';
}
