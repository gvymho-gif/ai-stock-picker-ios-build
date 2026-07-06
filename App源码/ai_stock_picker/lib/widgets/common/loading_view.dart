/// 加载视图组件 - 统一的加载状态显示
///
/// 提供：
/// - 标准加载指示器
/// - 带文字加载提示
/// - 全屏加载遮罩

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 标准加载指示器
class LoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const LoadingIndicator({
    Key? key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.5,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation(color ?? colors.primary),
      ),
    );
  }
}

/// 带文字的加载视图
class LoadingView extends StatelessWidget {
  final String? message;
  final double spacing;

  const LoadingView({
    Key? key,
    this.message,
    this.spacing = AppSpacing.lg,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const LoadingIndicator(size: 32),
        if (message != null)
          Padding(
            padding: EdgeInsets.only(top: spacing),
            child: Text(
              message!,
              style: AppText.body2.copyWith(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// 全屏加载遮罩
class FullScreenLoading extends StatelessWidget {
  final String? message;
  final bool showBackground;

  const FullScreenLoading({
    Key? key,
    this.message,
    this.showBackground = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: showBackground ? colors.background.withOpacity(0.9) : null,
      child: Center(
        child: LoadingView(message: message),
      ),
    );
  }
}

/// 内联加载（用于列表项加载）
class InlineLoading extends StatelessWidget {
  final String? message;

  const InlineLoading({
    Key? key,
    this.message = '加载中...',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 16),
            const SizedBox(width: AppSpacing.sm),
            Text(
              message!,
              style: AppText.body2.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}