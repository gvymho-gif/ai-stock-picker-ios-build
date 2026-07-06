import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_model_config.dart';
import 'ai_model_service.dart';
import 'local_data_service.dart';

/// 极智深度分析服务 - 调用云端AI大模型对个股进行智能分析
class StockDeepAnalysisService {
  final LocalDataService _stockService = LocalDataService();

  /// 对个股进行极智深度分析（调用云端AI）
  Future<Map<String, dynamic>> analyzeStock(Map<String, dynamic> stockData) async {
    final model = await AIModelService.getActiveModel();
    if (model == null) {
      return _buildOfflineResult(stockData, '请先在极智问答中配置AI模型');
    }

    try {
      // 构建包含所有模块数据和市场信息的提示词
      final prompt = await _buildAnalysisPrompt(stockData);

      // 调用云端AI（整体流程设置90秒超时）
      final aiResponse = await _callAI(model, prompt).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw Exception('AI分析整体流程超时(90s)，请检查网络连接或稍后重试');
        },
      );

      // 解析AI返回的分析结果
      return _parseAIResponse(aiResponse, stockData);
    } on TimeoutException catch (e) {
      return _buildOfflineResult(stockData, 'AI分析超时：${e.message}');
    } catch (e) {
      // 如果AI调用失败，返回本地分析作为备选
      return _buildOfflineResult(stockData, 'AI调用异常：$e');
    }
  }

  /// 构建分析提示词（包含所有模块数据 + 市场情绪 + 板块表现 + 新闻资讯）
  Future<String> _buildAnalysisPrompt(Map<String, dynamic> stockData) async {
    final name = stockData['name']?.toString() ?? '该股';
    final symbol = stockData['symbol']?.toString() ?? '';
    final market = stockData['market']?.toString() ?? '';
    final isHK = market == 'HK';
    final isUS = market == 'US';
    final currencySymbol = isHK ? 'HK\$' : (isUS ? '\$' : '¥');
    final price = stockData['price']?.toString() ?? '';
    final changePct = _safeDouble(stockData['change_pct']);
    final marketCap = stockData['market_cap_display']?.toString() ?? '';
    final pe = stockData['pe_ratio']?.toString() ?? 'N/A';
    final pb = stockData['pb_ratio']?.toString() ?? 'N/A';
    final roe = _safeDouble(stockData['roe']);
    final eps = stockData['eps']?.toString() ?? 'N/A';
    final revGrowth = _safeDouble(stockData['revenue_growth']);
    final divYield = _safeDouble(stockData['dividend_yield']);
    final turnoverRate = _safeDouble(stockData['turnover_rate']);
    final week52High = stockData['week52_high']?.toString() ?? '';
    final week52Low = stockData['week52_low']?.toString() ?? '';
    final volume = stockData['volume']?.toString() ?? '';
    final amount = stockData['amount']?.toString() ?? '';
    final high = stockData['high']?.toString() ?? '';
    final low = stockData['low']?.toString() ?? '';
    final prevClose = stockData['prev_close']?.toString() ?? '';
    final open = stockData['open']?.toString() ?? '';

    // ========== 1. 各模块分析结果 ==========
    final analysis = stockData['analysis'] as Map<String, dynamic>? ?? {};
    final modulesData = StringBuffer();

    // 价格模块
    final priceAnalysis = analysis['price'] as Map<String, dynamic>? ?? {};
    if (priceAnalysis.isNotEmpty) {
      modulesData.writeln('【价格模块】情绪:${priceAnalysis['sentiment'] ?? 'N/A'}, 评分:${priceAnalysis['score'] ?? 'N/A'}');
      final items = priceAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 量能模块
    final volumeAnalysis = analysis['volume'] as Map<String, dynamic>? ?? {};
    if (volumeAnalysis.isNotEmpty) {
      modulesData.writeln('【量能模块】情绪:${volumeAnalysis['sentiment'] ?? 'N/A'}, 评分:${volumeAnalysis['score'] ?? 'N/A'}');
      final items = volumeAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 趋势模块
    final trendAnalysis = analysis['trend'] as Map<String, dynamic>? ?? {};
    if (trendAnalysis.isNotEmpty) {
      modulesData.writeln('【趋势模块】情绪:${trendAnalysis['sentiment'] ?? 'N/A'}, 评分:${trendAnalysis['score'] ?? 'N/A'}');
      final items = trendAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 动量模块
    final momentumAnalysis = analysis['momentum'] as Map<String, dynamic>? ?? {};
    if (momentumAnalysis.isNotEmpty) {
      modulesData.writeln('【动量模块】情绪:${momentumAnalysis['sentiment'] ?? 'N/A'}, 评分:${momentumAnalysis['score'] ?? 'N/A'}');
      final items = momentumAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 估值模块
    final valuationAnalysis = analysis['valuation'] as Map<String, dynamic>? ?? {};
    if (valuationAnalysis.isNotEmpty) {
      modulesData.writeln('【估值模块】情绪:${valuationAnalysis['sentiment'] ?? 'N/A'}, 评分:${valuationAnalysis['score'] ?? 'N/A'}');
      final items = valuationAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 资金流模块
    final capitalFlowAnalysis = analysis['capital_flow'] as Map<String, dynamic>? ?? {};
    if (capitalFlowAnalysis.isNotEmpty) {
      modulesData.writeln('【资金流模块】情绪:${capitalFlowAnalysis['sentiment'] ?? 'N/A'}, 评分:${capitalFlowAnalysis['score'] ?? 'N/A'}');
      final items = capitalFlowAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 盘口模块
    final bidAskAnalysis = analysis['bid_ask'] as Map<String, dynamic>? ?? {};
    if (bidAskAnalysis.isNotEmpty) {
      modulesData.writeln('【盘口模块】情绪:${bidAskAnalysis['sentiment'] ?? 'N/A'}, 评分:${bidAskAnalysis['score'] ?? 'N/A'}');
      final items = bidAskAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 波动模块
    final volatilityAnalysis = analysis['volatility'] as Map<String, dynamic>? ?? {};
    if (volatilityAnalysis.isNotEmpty) {
      modulesData.writeln('【波动模块】情绪:${volatilityAnalysis['sentiment'] ?? 'N/A'}, 评分:${volatilityAnalysis['score'] ?? 'N/A'}');
      final items = volatilityAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 支撑压力模块
    final srAnalysis = analysis['support_resistance'] as Map<String, dynamic>? ?? {};
    if (srAnalysis.isNotEmpty) {
      modulesData.writeln('【支撑压力模块】情绪:${srAnalysis['sentiment'] ?? 'N/A'}, 评分:${srAnalysis['score'] ?? 'N/A'}');
      final items = srAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // 暗盘/竞价模块
    final preMarketAnalysis = analysis['pre_market'] as Map<String, dynamic>? ?? {};
    if (preMarketAnalysis.isNotEmpty) {
      modulesData.writeln('【暗盘/竞价模块】情绪:${preMarketAnalysis['sentiment'] ?? 'N/A'}, 评分:${preMarketAnalysis['score'] ?? 'N/A'}');
      final items = preMarketAnalysis['items'] as Map<String, dynamic>? ?? {};
      if (items.isNotEmpty) modulesData.writeln('详情: ${items.entries.map((e) => '${e.key}${e.value}').join('、')}');
    }

    // ========== 2. 市场情绪数据 ==========
    final marketSentimentData = await _fetchMarketSentiment();
    
    // ========== 3. 热门板块数据 ==========
    final hotSectorsData = await _fetchHotSectorsInfo();
    
    // ========== 4. 相关新闻资讯 ==========
    final newsData = await _fetchStockNewsInfo(symbol);
    
    // ========== 5. 企业简介信息 ==========
    final companyProfile = analysis['company_profile'] as Map<String, dynamic>? ?? {};

    // 计算市场整体情绪
    String overallMarketSentiment = '中性';
    if (marketSentimentData.isNotEmpty) {
      final upCount = marketSentimentData['up_count'] ?? 0;
      final downCount = marketSentimentData['down_count'] ?? 0;
      final limitUp = marketSentimentData['limit_up'] ?? 0;
      final limitDown = marketSentimentData['limit_down'] ?? 0;
      
      if (limitUp > limitDown * 2) {
        overallMarketSentiment = '极强（涨停${limitUp}家，跌停${limitDown}家）';
      } else if (upCount > downCount * 1.5) {
        overallMarketSentiment = '偏强（上涨${upCount}家，下跌${downCount}家）';
      } else if (downCount > upCount * 1.5) {
        overallMarketSentiment = '偏弱（上涨${upCount}家，下跌${downCount}家）';
      } else if (limitDown > limitUp * 2) {
        overallMarketSentiment = '极弱（涨停${limitUp}家，跌停${limitDown}家）';
      } else {
        overallMarketSentiment = '震荡（上涨${upCount}家，下跌${downCount}家，涨停${limitUp}家，跌停${limitDown}家）';
      }
    }

    // 构建完整提示词（精简版，提高响应速度）
    return '''你是一位资深证券分析师"极智"。请基于以下数据对$name($symbol)进行深度分析：

【基本信息】
现价: $currencySymbol$price  涨跌: ${changePct.toStringAsFixed(2)}%  市值: $marketCap
PE: $pe  PB: $pb  ROE: ${roe.toStringAsFixed(1)}%  EPS: $eps
营收增速: ${revGrowth.toStringAsFixed(1)}%  股息率: ${divYield.toStringAsFixed(2)}%
换手: ${turnoverRate.toStringAsFixed(2)}%  52周区间: $week52Low-$week52High

【技术分析】
$modulesData

【市场情绪】$overallMarketSentiment

【热门板块】
$hotSectorsData

【新闻资讯】
$newsData

请按以下格式回答（控制在800字内）：

极智解读：

1. 投资方向（二选一）：【值得买入持有】或【暂不建议买入】
   综合评分：XX/100

2. 核心理由（3-5条）：结合技术、基本面、市场环境综合分析

3. 持有者策略：已持有者的操作建议

4. 操作建议：
   - 短线（1-5天）：入场价、目标价、止损价
   - 中线（3-6月）：仓位建议、目标价、止损线
   - 长线（1年+）：是否适合长期持有

5. 风险提示（2-3条）''';
  }

  /// 获取市场整体情绪数据
  Future<Map<String, dynamic>> _fetchMarketSentiment() async {
    try {
      final sectors = await _stockService.fetchHotSectors();
      if (sectors.isEmpty) return {};

      int upCount = 0;
      int downCount = 0;
      int limitUp = 0;
      int limitDown = 0;
      double totalAmount = 0;

      for (final entry in sectors.entries) {
        final stocks = entry.value as List;
        for (final stock in stocks) {
          final changePct = _safeDouble(stock['change_pct']);
          if (changePct > 0) upCount++;
          if (changePct < 0) downCount++;
          if (changePct >= 9.9) limitUp++;
          if (changePct <= -9.9) limitDown++;
        }
      }

      // 计算市场温度 (0-100)
      final total = upCount + downCount;
      double temperature = 50;
      if (total > 0) {
        temperature = (upCount / total * 100).clamp(0, 100);
      }

      return {
        'up_count': upCount,
        'down_count': downCount,
        'limit_up': limitUp,
        'limit_down': limitDown,
        'temperature': temperature.toStringAsFixed(0),
      };
    } catch (e) {
      return {};
    }
  }

  /// 获取热门板块信息
  Future<String> _fetchHotSectorsInfo() async {
    try {
      final sectors = await _stockService.fetchHotSectors();
      if (sectors.isEmpty) return '暂无热门板块数据';

      final result = StringBuffer();
      int count = 0;
      for (final entry in sectors.entries) {
        if (count >= 5) break; // 只取前5个板块
        final stocks = entry.value as List;
        result.writeln('\n【${entry.key}板块】');
        for (final stock in stocks.take(3)) {
          final name = stock['name']?.toString() ?? '';
          final changePct = _safeDouble(stock['change_pct']);
          result.write('$name(${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%) ');
        }
        count++;
      }
      return result.toString();
    } catch (e) {
      return '暂无热门板块数据';
    }
  }

  /// 获取股票相关新闻
  Future<String> _fetchStockNewsInfo(String symbol) async {
    try {
      final news = await _stockService.fetchStockNews(symbol, count: 5);
      if (news.isEmpty) return '暂无相关新闻资讯';

      final result = StringBuffer();
      for (final item in news.take(3)) {
        final title = item['title'] ?? '';
        final source = item['source'] ?? '';
        final time = item['time'] ?? '';
        result.writeln('• $title [$source $time]');
      }
      return result.toString();
    } catch (e) {
      return '暂无相关新闻资讯';
    }
  }

  /// 调用云端AI
  Future<String> _callAI(AIModelConfig model, String prompt) async {
    String baseUrl = model.baseUrl.trim();

    // 修复协议头
    if (baseUrl.startsWith('ttps://')) {
      baseUrl = 'h$baseUrl';
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
    }
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }

    final endpoint = '$baseUrl/chat/completions';

    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${model.apiKey}',
    };

    // 构建请求体
    final bodyMap = <String, dynamic>{
      'model': model.model,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.6,
      'max_tokens': 3000, // 优化token限制，平衡响应质量和速度
    };

    // 针对不同模型禁用思考模式
    final modelName = model.model.toLowerCase();

    // DeepSeek V4/Reasoner - 使用extra_body
    if (modelName.contains('deepseek-v4') || modelName.contains('deepseek-reasoner')) {
      bodyMap['extra_body'] = {'thinking': {'type': 'disabled'}};
    }
    // GLM-5.x - 使用thinking字段
    if (modelName.contains('glm-5')) {
      bodyMap['thinking'] = {'type': 'disabled'};
    }
    // Kimi K2.x - 使用thinking字段直接禁用
    if (modelName.contains('kimi-k2')) {
      bodyMap['thinking'] = {'type': 'disabled'};
    }

    final body = json.encode(bodyMap);

    // 设置60秒超时，AI分析需要更长时间
    final response = await http.post(
      Uri.parse(endpoint),
      headers: headers,
      body: utf8.encode(body),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw Exception('AI分析请求超时(60s)，请检查网络或稍后重试');
      },
    );

    if (response.statusCode == 200) {
      // 确保使用UTF-8解码响应
      final responseText = utf8.decode(response.bodyBytes);
      final data = json.decode(responseText);
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        String content = message['content']?.toString() ?? '';
        
        // DeepSeek思考模式可能返回reasoning_content
        final reasoningContent = message['reasoning_content']?.toString() ?? '';
        if (reasoningContent.isNotEmpty && content.isEmpty) {
          content = reasoningContent;
        }
        
        return content;
      }
    }

    throw Exception('AI请求失败: ${response.statusCode}');
  }

  /// 解析AI返回的分析结果
  Map<String, dynamic> _parseAIResponse(String aiResponse, Map<String, dynamic> stockData) {
    // 从AI回复中提取投资方向判断
    String investmentDirection = '';
    String sentiment = '中性';
    double score = 0.5;

    // 提取投资方向（更精确的匹配）
    final directionMatch = RegExp(r'投资方向.*?[：:]\s*(值得买入持有|暂不建议买入|建议关注|不建议买入|买入|卖出|持有|观望)', caseSensitive: false).firstMatch(aiResponse);
    if (directionMatch != null) {
      investmentDirection = directionMatch.group(1) ?? '';
    } else {
      // 如果没有明确提取到，从内容判断
      if (aiResponse.contains('值得买入持有')) {
        investmentDirection = '值得买入持有';
      } else if (aiResponse.contains('暂不建议买入')) {
        investmentDirection = '暂不建议买入';
      } else if (aiResponse.contains('建议买入') || aiResponse.contains('值得买入')) {
        investmentDirection = '值得买入持有';
      } else {
        investmentDirection = '暂不建议买入';
      }
    }

    // 根据投资方向设置情绪和评分
    if (investmentDirection.contains('值得买入') || investmentDirection.contains('买入') || investmentDirection.contains('持有')) {
      sentiment = '建议关注';
      score = 0.65;
    } else {
      sentiment = '暂不建议';
      score = 0.35;
    }

    // 尝试从AI回复中提取评分
    final scoreMatch = RegExp(r'综合评分[：:]\s*(\d+)').firstMatch(aiResponse);
    if (scoreMatch != null) {
      final scoreValue = int.tryParse(scoreMatch.group(1) ?? '') ?? 50;
      score = scoreValue / 100.0;
    } else {
      // 从其他格式提取评分
      final altScoreMatch = RegExp(r'(\d+)/100').firstMatch(aiResponse);
      if (altScoreMatch != null) {
        final scoreValue = int.tryParse(altScoreMatch.group(1) ?? '') ?? 50;
        score = scoreValue / 100.0;
      }
    }

    return {
      'title': '极智深度分析',
      'icon': 'psychology',
      'sentiment': sentiment,
      'score': score,
      'items': {
        '分析来源': '云端AI大模型',
        '投资方向': investmentDirection,
        '综合评分': '${(score * 100).toStringAsFixed(0)}/100',
      },
      'advice': aiResponse,
      'extra_note': '本分析由云端AI大模型基于实时数据+市场情绪+板块表现+新闻资讯综合分析生成，不构成投资建议',
      'is_cloud_ai': true,
    };
  }

  /// 构建离线/失败时的备选结果
  Map<String, dynamic> _buildOfflineResult(Map<String, dynamic> stockData, String reason) {
    final name = stockData['name']?.toString() ?? '该股';
    final changePct = _safeDouble(stockData['change_pct']);
    final pe = _safeDouble(stockData['pe_ratio']);
    final roe = _safeDouble(stockData['roe']);

    String offlineAdvice = '极智解读：$reason\n\n';
    offlineAdvice += '$name当前涨跌幅${changePct.toStringAsFixed(2)}%。\n\n';

    if (pe > 0) {
      offlineAdvice += '估值参考：PE ${pe.toStringAsFixed(1)}倍';
      if (pe < 15) offlineAdvice += '，处于偏低水平，有一定安全边际。\n\n';
      else if (pe < 30) offlineAdvice += '，处于合理区间。\n\n';
      else offlineAdvice += '，估值偏高，需谨慎。\n\n';
    }

    if (roe > 0) {
      offlineAdvice += '盈利能力：ROE ${roe.toStringAsFixed(1)}%';
      if (roe > 15) offlineAdvice += '，盈利能力优秀。\n\n';
      else if (roe > 8) offlineAdvice += '，盈利能力尚可。\n\n';
      else offlineAdvice += '，盈利能力偏弱。\n\n';
    }

    offlineAdvice += '请在极智问答中配置AI模型以获取完整深度分析（含市场情绪、板块表现、新闻资讯等）。';

    return {
      'title': '极智深度分析',
      'icon': 'psychology',
      'sentiment': '待配置AI',
      'score': 0.5,
      'items': {
        '分析来源': '本地简化分析',
        '说明': reason,
      },
      'advice': offlineAdvice,
      'extra_note': '请在极智问答中配置云端AI模型以获取完整深度分析',
      'is_cloud_ai': false,
    };
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
