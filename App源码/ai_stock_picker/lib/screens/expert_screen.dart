/// 专家选股页面 - 年轻化设计
///
/// 深蓝紫渐变 + 玻璃态效果

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/expert_stock_service.dart';
import '../services/local_data_service.dart';
import 'stock_analysis_screen.dart';
import 'hot_track_screen.dart';

class ExpertScreen extends StatefulWidget {
  final LocalDataService api;
  const ExpertScreen({Key? key, required this.api}) : super(key: key);
  @override
  State<ExpertScreen> createState() => _ExpertScreenState();
}

class _ExpertScreenState extends State<ExpertScreen> {
  final ExpertStockService _expert = ExpertStockService();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
          title: Text('专家选股', style: AppText.h2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 策略卡片
            _buildStrategyCard('短炒猎手', '短线爆发 · 5-20日', Icons.flash_on,
              [colors.up, colors.warning],
              '追逐资金效率极致，识别放量突破、价格动能强劲的短线爆发标的',
              ['相对强度', '价格动能', '放量突破', '7%止损'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('成长先锋', '十倍股捕猎 · 1-3年', Icons.rocket_launch,
              [colors.primary, colors.accent],
              '寻找PEG<1、增速20-40%黄金区间的成长股',
              ['PEG估值', '业绩增长', '行业壁垒', '护城河'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('稳健堡垒', '穿越牛熊 · 长期持有', Icons.shield,
              [colors.down, colors.down],
              '极度保守的价值投资，高股息、高ROE、低负债',
              ['ROE>15%', '股息率>3.5%', '安全边际', '低负债'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('A股游资', 'T+1极速博弈', Icons.bolt,
              [colors.warning, colors.up],
              '顶级游资视角的情绪接力策略，打板确认+尾盘潜伏',
              ['打板确认', '尾盘潜伏', '次日预期', '4%硬止损'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('A股游资B', '游资+AI精选5只', Icons.auto_awesome,
              [colors.primary, colors.accent],
              '游资策略模型初筛+云端AI大模型综合分析，精选5只最强标的',
              ['游资初筛', 'AI精选', '综合评分', '精准5只'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('隔夜导航', '盘后选股 · 早盘预埋', Icons.nightlight,
              [colors.accent, colors.primary],
              '收盘后筛选溢价惯性标的，生成精确挂单计划',
              ['首板/突破', '挂单预埋', '止盈止损', '压力位'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('锦鲤选股', '四因子融合 · 10只精选', Icons.catching_pokemon,
              [colors.up, colors.warning],
              '资金+趋势+基本面+事件四因子共振，一票否决排除高风险标的',
              ['资金热点', '趋势确认', '基本面优', '事件共振'], colors),
            const SizedBox(height: AppSpacing.md),

            _buildStrategyCard('锦鲤选股B', '量化私募级 · AI深度穿透', Icons.psychology,
              [colors.primary, colors.accent],
              '顶级量化私募极智决策中枢，五红线风控+三维度穿透分析+极智综合评分',
              ['红线风控', '财务穿透', '资金动能', '涨停基因'], colors),
            const SizedBox(height: AppSpacing.md),

            // ★ 热点追踪 - AI决策引擎
            _buildHotTrackCard(colors),
            const SizedBox(height: AppSpacing.xl),
          ]),
        ),
      ),
    );
  }

  Widget _buildStrategyCard(String title, String subtitle, IconData icon, List<Color> gradientColors, String description, List<String> tags, AppColorScheme colors) {
    return GestureDetector(
      onTap: () => _runStrategy(title),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [gradientColors[0].withOpacity(0.15), gradientColors[1].withOpacity(0.05)]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: gradientColors[0].withOpacity(0.3)),
          boxShadow: [BoxShadow(color: gradientColors[0].withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadow.button,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.xs),
              Text(subtitle, style: AppText.caption.copyWith(color: gradientColors[0], fontWeight: FontWeight.w700)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(AppRadius.full),
                boxShadow: AppShadow.button,
              ),
              child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
          ]),
        ),
      ),
    );
  }

  /// 热点追踪入口卡片 - 特殊样式（火焰橙红渐变）
  Widget _buildHotTrackCard(AppColorScheme colors) {
    return GestureDetector(
      onTap: () => _openHotTrack(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.orange.withOpacity(0.15), Colors.red.withOpacity(0.05)]),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.local_fire_department, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('热点追踪', style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('AI', style: AppText.caption.copyWith(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              Text('AI决策引擎 · 预期差定性 · 量化参数生成', style: AppText.caption.copyWith(color: Colors.orange, fontWeight: FontWeight.w700)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
                borderRadius: BorderRadius.circular(AppRadius.full),
                boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
          ]),
        ),
      ),
    );
  }

  void _openHotTrack() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => HotTrackScreen(api: widget.api),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          return SlideTransition(position: Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation), child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _runStrategy(String name) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => StrategyResultScreen(strategyName: name, expert: _expert, api: widget.api),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          return SlideTransition(position: Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation), child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
    if (result != null && result is String && result.isNotEmpty) Navigator.pop(context, result);
  }
}

/// 策略执行结果页面
class StrategyResultScreen extends StatefulWidget {
  final String strategyName;
  final ExpertStockService expert;
  final LocalDataService api;

  const StrategyResultScreen({Key? key, required this.strategyName, required this.expert, required this.api}) : super(key: key);
  @override
  State<StrategyResultScreen> createState() => _StrategyResultScreenState();
}

class _StrategyResultScreenState extends State<StrategyResultScreen> {
  bool _loading = true;
  String? _err;
  Map<String, dynamic>? _result;

  @override
  void initState() { super.initState(); _runStrategy(); }

  void _runStrategy() async {
    setState(() { _loading = true; _err = null; });
    try {
      Map<String, dynamic> data;
      if (widget.strategyName == '短炒猎手') data = await widget.expert.runShortTermHunter();
      else if (widget.strategyName == '成长先锋') data = await widget.expert.runGrowthPioneer();
      else if (widget.strategyName == 'A股游资') data = await widget.expert.runSpeedAssassin();
      else if (widget.strategyName == 'A股游资B') data = await widget.expert.runSpeedAssassinB();
      else if (widget.strategyName == '隔夜导航') data = await widget.expert.runOvernightNavigator();
      else if (widget.strategyName == '锦鲤选股') data = await widget.expert.runKoiPicker();
      else if (widget.strategyName == '锦鲤选股B') data = await widget.expert.runKoiPickerB();
      else data = await widget.expert.runStableFortress();
      if (mounted) setState(() { _result = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
          title: Text(widget.strategyName, style: AppText.h2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
          ),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _runStrategy)],
        ),
        body: _loading ? _buildLoading(colors) : (_err != null ? _buildError(colors) : _buildResult(colors)),
      ),
    );
  }

  Widget _buildLoading(AppColorScheme colors) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Column(children: [
          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(colors.primary)),
          const SizedBox(height: AppSpacing.lg),
          Text('正在执行策略选股...', style: AppText.body2.copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Text(widget.strategyName == 'A股游资B' ? '游资策略初筛+云端AI精选中...' :
               widget.strategyName == '锦鲤选股B' ? '量化私募极智穿透分析中...' :
               '扫描全市场A股数据中', style: AppText.caption.copyWith(color: colors.textHint)),
        ]),
      ),
    ]));
  }

  Widget _buildError(AppColorScheme colors) {
    return Center(child: Container(
      margin: const EdgeInsets.all(AppSpacing.xxl),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.error.withOpacity(0.3))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: colors.error),
        const SizedBox(height: AppSpacing.md),
        Text('选股失败', style: AppText.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text(_err ?? '', style: AppText.body2.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton.icon(onPressed: _runStrategy, icon: const Icon(Icons.refresh, size: 18), label: const Text('重试')),
      ]),
    ));
  }

  Widget _buildResult(AppColorScheme colors) {
    final stocks = (_result?['stocks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final timestamp = _result?['timestamp']?.toString() ?? '';

    if (stocks.isEmpty) {
      return Center(child: Container(
        margin: const EdgeInsets.all(AppSpacing.xxl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 48, color: colors.textHint),
          const SizedBox(height: AppSpacing.md),
          Text('暂无匹配标的', style: AppText.h3.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Text('当前市场条件未找到满足策略要求的股票', style: AppText.body2.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
        ]),
      ));
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.down.withOpacity(0.15), colors.down.withOpacity(0.05)]),
        ),
        child: Row(children: [
          Icon(Icons.check_circle, size: 18, color: colors.down),
          const SizedBox(width: AppSpacing.sm),
          Text('筛选出 ${stocks.length} 只标的', style: AppText.body2.copyWith(color: colors.down, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(timestamp.substring(0, timestamp.length > 19 ? 19 : timestamp.length),
            style: AppText.hint.copyWith(color: colors.textHint)),
        ]),
      ),
      Expanded(child: ListView.builder(
        itemCount: stocks.length,
        itemBuilder: (ctx, i) => _buildStockCard(stocks[i], i + 1, colors),
      )),
    ]);
  }

  Widget _buildStockCard(Map<String, dynamic> s, int rank, AppColorScheme colors) {
    final name = s['name']?.toString() ?? '';
    final code = s['code']?.toString() ?? '';
    final price = _safeDouble(s['price']);
    final chg = _safeDouble(s['change_pct']);
    final score = _safeDouble(s['strategy_score']);
    final isUp = chg >= 0;
    final chgColor = isUp ? colors.up : colors.down;
    final aiAnalysis = s['ai_analysis_text']?.toString() ?? '';
    final localScore = _safeDouble(s['local_score']);
    final aiScore = _safeDouble(s['ai_score']);
    final isHotMoneyB = widget.strategyName == 'A股游资B';
    
    // 锦鲤选股专用字段
    final isKoi = widget.strategyName == '锦鲤选股' || widget.strategyName == '锦鲤选股B';
    final isKoiB = widget.strategyName == '锦鲤选股B';
    final koiLogic = s['koi_logic']?.toString() ?? '';
    final capitalScore = _safeDouble(s['capital_score']);
    final trendScore = _safeDouble(s['trend_score']);
    final fundamentalScore = _safeDouble(s['fundamental_score']);
    final eventScore = _safeDouble(s['event_score']);
    // 锦鲤AI深度检查字段
    final aiCheckResult = s['ai_check_result']?.toString() ?? '';
    final koiAiAnalysis = isKoi ? aiAnalysis : '';
    // 锦鲤B专用字段
    final vetoTriggered = s['veto_triggered'] == true;
    final vetoReason = s['veto_reason']?.toString() ?? '';
    final financialScore = _safeDouble(s['financial_score']);
    final capitalScoreKoiB = _safeDouble(s['capital_score_koi_b']);
    final technicalScore = _safeDouble(s['technical_score']);
    final decision = s['decision']?.toString() ?? '';
    final coreAnalysis = s['core_analysis']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.glassCard, borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.glassBorder),
        boxShadow: AppShadow.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _onStockTap(code, s),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    gradient: rank <= 3 ? LinearGradient(colors: [colors.warning, colors.up]) : null,
                    color: rank > 3 ? colors.surfaceVariant : null,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(child: Text('$rank', style: AppText.body2.copyWith(
                    color: rank <= 3 ? Colors.white : colors.textSecondary, fontWeight: FontWeight.w800))),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                  Text(code, style: AppText.hint.copyWith(color: colors.textHint)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(price > 0 ? price.toStringAsFixed(2) : '--',
                    style: AppText.h3.copyWith(color: chgColor, fontWeight: FontWeight.w800)),
                  Text('${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%',
                    style: AppText.caption.copyWith(color: chgColor, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: _scoreColor(score, colors).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text('${score.toStringAsFixed(0)}分',
                    style: AppText.caption.copyWith(color: _scoreColor(score, colors), fontWeight: FontWeight.w700)),
                ),
              ]),
              // A股游资B显示AI分析
              if (isHotMoneyB && aiAnalysis.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors.primaryGradient),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text('极智分析', style: AppText.caption.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                      if (aiScore > 0) ...[
                        const Spacer(),
                        Text('本地${localScore.toStringAsFixed(0)}+AI${aiScore.toStringAsFixed(0)}',
                          style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10)),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    Text(aiAnalysis, style: AppText.caption.copyWith(color: colors.textSecondary, height: 1.5)),
                  ]),
                ),
              ],
              // 锦鲤选股B显示三维度评分 + AI决策
              if (isKoiB) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [colors.primary.withOpacity(0.15), colors.accent.withOpacity(0.05)]),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: _getDecisionColor(decision, colors).withOpacity(0.3)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors.primaryGradient),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Icon(Icons.psychology, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text('量化私募极智决策', style: AppText.caption.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      // 评分来源
                      if (aiScore > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('本地${localScore.toStringAsFixed(0)}+AI${aiScore.toStringAsFixed(0)}', style: AppText.caption.copyWith(color: colors.primary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (decision.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getDecisionColor(decision, colors).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(decision, style: AppText.caption.copyWith(color: _getDecisionColor(decision, colors), fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    // 三维度评分进度条
                    _buildScoreBar('财务基本面', financialScore, 40, colors.down, colors),
                    const SizedBox(height: 4),
                    _buildScoreBar('资金动能', capitalScoreKoiB, 40, colors.primary, colors),
                    const SizedBox(height: 4),
                    _buildScoreBar('技术形态', technicalScore, 20, colors.warning, colors),
                    if (vetoTriggered && vetoReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(children: [
                          Icon(Icons.block, size: 14, color: colors.error),
                          const SizedBox(width: 4),
                          Expanded(child: Text('红线否决: $vetoReason', style: AppText.caption.copyWith(color: colors.error, fontSize: 11))),
                        ]),
                      ),
                    ],
                    // 点击卡片查看完整极智核心分析
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.touch_app, size: 12, color: colors.primary),
                        const SizedBox(width: 4),
                        Text('点击查看极智核心分析', style: AppText.caption.copyWith(color: colors.primary, fontSize: 10)),
                      ]),
                    ),
                  ]),
                ),
              ],
              // 锦鲤选股显示四因子评分 + AI深度检查
              if (isKoi && !isKoiB && koiLogic.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [colors.up.withOpacity(0.1), colors.warning.withOpacity(0.05)]),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [colors.up, colors.warning]),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: const Icon(Icons.catching_pokemon, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Text('锦鲤分析', style: AppText.caption.copyWith(color: colors.up, fontWeight: FontWeight.w700)),
                      if (aiScore > 0) ...[
                        const Spacer(),
                        Text('本地${localScore.toStringAsFixed(0)}+AI${aiScore.toStringAsFixed(0)}',
                          style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10)),
                      ],
                    ]),
                    const SizedBox(height: 6),
                    // 四因子评分条
                    Row(children: [
                      _buildFactorChip('资金', capitalScore, colors.down, colors),
                      const SizedBox(width: 6),
                      _buildFactorChip('趋势', trendScore, colors.primary, colors),
                      const SizedBox(width: 6),
                      _buildFactorChip('基本面', fundamentalScore, colors.accent, colors),
                      const SizedBox(width: 6),
                      _buildFactorChip('事件', eventScore, colors.warning, colors),
                    ]),
                    const SizedBox(height: 6),
                    Text(koiLogic, style: AppText.caption.copyWith(color: colors.textSecondary, height: 1.5)),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFactorChip(String label, double score, Color color, AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label${score.toStringAsFixed(0)}', style: AppText.caption.copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Color _scoreColor(double score, AppColorScheme colors) {
    if (score >= 70) return colors.down;
    if (score >= 50) return colors.warning;
    if (score >= 30) return colors.primary;
    return colors.textSecondary;
  }

  // 锦鲤AI检查结果颜色
  Color _getCheckResultColor(String result, AppColorScheme colors) {
    if (result.contains('通过')) return colors.down;
    if (result.contains('谨慎')) return colors.warning;
    if (result.contains('回避')) return colors.error;
    return colors.textSecondary;
  }

  // 锦鲤B决策颜色
  Color _getDecisionColor(String decision, AppColorScheme colors) {
    if (decision.contains('强力推荐')) return colors.down;
    if (decision.contains('建议观察')) return colors.warning;
    if (decision.contains('淘汰')) return colors.error;
    return colors.textSecondary;
  }

  // 锦鲤B三维度评分进度条
  Widget _buildScoreBar(String label, double score, double maxScore, Color color, AppColorScheme colors) {
    final ratio = maxScore > 0 ? (score / maxScore).clamp(0.0, 1.0) : 0.0;
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10))),
      Expanded(child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(3),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      )),
      const SizedBox(width: 4),
      SizedBox(width: 32, child: Text('${score.toStringAsFixed(0)}/${maxScore.toStringAsFixed(0)}',
        style: AppText.caption.copyWith(color: color, fontSize: 9, fontWeight: FontWeight.w700))),
    ]);
  }

  void _onStockTap(String code, Map<String, dynamic> stockData) {
    // 锦鲤选股B：点击弹出分析模板
    if (widget.strategyName == '锦鲤选股B') {
      _showKoiBAnalysisTemplate(code, stockData);
      return;
    }
    // 其他策略：直接导航到个股分析页
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockAnalysisScreen(symbol: code)),
    );
  }

  /// 锦鲤选股B - 展示分析内容模板
  void _showKoiBAnalysisTemplate(String code, Map<String, dynamic> s) {
    final colors = AppColors.of(context);
    final name = s['name']?.toString() ?? '';
    final price = _safeDouble(s['price']);
    final chg = _safeDouble(s['change_pct']);
    final turnover = _safeDouble(s['turnoverratio']);
    final amount = _safeDouble(s['amount']);
    final mktCap = _safeDouble(s['mktcap']);
    final fin = s['financials'] as Map<String, dynamic>? ?? {};
    final score = _safeDouble(s['strategy_score']);
    final localScore = _safeDouble(s['local_score']);
    final aiScore = _safeDouble(s['ai_score']);
    final vetoTriggered = s['veto_triggered'] == true;
    final vetoReason = s['veto_reason']?.toString() ?? '';
    final financialScore = _safeDouble(s['financial_score']);
    final capitalScore = _safeDouble(s['capital_score_koi_b']);
    final technicalScore = _safeDouble(s['technical_score']);
    final decision = s['decision']?.toString() ?? '';
    final coreAnalysis = s['core_analysis']?.toString() ?? '';

    final roe = _safeDouble(fin['roe']);
    final peg = _safeDouble(fin['peg']);
    final profitGrowth = _safeDouble(fin['profit_growth']);
    final revenueGrowth = _safeDouble(fin['revenue_growth']);
    final debtRatio = _safeDouble(fin['debt_ratio']);
    final grossMargin = _safeDouble(fin['gross_margin']);
    final capYi = mktCap > 0 ? (mktCap / 10000).toStringAsFixed(1) : '?';
    final amountYi = amount > 1e8 ? '${(amount / 1e8).toStringAsFixed(1)}亿' : '${(amount / 1e4).toStringAsFixed(0)}万';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (ctx, controller) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors.backgroundGradient),
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          ),
          child: Column(children: [
            // 顶部拖拽条
            Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: colors.textHint.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            // 标题栏
            Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: colors.primaryGradient), borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Icon(Icons.psychology, color: Colors.white, size: 18)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$name · 量化私募极智穿透分析', style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                  Text('$code  ${price.toStringAsFixed(2)}元  ${chg >= 0 ? "+" : ""}${chg.toStringAsFixed(2)}%',
                    style: AppText.caption.copyWith(color: chg >= 0 ? colors.up : colors.down)),
                ])),
                IconButton(icon: Icon(Icons.close, color: colors.textHint), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            // 内容区
            Expanded(child: ListView(controller: controller, padding: const EdgeInsets.all(AppSpacing.lg), children: [
              // ── 综合评分总览 ──
              _buildSectionTitle('综合评分总览', Icons.assessment, colors.primary, colors),
              const SizedBox(height: AppSpacing.md),
              Container(padding: const EdgeInsets.all(AppSpacing.lg), decoration: BoxDecoration(
                gradient: LinearGradient(colors: [colors.primary.withOpacity(0.12), colors.accent.withOpacity(0.04)]),
                borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: colors.primary.withOpacity(0.2)),
              ), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 72, height: 72, decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [_getDecisionColor(decision, colors).withOpacity(0.3), _getDecisionColor(decision, colors).withOpacity(0.1)]),
                    shape: BoxShape.circle, border: Border.all(color: _getDecisionColor(decision, colors), width: 2),
                  ), child: Center(child: Text('${score.toStringAsFixed(0)}', style: AppText.h1.copyWith(color: _getDecisionColor(decision, colors), fontWeight: FontWeight.w900, fontSize: 28)))),
                  const SizedBox(width: AppSpacing.xl),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('综合匹配度', style: AppText.body2.copyWith(color: colors.textSecondary)),
                    const SizedBox(height: 4),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(
                      color: _getDecisionColor(decision, colors).withOpacity(0.15), borderRadius: BorderRadius.circular(AppRadius.sm),
                    ), child: Text(decision.isEmpty ? '待评估' : decision, style: AppText.body2.copyWith(color: _getDecisionColor(decision, colors), fontWeight: FontWeight.w800))),
                    if (aiScore > 0) ...[
                      const SizedBox(height: 4),
                      Text('本地${localScore.toStringAsFixed(0)}×40% + AI${aiScore.toStringAsFixed(0)}×60%', style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10)),
                    ],
                  ]),
                ]),
              ])),
              const SizedBox(height: AppSpacing.xl),

              // ── 第一步：一票否决风控（红线审核）──
              _buildSectionTitle('第一步：一票否决风控（红线审核）', Icons.shield, vetoTriggered ? colors.error : colors.down, colors),
              const SizedBox(height: AppSpacing.md),
              _buildVetoCheckItem('ST/*ST标签', name.contains('ST') || name.contains('*ST'), colors),
              _buildVetoCheckItem('资产负债率≥70%', debtRatio >= 70, colors, detail: '当前${debtRatio.toStringAsFixed(1)}%'),
              _buildVetoCheckItem('扣非净利润大幅下滑', profitGrowth < -50, colors, detail: '净利增${profitGrowth.toStringAsFixed(1)}%'),
              _buildVetoCheckItem('夕阳行业', _isSunsetIndustry(name), colors, detail: name),
              _buildVetoCheckItem('低毛利且亏损', grossMargin < 10 && grossMargin > 0 && profitGrowth < -20, colors, detail: '毛利率${grossMargin.toStringAsFixed(1)}%'),
              if (vetoTriggered) ...[
                const SizedBox(height: AppSpacing.md),
                Container(padding: const EdgeInsets.all(AppSpacing.md), decoration: BoxDecoration(
                  color: colors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: colors.error.withOpacity(0.3)),
                ), child: Row(children: [
                  Icon(Icons.block, color: colors.error, size: 18), const SizedBox(width: 8),
                  Expanded(child: Text('红线否决: $vetoReason', style: AppText.body2.copyWith(color: colors.error, fontWeight: FontWeight.w700))),
                ])),
              ],
              const SizedBox(height: AppSpacing.xl),

              // ── 第二步：维度打分（本地计算）──
              _buildSectionTitle('第二步：维度打分与逻辑校验（满分100）', Icons.rule, colors.warning, colors),
              const SizedBox(height: AppSpacing.md),

              // 维度一：财务与基本面（本地计算）
              _buildDimensionCard('维度一：财务与基本面', 
                _calcDualGrowthScore(revenueGrowth, profitGrowth) + _calcProfitQualityScore(roe, grossMargin), 40, colors.down, colors, [
                _buildScoreDetail('业绩双增', 20, _calcDualGrowthScore(revenueGrowth, profitGrowth), colors,
                  '营收同比${revenueGrowth.toStringAsFixed(1)}%${revenueGrowth > 20 ? "✓" : "✗"}，净利同比${profitGrowth.toStringAsFixed(1)}%${profitGrowth > 50 ? "✓" : "✗"}'),
                _buildScoreDetail('利润含金量', 20, _calcProfitQualityScore(roe, grossMargin), colors,
                  'ROE ${roe.toStringAsFixed(1)}%，毛利率${grossMargin.toStringAsFixed(1)}%，负债率${debtRatio.toStringAsFixed(1)}%'),
              ]),
              const SizedBox(height: AppSpacing.md),

              // 维度二：资金面与主力含金量（本地计算）
              _buildDimensionCard('维度二：资金面与主力含金量', 
                _calcCapitalMatchScore(amount, mktCap) + _calcMainForceScore(turnover, amount), 40, colors.primary, colors, [
                _buildScoreDetail('资金体量匹配', 20, _calcCapitalMatchScore(amount, mktCap), colors,
                  '成交额$amountYi，流通市值${capYi}亿，占比${mktCap > 0 && amount > 0 ? (amount / (mktCap * 1e4) * 100).toStringAsFixed(1) : "?"}%'),
                _buildScoreDetail('主力背景穿透', 20, _calcMainForceScore(turnover, amount), colors,
                  '换手率${turnover.toStringAsFixed(1)}%，成交额$amountYi'),
              ]),
              const SizedBox(height: AppSpacing.md),

              // 维度三：技术形态与活跃度（本地计算）
              _buildDimensionCard('维度三：技术形态与活跃度', 
                _calcLimitUpScore(chg) + _calcVolumeHealthScore(turnover), 20, colors.warning, colors, [
                _buildScoreDetail('涨停基因', 15, _calcLimitUpScore(chg), colors,
                  '今日涨幅${chg.toStringAsFixed(2)}%${chg >= 9.8 ? "（涨停！）" : ""}'),
                _buildScoreDetail('量价健康', 5, _calcVolumeHealthScore(turnover), colors,
                  '换手率${turnover.toStringAsFixed(1)}%${turnover >= 3 && turnover <= 10 ? "（健康区间）" : turnover > 10 ? "（偏高）" : "（偏低）"}'),
              ]),
              const SizedBox(height: AppSpacing.xl),

              // ── 第三步：AI结构化评估输出 ──
              _buildSectionTitle('第三步：AI结构化评估输出', Icons.data_object, colors.accent, colors),
              const SizedBox(height: AppSpacing.md),
              Container(padding: const EdgeInsets.all(AppSpacing.md), decoration: BoxDecoration(
                color: colors.glassCard, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: colors.glassBorder),
              ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildOutputLine('股票名称', '$name($code)', colors.textPrimary, colors),
                _buildOutputLine('总分', '${(financialScore + capitalScore + technicalScore).toStringAsFixed(0)}/100', _getDecisionColor(decision, colors), colors),
                _buildOutputLine('维度一得分', '${financialScore.toStringAsFixed(0)}/40', colors.down, colors),
                _buildOutputLine('维度二得分', '${capitalScore.toStringAsFixed(0)}/40', colors.primary, colors),
                _buildOutputLine('维度三得分', '${technicalScore.toStringAsFixed(0)}/20', colors.warning, colors),
                _buildOutputLine('投资决策', vetoTriggered ? '淘汰剔除' : (decision.isEmpty ? '待评估' : decision), _getDecisionColor(vetoTriggered ? '淘汰' : decision, colors), colors),
              ])),
              const SizedBox(height: AppSpacing.xl),

              // ── 极智核心分析 ──
              if (coreAnalysis.isNotEmpty) ...[
                _buildSectionTitle('极智核心分析', Icons.auto_awesome, colors.accent, colors),
                const SizedBox(height: AppSpacing.md),
                Container(padding: const EdgeInsets.all(AppSpacing.md), decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [colors.primary.withOpacity(0.1), colors.accent.withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: colors.accent.withOpacity(0.2)),
                ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 按4点拆分显示
                  ..._buildCoreAnalysisSections(_cleanCoreAnalysis(coreAnalysis), colors),
                ])),
                const SizedBox(height: AppSpacing.xl),
              ],
            ])),
          ]),
        ),
      ),
    );
  }

  /// 构建区域标题
  Widget _buildSectionTitle(String title, IconData icon, Color color, AppColorScheme colors) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, size: 16, color: color)),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800))),
    ]);
  }

  /// 构建红线检查项
  Widget _buildVetoCheckItem(String label, bool triggered, AppColorScheme colors, {String detail = ''}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: triggered ? colors.error.withOpacity(0.08) : colors.down.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: triggered ? colors.error.withOpacity(0.2) : colors.down.withOpacity(0.1)),
      ),
      child: Row(children: [
        Icon(triggered ? Icons.cancel : Icons.check_circle, size: 16, color: triggered ? colors.error : colors.down),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppText.body2.copyWith(color: triggered ? colors.error : colors.textSecondary))),
        if (detail.isNotEmpty) Text(detail, style: AppText.caption.copyWith(color: triggered ? colors.error : colors.textHint, fontSize: 10)),
      ]),
    );
  }

  /// 构建维度卡片
  Widget _buildDimensionCard(String title, double score, double maxScore, Color color, AppColorScheme colors, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.08), color.withOpacity(0.02)]),
        borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: AppText.body1.copyWith(color: color, fontWeight: FontWeight.w800))),
          Text('${score.toStringAsFixed(0)} / ${maxScore.toStringAsFixed(0)}',
            style: AppText.h3.copyWith(color: color, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
          value: maxScore > 0 ? (score / maxScore).clamp(0.0, 1.0) : 0.0,
          backgroundColor: color.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(color), minHeight: 6,
        )),
        const SizedBox(height: AppSpacing.md),
        ...children,
      ]),
    );
  }

  /// 构建评分详情行
  Widget _buildScoreDetail(String label, double maxPoints, double actualPoints, AppColorScheme colors, String detail) {
    final ratio = maxPoints > 0 ? (actualPoints / maxPoints) : 0.0;
    final isGood = ratio >= 0.7;
    final isWarn = ratio >= 0.4 && ratio < 0.7;
    final color = isGood ? colors.down : (isWarn ? colors.warning : colors.error);
    return Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: AppText.body2.copyWith(color: colors.textSecondary))),
        Text('${actualPoints.toStringAsFixed(0)} / ${maxPoints.toStringAsFixed(0)}',
          style: AppText.body2.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 2),
      Text(detail, style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10, height: 1.4)),
    ]));
  }

  /// 构建结构化输出行
  Widget _buildOutputLine(String label, String value, Color valueColor, AppColorScheme colors) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 72, child: Text(label, style: TextStyle(color: colors.textSecondary, fontFamily: 'monospace', fontSize: 11))),
      Expanded(child: SelectableText(value, style: TextStyle(color: valueColor, fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600))),
    ]));
  }

  /// 清理核心分析文本，去除前后的大括号
  String _cleanCoreAnalysis(String analysis) {
    if (analysis.isEmpty) return analysis;
    String result = analysis.trim();
    // 去除开头的 {
    if (result.startsWith('{')) {
      result = result.substring(1).trim();
    }
    // 去除结尾的 }
    if (result.endsWith('}')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return result;
  }

  /// 构建极智核心分析分段展示
  List<Widget> _buildCoreAnalysisSections(String analysis, AppColorScheme colors) {
    final sections = <Widget>[];
    
    // 按"1." "2." "3." "4."拆分
    final parts = <String>[];
    final regex = RegExp(r'(\d\.\s)');
    final splits = regex.allMatches(analysis);
    
    if (splits.isEmpty) {
      // 没有1.2.3.4.格式，整段展示
      sections.add(SelectableText(analysis, style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.7)));
      return sections;
    }
    
    final indices = splits.map((m) => m.start).toList();
    for (int i = 0; i < indices.length; i++) {
      final start = indices[i];
      final end = i + 1 < indices.length ? indices[i + 1] : analysis.length;
      parts.add(analysis.substring(start, end).trim());
    }
    
    // 如果有前缀文本（1.之前的内容）
    if (indices.isNotEmpty && indices[0] > 0) {
      final prefix = analysis.substring(0, indices[0]).trim();
      if (prefix.isNotEmpty) parts.insert(0, prefix);
    }
    
    final labels = ['1.', '2.', '3.', '4.'];
    final icons = [Icons.trending_up, Icons.account_balance, Icons.warning_amber, Icons.speed];
    final sectionColors = [colors.down, colors.primary, colors.error, colors.warning];
    
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      // 查找对应的标签索引
      int labelIdx = -1;
      for (int j = 0; j < labels.length; j++) {
        if (part.startsWith(labels[j])) {
          labelIdx = j;
          break;
        }
      }
      
      if (labelIdx >= 0) {
        sections.add(Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: sectionColors[labelIdx].withOpacity(0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: sectionColors[labelIdx].withOpacity(0.15)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(margin: const EdgeInsets.only(top: 2), child: Icon(icons[labelIdx], size: 14, color: sectionColors[labelIdx])),
            const SizedBox(width: 6),
            Expanded(child: SelectableText(part, style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.7, fontSize: 12))),
          ]),
        ));
      } else {
        sections.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableText(part, style: AppText.body2.copyWith(color: colors.textSecondary, height: 1.7)),
        ));
      }
    }
    
    return sections;
  }

  // ── 锦鲤B评分辅助方法 ──
  bool _isSunsetIndustry(String name) {
    final kw = ['钢铁', '煤炭', '水泥', '造纸', '玻纤', '氯碱', '纯碱', 'PVC', '磷化工'];
    return kw.any((k) => name.contains(k));
  }

  double _calcDualGrowthScore(double revenueGrowth, double profitGrowth) {
    if (revenueGrowth > 20 && profitGrowth > 50) return 20;
    if (revenueGrowth > 20 || profitGrowth > 50) return 10;
    return 0;
  }

  double _calcProfitQualityScore(double roe, double grossMargin) {
    double s = 0;
    if (roe >= 20) s += 10; else if (roe >= 15) s += 8; else if (roe >= 10) s += 5; else if (roe >= 5) s += 2;
    if (grossMargin > 40) s += 10; else if (grossMargin > 25) s += 7; else if (grossMargin > 15) s += 4; else s += 1;
    return s;
  }

  double _calcCapitalMatchScore(double amount, double mktCap) {
    if (mktCap <= 0 || amount <= 0) return 0;
    final capYi = mktCap / 10000;
    final amountYi = amount / 1e8;
    if (capYi <= 0) return 0;
    final ratio = amountYi / capYi * 100;
    if (ratio >= 10) return 20; else if (ratio >= 5) return 15; else if (ratio >= 2) return 10; else if (ratio >= 1) return 5;
    return 0;
  }

  double _calcMainForceScore(double turnover, double amount) {
    final amountYi = amount / 1e8;
    if (turnover >= 3 && turnover <= 15 && amountYi > 3) return 20;
    if (turnover > 15 && turnover <= 25 && amountYi > 5) return 15;
    if (turnover >= 3 && amountYi > 2) return 10;
    if (turnover < 3 || amountYi < 1) return 0;
    return 5;
  }

  double _calcLimitUpScore(double chg) {
    if (chg >= 9.8) return 15;
    if (chg >= 7.0) return 12;
    if (chg >= 5.0) return 8;
    if (chg >= 3.0) return 5;
    return 0;
  }

  double _calcVolumeHealthScore(double turnover) {
    if (turnover >= 3 && turnover <= 10) return 5;
    if (turnover > 10 && turnover <= 20) return 3;
    return 1;
  }

  double _safeDouble(v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
