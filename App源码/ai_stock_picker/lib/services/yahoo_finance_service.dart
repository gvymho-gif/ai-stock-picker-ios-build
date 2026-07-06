/// Yahoo Finance 数据服务
///
/// 为港股和美股补充财务数据，解决腾讯API缺失的字段：
/// - PB/ROE/EPS/营收增速/股息率/行业/板块/公司简介等
///
/// API端点:
/// - 实时行情: /v8/finance/chart/{symbol}
/// - 财务数据: /v10/finance/quoteSummary/{symbol}?modules=...
/// - 股票搜索: /v1/finance/search?q={query}

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class YahooFinanceService {
  static const String _baseUrl = 'https://query1.finance.yahoo.com';
  static const String _baseUrl2 = 'https://query2.finance.yahoo.com';
  static const int _timeoutSeconds = 15;
  static final http.Client _client = http.Client();

  // 缓存：避免重复请求同一股票
  static final Map<String, Map<String, dynamic>> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// 获取股票综合数据（行情+财务+概况）
  Future<Map<String, dynamic>?> fetchFullData(String symbol) async {
    try {
      // 并发请求行情和财务数据
      final results = await Future.wait([
        fetchQuoteSummary(symbol),
        fetchChart(symbol),
      ]);

      final quoteData = results[0];
      final chartData = results[1];

      if (quoteData == null && chartData == null) return null;

      // 合并数据
      final combined = <String, dynamic>{};
      if (quoteData != null) combined.addAll(quoteData);
      if (chartData != null) {
        // 如果quoteData没有价格，用chartData补充
        combined['price'] ??= chartData['price'];
        combined['change_pct'] ??= chartData['change_pct'];
        combined['volume'] ??= chartData['volume'];
      }

      combined['source'] = 'yahoo';
      return combined;
    } catch (_) {
      return null;
    }
  }

  /// 获取实时行情（从Chart API）
  Future<Map<String, dynamic>?> fetchChart(String symbol) async {
    try {
      final url = '$_baseUrl/v8/finance/chart/$symbol?interval=1d&range=1d';
      final resp = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      ).timeout(const Duration(seconds: _timeoutSeconds));

      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body);
      final result = data['chart']?['result'];
      if (result == null || result is! List || result.isEmpty) return null;

      final meta = result[0]['meta'] as Map<String, dynamic>?;
      if (meta == null) return null;

      final quote = result[0]['indicators']?['quote']?[0] as Map<String, dynamic>?;
      final close = quote?['close'] as List?;
      final open = quote?['open'] as List?;
      final high = quote?['high'] as List?;
      final low = quote?['low'] as List?;
      final volume = quote?['volume'] as List?;

      final price = _getLastValue(close);
      final prevClose = _safeDouble(meta['previousClose']);
      final changePct = prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0.0;

      return {
        'symbol': symbol,
        'name': meta['shortName'] ?? meta['symbol'],
        'price': _round(price, 3),
        'prev_close': _round(prevClose, 3),
        'open': _round(_getLastValue(open), 3),
        'high': _round(_getLastValue(high), 3),
        'low': _round(_getLastValue(low), 3),
        'change_pct': _round(changePct, 2),
        'change_amt': _round(price - prevClose, 3),
        'volume': _safeInt(_getLastValue(volume)),
        'market_cap': _safeDouble(meta['marketCap']),
        'currency': meta['currency'] ?? 'USD',
        'exchange': meta['exchangeName'] ?? meta['exchange'],
        'source': 'yahoo_chart',
      };
    } catch (_) {
      return null;
    }
  }

  /// 获取财务统计数据（PE/PB/ROE/EPS/股息率等）
  Future<Map<String, dynamic>?> fetchQuoteSummary(String symbol) async {
    // 检查缓存
    final cacheKey = 'quote_$symbol';
    if (_cache.containsKey(cacheKey) &&
        DateTime.now().difference(_cacheTime[cacheKey]!) < _cacheExpiry) {
      return _cache[cacheKey];
    }

    try {
      final modules = 'price,summaryDetail,defaultKeyStatistics,financialData,assetProfile';
      final url = '$_baseUrl2/v10/finance/quoteSummary/$symbol?modules=$modules';
      final resp = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      ).timeout(const Duration(seconds: _timeoutSeconds));

      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body);
      final result = data['quoteSummary']?['result'];
      if (result == null || result is! List || result.isEmpty) return null;

      final summary = result[0] as Map<String, dynamic>;
      final priceData = summary['price'] as Map<String, dynamic>?;
      final summaryDetail = summary['summaryDetail'] as Map<String, dynamic>?;
      final keyStats = summary['defaultKeyStatistics'] as Map<String, dynamic>?;
      final financialData = summary['financialData'] as Map<String, dynamic>?;
      final assetProfile = summary['assetProfile'] as Map<String, dynamic>?;

      final resultData = _parseQuoteSummary(
        symbol,
        priceData,
        summaryDetail,
        keyStats,
        financialData,
        assetProfile,
      );

      // 缓存结果
      _cache[cacheKey] = resultData;
      _cacheTime[cacheKey] = DateTime.now();

      return resultData;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _parseQuoteSummary(
    String symbol,
    Map<String, dynamic>? priceData,
    Map<String, dynamic>? summaryDetail,
    Map<String, dynamic>? keyStats,
    Map<String, dynamic>? financialData,
    Map<String, dynamic>? assetProfile,
  ) {
    // 从 price 提取
    final regularMarketPrice = _extractRawValue(priceData, 'regularMarketPrice');
    final regularMarketChange = _extractRawValue(priceData, 'regularMarketChange');
    final regularMarketChangePercent = _extractRawValue(priceData, 'regularMarketChangePercent');

    // 从 summaryDetail 提取
    final marketCap = _extractRawValue(summaryDetail, 'marketCap');
    final dividendYield = _extractRawValue(summaryDetail, 'dividendYield');
    final fiftyTwoWeekHigh = _extractRawValue(summaryDetail, 'fiftyTwoWeekHigh');
    final fiftyTwoWeekLow = _extractRawValue(summaryDetail, 'fiftyTwoWeekLow');
    final peRatio = _extractRawValue(summaryDetail, 'trailingPE') ?? _extractRawValue(summaryDetail, 'forwardPE');
    final pbRatio = _extractRawValue(summaryDetail, 'priceToBook');
    final beta = _extractRawValue(summaryDetail, 'beta');
    final avgVolume = _extractRawValue(summaryDetail, 'averageDailyVolume10Day');

    // 从 defaultKeyStatistics 提取
    final trailingEps = _extractRawValue(keyStats, 'trailingEps');
    final forwardEps = _extractRawValue(keyStats, 'forwardEps');
    final priceToBook = _extractRawValue(keyStats, 'priceToBook');
    final pegRatio = _extractRawValue(keyStats, 'pegRatio');
    final enterpriseValue = _extractRawValue(keyStats, 'enterpriseValue');
    final profitMargins = _extractRawValue(keyStats, 'profitMargins');
    final sharesOutstanding = _extractRawValue(keyStats, 'sharesOutstanding');

    // 从 financialData 提取
    final returnOnEquity = _extractRawValue(financialData, 'returnOnEquity');
    final returnOnAssets = _extractRawValue(financialData, 'returnOnAssets');
    final revenueGrowth = _extractRawValue(financialData, 'revenueGrowth');
    final grossMargins = _extractRawValue(financialData, 'grossMargins');
    final operatingMargins = _extractRawValue(financialData, 'operatingMargins');
    final ebitdaMargins = _extractRawValue(financialData, 'ebitdaMargins');
    final totalCash = _extractRawValue(financialData, 'totalCash');
    final totalDebt = _extractRawValue(financialData, 'totalDebt');
    final freeCashflow = _extractRawValue(financialData, 'freeCashflow');
    final operatingCashflow = _extractRawValue(financialData, 'operatingCashflow');
    final totalRevenue = _extractRawValue(financialData, 'totalRevenue');
    final netIncomeToCommon = _extractRawValue(financialData, 'netIncomeToCommon');
    final earningsGrowth = _extractRawValue(financialData, 'earningsGrowth');

    // 从 assetProfile 提取
    final industry = assetProfile?['industry'] as String?;
    final sector = assetProfile?['sector'] as String?;
    final description = assetProfile?['longBusinessSummary'] as String?;
    final country = assetProfile?['country'] as String?;
    final city = assetProfile?['city'] as String?;
    final website = assetProfile?['website'] as String?;
    final fullTimeEmployees = assetProfile?['fullTimeEmployees'];

    return {
      'symbol': symbol,
      'name': priceData?['shortName'] ?? priceData?['longName'] ?? symbol,

      // 价格数据
      'price': _round(regularMarketPrice, 3),
      'change_amt': _round(regularMarketChange, 3),
      'change_pct': _round(regularMarketChangePercent, 2),
      'prev_close': _round(_safeDouble(priceData?['regularMarketPreviousClose']), 3),

      // 市值与估值
      'market_cap': marketCap,
      'pe_ratio': _round(peRatio, 2),
      'pb_ratio': _round(pbRatio ?? priceToBook, 2),
      'ps_ratio': _round(marketCap != null && totalRevenue != null && totalRevenue > 0
          ? marketCap / totalRevenue : null, 2),
      'peg_ratio': _round(pegRatio, 2),
      'beta': _round(beta, 2),
      'enterprise_value': enterpriseValue,

      // 收益指标
      'eps': trailingEps ?? forwardEps,
      'roe': returnOnEquity != null ? _round(returnOnEquity * 100, 2) : null,
      'roa': returnOnAssets != null ? _round(returnOnAssets * 100, 2) : null,

      // 成长指标
      'revenue_growth': revenueGrowth != null ? _round(revenueGrowth * 100, 2) : null,
      'earnings_growth': earningsGrowth != null ? _round(earningsGrowth * 100, 2) : null,

      // 利润率
      'gross_margin': grossMargins != null ? _round(grossMargins * 100, 2) : null,
      'operating_margin': operatingMargins != null ? _round(operatingMargins * 100, 2) : null,
      'net_margin': profitMargins != null ? _round(profitMargins * 100, 2) : null,
      'ebitda_margin': ebitdaMargins != null ? _round(ebitdaMargins * 100, 2) : null,

      // 股息
      'dividend_yield': dividendYield != null ? _round(dividendYield * 100, 2) : null,

      // 现金流与债务
      'total_cash': totalCash,
      'total_debt': totalDebt,
      'free_cashflow': freeCashflow,
      'operating_cashflow': operatingCashflow,
      'total_revenue': totalRevenue,
      'net_income': netIncomeToCommon,

      // 52周范围
      'week52_high': _round(fiftyTwoWeekHigh, 3),
      'week52_low': _round(fiftyTwoWeekLow, 3),

      // 成交量
      'avg_volume': avgVolume,
      'shares_outstanding': sharesOutstanding,

      // 公司信息
      'industry': industry,
      'sector': sector,
      'description': description,
      'country': country,
      'city': city,
      'website': website,
      'employees': fullTimeEmployees,

      'source': 'yahoo_summary',
    };
  }

  /// 股票搜索
  Future<List<Map<String, dynamic>>> searchStocks(String query, {String? market}) async {
    try {
      final url = '$_baseUrl/v1/finance/search?q=${Uri.encodeComponent(query)}&quotesCount=20&newsCount=0';
      final resp = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'},
      ).timeout(const Duration(seconds: _timeoutSeconds));

      if (resp.statusCode != 200) return [];

      final data = json.decode(resp.body);
      final quotes = data['quotes'] as List?;
      if (quotes == null) return [];

      final results = <Map<String, dynamic>>[];

      for (final quote in quotes) {
        final q = quote as Map<String, dynamic>;
        final symbol = q['symbol'] as String?;
        final quoteType = q['quoteType'] as String?;
        final exchange = q['exchange'] as String?;

        if (symbol == null) continue;

        // 过滤市场类型
        if (market != null) {
          if (market == 'HK' && quoteType != 'EQUITY') continue;
          if (market == 'US' && quoteType != 'EQUITY') continue;
          if (market == 'HK' && exchange != 'HKG' && !symbol.contains('.HK')) continue;
          if (market == 'US' && exchange != 'NMS' && exchange != 'NYQ' && exchange != 'PNK') continue;
        }

        // 构建标准符号格式
        String standardSymbol = symbol;
        if (exchange == 'HKG' && !symbol.contains('.HK')) {
          // 港股标准化为 0700.HK 格式
          standardSymbol = symbol.padLeft(5, '0') + '.HK';
        }

        results.add({
          'symbol': standardSymbol,
          'name': q['shortname'] ?? q['longname'] ?? q['symbol'],
          'exchange': exchange,
          'quote_type': quoteType,
          'market': exchange == 'HKG' || symbol.contains('.HK') ? 'HK' :
                    (exchange == 'NMS' || exchange == 'NYQ' ? 'US' : 'OTHER'),
        });
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  /// 批量获取多只股票数据
  Future<Map<String, Map<String, dynamic>>> fetchBatchQuotes(List<String> symbols) async {
    final results = <String, Map<String, dynamic>>{};

    // 并发请求，但限制并发数
    const batchSize = 5;
    for (var i = 0; i < symbols.length; i += batchSize) {
      final batch = symbols.sublist(i, i + batchSize > symbols.length ? symbols.length : i + batchSize);
      final futures = batch.map((s) async {
        final data = await fetchQuoteSummary(s);
        return MapEntry(s, data);
      });

      final entries = await Future.wait(futures);
      for (final entry in entries) {
        if (entry.value != null) {
          results[entry.key] = entry.value!;
        }
      }

      // 避免请求过于频繁
      if (i + batchSize < symbols.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    return results;
  }

  /// 清除缓存
  void clearCache() {
    _cache.clear();
    _cacheTime.clear();
  }

  // ============ 辅助方法 ============

  double _extractRawValue(Map<String, dynamic>? data, String key) {
    if (data == null || !data.containsKey(key)) return 0;
    final value = data[key];
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is Map) {
      // Yahoo 有时返回 {raw: 123, fmt: "123"} 格式
      final raw = value['raw'];
      if (raw is num) return raw.toDouble();
    }
    return 0;
  }

  double _safeDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  int _safeInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _round(double? value, int decimals) {
    if (value == null || value.isNaN || value.isInfinite) return 0;
    final factor = pow(10, decimals);
    return (value * factor).round() / factor;
  }

  double _getLastValue(List? list) {
    if (list == null || list.isEmpty) return 0;
    for (var i = list.length - 1; i >= 0; i--) {
      final val = list[i];
      if (val != null && val is num && val > 0) return val.toDouble();
    }
    return 0;
  }

  double pow(double x, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= x;
    }
    return result;
  }
}
