/// 空状态组件 - 统一的空数据显示
///
/// 提供：
/// - 标准空状态视图
/// - 无数据提示
/// - 无搜索结果提示

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 空状态视图
class EmptyView extends StatelessWidget {
  final String? message;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;

  const EmptyView({
    Key? key,
    this.message,
    this.subtitle,
    this.icon,
    this.action,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 48,
              color: colors.textHint,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message ?? '暂无数据',
              style: AppText.body1.copyWith(color: colors.textSecondary),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  subtitle!,
                  style: AppText.caption.copyWith(color: colors.textHint),
                ),
              ),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                child: action!,
              ),
          ],
        ),
      ),
    );
  }
}

/// 无搜索结果
class NoSearchResultView extends StatelessWidget {
  final String? keyword;
  final VoidCallback? onClear;

  const NoSearchResultView({
    Key? key,
    this.keyword,
    this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.search_off_outlined,
      message: keyword != null
          ? '未找到"$keyword"相关股票'
          : '未找到相关股票',
      subtitle: '请尝试其他关键词',
      action: onClear != null
          ? TextButton(
              onPressed: onClear,
              child: const Text('清除搜索'),
            )
          : null,
    );
  }
}

/// 无数据视图（用于列表）
class NoDataView extends StatelessWidget {
  final String? message;
  final VoidCallback? onRefresh;

  const NoDataView({
    Key? key,
    this.message,
    this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      message: message ?? '暂无数据',
      action: onRefresh != null
          ? ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            )
          : null,
    );
  }
}