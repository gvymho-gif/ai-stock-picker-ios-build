/// 已结算记录历史页
///
/// 通用页面，热点投资和轻量投资共用。
/// 通过构造函数注入 service、accentColor、accentGradient 区分两模块。
/// 将 _calendarArchive 按 portfolioName 分组聚合为 _SettledGroup 列表，
/// 支持展开/收起查看每只持仓详情，展示端去重保护。

import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/app_text.dart';
import '../services/hot_investment_service.dart';

/// 分组聚合模型（仅 UI 层使用）
class _SettledGroup {
  final String portfolioName;
  final List<Map<String, dynamic>> positions;
  final double totalInvested;
  final double totalReturn;
  final double avgReturnRate;
  final String? settledDate;

  _SettledGroup({
    required this.portfolioName,
    required this.positions,
    required this.totalInvested,
    required this.totalReturn,
    required this.avgReturnRate,
    this.settledDate,
  });
}

class SettlementHistoryScreen extends StatefulWidget {
  final HotInvestmentService service;
  final String moduleTitle;
  final Color accentColor;
  final List<Color> accentGradient;

  const SettlementHistoryScreen({
    Key? key,
    required this.service,
    required this.moduleTitle,
    required this.accentColor,
    required this.accentGradient,
  }) : super(key: key);

  @override
  State<SettlementHistoryScreen> createState() => _SettlementHistoryScreenState();
}

class _SettlementHistoryScreenState extends State<SettlementHistoryScreen> {
  List<_SettledGroup> _groups = [];
  final Set<int> _expandedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 展示端去重+分组聚合
  void _loadData() {
    final archive = widget.service.calendarArchive;
    final seenKeys = <String>{};
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final entry in archive) {
      final name = entry['portfolioName'] as String? ?? '';
      final code = entry['stockCode'] as String? ?? '';
      final sellTime = entry['sellTime'] as String? ?? '';
      if (name.isEmpty || code.isEmpty || sellTime.isEmpty) continue;

      // 展示端去重
      final dedupKey = '$name|$code|$sellTime';
      if (seenKeys.contains(dedupKey)) continue;
      seenKeys.add(dedupKey);

      grouped.putIfAbsent(name, () => []).add(entry);
    }

    final now = DateTime.now();
    final result = <_SettledGroup>[];

    for (final entry in grouped.entries) {
      double totalInvested = 0;
      double totalReturn = 0;
      String? latestSellTime;

      for (final pos in entry.value) {
        totalInvested += (pos['investedAmount'] as num?)?.toDouble() ?? 0;
        totalReturn += (pos['returnAmount'] as num?)?.toDouble() ?? 0;
        final st = pos['sellTime'] as String?;
        if (st != null && (latestSellTime == null || st.compareTo(latestSellTime) > 0)) {
          latestSellTime = st;
        }
      }

      result.add(_SettledGroup(
        portfolioName: entry.key,
        positions: entry.value,
        totalInvested: totalInvested,
        totalReturn: totalReturn,
        avgReturnRate: totalInvested > 0 ? totalReturn / totalInvested : 0,
        settledDate: latestSellTime != null ? _fmtSettleDate(latestSellTime) : null,
      ));
    }

    // 按 settledDate 倒序
    result.sort((a, b) {
      if (a.settledDate == null && b.settledDate == null) return 0;
      if (a.settledDate == null) return 1;
      if (b.settledDate == null) return -1;
      return b.settledDate!.compareTo(a.settledDate!);
    });

    setState(() => _groups = result);
  }

  // ========== 格式化工具 ==========

  static String _fmtAmount(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(2)}w';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }

  static String _fmtPrice(double p) {
    if (p == 0) return '—';
    if (p >= 100) return p.toStringAsFixed(0);
    return p.toStringAsFixed(2);
  }

  static String _fmtSettleDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.substring(0, 10);
    }
  }

  static String _fmtReturnPct(double rate) {
    return '${(rate * 100).toStringAsFixed(2)}%';
  }

  static String _fmtStatusLabel(String status) {
    switch (status) {
      case 'stopProfit':
        return '止盈';
      case 'stopLoss':
        return '止损';
      case 'timeLiquidated':
        return '清仓';
      default:
        return status;
    }
  }

  static Color? _statusColor(String status, AppColorScheme colors) {
    switch (status) {
      case 'stopProfit':
        return colors.up;
      case 'stopLoss':
        return colors.down;
      case 'timeLiquidated':
        return colors.textHint;
      default:
        return colors.textHint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('已结算记录', style: AppText.h2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient))),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
        child: _groups.isEmpty ? _buildEmptyState(colors) : _buildList(colors),
      ),
    );
  }

  Widget _buildEmptyState(AppColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 64, color: widget.accentColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('暂无已结算记录',
            style: AppText.h3.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 8),
          Text('投资组合止盈/止损/清仓后会自动归档到此处',
            textAlign: TextAlign.center,
            style: AppText.body2.copyWith(color: colors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _buildList(AppColorScheme colors) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _groups.length,
      itemBuilder: (context, index) => _buildGroupCard(_groups[index], index, colors),
    );
  }

  Widget _buildGroupCard(_SettledGroup group, int index, AppColorScheme colors) {
    final isExpanded = _expandedIndices.contains(index);
    final gain = group.totalReturn >= 0;
    final trendIcon = gain ? Icons.trending_up : Icons.trending_down;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            gain
                ? colors.up.withOpacity(0.05)
                : colors.down.withOpacity(0.05),
            colors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: gain
              ? colors.up.withOpacity(0.15)
              : colors.down.withOpacity(0.15),
        ),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedIndices.remove(index);
              } else {
                _expandedIndices.add(index);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(children: [
              // 盈亏图标
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gain
                        ? [colors.up.withOpacity(0.2), colors.up.withOpacity(0.05)]
                        : [colors.down.withOpacity(0.2), colors.down.withOpacity(0.05)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(trendIcon, color: gain ? colors.up : colors.down, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              // 组合信息
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(group.portfolioName,
                    style: AppText.body1.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${group.positions.length}只股票 · ${group.settledDate ?? "日期未知"}',
                    style: AppText.caption.copyWith(color: colors.textSecondary, fontSize: 11),
                  ),
                ]),
              ),
              const SizedBox(width: AppSpacing.sm),
              // 盈亏数据
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '${gain ? "+" : ""}${_fmtAmount(group.totalReturn)}',
                  style: TextStyle(
                    color: gain ? colors.up : colors.down,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${gain ? "+" : ""}${_fmtReturnPct(group.avgReturnRate)}',
                  style: TextStyle(
                    color: gain ? colors.up : colors.down,
                    fontSize: 11,
                  ),
                ),
              ]),
              const SizedBox(width: AppSpacing.sm),
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.arrow_forward_ios, size: 14, color: colors.textSecondary),
              ),
            ]),
          ),
        ),
        // 展开的持仓详情
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildPositionDetails(group, colors),
          crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ]),
    );
  }

  Widget _buildPositionDetails(_SettledGroup group, AppColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        // 表头
        Row(children: [
          Expanded(flex: 3, child: Text('股票', style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('数量', style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600))),
          Expanded(flex: 3, child: Text('建仓→结算', style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('盈亏', textAlign: TextAlign.right,
              style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: AppSpacing.sm),
        // 持仓行
        ...group.positions.map((pos) => _buildPositionRow(pos, colors)),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        // 合计
        Row(children: [
          Text('投入 ${_fmtAmount(group.totalInvested)}',
            style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('盈亏 ${group.totalReturn >= 0 ? "+" : ""}${_fmtAmount(group.totalReturn)}',
            style: TextStyle(
              color: group.totalReturn >= 0 ? colors.up : colors.down,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            )),
        ]),
      ]),
    );
  }

  Widget _buildPositionRow(Map<String, dynamic> pos, AppColorScheme colors) {
    final stockName = pos['stockName'] as String? ?? '';
    final shares = (pos['shares'] as num?)?.toInt() ?? 0;
    final buyPrice = (pos['buyPrice'] as num?)?.toDouble() ?? 0;
    final sellPrice = (pos['sellPrice'] as num?)?.toDouble() ?? 0;
    final returnAmount = (pos['returnAmount'] as num?)?.toDouble() ?? 0;
    final returnRate = (pos['returnRate'] as num?)?.toDouble() ?? 0;
    final statusStr = pos['status'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(flex: 3, child: Row(children: [
          Flexible(child: Text(stockName,
            style: AppText.body2.copyWith(color: colors.textPrimary, fontSize: 11),
            overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor(statusStr, colors)?.withOpacity(0.18) ?? Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_fmtStatusLabel(statusStr),
              style: TextStyle(color: _statusColor(statusStr, colors), fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        ])),
        Expanded(flex: 2, child: Text('$shares',
          style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 11))),
        Expanded(flex: 3, child: Text('${_fmtPrice(buyPrice)} → ${_fmtPrice(sellPrice)}',
          style: AppText.body2.copyWith(color: colors.textSecondary, fontSize: 11))),
        Expanded(flex: 2, child: Text(
          '${returnAmount >= 0 ? "+" : ""}${_fmtAmount(returnAmount)} (${_fmtReturnPct(returnRate)})',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: returnAmount >= 0 ? colors.up : colors.down,
            fontWeight: FontWeight.w600,
            fontSize: 10,
          )),
        ),
      ]),
    );
  }
}
