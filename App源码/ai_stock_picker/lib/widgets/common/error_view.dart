/// 错误状态组件 - 统一的错误显示
///
/// 提供：
/// - 标准错误视图
/// - 网络错误提示
/// - 可重试错误视图

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 错误视图
class ErrorView extends StatelessWidget {
  final String? message;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onRetry;
  final Widget? customAction;

  const ErrorView({
    Key? key,
    this.message,
    this.subtitle,
    this.icon,
    this.onRetry,
    this.customAction,
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
              icon ?? Icons.error_outline,
              size: 48,
              color: colors.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message ?? '出错了',
              style: AppText.body1.copyWith(color: colors.textPrimary),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  subtitle!,
                  style: AppText.caption.copyWith(color: colors.textHint),
                ),
              ),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
              ),
            if (customAction != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                child: customAction!,
              ),
          ],
        ),
      ),
    );
  }
}

/// 网络错误视图
class NetworkErrorView extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorView({
    Key? key,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ErrorView(
      icon: Icons.wifi_off_outlined,
      message: '网络连接失败',
      subtitle: '请检查网络设置后重试',
      onRetry: onRetry,
    );
  }
}

/// API错误视图
class ApiErrorView extends StatelessWidget {
  final String? errorMsg;
  final VoidCallback? onRetry;

  const ApiErrorView({
    Key? key,
    this.errorMsg,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ErrorView(
      message: '数据加载失败',
      subtitle: errorMsg,
      onRetry: onRetry,
    );
  }
}

/// 内联错误提示（用于表单验证等）
class InlineError extends StatelessWidget {
  final String message;

  const InlineError({
    Key? key,
    required this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppText.caption.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }
}