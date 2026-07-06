/// 横屏左侧指数滚动面板
/// 使用ScrollController + ListView.builder实现流畅滚动
/// 数据循环播放，到尾部无缝接回头部
/// 支持手动触摸滚动：按下暂停、松手后1.5秒恢复自动滚动

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/local_data_service.dart';
import '../theme/app_colors.dart';

class LandscapeIndexPanel extends StatefulWidget {
  const LandscapeIndexPanel({Key? key}) : super(key: key);

  @override
  State<LandscapeIndexPanel> createState() => _LandscapeIndexPanelState();
}

class _LandscapeIndexPanelState extends State<LandscapeIndexPanel> with TickerProviderStateMixin {
  final LocalDataService _api = LocalDataService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  Timer? _refreshTimer;
  Timer? _resumeTimer;

  // 用户是否正在触摸屏幕（手指按下）
  bool _isTouching = false;

  // 箭头拖尾动画
  late final Ticker _arrowTicker;
  final ValueNotifier<double> _arrowPhase = ValueNotifier(0.0);
  static const _arrowCycleMs = 2400.0;

  static const _baseRowHeight = 42.0;
  static const _baseFontSize = 17.0;
  static const _scale = 0.78;
  double _fs(double v) => v * _scale;

  static const _scrollStep = 0.384;

  // 松手后恢复自动滚动的延迟
  static const _autoScrollResumeDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _arrowTicker = createTicker((_) {
      _arrowPhase.value = (DateTime.now().millisecondsSinceEpoch % _arrowCycleMs.toInt()) / _arrowCycleMs;
    })..start();
    _loadData();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _refreshTimer?.cancel();
    _resumeTimer?.cancel();
    _arrowTicker.dispose();
    _arrowPhase.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final pairs = await _api.fetchMarketIndexPairs();
      final flattened = <Map<String, dynamic>>[];
      for (final pair in pairs) {
        final leftName = pair['leftName'] ?? '';
        final leftPct = (pair['leftChangePct'] ?? 0.0).toDouble();
        final rightName = pair['rightName'] ?? '';
        final rightPct = (pair['rightChangePct'] ?? 0.0).toDouble();
        if (leftName.isNotEmpty) flattened.add({'name': leftName, 'changePct': leftPct});
        if (rightName.isNotEmpty) flattened.add({'name': rightName, 'changePct': rightPct});
      }
      if (mounted) {
        setState(() { _items = flattened; _loading = false; });
        if (_refreshTimer == null && _items.isNotEmpty) {
          _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
          _startAutoScroll();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isMarketTrading(String indexName) {
    final now = DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) return false;
    final min = now.hour * 60 + now.minute;

    if (indexName.contains('上证') || indexName.contains('深证') ||
        indexName.contains('创业板') || indexName.contains('科创') ||
        indexName.contains('北证') || indexName.contains('沪深') ||
        indexName.contains('中证')) {
      return (min >= 570 && min < 690) || (min >= 780 && min < 900);
    }

    if (indexName.contains('恒生') || indexName.contains('红筹') ||
        indexName.contains('国企') && !indexName.contains('中国')) {
      return (min >= 570 && min < 720) || (min >= 780 && min < 960);
    }

    if (indexName.contains('纳斯达克') || indexName.contains('标普') ||
        indexName.contains('道琼斯') || indexName.contains('费城')) {
      return min >= 1290 || min < 300;
    }

    if (indexName.contains('日经') || indexName.contains('日本')) {
      return min >= 480 && min < 840;
    }

    if (indexName.contains('韩国') || indexName.contains('KOSPI')) {
      return min >= 480 && min < 870;
    }

    return true;
  }

  // ===================== 自动滚动 =====================

  void _startAutoScroll() {
    if (_items.isEmpty) return;
    _stopAutoScroll();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients || _isTouching) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      double current = _scrollController.offset + _scrollStep;
      final oneCycle = _items.length * _baseRowHeight * _scale;
      if (current >= oneCycle * 2) {
        current -= oneCycle;
        _scrollController.jumpTo(current);
      } else {
        _scrollController.jumpTo(current);
      }
    });
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  // ===================== 触摸交互 =====================

  /// 手指按下 → 暂停自动滚动
  void _onPointerDown(PointerDownEvent _) {
    _resumeTimer?.cancel();
    _isTouching = true;
    _stopAutoScroll();
  }

  /// 手指松开 → 延迟恢复自动滚动
  void _onPointerUp(PointerUpEvent _) {
    _isTouching = false;
    _scheduleResume();
  }

  /// 手指取消（被系统打断等）→ 也走恢复流程
  void _onPointerCancel(PointerCancelEvent _) {
    _isTouching = false;
    _scheduleResume();
  }

  /// 延迟恢复自动滚动
  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_autoScrollResumeDelay, () {
      if (!mounted) return;
      _startAutoScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading && _items.isEmpty) {
      return Container(
        color: colors.surface,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_items.isEmpty) return const SizedBox();

    final cycleItems = [..._items, ..._items, ..._items];
    final rowHeight = _baseRowHeight * _scale;

    // 初始滚动到1倍位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.offset < _items.length * rowHeight) {
        _scrollController.jumpTo(_items.length * rowHeight);
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        // 无边框设计：移除硬边框，用底色自然区分
      ),
      // Listener 监听原始指针事件，不影响 ListView 的滚动手势
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: ListView.builder(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          itemCount: cycleItems.length,
          itemExtent: rowHeight,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            final item = cycleItems[index % _items.length];
            return _buildRow(
              item['name'] as String,
              (item['changePct'] as double),
              colors, isDark,
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(String name, double changePct, AppColorScheme colors, bool isDark) {
    final rowHeight = _baseRowHeight * _scale;
    final isUp = changePct > 0.005;
    final isDown = changePct < -0.005;
    final color = isUp
        ? const Color(0xFFFF3B30)
        : (isDown ? const Color(0xFF34C759) : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF999999)));
    final sign = isUp ? '+' : '';
    final pctStr = '$sign${changePct.toStringAsFixed(2)}%';
    final fontSize = _fs(_baseFontSize);
    final arrow = isUp ? '▲' : (isDown ? '▼' : '');

    final arrowFontSize = fontSize * 0.70;
    final nameFontSize = fontSize * 0.81;
    final pctFontSize = fontSize * 0.74;

    return Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      // 无边框设计：移除底部分隔线，用自然排列区分行
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(name,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFB0B0B8) : const Color(0xFF666666),
                    fontSize: nameFontSize,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    letterSpacing: 0.3,
                    height: 1.1,
                  ),
                  maxLines: 1),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(pctStr,
                    style: TextStyle(
                      color: color,
                      fontSize: pctFontSize,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      letterSpacing: 0.3,
                      height: 1.1,
                    )),
              ),
              if (arrow.isNotEmpty) ...[
                const SizedBox(width: 1),
                if (_isMarketTrading(name))
                  CustomPaint(
                    size: Size(arrowFontSize * 1.4, rowHeight),
                    painter: _TrailArrowPainter(
                      animation: _arrowPhase,
                      arrow: arrow,
                      color: color,
                      fontSize: arrowFontSize,
                      percentFontSize: pctFontSize,
                      isUp: isUp,
                    ),
                  )
                else
                  Text(arrow, style: TextStyle(
                    color: color,
                    fontSize: arrowFontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  )),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 呼吸淡入淡出箭头：固定位置，透明度在 80%~100% 之间柔和波动
class _TrailArrowPainter extends CustomPainter {
  final ValueNotifier<double> animation;
  final String arrow;
  final Color color;
  final double fontSize;
  final double percentFontSize;
  final bool isUp;
  final double baseYOffset;

  _TrailArrowPainter({
    required this.animation,
    required this.arrow,
    required this.color,
    required this.fontSize,
    required this.percentFontSize,
    required this.isUp,
    this.baseYOffset = 0.0,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final v = animation.value;
    final textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

    final measureTP = TextPainter(text: TextSpan(text: arrow, style: textStyle), textDirection: TextDirection.ltr)..layout();
    final th = measureTP.height;
    final pctH = percentFontSize * 1.1;
    final rawBaseY = isUp
        ? (size.height + pctH) / 2 - th
        : (size.height - pctH) / 2;
    final baseY = rawBaseY + baseYOffset;

    final breath = math.sin(v * 2 * math.pi);
    final alpha = 0.70 + breath * 0.30;

    _paintArrow(canvas, size, textStyle, baseY, alpha);
  }

  void _paintArrow(Canvas canvas, Size size, TextStyle style, double y, double alpha) {
    final span = TextSpan(text: arrow, style: style.copyWith(color: color.withOpacity(alpha)));
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
  }

  @override
  bool shouldRepaint(_TrailArrowPainter old) {
    return old.arrow != arrow || old.color != color || old.fontSize != fontSize
        || old.percentFontSize != percentFontSize || old.isUp != isUp
        || old.baseYOffset != baseYOffset;
  }
}
