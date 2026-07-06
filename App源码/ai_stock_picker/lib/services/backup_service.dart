/// 收益统计 - Gitee云端备份 + 本地文件备份服务
///
/// 双保险方案：
/// 1. Gitee 私有仓库备份（自动/手动）
/// 2. 本地 JSON 文件备份（手动导出/导入）
///
/// v4 修复：
/// - 核心：SHA 死锁时「删库重建」（DELETE repo → CREATE repo → POST 新文件）
/// - 多层 SHA 获取：Contents API → Trees API → Commits API
/// - 自动检测仓库默认分支（master/main），不再硬编码
/// - 错误信息中包含 Gitee 原始响应，便于诊断

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class BackupService {
  static const String _kGiteeTokenKey = 'gitee_token';
  static const String _kGiteeRepoKey = 'gitee_repo_name';
  static const String _kGiteeUserKey = 'gitee_username';
  static const String _kAutoBackupKey = 'auto_backup_enabled';
  static const String _kCloudFileName = 'ai_stock_picker_backup.json';
  static const String _kLocalFileName = '蓝图极智_收益统计备份.json';
  static const String _kGiteeApiBase = 'https://gitee.com/api/v5';
  static const String _kDefaultRepoName = 'ai-stock-picker-backup';
  static const String _kDefaultBranchKey = 'gitee_default_branch';

  // ========== Gitee Token 管理 ==========

  static Future<bool> saveGiteeToken(String token, {String repoName = _kDefaultRepoName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGiteeTokenKey, token);
    await prefs.setString(_kGiteeRepoKey, repoName);
    await prefs.remove(_kDefaultBranchKey);

    final username = await _fetchUsername(token);
    if (username != null) {
      await prefs.setString(_kGiteeUserKey, username);
      print('[备份] 获取 Gitee 用户名: $username');
      return true;
    } else {
      print('[备份] 获取 Gitee 用户名失败，Token 可能无效');
      return false;
    }
  }

  static Future<String?> getGiteeToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGiteeTokenKey);
  }

  static Future<String?> getFullRepoPath() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kGiteeTokenKey);
    if (token == null || token.isEmpty) return null;

    var username = prefs.getString(_kGiteeUserKey);
    if (username == null || username.isEmpty) {
      username = await _fetchUsername(token);
      if (username != null) {
        await prefs.setString(_kGiteeUserKey, username);
      }
    }
    if (username == null) return null;

    final repoName = prefs.getString(_kGiteeRepoKey) ?? _kDefaultRepoName;
    return '$username/$repoName';
  }

  static Future<String?> getRepoName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kGiteeRepoKey) ?? _kDefaultRepoName;
  }

  static Future<void> setAutoBackup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoBackupKey, enabled);
  }

  static Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAutoBackupKey) ?? true;
  }

  static Future<bool> testGiteeToken(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$_kGiteeApiBase/user?access_token=$token'),
        headers: {'User-Agent': 'BlueprintAI-App'},
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _fetchUsername(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$_kGiteeApiBase/user?access_token=$token'),
        headers: {'User-Agent': 'BlueprintAI-App'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          return data['login']?.toString();
        }
      }
      return null;
    } catch (e) {
      print('[备份] 获取用户名异常: $e');
      return null;
    }
  }

  // ========== Gitee 仓库管理 ==========

  static Future<bool> _ensureRepoExists(String token, String repoName) async {
    try {
      final checkResp = await http.get(
        Uri.parse('$_kGiteeApiBase/repos/$repoName?access_token=$token'),
        headers: {'User-Agent': 'BlueprintAI-App'},
      ).timeout(const Duration(seconds: 10));

      if (checkResp.statusCode == 200) {
        print('[备份] 仓库已存在: $repoName');
        return true;
      }

      final nameOnly = repoName.contains('/') ? repoName.split('/').last : repoName;

      print('[备份] 仓库不存在，开始创建: $nameOnly');
      final createResp = await http.post(
        Uri.parse('$_kGiteeApiBase/user/repos?access_token=$token'),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'name': nameOnly,
          'description': '蓝图极智 - 收益统计自动备份',
          'private': true,
          'auto_init': true,
        }),
      ).timeout(const Duration(seconds: 15));

      if (createResp.statusCode == 200 || createResp.statusCode == 201) {
        print('[备份] 仓库创建成功: $repoName');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kDefaultBranchKey);
        return true;
      }

      if (createResp.statusCode == 422) {
        print('[备份] 仓库已存在(422): $repoName');
        return true;
      }

      print('[备份] 仓库创建失败: ${createResp.statusCode} ${createResp.body}');
      return false;
    } catch (e) {
      print('[备份] 确保仓库存在异常: $e');
      return false;
    }
  }

  static Future<String> _detectDefaultBranch(String token, String repoName) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kDefaultBranchKey);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final resp = await http.get(
        Uri.parse('$_kGiteeApiBase/repos/$repoName?access_token=$token'),
        headers: {'User-Agent': 'BlueprintAI-App'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          final branch = data['default_branch']?.toString() ?? 'master';
          print('[备份] 检测到默认分支: $branch');
          await prefs.setString(_kDefaultBranchKey, branch);
          return branch;
        }
      }
    } catch (e) {
      print('[备份] 检测默认分支异常: $e');
    }

    return 'master';
  }

  // ========== 多层 SHA 获取 ==========

  /// 从 Contents API 响应提取 SHA
  static String? _extractShaFromContentsResponse(String responseBody, String targetFileName) {
    try {
      final data = jsonDecode(responseBody);
      if (data is Map) {
        // 依次尝试多个可能的 SHA 字段名
        for (final key in ['sha', 'last_commit_sha', 'oid']) {
          final sha = data[key]?.toString();
          if (sha != null && sha.isNotEmpty && sha != 'null') return sha;
        }
      } else if (data is List) {
        for (var item in data) {
          if (item is Map) {
            final name = item['name']?.toString() ?? item['path']?.toString() ?? '';
            if (name == targetFileName) {
              for (final key in ['sha', 'last_commit_sha', 'oid']) {
                final sha = item[key]?.toString();
                if (sha != null && sha.isNotEmpty && sha != 'null') return sha;
              }
            }
          }
        }
        // 兜底
        for (var item in data) {
          if (item is Map) {
            final sha = item['sha']?.toString();
            if (sha != null && sha.isNotEmpty && sha != 'null') return sha;
          }
        }
      }
      return null;
    } catch (e) {
      print('[备份] Contents API 提取SHA异常: $e');
      return null;
    }
  }

  /// 通过 Trees API 获取文件 SHA
  static Future<String?> _getShaViaTreesApi(String token, String repoName, String branch, String targetFileName) async {
    try {
      final url = '$_kGiteeApiBase/repos/$repoName/git/trees/$branch?access_token=$token';
      print('[备份] [Trees] 查询分支 $branch 文件树...');
      final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['tree'] is List) {
          for (var item in data['tree']) {
            if (item is Map && (item['path']?.toString() == targetFileName)) {
              final sha = item['sha']?.toString();
              if (sha != null && sha.isNotEmpty) {
                print('[备份] [Trees] 找到SHA: ${sha.substring(0, sha.length > 10 ? 10 : sha.length)}...');
                return sha;
              }
            }
          }
        }
      }
      print('[备份] [Trees] 未找到');
    } catch (e) {
      print('[备份] [Trees] 异常: $e');
    }
    return null;
  }

  /// 通过 Commits API 获取文件 SHA
  static Future<String?> _getShaViaCommitsApi(String token, String repoName, String branch, String targetFileName) async {
    try {
      final encodedPath = Uri.encodeComponent(targetFileName);
      final url = '$_kGiteeApiBase/repos/$repoName/commits?path=$encodedPath&sha=$branch&per_page=1&access_token=$token';
      print('[备份] [Commits] 查询...');
      final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List && data.isNotEmpty) {
          final commit = data.first;
          if (commit is Map) {
            final files = commit['files'] as List?;
            if (files != null) {
              for (var file in files) {
                if (file is Map && file['filename']?.toString() == targetFileName) {
                  final sha = file['sha']?.toString();
                  if (sha != null && sha.isNotEmpty) {
                    print('[备份] [Commits] 找到SHA: ${sha.substring(0, sha.length > 10 ? 10 : sha.length)}...');
                    return sha;
                  }
                }
              }
            }
          }
        }
      }
      print('[备份] [Commits] 未找到');
    } catch (e) {
      print('[备份] [Commits] 异常: $e');
    }
    return null;
  }

  /// 综合获取文件 SHA（三层回退）
  static Future<String?> _getFileShaRobust(String token, String repoName, String targetFileName, String branch) async {
    // 第1层：Contents API
    try {
      final url = '$_kGiteeApiBase/repos/$repoName/contents/$targetFileName?ref=$branch&access_token=$token';
      final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final sha = _extractShaFromContentsResponse(resp.body, targetFileName);
        if (sha != null && sha.isNotEmpty) {
          print('[备份] [Contents] SHA获取成功');
          return sha;
        }
        // SHA 提取失败，打印响应摘要
        final preview = resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body;
        print('[备份] [Contents] 200但SHA提取失败，响应: $preview');
      }
    } catch (e) {
      print('[备份] [Contents] 异常: $e');
    }

    // 第2层：Trees API
    final treesSha = await _getShaViaTreesApi(token, repoName, branch, targetFileName);
    if (treesSha != null) return treesSha;

    // 第3层：Commits API
    final commitsSha = await _getShaViaCommitsApi(token, repoName, branch, targetFileName);
    if (commitsSha != null) return commitsSha;

    return null;
  }

  // ========== 核心上传逻辑 ==========

  static Future<Map<String, dynamic>> backupToGiteeWithDetail(
    String token,
    String repoName,
    String content, {
    String? fileName,
  }) async {
    try {
      final targetFileName = fileName ?? _kCloudFileName;
      final contentBase64 = base64Encode(utf8.encode(content)).replaceAll('\n', '');

      // 1. 确保仓库存在
      final repoOk = await _ensureRepoExists(token, repoName);
      if (!repoOk) {
        return {'ok': false, 'error': '仓库不存在且创建失败'};
      }

      // 2. 检测默认分支
      final defaultBranch = await _detectDefaultBranch(token, repoName);
      print('[备份] 默认分支: $defaultBranch');

      // 3. 检测所有可能的分支
      final branches = <String>[defaultBranch];
      if (!branches.contains('master')) branches.add('master');
      if (!branches.contains('main')) branches.add('main');

      // 4. 尝试在各个分支上获取文件信息
      String? fileSha;
      String foundBranch = defaultBranch;
      bool fileExistsOnServer = false;

      for (final branch in branches) {
        try {
          final checkUrl = '$_kGiteeApiBase/repos/$repoName/contents/$targetFileName?ref=$branch&access_token=$token';
          final checkResp = await http.get(Uri.parse(checkUrl), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));

          if (checkResp.statusCode == 200) {
            // 文件存在
            foundBranch = branch;
            fileExistsOnServer = true;
            fileSha = await _getFileShaRobust(token, repoName, targetFileName, branch);
            if (fileSha != null && fileSha.isNotEmpty) {
              print('[备份] 文件已存在 @ $branch, SHA: ${fileSha.substring(0, fileSha.length > 10 ? 10 : fileSha.length)}...');
              break;
            } else {
              print('[备份] 文件已存在 @ $branch, 但SHA获取失败');
              break;
            }
          } else if (checkResp.statusCode == 404) {
            foundBranch = branch;
            print('[备份] 文件不存在 @ $branch，将创建新文件');
            break;
          }
        } catch (e) {
          print('[备份] 分支 $branch 查询异常: $e');
        }
      }

      // 缓存分支名
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDefaultBranchKey, foundBranch);

      // 5. 如果文件存在但拿不到 SHA → 删库重建
      if (fileExistsOnServer && (fileSha == null || fileSha.isEmpty)) {
        print('[备份] 文件存在但SHA获取失败，执行删库重建...');
        final nukeResult = await _nukeAndPave(token, repoName, contentBase64, targetFileName);
        return nukeResult;
      }

      // 6. 正常上传（有 SHA → 更新，无 SHA → 创建新文件）
      final body = <String, dynamic>{
        'content': contentBase64,
        'message': 'Backup $targetFileName: ${DateTime.now()}',
        'branch': foundBranch,
      };
      if (fileSha != null && fileSha.isNotEmpty) {
        body['sha'] = fileSha;
        print('[备份] 更新模式，有SHA');
      } else {
        print('[备份] 创建模式，无SHA');
      }

      final putUrl = '$_kGiteeApiBase/repos/$repoName/contents/${Uri.encodeComponent(targetFileName)}?access_token=$token';
      final resp = await http.put(
        Uri.parse(putUrl),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('[备份] PUT结果: ${resp.statusCode}');

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        print('[备份] 上传成功');
        return {'ok': true, 'error': ''};
      }

      // 7. PUT 失败，如果是 sha 相关错误，删库重建
      final errBody = resp.body;
      if (errBody.contains('sha') && (errBody.contains('missing') || errBody.contains('empty'))) {
        print('[备份] PUT返回sha缺失错误，执行删库重建...');
        final nukeResult = await _nukeAndPave(token, repoName, contentBase64, targetFileName);
        return nukeResult;
      }

      final errMsg = 'HTTP ${resp.statusCode}: ${errBody.length > 300 ? errBody.substring(0, 300) : errBody}';
      return {'ok': false, 'error': errMsg};
    } catch (e) {
      print('[备份] 上传异常: $e');
      return {'ok': false, 'error': '异常: $e'};
    }
  }

  // ========== 删库重建 ==========
  /// 这是解决 SHA 死锁的终极方案
  static Future<Map<String, dynamic>> _nukeAndPave(
    String token,
    String repoName,
    String contentBase64,
    String targetFileName,
  ) async {
    try {
      // 1. 删除仓库
      print('[备份] [删库重建] 删除仓库: $repoName');
      final deleteResp = await http.delete(
        Uri.parse('$_kGiteeApiBase/repos/$repoName?access_token=$token'),
        headers: {'User-Agent': 'BlueprintAI-App'},
      ).timeout(const Duration(seconds: 15));

      print('[备份] [删库重建] 删除结果: ${deleteResp.statusCode}');

      if (deleteResp.statusCode != 200 && deleteResp.statusCode != 204 && deleteResp.statusCode != 202) {
        final errPreview = deleteResp.body.length > 200 ? deleteResp.body.substring(0, 200) : deleteResp.body;
        print('[备份] [删库重建] 删除失败: ${deleteResp.statusCode}: $errPreview');
        // 删除失败，可能是权限不足，尝试用 POST 在新分支创建
        return await _createOnNewBranch(token, repoName, contentBase64, targetFileName);
      }

      // 2. 清除分支缓存
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDefaultBranchKey);

      // 3. 重新创建仓库
      final nameOnly = repoName.contains('/') ? repoName.split('/').last : repoName;
      print('[备份] [删库重建] 重新创建仓库: $nameOnly');

      // 等待 Gitee 完成删除（有时需要短暂延迟）
      await Future.delayed(const Duration(seconds: 2));

      final createResp = await http.post(
        Uri.parse('$_kGiteeApiBase/user/repos?access_token=$token'),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'name': nameOnly,
          'description': '蓝图极智 - 收益统计自动备份',
          'private': true,
          'auto_init': true,
        }),
      ).timeout(const Duration(seconds: 15));

      print('[备份] [删库重建] 创建结果: ${createResp.statusCode}');

      if (createResp.statusCode != 200 && createResp.statusCode != 201) {
        if (createResp.statusCode == 422) {
          // 422 = 仓库还在删除中，等一下重试
          print('[备份] [删库重建] 仓库还在删除中，3秒后重试...');
          await Future.delayed(const Duration(seconds: 3));
          final retryCreate = await http.post(
            Uri.parse('$_kGiteeApiBase/user/repos?access_token=$token'),
            headers: {
              'User-Agent': 'BlueprintAI-App',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode({
              'name': nameOnly,
              'description': '蓝图极智 - 收益统计自动备份',
              'private': true,
              'auto_init': true,
            }),
          ).timeout(const Duration(seconds: 15));
          if (retryCreate.statusCode != 200 && retryCreate.statusCode != 201) {
            final errPreview = retryCreate.body.length > 200 ? retryCreate.body.substring(0, 200) : retryCreate.body;
            return {'ok': false, 'error': '删库重建失败(创建仓库): HTTP ${retryCreate.statusCode}: $errPreview'};
          }
        } else {
          final errPreview = createResp.body.length > 200 ? createResp.body.substring(0, 200) : createResp.body;
          return {'ok': false, 'error': '删库重建失败(创建仓库): HTTP ${createResp.statusCode}: $errPreview'};
        }
      }

      // 4. 重新检测默认分支
      final newBranch = await _detectDefaultBranch(token, repoName);
      print('[备份] [删库重建] 新仓库默认分支: $newBranch');

      // 5. POST 创建新文件（不需要 SHA！）
      final postBody = <String, dynamic>{
        'content': contentBase64,
        'message': 'Backup $targetFileName (fresh): ${DateTime.now()}',
        'branch': newBranch,
      };

      final postUrl = '$_kGiteeApiBase/repos/$repoName/contents/${Uri.encodeComponent(targetFileName)}?access_token=$token';
      final postResp = await http.post(
        Uri.parse(postUrl),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(postBody),
      ).timeout(const Duration(seconds: 30));

      print('[备份] [删库重建] POST结果: ${postResp.statusCode}');

      if (postResp.statusCode == 200 || postResp.statusCode == 201) {
        print('[备份] [删库重建] 成功！');
        return {'ok': true, 'error': ''};
      }

      // POST 也失败？尝试 PUT（有些 Gitee 版本用 PUT 创建新文件）
      final putResp = await http.put(
        Uri.parse(postUrl),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(postBody),
      ).timeout(const Duration(seconds: 30));

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        print('[备份] [删库重建] PUT创建成功！');
        return {'ok': true, 'error': ''};
      }

      final errPreview = postResp.body.length > 300 ? postResp.body.substring(0, 300) : postResp.body;
      return {'ok': false, 'error': '删库重建失败(上传): HTTP ${postResp.statusCode}: $errPreview'};
    } catch (e) {
      print('[备份] [删库重建] 异常: $e');
      return {'ok': false, 'error': '删库重建异常: $e'};
    }
  }

  /// 在新分支上创建文件（删库重建失败时的备选方案）
  static Future<Map<String, dynamic>> _createOnNewBranch(
    String token,
    String repoName,
    String contentBase64,
    String targetFileName,
  ) async {
    // 尝试在一个新分支上用 POST 创建文件
    // 分支名用时间戳确保唯一
    final newBranchName = 'backup-${DateTime.now().millisecondsSinceEpoch}';
    print('[备份] [新分支方案] 在分支 $newBranchName 上创建文件...');

    try {
      // 先获取默认分支的最新 commit SHA（用于创建新分支）
      final defaultBranch = await _detectDefaultBranch(token, repoName);
      String? latestCommitSha;

      try {
        final refUrl = '$_kGiteeApiBase/repos/$repoName/branches/$defaultBranch?access_token=$token';
        final refResp = await http.get(Uri.parse(refUrl), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));
        if (refResp.statusCode == 200) {
          final data = jsonDecode(refResp.body);
          if (data is Map) {
            final commit = data['commit'];
            if (commit is Map) {
              latestCommitSha = commit['sha']?.toString();
            }
          }
        }
      } catch (e) {
        print('[备份] [新分支方案] 获取分支信息失败: $e');
      }

      // 如果拿不到 commit SHA，回退到在当前分支用不同文件名
      if (latestCommitSha == null) {
        print('[备份] [新分支方案] 无法获取commit SHA，尝试用不同文件名...');
        return await _createWithAltFileName(token, repoName, contentBase64);
      }

      // 创建新分支
      final createBranchBody = jsonEncode({
        'branch_name': newBranchName,
        'refs': latestCommitSha,
      });

      final createBranchResp = await http.post(
        Uri.parse('$_kGiteeApiBase/repos/$repoName/branches?access_token=$token'),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: createBranchBody,
      ).timeout(const Duration(seconds: 15));

      if (createBranchResp.statusCode == 200 || createBranchResp.statusCode == 201) {
        // 在新分支上 POST 文件
        final postBody = jsonEncode({
          'content': contentBase64,
          'message': 'Backup (new branch): ${DateTime.now()}',
          'branch': newBranchName,
        });

        final postResp = await http.post(
          Uri.parse('$_kGiteeApiBase/repos/$repoName/contents/${Uri.encodeComponent(targetFileName)}?access_token=$token'),
          headers: {
            'User-Agent': 'BlueprintAI-App',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: postBody,
        ).timeout(const Duration(seconds: 30));

        if (postResp.statusCode == 200 || postResp.statusCode == 201) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kDefaultBranchKey, newBranchName);
          print('[备份] [新分支方案] 成功！');
          return {'ok': true, 'error': ''};
        }
      }

      // 新分支也失败，用不同文件名
      return await _createWithAltFileName(token, repoName, contentBase64);
    } catch (e) {
      print('[备份] [新分支方案] 异常: $e');
      return await _createWithAltFileName(token, repoName, contentBase64);
    }
  }

  /// 用不同的文件名创建（终极兜底）
  static Future<Map<String, dynamic>> _createWithAltFileName(
    String token,
    String repoName,
    String contentBase64,
  ) async {
    final altFileName = 'ai_stock_picker_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final branch = await _detectDefaultBranch(token, repoName);
    print('[备份] [备选文件名] 用 $altFileName @ $branch 创建...');

    try {
      final postBody = jsonEncode({
        'content': contentBase64,
        'message': 'Backup (alt name): ${DateTime.now()}',
        'branch': branch,
      });

      // 先 POST
      final postResp = await http.post(
        Uri.parse('$_kGiteeApiBase/repos/$repoName/contents/$altFileName?access_token=$token'),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: postBody,
      ).timeout(const Duration(seconds: 30));

      if (postResp.statusCode == 200 || postResp.statusCode == 201) {
        print('[备份] [备选文件名] 成功！');
        return {'ok': true, 'error': ''};
      }

      // 再 PUT
      final putResp = await http.put(
        Uri.parse('$_kGiteeApiBase/repos/$repoName/contents/$altFileName?access_token=$token'),
        headers: {
          'User-Agent': 'BlueprintAI-App',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: postBody,
      ).timeout(const Duration(seconds: 30));

      if (putResp.statusCode == 200 || putResp.statusCode == 201) {
        print('[备份] [备选文件名] PUT成功！');
        return {'ok': true, 'error': ''};
      }

      final errPreview = putResp.body.length > 300 ? putResp.body.substring(0, 300) : putResp.body;
      return {'ok': false, 'error': '所有方式均失败（含备选文件名）: HTTP ${putResp.statusCode}: $errPreview'};
    } catch (e) {
      return {'ok': false, 'error': '备选文件名方案异常: $e'};
    }
  }

  static Future<bool> backupToGitee(String token, String repoName, String content) async {
    final result = await backupToGiteeWithDetail(token, repoName, content);
    return result['ok'] == true;
  }

  // ========== Gitee 恢复 ==========

  static Future<String?> restoreFromGitee(String token, String repoName, {String? fileName}) async {
    try {
      final targetFileName = fileName ?? _kCloudFileName;
      final defaultBranch = await _detectDefaultBranch(token, repoName);

      final branches = <String>[defaultBranch];
      if (!branches.contains('master')) branches.add('master');
      if (!branches.contains('main')) branches.add('main');

      for (final branch in branches) {
        final url = '$_kGiteeApiBase/repos/$repoName/contents/$targetFileName?ref=$branch&access_token=$token';
        final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final contentBase64 = _extractContentFromResponse(resp.body);
          if (contentBase64 == null || contentBase64.isEmpty) continue;
          final content = utf8.decode(base64Decode(contentBase64));
          print('[备份] 下载成功($targetFileName @ $branch)');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kDefaultBranchKey, branch);
          return content;
        }
      }

      // 如果默认文件名找不到，尝试查找所有 json 文件
      for (final branch in branches) {
        try {
          final listUrl = '$_kGiteeApiBase/repos/$repoName/contents?ref=$branch&access_token=$token';
          final listResp = await http.get(Uri.parse(listUrl), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));
          if (listResp.statusCode == 200) {
            final data = jsonDecode(listResp.body);
            if (data is List) {
              for (var item in data) {
                if (item is Map) {
                  final name = item['name']?.toString() ?? '';
                  if (name.startsWith('ai_stock_picker_backup') && name.endsWith('.json')) {
                    // 找到备选文件，下载它
                    final altUrl = '$_kGiteeApiBase/repos/$repoName/contents/$name?ref=$branch&access_token=$token';
                    final altResp = await http.get(Uri.parse(altUrl), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 15));
                    if (altResp.statusCode == 200) {
                      final contentBase64 = _extractContentFromResponse(altResp.body);
                      if (contentBase64 != null && contentBase64.isNotEmpty) {
                        final content = utf8.decode(base64Decode(contentBase64));
                        print('[备份] 下载备选文件成功($name @ $branch)');
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(_kDefaultBranchKey, branch);
                        return content;
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          print('[备份] 查找备选文件异常: $e');
        }
      }

      print('[备份] 所有分支均未找到备份文件');
      return null;
    } catch (e) {
      print('[备份] 下载异常: $e');
      return null;
    }
  }

  static Future<bool> hasGiteeBackup(String token, String repoName, {String? fileName}) async {
    final targetFileName = fileName ?? _kCloudFileName;
    try {
      final defaultBranch = await _detectDefaultBranch(token, repoName);
      final branches = <String>[defaultBranch];
      if (!branches.contains('master')) branches.add('master');
      if (!branches.contains('main')) branches.add('main');

      for (final branch in branches) {
        final url = '$_kGiteeApiBase/repos/$repoName/contents/$targetFileName?ref=$branch&access_token=$token';
        final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'BlueprintAI-App'}).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static String? _extractContentFromResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data is! Map) return null;
      return data['content']?.toString().replaceAll('\n', '');
    } catch (e) {
      print('[备份] 提取内容异常: $e');
      return null;
    }
  }

  // ========== 本地文件备份/恢复 ==========

  static Future<String?> exportToLocal(String content) async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        final docDir = await getApplicationDocumentsDirectory();
        final filePath = path.join(docDir.path, _kLocalFileName);
        final file = File(filePath);
        await file.writeAsString(content, flush: true);
        return filePath;
      }
      final filePath = path.join(directory.path, _kLocalFileName);
      final file = File(filePath);
      await file.writeAsString(content, flush: true);
      return filePath;
    } catch (e) {
      print('[备份] 本地导出失败: $e');
      return null;
    }
  }

  static Future<String?> importFromLocal() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        final docDir = await getApplicationDocumentsDirectory();
        final filePath = path.join(docDir.path, _kLocalFileName);
        final file = File(filePath);
        if (await file.exists()) return await file.readAsString();
        return null;
      }
      final filePath = path.join(directory.path, _kLocalFileName);
      final file = File(filePath);
      if (await file.exists()) return await file.readAsString();
      return null;
    } catch (e) {
      print('[备份] 本地导入失败: $e');
      return null;
    }
  }

  static Future<String> getLocalBackupPath() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) return path.join(directory.path, _kLocalFileName);
    final docDir = await getApplicationDocumentsDirectory();
    return path.join(docDir.path, _kLocalFileName);
  }

  // ========== 公共方法 ==========

  static String buildBackupJson(List<dynamic> history) {
    final data = {
      'version': 1,
      'backupTime': DateTime.now().toIso8601String(),
      'recordCount': history.length,
      'history': history.map((r) => r.toJson()).toList(),
    };
    return JsonEncoder.withIndent('  ').convert(data);
  }

  static List<dynamic>? parseBackupJson(String content) {
    try {
      final data = jsonDecode(content);
      if (data is Map && data['history'] is List) return data['history'] as List<dynamic>;
      if (data is List) return data;
      return null;
    } catch (e) {
      print('[备份] 解析 JSON 失败: $e');
      return null;
    }
  }
}
