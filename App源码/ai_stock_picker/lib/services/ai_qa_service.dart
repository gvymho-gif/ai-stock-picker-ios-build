import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/ai_model_config.dart';
import '../models/chat_message.dart';
import '../models/ai_query_intent.dart';
import 'ai_model_service.dart';
import 'local_data_service.dart';
import 'nlp_service.dart';
import 'rag_service.dart';
import 'financial_report_service.dart';

/// 极智问答服务 v10.0 - 接入完整个股分析 + 技术指标数据
///
/// 将 AIQAScreen 提问时，自动获取该股票的完整分析数据作为参考
/// 包括：价格分析、估值分析、技术分析(MACD/RSI/KDJ/均线/布林)、资金流、公司Profile等
class AIQAService {
  static const int _maxContextMessages = 30;
  static const Duration _httpTimeout = Duration(seconds: 60);
  static const Duration _aiTimeout = Duration(seconds: 300);

  final http.Client _client = http.Client();

  /// 清理AI输出的Markdown标记，转换为更专业的纯文本排版
  static String cleanMarkdown(String text) {
    return text
      // 移除 ### 标题标记，保留文字并加粗效果通过换行体现
      .replaceAllMapped(RegExp(r'#{3,6}\s*(.+?)(?=\n|$)'), (m) => '\n${m.group(1)}\n')
      // 移除 ** 加粗标记
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '')
      // 移除 * 斜体标记
      .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1) ?? '')
      // 移除 ` 代码标记
      .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1) ?? '')
      // 移除 --- 分隔线
      .replaceAll(RegExp(r'\n-{3,}\n'), '\n')
      // 移除 > 引用标记
      .replaceAllMapped(RegExp(r'^>\s*(.+?)$', multiLine: true), (m) => m.group(1) ?? '')
      // 移除多余的空行（保留最多一个空行）
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      // 移除行首行尾空白
      .trim();
  }

  Future<String> askQuestion(String question, {List<ChatMessage>? contextHistory}) async {
    final model = await AIModelService.getActiveModel();
    if (model == null) return '请先在设置中配置AI模型API';

    try {
      // 1. 语义解析 — 理解用户意图
      final intent = NLPService().parse(question);

      // 2. 语义路由 — 只获取相关的数据
      final marketContext = await _routeAndFetchData(intent);

      // 3. RAG — 金融知识库检索增强
      final ragContext = RAGService().searchContext(question, topK: 3);

      // 4. 财报数据（如有股票代码）
      String? financialContext;
      if (intent.stockCodes.isNotEmpty && intent.intent == QueryIntentType.stockDiagnose) {
        final report = await FinancialReportService().getReportSummary(intent.stockCodes.first);
        financialContext = FinancialReportService().formatForLLM(report, intent.stockCodes.first);
      }

      // 5. 对话摘要（长对话压缩）
      final summaryContext = _buildConversationSummary(contextHistory);

      // 6. 构建精准Prompt
      final systemPrompt = _buildSystemPrompt_v2(
        marketContext: marketContext,
        ragContext: ragContext,
        financialContext: financialContext,
        summaryContext: summaryContext,
        intent: intent,
      );

      final messages = _buildMessages_v2(systemPrompt, question, contextHistory, summaryContext);
      final result = await _sendToAI_v2(model, messages);
      return cleanMarkdown(result);
    } catch (e) {
      return '极智分析出错：${e.toString()}';
    }
  }

  // ============================================================
  // 语义路由 — 根据意图精准获取数据
  // ============================================================
  Future<String> _routeAndFetchData(AIQueryIntent intent) async {
    final types = intent.requiredDataTypes;
    final buffer = StringBuffer();
    buffer.writeln('\n========== 实时市场数据 ==========');
    buffer.writeln('获取时间: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('解析意图: ${intent.intent.name}');
    if (intent.stockCodes.isNotEmpty) buffer.writeln('目标股票: ${intent.stockCodes.join(", ")}');
    if (intent.sectors.isNotEmpty) buffer.writeln('相关板块: ${intent.sectors.join(", ")}');

    String result;

    // 大盘指数
    if (types.contains(DataType.marketIndex)) {
      result = await _fetchIndexData();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 市场情绪
    if (types.contains(DataType.marketSentiment)) {
      result = await _fetchMarketSentiment();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 板块排行
    if (types.contains(DataType.sectorRanking)) {
      result = await _fetchSectorData();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 资金流向（仅大盘/板块意图）
    if (types.contains(DataType.capitalFlow)) {
      result = await _fetchMoneyFlow();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 涨跌排行（仅选股意图）
    if (types.contains(DataType.sectorAnalysis)) {
      result = await _fetchUpDownRanking();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 热点新闻
    if (types.contains(DataType.hotNews)) {
      result = await _fetchNews();
      if (result.isNotEmpty) buffer.writeln(result);
    }

    // 个股完整分析（诊股/对比意图）— 直接用NLP解析出的股票代码
    if (types.contains(DataType.stockDetail) || types.contains(DataType.technicalIndicators)) {
      for (final code in intent.stockCodes.take(3)) {
        result = await _fetchStockByCode(code);
        if (result.isNotEmpty) buffer.writeln(result);
      }
      // 选股条件注入
      if (intent.conditions.isNotEmpty) {
        buffer.writeln('\n【用户筛选条件】');
        for (final cond in intent.conditions) {
          buffer.writeln('  - ${cond.toDisplayString()}');
        }
      }
    }

    buffer.writeln('========== 数据结束 ==========');
    return buffer.toString();
  }

  /// 对话摘要 — 每10轮压缩上下文，保留关键信息
  String _buildConversationSummary(List<ChatMessage>? history) {
    if (history == null || history.length < 10) return '';
    final buf = StringBuffer();
    buf.writeln('\n【对话历史要点】');
    final recentStocks = <String>{};
    for (final msg in history) {
      final codes = _extractStockCodesFromText(msg.content);
      recentStocks.addAll(codes);
    }
    if (recentStocks.isNotEmpty) {
      buf.writeln('讨论过的股票: ${recentStocks.join(", ")}');
    }
    // 提取最近5条的用户问题作为记忆
    final userMessages = history.where((m) => m.isUser).toList();
    final recent = userMessages.length > 5 ? userMessages.sublist(userMessages.length - 5) : userMessages;
    buf.writeln('最近关注:');
    for (final m in recent) {
      buf.writeln('  - ${m.content.length > 50 ? m.content.substring(0, 50) + '...' : m.content}');
    }
    return buf.toString();
  }

  List<String> _extractStockCodesFromText(String text) {
    // 简单提取文本中的6位数字代码
    final regex = RegExp(r'\b(\d{6})\b');
    return regex.allMatches(text).map((m) => m.group(1)!).toSet().toList();
  }

  // ============================================================
  // 数据获取 (各子方法)
  // ============================================================

  /// 个股完整分析 — 直接使用NLP解析出的股票代码，支持A股/港股/美股
  Future<String> _fetchStockByCode(String stockCode) async {
    try {
      final api = LocalDataService();
      final stockData = await api.searchStock(stockCode);

      if (stockData == null || stockData.isEmpty) {
        return '\n【个股分析: $stockCode】\n  未找到相关数据';
      }

      final buf = StringBuffer('\n【个股完整分析: ${stockData['name']}(${stockData['symbol']})】');

      // 1. 基本信息
      final price = _safeDouble(stockData['price']);
      final changePct = _safeDouble(stockData['change_pct']);
      if (price > 0) {
        final sign = changePct >= 0 ? '+' : '';
        buf.writeln('  现价: ${price.toStringAsFixed(2)} ($sign${changePct.toStringAsFixed(2)}%)');
      }

      // 2. 估值指标（含ROE/营收增速）
      if (stockData['pe_ratio'] != null) buf.writeln('  PE: ${_formatNum(stockData['pe_ratio'])}倍');
      if (stockData['pb_ratio'] != null) buf.writeln('  PB: ${_formatNum(stockData['pb_ratio'])}倍');
      if (stockData['roe'] != null) buf.writeln('  ROE: ${_formatNum(stockData['roe'])}%');
      if (stockData['revenue_growth'] != null) buf.writeln('  营收增速: ${_formatNum(stockData['revenue_growth'])}%');
      if (stockData['eps'] != null) buf.writeln('  EPS: ${_formatNum(stockData['eps'])}');
      if (stockData['dividend_yield'] != null) buf.writeln('  股息率: ${_formatNum(stockData['dividend_yield'])}%');

      // 3. 技术指标（MACD/RSI/KDJ/均线/布林带/成交量/换手率）- 从K线数据实时计算
      final symbol = stockData['symbol']?.toString() ?? '';
      final market = stockData['market']?.toString() ?? '';
      final turnoverRate = _safeDouble(stockData['turnover_rate']);
      if (symbol.isNotEmpty) {
        final techData = await _fetchTechnicalIndicators(symbol, market, turnoverRate);
        if (techData.isNotEmpty) buf.writeln(techData);
      }

      // 4. AI 分析评分
      final aiAnalysis = stockData['ai_analysis'] as Map<String, dynamic>? ?? {};
      if (aiAnalysis.isNotEmpty) {
        final score = _safeDouble(aiAnalysis['score']);
        final action = aiAnalysis['action'] ?? '';
        final reason = aiAnalysis['reason'] ?? '';
        buf.writeln('  AI综合评分: ${(score * 100).toStringAsFixed(0)}分  建议: $action');
        if (reason.isNotEmpty) buf.writeln('  AI分析: $reason');

        final detail = aiAnalysis['detail'] as Map<String, dynamic>? ?? {};
        if (detail.isNotEmpty) {
          if (detail['fundamental_score'] != null) buf.writeln('  基本面评分: ${(_safeDouble(detail['fundamental_score']) * 100).toStringAsFixed(0)}');
          if (detail['technical_score'] != null) buf.writeln('  技术面评分: ${(_safeDouble(detail['technical_score']) * 100).toStringAsFixed(0)}');
          if (detail['capital_score'] != null) buf.writeln('  资金面评分: ${(_safeDouble(detail['capital_score']) * 100).toStringAsFixed(0)}');
          if (detail['momentum_score'] != null) buf.writeln('  动量面评分: ${(_safeDouble(detail['momentum_score']) * 100).toStringAsFixed(0)}');
        }
      }

      // 5. 各模块分析
      final analysis = stockData['analysis'] as Map<String, dynamic>? ?? {};
      if (analysis.isNotEmpty) {
        buf.writeln('\n  --- 各模块分析 ---');
        analysis.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            final title = value['title'] ?? key;
            final sentiment = value['sentiment'] ?? '';
            final score = _safeDouble(value['score']);
            final advice = value['advice'] ?? '';
            buf.writeln('  $title: $sentiment (${(score * 100).toStringAsFixed(0)}分)');
            if (advice.isNotEmpty && advice.length < 100) buf.writeln('    极智解读: $advice');
          }
        });
      }

      // 6. 公司Profile
      final companyProfile = stockData['company_profile'] as Map<String, dynamic>? ?? {};
      if (companyProfile.isNotEmpty) {
        buf.writeln('\n  --- 公司信息 ---');
        if (companyProfile['industry'] != null) buf.writeln('  行业: ${companyProfile['industry']}');
        if (companyProfile['main_business'] != null) buf.writeln('  主营业务: ${companyProfile['main_business']}');
      }

      return buf.toString();
    } catch (e) {
      return '\n【个股分析: $stockCode】\n  获取失败: $e';
    }
  }

  // ============================================================
  // 技术指标计算 - MACD / RSI / KDJ / 均线 / 布林带
  // ============================================================

  /// 从新浪K线API获取日K数据并计算全部技术指标（含历史趋势）
  Future<String> _fetchTechnicalIndicators(String symbol, String market, double turnoverRate) async {
    try {
      // 将 symbol 转为新浪API格式 (如 600028.SS → sh600028)
      String sinaCode = _toSinaCode(symbol, market);
      if (sinaCode.isEmpty) return '';

      // 获取120个交易日K线数据（计算MACD需要至少100根）
      final resp = await _client.get(
        Uri.parse('https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData?symbol=$sinaCode&scale=240&ma=no&datalen=120'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://finance.sina.com.cn'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200 || resp.body.isEmpty) return '';

      final List<dynamic> klineRaw = json.decode(resp.body) as List? ?? [];
      if (klineRaw.length < 30) return '';  // 数据太少无法计算

      // 解析K线数据
      final opens = <double>[];
      final closes = <double>[];
      final highs = <double>[];
      final lows = <double>[];
      final volumes = <double>[];
      final dates = <String>[];

      for (final item in klineRaw) {
        opens.add(_safeDouble(item['open']));
        closes.add(_safeDouble(item['close']));
        highs.add(_safeDouble(item['high']));
        lows.add(_safeDouble(item['low']));
        volumes.add(_safeDouble(item['volume']));
        dates.add(item['day']?.toString() ?? '');
      }

      final curPrice = closes.last;
      final buf = StringBuffer('\n  --- 技术指标详细数据 ---');

      // ============================================================
      // 1. 均线系统 (MA5/MA10/MA20/MA60) + 支撑压力位
      // ============================================================
      final ma5 = _calcMA(closes, 5);
      final ma10 = _calcMA(closes, 10);
      final ma20 = _calcMA(closes, 20);
      final ma60 = _calcMA(closes, 60);

      buf.writeln('  【均线系统】');
      buf.writeln('    当前价: ${curPrice.toStringAsFixed(2)}');
      if (ma5 > 0) {
        final diff = ((curPrice - ma5) / ma5 * 100);
        buf.writeln('    MA5: ${ma5.toStringAsFixed(2)} (偏离${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}%) ${curPrice > ma5 ? '✓站上' : '✗跌破'}');
      }
      if (ma10 > 0) {
        final diff = ((curPrice - ma10) / ma10 * 100);
        buf.writeln('    MA10: ${ma10.toStringAsFixed(2)} (偏离${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}%) ${curPrice > ma10 ? '✓站上' : '✗跌破'}');
      }
      if (ma20 > 0) {
        final diff = ((curPrice - ma20) / ma20 * 100);
        buf.writeln('    MA20: ${ma20.toStringAsFixed(2)} (偏离${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}%) ${curPrice > ma20 ? '✓站上' : '✗跌破'}');
      }
      if (ma60 > 0) {
        final diff = ((curPrice - ma60) / ma60 * 100);
        buf.writeln('    MA60: ${ma60.toStringAsFixed(2)} (偏离${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}%) ${curPrice > ma60 ? '✓站上' : '✗跌破'}');
      }

      // 均线排列判断
      if (ma5 > 0 && ma10 > 0 && ma20 > 0) {
        if (ma5 > ma10 && ma10 > ma20) {
          buf.writeln('    均线形态: 多头排列 (MA5>MA10>MA20)，趋势偏多');
        } else if (ma5 < ma10 && ma10 < ma20) {
          buf.writeln('    均线形态: 空头排列 (MA5<MA10<MA20)，趋势偏空');
        } else {
          buf.writeln('    均线形态: 交叉缠绕，趋势不明');
        }
      }

      // 支撑位与压力位
      buf.writeln('    支撑位: ${_findSupport(closes, ma5, ma10, ma20, ma60, lows).toStringAsFixed(2)}');
      buf.writeln('    压力位: ${_findResistance(closes, ma5, ma10, ma20, ma60, highs).toStringAsFixed(2)}');

      // ============================================================
      // 2. MACD (12,26,9) - 含近5日趋势
      // ============================================================
      final macdHistory = _calcMACDHistory(closes);
      final difList = macdHistory['dif'] as List<double>;
      final deaList = macdHistory['dea'] as List<double>;
      final histList = macdHistory['histogram'] as List<double>;

      buf.writeln('  【MACD(12,26,9)】');
      buf.writeln('    DIF: ${difList.last.toStringAsFixed(3)}');
      buf.writeln('    DEA: ${deaList.last.toStringAsFixed(3)}');
      buf.writeln('    MACD柱: ${histList.last.toStringAsFixed(3)}');

      // 零轴位置
      if (difList.last > 0 && deaList.last > 0) {
        buf.writeln('    零轴: DIF/DEA均在零轴上方，中期趋势偏多');
      } else if (difList.last < 0 && deaList.last < 0) {
        buf.writeln('    零轴: DIF/DEA均在零轴下方，中期趋势偏空');
      } else if (difList.last > 0 && deaList.last < 0) {
        buf.writeln('    零轴: DIF在零轴上方/DEA在零轴下方，趋势转换中');
      }

      // 金叉/死叉判断
      final isGoldenCross = difList.length >= 2 && difList[difList.length - 2] <= deaList[deaList.length - 2] && difList.last > deaList.last;
      final isDeathCross = difList.length >= 2 && difList[difList.length - 2] >= deaList[deaList.length - 2] && difList.last < deaList.last;
      if (isGoldenCross) {
        buf.writeln('    交叉信号: ★金叉形成（DIF上穿DEA），看多信号');
      } else if (isDeathCross) {
        buf.writeln('    交叉信号: ★死叉形成（DIF下穿DEA），看空信号');
      } else if (difList.last > deaList.last) {
        buf.writeln('    交叉信号: DIF在DEA上方，${histList.last > 0 ? '金叉状态(多头)' : '死叉收敛中'}');
      } else {
        buf.writeln('    交叉信号: DIF在DEA下方，${histList.last < 0 ? '死叉状态(空头)' : '金叉收敛中'}');
      }

      // 近5日MACD趋势
      buf.writeln('    近5日趋势:');
      final trendN = histList.length < 5 ? histList.length : 5;
      for (int i = histList.length - trendN; i < histList.length; i++) {
        final d = dates.length > i ? (dates[i].length >= 10 ? dates[i].substring(5, 10) : dates[i]) : '';
        final hSign = histList[i] >= 0 ? '+' : '';
        final bar = histList[i] >= 0 ? '█' * (histList[i].abs() * 20).round().clamp(1, 20) : '░' * (histList[i].abs() * 20).round().clamp(1, 20);
        buf.writeln('      $d DIF:${difList[i].toStringAsFixed(3)} DEA:${deaList[i].toStringAsFixed(3)} 柱:${hSign}${histList[i].toStringAsFixed(3)} $bar');
      }

      // 柱状线趋势判断
      if (histList.length >= 3) {
        final h3 = histList[histList.length - 3];
        final h2 = histList[histList.length - 2];
        final h1 = histList.last;
        if (h1 > h2 && h2 > h3) {
          buf.writeln('    柱状趋势: 连续缩短(红柱扩大)，多头动能增强');
        } else if (h1 < h2 && h2 < h3) {
          buf.writeln('    柱状趋势: 连续缩短(绿柱扩大)，空头动能增强');
        } else if (h1 > h2 && h2 < h3) {
          buf.writeln('    柱状趋势: 柱状线拐头向上，动能转强');
        } else if (h1 < h2 && h2 > h3) {
          buf.writeln('    柱状趋势: 柱状线拐头向下，动能转弱');
        }
      }

      // ============================================================
      // 3. RSI (6,14,24) - 含近5日趋势
      // ============================================================
      final rsi6List = _calcRSIHistory(closes, 6);
      final rsi14List = _calcRSIHistory(closes, 14);

      buf.writeln('  【RSI】');
      buf.writeln('    RSI6: ${rsi6List.last.toStringAsFixed(1)}');
      buf.writeln('    RSI14: ${rsi14List.last.toStringAsFixed(1)}');

      // RSI区间判断
      if (rsi14List.last > 80) {
        buf.writeln('    区间: 超买区(>80)，短期回调风险较大');
      } else if (rsi14List.last > 70) {
        buf.writeln('    区间: 偏强区(70-80)，注意追高风险');
      } else if (rsi14List.last < 20) {
        buf.writeln('    区间: 超卖区(<20)，短期可能反弹');
      } else if (rsi14List.last < 30) {
        buf.writeln('    区间: 偏弱区(20-30)，关注底部信号');
      } else {
        buf.writeln('    区间: 中性区(30-70)，无明显超买超卖');
      }

      // RSI背离检测（近10日）
      if (closes.length >= 10 && rsi14List.length >= 10) {
        final priceHigh1 = closes[closes.length - 1];
        final priceHigh2 = closes[closes.length - 5];
        final rsiHigh1 = rsi14List[rsi14List.length - 1];
        final rsiHigh2 = rsi14List[rsi14List.length - 5];
        if (priceHigh1 > priceHigh2 && rsiHigh1 < rsiHigh2) {
          buf.writeln('    背离信号: ⚠顶背离（价格创新高但RSI未创新高），注意回调风险');
        } else if (priceHigh1 < priceHigh2 && rsiHigh1 > rsiHigh2) {
          buf.writeln('    背离信号: ★底背离（价格创新低但RSI未创新低），关注反弹机会');
        }
      }

      // 近5日RSI趋势
      buf.writeln('    近5日趋势:');
      final rsiN = rsi14List.length < 5 ? rsi14List.length : 5;
      for (int i = rsi14List.length - rsiN; i < rsi14List.length; i++) {
        final d = dates.length > i + (closes.length - rsi14List.length) ? (dates[i + (closes.length - rsi14List.length)].length >= 10 ? dates[i + (closes.length - rsi14List.length)].substring(5, 10) : '') : '';
        buf.writeln('      $d RSI6:${rsi6List[i].toStringAsFixed(1)} RSI14:${rsi14List[i].toStringAsFixed(1)}');
      }

      // ============================================================
      // 4. KDJ (9,3,3) - 含近5日趋势与金叉/死叉
      // ============================================================
      final kdjHistory = _calcKDJHistory(highs, lows, closes);
      final kList = kdjHistory['k'] as List<double>;
      final dList = kdjHistory['d'] as List<double>;
      final jList = kdjHistory['j'] as List<double>;

      buf.writeln('  【KDJ(9,3,3)】');
      buf.writeln('    K: ${kList.last.toStringAsFixed(1)}');
      buf.writeln('    D: ${dList.last.toStringAsFixed(1)}');
      buf.writeln('    J: ${jList.last.toStringAsFixed(1)}');

      // KDJ金叉/死叉
      final kdGolden = kList.length >= 2 && kList[kList.length - 2] <= dList[dList.length - 2] && kList.last > dList.last;
      final kdDeath = kList.length >= 2 && kList[kList.length - 2] >= dList[dList.length - 2] && kList.last < dList.last;
      if (kdGolden) {
        buf.writeln('    交叉信号: ★金叉（K上穿D），看多信号');
      } else if (kdDeath) {
        buf.writeln('    交叉信号: ★死叉（K下穿D），看空信号');
      } else if (kList.last > dList.last) {
        buf.writeln('    交叉信号: K在D上方，偏多');
      } else {
        buf.writeln('    交叉信号: K在D下方，偏空');
      }

      // 超买超卖
      if (jList.last > 100) {
        buf.writeln('    超买超卖: J值超100，极度超买，注意回调');
      } else if (jList.last < 0) {
        buf.writeln('    超买超卖: J值低于0，极度超卖，关注反弹');
      } else if (kList.last > 80 && dList.last > 80) {
        buf.writeln('    超买超卖: K/D均超80，超买区');
      } else if (kList.last < 20 && dList.last < 20) {
        buf.writeln('    超买超卖: K/D均低于20，超卖区');
      }

      // 近5日KDJ趋势
      buf.writeln('    近5日趋势:');
      final kdjN = kList.length < 5 ? kList.length : 5;
      for (int i = kList.length - kdjN; i < kList.length; i++) {
        final d = dates.length > i + (closes.length - kList.length) ? (dates[i + (closes.length - kList.length)].length >= 10 ? dates[i + (closes.length - kList.length)].substring(5, 10) : '') : '';
        buf.writeln('      $d K:${kList[i].toStringAsFixed(1)} D:${dList[i].toStringAsFixed(1)} J:${jList[i].toStringAsFixed(1)}');
      }

      // ============================================================
      // 5. 布林带 (20,2) - 含开口方向
      // ============================================================
      final bollResult = _calcBollinger(closes, 20, 2);
      buf.writeln('  【布林带(20,2)】');
      buf.writeln('    上轨: ${_safeDouble(bollResult['upper']).toStringAsFixed(2)}');
      buf.writeln('    中轨: ${_safeDouble(bollResult['middle']).toStringAsFixed(2)}');
      buf.writeln('    下轨: ${_safeDouble(bollResult['lower']).toStringAsFixed(2)}');
      final upper = _safeDouble(bollResult['upper']);
      final lower = _safeDouble(bollResult['lower']);
      final bollMiddle = _safeDouble(bollResult['middle']);
      final bandwidth = upper - lower;
      if (bandwidth > 0) {
        final pos = ((curPrice - lower) / bandwidth * 100).toStringAsFixed(0);
        buf.writeln('    价格位置: ${pos}% (0%=下轨, 100%=上轨)');
        buf.writeln('    带宽: ${(bandwidth / bollMiddle * 100).toStringAsFixed(2)}% (带宽越大波动越剧烈)');
      }
      if (curPrice > upper) {
        buf.writeln('    信号: 突破上轨，短期可能超买');
      } else if (curPrice < lower) {
        buf.writeln('    信号: 跌破下轨，短期可能超卖');
      } else if (curPrice > bollMiddle) {
        buf.writeln('    信号: 价格在中轨上方，偏多');
      } else {
        buf.writeln('    信号: 价格在中轨下方，偏空');
      }

      // 布林带开口方向（与前日比较）
      if (closes.length >= 21) {
        final prevBoll = _calcBollinger(closes.sublist(0, closes.length - 1), 20, 2);
        final prevBandwidth = _safeDouble(prevBoll['upper']) - _safeDouble(prevBoll['lower']);
        if (bandwidth > prevBandwidth * 1.05) {
          buf.writeln('    开口方向: 布林带开口放大，波动率上升，趋势可能加速');
        } else if (bandwidth < prevBandwidth * 0.95) {
          buf.writeln('    开口方向: 布林带开口收窄，波动率下降，变盘在即');
        } else {
          buf.writeln('    开口方向: 布林带开口平稳');
        }
      }

      // ============================================================
      // 6. ATR(14) - 真实波动幅度
      // ============================================================
      final atr14 = _calcATR(highs, lows, closes, 14);
      buf.writeln('  【ATR(14)】');
      buf.writeln('    ATR: ${atr14.toStringAsFixed(2)}');
      if (atr14 > 0 && curPrice > 0) {
        buf.writeln('    日均波动: ${(atr14 / curPrice * 100).toStringAsFixed(2)}% (ATR/价格比)');
        if (atr14 / curPrice > 0.04) {
          buf.writeln('    信号: 波动率较高(>4%)，短期风险较大');
        } else if (atr14 / curPrice < 0.015) {
          buf.writeln('    信号: 波动率较低(<1.5%)，可能即将变盘');
        } else {
          buf.writeln('    信号: 波动率适中');
        }
      }

      // ============================================================
      // 7. WR(14) - 威廉指标
      // ============================================================
      final wr14 = _calcWR(highs, lows, closes, 14);
      buf.writeln('  【WR(14)】');
      buf.writeln('    WR: ${wr14.toStringAsFixed(1)}');
      if (wr14 < -80) {
        buf.writeln('    信号: 超卖区(<-80)，关注反弹');
      } else if (wr14 > -20) {
        buf.writeln('    信号: 超买区(>-20)，注意回调');
      } else {
        buf.writeln('    信号: 正常区间(-80~-20)');
      }

      // ============================================================
      // 8. OBV - 能量潮指标
      // ============================================================
      final obvList = _calcOBV(closes, volumes);
      buf.writeln('  【OBV能量潮】');
      buf.writeln('    当前OBV: ${obvList.last.toStringAsFixed(0)}');
      if (obvList.length >= 6) {
        final obv5avg = _calcMA(obvList, 5);
        if (obvList.last > obv5avg) {
          buf.writeln('    信号: OBV在5日均线上方，资金持续流入');
        } else {
          buf.writeln('    信号: OBV在5日均线下方，资金流出');
        }
        // OBV与价格背离
        final obvTrend = obvList.last - obvList[obvList.length - 6];
        final priceTrend = closes.last - closes[closes.length - 6];
        if (priceTrend > 0 && obvTrend < 0) {
          buf.writeln('    背离: ⚠价格涨但OBV跌，量价背离，上涨不可靠');
        } else if (priceTrend < 0 && obvTrend > 0) {
          buf.writeln('    背离: ★价格跌但OBV涨，资金暗中吸纳，关注反转');
        }
      }

      // ============================================================
      // 9. 成交量与量价分析
      // ============================================================
      buf.writeln('  【成交量与量价配合】');
      final vol5Avg = _calcMA(volumes, 5);
      final vol20Avg = _calcMA(volumes, 20);
      final curVol = volumes.last;
      final prevVol = volumes.length > 1 ? volumes[volumes.length - 2] : curVol;

      buf.writeln('    当日成交量: ${_fmtVolume(curVol)}手');
      if (vol5Avg > 0) {
        final volRatio = curVol / vol5Avg;
        buf.writeln('    5日均量: ${_fmtVolume(vol5Avg)}手 量比: ${volRatio.toStringAsFixed(2)}');
        if (volRatio > 3) {
          buf.writeln('    量比信号: 巨量(>3倍)，市场活跃度极高');
        } else if (volRatio > 2) {
          buf.writeln('    量比信号: 放量(2-3倍)，资金参与度较高');
        } else if (volRatio < 0.5) {
          buf.writeln('    量比信号: 缩量(<0.5倍)，市场观望');
        }
      }
      if (vol20Avg > 0) {
        buf.writeln('    20日均量: ${_fmtVolume(vol20Avg)}手');
      }

      // 换手率
      if (turnoverRate > 0) {
        buf.writeln('    换手率: ${turnoverRate.toStringAsFixed(2)}%');
        if (turnoverRate > 15) {
          buf.writeln('    换手信号: 换手率极高(>15%)，市场分歧加大，警惕变盘');
        } else if (turnoverRate > 10) {
          buf.writeln('    换手信号: 换手率较高(10-15%)，交投活跃，关注资金流向');
        } else if (turnoverRate > 5) {
          buf.writeln('    换手信号: 换手率适中(5-10%)，流动性良好');
        } else if (turnoverRate < 1) {
          buf.writeln('    换手信号: 换手率极低(<1%)，交投清淡，流动性差');
        } else {
          buf.writeln('    换手信号: 换手率正常(1-5%)');
        }
      }

      // 量价关系判断
      final priceChange = closes.length > 1 ? (closes.last - closes[closes.length - 2]) / closes[closes.length - 2] * 100 : 0.0;
      final volChange = prevVol > 0 ? (curVol - prevVol) / prevVol * 100 : 0.0;

      if (priceChange > 0 && volChange > 20) {
        buf.writeln('    量价关系: 量价齐升，上涨动能充足，趋势可靠');
      } else if (priceChange > 0 && volChange < -20) {
        buf.writeln('    量价关系: 缩量上涨，上涨动能减弱，警惕量价背离');
      } else if (priceChange < 0 && volChange > 20) {
        buf.writeln('    量价关系: 放量下跌，抛压较重，资金出逃明显');
      } else if (priceChange < 0 && volChange < -20) {
        buf.writeln('    量价关系: 缩量下跌，抛压减轻，可能接近底部');
      } else {
        buf.writeln('    量价关系: 量价配合一般，趋势待确认');
      }

      // ============================================================
      // 10. 近10日K线与指标概览（含MACD/RSI/KDJ/量）
      // ============================================================
      buf.writeln('  【近10日K线与指标一览】');
      final recentN = closes.length < 10 ? closes.length : 10;
      final offsetN = closes.length - recentN;
      for (int i = 0; i < recentN; i++) {
        final idx = offsetN + i;
        final d = dates[idx];
        final openP = opens[idx];
        final pct = openP > 0 ? ((closes[idx] - openP) / openP * 100) : 0.0;
        final sign = pct >= 0 ? '+' : '';
        final vol = _fmtVolume(volumes[idx]);
        final rsiIdx = idx - (closes.length - rsi14List.length);
        final kdjIdx = idx - (closes.length - kList.length);
        final macdIdx = idx - (closes.length - histList.length);
        String extras = '';
        if (macdIdx >= 0 && macdIdx < histList.length) {
          extras += ' 柱:${histList[macdIdx] >= 0 ? "+" : ""}${histList[macdIdx].toStringAsFixed(2)}';
        }
        if (rsiIdx >= 0 && rsiIdx < rsi14List.length) {
          extras += ' RSI:${rsi14List[rsiIdx].toStringAsFixed(0)}';
        }
        if (kdjIdx >= 0 && kdjIdx < kList.length) {
          extras += ' K:${kList[kdjIdx].toStringAsFixed(0)}';
        }
        buf.writeln('    ${d.length >= 10 ? d.substring(5, 10) : d} 开${openP.toStringAsFixed(2)} 收${closes[idx].toStringAsFixed(2)}($sign${pct.toStringAsFixed(2)}%) 量${vol}$extras');
      }

      return buf.toString();
    } catch (e) {
      return '\n  --- 技术指标: 获取失败 ---';
    }
  }

  /// symbol → 新浪K线API格式
  String _toSinaCode(String symbol, String market) {
    // 600028.SS → sh600028, 000001.SZ → sz000001
    if (symbol.contains('.SS')) {
      return 'sh${symbol.split('.').first}';
    } else if (symbol.contains('.SZ')) {
      return 'sz${symbol.split('.').first}';
    } else if (symbol.contains('.BJ')) {
      return 'bj${symbol.split('.').first}';
    } else if (symbol.length == 6 && int.tryParse(symbol) != null) {
      // 纯6位数字，根据首位判断
      if (symbol.startsWith('6')) return 'sh$symbol';
      if (symbol.startsWith('0') || symbol.startsWith('3')) return 'sz$symbol';
      if (symbol.startsWith('8') || symbol.startsWith('4')) return 'bj$symbol';
    }
    // 港股/美股不支持新浪K线
    return '';
  }

  // ============================================================
  // 技术指标计算算法（含历史序列）
  // ============================================================

  /// 计算简单移动平均线
  double _calcMA(List<double> data, int period) {
    if (data.length < period) return 0;
    double sum = 0;
    for (int i = data.length - period; i < data.length; i++) {
      sum += data[i];
    }
    return sum / period;
  }

  /// 计算MACD (12,26,9) - 返回完整历史序列
  Map<String, List<double>> _calcMACDHistory(List<double> closes) {
    if (closes.length < 35) {
      return {'dif': [0], 'dea': [0], 'histogram': [0]};
    }

    final ema12 = <double>[];
    final ema26 = <double>[];
    double smooth12 = 2.0 / (12 + 1);
    double smooth26 = 2.0 / (26 + 1);

    ema12.add(closes[0]);
    ema26.add(closes[0]);

    for (int i = 1; i < closes.length; i++) {
      ema12.add(closes[i] * smooth12 + ema12[i - 1] * (1 - smooth12));
      ema26.add(closes[i] * smooth26 + ema26[i - 1] * (1 - smooth26));
    }

    final dif = <double>[];
    for (int i = 0; i < closes.length; i++) {
      dif.add(ema12[i] - ema26[i]);
    }

    final dea = <double>[];
    double smoothDea = 2.0 / (9 + 1);
    dea.add(dif[0]);
    for (int i = 1; i < dif.length; i++) {
      dea.add(dif[i] * smoothDea + dea[i - 1] * (1 - smoothDea));
    }

    final histogram = <double>[];
    for (int i = 0; i < dif.length; i++) {
      histogram.add((dif[i] - dea[i]) * 2);
    }

    return {'dif': dif, 'dea': dea, 'histogram': histogram};
  }

  /// 计算RSI - 返回完整历史序列
  List<double> _calcRSIHistory(List<double> closes, int period) {
    if (closes.length < period + 1) return [50.0];

    final result = <double>[];
    // 使用Wilder平滑法计算RSI
    double avgGain = 0;
    double avgLoss = 0;

    // 初始化：第一个period的平均涨跌
    for (int i = 1; i <= period; i++) {
      final change = closes[i] - closes[i - 1];
      if (change > 0) avgGain += change;
      else avgLoss += change.abs();
    }
    avgGain /= period;
    avgLoss /= period;

    // 第一个RSI值
    if (avgLoss == 0) {
      result.add(100.0);
    } else {
      result.add(100 - 100 / (1 + avgGain / avgLoss));
    }

    // 后续用Wilder平滑
    for (int i = period + 1; i < closes.length; i++) {
      final change = closes[i] - closes[i - 1];
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? change.abs() : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      if (avgLoss == 0) {
        result.add(100.0);
      } else {
        result.add(100 - 100 / (1 + avgGain / avgLoss));
      }
    }

    return result;
  }

  /// 计算KDJ (9,3,3) - 返回完整历史序列
  Map<String, List<double>> _calcKDJHistory(List<double> highs, List<double> lows, List<double> closes) {
    final period = 9;
    if (closes.length < period) {
      return {'k': [50.0], 'd': [50.0], 'j': [50.0]};
    }

    final kList = <double>[];
    final dList = <double>[];
    final jList = <double>[];
    double prevK = 50;
    double prevD = 50;

    for (int i = period - 1; i < closes.length; i++) {
      double highest = highs[i];
      double lowest = lows[i];
      for (int j = i - period + 1; j < i; j++) {
        if (highs[j] > highest) highest = highs[j];
        if (lows[j] < lowest) lowest = lows[j];
      }

      double rsv = highest != lowest ? (closes[i] - lowest) / (highest - lowest) * 100 : 50;
      double k = 2.0 / 3 * prevK + 1.0 / 3 * rsv;
      double d = 2.0 / 3 * prevD + 1.0 / 3 * k;
      double j = 3 * k - 2 * d;

      kList.add(k);
      dList.add(d);
      jList.add(j);
      prevK = k;
      prevD = d;
    }

    return {'k': kList, 'd': dList, 'j': jList};
  }

  /// 计算布林带 (period, multiplier)
  Map<String, double> _calcBollinger(List<double> closes, int period, double multiplier) {
    if (closes.length < period) return {'upper': 0, 'middle': 0, 'lower': 0};

    final mid = _calcMA(closes, period);

    double sumSqDiff = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      sumSqDiff += (closes[i] - mid) * (closes[i] - mid);
    }
    final stdDev = sqrt(sumSqDiff / period);

    return {
      'upper': mid + multiplier * stdDev,
      'middle': mid,
      'lower': mid - multiplier * stdDev,
    };
  }

  /// 计算ATR(14) - 真实波动幅度
  double _calcATR(List<double> highs, List<double> lows, List<double> closes, int period) {
    if (closes.length < period + 1) return 0;

    final trList = <double>[];
    for (int i = 1; i < closes.length; i++) {
      final tr = [
        highs[i] - lows[i],
        (highs[i] - closes[i - 1]).abs(),
        (lows[i] - closes[i - 1]).abs(),
      ].reduce((a, b) => a > b ? a : b);
      trList.add(tr);
    }

    if (trList.length < period) return 0;

    // Wilder平滑
    double atr = 0;
    for (int i = 0; i < period; i++) {
      atr += trList[i];
    }
    atr /= period;

    for (int i = period; i < trList.length; i++) {
      atr = (atr * (period - 1) + trList[i]) / period;
    }

    return atr;
  }

  /// 计算WR(14) - 威廉指标
  double _calcWR(List<double> highs, List<double> lows, List<double> closes, int period) {
    if (closes.length < period) return -50;

    double highest = highs[closes.length - 1];
    double lowest = lows[closes.length - 1];
    for (int i = closes.length - period; i < closes.length; i++) {
      if (highs[i] > highest) highest = highs[i];
      if (lows[i] < lowest) lowest = lows[i];
    }

    if (highest == lowest) return -50;
    return -(highest - closes.last) / (highest - lowest) * 100;
  }

  /// 计算OBV - 能量潮指标
  List<double> _calcOBV(List<double> closes, List<double> volumes) {
    if (closes.isEmpty || volumes.isEmpty) return [0];

    final obv = <double>[];
    obv.add(volumes[0]);
    for (int i = 1; i < closes.length; i++) {
      if (closes[i] > closes[i - 1]) {
        obv.add(obv.last + volumes[i]);
      } else if (closes[i] < closes[i - 1]) {
        obv.add(obv.last - volumes[i]);
      } else {
        obv.add(obv.last);
      }
    }
    return obv;
  }

  /// 寻找支撑位（基于均线和近20日低点）
  double _findSupport(List<double> closes, double ma5, double ma10, double ma20, double ma60, List<double> lows) {
    final candidates = <double>[];
    if (ma5 > 0 && ma5 < closes.last) candidates.add(ma5);
    if (ma10 > 0 && ma10 < closes.last) candidates.add(ma10);
    if (ma20 > 0 && ma20 < closes.last) candidates.add(ma20);
    if (ma60 > 0 && ma60 < closes.last) candidates.add(ma60);
    // 近20日最低价
    final recentLows = lows.length > 20 ? lows.sublist(lows.length - 20) : lows;
    candidates.add(recentLows.reduce((a, b) => a < b ? a : b));
    if (candidates.isEmpty) return closes.last * 0.95;
    // 取最接近当前价的支撑
    candidates.sort((a, b) => (closes.last - a).abs().compareTo((closes.last - b).abs()));
    return candidates.first;
  }

  /// 寻找压力位（基于均线和近20日高点）
  double _findResistance(List<double> closes, double ma5, double ma10, double ma20, double ma60, List<double> highs) {
    final candidates = <double>[];
    if (ma5 > 0 && ma5 > closes.last) candidates.add(ma5);
    if (ma10 > 0 && ma10 > closes.last) candidates.add(ma10);
    if (ma20 > 0 && ma20 > closes.last) candidates.add(ma20);
    if (ma60 > 0 && ma60 > closes.last) candidates.add(ma60);
    // 近20日最高价
    final recentHighs = highs.length > 20 ? highs.sublist(highs.length - 20) : highs;
    candidates.add(recentHighs.reduce((a, b) => a > b ? a : b));
    if (candidates.isEmpty) return closes.last * 1.05;
    // 取最接近当前价的压力
    candidates.sort((a, b) => (a - closes.last).abs().compareTo((b - closes.last).abs()));
    return candidates.first;
  }

  // ============================================================
  // 大盘/市场数据
  // ============================================================

  /// 1. 大盘指数 - 腾讯API（A股+港股+美股主要指数）
  Future<String> _fetchIndexData() async {
    try {
      // sh000001=上证, sz399001=深证, sz399006=创业板, sh000688=科创50,
      // hkHSI=恒生, usINX=标普500, usIXIC=纳斯达克
      final resp = await _client.get(
        Uri.parse('https://qt.gtimg.cn/q=sh000001,sz399001,sz399006,sh000688,hkHSI,usINX'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_httpTimeout);

      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return '';

      final text = await LocalDataService.decodeGbk(resp.bodyBytes);
      final buf = StringBuffer('\n【大盘指数】');
      int found = 0;

      final lines = text.split(';');
      for (final line in lines) {
        if (!line.contains('~')) continue;
        final parts = line.split('~');
        if (parts.length <= 32) continue;

        final name = parts.length > 1 ? parts[1] : '';
        final price = _safeDouble(parts[3]);
        final pct = _safeDouble(parts[32]);
        final amount = _safeDouble(parts[37]);
        if (price <= 0) continue;

        final sign = pct >= 0 ? '+' : '';
        buf.writeln('  $name: ${price.toStringAsFixed(2)} ($sign${pct.toStringAsFixed(2)}%) 成交额:${_fmtAmountWan(amount)}');
        found++;
      }
      return found > 0 ? buf.toString() : '';
    } catch (_) {
      return '';
    }
  }

  /// 2. 市场情绪 - 全市场涨跌统计（新浪财经，并发统计全部A股）
  Future<String> _fetchMarketSentiment() async {
    try {
      // 新浪API每页最多100条，并发请求所有分页统计涨跌家数
      const pageSize = 100;
      const nodes = ['sh_a', 'sz_a']; // 沪市A股 + 深市A股
      int totalUp = 0, totalDown = 0, totalFlat = 0, totalStocks = 0;

      for (final node in nodes) {
        // 先获取该市场总股票数
        final countResp = await _client.get(
          Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeStockCount?node=$node'),
          headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://finance.sina.com.cn'},
        ).timeout(const Duration(seconds: 10));

        int stockCount = 0;
        if (countResp.statusCode == 200) {
          final countStr = countResp.body.trim().replaceAll('"', '');
          stockCount = int.tryParse(countStr) ?? 0;
        }
        if (stockCount == 0) continue;

        final totalPages = (stockCount / pageSize).ceil();
        // 并发请求所有分页
        final futures = <Future<List<int>>>[];
        for (int page = 1; page <= totalPages; page++) {
          futures.add(_fetchSinaPageStats(node, page));
        }
        final results = await Future.wait(futures);
        for (final r in results) {
          totalUp += r[0];
          totalDown += r[1];
          totalFlat += r[2];
          totalStocks += r[3];
        }
      }

      if (totalStocks > 0) {
        final pct = (totalUp / totalStocks * 100).toStringAsFixed(1);
        return '\n【全市场实时涨跌（A股$totalStocks只，新浪财经实时数据）】\n  上涨:$totalUp只 下跌:$totalDown只 平盘:$totalFlat只 多方占比:$pct%';
      }
    } catch (_) {}
    return '';
  }

  /// 新浪API单页涨跌统计：返回 [up, down, flat, total]
  Future<List<int>> _fetchSinaPageStats(String node, int page) async {
    try {
      final resp = await _client.get(
        Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=$page&num=100&sort=symbol&asc=1&node=$node&symbol=&_s_r_a=auto'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://finance.sina.com.cn'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final List<dynamic> data = json.decode(resp.body);
        int up = 0, down = 0, flat = 0;
        for (final stock in data) {
          final changePct = _safeDouble(stock['changepercent']);
          if (changePct > 0) up++;
          else if (changePct < 0) down++;
          else flat++;
        }
        return [up, down, flat, data.length];
      }
    } catch (_) {}
    return [0, 0, 0, 0];
  }

  int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 3. 板块行情
  Future<String> _fetchSectorData() async {
    try {
      final resp = await _client.get(
        Uri.parse('https://vip.stock.finance.sina.com.cn/q/view/newSinaHy.php'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://finance.sina.com.cn'},
      ).timeout(_httpTimeout);

      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return '';

      final text = await LocalDataService.decodeGbk(resp.bodyBytes);
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) return '';

      final jsonStr = text.substring(jsonStart, jsonEnd + 1);
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      final sectorData = <Map<String, dynamic>>[];
      data.forEach((key, val) {
        final parts = val.toString().split(',');
        if (parts.length >= 5) {
          final name = parts.length > 1 ? parts[1] : key;
          final pct = _safeDouble(parts[4]);
          sectorData.add({'name': name, 'pct': pct});
        }
      });
      sectorData.sort((a, b) => (_safeDouble(b['pct'])).compareTo(_safeDouble(a['pct'])));

      final buf = StringBuffer('\n【热门板块TOP10】');
      for (final s in sectorData.take(10)) {
        final pct = _safeDouble(s['pct']);
        final sign = pct >= 0 ? '+' : '';
        buf.writeln('  ${s['name']}: $sign${pct.toStringAsFixed(2)}%');
      }
      return buf.toString();
    } catch (_) {}
    return '';
  }

  /// 4. 涨跌排行
  Future<String> _fetchUpDownRanking() async {
    try {
      final buf = StringBuffer('\n【涨跌排行】');
      buf.writeln('  涨幅TOP5:');
      final upResp = await _client.get(
        Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=5&sort=changepercent&asc=0&node=hs_a'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_httpTimeout);
      if (upResp.statusCode == 200 && upResp.body.isNotEmpty) {
        for (final s in (json.decode(upResp.body) as List?) ?? []) {
          buf.writeln('    ${s['name']}(${s['code']}): ${_safeDouble(s['trade']).toStringAsFixed(2)} +${_safeDouble(s['changepercent']).toStringAsFixed(2)}%');
        }
      }

      buf.writeln('  跌幅TOP5:');
      final downResp = await _client.get(
        Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=5&sort=changepercent&asc=1&node=hs_a'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_httpTimeout);
      if (downResp.statusCode == 200 && downResp.body.isNotEmpty) {
        for (final s in (json.decode(downResp.body) as List?) ?? []) {
          buf.writeln('    ${s['name']}(${s['code']}): ${_safeDouble(s['trade']).toStringAsFixed(2)} ${_safeDouble(s['changepercent']).toStringAsFixed(2)}%');
        }
      }
      return buf.toString();
    } catch (_) {}
    return '';
  }

  /// 5. 资金热度
  Future<String> _fetchMoneyFlow() async {
    try {
      final resp = await _client.get(
        Uri.parse('https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=10&sort=amount&asc=0&node=hs_a'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(_httpTimeout);
      if (resp.statusCode != 200 || resp.body.isEmpty) return '';
      final list = json.decode(resp.body) as List? ?? [];
      if (list.isEmpty) return '';

      final buf = StringBuffer('\n【成交额活跃个股TOP10】');
      for (final s in list) {
        final name = s['name']?.toString() ?? '';
        final pct = _safeDouble(s['changepercent']);
        final amount = _safeDouble(s['amount']);
        final turnover = _safeDouble(s['turnoverratio']);
        final sign = pct >= 0 ? '+' : '';
        buf.writeln('  $name: $sign${pct.toStringAsFixed(2)}% 成交:${_fmtAmountYuan(amount)} 换手:${turnover.toStringAsFixed(2)}%');
      }
      return buf.toString();
    } catch (_) {}
    return '';
  }

  /// 6. 市场新闻 - 覆盖上证+深证+创业板
  Future<String> _fetchNews() async {
    try {
      final buf = StringBuffer('\n【市场新闻】');
      int totalNews = 0;

      // 多市场去重聚合
      final markets = ['1.000001', '0.399001', '0.399006']; // 上证/深证/创业板
      for (final mkt in markets) {
        if (totalNews >= 10) break;
        try {
          final resp = await _client.get(
            Uri.parse('https://np-listapi.eastmoney.com/comm/web/getListInfo?client=web&pageSize=4&type=1&mTypeAndCode=$mkt'),
            headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://so.eastmoney.com/'},
          ).timeout(_httpTimeout);
          if (resp.statusCode != 200 || resp.body.isEmpty) continue;
          final list = json.decode(resp.body)['data']?['list'] as List? ?? [];
          for (final item in list.take(4)) {
            final title = item['Art_Title']?.toString() ?? '';
            if (title.isNotEmpty) {
              buf.writeln('  - $title');
              totalNews++;
            }
          }
        } catch (_) {}
      }
      return totalNews > 0 ? buf.toString() : '';
    } catch (_) {}
    return '';
  }

  // ============================================================
  // AI交互
  // ============================================================

  String _buildSystemPrompt_v2({
    required String marketContext,
    required List<String> ragContext,
    String? financialContext,
    String summaryContext = '',
    required AIQueryIntent intent,
  }) {
    final buf = StringBuffer();
    buf.writeln('你是专业证券分析师"极智"，拥有CFA和FRM资质，擅长A股/港股/美股分析。');
    buf.writeln('\n【市场基本常识（严禁编造违背）】');
    buf.writeln('- A股市场目前有超过5000只股票，分布在沪深北三大交易所。');
    buf.writeln('- 回答中涉及股票数量、市场规模等客观数据时，必须基于上方实时数据，不得随口编造。');
    buf.writeln('- 用户问题优先：当上方实时数据与用户问题不完全匹配时，优先围绕用户问题给出有建设性的专业回答。');

    // 金融知识库
    if (ragContext.isNotEmpty) {
      buf.writeln('\n【金融知识参考】');
      for (var i = 0; i < ragContext.length; i++) {
        buf.writeln('${ragContext[i]}\n');
      }
    }

    // 对话历史摘要
    if (summaryContext.isNotEmpty) {
      buf.writeln(summaryContext);
    }

    // 实时市场数据
    buf.writeln(marketContext);

    // 财报数据
    if (financialContext != null) {
      buf.writeln(financialContext);
    }

    // 意图引导
    buf.writeln(_getIntentGuidance(intent.intent));

    return buf.toString();
  }

  String _getIntentGuidance(QueryIntentType intent) {
    switch (intent) {
      case QueryIntentType.stockPick:
        return '\n【任务：智能选股】\n1. 根据用户条件和实时数据筛选符合条件的股票\n2. 每只推荐股票需列出核心逻辑（至少2条数据支撑）\n3. 按综合评分排序，推荐TOP 3\n4. 必须基于上方实时数据，不可凭空推荐';
      case QueryIntentType.stockDiagnose:
        return '\n【任务：个股诊断】\n1. 综合技术面(MACD/RSI/KDJ/均线/布林)+基本面(PE/PB/ROE)+资金面(量价/换手)\n2. 给出短期(1-5日)和中期(1-3月)两档建议\n3. 指明关键支撑位和压力位\n4. 标注当前风险等级(低/中/高)及理由';
      case QueryIntentType.marketOverview:
        return '\n【任务：大盘分析】\n1. 分析主要指数走势（上证/深证/创业板）\n2. 判断市场整体趋势和情绪\n3. 指出当前热点板块和资金流向\n4. 给出仓位建议参考';
      case QueryIntentType.sectorAnalysis:
        return '\n【任务：板块分析】\n1. 分析目标板块的资金流向和涨跌情况\n2. 找出板块内龙头股和领涨股\n3. 判断板块延续性\n4. 给出关注建议';
      case QueryIntentType.newsQuery:
        return '\n【任务：资讯分析】\n1. 总结最新重要资讯\n2. 分析对市场/个股的影响\n3. 区分短期情绪影响和长期基本面影响';
      case QueryIntentType.comparison:
        return '\n【任务：股票对比】\n1. 从基本面、技术面、资金面三方面横向对比\n2. 用表格清晰展示差异\n3. 给出综合结论和选择建议';
      case QueryIntentType.knowledge:
        return '\n【任务：知识解答】\n1. 用通俗易懂的语言解释金融概念\n2. 结合A股实例说明\n3. 引用上方【金融知识参考】中的内容';
      case QueryIntentType.unknown:
        return '\n【回答要求】\n1. 优先围绕用户问题给出专业、有建设性的回答\n2. 如果问题涉及市场行情，参考上方实时数据进行分析\n3. 如果问题是通用知识类，直接专业解答，可引用金融知识参考\n4. 严禁编造数据，回答控制在800字以内，结构清晰';
    }
  }

  List<Map<String, String>> _buildMessages_v2(
    String systemPrompt,
    String question,
    List<ChatMessage>? history,
    String summaryContext,
  ) {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    if (history != null && history.isNotEmpty) {
      final maxMsgs = summaryContext.isNotEmpty ? 10 : _maxContextMessages;
      final recent = history.length > maxMsgs
          ? history.sublist(history.length - maxMsgs)
          : history;
      for (final msg in recent) {
        messages.add({'role': msg.isUser ? 'user' : 'assistant', 'content': msg.content});
      }
    }
    messages.add({'role': 'user', 'content': question});
    return messages;
  }

  Future<String> _sendToAI_v2(AIModelConfig model, List<Map<String, String>> messages) async {
    String baseUrl = model.baseUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) baseUrl = 'https://$baseUrl';
    if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);

    final endpoint = '$baseUrl/chat/completions';
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${model.apiKey}',
    };

    final bodyMap = <String, dynamic>{
      'model': model.model,
      'messages': messages,
      'temperature': model.temperature,
      'max_tokens': model.maxTokens,
    };
    if (model.topP != null) bodyMap['top_p'] = model.topP;
    if (model.frequencyPenalty != null) bodyMap['frequency_penalty'] = model.frequencyPenalty;
    if (model.presencePenalty != null) bodyMap['presence_penalty'] = model.presencePenalty;

    final modelName = model.model.toLowerCase();
    if (modelName.contains('deepseek-v4') || modelName.contains('deepseek-reasoner')) {
      bodyMap['extra_body'] = {'thinking': {'type': 'disabled'}};
    }
    if (modelName.contains('glm-5') || modelName.contains('kimi-k2')) {
      bodyMap['thinking'] = {'type': 'disabled'};
    }

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: headers,
        body: utf8.encode(json.encode(bodyMap)),
      ).timeout(
        _aiTimeout,
        onTimeout: () => throw Exception('AI请求超时(${_aiTimeout.inSeconds}s)'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'];
          String content = message['content']?.toString() ?? '';
          final reasoning = message['reasoning_content']?.toString() ?? '';
          if (reasoning.isNotEmpty && content.isEmpty) content = reasoning;
          return content;
        }
        return '极智返回数据格式异常';
      } else {
        return '极智请求失败：${response.statusCode}';
      }
    } catch (e) {
      return '网络请求错误：$e';
    }
  }

  // ============================================================
  // 工具方法
  // ============================================================

  double _safeDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }

  String _formatNum(dynamic val) {
    final v = _safeDouble(val);
    if (v == 0) return '0';
    return v.toStringAsFixed(v.abs() > 100 ? 0 : (v.abs() < 0.01 ? 4 : 2));
  }

  String _fmtAmountYuan(double amount) {
    if (amount >= 100000000) return '${(amount / 100000000).toStringAsFixed(2)}亿';
    if (amount >= 10000) return '${(amount / 10000).toStringAsFixed(0)}万';
    return '${amount.toStringAsFixed(0)}元';
  }

  String _fmtAmountWan(double amountWan) {
    if (amountWan >= 10000) return '${(amountWan / 10000).toStringAsFixed(2)}亿';
    return '${amountWan.toStringAsFixed(0)}万';
  }

  /// 格式化成交量（手）
  String _fmtVolume(double volume) {
    if (volume >= 100000000) return '${(volume / 100000000).toStringAsFixed(2)}亿';
    if (volume >= 10000) return '${(volume / 10000).toStringAsFixed(2)}万';
    return volume.toStringAsFixed(0);
  }

  /// 对股票数据进行AI深度分析（供极智深度分析模块调用）
  Future<String> analyzeStockWithData(
    String stockName,
    String stockSymbol,
    String dataSummary,
  ) async {
    final model = await AIModelService.getActiveModel();
    if (model == null) return '';

    try {
      final systemPrompt = '''你是专业证券分析师"极智"，拥有丰富的金融知识和市场分析经验。
请基于提供的实时数据，对股票进行专业、客观的深度分析。

【回答要求】
1. 必须严格基于提供的数据进行分析，绝不允许编造任何数据
2. 综合考量多个维度：基本面(PE/PB/ROE/营收增速)、技术面、资金面、市场情绪
3. 给出明确的操作建议：短期(1-5日)、中期(3-6个月)、长期(1年以上)
4. 必须提示风险
5. 回答控制在800字以内，结构清晰
6. 使用专业但不失易懂的语言''';

      final question = '''请对股票$stockName($stockSymbol)进行深度分析。

实时数据汇总：
$dataSummary

请给出：
1. 综合研判（多空方向、强度评估）
2. 短期操作建议（1-5日，含参考入场价、止损参考）
3. 中期持有建议（3-6个月，含加仓条件、目标参考）
4. 长期投资价值（1年以上，含核心逻辑、估值判断）
5. 风险提示（具体、可执行）

要求：具体、专业、有可操作性，回答控制在800字以内。''';

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': question},
      ];

      final result = await _sendToAI_v2(model, messages);
      return cleanMarkdown(result);
    } catch (e) {
      return '';
    }
  }
}
