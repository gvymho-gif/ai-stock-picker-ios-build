/// 投资组合同步服务
///
/// 双向同步：上传本地数据到服务器 / 从服务器恢复到本地。
/// 覆盖：极速投资 / 热点投资 / 轻量投资 / 收益统计 / 交易日记录
library portfolio_sync_service;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_service.dart';

class PortfolioSyncService {
  static final http.Client _client = http.Client();

  // ============================================================
  // 所有需要同步的存储 Key 映射
  // ============================================================

  static const Map<String, String> _storageKeys = {
    'speed': 'speed_portfolios',
    'hot': 'hot_investment_portfolios',
    'lite': 'lite_investment_portfolios',
  };

  static const Map<String, String> _extraKeys = {
    'speed': 'speed_settlements',
  };

  // ============================================================
  // 上传：从本地读取并同步到服务器
  // ============================================================

  static Future<Map<String, String>> syncAll() async {
    final results = <String, String>{};

    final config = await _getConfig();
    final baseUrl = config[0];
    final token = config[1];
    if (baseUrl == null) {
      return {'error': '未配置服务器地址和Token'};
    }

    // 三大投资组合
    for (final type in ['speed', 'hot', 'lite']) {
      try {
        results[type] = await _uploadPortfolios(baseUrl, token!, type);
      } catch (e) {
        results[type] = '同步失败: $e';
      }
    }

    // 收益统计
    try {
      results['收益统计'] = await _uploadGeneric(baseUrl, token!, 'performance', 'expert_performance_history');
    } catch (e) {
      results['收益统计'] = '同步失败: $e';
    }

    // 交易日记录
    try {
      results['交易日记录'] = await _uploadGeneric(baseUrl, token!, 'trading_day_records', 'trading_day_records');
    } catch (e) {
      results['交易日记录'] = '同步失败: $e';
    }

    return results;
  }

  static Future<String> _uploadPortfolios(
    String baseUrl, String token, String type,
  ) async {
    final key = _storageKeys[type] ?? '${type}_investment_portfolios';
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return '本地无数据';
    }

    final portfolios = json.decode(raw);
    if (portfolios is! List || portfolios.isEmpty) {
      return '本地无数据';
    }

    final Map<String, dynamic> payload = {'portfolios': portfolios};

    // ★ 热点/轻量：同时上传日历归档数据
    if (type == 'hot' || type == 'lite') {
      final archiveKey = type == 'hot' 
          ? 'hot_invest_calendar_archive' 
          : 'lite_invest_calendar_archive';
      final archiveRaw = prefs.getString(archiveKey);
      if (archiveRaw != null && archiveRaw.isNotEmpty) {
        try {
          final archiveList = json.decode(archiveRaw);
          if (archiveList is List && archiveList.isNotEmpty) {
            payload['calendarArchive'] = archiveList;
          }
        } catch (_) {}
      }
    }

    final body = json.encode(payload);
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/portfolio/$type/sync'),
      headers: _headers(token),
      body: utf8.encode(body),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final extra = payload.containsKey('calendarArchive') 
          ? ' + ${(payload['calendarArchive'] as List).length}条归档' 
          : '';
      return '已同步 ${portfolios.length} 个组合$extra';
    }
    return 'HTTP ${resp.statusCode}';
  }

  static Future<String> _uploadGeneric(
    String baseUrl, String token, String serverName, String localKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(localKey);
    if (raw == null || raw.isEmpty) {
      return '本地无数据';
    }

    final body = json.encode({'data': raw});
    final resp = await _client.post(
      Uri.parse('$baseUrl/api/portfolio/$serverName/sync'),
      headers: _headers(token),
      body: utf8.encode(body),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      return '已同步';
    }
    return 'HTTP ${resp.statusCode}';
  }

  // ============================================================
  // 下载恢复：从服务器拉取并写入本地
  // ============================================================

  static Future<Map<String, String>> restoreAll() async {
    final results = <String, String>{};

    final config = await _getConfig();
    final baseUrl = config[0];
    final token = config[1];
    if (baseUrl == null) {
      return {'error': '未配置服务器地址和Token'};
    }

    // 三大投资组合
    for (final type in ['speed', 'hot', 'lite']) {
      try {
        results[type] = await _restorePortfolios(baseUrl, token!, type);
      } catch (e) {
        results[type] = '恢复失败: $e';
      }
    }

    // 恢复后通知各 Service 强制重新加载
    await _forceReloadAllServices();

    // 收益统计
    try {
      results['收益统计'] = await _restoreGeneric(baseUrl, token!, 'performance', 'expert_performance_history', isPerformance: true);
    } catch (e) {
      results['收益统计'] = '恢复失败: $e';
    }

    // 交易日记录
    try {
      results['交易日记录'] = await _restoreGeneric(baseUrl, token!, 'trading_day_records', 'trading_day_records');
    } catch (e) {
      results['交易日记录'] = '恢复失败: $e';
    }

    return results;
  }

  /// 通知所有相关服务从 SharedPreferences 重新加载数据
  static Future<void> _forceReloadAllServices() async {
    try {
      // 用 import 路径延迟加载避免循环依赖
      // 通过 dynamic 调用避免静态依赖
      // ignore: avoid_dynamic_calls
      final speedService = _tryGetServiceInstance('SpeedInvestmentService');
      if (speedService != null) {
        await speedService.forceReload();
        await speedService.load();
      }
    } catch (_) {}
    try {
      final hotService = _tryGetServiceInstance('HotInvestmentService');
      if (hotService != null) {
        hotService.forceReload();
        await hotService.load();
      }
    } catch (_) {}
    try {
      final liteService = _tryGetServiceInstance('LiteInvestmentService');
      if (liteService != null) {
        liteService.forceReload();
        await liteService.load();
      }
    } catch (_) {}
  }

  /// 尝试通过 import 获取已存在的单例（避免循环依赖问题）
  static dynamic _tryGetServiceInstance(String className) {
    // 使用 ServiceAccess 单例
    return ServiceAccess.get(className);
  }

  static Future<String> _restorePortfolios(
    String baseUrl, String token, String type,
  ) async {
    final url = '$baseUrl/api/portfolio/${type}_portfolios';
    print('[恢复] $type: $url');

    http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url), headers: _headers(token))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      return '网络异常: $e';
    }

    if (resp.statusCode != 200) return 'HTTP ${resp.statusCode}';

    String rawBody;
    try {
      rawBody = utf8.decode(resp.bodyBytes);
    } catch (_) {
      rawBody = latin1.decode(resp.bodyBytes);
    }

    Map<String, dynamic> body;
    try {
      body = json.decode(rawBody) as Map<String, dynamic>;
    } catch (e) {
      return 'JSON解析失败';
    }

    dynamic rawData = body['data'] ?? body;
    if (rawData is! Map) return '数据格式异常';

    final data = rawData.cast<String, dynamic>();
    final rawPortfolios = data['portfolios'];
    if (rawPortfolios == null) return '无数据';
    if (rawPortfolios is! List) return '格式异常';
    if (rawPortfolios.isEmpty) return '空列表';

    // ★ 去重：按 id 保留唯一，跳过无效组合
    final seenIds = <String>{};
    final deduped = <dynamic>[];
    for (final pf in rawPortfolios) {
      if (pf is! Map) continue;
      final id = pf['id']?.toString() ?? '';
      if (id.isEmpty || seenIds.contains(id)) continue;
      seenIds.add(id);
      deduped.add(pf);
    }

    final key = _storageKeys[type] ?? '${type}_investment_portfolios';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(deduped));

    // ★ 热点/轻量：同时恢复日历归档数据
    if (type == 'hot' || type == 'lite') {
      final rawArchive = data['calendarArchive'];
      if (rawArchive is List && rawArchive.isNotEmpty) {
        final archiveKey = type == 'hot'
            ? 'hot_invest_calendar_archive'
            : 'lite_invest_calendar_archive';
        await prefs.setString(archiveKey, json.encode(rawArchive));
        return '已恢复 ${deduped.length} 个组合 + ${rawArchive.length} 条归档';
      }
    }

    // ★ 额外恢复：speed 类型时同步 settlements（用于日历归档）
    if (type == 'speed' && data['settlements'] is List) {
      final settleKey = _extraKeys['speed']!;
      await prefs.setString(settleKey, json.encode(data['settlements']));
      return '已恢复 ${deduped.length} 个组合 + ${(data['settlements'] as List).length} 条结算';
    }

    return '已恢复 ${deduped.length} 个组合';
  }

  static Future<String> _restoreGeneric(
    String baseUrl, String token, String serverName, String localKey,
    {bool isPerformance = false}) async {
    final url = '$baseUrl/api/portfolio/$serverName';
    print('[恢复] $serverName: $url');

    http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url), headers: _headers(token))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      return '网络异常: $e';
    }

    if (resp.statusCode != 200) return 'HTTP ${resp.statusCode}';

    String rawBody;
    try {
      rawBody = utf8.decode(resp.bodyBytes);
    } catch (_) {
      rawBody = latin1.decode(resp.bodyBytes);
    }

    Map<String, dynamic> body;
    try {
      body = json.decode(rawBody) as Map<String, dynamic>;
    } catch (e) {
      return 'JSON解析失败';
    }

    // 提取数据（统一处理为 list，App 端期望 list 格式）
    List<dynamic>? dataList;

    // 情况1: 服务器返回 {"data": [...]}（performance 接口）
    if (body['data'] is List) {
      dataList = body['data'] as List<dynamic>;
    }
    // 情况2: 服务器返回 {"data": {...}}（包装在 dict 里）
    else if (body['data'] is Map && (body['data'] as Map)['data'] is List) {
      dataList = ((body['data'] as Map)['data'] as List<dynamic>);
    }
    // 情况3: 服务器返回 {"data": "<json字符串>"}（老接口）
    else if (body['data'] is String) {
      try {
        final parsed = json.decode(body['data']);
        if (parsed is List) {
          dataList = parsed;
        } else if (parsed is Map) {
          // 尝试从 Map 找 list
          for (final v in parsed.values) {
            if (v is List && v.isNotEmpty) {
              dataList = v;
              break;
            }
          }
        }
      } catch (_) {}
    }
    // 情况4: 整个 body 包含嵌套 data
    if (dataList == null) {
      for (final key in ['performance', 'records', 'list']) {
        if (body[key] is List) {
          dataList = body[key] as List<dynamic>;
          break;
        }
      }
    }

    if (dataList == null || dataList.isEmpty) {
      return '无数据';
    }

    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(dataList);
    await prefs.setString(localKey, encoded);
    return '已恢复 ${dataList.length} 条记录';
  }

  // ============================================================
  // 工具方法
  // ============================================================

  /// 获取配置 (返回 [baseUrl, token]，未配置时 baseUrl 为 null)
  static Future<List<String?>> _getConfig() async {
    final url = await ServerConfigService.getServerUrl();
    final token = await ServerConfigService.getToken();
    if (url.isEmpty || token.isEmpty) return [null, null];
    return [url.replaceAll(RegExp(r'/+$'), ''), token];
  }

  static Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
}

/// 服务访问器（避免循环依赖）
class ServiceAccess {
  static final Map<String, dynamic> _instances = {};

  static void register(String name, dynamic instance) {
    _instances[name] = instance;
  }

  static dynamic get(String name) => _instances[name];
}
