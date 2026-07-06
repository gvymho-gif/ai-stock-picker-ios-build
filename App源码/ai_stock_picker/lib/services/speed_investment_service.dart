/// 极速投资服务层
///
/// 每个交易日20:00从A股游资(前3只)+隔夜导航(前3只)提取6只股票
/// 下一个交易日09:30买入，再下一个交易日09:30卖出
/// 严格T+1买入/T+2卖出日结，每只上限2万/总上限12万

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/speed_investment_model.dart';
import 'expert_stock_service.dart';
import 'backup_service.dart';
import 'jianguoyun_service.dart';
import 'local_data_service.dart';
import '../utils/trading_day_utils.dart';

class SpeedInvestmentService {
  static const String _kPortfoliosKey = 'speed_portfolios';
  static const String _kSettlementsKey = 'speed_settlements';

  final ExpertStockService _expertService = ExpertStockService();

  List<SpeedPortfolio> _portfolios = [];
  List<SpeedSettlementRecord> _settlements = [];
  Timer? _tradeTimer;
  bool _tradeRunning = false;

  // ========== 公开 getter ==========

  List<SpeedPortfolio> get portfolios => List.unmodifiable(_portfolios);
  List<SpeedPortfolio> get activePortfolios => _portfolios.where((p) => p.status == SpeedPortfolioStatus.active).toList();
  List<SpeedPortfolio> get settledPortfolios => _portfolios.where((p) => p.status == SpeedPortfolioStatus.settled).toList();
  List<SpeedSettlementRecord> get settlements => List.unmodifiable(_settlements);

  DateTime? get firstTradeDate {
    // 极速投资的"首个建仓日" = 第一个组合的buyDate（pending或active也算）
    if (_portfolios.isEmpty) return null;
    final allBuyDates = _portfolios
        .where((p) => p.status != SpeedPortfolioStatus.settled || p.positions.isNotEmpty)
        .map((p) => DateTime(p.buyDate.year, p.buyDate.month, p.buyDate.day))
        .toList();
    if (allBuyDates.isEmpty) {
      // 回退到 settlement 记录
      if (_settlements.isEmpty) return null;
      _settlements.sort((a, b) => a.date.compareTo(b.date));
      return DateTime.tryParse(_settlements.first.date);
    }
    allBuyDates.sort();
    return allBuyDates.first;
  }

  /// 日历归档（兼容 InvestmentReturnCalendarWidget）
  /// 使用资金加权收益率（与列表页/详情页 avgSettledReturn 口径一致）
  /// ★ 字段名统一为 'return'（日历组件第 214 行读取 entry['return']）
  List<Map<String, dynamic>> get calendarArchive {
    return _settlements.map((s) {
      double ret = s.settledReturn; // 回退值
      for (final p in _portfolios) {
        if (p.id == s.portfolioId && p.status == SpeedPortfolioStatus.settled) {
          ret = p.avgSettledReturn; // 资金加权现算
          break;
        }
      }
      return {'date': s.date, 'return': ret};
    }).toList();
  }

  SpeedStatistics get statistics => SpeedStatistics.compute(_settlements);

  // ========== 初始化 ==========

  /// 强制重新从 SharedPreferences 加载（用于 portfolio_sync_service 恢复后调用）
  Future<void> forceReload() async {
    await _loadFromLocal();
  }

  Future<void> init() async {
    await _loadFromLocal();
    _startTradeMonitor();
  }

  /// 启动交易监控定时器（买入+卖出持续检测）
  /// 交易日09:30-15:05 每30秒检查一次是否有待买入/待卖出的组合
  void _startTradeMonitor() {
    _tradeTimer?.cancel();
    _tradeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tradeCheck());
    // 立即执行一次
    Future.microtask(() => _tradeCheck());
  }

  /// 停止交易监控
  void dispose() {
    _tradeTimer?.cancel();
    _tradeTimer = null;
  }

  /// 单次交易检查：买入(pending→active) + 卖出(active→settled)
  Future<void> _tradeCheck() async {
    if (_tradeRunning) return; // 防止并发
    _tradeRunning = true;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (!TradingDayUtils.isSecuritiesTradingDay(today)) return;
      final minutes = now.hour * 60 + now.minute;
      if (minutes < 9 * 60 + 30 || minutes > 15 * 60 + 5) return;

      final todayStr = TradingDayUtils.formatDate(today);

      // ── 1. 买入：buyDate=今天的pending组合 → 按开盘价激活建仓 ──
      final todayPending = _portfolios.where((p) {
        if (p.status != SpeedPortfolioStatus.pending) return false;
        return TradingDayUtils.formatDate(p.buyDate) == todayStr;
      }).toList();
      if (todayPending.isNotEmpty) {
        debugPrint('[极速投资] 交易监控-激活${todayPending.length}个今日待买入组合');
        await tryAutoActivate();
      }

      // ── 2. 卖出：sellDate=今天的active组合 → 按实时价全额卖出 ──
      final todaySettleable = _portfolios.where((p) {
        if (p.status != SpeedPortfolioStatus.active) return false;
        return TradingDayUtils.formatDate(p.sellDate) == todayStr;
      }).toList();
      if (todaySettleable.isNotEmpty) {
        debugPrint('[极速投资] 交易监控-结算${todaySettleable.length}个今日待卖出组合');
        await tryAutoSettle();
      }
    } finally {
      _tradeRunning = false;
    }
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final pJson = prefs.getString(_kPortfoliosKey);
    if (pJson != null) {
      try {
        final list = json.decode(pJson) as List<dynamic>;
        final loaded = list.map((e) => SpeedPortfolio.fromJson(e as Map<String, dynamic>)).toList();
        // ★ 加载时按 id 去重（防 local cache 中残留重复）
        final seen = <String>{};
        _portfolios = [];
        for (final p in loaded) {
          if (p.id.isEmpty || seen.contains(p.id)) continue;
          seen.add(p.id);
          _portfolios.add(p);
        }
        if (loaded.length != _portfolios.length) {
          debugPrint('[极速投资] 加载时去重: ${loaded.length} -> ${_portfolios.length}');
          await prefs.setString(_kPortfoliosKey, json.encode(_portfolios.map((p) => p.toJson()).toList()));
        }
      } catch (_) {}
    }
    final sJson = prefs.getString(_kSettlementsKey);
    if (sJson != null) {
      try {
        final list = json.decode(sJson) as List<dynamic>;
        final loaded = list.map((e) => SpeedSettlementRecord.fromJson(e as Map<String, dynamic>)).toList();
        // ★ settlements 按 date+portfolioId 去重
        final seenKeys = <String>{};
        _settlements = [];
        for (final s in loaded) {
          final key = '${s.date}_${s.portfolioId}';
          if (seenKeys.contains(key)) continue;
          seenKeys.add(key);
          _settlements.add(s);
        }
      } catch (_) {}
    }

    // ★ 旧数据迁移：returnAmount 在旧版(v2.0.5及以前)存的是总回款，
    //   新版(v2.0.6+)期望存利润。判断方法：
    //   - 若 returnAmount 是利润，则 returnAmount / investedAmount ≈ returnRate
    //   - 若 returnAmount 是总回款，则 returnAmount / investedAmount ≈ returnRate + 1
    //   取距离近者作为实际语义，总回款时转换为利润 = returnAmount - investedAmount。
    bool migrated = false;
    for (final p in _portfolios) {
      if (p.status != SpeedPortfolioStatus.settled) continue;
      for (int i = 0; i < p.positions.length; i++) {
        final pos = p.positions[i];
        if (pos.status != SpeedPositionStatus.settled) continue;
        if (pos.investedAmount <= 0) continue;
        final ret = pos.returnAmount;
        if (ret == null) continue;
        final rate = pos.returnRate ?? 0.0;
        final ratio = ret / pos.investedAmount;
        final asProfitDist = (ratio - rate).abs();
        final asTotalReturnDist = (ratio - (rate + 1.0)).abs();
        if (asTotalReturnDist < asProfitDist) {
          final profit = ret - pos.investedAmount;
          final newRate = pos.investedAmount > 0 ? profit / pos.investedAmount : 0.0;
          p.positions[i] = SpeedPosition(
            stockCode: pos.stockCode,
            stockName: pos.stockName,
            buyPrice: pos.buyPrice,
            buyTime: pos.buyTime,
            investedAmount: pos.investedAmount,
            shares: pos.shares,
            plannedAmount: pos.plannedAmount,
            status: pos.status,
            sellPrice: pos.sellPrice,
            sellTime: pos.sellTime,
            returnAmount: profit,
            returnRate: newRate,
          );
          migrated = true;
        }
      }
    }
    if (migrated) {
      debugPrint('[极速投资] 完成旧数据迁移：returnAmount 从总回款转换为利润');
    }

    // ★ 统一从已结算组合重新生成 settlements，确保 settledReturn 与利润一致。
    //   这同时修复旧版 settlements 中 settledReturn ≈ 100%（总回款/总投入）的异常。
    _settlements = _portfolios
        .where((p) => p.status == SpeedPortfolioStatus.settled)
        .map((p) => SpeedSettlementRecord(
              date: p.sellDateStr,
              portfolioId: p.id,
              settledReturn: p.avgSettledReturn,
              floatingReturn: 0,
              totalReturn: p.avgSettledReturn,
            ))
        .where((s) => s.date.isNotEmpty)
        .toList();
    _settlements.sort((a, b) => a.date.compareTo(b.date));
    await _saveToLocal();
  }

  Future<void> _saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPortfoliosKey, json.encode(_portfolios.map((p) => p.toJson()).toList()));
    await prefs.setString(_kSettlementsKey, json.encode(_settlements.map((s) => s.toJson()).toList()));
  }

  // ========== 核心选股（交易日20:00调用） ==========

  /// 从A股游资和隔夜导航各提取前3只，合成6只组合
  /// 仅在交易日前夜20:00~次日09:30可调用（即明天是交易日时才能创建）
  /// T-1日20:00仅记录预选股票信息，不计算买入价格和股数
  /// T日09:30由 activatePortfolio 按实际开盘价正式建仓
  Future<SpeedPortfolio?> createDailyPortfolio() async {
    try {
      // 检查明天是否是交易日（选股必须在交易日前一天晚上20:00进行）
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      if (!TradingDayUtils.isSecuritiesTradingDay(tomorrowDate)) {
        debugPrint('[极速投资] 明天不是交易日，无法创建组合');
        return null;
      }
      // 获取A股游资前3只
      final speedResult = await _expertService.runSpeedAssassin();
      final speedStocks = _extractStocks(speedResult, 3);

      // 获取隔夜导航前3只
      final overnightResult = await _expertService.runOvernightNavigator();
      final overnightStocks = _extractStocks(overnightResult, 3);

      if (speedStocks.length < 3 || overnightStocks.length < 3) {
        debugPrint('[极速投资] 选股数据不足: A股游资${speedStocks.length}只, 隔夜导航${overnightStocks.length}只');
        return null;
      }

      final now = DateTime.now();
      const double maxPerStock = 20000.0;
      final List<SpeedPosition> positions = [];
      final List<String> sources = [];
      double totalPlanned = 0;

      // A股游资3只 — 记录预选信息（含选股价格作为回退买入价）
      for (int i = 0; i < 3 && i < speedStocks.length; i++) {
        final s = speedStocks[i];
        positions.add(SpeedPosition(
          stockCode: s.code,
          stockName: s.name,
          plannedAmount: maxPerStock,
          buyPrice: s.price, // 选股价格，作为实时价获取失败时的回退
          status: SpeedPositionStatus.holding,
        ));
        sources.add('A股游资');
        totalPlanned += maxPerStock;
      }

      // 隔夜导航3只 — 记录预选信息（含选股价格作为回退买入价）
      for (int i = 0; i < 3 && i < overnightStocks.length; i++) {
        final s = overnightStocks[i];
        positions.add(SpeedPosition(
          stockCode: s.code,
          stockName: s.name,
          plannedAmount: maxPerStock,
          buyPrice: s.price, // 选股价格，作为实时价获取失败时的回退
          status: SpeedPositionStatus.holding,
        ));
        sources.add('隔夜导航');
        totalPlanned += maxPerStock;
      }

      if (positions.length != 6) {
        debugPrint('[极速投资] 无法凑齐6只股票，当前${positions.length}只');
        return null;
      }

      final portfolio = SpeedPortfolio(
        id: 'speed_${now.millisecondsSinceEpoch}',
        createTime: now,
        positions: positions,
        status: SpeedPortfolioStatus.pending,
        totalInvested: totalPlanned,
        sourceLabels: sources,
      );

      _portfolios.add(portfolio);
      await _saveToLocal();
      debugPrint('[极速投资] 预选组合创建成功: ${positions.length}只, 计划投入¥$totalPlanned, 等待明日09:30买入');
      return portfolio;
    } catch (e) {
      debugPrint('[极速投资] 创建组合异常: $e');
      return null;
    }
  }

  /// 激活组合（T日09:30，按实际开盘价买入）
  /// [quotes] Map<stockCode, currentPrice> 实时行情
  Future<bool> activatePortfolio(String portfolioId, Map<String, double> quotes) async {
    final idx = _portfolios.indexWhere((p) => p.id == portfolioId);
    if (idx == -1) return false;
    final old = _portfolios[idx];
    if (old.status != SpeedPortfolioStatus.pending) return false;

    final now = DateTime.now();
    final List<SpeedPosition> activatedPositions = [];
    double totalInvested = 0;
    int bought = 0;

    for (final pos in old.positions) {
      // 优先用实时行情价格，获取不到则回退到选股时记录的价格
      double buyPrice = 0;
      final realPrice = quotes[pos.stockCode];
      if (realPrice != null && realPrice > 0) {
        buyPrice = realPrice;
      } else if (pos.buyPrice > 0) {
        // 回退：使用选股时记录的价格
        buyPrice = pos.buyPrice;
        debugPrint('[极速投资] ${pos.stockName}(${pos.stockCode}) 实时价格获取失败，回退使用选股价格¥$buyPrice');
      }

      if (buyPrice > 0) {
        final plannedAmt = pos.plannedAmount > 0 ? pos.plannedAmount : 20000.0;
        final shares = ((plannedAmt / buyPrice) / 100).floor() * 100;
        if (shares > 0) {
          final actualInvested = shares * buyPrice;
          activatedPositions.add(SpeedPosition(
            stockCode: pos.stockCode,
            stockName: pos.stockName,
            buyPrice: buyPrice,
            buyTime: now,
            investedAmount: actualInvested,
            shares: shares,
            plannedAmount: plannedAmt,
            status: SpeedPositionStatus.holding,
          ));
          totalInvested += actualInvested;
          bought++;
          debugPrint('[极速投资] 买入 ${pos.stockName}(${pos.stockCode}): ${buyPrice.toStringAsFixed(2)}x$shares=¥${actualInvested.toStringAsFixed(0)}');
        }
      } else {
        debugPrint('[极速投资] ${pos.stockName}(${pos.stockCode}) 无可用价格，跳过买入');
      }
    }

    if (bought == 0) {
      debugPrint('[极速投资] 无可用实时价格，激活失败');
      return false;
    }

    _portfolios[idx] = SpeedPortfolio(
      id: old.id,
      createTime: old.createTime,
      positions: activatedPositions,
      status: SpeedPortfolioStatus.active,
      totalInvested: totalInvested,
      sourceLabels: old.sourceLabels,
    );

    await _saveToLocal();
    debugPrint('[极速投资] 激活完成: $bought只, 总投入¥${totalInvested.toStringAsFixed(0)}');
    return true;
  }

  /// 自动激活所有pending组合（T日09:30由首页/列表页调用）
  /// 批量获取实时行情后按实际开盘价建仓
  /// 优先使用开盘价（腾讯行情 fields[5]），搁置时用当前价（fields[3]）
  Future<int> tryAutoActivate() async {
    final todayStr = TradingDayUtils.formatDate(DateTime.now());
    final pending = _portfolios.where((p) {
      if (p.status != SpeedPortfolioStatus.pending) return false;
      // 仅激活buyDate=今天的组合
      return TradingDayUtils.formatDate(p.buyDate) == todayStr;
    }).toList();
    if (pending.isEmpty) return 0;

    debugPrint('[极速投资] 自动激活${pending.length}个待买入组合');

    final allCodes = <String>{};
    for (final p in pending) {
      for (final pos in p.positions) {
        allCodes.add(pos.stockCode);
      }
    }

    // 先尝试开盘价，失败则尝试当前价
    Map<String, double> quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: true);
    if (quotes.isEmpty) {
      await Future.delayed(const Duration(seconds: 2));
      quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    }
    if (quotes.isEmpty) {
      await Future.delayed(const Duration(seconds: 3));
      quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    }

    int activated = 0;
    for (final p in pending) {
      final ok = await activatePortfolio(p.id, quotes);
      if (ok) activated++;
    }

    if (activated > 0) await _saveToLocal();
    debugPrint('[极速投资] 自动激活完成: $activated/${pending.length}个组合');
    return activated;
  }

  /// 手动激活所有pending组合（不校验buyDate，由用户手动触发）
  Future<int> activateAllPending() async {
    final pending = _portfolios.where((p) => p.status == SpeedPortfolioStatus.pending).toList();
    if (pending.isEmpty) return 0;

    debugPrint('[极速投资] 手动激活${pending.length}个组合');

    final allCodes = <String>{};
    for (final p in pending) {
      for (final pos in p.positions) {
        allCodes.add(pos.stockCode);
      }
    }

    // 尝试获取实时价格
    Map<String, double> quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    if (quotes.isEmpty) {
      await Future.delayed(const Duration(seconds: 2));
      quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    }

    int activated = 0;
    for (final p in pending) {
      final ok = await activatePortfolio(p.id, quotes);
      if (ok) activated++;
    }

    if (activated > 0) await _saveToLocal();
    debugPrint('[极速投资] 手动激活完成: $activated/${pending.length}个组合');
    return activated;
  }

  /// 自动结算所有sellDate=今天的active组合（T+1日09:30卖出）
  /// 批量获取实时行情后按实际价格全额卖出，记录结算收益
  Future<int> tryAutoSettle() async {
    final todayStr = TradingDayUtils.formatDate(DateTime.now());
    final settleable = _portfolios.where((p) {
      if (p.status != SpeedPortfolioStatus.active) return false;
      // 仅结算sellDate=今天的组合
      return TradingDayUtils.formatDate(p.sellDate) == todayStr;
    }).toList();
    if (settleable.isEmpty) return 0;

    debugPrint('[极速投资] 自动结算${settleable.length}个今日待卖出组合');

    final allCodes = <String>{};
    for (final p in settleable) {
      for (final pos in p.positions) {
        if (pos.status == SpeedPositionStatus.holding) {
          allCodes.add(pos.stockCode);
        }
      }
    }

    // 获取实时价格用于结算（卖出用当前价，非开盘价）
    Map<String, double> quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    if (quotes.isEmpty) {
      await Future.delayed(const Duration(seconds: 2));
      quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    }
    if (quotes.isEmpty) {
      await Future.delayed(const Duration(seconds: 3));
      quotes = await _fetchPrices(allCodes.toList(), useOpenPrice: false);
    }

    int settled = 0;
    for (final p in settleable) {
      await settlePortfolio(p.id, quotes);
      settled++;
    }

    if (settled > 0) await _saveToLocal();
    debugPrint('[极速投资] 自动结算完成: $settled/${settleable.length}个组合');
    return settled;
  }

  /// 腾讯行情API批量获取价格
  /// [useOpenPrice] true=开盘价(fields[5]), false=当前价(fields[3])
  /// 腾讯行情要求带市场前缀：沪市sh/深市sz/创业板sz，纯6位数字需自动加前缀
  Future<Map<String, double>> _fetchPrices(List<String> codes, {required bool useOpenPrice}) async {
    final result = <String, double>{};
    if (codes.isEmpty) return result;
    try {
      // 将股票代码转为腾讯行情格式（sh/sz前缀+6位数字）
      final qqCodes = codes.map((code) {
        if (code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj')) return code;
        // 纯6位数字：6/9开头=沪市sh，其余=深市sz
        if (code.startsWith('6') || code.startsWith('9')) return 'sh$code';
        return 'sz$code';
      }).join(',');
      final resp = await http.get(
        Uri.parse('https://qt.gtimg.cn/q=$qqCodes'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 8));
      final text = String.fromCharCodes(resp.bodyBytes);
      final fieldIdx = useOpenPrice ? 5 : 3; // 5=开盘价, 3=当前价
      for (final code in codes) {
        // 腾讯行情返回格式为 sh600000="..." 或 sz000001="..."
        // 需要同时匹配带前缀和不带前缀的格式
        final qqCode = code.startsWith('sh') || code.startsWith('sz') || code.startsWith('bj') ? code
            : (code.startsWith('6') || code.startsWith('9') ? 'sh$code' : 'sz$code');
        final pattern = RegExp('${RegExp.escape(qqCode)}="([^"]*)"');
        final match = pattern.firstMatch(text);
        if (match != null) {
          final fields = match.group(1)!.split('~');
          if (fields.length > fieldIdx) {
            final price = double.tryParse(fields[fieldIdx]);
            if (price != null && price > 0) result[code] = price;
          }
        }
      }
      debugPrint('[极速投资] ${useOpenPrice ? "开盘价" : "当前价"}: ${result.length}/${codes.length}只');
    } catch (e) {
      debugPrint('[极速投资] 获取价格失败: $e');
    }
    return result;
  }

  /// 结算组合（次日09:30卖出，用实时价格结算6只股票）
  /// [quotes] Map<stockCode, currentPrice>
  Future<void> settlePortfolio(String portfolioId, Map<String, double> quotes) async {
    final idx = _portfolios.indexWhere((p) => p.id == portfolioId);
    if (idx == -1) return;
    final old = _portfolios[idx];
    final now = DateTime.now();

    final List<SpeedPosition> settledPositions = [];
    double totalReturnRate = 0;
    int settledCount = 0;

    for (final pos in old.positions) {
      final currentPrice = quotes[pos.stockCode];
      if (currentPrice != null && currentPrice > 0) {
        final sellTotal = currentPrice * pos.shares;          // 卖出总金额
        final profit = sellTotal - pos.investedAmount;       // ★ 利润 = 卖出 - 投入
        final returnRate = profit / pos.investedAmount;
        settledPositions.add(SpeedPosition(
          stockCode: pos.stockCode,
          stockName: pos.stockName,
          buyPrice: pos.buyPrice,
          buyTime: pos.buyTime,
          investedAmount: pos.investedAmount,
          shares: pos.shares,
          status: SpeedPositionStatus.settled,
          sellPrice: currentPrice,
          sellTime: now,
          returnAmount: profit,    // ★ 修复：returnAmount 存"利润"，不是"总回款"
          returnRate: returnRate,
        ));
        totalReturnRate += returnRate;
        settledCount++;
      } else {
        // 未获取到价格，按原价结算（无盈亏）
        settledPositions.add(SpeedPosition(
          stockCode: pos.stockCode,
          stockName: pos.stockName,
          buyPrice: pos.buyPrice,
          buyTime: pos.buyTime,
          investedAmount: pos.investedAmount,
          shares: pos.shares,
          status: SpeedPositionStatus.settled,
          sellPrice: pos.buyPrice,
          sellTime: now,
          returnAmount: 0,         // ★ 修复：原价卖出，returnAmount=0（无利润）
          returnRate: 0,
        ));
      }
    }

    final avgReturn = settledCount > 0 ? totalReturnRate / settledCount * 100 : 0.0;

    _portfolios[idx] = SpeedPortfolio(
      id: old.id,
      createTime: old.createTime,
      positions: settledPositions,
      status: SpeedPortfolioStatus.settled,
      totalInvested: old.totalInvested,
      sourceLabels: old.sourceLabels,
    );

    // 记录结算（按 date+portfolioId 去重，避免同一天多个组合互相覆盖）
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final existingIdx = _settlements.indexWhere((s) => s.date == dateStr && s.portfolioId == portfolioId);
    final record = SpeedSettlementRecord(
      date: dateStr,
      portfolioId: portfolioId,
      settledReturn: avgReturn,
    );
    if (existingIdx >= 0) {
      _settlements[existingIdx] = record;
    } else {
      _settlements.add(record);
    }
    _settlements.sort((a, b) => a.date.compareTo(b.date));

    await _saveToLocal();
    debugPrint('[极速投资] 结算完成: 平均回报${avgReturn.toStringAsFixed(2)}%');
  }

  /// 删除组合（仅pending/active/settled状态均可删除）
  Future<bool> deletePortfolio(String portfolioId) async {
    final idx = _portfolios.indexWhere((p) => p.id == portfolioId);
    if (idx == -1) return false;
    final p = _portfolios[idx];
    _portfolios.removeAt(idx);
    // 同时删除关联的结算记录
    _settlements.removeWhere((s) => s.portfolioId == portfolioId);
    await _saveToLocal();
    debugPrint('[极速投资] 删除组合: ${p.createTime.month}/${p.createTime.day}，剩余${_portfolios.length}个组合');
    return true;
  }

  /// 更新组合浮动收益（盘中实时价格）
  /// 返回Map<portfolioId, double> = 浮动收益率%
  Map<String, double> updateFloatingReturns(Map<String, double> quotes) {
    final result = <String, double>{};
    for (final p in _portfolios.where((p) => p.status == SpeedPortfolioStatus.active)) {
      double totalReturn = 0;
      int count = 0;
      for (final pos in p.positions) {
        final price = quotes[pos.stockCode];
        if (price != null && price > 0) {
          totalReturn += (price - pos.buyPrice) / pos.buyPrice;
          count++;
        }
      }
      if (count > 0) {
        result[p.id] = totalReturn / count * 100;
      }
    }
    return result;
  }

  // ========== 日历数据 ==========

  /// 获取某天的结算+浮动数据
  Map<String, double> getDailyReturns(String dateStr) {
    final settlement = _settlements.where((s) => s.date == dateStr).fold<double>(0, (sum, s) => sum + s.settledReturn);
    return {'settled': settlement, 'floating': 0};
  }

  /// 检查当前时间是否是选股时间（交易日前夜 20:00 后）
  bool canAutoCreate() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return TradingDayUtils.isSecuritiesTradingDay(DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
  }

  /// Gitee云端上传
  Future<Map<String, dynamic>> uploadToCloud() async {
    try {
      final token = await BackupService.getGiteeToken();
      if (token == null || token.isEmpty) return {'ok': false, 'error': '请先在设置中配置Gitee Token'};
      final repoName = await BackupService.getRepoName() ?? 'ai-stock-data';
      final data = {
        'portfolios': _portfolios.map((p) => p.toJson()).toList(),
        'settlements': _settlements.map((s) => s.toJson()).toList(),
      };
      final jsonStr = json.encode(data);
      final ok = await BackupService.backupToGitee(token, repoName, jsonStr);
      return {'ok': ok, 'error': ok ? '' : '上传失败'};
    } catch (e) {
      return {'ok': false, 'error': '异常: $e'};
    }
  }

  /// Gitee云端下载
  Future<Map<String, dynamic>> downloadFromCloud() async {
    try {
      final token = await BackupService.getGiteeToken();
      if (token == null || token.isEmpty) return {'ok': false, 'error': '请先在设置中配置Gitee Token'};
      final repoName = await BackupService.getRepoName() ?? 'ai-stock-data';
      final content = await BackupService.restoreFromGitee(token, repoName);
      if (content == null) return {'ok': false, 'error': '云端无数据'};
      return await _mergeFromJson(content);
    } catch (e) {
      return {'ok': false, 'error': '异常: $e'};
    }
  }

  /// 坚果云上传
  Future<Map<String, dynamic>> uploadToJianguoyun() async {
    final data = {'portfolios': _portfolios.map((p) => p.toJson()).toList(), 'settlements': _settlements.map((s) => s.toJson()).toList()};
    return JianguoyunService.upload('speed_investment', json.encode(data));
  }

  /// 坚果云下载
  Future<Map<String, dynamic>> downloadFromJianguoyun() async {
    final r = await JianguoyunService.downloadWithDetails('speed_investment');
    if (r['ok'] != true) return {'ok': false, 'error': r['error'] ?? '云端无数据'};
    final content = r['content'] as String?;
    if (content == null || content.isEmpty) return {'ok': false, 'error': '备份文件为空'};
    return await _mergeFromJson(content);
  }

  /// 本地导出JSON
  String exportToLocalJson() {
    final data = {'portfolios': _portfolios.map((p) => p.toJson()).toList(), 'settlements': _settlements.map((s) => s.toJson()).toList()};
    return json.encode(data);
  }

  /// 本地导入JSON
  Future<Map<String, dynamic>> importFromLocalJson(String jsonStr) async {
    return await _mergeFromJson(jsonStr);
  }

  Future<Map<String, dynamic>> _mergeFromJson(String jsonStr) async {
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final newPortfolios = (data['portfolios'] as List<dynamic>?)?.map((e) => SpeedPortfolio.fromJson(e as Map<String, dynamic>)).toList() ?? [];
      final newSettlements = (data['settlements'] as List<dynamic>?)?.map((e) => SpeedSettlementRecord.fromJson(e as Map<String, dynamic>)).toList() ?? [];

      // ★ 诊断日志：打印解析后的关键字段
      debugPrint('[极速投资下载] 解析完成: ${newPortfolios.length} portfolios, ${newSettlements.length} settlements');
      for (final p in newPortfolios.take(2)) {
        debugPrint('[极速投资下载] portfolio id=${p.id.substring(0,12)}... status=${p.status.name} createTime=${p.createTime} buyDateStr=${p.buyDateStr} sellDateStr=${p.sellDateStr} totalRet=${p.totalReturn}');
      }
      for (final s in newSettlements.take(3)) {
        debugPrint('[极速投资下载] settlement date=${s.date} settledReturn=${s.settledReturn}');
      }

      // ★ 替换式合并：坚果云数据为权威源，同 id 用新数据覆盖旧数据
      final mergedPortfolios = Map<String, SpeedPortfolio>();
      for (final p in _portfolios) {
        mergedPortfolios[p.id] = p;
      }
      for (final p in newPortfolios) {
        mergedPortfolios[p.id] = p;           // 同 id 替换（权威）
      }
      _portfolios = mergedPortfolios.values.toList();

      // settlements 同样替换式合并
      final mergedSettlements = Map<String, SpeedSettlementRecord>();
      for (final s in _settlements) {
        mergedSettlements[s.date] = s;
      }
      for (final s in newSettlements) {
        mergedSettlements[s.date] = s;        // 同日期替换（权威）
      }
      _settlements = mergedSettlements.values.toList();
      _settlements.sort((a, b) => a.date.compareTo(b.date));
      
      await _saveToLocal();
      debugPrint('[极速投资下载] 保存完成: ${_portfolios.length} portfolios, ${_settlements.length} settlements');
      return {'ok': true, 'count': _portfolios.length};
    } catch (e) {
      debugPrint('[极速投资下载] 解析异常: $e');
      return {'ok': false, 'error': 'JSON解析失败: $e'};
    }
  }

  // ========== 内部工具 ==========

  double mathMin(double a, double b) => a < b ? a : b;

  List<_StockBrief> _extractStocks(Map<String, dynamic> result, int count) {
    final stocks = <_StockBrief>[];
    try {
      final list = result['stocks'] as List<dynamic>?;
      if (list == null) return stocks;
      for (int i = 0; i < list.length && stocks.length < count; i++) {
        final s = list[i] as Map<String, dynamic>?;
        if (s == null) continue;
        // 策略返回的 code 字段可能是纯6位数字或带sh/sz前缀
        // 统一转为腾讯行情格式（sh/sz前缀+6位数字），确保后续请求和匹配一致
        var code = (s['code'] ?? s['symbol'] ?? '') as String;
        if (code.isNotEmpty && !code.startsWith('sh') && !code.startsWith('sz') && !code.startsWith('bj')) {
          code = (code.startsWith('6') || code.startsWith('9')) ? 'sh$code' : 'sz$code';
        }
        final name = (s['name'] ?? s['stockName'] ?? '') as String;
        final price = (s['price'] as num?)?.toDouble() ?? (s['currentPrice'] as num?)?.toDouble() ?? 0;
        if (code.isNotEmpty && price > 0) {
          stocks.add(_StockBrief(code: code, name: name, price: price));
        }
      }
    } catch (e) {
      debugPrint('[极速投资] 提取股票异常: $e');
    }
    return stocks;
  }
}

class _StockBrief {
  final String code;
  final String name;
  final double price;
  const _StockBrief({required this.code, required this.name, required this.price});
}
