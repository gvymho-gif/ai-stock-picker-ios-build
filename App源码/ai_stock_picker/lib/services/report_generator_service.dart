import 'dart:convert';
import 'dart:math';

/// 报告生成服务 — 生成结构化分析报告文本
///
/// 当前输出结构化文本报告，后续可升级为PDF
class ReportGeneratorService {
  static final ReportGeneratorService _instance = ReportGeneratorService._();
  factory ReportGeneratorService() => _instance;
  ReportGeneratorService._();

  /// 生成个股分析报告
  String generateStockReport({
    required String stockName,
    required String stockCode,
    required String aiAnalysis,
    Map<String, dynamic>? stockData,
    List<Map<String, double>>? klineData,
  }) {
    final buf = StringBuffer();

    buf.writeln('═══════════════════════════════════');
    buf.writeln('   📊 $stockName ($stockCode) 深度分析报告');
    buf.writeln('═══════════════════════════════════');
    buf.writeln('生成时间：${DateTime.now().toString().substring(0, 19)}');
    buf.writeln('');

    // 基本面数据
    if (stockData != null && stockData.isNotEmpty) {
      buf.writeln('── 基本面数据 ──');
      final price = _d(stockData['price']);
      final changePct = _d(stockData['change_pct']);
      final pe = _d(stockData['pe_ratio']);
      final pb = _d(stockData['pb_ratio']);
      final roe = _d(stockData['roe']);
      final eps = _d(stockData['eps']);

      if (price > 0) buf.writeln('现价：${price.toStringAsFixed(2)} (${changePct >= 0 ? "+" : ""}${changePct.toStringAsFixed(2)}%)');
      if (pe > 0) buf.writeln('市盈率(PE)：${pe.toStringAsFixed(2)}');
      if (pb > 0) buf.writeln('市净率(PB)：${pb.toStringAsFixed(2)}');
      if (roe > 0) buf.writeln('ROE：${roe.toStringAsFixed(2)}%');
      if (eps > 0) buf.writeln('每股收益(EPS)：${eps.toStringAsFixed(3)}');
      buf.writeln('');
    }

    // AI分析结论
    buf.writeln('── 极智AI分析 ──');
    buf.writeln(aiAnalysis);
    buf.writeln('');

    // 风险提示
    buf.writeln('── ⚠ 风险提示 ──');
    buf.writeln('• 本报告由AI自动生成，仅供参考，不构成投资建议');
    buf.writeln('• 股市有风险，投资需谨慎');
    buf.writeln('• 历史表现不代表未来收益');
    buf.writeln('');
    buf.writeln('═══════════════════════════════════');
    buf.writeln('  报告由 蓝图极智 v2.1 生成');
    buf.writeln('═══════════════════════════════════');

    return buf.toString();
  }

  /// 生成市场概览报告
  String generateMarketReport({
    required String aiAnalysis,
    Map<String, dynamic>? marketData,
  }) {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════');
    buf.writeln('   📈 A股市场概览报告');
    buf.writeln('═══════════════════════════════════');
    buf.writeln('生成时间：${DateTime.now().toString().substring(0, 19)}');
    buf.writeln('');
    buf.writeln(aiAnalysis);
    buf.writeln('');
    buf.writeln('── ⚠ 风险提示 ──');
    buf.writeln('以上分析仅供参考，不构成投资建议。股市有风险，投资需谨慎。');
    buf.writeln('');
    buf.writeln('═══════════════════════════════════');

    return buf.toString();
  }

  double _d(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0;
  }
}
