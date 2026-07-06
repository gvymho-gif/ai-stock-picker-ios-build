/// 首页极速投资入口卡片
///
/// 蓝色系（#3B82F6），参考轻量投资卡片风格

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/speed_investment_service.dart';

class SpeedInvestmentCardWidget extends StatefulWidget {
  final SpeedInvestmentService service;
  final VoidCallback onTap;

  const SpeedInvestmentCardWidget({
    Key? key,
    required this.service,
    required this.onTap,
  }) : super(key: key);

  @override
  State<SpeedInvestmentCardWidget> createState() => _SpeedInvestmentCardWidgetState();
}

class _SpeedInvestmentCardWidgetState extends State<SpeedInvestmentCardWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.speedInvestCardStart, colors.speedInvestCardEnd]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.speedInvestAccent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: colors.speedInvestAccent.withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.speedInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [
                BoxShadow(
                  color: colors.speedInvestAccent.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.speed, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text('极速投资',
              style: AppText.h2.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.speedInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ),
        ]),
      ),
    );
  }
}
