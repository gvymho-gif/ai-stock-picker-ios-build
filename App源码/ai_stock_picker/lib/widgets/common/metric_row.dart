/// 指标行组件 - 统一的指标展示样式
///
/// 提供：
/// - 单个指标展示
/// - 指标网格
/// - 指标列表

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 单个指标项
class MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;

  const MetricItem({
    Key? key,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.icon,
    this.iconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor ?? colors.textHint,
                ),
              ),
            Text(
              label,
              style: AppText.caption.copyWith(color: colors.textHint),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: AppText.h2.copyWith(color: valueColor ?? colors.textPrimary),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              subtitle!,
              style: AppText.hint.copyWith(color: colors.textHint),
            ),
          ),
      ],
    );
  }
}

/// 指标行（横向排列）
class MetricRow extends StatelessWidget {
  final List<MetricItemData> metrics;
  final int crossAxisCount;
  final double spacing;

  const MetricRow({
    Key? key,
    required this.metrics,
    this.crossAxisCount = 4,
    this.spacing = AppSpacing.lg,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: metrics
          .map((m) => Expanded(
                child: MetricItem(
                  label: m.label,
                  value: m.value,
                  valueColor: m.valueColor,
                  subtitle: m.subtitle,
                  icon: m.icon,
                  iconColor: m.iconColor,
                ),
              ))
          .toList()
          .joinWith(SizedBox(width: spacing)),
    );
  }
}

/// 指标网格
class MetricGrid extends StatelessWidget {
  final List<MetricItemData> metrics;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const MetricGrid({
    Key? key,
    required this.metrics,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = AppSpacing.lg,
    this.crossAxisSpacing = AppSpacing.lg,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: 2.5,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final m = metrics[index];
        return MetricItem(
          label: m.label,
          value: m.value,
          valueColor: m.valueColor,
          subtitle: m.subtitle,
          icon: m.icon,
          iconColor: m.iconColor,
        );
      },
    );
  }
}

/// 指标数据类
class MetricItemData {
  final String label;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;

  const MetricItemData({
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.icon,
    this.iconColor,
  });
}

/// 列表扩展方法
extension ListWidgetExtension on List<Widget> {
  List<Widget> joinWith(Widget separator) {
    if (length <= 1) return this;
    return [
      for (int i = 0; i < length; i++) ...[
        if (i > 0) separator,
        this[i],
      ],
    ];
  }
}