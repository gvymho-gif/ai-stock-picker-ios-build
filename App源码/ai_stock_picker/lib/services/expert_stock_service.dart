/// 专家选股服务 - 远程后端调用版
///
/// 选股策略已在百度云后端执行，App 端仅做远程调用与结果展示。
/// AI 大模型 API 仍然保留在 App 端，用户可在设置中配置。
///
/// 数据安全：选股逻辑完全托管在后端，APK 反编译无法获取评分公式。

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_model_service.dart';
import 'server_config_service.dart';
import '../models/ai_model_config.dart';

class ExpertStockService {
  static const int _timeoutSeconds = 30;
  static final http.Client _client = http.Client();

  // 锦鲤选股B缓存
  static const String _koiBCacheKey = 'koi_b_analysis_cache';

  /// 获取锦鲤选股B缓存（当天有效）
  static Future<List<Map<String, dynamic>>?> _getKoiBCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_koiBCacheKey);
      if (jsonStr == null) return null;

      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final cacheDate = data['date'] as String?;
      final today = DateTime.now().toString().substring(0, 10);

      if (cacheDate != today) {
        await prefs.remove(_koiBCacheKey);
        return null;
      }

      final stocks = data['stocks'] as List?;
      if (stocks == null || stocks.isEmpty) return null;

      return stocks.cast<Map<String, dynamic>>();
    } catch (e) {
      return null;
    }
  }

  /// 保存锦鲤选股B分析结果到缓存
  static Future<void> _saveKoiBCache(List<Map<String, dynamic>> stocks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toString().substring(0, 10);
      await prefs.setString(_koiBCacheKey, json.encode({
        'date': today,
        'stocks': stocks,
      }));
    } catch (e) {
      // 缓存保存失败不影响主流程
    }
  }

  // ============================================================
  // 策略接口 - 全部通过远程后端调用
  // ============================================================

  Future<Map<String, dynamic>> runShortTermHunter() async {
    return _callRemoteStrategy('short_term_hunter', '短炒猎手', '短线爆发策略');
  }

  Future<Map<String, dynamic>> runGrowthPioneer() async {
    return _callRemoteStrategy('growth_pioneer', '成长先锋', '成长股策略');
  }

  Future<Map<String, dynamic>> runStableFortress() async {
    return _callRemoteStrategy('stable_fortress', '稳健堡垒', '价值投资策略');
  }

  /// A股游资 - T+1
  Future<Map<String, dynamic>> runSpeedAssassin() async {
    return _callRemoteStrategy('speed_assassin', 'A股游资', 'T+1极速博弈与情绪接力');
  }

  /// A股游资B - 后端评分 + App端可选AI增强
  Future<Map<String, dynamic>> runSpeedAssassinB() async {
    final result = await _callRemoteStrategy('speed_assassin_b', 'A股游资B', '游资策略+云端AI精选');
    // App端可选AI增强
    return _applyAIEnhancement(result, 'speed_assassin_b');
  }

  Future<Map<String, dynamic>> runOvernightNavigator() async {
    return _callRemoteStrategy('overnight_navigator', '隔夜导航', '盘后选股+早盘预埋策略');
  }

  /// 锦鲤选股 - 后端评分 + App端可选AI增强
  Future<Map<String, dynamic>> runKoiPicker() async {
    final result = await _callRemoteStrategy('koi_picker', '锦鲤选股', '四因子融合选股');
    return _applyAIEnhancement(result, 'koi_picker');
  }

  /// 锦鲤选股B - 后端评分 + App端可选AI深度增强
  Future<Map<String, dynamic>> runKoiPickerB() async {
    // 检查缓存
    final cachedResults = await _getKoiBCache();
    if (cachedResults != null && cachedResults.isNotEmpty) {
      return {
        'strategy': '锦鲤选股B',
        'description': '量化私募极智穿透分析',
        'stocks': cachedResults,
        'count': cachedResults.length,
        'timestamp': DateTime.now().toIso8601String(),
        'from_cache': true,
      };
    }

    final result = await _callRemoteStrategy('koi_picker_b', '锦鲤选股B', '量化私募极智穿透分析');

    // App端可选AI深度穿透分析
    final enhanced = await _applyKoiBDeepAI(result);

    // 缓存结果
    final stocks = (enhanced['stocks'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ?? [];
    if (stocks.any((s) => ((s['ai_score'] as num?)?.toDouble() ?? 0) > 0)) {
      await _saveKoiBCache(stocks);
    }

    return enhanced;
  }

  // ============================================================
  // 远程调用核心方法
  // ============================================================

  /// 调用远程后端策略
  Future<Map<String, dynamic>> _callRemoteStrategy(
    String strategyId,
    String name,
    String desc,
  ) async {
    final serverUrl = await ServerConfigService.getServerUrl();
    final token = await ServerConfigService.getToken();

    if (serverUrl.isEmpty) {
      return {
        'strategy': name,
        'description': desc,
        'stocks': <Map<String, dynamic>>[],
        'count': 0,
        'warning': '未配置选股服务器地址，请在设置中配置',
      };
    }

    final baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$baseUrl/api/strategy/$strategyId';

    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return data;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'strategy': name,
          'description': desc,
          'stocks': <Map<String, dynamic>>[],
          'count': 0,
          'warning': '后端Token认证失败，请在设置中检查Token',
          'error': 'HTTP ${response.statusCode}',
        };
      } else {
        return {
          'strategy': name,
          'description': desc,
          'stocks': <Map<String, dynamic>>[],
          'count': 0,
          'error': 'HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'strategy': name,
        'description': desc,
        'stocks': <Map<String, dynamic>>[],
        'count': 0,
        'warning': '无法连接选股服务器 ($serverUrl)，请检查网络和配置',
        'error': e.toString(),
      };
    }
  }

  // ============================================================
  // AI增强层（App端保留）
  // ============================================================

  /// 对策略结果进行AI增强（游资B、锦鲤选股适用）
  Future<Map<String, dynamic>> _applyAIEnhancement(
    Map<String, dynamic> result,
    String strategyId,
  ) async {
    final activeModel = await AIModelService.getActiveModel();
    if (activeModel == null) return result;

    final stocks = (result['stocks'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ?? [];
    if (stocks.isEmpty) return result;

    try {
      // 使用后端返回的本地评分数据构建AI提示词
      final prompt = _buildEnhancementPrompt(stocks, strategyId);
      final aiResponse = await _callAIBatchAnalysis(activeModel, prompt);
      final aiResults = _parseAIScores(aiResponse);

      for (int i = 0; i < stocks.length; i++) {
        final code = stocks[i]['code']?.toString() ?? '';
        final aiData = aiResults[code];
        if (aiData != null) {
          final localScore = (stocks[i]['strategy_score'] as num?)?.toDouble() ?? 0;
          final aiScore = aiData['score'] as double? ?? 0;

          stocks[i]['local_score'] = stocks[i]['strategy_score'];
          stocks[i]['ai_score'] = aiScore;
          stocks[i]['ai_analysis_text'] = aiData['comment'] as String? ?? '';

          if (aiScore > 0) {
            stocks[i]['strategy_score'] = localScore * 0.5 + aiScore * 0.5;
          }
        }
      }

      result['stocks'] = stocks;
      result['ai_enhanced'] = true;
    } catch (e) {
      // AI增强失败，使用后端原始结果
      for (final s in stocks) {
        s['local_score'] = s['strategy_score'];
        s['ai_score'] = 0;
        s['ai_analysis_text'] = 'AI增强暂时不可用';
      }
    }

    return result;
  }

  /// 锦鲤选股B - AI深度穿透分析
  Future<Map<String, dynamic>> _applyKoiBDeepAI(Map<String, dynamic> result) async {
    final activeModel = await AIModelService.getActiveModel();
    final stocks = (result['stocks'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ?? [];

    if (activeModel == null) {
      for (final s in stocks) {
        s['ai_analysis_text'] = '⚠️ AI深度分析需要配置AI模型。请前往【极智问答】配置AI模型。';
        s['ai_score'] = 0;
        s['local_score'] = s['strategy_score'];
      }
      result['stocks'] = stocks;
      return result;
    }

    try {
      final prompt = _buildKoiBDeepPrompt(stocks);
      final aiResponse = await _callAIBatchAnalysis(activeModel, prompt);
      final aiResults = _parseKoiBDeepResults(aiResponse);

      for (final s in stocks) {
        final code = s['code']?.toString() ?? '';
        final aiData = aiResults[code];

        if (aiData != null && aiData['ai_valid'] == true) {
          s['local_score'] = s['strategy_score'];
          s['ai_score'] = aiData['score'];
          s['financial_score'] = aiData['financial_score'];
          s['capital_score_koi_b'] = aiData['capital_score'];
          s['technical_score'] = aiData['technical_score'];
          s['decision'] = aiData['decision'];
          s['core_analysis'] = aiData['core_analysis'];
          s['ai_analysis_text'] = aiData['core_analysis'];

          if (aiData['score'] > 0) {
            final localScore = (s['strategy_score'] as num?)?.toDouble() ?? 0;
            s['strategy_score'] = localScore * 0.4 + aiData['score'] * 0.6;
          }
        } else if (s['veto_triggered'] != true) {
          s['decision'] = 'AI分析失败';
          s['core_analysis'] = '⚠️ AI深度穿透分析异常，请检查AI模型配置';
        }
      }
    } catch (e) {
      for (final s in stocks) {
        if (s['veto_triggered'] != true) {
          s['ai_score'] = 0;
          s['decision'] = 'AI分析失败';
          s['core_analysis'] = '⚠️ 网络或AI模型异常，请稍后重试';
        }
      }
    }

    result['stocks'] = stocks;
    return result;
  }

  // ============================================================
  // AI调用与解析
  // ============================================================

  /// 调用云端AI
  Future<String> _callAIBatchAnalysis(AIModelConfig model, String prompt) async {
    String baseUrl = model.baseUrl.trim();
    if (baseUrl.startsWith('ttps://')) baseUrl = 'h$baseUrl';
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) baseUrl = 'https://$baseUrl';
    if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);

    final endpoint = '$baseUrl/chat/completions';
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer ${model.apiKey}',
    };

    final modelNameLower = model.model.toLowerCase();
    final bodyMap = <String, dynamic>{
      'model': model.model,
      'messages': [{'role': 'user', 'content': prompt}],
      'temperature': 0.3,
      'max_tokens': 2500,
    };

    if (modelNameLower.contains('deepseek-v4') || modelNameLower.contains('deepseek-reasoner')) {
      bodyMap['extra_body'] = {'thinking': {'type': 'disabled'}};
    }
    if (modelNameLower.contains('glm-5')) {
      bodyMap['thinking'] = {'type': 'disabled'};
    }
    if (modelNameLower.contains('kimi-k2')) {
      bodyMap['thinking'] = {'type': 'disabled'};
    }

    final body = json.encode(bodyMap);

    final response = await _client.post(
      Uri.parse(endpoint),
      headers: headers,
      body: utf8.encode(body),
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw Exception('AI请求超时(60s)'),
    );

    if (response.statusCode == 200) {
      final responseText = utf8.decode(response.bodyBytes);
      final data = json.decode(responseText);
      final choices = data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'];
        String content = message['content']?.toString() ?? '';
        final reasoningContent = message['reasoning_content']?.toString() ?? '';
        if (reasoningContent.isNotEmpty && content.isEmpty) {
          content = reasoningContent;
        }
        return content;
      }
    }
    throw Exception('AI请求失败: ${response.statusCode}');
  }

  /// 解析简单AI评分结果（代码|评分|评语）
  Map<String, Map<String, dynamic>> _parseAIScores(String aiResponse) {
    final result = <String, Map<String, dynamic>>{};
    if (aiResponse.isEmpty) return result;

    final lines = aiResponse.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|');
      if (parts.length >= 3) {
        final code = parts[0].trim();
        final score = double.tryParse(parts[1].trim()) ?? 0;
        final comment = parts.sublist(2).join('|').trim();
        if (code.isNotEmpty && score > 0) {
          result[code] = {'score': score, 'comment': comment};
        }
      }
    }
    return result;
  }

  /// 解析锦鲤B深度AI结果
  Map<String, Map<String, dynamic>> _parseKoiBDeepResults(String aiResponse) {
    final result = <String, Map<String, dynamic>>{};
    if (aiResponse.isEmpty) return result;

    try {
      final startIndex = aiResponse.indexOf('[');
      final endIndex = aiResponse.lastIndexOf(']');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        final jsonStr = aiResponse.substring(startIndex, endIndex + 1);
        final jsonArray = json.decode(jsonStr) as List;
        for (final item in jsonArray) {
          final data = item as Map<String, dynamic>;
          final code = data['code']?.toString() ?? '';
          if (code.isNotEmpty && data['score'] != null) {
            result[code] = {
              'score': (data['score'] as num).toDouble(),
              'financial_score': (data['financial_score'] as num?)?.toDouble() ?? 0,
              'capital_score': (data['capital_score'] as num?)?.toDouble() ?? 0,
              'technical_score': (data['technical_score'] as num?)?.toDouble() ?? 0,
              'decision': data['decision']?.toString() ?? '',
              'core_analysis': data['core_analysis']?.toString() ?? '',
              'ai_valid': true,
            };
          }
        }
      }
    } catch (_) {
      // JSON解析失败
    }

    // 如果JSON解析失败，尝试旧格式
    if (result.isEmpty) {
      final blocks = aiResponse.split('===');
      for (final block in blocks) {
        final lines = block.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.length < 5) continue;
        try {
          final codeMatch = RegExp(r'\((\d+)\)').firstMatch(lines[0].trim());
          final code = codeMatch?.group(1) ?? '';
          if (code.isEmpty) continue;
          final totalScore = double.tryParse(lines[1].trim()) ?? 0;
          final scores = lines[2].trim().split('|');
          result[code] = {
            'score': totalScore,
            'financial_score': scores.isNotEmpty ? double.tryParse(scores[0].trim()) ?? 0 : 0,
            'capital_score': scores.length >= 2 ? double.tryParse(scores[1].trim()) ?? 0 : 0,
            'technical_score': scores.length >= 3 ? double.tryParse(scores[2].trim()) ?? 0 : 0,
            'decision': lines[3].trim(),
            'core_analysis': lines.sublist(4).join(''),
            'ai_valid': true,
          };
        } catch (_) {}
      }
    }

    return result;
  }

  // ============================================================
  // AI Prompt 构建
  // ============================================================

  String _buildEnhancementPrompt(List<Map<String, dynamic>> stocks, String strategyId) {
    final buf = StringBuffer();
    buf.writeln('你是一位A股量化分析师，请对以下候选股票进行AI辅助评分。');
    buf.writeln('');
    buf.writeln('【候选股票】');

    for (int i = 0; i < stocks.length; i++) {
      final s = stocks[i];
      final name = s['name']?.toString() ?? '';
      final code = s['code']?.toString() ?? '';
      final price = s['price']?.toString() ?? '?';
      final chg = s['change_pct']?.toString() ?? '0';
      final score = s['strategy_score']?.toString() ?? '0';
      buf.writeln('${i + 1}. $name($code) 价$price 涨$chg% 分$score');
    }

    buf.writeln('');
    buf.writeln('【输出格式】');
    buf.writeln('代码|AI评分(0-100)|简短评语');
    buf.writeln('只输出评估结果，不要其他内容。');

    return buf.toString();
  }

  String _buildKoiBDeepPrompt(List<Map<String, dynamic>> stocks) {
    final buf = StringBuffer();
    buf.writeln('你是量化私募基金AI决策中枢，对以下股票进行深度穿透分析。');
    buf.writeln('');

    for (int i = 0; i < stocks.length; i++) {
      final s = stocks[i];
      final name = s['name']?.toString() ?? '';
      final code = s['code']?.toString() ?? '';
      final score = s['strategy_score']?.toString() ?? '0';
      buf.writeln('${i + 1}. $name($code) 本地评分:$score');
    }

    buf.writeln('');
    buf.writeln('【输出格式】只输出JSON数组：');
    buf.writeln('[{"code":"代码","score":总分,"financial_score":财务0-40,"capital_score":资金0-40,"technical_score":技术0-20,"decision":"强力推荐/建议观察/淘汰剔除","core_analysis":"分析"}]');

    return buf.toString();
  }
}
