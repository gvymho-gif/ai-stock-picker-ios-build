/// 筛选条件模型
/// 支持多市场（A股全功能，港股/美股基础版）的股票筛选

import 'package:flutter/material.dart';
import '../services/foreign_holder_service.dart';

class FilterCriteria {
  /// 市场: 'A' = A股, 'HK' = 港股, 'US' = 美股
  final String market;

  // ============ 估值筛选 ============
  /// PE市盈率区间 (0-100)
  final RangeValues? peRange;
  /// PB市净率区间 (0-20)
  final RangeValues? pbRange;

  // ============ 盈利筛选（仅A股）============
  /// ROE净资产收益率区间 (0-50%)
  final RangeValues? roeRange;
  /// 营收增速区间 (-50% ~ 200%)
  final RangeValues? revenueGrowthRange;
  /// 净利润增速区间 (-50% ~ 200%)
  final RangeValues? profitGrowthRange;

  // ============ 分红筛选（仅A股）============
  /// 股息率区间 (0-10%)
  final RangeValues? dividendYieldRange;

  // ============ 规模筛选 ============
  /// 总市值级别: 'small'(<100亿), 'mid'(100-500亿), 'large'(>500亿), 'all'(不限)
  final String? marketCapLevel;
  /// 流通市值级别
  final String? floatMarketCapLevel;
  /// 最小上市年限 (排除次新股)
  final int? minListingYears;

  // ============ 技术面筛选 ============
  /// 换手率区间 (0-30%)
  final RangeValues? turnoverRange;
  /// 距52周高点百分比区间 (0-100%，越小表示离高点越远)
  final RangeValues? pctFrom52WeekHigh;
  /// 涨跌幅区间 (-10% ~ 20%)
  final RangeValues? changePctRange;
  /// 成交量区间 (万手, 0-10000万手)
  final RangeValues? volumeRange;

  // ============ 外资持股筛选（仅A股）============
  /// 外资持股筛选条件
  final ForeignHolderFilter? foreignHolderFilter;

  const FilterCriteria({
    this.market = 'A',
    this.peRange,
    this.pbRange,
    this.roeRange,
    this.revenueGrowthRange,
    this.profitGrowthRange,
    this.dividendYieldRange,
    this.marketCapLevel,
    this.floatMarketCapLevel,
    this.minListingYears,
    this.turnoverRange,
    this.pctFrom52WeekHigh,
    this.changePctRange,
    this.volumeRange,
    this.foreignHolderFilter,
  });

  /// 复制并修改
  FilterCriteria copyWith({
    String? market,
    RangeValues? peRange,
    RangeValues? pbRange,
    RangeValues? roeRange,
    RangeValues? revenueGrowthRange,
    RangeValues? profitGrowthRange,
    RangeValues? dividendYieldRange,
    String? marketCapLevel,
    String? floatMarketCapLevel,
    int? minListingYears,
    RangeValues? turnoverRange,
    RangeValues? pctFrom52WeekHigh,
    RangeValues? changePctRange,
    RangeValues? volumeRange,
    ForeignHolderFilter? foreignHolderFilter,
    bool clearPeRange = false,
    bool clearPbRange = false,
    bool clearRoeRange = false,
    bool clearRevenueGrowthRange = false,
    bool clearProfitGrowthRange = false,
    bool clearDividendYieldRange = false,
    bool clearMarketCapLevel = false,
    bool clearFloatMarketCapLevel = false,
    bool clearMinListingYears = false,
    bool clearTurnoverRange = false,
    bool clearPctFrom52WeekHigh = false,
    bool clearChangePctRange = false,
    bool clearVolumeRange = false,
    bool clearForeignHolderFilter = false,
  }) {
    return FilterCriteria(
      market: market ?? this.market,
      peRange: clearPeRange ? null : (peRange ?? this.peRange),
      pbRange: clearPbRange ? null : (pbRange ?? this.pbRange),
      roeRange: clearRoeRange ? null : (roeRange ?? this.roeRange),
      revenueGrowthRange: clearRevenueGrowthRange ? null : (revenueGrowthRange ?? this.revenueGrowthRange),
      profitGrowthRange: clearProfitGrowthRange ? null : (profitGrowthRange ?? this.profitGrowthRange),
      dividendYieldRange: clearDividendYieldRange ? null : (dividendYieldRange ?? this.dividendYieldRange),
      marketCapLevel: clearMarketCapLevel ? null : (marketCapLevel ?? this.marketCapLevel),
      floatMarketCapLevel: clearFloatMarketCapLevel ? null : (floatMarketCapLevel ?? this.floatMarketCapLevel),
      minListingYears: clearMinListingYears ? null : (minListingYears ?? this.minListingYears),
      turnoverRange: clearTurnoverRange ? null : (turnoverRange ?? this.turnoverRange),
      pctFrom52WeekHigh: clearPctFrom52WeekHigh ? null : (pctFrom52WeekHigh ?? this.pctFrom52WeekHigh),
      changePctRange: clearChangePctRange ? null : (changePctRange ?? this.changePctRange),
      volumeRange: clearVolumeRange ? null : (volumeRange ?? this.volumeRange),
      foreignHolderFilter: clearForeignHolderFilter ? null : (foreignHolderFilter ?? this.foreignHolderFilter),
    );
  }

  /// 重置所有筛选条件
  FilterCriteria reset() {
    return FilterCriteria(market: market);
  }

  /// 是否有任何筛选条件
  bool get hasFilters {
    return peRange != null ||
        pbRange != null ||
        roeRange != null ||
        revenueGrowthRange != null ||
        profitGrowthRange != null ||
        dividendYieldRange != null ||
        marketCapLevel != null ||
        floatMarketCapLevel != null ||
        minListingYears != null ||
        turnoverRange != null ||
        pctFrom52WeekHigh != null ||
        changePctRange != null ||
        volumeRange != null ||
        (foreignHolderFilter != null && foreignHolderFilter!.hasFilter);
  }

  /// 获取筛选条件描述文本
  String get description {
    final parts = <String>[];
    if (peRange != null) parts.add('PE ${peRange!.start.toInt()}-${peRange!.end.toInt()}');
    if (pbRange != null) parts.add('PB ${pbRange!.start.toInt()}-${pbRange!.end.toInt()}');
    if (roeRange != null) parts.add('ROE ${roeRange!.start.toInt()}-${roeRange!.end.toInt()}%');
    if (revenueGrowthRange != null) parts.add('营收增速${revenueGrowthRange!.start.toInt()}-${revenueGrowthRange!.end.toInt()}%');
    if (profitGrowthRange != null) parts.add('净利润增速${profitGrowthRange!.start.toInt()}-${profitGrowthRange!.end.toInt()}%');
    if (dividendYieldRange != null) parts.add('股息率${dividendYieldRange!.start.toInt()}-${dividendYieldRange!.end.toInt()}%');
    if (marketCapLevel != null) {
      final capText = {'small': '小盘', 'mid': '中盘', 'large': '大盘'}[marketCapLevel] ?? '';
      if (capText.isNotEmpty) parts.add(capText);
    }
    if (minListingYears != null) parts.add('上市>${minListingYears}年');
    if (turnoverRange != null) parts.add('换手${turnoverRange!.start.toInt()}-${turnoverRange!.end.toInt()}%');
    if (pctFrom52WeekHigh != null) parts.add('距52周高<${pctFrom52WeekHigh!.end.toInt()}%');
    if (changePctRange != null) parts.add('涨幅${changePctRange!.start.toInt()}-${changePctRange!.end.toInt()}%');
    if (volumeRange != null) parts.add('成交量${volumeRange!.start.toInt()}-${volumeRange!.end.toInt()}万手');
    if (foreignHolderFilter != null && foreignHolderFilter!.hasFilter) {
      final foreignDesc = foreignHolderFilter!.description;
      if (foreignDesc.isNotEmpty) parts.add(foreignDesc);
    }
    return parts.isEmpty ? '无筛选条件' : parts.join(', ');
  }
}

/// 快捷筛选模板
class FilterTemplate {
  final String name;
  final String description;
  final FilterCriteria Function() getCriteria;

  const FilterTemplate({
    required this.name,
    required this.description,
    required this.getCriteria,
  });
}

/// 预定义的快捷筛选模板
class FilterTemplates {
  static List<FilterTemplate> get all => [
    FilterTemplate(
      name: '低估值蓝筹',
      description: 'PE<15, ROE>12%, 市值>500亿',
      getCriteria: () => const FilterCriteria(
        market: 'A',
        peRange: RangeValues(0, 15),
        roeRange: RangeValues(12, 50),
        marketCapLevel: 'large',
      ),
    ),
    FilterTemplate(
      name: '高成长',
      description: '营收增速>30%, PE<40',
      getCriteria: () => const FilterCriteria(
        market: 'A',
        revenueGrowthRange: RangeValues(30, 200),
        peRange: RangeValues(0, 40),
      ),
    ),
    FilterTemplate(
      name: '高股息防御',
      description: '股息率≥4%, PE<20, ROE≥10%, 市值≥100亿',
      getCriteria: () => const FilterCriteria(
        market: 'A',
        dividendYieldRange: RangeValues(4, 10),
        peRange: RangeValues(0, 20),
        roeRange: RangeValues(10, 50),
        marketCapLevel: 'mid',
      ),
    ),
    FilterTemplate(
      name: '超跌反弹',
      description: '距52周高<60%, 换手率≥2%, 市值≥100亿',
      getCriteria: () => const FilterCriteria(
        market: 'A',
        pctFrom52WeekHigh: RangeValues(0, 60),
        turnoverRange: RangeValues(2, 30),
        marketCapLevel: 'mid',
        peRange: RangeValues(0, 30),
      ),
    ),
    FilterTemplate(
      name: '次新小盘',
      description: '市值<100亿, 上市1-3年, ROE>5%',
      getCriteria: () => const FilterCriteria(
        market: 'A',
        marketCapLevel: 'small',
        minListingYears: 1,
        roeRange: RangeValues(5, 50),
        turnoverRange: RangeValues(1, 20),
      ),
    ),
  ];
}
