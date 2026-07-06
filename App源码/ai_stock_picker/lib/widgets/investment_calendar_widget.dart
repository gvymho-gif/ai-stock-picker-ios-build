/// 投资月历组件
/// 4×3网格布局，显示12个月份及其对应板块
/// 实时获取每个板块股票数据，计算真实平均涨跌、上涨家数、下跌家数

import 'package:flutter/material.dart';
import '../models/investment_calendar.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../services/local_data_service.dart';
import '../screens/sector_stocks_screen.dart';

class InvestmentCalendarWidget extends StatefulWidget {
  final LocalDataService api;

  const InvestmentCalendarWidget({
    Key? key,
    required this.api,
  }) : super(key: key);

  @override
  State<InvestmentCalendarWidget> createState() => _InvestmentCalendarWidgetState();
}

class _InvestmentCalendarWidgetState extends State<InvestmentCalendarWidget> {
  bool _loading = true;
  Map<String, double> _sectorChanges = {};
  Map<String, Map<String, dynamic>> _sectorStats = {}; // 新增：存储每个板块的详细统计

  @override
  void initState() {
    super.initState();
    _loadSectorChanges();
  }

  Future<void> _loadSectorChanges() async {
    try {
      // 调用新方法获取所有板块的实时数据
      final sectorData = await widget.api.fetchAllCalendarSectors();
      
      final changes = <String, double>{};
      
      // 提取每个板块的平均涨跌幅
      sectorData.forEach((sectorName, stats) {
        final avgChange = stats['avgChange'] as double? ?? 0.0;
        changes[sectorName] = avgChange;
      });

      if (mounted) {
        setState(() {
          _sectorChanges = changes;
          _sectorStats = sectorData;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4×3 月历网格
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              // 第1行: 1-4月
              _buildMonthRow([0, 1, 2, 3]),
              Divider(height: 1, color: colors.border),
              // 第2行: 5-8月
              _buildMonthRow([4, 5, 6, 7]),
              Divider(height: 1, color: colors.border),
              // 第3行: 9-12月
              _buildMonthRow([8, 9, 10, 11]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthRow(List<int> indices) {
    return Row(
      children: indices.map((index) {
        if (index < InvestmentCalendarData.calendarData.length) {
          return Expanded(
            child: _buildMonthCell(
              InvestmentCalendarData.calendarData[index],
            ),
          );
        }
        return const Expanded(child: SizedBox());
      }).toList(),
    );
  }

  Widget _buildMonthCell(MonthSectorData monthData) {
    final colors = AppColors.of(context);
    final isCurrentMonth = monthData.month == DateTime.now().month;

    return Material(
      color: isCurrentMonth
        ? colors.primary.withOpacity(0.05)
        : Colors.transparent,
      child: InkWell(
        onTap: () => _showMonthDetail(monthData),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 月份标题
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isCurrentMonth
                    ? colors.primary.withOpacity(0.15)
                    : colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  monthData.monthName,
                  style: AppText.caption.copyWith(
                    color: isCurrentMonth ? colors.primary : colors.textSecondary,
                    fontWeight: isCurrentMonth ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // 两个板块
              ...monthData.sectors.map((sector) {
                final change = _sectorChanges[sector.name] ?? 0;
                final isUp = change >= 0;
                final changeColor = isUp ? colors.up : colors.down;

                // 获取统计数据
                final stats = _sectorStats[sector.name];
                final upCount = stats?['upCount'] as int? ?? 0;
                final downCount = stats?['downCount'] as int? ?? 0;
                final validCount = stats?['validCount'] as int? ?? 0;

                // 月涨幅
                final monthChange = _safeDouble(stats?['avgMonthChange']);
                final isMonthUp = monthChange >= 0;
                final monthChangeColor = isMonthUp ? colors.up : colors.down;

                return Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: changeColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: changeColor.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sector.displayName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // 当天涨跌幅（上行）
                      Text(
                        '日${isUp ? "+" : ""}${change.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: changeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 1),
                      // 月涨幅（下行，当月累计）
                      Text(
                        '月${isMonthUp ? "+" : ""}${monthChange.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: monthChangeColor.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _showMonthDetail(MonthSectorData monthData) {
    final colors = AppColors.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动条
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                
                // 标题
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors.primaryGradient),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(Icons.calendar_month, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${monthData.monthName}投资方向',
                      style: AppText.h2.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                
                // 板块列表
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: monthData.sectors.length,
                    itemBuilder: (context, index) {
                      final sector = monthData.sectors[index];
                      final change = _sectorChanges[sector.name] ?? 0;
                      final isUp = change >= 0;
                      final changeColor = isUp ? colors.up : colors.down;
                      
                      // 获取统计数据
                      final stats = _sectorStats[sector.name];
                      final upCount = stats?['upCount'] as int? ?? 0;
                      final downCount = stats?['downCount'] as int? ?? 0;
                      final validCount = stats?['validCount'] as int? ?? 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: colors.border),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            onTap: () => _openSectorDetail(monthData.monthName, sector),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sector.displayName,
                                          style: AppText.body1.copyWith(
                                            color: colors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        // 显示上涨/下跌家数
                                        if (validCount > 0)
                                          Text(
                                            '↑$upCount ↓$downCount · 共$validCount只',
                                            style: AppText.caption.copyWith(
                                              color: colors.textHint,
                                            ),
                                          )
                                        else
                                          Text(
                                            sector.keywords.split(',').take(3).join(' · '),
                                            style: AppText.caption.copyWith(
                                              color: colors.textHint,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: changeColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Text(
                                      '${isUp ? "+" : ""}${change.toStringAsFixed(2)}%',
                                      style: AppText.body2.copyWith(
                                        color: changeColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: colors.textHint,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSectorDetail(String monthName, SectorInfo sector) {
    Navigator.pop(context); // 关闭底部弹窗
    
    // 跳转到板块股票列表页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SectorStocksScreen(
          monthName: monthName,
          sector: sector,
        ),
      ),
    );
  }

  double _safeDouble(dynamic val) {
    if (val == null) return 0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }
}
