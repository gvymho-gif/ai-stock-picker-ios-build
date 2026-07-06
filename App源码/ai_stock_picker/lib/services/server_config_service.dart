/// 后端服务器配置服务
///
/// 管理百度云后端地址和Token

import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigService {
  static const String _kServerUrlKey = 'server_url';
  static const String _kServerTokenKey = 'server_token';
  
  static const String defaultServerUrl = 'http://你的服务器IP:8000';
  
  /// 获取服务器地址
  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrlKey) ?? '';
  }
  
  /// 保存服务器地址
  static Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrlKey, url.trim());
  }
  
  /// 获取Token
  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerTokenKey) ?? '';
  }
  
  /// 保存Token
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerTokenKey, token.trim());
  }
  
  /// 检查是否已配置
  static Future<bool> isConfigured() async {
    final url = await getServerUrl();
    final token = await getToken();
    return url.isNotEmpty && token.isNotEmpty;
  }
}
