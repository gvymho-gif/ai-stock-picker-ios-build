import '../models/ai_query_intent.dart';

/// 金融NLP语义理解引擎 — 意图分类 + 命名实体识别 + 槽位填充
///
/// 对标同花顺i问财NER（96-97%准确率），当前用规则+关键词实现，
/// 后续可升级为轻量级BERT金融NER模型。
class NLPService {
  static final NLPService _instance = NLPService._();
  factory NLPService() => _instance;
  NLPService._();

  // ════════════════════════════════════════════════════════════════
  // 股票代码/名称映射表（常见A股核心资产 + 热门股）
  // ════════════════════════════════════════════════════════════════
  static const Map<String, String> _stockNameToCode = {
    // 拼音缩写
    'mt': '600519',  '茅台': '600519',  '贵州茅台': '600519',
    'wly': '000858',  '五粮液': '000858',
    'zgpa': '601318',  '中国平安': '601318', '平安': '601318',
    'zssh': '600036',  '招商银行': '600036', '招行': '600036',
    'byd': '002594',   '比亚迪': '002594',
    'ndsd': '300750',  '宁德时代': '300750', '宁德': '300750',
    'mq': '000333',    '美的集团': '000333', '美的': '000333',
    'gl': '000651',    '格力电器': '000651', '格力': '000651',
    'hg': '600585',    '海螺水泥': '600585', '海螺': '600585',
    'hrkj': '002415',  '海康威视': '002415', '海康': '002415',
    'lxjm': '600887',  '伊利股份': '600887', '伊利': '600887',
    'zxzq': '600030',  '中信证券': '600030', '中信': '600030',
    'dfcf': '300059',  '东方财富': '300059',
    'zxgs': '000063',  '中兴通讯': '000063',
    'hdny': '600900',  '长江电力': '600900',
    'zgjy': '601857',  '中国石油': '601857',
    'zgsy': '600028',  '中国石化': '600028',
    'zgdx': '601728',  '中国电信': '601728',
    'zglt': '600050',  '中国联通': '600050',
    'yhdl': '601985',  '中国核电': '601985',
    'zghy': '600941',  '中国移动': '600941',
    'zgja': '601988',  '中航光电': '002179',
    'hkws': '002415',
    'lxgf': '600887',
    'wka': '000002',   '万科A': '000002', '万科': '000002',
    'bd': '000725',    '京东方A': '000725', '京东方': '000725',
    'lf': '002460',    '赣锋锂业': '002460',
    'th': '300014',    '亿纬锂能': '300014',
    'lx': '300124',    '汇川技术': '300124',
    'smic': '688981',  '中芯国际': '688981', '中芯': '688981',
    'hwy': '688012',   '中微公司': '688012',
    'sx': '601012',    '隆基绿能': '601012', '隆基': '601012',
    'tw': '300274',    '阳光电源': '300274',
    'ynby': '000538',  '云南白药': '000538',
    'pfyh': '600000',  '浦发银行': '600000',
    'xyyh': '601166',  '兴业银行': '601166',
    'jtyh': '601328',  '交通银行': '601328',
    'jsyh': '601939',  '建设银行': '601939',
    'gsyh': '601398',  '工商银行': '601398',
    'nyyh': '601288',  '农业银行': '601288',
    'zgyh': '601988',  '中国银行': '601988',
    'gddl': '601985',
    // 港股
    'tx': '00700',     '腾讯': '00700',   '腾讯控股': '00700',
    'albb': '09988',   '阿里巴巴': '09988',  '阿里': '09988',
    'mtkd': '03690',   '美团': '03690',
    'xy': '01810',     '小米': '01810',    '小米集团': '01810',
    'jd': '09618',     '京东': '09618',
    'wy': '09999',     '网易': '09999',
    'xcp': '02015',    '理想汽车': '02015',
    'xl': '09866',     '蔚来': '09866',
    'xpy': '09888',    '百度': '09888',
    'ks': '01024',     '快手': '01024',
    // 美股
    'aapl': 'AAPL',    '苹果': 'AAPL',
    'googl': 'GOOGL',  '谷歌': 'GOOGL',
    'msft': 'MSFT',    '微软': 'MSFT',
    'amzn': 'AMZN',    '亚马逊': 'AMZN',
    'nvda': 'NVDA',    '英伟达': 'NVDA',
    'tsla': 'TSLA',    '特斯拉': 'TSLA',
    'meta': 'META',
    'baba': 'BABA',    '阿里美股': 'BABA',
    'nio': 'NIO',      '蔚来美股': 'NIO',
    'bidu': 'BIDU',
  };

  // 板块/行业关键词映射
  static const Map<String, List<String>> _sectorKeywords = {
    '科技': ['科技', 'TMT', 'AI', '人工智能', '半导体', '芯片', '5G', '云计算', '大数据', '物联网', '软件'],
    '新能源': ['新能源', '光伏', '锂电', '储能', '风电', '氢能', '碳中和', '新能源汽车', '电动车'],
    '消费': ['消费', '白酒', '食品', '家电', '零售', '医美', '免税'],
    '医药': ['医药', '医疗', '生物', '创新药', '中药', '疫苗', 'CRO', '医疗器械'],
    '金融': ['金融', '银行', '保险', '券商', '证券', '信托'],
    '地产': ['地产', '房地产', '物业', '建材'],
    '军工': ['军工', '国防', '航空'],
    '周期': ['煤炭', '有色', '钢铁', '化工', '石油', '黄金'],
  };

  // 技术指标关键词
  static const List<String> _indicatorKeywords = [
    'MACD', 'RSI', 'KDJ', '布林带', 'BOLL', '均线', 'MA', 'EMA',
    '成交量', '放量', '缩量', '换手率', '量比',
    '金叉', '死叉', '超买', '超卖', '背离',
    '支撑位', '压力位', '突破', '回调', '反弹',
    'ATR', 'OBV', 'WR', '威廉',
  ];

  // ════════════════════════════════════════════════════════════════
  // 金融数值条件正则提取
  // ════════════════════════════════════════════════════════════════
  static final List<_ConditionPattern> _conditionPatterns = [
    _ConditionPattern(RegExp(r'(市盈率|PE)\s*[<＜]\s*(\d+\.?\d*)'), 'PE', '<'),
    _ConditionPattern(RegExp(r'(市盈率|PE)\s*[>＞]\s*(\d+\.?\d*)'), 'PE', '>'),
    _ConditionPattern(RegExp(r'(市盈率|PE)\s*(<=|≤)\s*(\d+\.?\d*)'), 'PE', '<='),
    _ConditionPattern(RegExp(r'(市盈率|PE)\s*(>=|≥)\s*(\d+\.?\d*)'), 'PE', '>='),
    _ConditionPattern(RegExp(r'(市净率|PB)\s*[<＜]\s*(\d+\.?\d*)'), 'PB', '<'),
    _ConditionPattern(RegExp(r'(市净率|PB)\s*[>＞]\s*(\d+\.?\d*)'), 'PB', '>'),
    _ConditionPattern(RegExp(r'ROE\s*[>＞]\s*(\d+\.?\d*)'), 'ROE', '>'),
    _ConditionPattern(RegExp(r'ROE\s*[<＜]\s*(\d+\.?\d*)'), 'ROE', '<'),
    _ConditionPattern(RegExp(r'(市值|总市值)\s*[>＞]\s*(\d+\.?\d*)\s*(亿|万|万亿)?'), '市值', '>'),
    _ConditionPattern(RegExp(r'(市值|总市值)\s*[<＜]\s*(\d+\.?\d*)\s*(亿|万|万亿)?'), '市值', '<'),
    _ConditionPattern(RegExp(r'(净利润增长率|利润增速)\s*[>＞]\s*(\d+\.?\d*)'), '利润增速', '>'),
    _ConditionPattern(RegExp(r'(营收增长率|营收增速)\s*[>＞]\s*(\d+\.?\d*)'), '营收增速', '>'),
    _ConditionPattern(RegExp(r'(涨跌幅?|涨幅)\s*[>＞]\s*(\d+\.?\d*)'), '涨跌幅', '>'),
    _ConditionPattern(RegExp(r'(涨跌幅?|跌幅)\s*[<＜-]\s*(\d+\.?\d*)'), '涨跌幅', '<'),
    _ConditionPattern(RegExp(r'(股息率|分红率)\s*[>＞]\s*(\d+\.?\d*)'), '股息率', '>'),
    _ConditionPattern(RegExp(r'换手率\s*[>＞]\s*(\d+\.?\d*)'), '换手率', '>'),
    _ConditionPattern(RegExp(r'成交量.*?(放量|放大)'), '成交量', '放量'),
    _ConditionPattern(RegExp(r'近期.*?(上涨|下跌|涨|跌)'), '近期趋势', ''),
  ];

  // ════════════════════════════════════════════════════════════════
  // 主入口：完整语义解析
  // ════════════════════════════════════════════════════════════════
  AIQueryIntent parse(String question) {
    final normalized = question.toLowerCase().trim();

    final intent = _classifyIntent(normalized);
    final stockCodes = _extractStockCodes(normalized);
    final sectors = _extractSectors(normalized);
    final indicators = _extractIndicators(normalized);
    final conditions = _extractConditions(question); // 用原文匹配数字
    final isAboutMarket = _isMarketQuery(normalized);
    final isAboutComparison = _isComparisonQuery(normalized);
    final timeRange = _extractTimeRange(normalized);

    return AIQueryIntent(
      intent: intent,
      stockCodes: stockCodes,
      sectors: sectors,
      indicators: indicators,
      conditions: conditions,
      isAboutMarket: isAboutMarket,
      isAboutComparison: isAboutComparison,
      timeRange: timeRange,
      rawQuestion: question,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 意图分类 (8类)
  // ════════════════════════════════════════════════════════════════
  QueryIntentType _classifyIntent(String q) {
    // 选股意图: 包含筛选条件 + 选股关键词
    final stockPickKeywords = [
      '帮我找', '筛选', '选股', '有哪些', '推荐.*股', '找.*股票',
      '什么.*股.*好', '哪些.*股', '挑.*股', '潜力股', '牛股',
      '低估', '高股息', '成长股', '白马股', '蓝筹',
    ];
    if (stockPickKeywords.any((kw) => RegExp(kw).hasMatch(q))) {
      return QueryIntentType.stockPick;
    }

    // 对比意图
    if (_isComparisonQuery(q)) {
      return QueryIntentType.comparison;
    }

    // 诊股意图: 有明确股票代码/名称 + 分析关键词
    final stockCode = _extractStockCodes(q);
    final diagnoseKeywords = [
      '分析', '怎么样', '如何', '怎么看', '评价', '走势', '行情',
      '技术面', '基本面', '资金面', '估值', '财报', '业绩',
      '还能买', '该不该卖', '可以买', '值得买', '持有', '止损', '止盈',
    ];
    if (stockCode.isNotEmpty && diagnoseKeywords.any((kw) => q.contains(kw))) {
      return QueryIntentType.stockDiagnose;
    }
    if (stockCode.isNotEmpty) {
      return QueryIntentType.stockDiagnose; // 提股票名默认诊股
    }

    // 大盘意图
    final marketKeywords = [
      '大盘', '上证', '深证', '创业板', '科创板', 'A股.*走势',
      '市场.*走势', '指数', '沪深300', '今日.*行情', '市场.*整体',
    ];
    if (marketKeywords.any((kw) => RegExp(kw).hasMatch(q))) {
      return QueryIntentType.marketOverview;
    }

    // 板块意图
    final sectorKeywords = [
      '板块', '行业', '哪个.*板块', '热点', '概念', '赛道',
      '哪些.*行业', '板块.*分析',
    ];
    if (sectorKeywords.any((kw) => RegExp(kw).hasMatch(q)) || _extractSectors(q).isNotEmpty) {
      return QueryIntentType.sectorAnalysis;
    }

    // 资讯意图
    final newsKeywords = [
      '新闻', '消息', '公告', '最新动态', '发生了什么', '有什么.*消息',
      '利好', '利空', '政策',
    ];
    if (newsKeywords.any((kw) => RegExp(kw).hasMatch(q))) {
      return QueryIntentType.newsQuery;
    }

    // 基础知识意图
    final knowledgeKeywords = [
      '什么是', '什么意思', '如何计算', '怎么算', '解释', '含义',
      'MACD', 'RSI', 'KDJ', '市盈率', 'PE', 'PB', 'ROE',
      '交易时间', '涨跌停', 'T+1',
    ];
    if (knowledgeKeywords.any((kw) => q.contains(kw.toLowerCase())) && _extractStockCodes(q).isEmpty) {
      return QueryIntentType.knowledge;
    }

    return QueryIntentType.unknown;
  }

  // ════════════════════════════════════════════════════════════════
  // 股票代码提取
  // ════════════════════════════════════════════════════════════════
  List<String> _extractStockCodes(String q) {
    final codes = <String>{};

    // 6位数字代码 (A股)
    final code6Regex = RegExp(r'\b(\d{6})\b');
    for (final m in code6Regex.allMatches(q)) {
      final code = m.group(1)!;
      if (_isValidACode(code)) {
        codes.add(code);
      }
    }

    // 美股代码 (大写字母1-5个)
    final upperQ = q.toUpperCase();
    final usRegex = RegExp(r'\b([A-Z]{1,5})\b');
    for (final m in usRegex.allMatches(upperQ)) {
      final sym = m.group(1)!;
      if (_stockNameToCode.containsKey(sym) && codes.length < 5) {
        final code = _stockNameToCode[sym]!;
        if (code.length <= 5) codes.add(code); // 美股
      }
    }

    // 中文股票名称匹配
    for (final entry in _stockNameToCode.entries) {
      if (entry.key.length >= 2 && q.contains(entry.key)) {
        if (codes.length < 5) codes.add(entry.value);
      }
    }

    return codes.toList();
  }

  bool _isValidACode(String code) {
    if (code.length != 6) return false;
    final prefix = code.substring(0, 2);
    return ['60', '00', '30', '68'].contains(prefix);
  }

  // ════════════════════════════════════════════════════════════════
  // 板块/行业提取
  // ════════════════════════════════════════════════════════════════
  List<String> _extractSectors(String q) {
    final sectors = <String>[];
    for (final entry in _sectorKeywords.entries) {
      for (final kw in entry.value) {
        if (q.contains(kw)) {
          sectors.add(entry.key);
          break;
        }
      }
    }
    return sectors.toSet().toList();
  }

  // ════════════════════════════════════════════════════════════════
  // 技术指标提取
  // ════════════════════════════════════════════════════════════════
  List<String> _extractIndicators(String q) {
    return _indicatorKeywords.where((kw) => q.toUpperCase().contains(kw.toUpperCase())).toList();
  }

  // ════════════════════════════════════════════════════════════════
  // 金融条件提取
  // ════════════════════════════════════════════════════════════════
  List<StockCondition> _extractConditions(String q) {
    final conditions = <StockCondition>[];
    for (final pattern in _conditionPatterns) {
      for (final m in pattern.regex.allMatches(q)) {
        conditions.add(StockCondition(
          field: pattern.field,
          operator: pattern.operator,
          value: _extractValue(m),
        ));
      }
    }
    return conditions;
  }

  String _extractValue(RegExpMatch m) {
    if (m.groupCount >= 2) return m.group(2) ?? m.group(1) ?? '';
    return m.group(1) ?? '';
  }

  // ════════════════════════════════════════════════════════════════
  // 附属判断
  // ════════════════════════════════════════════════════════════════
  bool _isMarketQuery(String q) {
    final keywords = ['大盘', '市场', '指数', '上证', '深证', '创业板', '科创板', '沪深300', '整体', '宏观'];
    return keywords.any((kw) => q.contains(kw));
  }

  bool _isComparisonQuery(String q) {
    final keywords = ['对比', '比较', 'vs', '哪个更好', '哪个强', '哪个好', '区别'];
    return keywords.any((kw) => q.contains(kw.toLowerCase()));
  }

  String _extractTimeRange(String q) {
    if (RegExp(r'最近?[1一]周|近[1一]周|本周|这周').hasMatch(q)) return '1w';
    if (RegExp(r'最近?[1一]个?月|近[1一]月|本月|这个月').hasMatch(q)) return '1m';
    if (RegExp(r'最近?3(个)?月|近3月|季度').hasMatch(q)) return '3m';
    if (RegExp(r'最近?6(个)?月|近半年').hasMatch(q)) return '6m';
    if (RegExp(r'最近?[1一]年|近[1一]年|今年|本年').hasMatch(q)) return '1y';
    if (RegExp(r'最近?(\d+)天').hasMatch(q)) {
      final match = RegExp(r'最近?(\d+)天').firstMatch(q);
      return '${match!.group(1)}d';
    }
    return '';
  }

  /// 快速判断问题是否涉及具体股票
  bool hasStockCode(String q) => _extractStockCodes(q).isNotEmpty;
}

/// 条件解析内部类
class _ConditionPattern {
  final RegExp regex;
  final String field;
  final String operator;
  _ConditionPattern(this.regex, this.field, this.operator);
}
