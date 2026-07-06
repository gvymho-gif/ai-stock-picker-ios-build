/// 板块股票详情页面
/// 显示指定板块的前50只股票及涨跌情况 - 紧凑列表布局

import 'package:flutter/material.dart';
import '../models/investment_calendar.dart';
import '../services/local_data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/common.dart';
import 'stock_analysis_screen.dart';

class SectorStocksScreen extends StatefulWidget {
  final SectorInfo sector;
  final String monthName;

  const SectorStocksScreen({
    Key? key,
    required this.sector,
    required this.monthName,
  }) : super(key: key);

  @override
  State<SectorStocksScreen> createState() => _SectorStocksScreenState();
}

class _SectorStocksScreenState extends State<SectorStocksScreen> {
  final LocalDataService _api = LocalDataService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stocks = [];
  double _avgChange = 0.0;
  int _upCount = 0;
  int _downCount = 0;
  Map<String, double> _monthChanges = {}; // 月涨幅数据

  @override
  void initState() {
    super.initState();
    _loadSectorStocks();
  }

  Future<void> _loadSectorStocks() async {
    setState(() { _loading = true; _error = null; });

    try {
      // 通过API获取板块对应的股票列表，增加到50只
      final result = await _api.getSectorStocks(
        sectorName: widget.sector.name,
        keywords: widget.sector.keywords,
        stockCodes: widget.sector.stockCodes,
        limit: 50,
      );

      if (mounted) {
        final stocks = result['stocks'] as List<dynamic>? ?? [];
        final errorMsg = result['error'] as String?;
        final parsedStocks = stocks.cast<Map<String, dynamic>>().toList();

        // 计算统计数据
        double totalChange = 0;
        int up = 0;
        int down = 0;

        for (var stock in parsedStocks) {
          final change = _parseChange(stock['change_pct']);
          totalChange += change;
          if (change > 0) up++;
          else if (change < 0) down++;
        }

        // 获取月涨幅数据
        final monthChanges = await _fetchMonthChanges(parsedStocks);

        setState(() {
          _stocks = parsedStocks;
          _avgChange = parsedStocks.isNotEmpty ? totalChange / parsedStocks.length : 0;
          _upCount = up;
          _downCount = down;
          _monthChanges = monthChanges;
          _loading = false;
          // 如果没有数据但有错误信息，显示错误
          if (parsedStocks.isEmpty && errorMsg != null) {
            _error = '数据获取失败: $errorMsg';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '网络错误: $e';
          _loading = false;
        });
      }
    }
  }

  /// 获取股票月涨幅数据
  /// 直接从stock数据的month_change_pct字段提取（_fetchStocksByCodes已从腾讯API获取）
  /// 不再单独请求API，避免重复网络请求和GBK解码问题
  Future<Map<String, double>> _fetchMonthChanges(List<Map<String, dynamic>> stocks) async {
    final result = <String, double>{};
    for (final stock in stocks) {
      final symbol = stock['symbol']?.toString() ?? '';
      final monthChange = _parseChange(stock['month_change_pct']);
      if (monthChange != 0 && symbol.isNotEmpty) {
        result[symbol] = double.parse(monthChange.toStringAsFixed(2));
      }
    }
    return result;
  }

  double _parseChange(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.backgroundGradient,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            children: [
              Text(
                '${widget.monthName} · ${widget.sector.displayName}',
                style: AppText.h3.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
              ),
              Text(
                widget.sector.keywords.split(',').take(3).join(' · '),
                style: AppText.caption.copyWith(color: colors.textHint),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: colors.primary),
              onPressed: _loadSectorStocks,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingView(message: '加载板块股票...');
    }

    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _loadSectorStocks,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSectorStocks,
      color: AppColors.primary,
      child: CustomScrollView(
        slivers: [
          // 统计卡片
          SliverToBoxAdapter(
            child: _buildStatsCard(),
          ),
          
          // 股票列表标题和表头
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 板块成分股标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                  child: Row(
                    children: [
                      Text(
                        '板块成分股',
                        style: AppText.h3.copyWith(color: AppColors.of(context).textPrimary, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '${_stocks.length}只',
                          style: AppText.caption.copyWith(color: AppColors.of(context).primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 表头
                _buildTableHeader(),
              ],
            ),
          ),
          
          // 股票列表
          _stocks.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: EmptyView(
                      message: '暂无股票数据',
                      icon: Icons.show_chart,
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildStockRow(_stocks[index], index + 1),
                    childCount: _stocks.length,
                  ),
                ),
          
          // 底部间距
          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.xl),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final colors = AppColors.of(context);
    final isUp = _avgChange >= 0;
    final changeColor = isUp ? AppColors.up : AppColors.down;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            changeColor.withOpacity(0.15),
            changeColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: changeColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('平均涨跌', '${isUp ? "+" : ""}${_avgChange.toStringAsFixed(2)}%', changeColor),
              _buildStatItem('上涨家数', '$_upCount', AppColors.up),
              _buildStatItem('下跌家数', '$_downCount', AppColors.down),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 涨跌分布条
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Row(
              children: [
                if (_stocks.isNotEmpty)
                  Expanded(
                    flex: _upCount,
                    child: Container(
                      height: 8,
                      color: AppColors.up.withOpacity(0.7),
                    ),
                  ),
                if (_stocks.isNotEmpty)
                  Expanded(
                    flex: _stocks.length - _upCount - _downCount,
                    child: Container(
                      height: 8,
                      color: colors.textHint.withOpacity(0.3),
                    ),
                  ),
                if (_stocks.isNotEmpty)
                  Expanded(
                    flex: _downCount,
                    child: Container(
                      height: 8,
                      color: AppColors.down.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: AppText.h2.copyWith(color: color, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppText.caption.copyWith(color: AppColors.of(context).textSecondary),
        ),
      ],
    );
  }

  /// 表头
  Widget _buildTableHeader() {
    final colors = AppColors.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          // 序号
          SizedBox(
            width: 32,
            child: Text(
              '#',
              style: AppText.caption.copyWith(
                color: colors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 名称
          Expanded(
            flex: 3,
            child: Text(
              '名称',
              style: AppText.caption.copyWith(
                color: colors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 代码
          Expanded(
            flex: 2,
            child: Text(
              '代码',
              style: AppText.caption.copyWith(
                color: colors.textHint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 最新价
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '最新价',
                style: AppText.caption.copyWith(
                  color: colors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 涨跌
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '涨跌',
                style: AppText.caption.copyWith(
                  color: colors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 月涨跌
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '月涨跌',
                style: AppText.caption.copyWith(
                  color: colors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 紧凑的股票行
  Widget _buildStockRow(Map<String, dynamic> stock, int rank) {
    final colors = AppColors.of(context);
    final name = stock['name']?.toString() ?? '--';
    final symbol = stock['symbol']?.toString() ?? '--';
    final price = _parseChange(stock['price']);
    final change = _parseChange(stock['change_pct']);
    final isUp = change >= 0;
    final changeColor = isUp ? AppColors.up : AppColors.down;

    // 月涨幅 - 使用带后缀的symbol查询
    final monthChange = _monthChanges[symbol] ?? 0.0;
    final isMonthUp = monthChange >= 0;
    final monthChangeColor = isMonthUp ? AppColors.up : AppColors.down;

    return Material(
      color: rank % 2 == 0 ? colors.surface : colors.surface.withOpacity(0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          // 直接导航到个股分析页面，让页面自己加载数据
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => StockAnalysisScreen(symbol: symbol),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.border.withOpacity(0.5)),
            ),
          ),
          child: Row(
            children: [
              // 序号
              SizedBox(
                width: 32,
                child: Text(
                  '$rank',
                  style: AppText.body2.copyWith(
                    color: rank <= 3 ? colors.primary : colors.textSecondary,
                    fontWeight: rank <= 3 ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
              
              // 名称
              Expanded(
                flex: 3,
                child: Text(
                  name,
                  style: AppText.body2.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              // 代码
              Expanded(
                flex: 2,
                child: Text(
                  symbol.replaceAll('.SS', '').replaceAll('.SZ', '').replaceAll('.BJ', ''),
                  style: AppText.body2.copyWith(
                    color: colors.textHint,
                    fontSize: 13,
                  ),
                ),
              ),
              
              // 最新价
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    price > 0 ? price.toStringAsFixed(3) : '--',
                    style: AppText.body2.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              
              // 涨跌
              SizedBox(
                width: 72,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${isUp ? "+" : ""}${change.toStringAsFixed(2)}%',
                    style: AppText.body2.copyWith(
                      color: changeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              // 月涨跌
              SizedBox(
                width: 72,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    monthChange != 0 ? '${isMonthUp ? "+" : ""}${monthChange.toStringAsFixed(2)}%' : '--',
                    style: AppText.body2.copyWith(
                      color: monthChangeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
