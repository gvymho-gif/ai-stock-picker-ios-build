/// 股票卡片 - 年轻化设计
///
/// 深蓝紫渐变 + 玻璃态效果

import 'package:flutter/material.dart';
import '../models/stock_model.dart';
import '../theme/app_theme.dart';
import 'styles.dart';

class StockCard extends StatelessWidget {
  final StockRecommendation stock;
  final VoidCallback onTap;

  const StockCard({Key? key, required this.stock, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final actionColor = ActionStyle.getColor(stock.action);
    final scoreColor = AppColors.getScoreColor(stock.score);
    final priceColor = AppColors.getPriceColor(stock.changePct);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border.withOpacity(0.5)),
        boxShadow: AppShadow.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(children: [
              // 第一行: 名称 + 行动标签
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stock.name, style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(stock.symbol, style: AppText.caption.copyWith(color: colors.textHint)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [actionColor.withOpacity(0.25), actionColor.withOpacity(0.1)]),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: actionColor.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ActionStyle.getIcon(stock.action), size: 16, color: actionColor),
                    const SizedBox(width: AppSpacing.xs),
                    Text(stock.actionLabel, style: AppText.body2.copyWith(color: actionColor, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: AppSpacing.lg),

              // 第二行: 价格 + 涨跌 + 评分
              Row(children: [
                Text('¥${stock.price.toStringAsFixed(2)}', style: AppText.price.copyWith(color: priceColor)),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: priceColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text('${stock.changePct >= 0 ? "+" : ""}${stock.changePct.toStringAsFixed(2)}%',
                    style: AppText.changePct.copyWith(color: priceColor)),
                ),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('AI评分', style: AppText.hint.copyWith(color: colors.textHint)),
                  Text(stock.scoreLabel, style: AppText.score.copyWith(color: scoreColor)),
                ]),
              ]),
              const SizedBox(height: AppSpacing.lg),

              // 第三行: 胜率 + 趋势
              Row(children: [
                _buildChip('盈利率', stock.winRateLabel, colors.primary),
                const SizedBox(width: AppSpacing.md),
                _buildChip('趋势', stock.trendLabel, TrendStyle.getColor(stock.trend)),
                const Spacer(),
                if (stock.dataSource == 'offline')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text('离线', style: AppText.hint.copyWith(color: colors.textHint)),
                  ),
                if (stock.risk.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(Icons.warning_amber, size: 16, color: colors.warning)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: AppText.caption.copyWith(color: AppColors.textHint)),
      Text(value, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    ]);
  }
}
