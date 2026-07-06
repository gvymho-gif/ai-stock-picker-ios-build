/// 坚果云 WebDAV 备份服务
///
/// 通过坚果云第三方应用密码进行 WebDAV 协议的上传下载备份
/// 设置 → 坚果云 → 填入应用名称和应用密码即可使用

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class JianguoyunService {
  static const String _kAppNameKey = 'jianguoyun_app_name';
  static const String _kAppPasswordKey = 'jianguoyun_app_password';
  static const String _kHost = 'dav.jianguoyun.com';
  static const String _kFolderName = '蓝图极智AI选股';

  // ========== 配置管理 ==========

  static Future<void> saveCredentials(String appName, String appPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppNameKey, appName.trim());
    await prefs.setString(_kAppPasswordKey, appPassword.trim());
  }

  static Future<String?> getAppName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAppNameKey);
  }

  static Future<String?> getAppPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAppPasswordKey);
  }

  static Future<bool> isConfigured() async {
    final name = await getAppName();
    final pwd = await getAppPassword();
    return name != null && name.isNotEmpty && pwd != null && pwd.isNotEmpty;
  }

  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAppNameKey);
    await prefs.remove(_kAppPasswordKey);
  }

  /// 验证凭据有效性（PROPFIND 查询根目录）
  static Future<bool> testCredentials(String appName, String appPassword) async {
    try {
      final auth = base64Encode(utf8.encode('$appName:$appPassword'));
      final request = http.Request('PROPFIND', _rootUri())
        ..headers['Authorization'] = 'Basic $auth'
        ..headers['User-Agent'] = 'BlueprintAI-App'
        ..headers['Depth'] = '0';
      final resp = await request.send().timeout(const Duration(seconds: 10));
      final statusCode = resp.statusCode;
      debugPrint('[坚果云] 凭据验证: HTTP $statusCode');
      return statusCode == 207 || statusCode == 404;
    } catch (e) {
      debugPrint('[坚果云] 凭据验证异常: $e');
      return false;
    }
  }

  // ========== 核心上传 ==========

  /// 上传JSON数据到坚果云
  /// [moduleName] 模块标识（用于文件名：{moduleName}_backup.json）
  /// [content] JSON字符串
  static Future<Map<String, dynamic>> upload(String moduleName, String content) async {
    try {
      final appName = await getAppName();
      final appPassword = await getAppPassword();
      if (appName == null || appPassword == null || appName.isEmpty || appPassword.isEmpty) {
        return {'ok': false, 'error': '坚果云凭据未配置，请先在设置中填入应用名称和应用密码'};
      }

      final auth = base64Encode(utf8.encode('$appName:$appPassword'));
      final fileName = _fileName(moduleName);
      final uri = _fileUri(fileName);

      // 1. 先确保目录存在（MKCOL）
      final folderOk = await _ensureFolder(appName, appPassword, auth);
      if (!folderOk) {
        return {'ok': false, 'error': '坚果云目录创建失败，请检查应用密码是否正确'};
      }

      // 2. PUT 文件
      debugPrint('[坚果云] 上传 $fileName (${content.length} 字符) -> $uri');
      final resp = await http.put(
        uri,
        headers: {
          'Authorization': 'Basic $auth',
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(content),
      ).timeout(const Duration(seconds: 30));

      debugPrint('[坚果云] 上传结果: ${resp.statusCode}');
      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
        return {'ok': true, 'error': ''};
      }
      return {'ok': false, 'error': 'HTTP ${resp.statusCode}: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}'};
    } catch (e) {
      debugPrint('[坚果云] 上传异常: $e');
      return {'ok': false, 'error': '异常: $e'};
    }
  }

  // ========== 核心下载 ==========

  /// 从坚果云下载JSON数据
  /// 返回 Map {ok, content, error, statusCode}
  static Future<Map<String, dynamic>> downloadWithDetails(String moduleName) async {
    try {
      final appName = await getAppName();
      final appPassword = await getAppPassword();
      if (appName == null || appPassword == null || appName.isEmpty || appPassword.isEmpty) {
        return {'ok': false, 'content': null, 'error': '凭据未配置', 'statusCode': 0};
      }

      final auth = base64Encode(utf8.encode('$appName:$appPassword'));
      final fileName = _fileName(moduleName);
      final uri = _fileUri(fileName);

      debugPrint('[坚果云] 下载 $moduleName -> 文件名 $fileName -> URI $uri');

      // ★ 使用 IOClient 以确保跟随重定向
      final client = http.Client();
      try {
        final resp = await client.get(
          uri,
          headers: {'Authorization': 'Basic $auth', 'User-Agent': 'BlueprintAI-App'},
        ).timeout(const Duration(seconds: 30));

        debugPrint('[坚果云] 下载结果: HTTP ${resp.statusCode}, 内容长度 ${resp.bodyBytes.length} 字节');
        debugPrint('[坚果云] 响应头 Content-Type: ${resp.headers['content-type']}');

        if (resp.statusCode == 200) {
          final text = utf8.decode(resp.bodyBytes);
          debugPrint('[坚果云] 解码文本长度: ${text.length} 字符, 前100字: ${text.length > 100 ? text.substring(0, 100) : text}');
          return {'ok': true, 'content': text, 'error': '', 'statusCode': 200};
        }

        // 非 200 的详细错误信息
        final bodyPreview = resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body;
        debugPrint('[坚果云] 下载失败: HTTP ${resp.statusCode}, body: $bodyPreview');
        return {'ok': false, 'content': null, 'error': 'HTTP ${resp.statusCode}: $bodyPreview', 'statusCode': resp.statusCode};
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[坚果云] 下载异常: $e');
      return {'ok': false, 'content': null, 'error': '网络异常: $e', 'statusCode': 0};
    }
  }

  /// 兼容旧接口：从坚果云下载JSON数据，失败返回 null
  static Future<String?> download(String moduleName) async {
    final r = await downloadWithDetails(moduleName);
    return r['content'] as String?;
  }

  /// 检查云端是否有备份
  static Future<bool> hasBackup(String moduleName) async {
    final r = await downloadWithDetails(moduleName);
    return r['ok'] == true && (r['content'] as String? ?? '').isNotEmpty;
  }

  // ========== 目录列表（诊断用） ==========

  /// 列出坚果云备份目录中的所有文件（用于诊断）
  static Future<Map<String, dynamic>> listFiles() async {
    try {
      final appName = await getAppName();
      final appPassword = await getAppPassword();
      if (appName == null || appPassword == null) {
        return {'ok': false, 'files': [], 'error': '凭据未配置'};
      }

      final auth = base64Encode(utf8.encode('$appName:$appPassword'));
      final request = http.Request('PROPFIND', _folderUri());
      request.headers['Authorization'] = 'Basic $auth';
      request.headers['User-Agent'] = 'BlueprintAI-App';
      request.headers['Depth'] = '1';

      final resp = await request.send().timeout(const Duration(seconds: 15));
      final body = await resp.stream.bytesToString();
      debugPrint('[坚果云] PROPFIND 目录列表: HTTP ${resp.statusCode}');

      if (resp.statusCode == 207) {
        // 解析 XML 提取文件名
        final files = <String>[];
        // 简单提取 href 标签中的内容
        final hrefRegex = RegExp(r'<d:href>([^<]+)</d:href>', caseSensitive: false);
        for (final match in hrefRegex.allMatches(body)) {
          final href = match.group(1) ?? '';
          // 只取文件名部分（去掉目录路径）
          final decoded = Uri.decodeFull(href);
          if (decoded.contains('_backup.json')) {
            files.add(decoded.split('/').last);
          }
        }
        debugPrint('[坚果云] 找到 ${files.length} 个备份文件: $files');
        return {'ok': true, 'files': files, 'error': ''};
      }

      return {'ok': false, 'files': [], 'error': 'HTTP ${resp.statusCode}'};
    } catch (e) {
      debugPrint('[坚果云] 列出文件异常: $e');
      return {'ok': false, 'files': [], 'error': '异常: $e'};
    }
  }

  // ========== 内部方法 ==========

  static Uri _rootUri() => Uri(scheme: 'https', host: _kHost, pathSegments: ['dav']);

  static Uri _folderUri() => Uri(scheme: 'https', host: _kHost, pathSegments: ['dav', _kFolderName]);

  static Uri _fileUri(String fileName) => Uri(
        scheme: 'https',
        host: _kHost,
        pathSegments: ['dav', _kFolderName, fileName],
      );

  static String _fileName(String moduleName) {
    return '${moduleName}_backup.json';
  }

  /// 确保目录存在（MKCOL 创建目录）
  static Future<bool> _ensureFolder(String appName, String appPassword, String auth) async {
    try {
      // 先用 PROPFIND 检查目录是否已存在
      final checkRequest = http.Request('PROPFIND', _folderUri())
        ..headers['Authorization'] = 'Basic $auth'
        ..headers['User-Agent'] = 'BlueprintAI-App'
        ..headers['Depth'] = '0';
      final checkResp = await checkRequest.send().timeout(const Duration(seconds: 10));
      final checkStatus = checkResp.statusCode;

      if (checkStatus == 207) {
        debugPrint('[坚果云] 目录已存在: $_kFolderName');
        return true;
      }

      debugPrint('[坚果云] MKCOL 创建目录 $_kFolderName...');
      final mkcolRequest = http.Request('MKCOL', _folderUri())
        ..headers['Authorization'] = 'Basic $auth'
        ..headers['User-Agent'] = 'BlueprintAI-App';
      final mkcolResp = await mkcolRequest.send().timeout(const Duration(seconds: 10));
      final mkcolStatus = mkcolResp.statusCode;

      debugPrint('[坚果云] MKCOL结果: $mkcolStatus');
      if (mkcolStatus == 201 || mkcolStatus == 405) {
        return true;
      }

      final body = await mkcolResp.stream.bytesToString();
      debugPrint('[坚果云] MKCOL失败: HTTP $mkcolStatus, body: ${body.length > 200 ? body.substring(0, 200) : body}');
      return false;
    } catch (e) {
      debugPrint('[坚果云] 创建目录异常: $e');
      return false;
    }
  }
}
