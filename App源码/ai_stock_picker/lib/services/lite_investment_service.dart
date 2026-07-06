/// 轻量投资服务
///
/// 继承热点投资服务，仅覆盖投资限额和数据存储key
/// 每只股票上限3333元，组合总投资上限1万元（3只×3333）
/// 其他规则完全相同：止盈+10%、硬止损-5%、5个交易日14:55强制平仓、T+1

import '../services/hot_investment_service.dart';

class LiteInvestmentService extends HotInvestmentService {
  // 独立单例，与热点投资服务分开
  static final LiteInvestmentService _instance = LiteInvestmentService._internal();
  factory LiteInvestmentService() => _instance;
  LiteInvestmentService._internal() : super.createInstance();

  // ── 覆盖 getter ──

  @override
  String get portfoliosKey => 'lite_investment_portfolios';

  @override
  String get calendarArchiveKey => 'lite_invest_calendar_archive';

  @override
  double get maxStockInvest => 3333.0;         // 每只股票上限 3333 元

  @override
  double get maxPortfolioInvest => 10000.0;     // 组合上限 1 万元

  @override
  String get investmentType => '轻量投资';       // 日志前缀

  @override
  DateTime get firstTradeDate => DateTime(2026, 6, 22);  // 首个建仓日 2026-06-22
}
