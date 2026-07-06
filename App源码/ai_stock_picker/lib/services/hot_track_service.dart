import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_model_config.dart';
import '../models/hot_track_model.dart';
import 'ai_model_service.dart';
import 'local_data_service.dart';
import 'news_service.dart';
import 'server_config_service.dart';

/// 热点追踪服务 - AI决策引擎
///
/// 数据流：东方财富新闻API → 关键词初筛 → AI大脑定性 → 标的锁定 → 量化参数生成
class HotTrackService {
  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _aiTimeout = Duration(seconds: 120);

  final http.Client _client = http.Client();

  // ============================================================
  // 第一步：拉取新闻 + 初筛
  // ============================================================

  /// 拉取最新新闻并进行关键词初筛（必须通过后端，不再本地降级）
  Future<List<Map<String, dynamic>>> fetchAndFilterNews() async {
    final serverUrl = await ServerConfigService.getServerUrl();
    final token = await ServerConfigService.getToken();

    if (serverUrl.isEmpty || token.isEmpty) {
      print('[热点追踪] 未配置选股服务器，无法获取新闻');
      return [];
    }

    final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/hot-track/news'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = json.decode(utf8.decode(resp.bodyBytes));
      return (data['news'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    }

    return [];
  }

  // ============================================================
  // 第二步：AI决策引擎
  // ============================================================

  /// 对单条新闻进行AI决策分析
  Future<HotTrackResult> analyzeNews(Map<String, dynamic> news) async {
    final model = await AIModelService.getActiveModel();
    if (model == null) {
      return HotTrackResult(
        actionSignal: ActionSignal.reject,
        newsRating: NewsRating.c,
        coreLogic: '未配置AI模型，请先在设置中配置AI API',
        targets: [],
        newsTitle: news['title'] ?? '',
        newsTime: news['time'] ?? '',
        rawAIResponse: '',
      );
    }

    final newsTitle = news['title']?.toString() ?? '';
    final newsTime = news['time']?.toString() ?? '';

    // 获取新闻正文摘要
    String newsContent = '';
    final newsUrl = news['url']?.toString() ?? '';
    if (newsUrl.isNotEmpty) {
      newsContent = await NewsService.fetchNewsContent(newsUrl);
      // 截取前500字作为摘要
      if (newsContent.length > 500) {
        newsContent = '${newsContent.substring(0, 500)}...';
      }
    }

    // 获取市场热点板块数据作为辅助信息
    String marketContext = '';
    try {
      final api = LocalDataService();
      final sectors = await api.fetchHotSectors();
      if (sectors['A股'] != null && sectors['A股']!.isNotEmpty) {
        final topSectors = sectors['A股']!.take(5).map((s) =>
          '${s['name'] ?? ""}(涨幅${s['change_pct'] ?? "0"}%)').join('、');
        marketContext = '\n当前A股热门板块：$topSectors';
      }
    } catch (_) {}

    // 构建AI请求
    final systemPrompt = _buildSystemPrompt();
    final userPrompt = _buildUserPrompt(newsTitle, newsContent, newsTime, marketContext);
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
    ];

    final rawResponse = await _sendToAI(model, messages);
    return _parseAIResponse(rawResponse, newsTitle, newsTime);
  }

  /// 构建AI决策引擎的System Prompt
  String _buildSystemPrompt() {
    return '''你是一个高级游资量化系统的"AI核心大脑"。本系统采用"初筛模块 -> AI大脑 -> 量化执行模块"的三级架构。目前，第一级的正则关键词初筛模块已经拦截了90%的噪音，并将触发了敏感阈值的【高潜力突发新闻】API数据传送给你。

你的任务是对送达的突发新闻进行深度"预期差"定性与"产业链"推理，找出市场上最核心的对应龙头股票，并为下游的"第三级：量化执行模块"生成极其严格的触发参数。如果新闻评级低下，你必须直接下达"熔断指令"阻止交易。

【处理逻辑】
1. 验真与定性：评估初筛漏过来的新闻是否真的具有爆炒价值（关注是否是"从0到1的新技术"、"重大政策转向"或"突发地缘/供需危机"）。如果只是换汤不换药的陈旧题材，立刻给出 REJECT 指令。
2. 逻辑链推演：对于新题材，不要只看字面，必须推演隐藏的受益端。例如："新能源车销量大增" -> 推演至 -> "上游锂矿紧缺"或"核心零部件供应商"。
3. 标的锁定与参数生成：锁定流通市值在30亿-150亿之间的核心标的，并为下游程序设定严苛的扫板/买入量价参数。

【输出格式】
请严格按以下结构化格式输出，不要添加其他内容：

ACTION_SIGNAL: GO 或 REJECT 或 WAIT
NEWS_RATING: S 或 A 或 B 或 C
CORE_LOGIC: 一句话简述炒作逻辑

TARGET_1_CODE: 股票代码(6位数字)
TARGET_1_NAME: 股票名称
TARGET_1_REASON: 选股理由
TARGET_1_CAP: 流通市值约X亿

TARGET_2_CODE: 股票代码(6位数字)
TARGET_2_NAME: 股票名称
TARGET_2_REASON: 选股理由
TARGET_2_CAP: 流通市值约X亿

TARGET_3_CODE: 股票代码(6位数字)
TARGET_3_NAME: 股票名称
TARGET_3_REASON: 选股理由
TARGET_3_CAP: 流通市值约X亿

TARGET_4_CODE: 股票代码(6位数字)
TARGET_4_NAME: 股票名称
TARGET_4_REASON: 选股理由
TARGET_4_CAP: 流通市值约X亿

TARGET_5_CODE: 股票代码(6位数字)
TARGET_5_NAME: 股票名称
TARGET_5_REASON: 选股理由
TARGET_5_CAP: 流通市值约X亿

MIN_BID_VOLUME_MULTIPLIER: 0.05到0.1之间的数值
OPENING_PRICE_MIN: 开盘涨幅下限%
OPENING_PRICE_MAX: 开盘涨幅上限%
TRIGGER_ACTION: 打板买入/突破买入/竞价抢筹
HARD_STOP_LOSS: 止损位描述

注意：
- 只有S和A级才允许给出GO信号，B和C级必须给REJECT或WAIT
- 若信号为REJECT，标的部分可以只填1-2个或留空
- 股票代码必须是6位数字，名称必须是A股真实股票名称
- 必须推荐3-5只匹配的A股股票''';
  }

  /// 构建用户输入Prompt
  String _buildUserPrompt(String title, String content, String time, String marketContext) {
    final prompt = StringBuffer();
    prompt.writeln('>>> 突发新闻推送 <<<');
    prompt.writeln('新闻时间戳: $time');
    prompt.writeln('新闻标题: $title');
    if (content.isNotEmpty) {
      prompt.writeln('新闻正文摘要: $content');
    }
    if (marketContext.isNotEmpty) {
      prompt.writeln(marketContext);
    }
    prompt.writeln();
    prompt.writeln('请对以上新闻进行AI决策分析，输出结构化报告。');
    return prompt.toString();
  }

  // ============================================================
  // 第三步：解析AI输出
  // ============================================================

  /// 解析AI结构化输出
  HotTrackResult _parseAIResponse(String raw, String newsTitle, String newsTime) {
    // 解析 ACTION_SIGNAL
    final signalMatch = RegExp(r'ACTION_SIGNAL:\s*(GO|REJECT|WAIT)', caseSensitive: false).firstMatch(raw);
    ActionSignal signal = ActionSignal.wait;
    if (signalMatch != null) {
      final s = signalMatch.group(1)!.toUpperCase();
      if (s == 'GO') signal = ActionSignal.go;
      else if (s == 'REJECT') signal = ActionSignal.reject;
      else signal = ActionSignal.wait;
    }

    // 解析 NEWS_RATING
    final ratingMatch = RegExp(r'NEWS_RATING:\s*([SABC])', caseSensitive: false).firstMatch(raw);
    NewsRating rating = NewsRating.c;
    if (ratingMatch != null) {
      final r = ratingMatch.group(1)!.toUpperCase();
      if (r == 'S') rating = NewsRating.s;
      else if (r == 'A') rating = NewsRating.a;
      else if (r == 'B') rating = NewsRating.b;
      else rating = NewsRating.c;
    }

    // 解析 CORE_LOGIC
    final logicMatch = RegExp(r'CORE_LOGIC:\s*(.+)', caseSensitive: false).firstMatch(raw);
    final coreLogic = logicMatch?.group(1)?.trim() ?? '未识别';

    // 解析标的池（1-5个）
    final targets = <TargetStock>[];
    for (int i = 1; i <= 5; i++) {
      final codeMatch = RegExp('TARGET_${i}_CODE:\\s*(\\d{6})').firstMatch(raw);
      final nameMatch = RegExp('TARGET_${i}_NAME:\\s*(.+)').firstMatch(raw);
      final reasonMatch = RegExp('TARGET_${i}_REASON:\\s*(.+)').firstMatch(raw);
      final capMatch = RegExp('TARGET_${i}_CAP:\\s*(.+)').firstMatch(raw);

      if (codeMatch != null && nameMatch != null) {
        final code = codeMatch.group(1)!;
        final name = nameMatch.group(1)!.trim();
        // 清理name中可能混入的后续字段
        final cleanName = name.split(RegExp(r'(TARGET_|MIN_BID|OPENING|TRIGGER|HARD_STOP)')).first.trim();
        final reason = reasonMatch?.group(1)?.trim() ?? '';
        final cleanReason = reason.split(RegExp(r'(TARGET_|MIN_BID|OPENING|TRIGGER|HARD_STOP)')).first.trim();
        final capStr = capMatch?.group(1)?.trim() ?? '0';
        final capNum = double.tryParse(RegExp(r'[\d.]+').firstMatch(capStr)?[0] ?? '0') ?? 0;

        targets.add(TargetStock(
          code: code,
          name: cleanName,
          reason: cleanReason,
          marketCap: capNum,
        ));
      }
    }

    // 解析执行参数
    ExecutionParams? params;
    final minBidMatch = RegExp(r'MIN_BID_VOLUME_MULTIPLIER:\s*([\d.]+)').firstMatch(raw);
    final openMinMatch = RegExp(r'OPENING_PRICE_MIN:\s*([\d.]+)').firstMatch(raw);
    final openMaxMatch = RegExp(r'OPENING_PRICE_MAX:\s*([\d.]+)').firstMatch(raw);
    final triggerMatch = RegExp(r'TRIGGER_ACTION:\s*(.+)').firstMatch(raw);
    final stopLossMatch = RegExp(r'HARD_STOP_LOSS:\s*(.+)').firstMatch(raw);

    if (minBidMatch != null || openMinMatch != null) {
      params = ExecutionParams(
        minBidVolumeMultiplier: double.tryParse(minBidMatch?.group(1) ?? '0.05') ?? 0.05,
        openingPriceMin: double.tryParse(openMinMatch?.group(1) ?? '3') ?? 3,
        openingPriceMax: double.tryParse(openMaxMatch?.group(1) ?? '8') ?? 8,
        triggerAction: triggerMatch?.group(1)?.trim() ?? '打板买入',
        hardStopLoss: stopLossMatch?.group(1)?.trim() ?? '买入价-4%',
      );
    }

    return HotTrackResult(
      actionSignal: signal,
      newsRating: rating,
      coreLogic: coreLogic,
      targets: targets,
      executionParams: params,
      newsTitle: newsTitle,
      newsTime: newsTime,
      rawAIResponse: raw,
    );
  }

  // ============================================================
  // 第四步：行情数据增强
  // ============================================================

  /// 为标的池补充实时行情数据，并用官方名称校验纠正AI生成的名称
  Future<List<TargetStock>> enrichTargetsWithQuotes(List<TargetStock> targets) async {
    if (targets.isEmpty) return targets;

    try {
      final api = LocalDataService();
      for (final target in targets) {
        try {
          // 直接传6位代码给searchStock，由内部_normalizeSymbol自动处理为SS/SZ/BJ格式
          final data = await api.searchStock(target.code);
          if (data != null && data.isNotEmpty) {
            // 用行情API返回的官方名称校验并纠正AI生成的名称
            final apiName = data['name']?.toString().trim() ?? '';
            if (apiName.isNotEmpty) {
              // 官方名称有3种情况：
              // 1) 完全相同 → 无需处理
              // 2) 部分匹配（如AI给简称，API给全称）→ 以API为准，但保留原始名供参考
              // 3) 完全不匹配（AI幻觉）→ 用API官方名称覆盖
              final aiName = target.name.trim();
              final apiShort = apiName.replaceAll(RegExp(r'[\(（].*[\)）]'), '').trim();
              final aiShort = aiName.replaceAll(RegExp(r'[\*＊A]'), '').trim();

              // 检查是否核心部分匹配（取前2字对比或包含关系）
              final coreMatch = aiShort.length >= 2 &&
                  (apiShort.contains(aiShort) ||
                   aiShort.contains(apiShort) ||
                   apiShort.contains(aiShort.substring(0, aiShort.length.clamp(0, 2))));

              if (!coreMatch) {
                // 名称不匹配 → AI幻觉，用官方名称覆盖
                target.name = apiShort;
              } else if (apiName != aiName) {
                // 名称部分匹配但有差异 → 用官方名称
                target.name = apiShort;
              }
              // 完全相同则保持原样
            }

            target.price = _safeDouble(data['price']);
            target.changePct = _safeDouble(data['change_pct']);
            target.turnover = _safeDouble(data['turnover_rate'] ?? data['turnoverratio']);
          }
        } catch (_) {
          // 单个股票获取失败不影响其他
        }
      }
    } catch (_) {}

    return targets;
  }

  // ============================================================
  // AI调用
  // ============================================================

  Future<String> _sendToAI(AIModelConfig model, List<Map<String, String>> messages) async {
    String baseUrl = model.baseUrl.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
    }
    if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);

    final endpoint = '$baseUrl/chat/completions';
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${model.apiKey}',
    };

    final bodyMap = <String, dynamic>{
      'model': model.model,
      'messages': messages,
      'temperature': 0.4, // 降低温度，追求更精确的结构化输出
      'max_tokens': 2000,
    };

    // 兼容DeepSeek/GLM-5/Kimi-K2思考模式禁用
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
        return 'AI返回数据格式异常';
      } else {
        return 'AI请求失败：${response.statusCode}';
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
}
