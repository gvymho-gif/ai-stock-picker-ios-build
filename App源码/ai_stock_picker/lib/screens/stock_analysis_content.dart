/// 个股分析内容组件 - 从 HomeScreen 提取
///
/// 用于在 StockAnalysisScreen 中显示分析结果

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/stock_deep_analysis_service.dart';

class StockAnalysisContent extends StatelessWidget {
  final Map<String, dynamic> stockData;
  final VoidCallback? onRefresh;
  final ScrollController? scrollController;

  const StockAnalysisContent({
    Key? key,
    required this.stockData,
    this.onRefresh,
    this.scrollController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isFund = stockData['fund_type'] == 'fund';
    final ai = stockData['ai_analysis'] as Map<String, dynamic>? ?? {};
    final analysis = stockData['analysis'] as Map<String, dynamic>? ?? {};
    final action = ai['action'] ?? 'hold';
    final score = _d(ai['score']);
    final cp = _d(stockData['change_pct']);

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          _buildPriceHeader(stockData, isFund, ai, action, score, cp, context),
          const SizedBox(height: AppSpacing.md),
          _buildAiSummaryCard(ai, score, context),
          const SizedBox(height: AppSpacing.md),
          ..._buildAnalysisModules(analysis, context),
          const SizedBox(height: AppSpacing.sm),
          if (analysis['company_profile'] != null)
            _buildAnalysisCard(analysis['company_profile'] as Map<String, dynamic>, context, 'company_profile'),
          const SizedBox(height: AppSpacing.sm),
          _buildRiskCard(ai, context),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ============ 工具方法 ============

  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _fmtPriceByMarket(dynamic v, String market) {
    if (v == null) return '--';
    final d = _safeDouble(v);
    if (d == 0 && v.toString() != '0') return v.toString();
    if (market == 'HK') return d.toStringAsFixed(3);
    if (market == 'US') return d.toStringAsFixed(2);
    return d.toStringAsFixed(2);
  }

  int _safeInt(v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return 0;
  }

  double _safeDouble(v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return 0.0;
  }

  String _fmtVol(int v) {
    if (v <= 0) return '--';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万手';
    return '$v手';
  }

  String _fmtAmt(double v) {
    if (v <= 0) return '--';
    if (v >= 1e8) return '${(v / 1e8).toStringAsFixed(1)}亿';
    if (v >= 1e4) return '${(v / 1e4).toStringAsFixed(0)}万';
    return v.toStringAsFixed(0);
  }

  // ============ 价格头部 ============

  Widget _buildPriceHeader(
      Map<String, dynamic> r,
      bool isFund,
      Map<String, dynamic> ai,
      String action,
      double score,
      double cp,
      BuildContext context) {
    final colors = AppColors.of(context);
    final pc = getPriceColor(cp);
    final ac = _getActionColor(action, colors);
    final market = r['market']?.toString() ?? '';
    final isHK = market == 'HK';
    final isUS = market == 'US';

    String currencySymbol;
    int pricePrecision;
    if (isFund) {
      currencySymbol = '净值';
      pricePrecision = 4;
    } else if (isHK) {
      currencySymbol = 'HK\$';
      pricePrecision = 3;
    } else if (isUS) {
      currencySymbol = '\$';
      pricePrecision = 2;
    } else {
      currencySymbol = '¥';
      pricePrecision = 2;
    }
    final priceStr = _d(r['price']).toStringAsFixed(pricePrecision);
    final changeAmt = _d(r['change_amt']);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [colors.priceHeaderStart, colors.priceHeaderEnd]),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: pc.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: pc.withOpacity(0.1), blurRadius: 20)],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['name'] ?? '', style: AppText.h1.copyWith(color: colors.textPrimary)),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text(r['symbol'] ?? '', style: AppText.caption.copyWith(color: colors.textHint)),
                        if (market.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [colors.primary.withOpacity(0.2), colors.accent.withOpacity(0.1)]),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(market, style: AppText.hint.copyWith(color: colors.primaryLight, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [ac.withOpacity(0.3), ac.withOpacity(0.1)]),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: ac.withOpacity(0.4)),
                ),
                child: Text(_getActionLabel(action), style: AppText.h3.copyWith(color: ac, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$currencySymbol$priceStr', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: pc, letterSpacing: -1)),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cp >= 0 ? '+' : ''}${cp.toStringAsFixed(2)}%', style: AppText.h2.copyWith(color: pc, fontWeight: FontWeight.w700)),
                    if (changeAmt != 0) Text('${changeAmt >= 0 ? '+' : ''}${changeAmt.toStringAsFixed(isHK || isUS ? 3 : 2)}', style: AppText.caption.copyWith(color: pc)),
                  ],
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('AI评分', style: AppText.hint.copyWith(color: colors.textHint)),
                  Text('${(score * 100).toStringAsFixed(0)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _getScoreColor(score, colors))),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _miniInfo('开盘', _fmtPriceByMarket(r['open'], market), context),
              _miniInfo('最高', _fmtPriceByMarket(r['high'], market), context),
              _miniInfo('最低', _fmtPriceByMarket(r['low'], market), context),
              _miniInfo('昨收', _fmtPriceByMarket(r['prev_close'], market), context),
              if (r['volume'] != null && !isFund) _miniInfo('量', _fmtVol(_safeInt(r['volume'])), context),
              if (r['amount'] != null) _miniInfo('额', _fmtAmt(_safeDouble(r['amount'])), context),
              if (r['market_cap_display'] != null) _miniInfo('市值', r['market_cap_display'].toString(), context),
              if (r['pe_ratio'] != null) _miniInfo('PE', r['pe_ratio'].toString(), context),
              if (r['turn_over_rate'] != null) _miniInfo('换手', '${r['turn_over_rate']}%', context),
              _miniInfo('股息', r['dividend_yield'] != null ? '${r['dividend_yield']}%' : '0%', context),
              // ROE 和 营收增速 - 新增
              if (r['roe'] != null) _miniInfo('ROE', '${_d(r['roe']).toStringAsFixed(1)}%', context),
              if (r['revenue_growth'] != null) _miniInfo('营收增速', '${_d(r['revenue_growth']).toStringAsFixed(1)}%', context),
            ],
          ),
        ],
      ),
    );
  }

  // ============ AI综合评分卡 ============

  Widget _buildAiSummaryCard(Map<String, dynamic> ai, double score, BuildContext context) {
    final colors = AppColors.of(context);
    final detail = ai['detail'] as Map<String, dynamic>? ?? {};
    final reason = ai['reason'] ?? '';
    final wr = _d(ai['short_term_win_rate']);
    final trend = ai['trend'] ?? 'neutral';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.primary.withOpacity(0.2)),
        boxShadow: AppShadow.card,
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('极智分析', style: AppText.h2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _circleIndicator('综合评分', '${(score * 100).toStringAsFixed(0)}', _getScoreColor(score, colors), context),
              _circleIndicator('短线胜率', '${(wr * 100).toStringAsFixed(0)}%', colors.primary, context),
              _circleIndicator('趋势', _getTrendLabel(trend), _getTrendColor(trend, colors), context),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (detail.isNotEmpty) ...[
            _scoreBar('基本面', _d(detail['fundamental_score']), colors),
            const SizedBox(height: AppSpacing.sm),
            _scoreBar('技术面', _d(detail['technical_score']), colors),
            const SizedBox(height: AppSpacing.sm),
            _scoreBar('资金面', _d(detail['capital_score']), colors),
            const SizedBox(height: AppSpacing.sm),
            _scoreBar('动量面', _d(detail['momentum_score']), colors),
            const SizedBox(height: AppSpacing.lg),
          ],
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb, size: 18, color: colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(reason, style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.5))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ 分析模块 ============

  List<Widget> _buildAnalysisModules(Map<String, dynamic> analysis, BuildContext context) {
    const keys = ['price', 'volume', 'volatility', 'trend', 'bid_ask', 'valuation', 'momentum', 'support_resistance', 'capital_flow', 'pre_market', 'ai_detailed'];
    return keys
        .where((k) => analysis[k] != null)
        .map((k) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _buildAnalysisCard(analysis[k] as Map<String, dynamic>, context, k),
            ))
        .toList();
  }

  // ============ 通用分析卡片 ============

  Widget _buildAnalysisCard(Map<String, dynamic> a, BuildContext context, String moduleKey) {
    return _ExpandableAnalysisCard(
      title: a['title'] ?? '',
      icon: _analysisIcon(a['icon'] ?? ''),
      sentiment: a['sentiment'] ?? '',
      score: _d(a['score']),
      items: (a['items'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, v.toString())),
      advice: a['advice'] ?? '',
      extraNote: a['extra_note'] ?? '',
      moduleKey: moduleKey,
      stockData: stockData,
    );
  }

  // ============ 风险卡片 ============

  Widget _buildRiskCard(Map<String, dynamic> ai, BuildContext context) {
    final colors = AppColors.of(context);
    final risks = (ai['risk'] ?? ['市场系统性风险不可忽视']) as List;

    return Container(
      decoration: BoxDecoration(
        color: colors.riskCardBg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('风险提示', style: AppText.h2.copyWith(color: colors.textPrimary)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...risks.map((x) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(margin: const EdgeInsets.only(top: 6), width: 6, height: 6, decoration: BoxDecoration(color: AppColors.warning, shape: BoxShape.circle)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(x.toString(), style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.5))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ============ 小组件 ============
  Widget _miniInfo(String label, String value, BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.hint.copyWith(color: colors.textHint)),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppText.caption.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _circleIndicator(String label, String val, Color c, BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [c.withOpacity(0.3), c.withOpacity(0.1)]),
            border: Border.all(color: c.withOpacity(0.6), width: 2.5),
          ),
          child: Center(child: FittedBox(child: Text(val, style: AppText.body1.copyWith(color: c, fontWeight: FontWeight.w800)))),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppText.hint.copyWith(color: colors.textHint)),
      ],
    );
  }

  Widget _scoreBar(String label, double v, AppColorScheme colors) {
    v = v.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label, style: AppText.caption.copyWith(color: colors.textSecondary))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: v,
              backgroundColor: colors.surfaceVariant,
              minHeight: 8,
              valueColor: AlwaysStoppedAnimation(_getScoreColor(v, colors)),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(width: 40, child: Text('${(v * 100).toStringAsFixed(0)}%', style: AppText.caption.copyWith(color: _getScoreColor(v, colors), fontWeight: FontWeight.w700))),
      ],
    );
  }

  // ============ 可展开分析卡片 ============

  IconData _analysisIcon(String type) {
    switch (type) {
      case 'price': return Icons.attach_money;
      case 'volume': return Icons.bar_chart;
      case 'volatility': return Icons.show_chart;
      case 'bid_ask': return Icons.swap_vert;
      case 'trend': return Icons.trending_up;
      case 'valuation': return Icons.assessment;
      case 'momentum': return Icons.speed;
      case 'support': return Icons.vertical_align_center;
      case 'schedule': return Icons.schedule;
      case 'capital_flow': return Icons.account_balance;
      case 'psychology': return Icons.psychology;
      default: return Icons.analytics;
    }
  }

  Color getPriceColor(double changePct) => changePct >= 0 ? AppColors.up : AppColors.down;

  Color _getActionColor(String action, AppColorScheme colors) {
    return colors.getActionColor(action);
  }

  String _getActionLabel(String action) {
    switch (action) {
      case 'buy': return '买入';
      case 'sell': return '卖出';
      case 'hold': return '持有';
      default: return '持有';
    }
  }

  Color _getScoreColor(double score, AppColorScheme colors) {
    if (score >= 0.7) return AppColors.up;
    if (score >= 0.4) return AppColors.warning;
    return AppColors.down;
  }

  Color _getTrendColor(String trend, AppColorScheme colors) {
    return colors.getTrendColor(trend);
  }

  String _getTrendLabel(String trend) {
    switch (trend) {
      case 'up': return '上涨';
      case 'down': return '下跌';
      default: return '中性';
    }
  }
}

// ============ 可展开分析卡片 ============

class _ExpandableAnalysisCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final String sentiment;
  final double score;
  final Map<String, String> items;
  final String advice;
  final String extraNote;
  final String moduleKey;
  final Map<String, dynamic>? stockData;

  const _ExpandableAnalysisCard({
    required this.title,
    required this.icon,
    required this.sentiment,
    required this.score,
    required this.items,
    required this.advice,
    required this.extraNote,
    this.moduleKey = '',
    this.stockData,
  });

  @override
  State<_ExpandableAnalysisCard> createState() => _ExpandableAnalysisCardState();
}

class _ExpandableAnalysisCardState extends State<_ExpandableAnalysisCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _rotation;

  // 云端AI分析相关状态
  bool _isLoadingAI = false;
  String? _cloudAIAdvice;
  Map<String, dynamic>? _cloudAIResult;
  final StockDeepAnalysisService _aiService = StockDeepAnalysisService();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _rotation = Tween<double>(begin: 0, end: 0.5).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  // 判断是否为极智深度分析模块
  bool get _isDeepAnalysisModule => widget.moduleKey == 'psychology' || widget.moduleKey == 'ai_detailed' || widget.title == '极智深度分析';

  // 是否已有云端AI结果
  bool get _hasCloudAIResult => _cloudAIResult?['is_cloud_ai'] == true;

  void _onExpandChanged(bool expanded) {
    setState(() => _expanded = expanded);
    if (expanded) {
      _controller.forward();
      // 展开极智深度分析模块时，自动触发云端AI分析
      if (_isDeepAnalysisModule && !_hasCloudAIResult && widget.stockData != null && _cloudAIResult == null) {
        _fetchCloudAIAnalysis();
      }
    } else {
      _controller.reverse();
    }
  }

  // 调用云端AI进行深度分析
  Future<void> _fetchCloudAIAnalysis() async {
    if (_isLoadingAI || widget.stockData == null) return;
    setState(() => _isLoadingAI = true);
    try {
      final result = await _aiService.analyzeStock(widget.stockData!);
      if (mounted) {
        setState(() {
          _cloudAIResult = result;
          _cloudAIAdvice = result['advice'] as String?;
          _isLoadingAI = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAI = false;
          _cloudAIAdvice = '极智云端分析暂时不可用';
        });
      }
    }
  }

  String get _displayAdvice => _cloudAIAdvice ?? widget.advice;
  Map<String, String> get _displayItems {
    if (_cloudAIResult != null) {
      final items = _cloudAIResult!['items'] as Map<String, dynamic>? ?? {};
      return items.map((k, v) => MapEntry(k, v.toString()));
    }
    return widget.items;
  }
  double get _displayScore => (_cloudAIResult?['score'] as num?)?.toDouble() ?? widget.score;
  String get _displaySentiment => _cloudAIResult?['sentiment'] as String? ?? widget.sentiment;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scoreColor = _getScoreColor(_displayScore, colors);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: _expanded ? colors.primary.withOpacity(0.4) : colors.border.withOpacity(0.5)),
        boxShadow: _expanded ? AppShadow.card : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _onExpandChanged(!_expanded),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [scoreColor.withOpacity(0.2), scoreColor.withOpacity(0.05)]),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(widget.icon, color: scoreColor, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(widget.title, style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(_displaySentiment, style: AppText.caption.copyWith(color: scoreColor, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('${(_displayScore * 100).toStringAsFixed(0)}', style: AppText.h2.copyWith(color: scoreColor, fontWeight: FontWeight.w800)),
                    RotationTransition(
                      turns: _rotation,
                      child: Icon(Icons.expand_more, color: colors.textSecondary),
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(color: AppColors.divider, height: 1),
                  const SizedBox(height: AppSpacing.lg),
                  // 云端AI加载中
                  if (_isDeepAnalysisModule && _isLoadingAI) ...[
                    Center(child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(children: [
                        SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(colors.primary))),
                        const SizedBox(height: AppSpacing.md),
                        Text('极智云端分析中...', style: AppText.body2.copyWith(color: colors.textSecondary)),
                      ]),
                    )),
                  ] else ...[
                  if (_displayItems.isNotEmpty) ...[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: _displayItems.entries.map((e) => SizedBox(
                        width: (MediaQuery.of(context).size.width - AppSpacing.xl * 2 - AppSpacing.sm) / 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key, style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(e.value, style: AppText.body2.copyWith(
                              color: _itemValueColor(e.key, e.value, colors),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            )),
                          ],
                        ),
                      )).toList(),
                    ),
                  ],
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text('极智解读', style: AppText.caption.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              // 云端AI标识
                              if (_isDeepAnalysisModule && _hasCloudAIResult)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.cloud_done, size: 12, color: AppColors.success),
                                    const SizedBox(width: 4),
                                    Text('云端AI', style: AppText.caption.copyWith(color: AppColors.success, fontSize: 10)),
                                  ]),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 500),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(_displayAdvice, style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.6)),
                            ),
                          ),
                          if (widget.extraNote.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(widget.extraNote, style: AppText.caption.copyWith(color: colors.textHint, height: 1.5)),
                          ],
                          // 调用云端AI按钮（仅在极智深度分析模块且未获取结果时显示）
                          if (_isDeepAnalysisModule && !_hasCloudAIResult && !_isLoadingAI && _cloudAIResult == null) ...[
                            const SizedBox(height: AppSpacing.md),
                            InkWell(
                              onTap: _fetchCloudAIAnalysis,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: AppColors.primaryGradient),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.cloud_sync, size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text('调用云端AI深度分析', style: AppText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getScoreColor(double score, AppColorScheme colors) {
    if (score >= 0.7) return AppColors.up;
    if (score >= 0.4) return AppColors.warning;
    return AppColors.down;
  }

  Color _itemValueColor(String key, String value, AppColorScheme colors) {
    if (key == 'ROE' || key == '营收增速' || key == '毛利率') {
      final v = double.tryParse(value.replaceAll(RegExp(r'[+%倍]'), '')) ?? 0;
      if (v > 0) return AppColors.up;
      if (v < 0) return AppColors.down;
    }
    if (key == 'PE') {
      final v = double.tryParse(value.replaceAll(RegExp(r'[倍]'), '')) ?? 0;
      if (v > 0 && v < 15) return AppColors.up;
      if (v > 40) return AppColors.down;
    }
    return colors.textSecondary;
  }
}
