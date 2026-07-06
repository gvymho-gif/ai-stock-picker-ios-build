/// 股票对比服务 — 多股票横向对比分析
class StockCompareService {
  static final StockCompareService _instance = StockCompareService._();
  factory StockCompareService() => _instance;
  StockCompareService._();

  /// 生成多股票对比文本
  String generateComparison({
    required List<Map<String, dynamic>> stockDataList,
    required List<String> stockNames,
  }) {
    final buf = StringBuffer();
    buf.writeln('\n【多股票横向对比】');

    // 表头
    buf.writeln('| 指标 | ${stockNames.join(" | ")} |');
    buf.writeln('|------|${List.filled(stockNames.length, '------').join('|')}|');

    // 价格
    final prices = stockDataList.map((d) {
      final p = _d(d['price']);
      return p > 0 ? p.toStringAsFixed(2) : 'N/A';
    }).toList();
    buf.writeln('| 现价 | ${prices.join(" | ")} |');

    // 涨跌幅
    final changes = stockDataList.map((d) {
      final c = _d(d['change_pct']);
      return '${c >= 0 ? "+" : ""}${c.toStringAsFixed(2)}%';
    }).toList();
    buf.writeln('| 涨跌幅 | ${changes.join(" | ")} |');

    // PE
    final pes = stockDataList.map((d) {
      final pe = _d(d['pe_ratio']);
      return pe > 0 ? pe.toStringAsFixed(2) : 'N/A';
    }).toList();
    buf.writeln('| PE | ${pes.join(" | ")} |');

    // PB
    final pbs = stockDataList.map((d) {
      final pb = _d(d['pb_ratio']);
      return pb > 0 ? pb.toStringAsFixed(2) : 'N/A';
    }).toList();
    buf.writeln('| PB | ${pbs.join(" | ")} |');

    // ROE
    final roes = stockDataList.map((d) {
      final roe = _d(d['roe']);
      return roe > 0 ? '${roe.toStringAsFixed(1)}%' : 'N/A';
    }).toList();
    buf.writeln('| ROE | ${roes.join(" | ")} |');

    // EPS
    final epss = stockDataList.map((d) {
      final eps = _d(d['eps']);
      return eps > 0 ? eps.toStringAsFixed(3) : 'N/A';
    }).toList();
    buf.writeln('| EPS | ${epss.join(" | ")} |');

    // 换手率
    final turnovers = stockDataList.map((d) {
      final t = _d(d['turnover_rate']);
      return t > 0 ? '${t.toStringAsFixed(2)}%' : 'N/A';
    }).toList();
    buf.writeln('| 换手率 | ${turnovers.join(" | ")} |');

    // AI评分
    final scores = stockDataList.map((d) {
      final a = d['ai_analysis'] as Map<String, dynamic>?;
      final s = _d(a?['score']);
      return s > 0 ? '${(s * 100).toStringAsFixed(0)}分' : 'N/A';
    }).toList();
    buf.writeln('| AI评分 | ${scores.join(" | ")} |');

    return buf.toString();
  }

  /// 生成雷达图数据结构用于可视化
  List<Map<String, dynamic>> generateRadarData(List<Map<String, dynamic>> stockDataList) {
    final dimensions = ['估值', '成长', '技术', '资金', '风险'];
    final result = <Map<String, dynamic>>[];

    for (var i = 0; i < stockDataList.length; i++) {
      final d = stockDataList[i];
      final name = d['name']?.toString() ?? '股票${i + 1}';
      final analysis = d['ai_analysis'] as Map<String, dynamic>? ?? {};
      final detail = analysis['detail'] as Map<String, dynamic>? ?? {};

      result.add({
        'name': name,
        '估值': _d(detail['fundamental_score']) * 100,
        '成长': _d(d['revenue_growth']),
        '技术': _d(detail['technical_score']) * 100,
        '资金': _d(detail['capital_score']) * 100,
        '风险': (1.0 - _d(detail['risk_score'])) * 100,
      });
    }
    return result;
  }

  double _d(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}
