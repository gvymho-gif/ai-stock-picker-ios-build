/// 搜索栏组件 - 首页搜索输入框
///
/// Material Design 3 风格，深色主题适配

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final String hintText;

  const SearchBarWidget({
    Key? key,
    required this.controller,
    required this.onSearch,
    required this.onFilter,
    this.hintText = '输入代码/名称搜索，如 600519、茅台、AAPL',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.border),
        ),
        child: TextField(
          controller: controller,
          style: AppText.body1.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppText.body2.copyWith(color: AppColors.textHint),
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.filter_list,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: onFilter,
                  tooltip: '智能筛选',
                  padding: EdgeInsets.zero,
                ),
                const Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            suffixIcon: Container(
              margin: const EdgeInsets.all(AppSpacing.xs),
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  onTap: onSearch,
                  child: Center(
                    widthFactor: 2,
                    child: Text(
                      '搜索',
                      style: AppText.body2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
        ),
      ),
    );
  }
}
