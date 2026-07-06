/// 市场概览组件 - 紧凑单行5指标布局
/// 
/// 显示实时市场情绪、涨跌家数、北向资金、AI温度等核心指标
/// 位置：首页搜索栏下方

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/market_overview_service.dart';
import '../theme/app_theme.dart';

class MarketOverviewWidget extends StatefulWidget {
  const MarketOverviewWidget({Key? key}) : super(key: key);

  @override
  State<MarketOverviewWidget> createState() => _MarketOverviewWidgetState();
}

class _MarketOverviewWidgetState extends State<MarketOverviewWidget> {
  MarketOverviewData _data = MarketOverviewData.empty();
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 每30秒刷新一次
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    
    final data = await MarketOverviewService.fetchOverviewData();
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    
    return Container(
      // 不设置margin，由外层padding统一控制宽度
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface, // 根据主题切换背景色
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：标题 + 实时更新标签 + 更新时间
          Row(
            children: [
              Text(
                '市场概览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              // 实时更新标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '实时更新',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // 更新时间
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '更新于 ${_formatTime(_data.updateTime)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _loading ? null : _loadData,
                    child: _loading
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textSecondary,
                          ),
                        )
                      : Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 5个指标一行
          Row(
            children: [
              // 1. 市场情绪
              Expanded(
                child: _buildIndicator(
                  context: context,
                  label: '市场情绪',
                  mainValue: '${_data.sentiment}',
                  subValue: _data.sentimentLabel,
                  subColor: _getSentimentColor(_data.sentiment, colors),
                  showProgress: true,
                  progressValue: _data.sentiment / 100,
                  progressColor: _getSentimentColor(_data.sentiment, colors),
                ),
              ),
              
              // 2. 上涨家数
              Expanded(
                child: _buildIndicator(
                  context: context,
                  label: '上涨家数',
                  mainValue: _data.upCount > 0 ? '${_data.upCount}' : '--',
                  subValue: _data.upPercent != 0 ? '+${_data.upPercent.toStringAsFixed(2)}%' : '--',
                  mainColor: colors.up,
                  subColor: colors.up,
                ),
              ),
              
              // 3. 下跌家数
              Expanded(
                child: _buildIndicator(
                  context: context,
                  label: '下跌家数',
                  mainValue: _data.downCount > 0 ? '${_data.downCount}' : '--',
                  subValue: _data.downPercent != 0 ? '${_data.downPercent.toStringAsFixed(2)}%' : '--',
                  mainColor: colors.down,
                  subColor: colors.down,
                ),
              ),
              
              // 4. 北向资金（方案3：显示成交总额）
              Expanded(
                child: _buildIndicator(
                  context: context,
                  label: '北向资金',
                  mainValue: _data.northMoneyAvailable && _data.northMoney != 0
                    ? '${_data.northMoney.toStringAsFixed(1)}亿'
                    : '暂无数据',
                  subValue: _data.northMoneyAvailable
                    ? (_data.northMoneyIsTotal ? '成交' : _data.northMoneyLabel)
                    : '',
                  mainColor: _data.northMoneyAvailable && _data.northMoney != 0
                    ? colors.primary
                    : colors.textSecondary,
                  subColor: _data.northMoneyAvailable && _data.northMoney != 0
                    ? colors.primary
                    : colors.textSecondary,
                ),
              ),
              
              // 5. AI温度
              Expanded(
                child: _buildIndicator(
                  context: context,
                  label: 'AI温度',
                  mainValue: '${_data.aiTemperature}',
                  subValue: _data.aiTempLabel,
                  mainColor: colors.primary,
                  subColor: colors.primary,
                  suffix: '℃',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个指标组件
  Widget _buildIndicator({
    required BuildContext context,
    required String label,
    required String mainValue,
    String? subValue,
    Color? mainColor,
    Color? subColor,
    bool showProgress = false,
    double progressValue = 0,
    Color? progressColor,
    String? suffix,
  }) {
    final colors = AppColors.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 标签
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        // 主数值
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mainValue,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: mainColor ?? colors.textPrimary,
              ),
            ),
            if (suffix != null)
              Text(
                suffix,
                style: TextStyle(
                  fontSize: 12,
                  color: mainColor ?? colors.textPrimary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // 副数值或进度条
        if (showProgress && progressColor != null) ...[
          // 进度条
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progressValue,
              child: Container(
                decoration: BoxDecoration(
                  color: progressColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // 标签
          Text(
            subValue ?? '',
            style: TextStyle(
              fontSize: 10,
              color: subColor ?? colors.textSecondary,
            ),
          ),
        ] else ...[
          // 副数值
          Text(
            subValue ?? '',
            style: TextStyle(
              fontSize: 11,
              color: subColor ?? colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Color _getSentimentColor(int sentiment, AppColorScheme colors) {
    if (sentiment >= 65) return colors.up;
    if (sentiment >= 45) return colors.primary; // 蓝色
    return colors.down;
  }
}
