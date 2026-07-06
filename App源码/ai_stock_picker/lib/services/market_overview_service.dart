/// 市场概览服务 - 实时获取大盘数据
/// 
/// 数据来源：
/// - 上涨/下跌家数：新浪行情中心API
/// - 市场情绪：基于涨跌家数比例计算
/// - AI温度：基于成交量和涨跌家数综合计算
/// - 北向资金：东方财富API（ForeignHolderService）

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'foreign_holder_service.dart';

class MarketOverviewData {
  /// 市场情绪值 0-100（67偏强）
  final int sentiment;
  /// 市场情绪描述（偏强/中性/偏弱）
  final String sentimentLabel;
  /// 情绪进度条颜色
  final int sentimentColor;
  
  /// 上涨家数
  final int upCount;
  /// 上涨百分比（+1.32%）
  final double upPercent;
  
  /// 下跌家数
  final int downCount;
  /// 下跌百分比（-0.86%）
  final double downPercent;
  
  /// 北向资金（亿）- 当显示成交总额时为成交额
  final double northMoney;
  /// 北向资金流向（净流入/净流出/成交）
  final String northMoneyLabel;
  
  /// AI温度（0-100℃）
  final int aiTemperature;
  /// 市场活跃度描述
  final String aiTempLabel;
  
  /// 北向资金数据是否可用
  final bool northMoneyAvailable;
  /// 北向资金显示的是成交总额（true）还是净流入（false）
  final bool northMoneyIsTotal;

  /// 最后更新时间
  final DateTime updateTime;

  MarketOverviewData({
    required this.sentiment,
    required this.sentimentLabel,
    required this.sentimentColor,
    required this.upCount,
    required this.upPercent,
    required this.downCount,
    required this.downPercent,
    required this.northMoney,
    required this.northMoneyLabel,
    required this.northMoneyAvailable,
    required this.northMoneyIsTotal,
    required this.aiTemperature,
    required this.aiTempLabel,
    required this.updateTime,
  });

  factory MarketOverviewData.empty() {
    return MarketOverviewData(
      sentiment: 50,
      sentimentLabel: '中性',
      sentimentColor: 0xFFFFA500,
      upCount: 0,
      upPercent: 0,
      downCount: 0,
      downPercent: 0,
      northMoney: 0,
      northMoneyLabel: '成交',
      northMoneyAvailable: false,
      northMoneyIsTotal: true,
      aiTemperature: 50,
      aiTempLabel: '一般',
      updateTime: DateTime.now(),
    );
  }
}

class MarketOverviewService {
  static final _client = http.Client();
  static const _httpTimeout = Duration(seconds: 10);

  /// 获取市场概览数据
  static Future<MarketOverviewData> fetchOverviewData() async {
    try {
      // 获取涨跌家数统计
      final marketStats = await _fetchMarketStats();
      
      // 获取北向资金（使用 ForeignHolderService 的真实数据）
      final northMoney = await _fetchNorthMoney();
      
      // 计算情绪指标
      final sentiment = _calcSentiment(marketStats['upCount'], marketStats['downCount']);
      
      // 计算AI温度
      final aiTemp = _calcAITemperature(marketStats['upCount'], marketStats['downCount'], marketStats['totalVolume']);
      
      return MarketOverviewData(
        sentiment: sentiment['value'] as int,
        sentimentLabel: sentiment['label'] as String,
        sentimentColor: sentiment['color'] as int,
        upCount: marketStats['upCount'] as int,
        upPercent: marketStats['upPercent'] as double,
        downCount: marketStats['downCount'] as int,
        downPercent: marketStats['downPercent'] as double,
        northMoney: northMoney['amount'] as double,
        northMoneyLabel: northMoney['label'] as String,
        northMoneyAvailable: northMoney['available'] as bool,
        northMoneyIsTotal: northMoney['is_total'] as bool? ?? false,
        aiTemperature: aiTemp['value'] as int,
        aiTempLabel: aiTemp['label'] as String,
        updateTime: DateTime.now(),
      );
    } catch (e) {
      print('[市场概览] 获取数据失败: $e');
      return MarketOverviewData.empty();
    }
  }

  /// 获取市场涨跌家数统计（东方财富实时数据，非采样）
  /// 上证指数(1.000001)覆盖全部沪市A股，深证综指(0.399106)覆盖全部深市A股
  static Future<Map<String, dynamic>> _fetchMarketStats() async {
    try {
      // 沪市涨跌家数 + 成交额
      final shResp = await _client.get(
        Uri.parse('https://push2.eastmoney.com/api/qt/stock/get?secid=1.000001&fields=f170,f171,f48'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://quote.eastmoney.com'},
      ).timeout(_httpTimeout);

      // 深市涨跌家数 + 成交额
      final szResp = await _client.get(
        Uri.parse('https://push2.eastmoney.com/api/qt/stock/get?secid=0.399106&fields=f170,f171,f48'),
        headers: {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://quote.eastmoney.com'},
      ).timeout(_httpTimeout);

      int shUp = 0, shDown = 0, szUp = 0, szDown = 0;
      double totalVolume = 0;

      if (shResp.statusCode == 200) {
        final shData = json.decode(shResp.body)['data'] as Map<String, dynamic>?;
        if (shData != null) {
          shUp = _safeInt(shData['f170']);
          shDown = _safeInt(shData['f171']);
          totalVolume += _safeDouble(shData['f48']);
        }
      }

      if (szResp.statusCode == 200) {
        final szData = json.decode(szResp.body)['data'] as Map<String, dynamic>?;
        if (szData != null) {
          szUp = _safeInt(szData['f170']);
          szDown = _safeInt(szData['f171']);
          totalVolume += _safeDouble(szData['f48']);
        }
      }

      final upCount = shUp + szUp;
      final downCount = shDown + szDown;
      final total = upCount + downCount;
      final upPercent = total > 0 ? (upCount / total * 100) : 0;
      final downPercent = total > 0 ? (downCount / total * 100) : 0;

      return {
        'upCount': upCount,
        'downCount': downCount,
        'flatCount': 0,          // 东方财富接口不返回平盘数
        'total': total,
        'upPercent': upPercent,
        'downPercent': -downPercent,
        'totalVolume': totalVolume,
      };
    } catch (_) {
      return {'upCount': 0, 'downCount': 0, 'flatCount': 0, 'total': 0, 'upPercent': 0.0, 'downPercent': 0.0, 'totalVolume': 0.0};
    }
  }

  static int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  /// 获取北向资金（方案3：显示当日成交总额）
  /// 交易所2024年8月起停止披露北向净流入，但成交总额(buySellAmt)仍可获取
  static Future<Map<String, dynamic>> _fetchNorthMoney() async {
    try {
      final data = await ForeignHolderService.fetchNorthSouthFlow();
      final northNet = data['north_net'] as double? ?? 0.0;
      final northTotalAmount = data['north_total_amount'] as double? ?? 0.0;
      final available = data['north_available'] as bool? ?? false;
      final isTotal = data['north_is_total'] as bool? ?? false;

      if (isTotal && available && northTotalAmount > 0) {
        // 方案3：显示北向成交总额
        return {
          'amount': northTotalAmount,
          'label': '成交',
          'available': true,
          'is_total': true,
        };
      } else if (available && northNet != 0) {
        // 如果未来恢复了净流入数据
        return {
          'amount': northNet.abs(),
          'label': northNet >= 0 ? '净流入' : '净流出',
          'available': true,
          'is_total': false,
        };
      }
      // 数据不可用
      return {
        'amount': 0.0,
        'label': '暂无数据',
        'available': false,
        'is_total': false,
      };
    } catch (e) {
      print('[市场概览] 北向资金获取失败: $e');
    }

    return {'amount': 0.0, 'label': '暂无数据', 'available': false, 'is_total': false};
  }

  /// 计算市场情绪
  /// 基于涨跌家数比例，0-100分
  static Map<String, dynamic> _calcSentiment(int upCount, int downCount) {
    final total = upCount + downCount;
    if (total == 0) {
      return {'value': 50, 'label': '中性', 'color': 0xFFFFA500};
    }
    
    final ratio = upCount / total;
    final sentiment = (ratio * 100).round();
    
    String label;
    int color;
    if (sentiment >= 65) {
      label = '偏强';
      color = 0xFFFF4444; // 红色
    } else if (sentiment >= 45) {
      label = '中性';
      color = 0xFFFFA500; // 橙色
    } else {
      label = '偏弱';
      color = 0xFF44FF44; // 绿色
    }
    
    return {'value': sentiment, 'label': label, 'color': color};
  }

  /// 计算AI温度
  /// 综合成交量、涨跌家数等因素，0-100℃
  static Map<String, dynamic> _calcAITemperature(int upCount, int downCount, double totalVolume) {
    final total = upCount + downCount;
    if (total == 0) {
      return {'value': 50, 'label': '一般'};
    }
    
    // 基础温度：上涨比例
    double baseTemp = (upCount / total) * 60;
    
    // 活跃度加成（假设1000亿成交量为基准）
    double volumeFactor = math.min(totalVolume / 1000000000000, 1.0) * 40;
    
    // 最终温度
    int temperature = (baseTemp + volumeFactor).round();
    temperature = math.max(0, math.min(100, temperature));
    
    String label;
    if (temperature >= 70) label = '活跃';
    else if (temperature >= 50) label = '一般';
    else if (temperature >= 30) label = '冷淡';
    else label = '极冷';
    
    return {'value': temperature, 'label': label};
  }

  static double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }
}
