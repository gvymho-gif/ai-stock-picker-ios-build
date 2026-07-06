/// 通用卡片组件 - 统一的卡片样式
///
/// 提供统一的卡片容器，支持：
/// - 标准卡片样式
/// - 可点击卡片
/// - 可展开卡片

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? borderRadius;
  final bool showBorder;
  final Color? borderColor;

  const AppCard({
    Key? key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
    this.showBorder = false,
    this.borderColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final cardColor = backgroundColor ?? colors.surface;
    final radius = borderRadius ?? AppRadius.md;

    Widget card = Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(color: borderColor ?? colors.border, width: 1)
            : null,
      ),
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(radius),
          child: card,
        ),
      );
    }

    return card;
  }
}

/// 可展开卡片
class ExpandableCard extends StatefulWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;
  final Widget content;
  final bool initiallyExpanded;
  final VoidCallback? onExpandChanged;

  const ExpandableCard({
    Key? key,
    required this.title,
    this.leading,
    this.trailing,
    required this.content,
    this.initiallyExpanded = false,
    this.onExpandChanged,
  }) : super(key: key);

  @override
  State<ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<ExpandableCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (widget.leading != null) widget.leading!,
                  if (widget.leading != null)
                    const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppText.h3.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // 内容
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: widget.content,
            ),
        ],
      ),
    );
  }
}

/// 标题卡片 - 带标题的卡片
class TitleCard extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget content;
  final EdgeInsetsGeometry? padding;

  const TitleCard({
    Key? key,
    required this.title,
    this.action,
    required this.content,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppText.h3.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          // 内容
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: content,
          ),
        ],
      ),
    );
  }
}