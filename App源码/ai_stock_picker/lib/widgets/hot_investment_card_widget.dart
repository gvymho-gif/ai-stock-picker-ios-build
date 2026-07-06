/// 首页热点投资入口卡片
///
/// 完全参照「专家选股」卡片的设计规范：
/// 主题色渐变底 + 主题色图标（带按钮阴影） + 发光边框 + Glow阴影
/// 仅将紫色系替换为橙黄色系（#FFA726）作为功能区分色
/// 精简版：仅标题 + 箭头，无计数徽章和副标题

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/hot_investment_service.dart';

class HotInvestmentCardWidget extends StatefulWidget {
  final HotInvestmentService service;
  final VoidCallback onTap;

  const HotInvestmentCardWidget({
    Key? key,
    required this.service,
    required this.onTap,
  }) : super(key: key);

  @override
  State<HotInvestmentCardWidget> createState() => _HotInvestmentCardWidgetState();
}

class _HotInvestmentCardWidgetState extends State<HotInvestmentCardWidget> {
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
          gradient: LinearGradient(colors: [colors.hotInvestCardStart, colors.hotInvestCardEnd]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.hotInvestAccent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: colors.hotInvestAccent.withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(children: [
          // 左侧：橙黄渐变圆角方块图标（参照专家选股）
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.hotInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [
                BoxShadow(
                  color: colors.hotInvestAccent.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.whatshot, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          // 中间：标题
          Expanded(
            child: Text('热点投资',
              style: AppText.h2.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              )),
          ),
          // 右侧：橙黄渐变胶囊箭头按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors.hotInvestGradient),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ),
        ]),
      ),
    );
  }
}
