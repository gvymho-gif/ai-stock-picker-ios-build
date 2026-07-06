/// 字体系统 - 年轻化设计
///
/// 更大胆的字号对比，让层次更分明
/// 标题更醒目，正文适中，标签更精致

import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppText {
  AppText._();

  // ============ 标题样式 - 更大更醒目 ============
  /// H1 - 28px，用于股票名称、大价格数字
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
  );

  /// H2 - 20px，用于页面标题、卡片标题
  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// H3 - 17px，用于区块标题
  static const TextStyle h3 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // ============ 正文样式 ============
  /// Body1 - 16px，用于主要内容
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// Body2 - 14px，用于次要内容
  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // ============ 辅助样式 ============
  /// Caption - 12px，用于标签
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  /// Hint - 11px，用于极小提示
  static const TextStyle hint = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  // ============ 带颜色快捷样式 ============
  static TextStyle get primaryBody => body1.copyWith(color: AppColors.textPrimary);
  static TextStyle get secondaryBody => body2.copyWith(color: AppColors.textSecondary);
  static TextStyle get hintCaption => caption.copyWith(color: AppColors.textHint);

  // ============ 特殊样式 ============
  /// 价格数字样式 - 更大更醒目
  static TextStyle get price => const TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// 涨跌幅样式
  static const TextStyle changePct = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// AI评分样式
  static const TextStyle score = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  /// 按钮文字样式
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  );

  /// 大按钮文字
  static const TextStyle buttonLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// 圆角系统 - 更大更圆润
class AppRadius {
  AppRadius._();

  /// 极小圆角 - 4px
  static const xs = 4.0;

  /// 小圆角 - 8px
  static const sm = 8.0;

  /// 中等圆角 - 14px
  static const md = 14.0;

  /// 大圆角 - 20px
  static const lg = 20.0;

  /// 超大圆角 - 28px
  static const xl = 28.0;

  /// 胶囊/圆形 - 100px
  static const full = 100.0;
}

/// 阴影系统 - 紫色发光效果
class AppShadow {
  AppShadow._();

  /// 卡片阴影 - 带紫色光晕
  static List<BoxShadow> get card => [
    BoxShadow(
      color: AppColors.shadowPurple.withOpacity(0.3),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: AppColors.shadowDark,
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// 悬浮阴影
  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: AppColors.shadowPurple.withOpacity(0.4),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];

  /// 发光效果
  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.4),
      blurRadius: 24,
      spreadRadius: 2,
    ),
  ];

  /// 按钮阴影
  static List<BoxShadow> get button => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.35),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
