/// 市场指数像素滚动栏
/// 
/// 专业交易终端风格，像素字体
/// 平滑向上滚动动画，每3秒滚动一行
/// 共8行：A股×2 + 港股×2 + 美股×2 + 期货外汇×2
/// 涨=红色(#FF3B30)，跌=绿色(#34C759)

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_data_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class MarketIndexScrollWidget extends StatefulWidget {
  const MarketIndexScrollWidget({Key? key}) : super(key: key);

  @override
  State<MarketIndexScrollWidget> createState() => _MarketIndexScrollWidgetState();
}

class _MarketIndexScrollWidgetState extends State<MarketIndexScrollWidget>
    with TickerProviderStateMixin {
  final LocalDataService _api = LocalDataService();
  List<Map<String, dynamic>> _pairs = [];
  bool _loading = true;

  int _currentIndex = 0;
  late AnimationController _animController;
  late Animation<double> _slideAnim;

  Timer? _scrollTimer;
  Timer? _refreshTimer;

  // 缓存当前和下一帧数据
  String _curLeftName = '';
  double _curLeftPct = 0;
  String _curRightName = '';
  double _curRightPct = 0;
  String _nextLeftName = '';
  double _nextLeftPct = 0;
  String _nextRightName = '';
  double _nextRightPct = 0;
  bool _animating = false;

  static const _itemHeight = 46.0;
  static const _scrollInterval = Duration(seconds: 3);
  static const _refreshInterval = Duration(seconds: 30);
  static const _animDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: _animDuration,
      vsync: this,
    );
    _slideAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animating = false;
        setState(() {
          _curLeftName = _nextLeftName;
          _curLeftPct = _nextLeftPct;
          _curRightName = _nextRightName;
          _curRightPct = _nextRightPct;
        });
        _animController.reset();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _refreshTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await _api.fetchMarketIndexPairs();
      if (mounted) {
        setState(() {
          _pairs = data;
          _loading = false;
        });
        if (_pairs.isNotEmpty && _curLeftName.isEmpty) {
          final pair = _pairs[0];
          _curLeftName = pair['leftName'] ?? '';
          _curLeftPct = (pair['leftChangePct'] ?? 0.0).toDouble();
          _curRightName = pair['rightName'] ?? '';
          _curRightPct = (pair['rightChangePct'] ?? 0.0).toDouble();
        }
        if (_scrollTimer == null) {
          _startAutoScroll();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoScroll() {
    _scrollTimer = Timer.periodic(_scrollInterval, (_) => _scrollToNext());
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _loadData());
  }

  void _scrollToNext() {
    if (_pairs.isEmpty || !mounted || _animating) return;

    final nextIndex = (_currentIndex + 1) % _pairs.length;
    final pair = _pairs[nextIndex];

    _nextLeftName = pair['leftName'] ?? '';
    _nextLeftPct = (pair['leftChangePct'] ?? 0.0).toDouble();
    _nextRightName = pair['rightName'] ?? '';
    _nextRightPct = (pair['rightChangePct'] ?? 0.0).toDouble();

    _currentIndex = nextIndex;
    _animating = true;
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_loading && _pairs.isEmpty) {
      return _buildSkeleton(colors);
    }
    if (_pairs.isEmpty) {
      return const SizedBox(height: _itemHeight);
    }

    return Container(
      height: _itemHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            // 动画层
            AnimatedBuilder(
              animation: _slideAnim,
              builder: (context, _) {
                final progress = _slideAnim.value;
                // 当前行向上移出，下一行从下方移入
                final curOffset = -_itemHeight * progress;
                final nextOffset = _itemHeight * (1 - progress);

                return Stack(
                  children: [
                    // 当前行（向上滑出）
                    if (progress < 1.0)
                      Transform.translate(
                        offset: Offset(0, curOffset),
                        child: _buildRow(_curLeftName, _curLeftPct, _curRightName, _curRightPct),
                      ),
                      // 下一行（从下方滑入）
                      if (progress > 0.0)
                        Transform.translate(
                          offset: Offset(0, nextOffset),
                          child: _buildRow(_nextLeftName, _nextLeftPct, _nextRightName, _nextRightPct),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String leftName, double leftPct, String rightName, double rightPct) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: _buildIndexDisplay(leftName, leftPct, isDark),
        ),
        Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                (isDark ? const Color(0xFF2C2C3A) : const Color(0xFFE8E8EC)).withOpacity(0),
                isDark ? const Color(0xFF2C2C3A) : const Color(0xFFE8E8EC),
                (isDark ? const Color(0xFF2C2C3A) : const Color(0xFFE8E8EC)).withOpacity(0),
              ],
            ),
          ),
        ),
        Expanded(
          child: _buildIndexDisplay(rightName, rightPct, isDark),
        ),
      ],
    );
  }

  Widget _buildIndexDisplay(String name, double changePct, bool isDark) {
    final isUp = changePct > 0;
    final isDown = changePct < 0;
    final color = isUp
        ? const Color(0xFFFF3B30)
        : (isDown
            ? const Color(0xFF34C759)
            : (isDark ? const Color(0xFF8E8E93) : const Color(0xFF999999)));
    final sign = isUp ? '+' : '';
    final pctStr = '$sign${changePct.toStringAsFixed(2)}%';

    const fontSize = 17.0;

    return Container(
      height: _itemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 名称：用FittedBox确保完整显示，空间不足时自动缩小
          Flexible(
            flex: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                name,
                style: TextStyle(
                  color: isDark ? const Color(0xFFB0B0B8) : const Color(0xFF666666),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  letterSpacing: 0.3,
                  height: 1.1,
                ),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 涨跌幅：固定宽度，确保对齐
          Text(
            pctStr,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 0.3,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(AppColorScheme colors) {
    return Container(
      height: _itemHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );
  }
}
