/// 样式定义 - 统一管理APP中的颜色、图标等样式
///
/// 使用统一的设计系统，便于全局修改

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 行动建议样式
class ActionStyle {
  /// 获取行动建议的颜色
  static Color getColor(String action) => AppColors.getActionColor(action);

  /// 获取行动建议的图标
  static IconData getIcon(String action) {
    switch (action) {
      case 'buy': return Icons.trending_up;
      case 'avoid': return Icons.trending_down;
      case 'hold': return Icons.remove;
      default: return Icons.remove;
    }
  }

  /// 行动建议的中文标签
  static String getLabel(String action) {
    switch (action) {
      case 'buy': return '买入';
      case 'avoid': return '回避';
      case 'hold': return '观望';
      default: return '观望';
    }
  }
}

/// 趋势样式
class TrendStyle {
  static Color getColor(String trend) => AppColors.getTrendColor(trend);

  static String getLabel(String trend) {
    switch (trend) {
      case 'bullish': return '看多';
      case 'bearish': return '看空';
      case 'neutral': return '中性';
      default: return '中性';
    }
  }
}

/// 根据评分获取颜色
Color getScoreColor(double score) => AppColors.getScoreColor(score);

/// 价格涨跌颜色 (中国: 红涨绿跌)
Color getPriceColor(double changePct) => AppColors.getPriceColor(changePct);

/// 市场名称映射
String getMarketName(String market) {
  switch (market) {
    case 'A': return 'A股';
    case 'HK': return '港股';
    case 'US': return '美股';
    case 'ALL': return '全部';
    default: return market;
  }
}

/// 格式化大数字 (亿/万亿)
String formatBigNumber(dynamic num) {
  if (num == null) return 'N/A';
  double value;
  if (num is int) {
    value = num.toDouble();
  } else if (num is double) {
    value = num;
  } else {
    return num.toString();
  }
  if (value >= 1e12) return '${(value / 1e12).toStringAsFixed(1)}万亿';
  if (value >= 1e8) return '${(value / 1e8).toStringAsFixed(1)}亿';
  if (value >= 1e4) return '${(value / 1e4).toStringAsFixed(1)}万';
  return value.toStringAsFixed(2);
}
