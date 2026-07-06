/// API服务 - 负责与后端通信，带异常处理和离线fallback
///
/// 设计原则:
/// 1. 所有网络调用都有超时保护
/// 2. 网络失败自动使用本地模拟数据（确保APP可用）
/// 3. 所有JSON解析都有类型安全保护
/// 4. 支持配置后端地址

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/stock_model.dart';

class ApiService {
  /// 后端API基础地址
  ///
  /// 模拟器访问本机后端: 10.0.2.2
  /// 真机访问: 需要改为实际IP，如 192.168.1.x
  /// 也可通过构造函数传入
  String baseUrl;

  /// 请求超时 (秒)
  static const int _timeoutSeconds = 60;

  /// 是否使用离线模式 (不发起网络请求)
  bool _offlineMode = false;

  ApiService({String? apiUrl})
      : baseUrl = apiUrl ?? 'https://8000-5af995f6821c46338775eccd2608ab00.e2b.bj7.sandbox.cloudstudio.club';

  /// 手动设置API地址
  void updateBaseUrl(String url) {
    baseUrl = url;
    _offlineMode = false; // 切换地址时重置离线模式
  }

  /// 切换离线模式
  void setOfflineMode(bool offline) {
    _offlineMode = offline;
  }

  // ============================================================
  // 搜索证券/基金 (核心功能)
  // ============================================================

  /// 搜索证券 - 输入任意代码获取实时数据+AI建议
  ///
  /// 支持: A股(600519)、港股(0700.HK)、美股(AAPL)
  /// 后端自动识别代码格式，返回实时行情+AI分析
  Future<Map<String, dynamic>> searchStock(String query) async {
    if (query.trim().isEmpty) {
      throw Exception('请输入股票/基金代码');
    }

    try {
      final uri = Uri.parse('$baseUrl/api/search')
          .replace(queryParameters: {'q': query.trim()});

      final response = await http.get(uri).timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(data['detail'] ?? '未找到该证券数据');
      } else if (response.statusCode == 400) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(data['detail'] ?? '请求参数错误');
      } else {
        throw Exception('服务器错误 (${response.statusCode})');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查网络连接');
    } on http.ClientException {
      throw Exception('网络连接失败，请确保后端服务已启动');
    } on FormatException {
      throw Exception('数据格式错误');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('未知错误: $e');
    }
  }

  // ============================================================
  // 获取推荐股票
  // ============================================================

  /// 获取推荐股票列表
  ///
  /// [market]: A(A股)/HK(港股)/US(美股)
  /// [topN]: 返回Top N只股票
  ///
  /// 网络失败时自动返回模拟数据
  Future<SelectionResponse> getRecommendations({
    String market = 'A',
    int topN = 5,
  }) async {
    if (_offlineMode) {
      return _getMockRecommendations(market);
    }

    try {
      final uri = Uri.parse('$baseUrl/api/stocks/recommend')
          .replace(queryParameters: {'market': market, 'top_n': topN.toString()});

      final response = await http.get(uri).timeout(
        Duration(seconds: _timeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return SelectionResponse.fromJson(data);
      } else {
        debugPrint('[API] 推荐接口返回 ${response.statusCode}');
        return _getMockRecommendations(market);
      }
    } on TimeoutException {
      debugPrint('[API] 推荐接口超时，使用离线数据');
      return _getMockRecommendations(market);
    } on http.ClientException catch (e) {
      debugPrint('[API] 网络错误: $e');
      return _getMockRecommendations(market);
    } on FormatException catch (e) {
      debugPrint('[API] 数据格式错误: $e');
      return _getMockRecommendations(market);
    } catch (e) {
      debugPrint('[API] 未知错误: $e');
      return _getMockRecommendations(market);
    }
  }

  // ============================================================
  // 获取股票详情
  // ============================================================

  Future<StockDetail> getStockDetail(String symbol) async {
    if (_offlineMode) {
      return _getMockDetail(symbol);
    }

    try {
      final uri = Uri.parse('$baseUrl/api/stocks/$symbol/detail');
      final response = await http.get(uri).timeout(
        Duration(seconds: _timeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return StockDetail.fromJson(data);
      } else {
        return _getMockDetail(symbol);
      }
    } catch (e) {
      debugPrint('[API] 详情接口错误: $e');
      return _getMockDetail(symbol);
    }
  }

  // ============================================================
  // 获取回测结果
  // ============================================================

  Future<BacktestResult> getBacktest(String symbol) async {
    if (_offlineMode) {
      return _getMockBacktest(symbol);
    }

    try {
      final uri = Uri.parse('$baseUrl/api/stocks/$symbol/backtest');
      final response = await http.get(uri).timeout(
        Duration(seconds: _timeoutSeconds),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        return BacktestResult.fromJson(data);
      } else {
        return _getMockBacktest(symbol);
      }
    } catch (e) {
      debugPrint('[API] 回测接口错误: $e');
      return _getMockBacktest(symbol);
    }
  }

  // ============================================================
  // 健康检查
  // ============================================================

  /// 检查后端是否可用
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$baseUrl/api/health');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 模拟数据 (离线/演示模式)
  // 数据结构完全匹配API返回格式，确保前端逻辑一致
  // ============================================================

  SelectionResponse _getMockRecommendations(String market) {
    final mockStocks = [
      StockRecommendation(
        symbol: '600519.SS',
        name: '贵州茅台',
        price: 1688.50,
        changePct: 1.25,
        action: 'buy',
        score: 0.82,
        shortTermWinRate: 0.72,
        trend: 'bullish',
        reason: '基本面优秀；技术面看多；均线多头排列',
        risk: ['估值偏高(PE=35.2)，注意泡沫风险', '市场系统性风险不可忽视'],
        detail: {
          'fundamental_score': 0.75,
          'technical_score': 0.85,
          'capital_score': 0.70,
          'momentum_score': 0.80,
        },
        technicalIndicators: {
          'ma5': 1680.0, 'ma10': 1665.0, 'ma20': 1640.0,
          'rsi': 58.5, 'macd': 2.35,
          'bullish_alignment': true,
          'macd_golden_cross': true,
          'volume_surge': true,
        },
        dataSource: 'offline',
      ),
      StockRecommendation(
        symbol: '000858.SZ',
        name: '五粮液',
        price: 158.30,
        changePct: 0.85,
        action: 'buy',
        score: 0.76,
        shortTermWinRate: 0.68,
        trend: 'bullish',
        reason: '基本面良好；技术面看多；资金流入明显',
        risk: ['市场系统性风险不可忽视'],
        detail: {
          'fundamental_score': 0.72,
          'technical_score': 0.78,
          'capital_score': 0.68,
          'momentum_score': 0.72,
        },
        technicalIndicators: {
          'ma5': 156.0, 'ma10': 154.5, 'ma20': 152.0,
          'rsi': 55.2, 'macd': 1.12,
          'bullish_alignment': true,
          'macd_golden_cross': false,
          'volume_surge': false,
        },
        dataSource: 'offline',
      ),
      StockRecommendation(
        symbol: '601318.SS',
        name: '中国平安',
        price: 48.65,
        changePct: -0.31,
        action: 'hold',
        score: 0.58,
        shortTermWinRate: 0.55,
        trend: 'neutral',
        reason: '综合评估中性',
        risk: ['市场系统性风险不可忽视'],
        detail: {
          'fundamental_score': 0.60,
          'technical_score': 0.55,
          'capital_score': 0.50,
          'momentum_score': 0.55,
        },
        technicalIndicators: {
          'ma5': 48.80, 'ma10': 49.10, 'ma20': 48.50,
          'rsi': 48.3, 'macd': -0.15,
          'bullish_alignment': false,
          'macd_golden_cross': false,
          'volume_surge': false,
        },
        dataSource: 'offline',
      ),
      StockRecommendation(
        symbol: '600036.SS',
        name: '招商银行',
        price: 35.20,
        changePct: 0.57,
        action: 'buy',
        score: 0.71,
        shortTermWinRate: 0.65,
        trend: 'bullish',
        reason: '基本面良好；MACD金叉',
        risk: ['市场系统性风险不可忽视'],
        detail: {
          'fundamental_score': 0.70,
          'technical_score': 0.72,
          'capital_score': 0.60,
          'momentum_score': 0.68,
        },
        technicalIndicators: {
          'ma5': 35.0, 'ma10': 34.80, 'ma20': 34.50,
          'rsi': 52.8, 'macd': 0.45,
          'bullish_alignment': true,
          'macd_golden_cross': true,
          'volume_surge': false,
        },
        dataSource: 'offline',
      ),
      StockRecommendation(
        symbol: '000333.SZ',
        name: '美的集团',
        price: 62.80,
        changePct: 1.53,
        action: 'buy',
        score: 0.73,
        shortTermWinRate: 0.66,
        trend: 'bullish',
        reason: '基本面良好；技术面看多；量能放大',
        risk: ['市场系统性风险不可忽视'],
        detail: {
          'fundamental_score': 0.68,
          'technical_score': 0.75,
          'capital_score': 0.65,
          'momentum_score': 0.76,
        },
        technicalIndicators: {
          'ma5': 62.0, 'ma10': 61.50, 'ma20': 60.80,
          'rsi': 56.7, 'macd': 0.89,
          'bullish_alignment': true,
          'macd_golden_cross': false,
          'volume_surge': true,
        },
        dataSource: 'offline',
      ),
    ];

    return SelectionResponse(
      timestamp: DateTime.now().toIso8601String(),
      market: market == 'A' ? 'A股' : market,
      totalAnalyzed: 20,
      recommendations: mockStocks,
      disclaimer: '本工具仅供参考，不构成投资建议。投资有风险，入市需谨慎。（离线数据）',
    );
  }

  StockDetail _getMockDetail(String symbol) {
    return StockDetail(
      symbol: symbol,
      name: '模拟数据',
      price: 100.0,
      changePct: 1.5,
      marketCap: 500000000000,
      marketCapDisplay: '5000亿',
      peRatio: 25.6,
      roe: 0.18,
      revenueGrowth: 0.15,
      eps: 3.91,
      technicalIndicators: {
        'ma5': 99.5, 'ma10': 98.8, 'ma20': 97.2,
        'rsi': 55.0, 'macd': 0.5,
        'bullish_alignment': true,
        'macd_golden_cross': false,
        'volume_surge': false,
      },
      aiAnalysis: {
        'score': 0.75,
        'short_term_win_rate': 0.65,
        'trend': 'bullish',
        'action': 'buy',
        'reason': '综合评估看多',
        'risk': ['市场系统性风险不可忽视'],
        'ai_source': 'local_rules',
      },
      dataSource: 'offline',
      disclaimer: '本工具仅供参考，不构成投资建议。（离线数据）',
    );
  }

  BacktestResult _getMockBacktest(String symbol) {
    return BacktestResult(
      symbol: symbol,
      winRate: 0.62,
      avgReturn: '5.8%',
      maxDrawdown: '12.3%',
      totalTrades: 8,
    );
  }
}
