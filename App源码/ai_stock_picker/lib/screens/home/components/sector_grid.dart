/// 板块网格组件 - 展示热门板块
///
/// 十二宫格布局，按市场分类展示

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class SectorGridWidget extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> sectors;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onSectorTap;

  const SectorGridWidget({
    Key? key,
    required this.sectors,
    required this.loading,
    required this.onRefresh,
    required this.onSectorTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final markets = ['A股', '港股', '美股'];
    final colors = [AppColors.up, AppColors.warning, AppColors.primary];
    final icons = [Icons.show_chart, Icons.trending_up, Icons.public];

    return Column(
      children: markets.asMap().entries.map((entry) {
        final idx = entry.key;
        final market = entry.value;
        final marketSectors = sectors[market] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 市场标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(icons[idx], size: 16, color: colors[idx]),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    market,
                    style: AppText.body2.copyWith(
                      color: colors[idx],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onRefresh,
                    child: Icon(
                      Icons.refresh,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),

            // 板块网格
            loading
                ? SizedBox(
                    height: 72,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: List.generate(4, (i) {
                      if (i >= marketSectors.length) {
                        return Expanded(
                          child: _SectorCell(
                            sector: null,
                            market: market,
                            onTap: null,
                          ),
                        );
                      }
                      return Expanded(
                        child: _SectorCell(
                          sector: marketSectors[i],
                          market: market,
                          onTap: () => onSectorTap(marketSectors[i]),
                        ),
                      );
                    }),
                  ),
            const SizedBox(height: AppSpacing.xs),
          ],
        );
      }).toList(),
    );
  }
}

class _SectorCell extends StatelessWidget {
  final Map<String, dynamic>? sector;
  final String market;
  final VoidCallback? onTap;

  const _SectorCell({
    required this.sector,
    required this.market,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (sector == null) {
      return GestureDetector(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                '--',
                style: AppText.caption.copyWith(color: AppColors.textHint),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '--',
                style: AppText.caption.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final name = sector!['name']?.toString() ?? '';
    final chg = sector!['change_pct'] as double? ?? 0.0;
    final isUp = chg >= 0;
    final chgColor = isUp ? AppColors.up : AppColors.down;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60, // 固定高度确保4个Cell对齐
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: chgColor.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              name,
              style: AppText.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            Text(
              '${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%',
              style: AppText.caption.copyWith(
                color: chgColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
