/// 标签组件 - 统一的标签样式
///
/// 提供：
/// - 标准标签
/// - 状态标签（买入/卖出/观望）
/// - 可选择标签

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 基础标签
class AppChip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const AppChip({
    Key? key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.fontSize,
    this.padding,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final chip = Container(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                icon,
                size: (fontSize ?? 12) + 2,
                color: textColor ?? colors.textSecondary,
              ),
            ),
          Text(
            label,
            style: AppText.caption.copyWith(
              color: textColor ?? colors.textSecondary,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: chip,
        ),
      );
    }

    return chip;
  }
}

/// 状态标签（买入/卖出/观望）
class ActionChip extends StatelessWidget {
  final String action;
  final bool showIcon;
  final double? fontSize;

  const ActionChip({
    Key? key,
    required this.action,
    this.showIcon = true,
    this.fontSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getActionColor(action);
    final label = _getActionLabel(action);
    final icon = _getActionIcon(action);

    return AppChip(
      label: label,
      backgroundColor: color.withOpacity(0.15),
      textColor: color,
      icon: showIcon ? icon : null,
      fontSize: fontSize,
    );
  }

  String _getActionLabel(String action) {
    switch (action) {
      case 'buy': return '买入';
      case 'avoid': return '回避';
      case 'hold': return '观望';
      default: return action;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'buy': return Icons.trending_up;
      case 'avoid': return Icons.trending_down;
      case 'hold': return Icons.remove;
      default: return Icons.remove;
    }
  }
}

/// 涨跌标签
class ChangeChip extends StatelessWidget {
  final double changePct;
  final double? fontSize;

  const ChangeChip({
    Key? key,
    required this.changePct,
    this.fontSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getPriceColor(changePct);
    final text = '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%';

    return AppChip(
      label: text,
      backgroundColor: color.withOpacity(0.15),
      textColor: color,
      fontSize: fontSize,
    );
  }
}

/// AI评分标签
class ScoreChip extends StatelessWidget {
  final double score;
  final bool showLabel;

  const ScoreChip({
    Key? key,
    required this.score,
    this.showLabel = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getScoreColor(score);
    final label = showLabel ? 'AI ${_formatScore(score)}' : _formatScore(score);

    return AppChip(
      label: label,
      backgroundColor: color.withOpacity(0.15),
      textColor: color,
    );
  }

  String _formatScore(double score) {
    return (score * 100).toStringAsFixed(0);
  }
}

/// 可选择标签
class SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const SelectableChip({
    Key? key,
    required this.label,
    this.selected = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppChip(
      label: label,
      backgroundColor: selected ? colors.primary : colors.surfaceVariant,
      textColor: selected ? Colors.white : colors.textSecondary,
      onTap: onTap,
    );
  }
}