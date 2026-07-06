/// 投资组合二级菜单
///
/// 展示三大投资模块入口：热点投资 / 轻量投资 / 极速投资
/// 直接复用首页原始卡片组件，保留各自发光色调

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/hot_investment_service.dart';
import '../services/lite_investment_service.dart';
import '../services/speed_investment_service.dart';
import 'hot_investment_list_screen.dart';
import 'lite_investment_list_screen.dart';
import 'speed_investment_list_screen.dart';

class PortfolioMenuScreen extends StatefulWidget {
  final HotInvestmentService hotService;
  final LiteInvestmentService liteService;
  final SpeedInvestmentService speedService;

  const PortfolioMenuScreen({
    Key? key,
    required this.hotService,
    required this.liteService,
    required this.speedService,
  }) : super(key: key);

  @override
  State<PortfolioMenuScreen> createState() => _PortfolioMenuScreenState();
}

class _PortfolioMenuScreenState extends State<PortfolioMenuScreen> {
  @override
  void initState() {
    super.initState();
    widget.speedService.init();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('投资组合', style: AppText.h2.copyWith(
            color: colors.textPrimary, fontWeight: FontWeight.w800)),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 副标题
            Text('选择投资模块', style: AppText.body1.copyWith(color: colors.textSecondary)),
            const SizedBox(height: AppSpacing.xl),

            // === 热点投资（原始发光卡片） ===
            _buildOriginalCard(
              icon: Icons.whatshot,
              title: '热点投资',
              gradient: colors.hotInvestGradient,
              cardStart: colors.hotInvestCardStart,
              cardEnd: colors.hotInvestCardEnd,
              accent: colors.hotInvestAccent,
              onTap: () {
                Navigator.push(context, _slideRoute(
                  HotInvestmentListScreen(service: widget.hotService),
                ));
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // === 轻量投资（原始发光卡片） ===
            _buildOriginalCard(
              icon: Icons.analytics_outlined,
              title: '轻量投资',
              gradient: colors.liteInvestGradient,
              cardStart: colors.liteInvestCardStart,
              cardEnd: colors.liteInvestCardEnd,
              accent: colors.liteInvestAccent,
              onTap: () {
                Navigator.push(context, _slideRoute(
                  LiteInvestmentListScreen(service: widget.liteService),
                ));
              },
            ),
            const SizedBox(height: AppSpacing.lg),

            // === 极速投资（原始发光卡片） ===
            _buildOriginalCard(
              icon: Icons.speed,
              title: '极速投资',
              gradient: colors.speedInvestGradient,
              cardStart: colors.speedInvestCardStart,
              cardEnd: colors.speedInvestCardEnd,
              accent: colors.speedInvestAccent,
              onTap: () {
                Navigator.push(context, _slideRoute(
                  SpeedInvestmentListScreen(service: widget.speedService),
                ));
              },
            ),
          ]),
        ),
      ),
    );
  }

  /// 发光卡片（精简版：仅标题+箭头，无副标题）
  Widget _buildOriginalCard({
    required IconData icon,
    required String title,
    required List<Color> gradient,
    required Color cardStart,
    required Color cardEnd,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cardStart, cardEnd]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: accent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.4),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(title, style: AppText.h2.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
          ),
        ]),
      ),
    );
  }

  PageRouteBuilder _slideRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
