import 'dart:convert';
import 'package:http/http.dart' as http;

/// 财报分析服务 — 从东方财富获取利润表/资产负债表/现金流量表关键数据
class FinancialReportService {
  static final FinancialReportService _instance = FinancialReportService._();
  factory FinancialReportService() => _instance;
  FinancialReportService._();

  final http.Client _client = http.Client();

  /// 获取财报摘要（最近一期）
  Future<FinancialReportSummary?> getReportSummary(String stockCode) async {
    try {
      final market = _getMarket(stockCode);
      final url = 'https://datacenter.eastmoney.com/securities/api/data/v1/get'
          '?reportName=RPT_LICO_FN_CPD'
          '&columns=SECURITY_CODE,SECURITY_NAME_ABBR,NOTICE_DATE,REPORT_DATE'
          ',TOTAL_OPERATE_INCOME,TOTAL_OPERATE_INCOME_YOY'
          ',PARENT_NETPROFIT,PARENT_NETPROFIT_YOY'
          ',WEIGHTAVG_ROE,GROSS_PROFIT_RATIO,NET_PROFIT_RATIO'
          ',BASIC_EPS,BPS,CURRENT_RATIO,QUICK_RATIO'
          ',ASSET_LIAB_RATIO,TOTAL_ASSETS,TOTAL_LIABILITIES'
          '&filter=(SECURITY_TYPE_CODE="058001001")'
          '&sortColumns=REPORT_DATE&sortTypes=-1'
          '&pageSize=2'
          '&source=HSF10&client=PC';

      final fullUrl = '$url&filter=(SECURITY_CODE="$stockCode")';
      final response = await _client.get(
        Uri.parse(fullUrl),
        headers: {'Referer': 'https://emweb.securities.eastmoney.com/'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['result'] != null) {
          final items = data['result']['data'] as List?;
          if (items != null && items.isNotEmpty) {
            return FinancialReportSummary.fromJson(items[0]);
          }
        }
      }
    } catch (_) {
      // 财报获取失败静默处理，不阻塞主流程
    }
    return null;
  }

  /// 格式化财报摘要为LLM友好的文本
  String formatForLLM(FinancialReportSummary? report, String stockName) {
    if (report == null) {
      return '[财报数据] $stockName：暂无最新财报数据，建议参考其他分析维度。';
    }

    final b = StringBuffer();
    b.writeln('【$stockName 最新财报摘要】');
    b.writeln('报告期：${report.reportDate}');
    b.writeln('营业收入：${_fmtNum(report.totalOperateIncome)}元（同比${_fmtPct(report.totalOperateIncomeYoY)}）');
    b.writeln('归母净利润：${_fmtNum(report.parentNetProfit)}元（同比${_fmtPct(report.parentNetProfitYoY)}）');
    b.writeln('加权ROE：${report.weightAvgROE?.toStringAsFixed(2) ?? 'N/A'}%');
    b.writeln('毛利率：${report.grossProfitRatio?.toStringAsFixed(2) ?? 'N/A'}%');
    b.writeln('净利率：${report.netProfitRatio?.toStringAsFixed(2) ?? 'N/A'}%');
    b.writeln('基本每股收益(EPS)：${report.basicEPS?.toStringAsFixed(4) ?? 'N/A'}');
    b.writeln('每股净资产(BPS)：${report.bps?.toStringAsFixed(2) ?? 'N/A'}');
    b.writeln('资产负债率：${report.assetLiabRatio?.toStringAsFixed(2) ?? 'N/A'}%');
    b.writeln('流动比率：${report.currentRatio?.toStringAsFixed(2) ?? 'N/A'}');
    b.writeln('速动比率：${report.quickRatio?.toStringAsFixed(2) ?? 'N/A'}');
    return b.toString();
  }

  String _fmtNum(double? num) {
    if (num == null) return 'N/A';
    final abs = num.abs();
    if (abs >= 1e8) return '${(num / 1e8).toStringAsFixed(2)}亿';
    if (abs >= 1e4) return '${(num / 1e4).toStringAsFixed(2)}万';
    return num.toStringAsFixed(2);
  }

  String _fmtPct(double? pct) {
    if (pct == null) return 'N/A';
    return '${pct.toStringAsFixed(2)}%';
  }

  String _getMarket(String code) {
    if (code.startsWith('6')) return 'SH';
    if (code.startsWith('0') || code.startsWith('3')) return 'SZ';
    return 'SH';
  }
}

/// 财报摘要数据模型
class FinancialReportSummary {
  final String securityCode;
  final String securityName;
  final String noticeDate;
  final String reportDate;
  final double? totalOperateIncome;
  final double? totalOperateIncomeYoY;
  final double? parentNetProfit;
  final double? parentNetProfitYoY;
  final double? weightAvgROE;
  final double? grossProfitRatio;
  final double? netProfitRatio;
  final double? basicEPS;
  final double? bps;
  final double? currentRatio;
  final double? quickRatio;
  final double? assetLiabRatio;
  final double? totalAssets;
  final double? totalLiabilities;

  FinancialReportSummary({
    required this.securityCode,
    required this.securityName,
    required this.noticeDate,
    required this.reportDate,
    this.totalOperateIncome,
    this.totalOperateIncomeYoY,
    this.parentNetProfit,
    this.parentNetProfitYoY,
    this.weightAvgROE,
    this.grossProfitRatio,
    this.netProfitRatio,
    this.basicEPS,
    this.bps,
    this.currentRatio,
    this.quickRatio,
    this.assetLiabRatio,
    this.totalAssets,
    this.totalLiabilities,
  });

  factory FinancialReportSummary.fromJson(Map<String, dynamic> json) {
    return FinancialReportSummary(
      securityCode: json['SECURITY_CODE']?.toString() ?? '',
      securityName: json['SECURITY_NAME_ABBR']?.toString() ?? '',
      noticeDate: json['NOTICE_DATE']?.toString() ?? '',
      reportDate: json['REPORT_DATE']?.toString() ?? '',
      totalOperateIncome: _parseDouble(json['TOTAL_OPERATE_INCOME']),
      totalOperateIncomeYoY: _parseDouble(json['TOTAL_OPERATE_INCOME_YOY']),
      parentNetProfit: _parseDouble(json['PARENT_NETPROFIT']),
      parentNetProfitYoY: _parseDouble(json['PARENT_NETPROFIT_YOY']),
      weightAvgROE: _parseDouble(json['WEIGHTAVG_ROE']),
      grossProfitRatio: _parseDouble(json['GROSS_PROFIT_RATIO']),
      netProfitRatio: _parseDouble(json['NET_PROFIT_RATIO']),
      basicEPS: _parseDouble(json['BASIC_EPS']),
      bps: _parseDouble(json['BPS']),
      currentRatio: _parseDouble(json['CURRENT_RATIO']),
      quickRatio: _parseDouble(json['QUICK_RATIO']),
      assetLiabRatio: _parseDouble(json['ASSET_LIAB_RATIO']),
      totalAssets: _parseDouble(json['TOTAL_ASSETS']),
      totalLiabilities: _parseDouble(json['TOTAL_LIABILITIES']),
    );
  }

  static double? _parseDouble(dynamic val) {
    if (val == null) return null;
    return double.tryParse(val.toString());
  }
}
