/// 蓝图极智 · 启动动画 — 菱形 Logo + 跨屏过渡到首页标题
///
/// 三阶段：
/// Phase 1 (0.00-0.70): 菱形绘制 + Logo + 文字展示
/// Phase 2 (0.70-0.85): 整体缩小上移
/// Phase 3 (0.85-1.00): 图案渐隐，触发跨屏过渡
///
/// 跨屏过渡（PageRoute transitionsBuilder）：
/// 首页淡入的同时，一个小菱形图案在 AppBar 标题处浮现 → 微脉 → 消隐
/// 首页标题随后淡入，形成无缝衔接
///
/// 总长 2.5s splash + 0.6s 跨屏过渡

import 'dart:math';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget nextScreen;
  const SplashScreen({Key? key, required this.nextScreen}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _ctrl.addListener(_checkNavigate);
    _ctrl.forward();
  }

  void _checkNavigate() {
    if (!_navigated && _ctrl.value >= 0.96) {
      _navigated = true;
      _doTransition();
    }
  }

  void _doTransition() {
    final size = MediaQuery.of(context).size;
    final padTop = MediaQuery.of(context).padding.top;
    final targetY = padTop + 20;
    final cx = size.width / 2;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionDuration: const Duration(milliseconds: 1350),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return Stack(
            children: [
              // 首页淡入
              FadeTransition(opacity: animation, child: child),
              // 跨屏图案：在标题位置浮现
              _buildCrossScreenPattern(animation, cx, targetY, size),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCrossScreenPattern(
      Animation<double> anim, double cx, double targetY, Size size) {
    final r = min(cx, size.height / 2) * 0.28 * 0.10; // 缩小后尺寸

    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final v = anim.value;
        // 滑入: 0.0~0.35 从下方 160px 平滑滑到标题位置
        final slideProgress = (v / 0.35).clamp(0.0, 1.0);
        final slideCurve = Curves.easeOutCubic.transform(slideProgress);
        final slideOffset = (1 - slideCurve) * 160;
        // 透明度
        final appear = Curves.easeOutQuart.transform(slideProgress);
        final disappear = v > 0.60
            ? 1.0 - ((v - 0.60) / 0.40).clamp(0.0, 1.0)
            : 1.0;
        final opacity = appear * disappear;

        return Positioned(
          left: cx - r / 0.10,
          top: targetY - r / 0.10 + slideOffset,
          child: Opacity(
            opacity: opacity,
            child: SizedBox(
              width: r * 2 / 0.10,
              height: r * 2 / 0.10,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: opacity,
                    child: SizedBox(
                      width: r * 1.5 / 0.10,
                      height: r * 1.5 / 0.10,
                      child: Image.asset(
                        'assets/logo_transparent.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // 菱形光框
                  CustomPaint(
                    size: Size(r * 2 / 0.10, r * 2 / 0.10),
                    painter: _TinyDiamondPainter(opacity),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_checkNavigate);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          if (t <= 0) return const SizedBox.expand();

          final size = MediaQuery.of(context).size;
          final cx = size.width / 2;
          final cy = size.height / 2;
          final diamondR = min(cx, cy) * 0.28;
          final shiftUp = min(cx, cy) * 0.10;

          // Phase timing
          const p1End = 0.70;
          const p2End = 0.85;

          final shrinkRaw =
              ((t - p1End) / (p2End - p1End)).clamp(0.0, 1.0);
          final shrinkT = Curves.easeInOutCubic.transform(shrinkRaw);

          final scale = 1.0 - shrinkT * 0.90;
          final transY = (cy * 0.12) * shrinkT * -1; // 明显上移

          final finalFade = t > p2End
              ? 1.0 - ((t - p2End) / (1.0 - p2End)).clamp(0.0, 1.0)
              : 1.0;

          final appear =
              Curves.easeOutQuart.transform(((t - 0.03) / 0.22).clamp(0.0, 1.0));
          final alpha = appear * finalFade;
          if (alpha <= 0) return const SizedBox.expand();

          final logoFadeIn =
              Curves.easeOutQuart.transform(((t - 0.50) / 0.25).clamp(0.0, 1.0));

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(0.0, transY)
                    ..scale(scale),
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Transform.translate(
                          offset: Offset(0, -shiftUp),
                          child: Opacity(
                            opacity: logoFadeIn * finalFade,
                            child: SizedBox(
                              width: diamondR * 1.35,
                              height: diamondR * 1.35,
                              child: Image.asset(
                                'assets/logo_transparent.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _DiamondPainter(t, alpha, shiftUp: shiftUp),
                      ),
                      _BrandText(t, alpha, logoFadeIn, finalFade),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _BrandText(
      double t, double alpha, double logoFadeIn, double finalFade) {
    final fadeIn =
        Curves.easeOutQuart.transform(((t - 0.53) / 0.27).clamp(0.0, 1.0));
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              height: min(MediaQuery.of(context).size.width,
                      MediaQuery.of(context).size.height) *
                  0.42),
          Opacity(
            opacity: fadeIn * finalFade,
            child: const Text('蓝图极智',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8E6FF),
                    letterSpacing: 8)),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: fadeIn * finalFade,
            child: const Text('AI STOCK PICKER',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0377F8),
                    letterSpacing: 5)),
          ),
        ],
      ),
    );
  }
}

class _Edge {
  final Offset start;
  final Offset end;
  const _Edge(this.start, this.end);
}

// Splash 菱形绘制
class _DiamondPainter extends CustomPainter {
  final double t, alpha, shiftUp;
  _DiamondPainter(this.t, this.alpha, {this.shiftUp = 0});

  static const _accent = Color(0xFFA78BFA);
  static const _glow = Color(0xFF7C65F0);

  @override
  void paint(Canvas canvas, Size size) {
    if (alpha <= 0) return;
    final cx = size.width / 2;
    final cy = size.height / 2 - shiftUp;
    final r = min(cx, cy) * 0.28;
    final dp = Curves.easeInOutQuart.transform(((t - 0.10) / 0.50).clamp(0.0, 1.0));
    final top = Offset(cx, cy - r), right = Offset(cx + r, cy);
    final bottom = Offset(cx, cy + r), left = Offset(cx - r, cy);
    final edges = [_Edge(top, right), _Edge(right, bottom), _Edge(bottom, left), _Edge(left, top)];
    if (dp > 0.01) {
      final ga = alpha * 0.03 * (dp.clamp(0.0, 0.5) * 2);
      final gp = Paint()
        ..shader = RadialGradient(center: Alignment.center, radius: 1.0, colors: [_glow.withOpacity(ga * 0.6), _glow.withOpacity(0)])
            .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(Offset(cx, cy), r * 1.5, gp);
    }
    final fe = (dp * 4).floor().clamp(0, 4);
    final pt = (dp * 4) - fe;
    final path = Path()..moveTo(top.dx, top.dy);
    for (int i = 0; i < fe; i++) path.lineTo(edges[i].end.dx, edges[i].end.dy);
    Offset? tip;
    if (fe < 4 && pt > 0) {
      final e = edges[fe];
      tip = Offset(e.start.dx + (e.end.dx - e.start.dx) * pt, e.start.dy + (e.end.dy - e.start.dy) * pt);
      path.lineTo(tip!.dx, tip.dy);
    }
    canvas.drawPath(path, Paint()..color = _accent.withOpacity(alpha * 0.8)..strokeWidth = 2.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    if (tip != null && dp > 0 && dp < 1.0) {
      final da = alpha * 0.9;
      canvas.drawCircle(tip, 10, Paint()..shader = RadialGradient(center: Alignment.center, radius: 1.0, colors: [_accent.withOpacity(da), _accent.withOpacity(0)]).createShader(Rect.fromCircle(center: tip, radius: 10))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(tip, 2.5, Paint()..color = Colors.white.withOpacity(da));
    }
    if (dp >= 0.99) {
      final br = 1.0 + 0.012 * sin((t - 0.60) * pi * 3.2);
      final ba = alpha * 0.10 * (1.0 - ((t - 0.60) / 0.3).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(cx, cy), r * 1.7 * br, Paint()..shader = RadialGradient(center: Alignment.center, radius: 1.0, colors: [_glow.withOpacity(ba), _glow.withOpacity(0)]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.7 * br))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    }
  }

  @override
  bool shouldRepaint(covariant _DiamondPainter old) => old.t != t || old.alpha != alpha || old.shiftUp != shiftUp;
}

// 跨屏过渡小菱形
class _TinyDiamondPainter extends CustomPainter {
  final double opacity;
  _TinyDiamondPainter(this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.05) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = min(cx, cy) * 0.35;

    final path = Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r, cy)
      ..close();

    final paint = Paint()
      ..color = const Color(0xFFA78BFA).withOpacity(opacity)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    // 辉光
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          const Color(0xFF7C65F0).withOpacity(opacity * 0.4),
          const Color(0xFF7C65F0).withOpacity(0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.8))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(cx, cy), r * 1.8, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _TinyDiamondPainter old) => old.opacity != opacity;
}
