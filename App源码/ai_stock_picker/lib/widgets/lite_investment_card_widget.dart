/// 首页轻量投资入口卡片
///
/// 主题色：青色系（#26A69A / Teal），与热点投资的橙黄色区分
/// 设计风格与 HotInvestmentCardWidget 一致，仅替换配色和文案

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/lite_investment_service.dart';

class LiteInvestmentCardWidget extends StatefulWidget {
  final LiteInvestmentService service;
  final VoidCallback onTap;

  const LiteInvestmentCardWidget({
    Key? key,
    required this.service,
    required this.onTap,
  }) : super(key: key);

  @override
  State<LiteInvestmentCardWidget> createState() => _LiteInvestmentCardWidgetState();
}

class _LiteInvestmentCardWidgetState extends State<LiteInvestmentCardWidget> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.liteInvestCardStart, colors.liteInvestCardEnd]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.liteInvestAccent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: colors.liteInvestAccent.withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(children: [
          // 左侧：青色渐变圆角方块图标
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.liteInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [
                BoxShadow(
                  color: colors.liteInvestAccent.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          // 中间：标题
          Expanded(
            child: Text('轻量投资',
              style: AppText.h2.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              )),
          ),
          // 右侧：青色渐变胶囊箭头按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.liteInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ),
        ]),
      ),
    );
  }
}
