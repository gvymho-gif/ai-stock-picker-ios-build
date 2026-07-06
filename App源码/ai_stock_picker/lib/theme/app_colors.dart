/// 年轻化配色系统 - AI智能选股
///
/// 设计理念：
/// - 深色模式：深邃的深蓝紫渐变背景 + 玻璃态卡片效果
/// - 浅色模式：清新明亮白色背景 + 深色文字确保清晰可见
/// - 鲜艳的紫蓝强调色
/// - 更有活力的涨跌色

import 'package:flutter/material.dart';

/// 颜色主题接口
abstract class AppColorScheme {
  // 渐变背景
  Color get background;
  Color get backgroundSecondary;
  Color get gradientStart;
  Color get gradientEnd;

  // 玻璃态卡片
  Color get glassCard;
  Color get glassBorder;
  Color get glassHighlight;

  // 卡片/容器
  Color get surface;
  Color get surfaceElevated;
  Color get surfaceVariant;

  // 主色调
  Color get primary;
  Color get primaryLight;
  Color get primaryDark;
  Color get primaryContainer;

  // 强调色
  Color get accent;
  Color get gradientPurple;
  Color get gradientPink;

  // 涨跌色（固定）
  Color get up;
  Color get upLight;
  Color get down;
  Color get downLight;
  Color get neutral;

  // 文字色
  Color get textPrimary;
  Color get textSecondary;
  Color get textHint;
  Color get textDisabled;

  // 边框
  Color get border;
  Color get divider;
  Color get borderGlow;

  // 功能色
  Color get success;
  Color get warning;
  Color get error;
  Color get info;

  // 阴影
  Color get shadowPurple;
  Color get shadowDark;

  // 渐变
  List<Color> get primaryGradient;
  List<Color> get backgroundGradient;
  List<Color> get upGradient;
  List<Color> get downGradient;
  List<Color> get buyGradient;
  List<Color> get sellGradient;

  // 特殊卡片渐变
  Color get expertEntryStart;
  Color get expertEntryEnd;
  Color get portfolioEntryStart;
  Color get portfolioEntryEnd;
  Color get priceHeaderStart;
  Color get priceHeaderEnd;
  Color get riskCardBg;

  // 热点投资卡片渐变（橙黄系）
  Color get hotInvestCardStart;
  Color get hotInvestCardEnd;
  Color get hotInvestAccent;
  Color get hotInvestLight;
  List<Color> get hotInvestGradient;

  // 轻量投资卡片渐变（青色系）
  Color get liteInvestCardStart;
  Color get liteInvestCardEnd;
  Color get liteInvestAccent;
  Color get liteInvestLight;
  List<Color> get liteInvestGradient;

  // 极速投资卡片渐变（蓝色系）
  Color get speedInvestCardStart;
  Color get speedInvestCardEnd;
  Color get speedInvestAccent;
  List<Color> get speedInvestGradient;

  // 工具方法
  Color getScoreColor(double score);
  Color getPriceColor(double changePct);
  Color getActionColor(String action);
  Color getTrendColor(String trend);
}

/// 深色主题颜色
class AppColorsDark implements AppColorScheme {
  @override
  Color get background => const Color(0xFF06060F);

  @override
  Color get backgroundSecondary => const Color(0xFF0A0A18);

  @override
  Color get gradientStart => const Color(0xFF08081A);

  @override
  Color get gradientEnd => const Color(0xFF101028);

  @override
  Color get glassCard => const Color(0x1AFFFFFF);

  @override
  Color get glassBorder => const Color(0x33FFFFFF);

  @override
  Color get glassHighlight => const Color(0x0DFFFFFF);

  @override
  Color get surface => const Color(0xFF1C1C3E);

  @override
  Color get surfaceElevated => const Color(0xFF24244E);

  @override
  Color get surfaceVariant => const Color(0xFF2E2E56);

  @override
  Color get primary => const Color(0xFF6C63FF);

  @override
  Color get primaryLight => const Color(0xFF8B85FF);

  @override
  Color get primaryDark => const Color(0xFF5249E6);

  @override
  Color get primaryContainer => const Color(0x266C63FF);

  @override
  Color get accent => const Color(0xFFA855F7);

  @override
  Color get gradientPurple => const Color(0xFF9333EA);

  @override
  Color get gradientPink => const Color(0xFFEC4899);

  @override
  Color get up => const Color(0xFFFF6B6B);

  @override
  Color get upLight => const Color(0xFFFF8A8A);

  @override
  Color get down => const Color(0xFF4ECDC4);

  @override
  Color get downLight => const Color(0xFF7EDDD6);

  @override
  Color get neutral => const Color(0xFFFFB347);

  @override
  Color get textPrimary => Colors.white;

  @override
  Color get textSecondary => const Color(0xFFB4B4D0);

  @override
  Color get textHint => const Color(0xFF6B6B8D);

  @override
  Color get textDisabled => const Color(0xFF3D3D5C);

  @override
  Color get border => const Color(0xFF33335A);

  @override
  Color get divider => const Color(0xFF26264A);

  @override
  Color get borderGlow => const Color(0x406C63FF);

  @override
  Color get success => const Color(0xFF4ECDC4);

  @override
  Color get warning => const Color(0xFFFFB347);

  @override
  Color get error => const Color(0xFFFF6B6B);

  @override
  Color get info => const Color(0xFF6C63FF);

  @override
  Color get shadowPurple => const Color(0x336C63FF);

  @override
  Color get shadowDark => const Color(0x4D000000);

  @override
  List<Color> get primaryGradient => [primary, accent];

  @override
  List<Color> get backgroundGradient => [gradientStart, gradientEnd];

  @override
  List<Color> get upGradient => [up, const Color(0xFFFF8E8E)];

  @override
  List<Color> get downGradient => [down, const Color(0xFF6FD9D0)];

  @override
  List<Color> get buyGradient => [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)];

  @override
  List<Color> get sellGradient => [const Color(0xFF4ECDC4), const Color(0xFF44A08D)];

  @override
  Color get expertEntryStart => const Color(0xFF1E1040);

  @override
  Color get expertEntryEnd => const Color(0xFF2A1560);

  @override
  Color get portfolioEntryStart => const Color(0xFF2A2318);

  @override
  Color get portfolioEntryEnd => const Color(0xFF332A1C);

  @override
  Color get priceHeaderStart => const Color(0xFF1A1040);

  @override
  Color get priceHeaderEnd => const Color(0xFF251860);

  @override
  Color get riskCardBg => const Color(0xFF1A1020);

  @override
  Color get hotInvestCardStart => const Color(0xFF1E1408);

  @override
  Color get hotInvestCardEnd => const Color(0xFF2A2008);

  @override
  Color get hotInvestAccent => const Color(0xFFFFA726);

  @override
  Color get hotInvestLight => const Color(0xFFFFCC80);

  @override
  List<Color> get hotInvestGradient => [const Color(0xFFFFA726), const Color(0xFFFF8F00)];

  // ── 轻量投资（青色系）──
  @override
  Color get liteInvestCardStart => const Color(0xFF081E1A);

  @override
  Color get liteInvestCardEnd => const Color(0xFF0A2A24);

  @override
  Color get liteInvestAccent => const Color(0xFF26A69A);

  @override
  Color get liteInvestLight => const Color(0xFF80CBC4);

  @override
  List<Color> get liteInvestGradient => [const Color(0xFF26A69A), const Color(0xFF00897B)];

  @override
  Color get speedInvestCardStart => const Color(0xFF0A1630);
  @override
  Color get speedInvestCardEnd => const Color(0xFF0D1F40);
  @override
  Color get speedInvestAccent => const Color(0xFF3B82F6);
  @override
  List<Color> get speedInvestGradient => [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)];

  @override
  Color getScoreColor(double score) {
    if (score >= 0.7) return up;
    if (score >= 0.5) return neutral;
    return down;
  }

  @override
  Color getPriceColor(double changePct) => changePct >= 0 ? up : down;

  @override
  Color getActionColor(String action) {
    switch (action) {
      case 'buy': return up;
      case 'avoid': return down;
      case 'hold': return neutral;
      default: return textSecondary;
    }
  }

  @override
  Color getTrendColor(String trend) {
    switch (trend) {
      case 'bullish': return up;
      case 'bearish': return down;
      case 'neutral': return neutral;
      default: return textSecondary;
    }
  }
}

/// 浅色主题颜色 - 清新明亮风格
class AppColorsLight implements AppColorScheme {
  @override
  Color get background => const Color(0xFFFFFFFF);

  @override
  Color get backgroundSecondary => const Color(0xFFF5F5F7);

  @override
  Color get gradientStart => const Color(0xFFFFFFFF);

  @override
  Color get gradientEnd => const Color(0xFFF0F0F5);

  @override
  Color get glassCard => const Color(0xFFFFFFFF); // 白天模式卡片纯白背景

  @override
  Color get glassBorder => const Color(0xFFE0E0E8); // 白天模式边框浅灰色

  @override
  Color get glassHighlight => const Color(0xFFF5F5F7); // 白天模式高亮浅灰

  @override
  Color get surface => const Color(0xFFFFFFFF);

  @override
  Color get surfaceElevated => const Color(0xFFFAFAFA);

  @override
  Color get surfaceVariant => const Color(0xFFF0F0F5);

  @override
  Color get primary => const Color(0xFF6C63FF);

  @override
  Color get primaryLight => const Color(0xFF8B85FF);

  @override
  Color get primaryDark => const Color(0xFF5249E6);

  @override
  Color get primaryContainer => const Color(0x196C63FF);

  @override
  Color get accent => const Color(0xFF8B5CF6);

  @override
  Color get gradientPurple => const Color(0xFF9333EA);

  @override
  Color get gradientPink => const Color(0xFFEC4899);

  @override
  Color get up => const Color(0xFFE53935); // 更深的红色，在白底上更清晰

  @override
  Color get upLight => const Color(0xFFFF5252);

  @override
  Color get down => const Color(0xFF00897B); // 更深的绿色，在白底上更清晰

  @override
  Color get downLight => const Color(0xFF26A69A);

  @override
  Color get neutral => const Color(0xFFFF9800);

  @override
  Color get textPrimary => const Color(0xFF1A1A2E);

  @override
  Color get textSecondary => const Color(0xFF4A4A68);

  @override
  Color get textHint => const Color(0xFF9E9EB4);

  @override
  Color get textDisabled => const Color(0xFFBDBDC6);

  @override
  Color get border => const Color(0xFFE0E0E8);

  @override
  Color get divider => const Color(0xFFF0F0F5);

  @override
  Color get borderGlow => const Color(0x266C63FF);

  @override
  Color get success => const Color(0xFF00897B);

  @override
  Color get warning => const Color(0xFFFF9800);

  @override
  Color get error => const Color(0xFFE53935);

  @override
  Color get info => const Color(0xFF6C63FF);

  @override
  Color get shadowPurple => const Color(0x1A6C63FF);

  @override
  Color get shadowDark => const Color(0x14000000);

  @override
  List<Color> get primaryGradient => [primary, accent];

  @override
  List<Color> get backgroundGradient => [gradientStart, gradientEnd];

  @override
  List<Color> get upGradient => [up, const Color(0xFFFF5252)];

  @override
  List<Color> get downGradient => [down, const Color(0xFF26A69A)];

  @override
  List<Color> get buyGradient => [const Color(0xFFE53935), const Color(0xFFFF5722)];

  @override
  List<Color> get sellGradient => [const Color(0xFF00897B), const Color(0xFF00A890)];

  @override
  Color get expertEntryStart => const Color(0xFFEDE7F6);

  @override
  Color get expertEntryEnd => const Color(0xFFF3E5F5);

  @override
  Color get portfolioEntryStart => const Color(0xFFFFF8EC);

  @override
  Color get portfolioEntryEnd => const Color(0xFFFFF1D8);

  @override
  Color get priceHeaderStart => const Color(0xFFF5F0FA);

  @override
  Color get priceHeaderEnd => const Color(0xFFEDE7F6);

  @override
  Color get riskCardBg => const Color(0xFFFFF8E1);

  @override
  Color get hotInvestCardStart => const Color(0xFFFFF8E1);

  @override
  Color get hotInvestCardEnd => const Color(0xFFFFECB3);

  @override
  Color get hotInvestAccent => const Color(0xFFE65100);

  @override
  Color get hotInvestLight => const Color(0xFFE65100);

  @override
  List<Color> get hotInvestGradient => [const Color(0xFFFFA726), const Color(0xFFE65100)];

  // ── 轻量投资（青色系）──
  @override
  Color get liteInvestCardStart => const Color(0xFFE0F2F1);

  @override
  Color get liteInvestCardEnd => const Color(0xFFB2DFDB);

  @override
  Color get liteInvestAccent => const Color(0xFF00796B);

  @override
  Color get liteInvestLight => const Color(0xFF00796B);

  @override
  List<Color> get liteInvestGradient => [const Color(0xFF26A69A), const Color(0xFF00796B)];

  @override
  Color get speedInvestCardStart => const Color(0xFFE8F0FE);
  @override
  Color get speedInvestCardEnd => const Color(0xFFD0E2FD);
  @override
  Color get speedInvestAccent => const Color(0xFF2563EB);
  @override
  List<Color> get speedInvestGradient => [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)];

  @override
  Color getScoreColor(double score) {
    if (score >= 0.7) return up;
    if (score >= 0.5) return neutral;
    return down;
  }

  @override
  Color getPriceColor(double changePct) => changePct >= 0 ? up : down;

  @override
  Color getActionColor(String action) {
    switch (action) {
      case 'buy': return up;
      case 'avoid': return down;
      case 'hold': return neutral;
      default: return textSecondary;
    }
  }

  @override
  Color getTrendColor(String trend) {
    switch (trend) {
      case 'bullish': return up;
      case 'bearish': return down;
      case 'neutral': return neutral;
      default: return textSecondary;
    }
  }
}

/// 便捷访问类 - 保持向后兼容
class AppColors {
  AppColors._();

  // 默认使用深色主题的静态属性（向后兼容）
  static const background = Color(0xFF06060F);
  static const backgroundSecondary = Color(0xFF0A0A18);
  static const gradientStart = Color(0xFF08081A);
  static const gradientEnd = Color(0xFF101028);
  static const glassCard = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const glassHighlight = Color(0x0DFFFFFF);
  static const surface = Color(0xFF1C1C3E);
  static const surfaceElevated = Color(0xFF24244E);
  static const surfaceVariant = Color(0xFF2E2E56);
  static const primary = Color(0xFF6C63FF);
  static const primaryLight = Color(0xFF8B85FF);
  static const primaryDark = Color(0xFF5249E6);
  static const primaryContainer = Color(0x266C63FF);
  static const accent = Color(0xFFA855F7);
  static const gradientPurple = Color(0xFF9333EA);
  static const gradientPink = Color(0xFFEC4899);
  static const up = Color(0xFFFF6B6B);
  static const upLight = Color(0xFFFF8A8A);
  static const down = Color(0xFF4ECDC4);
  static const downLight = Color(0xFF7EDDD6);
  static const neutral = Color(0xFFFFB347);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB4B4D0);
  static const textHint = Color(0xFF6B6B8D);
  static const textDisabled = Color(0xFF3D3D5C);
  static const border = Color(0xFF33335A);
  static const divider = Color(0xFF26264A);
  static const borderGlow = Color(0x406C63FF);
  static const success = Color(0xFF4ECDC4);
  static const warning = Color(0xFFFFB347);
  static const error = Color(0xFFFF6B6B);
  static const info = Color(0xFF6C63FF);
  static const shadowPurple = Color(0x336C63FF);
  static const shadowDark = Color(0x4D000000);
  static const primaryGradient = [primary, accent];
  static const backgroundGradient = [gradientStart, gradientEnd];
  static const upGradient = [up, Color(0xFFFF8E8E)];
  static const downGradient = [down, Color(0xFF6FD9D0)];
  static const buyGradient = [Color(0xFFFF6B6B), Color(0xFFFF8E53)];
  static const sellGradient = [Color(0xFF4ECDC4), Color(0xFF44A08D)];
  static const hotInvestGradient = [Color(0xFFFFA726), Color(0xFFFF8F00)];
  static const liteInvestGradient = [Color(0xFF26A69A), Color(0xFF00897B)];

  /// 获取当前主题的颜色方案
  static AppColorScheme of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? AppColorsDark()
        : AppColorsLight();
  }

  /// 根据评分获取颜色
  static Color getScoreColor(double score) {
    if (score >= 0.7) return up;
    if (score >= 0.5) return neutral;
    return down;
  }

  /// 价格涨跌颜色
  static Color getPriceColor(double changePct) {
    return changePct >= 0 ? up : down;
  }

  /// 行动建议颜色
  static Color getActionColor(String action) {
    switch (action) {
      case 'buy': return up;
      case 'avoid': return down;
      case 'hold': return neutral;
      default: return textSecondary;
    }
  }

  /// 趋势颜色
  static Color getTrendColor(String trend) {
    switch (trend) {
      case 'bullish': return up;
      case 'bearish': return down;
      case 'neutral': return neutral;
      default: return textSecondary;
    }
  }
}
