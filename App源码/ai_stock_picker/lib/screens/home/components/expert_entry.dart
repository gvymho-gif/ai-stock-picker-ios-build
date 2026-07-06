/// 专家选股入口组件
///
/// Material Design 3 风格卡片

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class ExpertEntryWidget extends StatelessWidget {
  final VoidCallback onTap;

  const ExpertEntryWidget({
    Key? key,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1A1F36),
              Color(0xFF252D4A),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            // 图标
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.primary,
                    Color(0xFF7C3AED),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // 标题和描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '专家选股',
                    style: AppText.h3.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '五大策略 · 短炒猎手 · 成长先锋 · 稳健堡垒 · A股游资 · 隔夜导航',
                    style: AppText.hint.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
            ),

            // 箭头
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.primary,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
