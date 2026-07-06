/// 极速投资详情页
///
/// 参考热点投资详情页风格：深色主题 + 渐变总结卡片 + 数据行 + 持仓卡片
/// T-1日20:00选股(pending) → T日09:30买入(active) → T+1日09:30卖出(settled)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../theme/app_text.dart';
import '../models/speed_investment_model.dart';
import '../services/speed_investment_service.dart';
import '../utils/trading_day_utils.dart';
import 'speed_investment_list_screen.dart';

String _portfolioDisplayDate(dynamic portfolio) {
  if (portfolio == null) return '?';
  final bd = portfolio.buyDate as DateTime;
  final prev = TradingDayUtils.getPreviousTradingDay(bd);
  return '${prev.month}/${prev.day}';
}

class SpeedInvestmentDetailScreen extends StatefulWidget {
  final SpeedPortfolio portfolio;
  final SpeedInvestmentService service;

  const SpeedInvestmentDetailScreen({Key? key, required this.portfolio, required this.service}) : super(key: key);

  @override
  State<SpeedInvestmentDetailScreen> createState() => _SpeedInvestmentDetailScreenState();
}

class _SpeedInvestmentDetailScreenState extends State<SpeedInvestmentDetailScreen> {
  SpeedPortfolio get _p => widget.portfolio;

  // 实时行情
  Map<String, Map<String, dynamic>> _quotes = {};
  bool _loadingQuotes = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    if (_p.status == SpeedPortfolioStatus.active) {
      _refreshQuotes();
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshQuotes();
    });
  }

  Future<void> _refreshQuotes() async {
    if (_p.status != SpeedPortfolioStatus.active || _p.positions.isEmpty) return;
    if (mounted) setState(() => _loadingQuotes = true);
    try {
      final codes = _p.positions.map((pos) => pos.stockCode).toList();
      // 腾讯行情要求带市场前缀：沪市sh/深市sz，纯6位数字需自动加前缀
      final qqCodes = codes.map((code) {
        if (code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj')) return code;
        if (code.startsWith('6') || code.startsWith('9')) return 'sh$code';
        return 'sz$code';
      }).join(',');
      final resp = await http.get(
        Uri.parse('https://qt.gtimg.cn/q=$qqCodes'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 8));
      final text = String.fromCharCodes(resp.bodyBytes);
      final quotes = <String, Map<String, dynamic>>{};
      for (final code in codes) {
        // 腾讯行情返回格式为 sh600000="..." 或 sz000001="..."
        final qqCode = code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj') ? code
            : (code.startsWith('6') || code.startsWith('9') ? 'sh$code' : 'sz$code');
        final pattern = RegExp('${RegExp.escape(qqCode)}="([^"]*)"');
        final match = pattern.firstMatch(text);
        if (match != null) {
          final fields = match.group(1)!.split('~');
          if (fields.length > 32) {
            quotes[code] = {
              'price': double.tryParse(fields[3]) ?? 0,
              'change_pct': double.tryParse(fields[32]) ?? 0,
            };
          }
        }
      }
      if (mounted) setState(() { _quotes = quotes; _loadingQuotes = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final p = _p;
    final isPending = p.status == SpeedPortfolioStatus.pending;
    final isActive  = p.status == SpeedPortfolioStatus.active;
    final isSettled = p.status == SpeedPortfolioStatus.settled;

    final plannedTotal = p.positions.fold<double>(0.0, (s, pos) => s + (pos.plannedAmount > 0 ? pos.plannedAmount : 20000));
    final displayAmount = isPending ? plannedTotal : p.totalInvested;

    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
          title: Text('极速组合 ${_portfolioDisplayDate(p)}',
            style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
          centerTitle: true,
          flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient))),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── 总结卡片 ──
            _buildSummaryCard(p, isPending, isActive, isSettled, displayAmount, colors),
            const SizedBox(height: AppSpacing.xl),

            // ── 持仓明细 ──
            Text(isPending ? '预选明细' : '持仓明细',
              style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.md),
            ...List.generate(p.positions.length, (idx) =>
              _buildPositionCard(p.positions[idx], idx + 1, isPending, p.sourceLabels.length > idx ? p.sourceLabels[idx] : '', colors),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }

  // ─── 总结卡片 ─────────────────────────────────────

  Widget _buildSummaryCard(SpeedPortfolio p, bool isPending, bool isActive, bool isSettled,
      double displayAmount, AppColorScheme colors) {
    final statusColor = isPending ? Colors.orange : (isSettled ? Colors.green : Colors.blue);
    final statusLabel = isPending ? '待买入' : (isActive ? '持仓中' : '已结算');

    // 6项指标计算逻辑（严格按业务规范）
    // 1.总投入 = 6只股票实际买入使用的总金额；未买入显示0
    final double totalInvested = isPending ? 0.0 : p.totalInvested;

    // 2.当前市值 = 6只股票按实时价格的持有股数对应价值总和；未买入显示0
    // 已结算时显示卖出回款总额
    double marketValue = 0.0;
    if (!isPending) {
      for (final pos in p.positions) {
        if (pos.status == SpeedPositionStatus.holding) {
          // 持仓中：用实时价计算
          final quote = _quotes[pos.stockCode];
          final livePrice = quote != null ? ((quote['price'] as num?)?.toDouble() ?? 0) : 0.0;
          final price = livePrice > 0 ? livePrice : pos.buyPrice;
          marketValue += price * pos.shares;
        } else if (pos.status == SpeedPositionStatus.settled) {
          // 已结算：returnAmount 是利润，市值 = 投入 + 利润 = 总回款
          marketValue += pos.investedAmount + (pos.returnAmount ?? 0);
        }
      }
    }

    // 3.浮动盈亏 = 当前市值 - 总投入；未买入显示0
    final double floatingPnl = isPending ? 0.0 : marketValue - totalInvested;

    // 4.持股数 = 6只（固定）
    final int stockCount = p.positions.length;

    // 5.盈利中 = 盈利只数/总持有只数；未买入显示0/0
    int profitableCount = 0;
    int totalHolding = 0;
    if (!isPending) {
      for (final pos in p.positions) {
        if (pos.status == SpeedPositionStatus.holding) {
          totalHolding++;
          // 用实时价判断是否盈利（无实时价回退买入价）
          final quote = _quotes[pos.stockCode];
          final livePrice = quote != null ? ((quote['price'] as num?)?.toDouble() ?? 0) : 0.0;
          final price = livePrice > 0 ? livePrice : pos.buyPrice;
          if (price * pos.shares > pos.investedAmount) profitableCount++;
        } else if (pos.status == SpeedPositionStatus.settled) {
          totalHolding++;
          // returnAmount 是利润，利润 > 0 即盈利
          if ((pos.returnAmount ?? 0) > 0) profitableCount++;
        }
      }
    }

    // 6.收益率 = 浮动盈亏 / 总投入 × 100%；未买入显示0%
    final double returnRate = (isPending || totalInvested <= 0) ? 0.0 : floatingPnl / totalInvested * 100;

    final bool isProfit = returnRate >= 0;
    final bool hasLiveQuotes = _quotes.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [statusColor.withOpacity(0.15), statusColor.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(children: [
        // 标题行
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
            child: Text(statusLabel, style: AppText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('T+1极速策略', style: AppText.caption.copyWith(color: colors.textHint)),
          const Spacer(),
        ]),
        const SizedBox(height: AppSpacing.lg),

        // 数据行1：总投入 / 当前市值 / 浮动盈亏
        Row(children: [
          _buildDataItem('总投入', isPending ? '¥0' : '¥${totalInvested.toStringAsFixed(0)}', colors.textSecondary, colors),
          _buildDataItem('当前市值', isPending ? '¥0' : '¥${marketValue.toStringAsFixed(0)}', colors.textSecondary, colors),
          _buildDataItem('浮动盈亏', isPending ? '¥0'
            : '${floatingPnl >= 0 ? "▲" : "▼"}¥${floatingPnl.abs().toStringAsFixed(0)}',
            isPending ? colors.textHint : (floatingPnl >= 0 ? colors.up : colors.down), colors),
        ]),
        const SizedBox(height: AppSpacing.md),

        // 数据行2：持股数 / 盈利中 / 收益率
        Row(children: [
          _buildDataItem('持股数', '$stockCount只', colors.textSecondary, colors),
          _buildDataItem('盈利中', isPending ? '0/0' : '$profitableCount/$totalHolding', colors.textSecondary, colors),
          _buildDataItem('收益率', isPending ? '0.00%'
            : '${isProfit ? "▲" : "▼"}${returnRate.abs().toStringAsFixed(2)}%',
            isPending ? colors.textHint : (isProfit ? colors.up : colors.down), colors),
        ]),
      ]),
    );
  }

  Widget _buildDataItem(String label, String value, Color valueColor, AppColorScheme colors) {
    return Expanded(
      child: Column(children: [
        Text(label, style: AppText.caption.copyWith(color: colors.textHint, fontSize: 11)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown,
          child: Text(value, style: AppText.body1.copyWith(color: valueColor, fontWeight: FontWeight.w800))),
      ]),
    );
  }

  // ─── 已结算横幅 ───────────────────────────────────

  Widget _buildSettledBanner(SpeedPortfolio p, AppColorScheme colors) {
    final avgRet = p.avgSettledReturn;
    final isProfit = avgRet >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isProfit ? colors.up.withOpacity(0.1) : colors.down.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: isProfit ? colors.up.withOpacity(0.3) : colors.down.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(isProfit ? Icons.emoji_events : Icons.trending_down, color: isProfit ? colors.up : colors.down, size: 24),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isProfit ? '组合已盈利结算' : '组合已亏损结算',
            style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
          Text('建仓日: ${p.createTime.month}/${p.createTime.day}', style: AppText.caption.copyWith(color: colors.textSecondary)),
        ])),
        Text('${isProfit ? "▲" : "▼"}${avgRet.abs().toStringAsFixed(2)}%',
          style: AppText.h2.copyWith(color: isProfit ? colors.up : colors.down, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ─── 待买入提示 ──────────────────────────────────

  Widget _buildPendingHint(AppColorScheme colors) {
    final buyDate = _p.buyDate;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text('${buyDate.month}月${buyDate.day}日 09:30 按实际开盘价自动买入',
          style: TextStyle(color: Colors.orange.shade700, fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  // ─── 交易时间线 ──────────────────────────────────

  Widget _buildTimeline(SpeedPortfolio p, AppColorScheme colors) {
    final buyDate = p.buyDate;
    final sellDate = p.sellDate;
    final isPending = p.status == SpeedPortfolioStatus.pending;
    final isActive  = p.status == SpeedPortfolioStatus.active;
    final isSettled = p.status == SpeedPortfolioStatus.settled;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('交易时间线', style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _timelineItem('选股日', '${p.createTime.month}/${p.createTime.day} 20:00',
          'A股游资×3 + 隔夜导航×3，每只¥20,000', colors, true),
        _timelineItem('买入日', '${buyDate.month}/${buyDate.day} 09:30',
          '按实际开盘价全额买入6只股票', colors, !isPending),
        _timelineItem('卖出日', '${sellDate.month}/${sellDate.day} 09:30',
          '全额卖出全部6只股票，完成日结', colors, isSettled),
      ]),
    );
  }

  Widget _timelineItem(String title, String time, String desc, AppColorScheme colors, bool active) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: active ? colors.speedInvestAccent : colors.textHint)),
          if (active) Container(width: 2, height: 28, color: colors.border),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
            color: active ? colors.textPrimary : colors.textHint, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(time, style: TextStyle(color: active ? colors.speedInvestAccent : colors.textHint, fontSize: 11)),
          Text(desc, style: TextStyle(color: active ? colors.textSecondary : colors.textHint, fontSize: 10)),
        ])),
      ]),
    );
  }

  // ─── 持仓明细卡片 ─────────────────────────────────

  Widget _buildPositionCard(SpeedPosition pos, int index, bool isPending, String source, AppColorScheme colors) {
    final isSettled = pos.status == SpeedPositionStatus.settled;
    final isActive  = !isPending && !isSettled;
    final pnl = pos.settledPnl;
    final rate = pos.returnRate ?? 0;
    final isProfit = pnl >= 0;

    // 实时行情数据
    final quote = _quotes[pos.stockCode];
    final currentPrice = quote != null ? ((quote['price'] as num?)?.toDouble() ?? 0) : 0.0;
    final dailyChangePct = quote != null ? ((quote['change_pct'] as num?)?.toDouble() ?? 0) : 0.0;
    final hasQuote = quote != null && currentPrice > 0;

    // 浮动盈亏计算
    double floatingPnl = 0;
    double floatingRate = 0;
    if (hasQuote && pos.investedAmount > 0) {
      floatingPnl = (currentPrice - pos.buyPrice) * pos.shares;
      floatingRate = floatingPnl / pos.investedAmount * 100;
    }
    final isFloatingProfit = floatingPnl >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题行
        Row(children: [
          // 序号
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: isPending ? Colors.orange.withOpacity(0.15) : colors.speedInvestAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: Text('$index', style: TextStyle(
              color: isPending ? Colors.orange : colors.speedInvestAccent,
              fontWeight: FontWeight.w800, fontSize: 12))),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 股票名称+代码
          Expanded(child: Row(children: [
            Text(pos.stockName, style: AppText.body2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(pos.stockCode, style: AppText.caption.copyWith(color: colors.textSecondary)),
          ])),
          // 来源标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.speedInvestAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(source, style: TextStyle(color: colors.speedInvestAccent, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 状态标识
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSettled ? Colors.green.withOpacity(0.15)
                   : isPending ? Colors.orange.withOpacity(0.15)
                   : Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(isSettled ? '已结算' : (isPending ? '待买入' : '持仓中'),
              style: TextStyle(
                color: isSettled ? Colors.green : (isPending ? Colors.orange : Colors.blue),
                fontWeight: FontWeight.w700, fontSize: 10)),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),

        // 数据行
        if (isPending) ...[
          // 待买入：计划投入 / 买入时间 / 预计股数
          Row(children: [
            _buildField('计划投入', '¥${pos.plannedAmount.toStringAsFixed(0)}', colors.textSecondary, colors),
            _buildField('买入时间', '明日09:30', Colors.orange, colors),
            _buildField('预计股数', '待建仓', colors.textHint, colors),
          ]),
        ] else if (isActive) ...[
          // 持仓中：详细数据（实时行情）
          // 第1行：建仓价 / 当前价 / 数量
          Row(children: [
            _buildField('建仓价', '¥${pos.buyPrice.toStringAsFixed(2)}', colors.textSecondary, colors),
            _buildField('当前价', hasQuote ? '¥${currentPrice.toStringAsFixed(2)}' : _loadingQuotes ? '获取中...' : '暂无行情',
              hasQuote ? (currentPrice >= pos.buyPrice ? colors.up : colors.down) : colors.textHint, colors),
            _buildField('数量', '${pos.shares}股', colors.textSecondary, colors),
          ]),
          // 第2行：日涨跌
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            _buildField('日涨跌', hasQuote
              ? '${dailyChangePct > 0 ? "▲" : "▼"}${dailyChangePct.abs().toStringAsFixed(2)}%'
              : _loadingQuotes ? '获取中...' : '——',
              hasQuote ? (dailyChangePct >= 0 ? colors.up : colors.down) : colors.textHint, colors),
            _buildField('创建', '${pos.buyTime!.month}/${pos.buyTime!.day} ${pos.buyTime!.hour}:${pos.buyTime!.minute.toString().padLeft(2, "0")}', colors.textHint, colors),
            const Spacer(),
          ]),
          // 第3行：投入 / 浮动盈亏 / 回报率
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            _buildField('投入', '¥${pos.investedAmount.toStringAsFixed(0)}', colors.textSecondary, colors),
            _buildField('浮动盈亏', hasQuote
              ? '${isFloatingProfit ? "▲" : "▼"}¥${floatingPnl.abs().toStringAsFixed(0)}'
              : _loadingQuotes ? '计算中...' : '——',
              hasQuote ? (isFloatingProfit ? colors.up : colors.down) : colors.textHint, colors),
            _buildField('回报率', hasQuote
              ? '${isFloatingProfit ? "▲" : "▼"}${floatingRate.abs().toStringAsFixed(2)}%'
              : _loadingQuotes ? '计算中...' : '——',
              hasQuote ? (isFloatingProfit ? colors.up : colors.down) : colors.textHint, colors),
          ]),
        ] else ...[
          // 已结算：显示实际交易数据
          Row(children: [
            _buildField('建仓价', '¥${pos.buyPrice.toStringAsFixed(2)}', colors.textSecondary, colors),
            _buildField('数量', '${pos.shares}股', colors.textSecondary, colors),
            _buildField('投入', '¥${pos.investedAmount.toStringAsFixed(0)}', colors.textSecondary, colors),
          ]),
        ],
        if (isSettled) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            _buildField('卖出价', '¥${(pos.sellPrice ?? 0).toStringAsFixed(2)}', colors.textPrimary, colors),
            _buildField('盈亏', '${pnl >= 0 ? "▲" : "▼"}¥${pnl.abs().toStringAsFixed(0)}',
              isProfit ? colors.up : colors.down, colors),
            _buildField('回报率', '${(rate * 100) >= 0 ? "▲" : "▼"}${(rate * 100).abs().toStringAsFixed(2)}%',
              isProfit ? colors.up : colors.down, colors),
          ]),
        ],
      ]),
    );
  }

  Widget _buildField(String label, String value, Color valueColor, AppColorScheme colors) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.caption.copyWith(color: colors.textHint, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}
