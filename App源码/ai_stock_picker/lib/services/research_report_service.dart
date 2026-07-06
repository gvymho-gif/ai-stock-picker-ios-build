import 'dart:convert';
import 'package:http/http.dart' as http;

/// 研报分析服务 — 从东方财富获取券商研报摘要
class ResearchReportService {
  static final ResearchReportService _instance = ResearchReportService._();
  factory ResearchReportService() => _instance;
  ResearchReportService._();

  final http.Client _client = http.Client();

  /// 获取个股最近研报摘要
  Future<List<ResearchReport>> getRecentReports(String stockCode, {int count = 3}) async {
    try {
      final market = stockCode.startsWith('6') ? 'SH' : 'SZ';
      final url = 'https://datacenter.eastmoney.com/securities/api/data/v1/get'
          '?reportName=RPT_RESREPORT_SEARCH'
          '&columns=STOCK_CODE,STOCK_NAME,ORG_NAME,TITLE,PUBLISH_DATE,RESEARCHER,RATING,VALUE_ANALYSIS'
          '&filter=(STOCK_CODE="$stockCode")'
          '&sortColumns=PUBLISH_DATE&sortTypes=-1'
          '&pageSize=$count'
          '&source=HSF10&client=PC';

      final response = await _client.get(
        Uri.parse(url),
        headers: {'Referer': 'https://emweb.securities.eastmoney.com/'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['result'] != null) {
          final items = data['result']['data'] as List? ?? [];
          return items.map((i) => ResearchReport.fromJson(i)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// 格式化研报为LLM友好文本
  String formatForLLM(List<ResearchReport> reports, String stockName) {
    if (reports.isEmpty) return '';

    final buf = StringBuffer();
    buf.writeln('\n【最近券商研报 - $stockName】');
    for (final r in reports) {
      buf.writeln('• ${r.publishDate} ${r.orgName}: ${r.title} (评级: ${r.rating})');
      if (r.valueAnalysis.isNotEmpty && r.valueAnalysis.length < 200) {
        buf.writeln('  核心观点: ${r.valueAnalysis}');
      }
    }
    return buf.toString();
  }
}

class ResearchReport {
  final String stockCode;
  final String stockName;
  final String orgName;
  final String title;
  final String publishDate;
  final String researcher;
  final String rating;
  final String valueAnalysis;

  ResearchReport({
    required this.stockCode,
    required this.stockName,
    required this.orgName,
    required this.title,
    required this.publishDate,
    required this.researcher,
    required this.rating,
    required this.valueAnalysis,
  });

  factory ResearchReport.fromJson(Map<String, dynamic> json) {
    return ResearchReport(
      stockCode: json['STOCK_CODE']?.toString() ?? '',
      stockName: json['STOCK_NAME']?.toString() ?? '',
      orgName: json['ORG_NAME']?.toString() ?? '',
      title: json['TITLE']?.toString() ?? '',
      publishDate: json['PUBLISH_DATE']?.toString() ?? '',
      researcher: json['RESEARCHER']?.toString() ?? '',
      rating: json['RATING']?.toString() ?? '',
      valueAnalysis: json['VALUE_ANALYSIS']?.toString() ?? '',
    );
  }
}
