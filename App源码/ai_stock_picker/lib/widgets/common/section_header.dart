/// 区块标题组件 - 统一的区块标题样式
///
/// 提供：
/// - 标准区块标题
/// - 带操作按钮的标题
/// - 可展开的区块标题

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 区块标题
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    Key? key,
    required this.title,
    this.trailing,
    this.onTap,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppText.h3.copyWith(color: colors.textPrimary),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// 带箭头的区块标题（可点击跳转）
class LinkSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final String? linkText;
  final bool showArrow;

  const LinkSectionHeader({
    Key? key,
    required this.title,
    required this.onTap,
    this.linkText = '查看全部',
    this.showArrow = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SectionHeader(
      title: title,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            linkText!,
            style: AppText.body2.copyWith(color: colors.primary),
          ),
          if (showArrow)
            Icon(
              Icons.keyboard_arrow_right,
              size: 18,
              color: colors.primary,
            ),
        ],
      ),
    );
  }
}

/// 带图标的区块标题
class IconSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget? trailing;

  const IconSectionHeader({
    Key? key,
    required this.title,
    required this.icon,
    this.iconColor,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      title: title,
      trailing: trailing,
    );
  }
}

/// 分割线标题
class DividerHeader extends StatelessWidget {
  final String title;

  const DividerHeader({
    Key? key,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: colors.divider,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              title,
              style: AppText.caption.copyWith(color: colors.textHint),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: colors.divider,
            ),
          ),
        ],
      ),
    );
  }
}