import 'dart:math';

/// RAG知识检索服务 — TF-IDF向量化 + 余弦相似度搜索
///
/// 提供金融领域知识检索，降低LLM幻觉率
/// 后续可升级为embedding-based向量检索
class RAGService {
  static final RAGService _instance = RAGService._();
  factory RAGService() => _instance;
  RAGService._() { _buildIndex(); }

  List<_KnowledgeDoc> _docs = [];
  Map<String, double> _idf = {};

  // ════════════════════════════════════════════════════════════════
  // 金融知识库（分三类）
  // ════════════════════════════════════════════════════════════════
  void _buildIndex() {
    _docs = [];

    // ─── 类别1: A股交易规则知识 ───
    _addDoc('trading_rules', 'A股交易时间 交易规则',
      'A股交易时间为周一至周五上午9:30-11:30，下午13:00-15:00。'
      '9:15-9:25为集合竞价时间，其中9:20-9:25不可撤单。'
      'A股实行T+1交易制度，当天买入的股票下一个交易日才能卖出。'
      '涨跌停板制度：主板±10%，创业板/科创板±20%，北交所±30%，ST股±5%。'
      '交易费用包括印花税(仅卖出0.05%)、佣金(约0.025%)、过户费等。');

    _addDoc('trading_rules', '港股交易时间 港股通',
      '港股交易时间为周一至周五上午9:30-12:00，下午13:00-16:00。'
      '港股实行T+0交易制度(当天可买卖)，但资金结算为T+2。'
      '港股没有涨跌停板限制。港股通包含沪港通和深港通，内地投资者可直接买卖港股。');

    _addDoc('trading_rules', '美股交易时间 美股规则',
      '美股交易时间为美东时间周一至周五9:30-16:00（北京时间21:30-次日4:00，夏令时）。'
      '盘前交易4:00-9:30，盘后交易16:00-20:00。美股实行T+0交易制度。'
      '美股有熔断机制：标普500下跌7%/13%/20%触发不同级别熔断。');

    // ─── 类别2: 技术指标知识库 ───
    _addDoc('indicators', 'MACD指标 金叉死叉',
      'MACD（指数平滑异同移动平均线）由DIF线、DEA线和柱状图(BAR)组成。'
      'DIF=EMA(12)-EMA(26)，DEA=EMA(DIF,9)，BAR=2×(DIF-DEA)。\n'
      '金叉信号：DIF上穿DEA，通常视为买入信号。\n'
      '死叉信号：DIF下穿DEA，通常视为卖出信号。\n'
      '底背离：股价创新低但DIF未创新低，看涨信号。\n'
      '顶背离：股价创新高但DIF未创新高，看跌信号。\n'
      '零轴之上为多头市场，零轴之下为空头市场。');

    _addDoc('indicators', 'RSI指标 相对强弱 超买超卖',
      'RSI（相对强弱指标）取值范围0-100。\n'
      'RSI>70：超买区域，可能回调，考虑卖出。\n'
      'RSI<30：超卖区域，可能反弹，考虑买入。\n'
      'RSI=50附近：多空均衡。\n'
      'RSI背离是重要的反转信号。'
      '参数设置：短期常用6日RSI，中期14日RSI。');

    _addDoc('indicators', 'KDJ指标 随机指标',
      'KDJ由K线、D线、J线组成。\n'
      'K>80为超买，K<20为超卖。\n'
      'K线上穿D线为金叉(买入信号)，K线下穿D线为死叉(卖出信号)。\n'
      'J线>100为严重超买，J线<0为严重超卖。\n'
      'KDJ适合震荡市，单边趋势中容易钝化。');

    _addDoc('indicators', '布林带 BOLL 轨道',
      '布林带由上轨、中轨(20日均线)、下轨组成。\n'
      '价格触及上轨：超买，可能回调。\n'
      '价格触及下轨：超卖，可能反弹。\n'
      '带宽收窄：变盘信号，可能出现大行情。\n'
      '带宽扩张：趋势确认信号。\n'
      '布林带宽度=(上轨-下轨)/中轨，反映波动率。');

    _addDoc('indicators', '均线系统 MA 多头空头排列',
      '均线(MA)是N日收盘价的平均值。常用组合：5日/10日/20日/60日/120日/250日。\n'
      '多头排列：短期均线在长期均线上方，看涨。\n'
      '空头排列：短期均线在长期均线下方，看跌。\n'
      '金叉：短期均线上穿长期均线，买入信号。\n'
      '死叉：短期均线下穿长期均线，卖出信号。\n'
      '均线支撑：股价回踩均线获得支撑。\n'
      '均线压力：股价反弹至均线遇阻。');

    _addDoc('indicators', '成交量 量价关系',
      '量价配合四大法则：\n'
      '价涨量增：上涨趋势确认，看多。\n'
      '价涨量缩：上涨乏力，警惕回调。\n'
      '价跌量增：下跌加速，看空。\n'
      '价跌量缩：下跌动能减弱，可能见底。\n'
      '放量突破关键位置是有效突破的重要确认。\n'
      '天量天价：巨量之后往往见顶。\n'
      '地量地价：缩量至极低水平可能见底。');

    // ─── 类别3: 基本面知识 ───
    _addDoc('fundamentals', '市盈率PE 估值方法',
      '市盈率(PE)=股价/每股收益(EPS)。\n'
      'PE反映市场对公司未来盈利的预期。\n'
      'A股主板合理PE一般在10-30倍之间，成长股可更高。\n'
      '银行股PE通常5-10倍，科技股PE可30-60倍。\n'
      '低PE不一定便宜，可能是盈利质量差或周期性高点。\n'
      '高PE不一定贵，可能是高成长预期。\n'
      '建议结合PEG(PE/增长率)综合判断，PEG<1相对合理。');

    _addDoc('fundamentals', '市净率PB 净资产',
      '市净率(PB)=股价/每股净资产。\n'
      'PB<1意味着股价低于每股净资产(破净)。\n'
      '银行、钢铁等重资产行业常用PB估值，PB<1可能低估。\n'
      '科技、消费等轻资产行业PB通常较高。\n'
      '建议结合ROE判断：高ROE公司PB可以更高。');

    _addDoc('fundamentals', 'ROE 净资产收益率 杜邦分析',
      'ROE(净资产收益率)=净利润/净资产×100%。\n'
      'ROE>15%通常被认为是优秀公司。\n'
      'ROE>20%是非常优秀的公司。\n'
      '持续高ROE(连续5年>15%)是巴菲特选股的重要标准。\n'
      'ROE=净利率×总资产周转率×权益乘数(杜邦分析)。\n'
      '高ROE需要关注是否来自高杠杆(权益乘数过高)。');

    _buildIDF();
  }

  void _addDoc(String category, String title, String content) {
    _docs.add(_KnowledgeDoc(category: category, title: title, content: content));
  }

  // ════════════════════════════════════════════════════════════════
  // TF-IDF 计算
  // ════════════════════════════════════════════════════════════════
  void _buildIDF() {
    final totalDocs = _docs.length;
    final docFreq = <String, int>{};

    for (final doc in _docs) {
      final terms = _tokenize(doc.indexText);
      final seen = <String>{};
      for (final t in terms) {
        if (!seen.contains(t)) {
          docFreq[t] = (docFreq[t] ?? 0) + 1;
          seen.add(t);
        }
      }
    }

    _idf = {};
    for (final entry in docFreq.entries) {
      _idf[entry.key] = log((totalDocs + 1) / (entry.value + 1)) + 1;
    }
  }

  List<String> _tokenize(String text) {
    // 简化版分词：按空格/标点分割 + 单字过滤 + 2-gram
    final raw = text
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), ' ')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && t.length >= 2)
        .toList();
    // 中文2-gram
    final bigrams = <String>[];
    for (final w in raw) {
      if (RegExp(r'^[\u4e00-\u9fa5]+$').hasMatch(w) && w.length >= 2) {
        for (var i = 0; i < w.length - 1; i++) {
          bigrams.add(w.substring(i, i + 2));
        }
      }
    }
    return [...raw, ...bigrams];
  }

  Map<String, double> _tfIdfVector(_KnowledgeDoc doc) {
    final terms = _tokenize(doc.indexText);
    final tf = <String, int>{};
    for (final t in terms) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final vec = <String, double>{};
    for (final entry in tf.entries) {
      final idfVal = _idf[entry.key] ?? 1.0;
      vec[entry.key] = entry.value * idfVal / terms.length;
    }
    return vec;
  }

  double _cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (final entry in a.entries) {
      dot += entry.value * (b[entry.key] ?? 0);
      normA += entry.value * entry.value;
    }
    for (final v in b.values) {
      normB += v * v;
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  // ════════════════════════════════════════════════════════════════
  // 主搜索接口
  // ════════════════════════════════════════════════════════════════
  /// 搜索与问题最相关的金融知识片段
  List<String> searchContext(String question, {int topK = 5}) {
    if (_docs.isEmpty) { _buildIndex(); }

    final queryVec = _tfIdfVector(_KnowledgeDoc(category: '', title: '', content: question));
    // Override the index text for the query
    final queryTokens = _tokenize(question);
    final queryTf = <String, int>{};
    for (final t in queryTokens) {
      queryTf[t] = (queryTf[t] ?? 0) + 1;
    }
    final qv = <String, double>{};
    for (final entry in queryTf.entries) {
      final idfVal = _idf[entry.key] ?? 1.0;
      qv[entry.key] = entry.value * idfVal / queryTokens.length;
    }

    final scores = <_ScoredDoc>[];
    for (final doc in _docs) {
      final dv = _tfIdfVector(doc);
      scores.add(_ScoredDoc(doc, _cosineSimilarity(qv, dv)));
    }

    scores.sort((a, b) => b.score.compareTo(a.score));

    final results = <String>[];
    for (var i = 0; i < topK && i < scores.length; i++) {
      if (scores[i].score > 0.05) {
        results.add(scores[i].doc.content);
      }
    }
    return results;
  }

  /// 获取知识库统计
  Map<String, int> getStats() {
    final cats = <String, int>{};
    for (final d in _docs) {
      cats[d.category] = (cats[d.category] ?? 0) + 1;
    }
    return cats;
  }
}

class _KnowledgeDoc {
  final String category;
  final String title;
  final String content;
  String get indexText => '$title $content';

  _KnowledgeDoc({required this.category, required this.title, required this.content});
}

class _ScoredDoc {
  final _KnowledgeDoc doc;
  final double score;
  _ScoredDoc(this.doc, this.score);
}
