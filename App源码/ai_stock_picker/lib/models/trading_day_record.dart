/// 交易日记录模型
/// 用于云端存储和展示每个交易日的选股表现

import '../utils/trading_day_utils.dart';

class TradingDayRecord {
  final String date; // 交易日期 YYYY-MM-DD
  final List<String> stockCodes; // 6只股票代码
  final List<String> stockNames; // 6只股票名称（可选，用于展示）
  final List<double> stockChanges; // 每只股票当天的涨跌幅百分比
  final double totalChangePercent; // 总涨跌幅百分比（6只涨跌相加）
  final double avgChangePercent; // 平均涨跌幅百分比（总涨跌 / 6）
  final String? notes; // 备注（可选）
  final String? reviewContent; // 极智复盘分析内容（可选）
  final String? reviewGeneratedAt; // 复盘生成时间（可选）

  TradingDayRecord({
    required this.date,
    required this.stockCodes,
    this.stockNames = const [],
    this.stockChanges = const [],
    required this.totalChangePercent,
    required this.avgChangePercent,
    this.notes,
    this.reviewContent,
    this.reviewGeneratedAt,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'stockCodes': stockCodes,
    'stockNames': stockNames,
    'stockChanges': stockChanges,
    'totalChangePercent': totalChangePercent,
    'avgChangePercent': avgChangePercent,
    'notes': notes,
    'reviewContent': reviewContent,
    'reviewGeneratedAt': reviewGeneratedAt,
  };

  factory TradingDayRecord.fromJson(Map<String, dynamic> json) {
    return TradingDayRecord(
      date: json['date'] ?? '',
      stockCodes: List<String>.from(json['stockCodes'] ?? []),
      stockNames: List<String>.from(json['stockNames'] ?? []),
      stockChanges: List<double>.from((json['stockChanges'] ?? []).map((e) => (e ?? 0.0).toDouble())),
      totalChangePercent: (json['totalChangePercent'] ?? 0.0).toDouble(),
      avgChangePercent: (json['avgChangePercent'] ?? 0.0).toDouble(),
      notes: json['notes'],
      reviewContent: json['reviewContent'],
      reviewGeneratedAt: json['reviewGeneratedAt'],
    );
  }

  /// 从ExpertPerformance转换
  factory TradingDayRecord.fromExpertPerformance(
    String date,
    List<String> codes,
    List<String> names,
    List<double> changes,
    double totalChange,
    double avgChange,
  ) {
    return TradingDayRecord(
      date: date,
      stockCodes: codes,
      stockNames: names,
      stockChanges: changes,
      totalChangePercent: totalChange,
      avgChangePercent: avgChange,
    );
  }

  /// 格式化显示日期 - 简化为MM-DD格式，确保单行显示
  String get displayDate {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        // 返回 MM-DD 格式，更短不易换行
        return '${parts[1]}-${parts[2]}';
      }
      return date;
    } catch (_) {
      return date;
    }
  }

  /// 完整日期显示（用于详情弹窗）
  String get fullDisplayDate {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        return '${parts[0]}/${parts[1]}/${parts[2]}';
      }
      return date;
    } catch (_) {
      return date;
    }
  }

  /// 涨跌状态
  bool get isPositive => avgChangePercent >= 0;
}

/// 交易统计数据
class TradingStatistics {
  final int totalDays; // 总交易日数
  final double cumulativeReturn; // 累计回报率（所有平均涨跌累加）
  final double dailyAvgReturn; // 日均回报率（累计 / 天数）
  final int positiveDays; // 盈利天数
  final int negativeDays; // 亏损天数
  final double maxSingleDayGain; // 单日最大涨幅
  final double maxSingleDayLoss; // 单日最大跌幅
  final String maxGainDate; // 最大涨幅日期
  final String maxLossDate; // 最大跌幅日期

  TradingStatistics({
    required this.totalDays,
    required this.cumulativeReturn,
    required this.dailyAvgReturn,
    required this.positiveDays,
    required this.negativeDays,
    required this.maxSingleDayGain,
    required this.maxSingleDayLoss,
    required this.maxGainDate,
    required this.maxLossDate,
  });

  /// 从记录列表计算统计
  /// ★ 非交易时段（20:00-09:19）当天的记录按0计算
  /// ★ 固定金额每日投资：简单算术累计（非复利滚动）
  factory TradingStatistics.fromRecords(List<TradingDayRecord> records) {
    if (records.isEmpty) {
      return TradingStatistics(
        totalDays: 0,
        cumulativeReturn: 0.0,
        dailyAvgReturn: 0.0,
        positiveDays: 0,
        negativeDays: 0,
        maxSingleDayGain: 0.0,
        maxSingleDayLoss: 0.0,
        maxGainDate: '',
        maxLossDate: '',
      );
    }

    // ★ 判断当前是否在非交易时段（20:00-09:30）
    final now = DateTime.now();
    final todayStr = TradingDayUtils.formatDate(now);

    // ★ 按日期排序后计算
    final sorted = List<TradingDayRecord>.from(records)
      ..sort((a, b) => a.date.compareTo(b.date));

    // ★ 固定金额投资：简单算术累计（每天独立，不滚动本金）
    double totalCumulative = 0.0; // 累计收益 = 所有日均涨跌幅之和
    double totalSum = 0.0;        // 日收益总和（用于算平均）

    int positive = 0;
    int negative = 0;
    double maxGain = 0.0;
    double maxLoss = 0.0;
    String gainDate = '';
    String lossDate = '';

    for (var record in sorted) {
      // ★ 如果记录尚未到下一个交易日的确认时间，按0计算
      double dailyChangePercent = TradingDayUtils.shouldRecordShowZero(record.date)
          ? 0.0
          : record.avgChangePercent;

      totalCumulative += dailyChangePercent;
      totalSum += dailyChangePercent;

      // 统计单日涨跌
      if (dailyChangePercent > 0) {
        positive++;
        if (dailyChangePercent > maxGain) {
          maxGain = dailyChangePercent;
          gainDate = record.date;
        }
      } else if (dailyChangePercent < 0) {
        negative++;
        if (dailyChangePercent < maxLoss) {
          maxLoss = dailyChangePercent;
          lossDate = record.date;
        }
      }
    }

    return TradingStatistics(
      totalDays: records.length,
      cumulativeReturn: totalCumulative,         // 简单累计（非复利）
      dailyAvgReturn: totalSum / records.length, // 简单算术平均
      positiveDays: positive,
      negativeDays: negative,
      maxSingleDayGain: maxGain,
      maxSingleDayLoss: maxLoss,
      maxGainDate: gainDate,
      maxLossDate: lossDate,
    );
  }

  /// 胜率百分比
  double get winRate => totalDays > 0 ? (positiveDays / totalDays * 100) : 0.0;

  /// 格式化显示
  String get formattedCumulativeReturn => '${cumulativeReturn >= 0 ? '+' : ''}${cumulativeReturn.toStringAsFixed(2)}%';
  String get formattedDailyAvgReturn => '${dailyAvgReturn >= 0 ? '+' : ''}${dailyAvgReturn.toStringAsFixed(2)}%';
  String get formattedWinRate => '${winRate.toStringAsFixed(1)}%';
}
