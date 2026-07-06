/// 间距系统 - AI智能选股统一间距定义
///
/// 6级间距体系，确保整体布局节奏一致

import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();

  /// 超小间距 - 4px，用于紧凑元素间
  static const xs = 4.0;

  /// 小间距 - 8px，用于元素内部间距
  static const sm = 8.0;

  /// 中小间距 - 12px，用于小组件间距
  static const md = 12.0;

  /// 标准间距 - 16px，用于标准组件间距
  static const lg = 16.0;

  /// 大间距 - 20px，用于区块间间距
  static const xl = 20.0;

  /// 超大间距 - 24px，用于页面边距
  static const xxl = 24.0;

  /// 页面水平内边距
  static const pageHorizontal = 16.0;

  /// 页面顶部内边距
  static const pageTop = 12.0;

  /// 列表项间距
  static const listItemGap = 8.0;

  /// 卡片内部间距
  static const cardPadding = 16.0;

  /// 区块标题下方间距
  static const sectionGap = 16.0;
}

/// 边距快捷方法
class AppPadding {
  AppPadding._();

  /// 页面标准内边距
  static const page = EdgeInsets.symmetric(horizontal: AppSpacing.pageHorizontal);

  /// 卡片内边距
  static const card = EdgeInsets.all(AppSpacing.cardPadding);

  /// 列表项内边距
  static const listItem = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );
}
