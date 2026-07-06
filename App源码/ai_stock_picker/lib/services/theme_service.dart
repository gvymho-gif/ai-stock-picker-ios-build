/// 主题管理服务
///
/// 使用SharedPreferences持久化用户主题偏好
/// 支持深色/浅色主题切换

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;

  ThemeService._(this._prefs, this._themeMode);

  /// 初始化ThemeService
  static Future<ThemeService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString(_themeModeKey);
    
    ThemeMode themeMode;
    switch (themeModeString) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.dark; // 默认深色主题
    }

    return ThemeService._(prefs, themeMode);
  }

  /// 当前主题模式
  ThemeMode get themeMode => _themeMode;

  /// 是否为深色主题
  bool get isDark => _themeMode == ThemeMode.dark;

  /// 是否为浅色主题
  bool get isLight => _themeMode == ThemeMode.light;

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      default:
        modeString = 'dark';
    }

    await _prefs.setString(_themeModeKey, modeString);
    notifyListeners();
  }

  /// 切换主题
  Future<void> toggleTheme() async {
    final newMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// 获取主题模式名称（用于显示）
  String get themeModeName {
    switch (_themeMode) {
      case ThemeMode.light:
        return '白天模式';
      case ThemeMode.dark:
        return '夜晚模式';
      default:
        return '跟随系统';
    }
  }

  /// 获取主题图标
  IconData get themeIcon {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      default:
        return Icons.brightness_auto;
    }
  }
}
