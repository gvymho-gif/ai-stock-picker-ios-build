/// 筛选结果页面
/// 展示筛选统计卡片和股票列表

import 'package:flutter/material.dart';
import '../models/filter_criteria.dart';
import '../services/stock_filter_service.dart';
import '../services/local_data_service.dart';
import '../theme/app_colors.dart';

class FilterScreen extends StatefulWidget {
  final FilterCriteria criteria;

  const FilterScreen({Key? key, required this.criteria}) : super(key: key);

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final StockFilterService _filterService = StockFilterService();
  final LocalDataService _api = LocalDataService();

  List<Map<String, dynamic>> _stocks = [];
  bool _loading = true;
  String? _error;

  // 统计数据
  double _avgPe = 0;
  double _avgPb = 0;
  double _avgRoe = 0;
  int _upCount = 0;
  int _downCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _filterService.filterStocks(widget.criteria);

      // 计算统计数据
      _calculateStats(result);

      if (mounted) {
        setState(() {
          _stocks = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _calculateStats(List<Map<String, dynamic>> stocks) {
    if (stocks.isEmpty) return;

    double totalPe = 0;
    double totalPb = 0;
    double totalRoe = 0;
    int peCount = 0;
    int pbCount = 0;
    int roeCount = 0;
    int up = 0;
    int down = 0;

    for (final stock in stocks) {
      final pe = _safeDouble(stock['pe']);
      final pb = _safeDouble(stock['pb']);
      final roe = _safeDouble(stock['roe']);
      final chg = _safeDouble(stock['change_pct']);

      if (pe > 0) { totalPe += pe; peCount++; }
      if (pb > 0) { totalPb += pb; pbCount++; }
      if (roe > 0) { totalRoe += roe; roeCount++; }
      if (chg >= 0) up++; else down++;
    }

    _avgPe = peCount > 0 ? totalPe / peCount : 0;
    _avgPb = pbCount > 0 ? totalPb / pbCount : 0;
    _avgRoe = roeCount > 0 ? totalRoe / roeCount : 0;
    _upCount = up;
    _downCount = down;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('筛选结果', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: colors.textPrimary)),
        centerTitle: true,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors.backgroundGradient),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textHint),
            onPressed: _loadData,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading ? _loadingView(colors) : (_error != null ? _errorView(colors) : _contentView(colors)),
    );
  }

  Widget _loadingView(AppColorScheme colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text('正在扫描全市场...', style: TextStyle(fontSize: 14, color: colors.textHint)),
        ],
      ),
    );
  }

  Widget _errorView(AppColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: 12),
            Text('筛选失败', style: TextStyle(fontSize: 18, color: colors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: colors.textHint)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _contentView(AppColorScheme colors) {
    return Column(
      children: [
        // 筛选条件描述
        _buildCriteriaBar(colors),
        // 统计卡片
        _buildStatsCards(colors),
        // 股票列表
        Expanded(child: _buildStockList(colors)),
      ],
    );
  }

  Widget _buildCriteriaBar(AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.surface,
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '筛选条件: ${widget.criteria.description}',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(AppColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatCard(colors, '筛选结果', '${_stocks.length}只', colors.primary),
          const SizedBox(width: 12),
          _buildStatCard(colors, '平均PE', _avgPe > 0 ? _avgPe.toStringAsFixed(1) : '--', colors.success),
          const SizedBox(width: 12),
          _buildStatCard(colors, '平均ROE', _avgRoe > 0 ? '${_avgRoe.toStringAsFixed(1)}%' : '--', colors.error),
          const SizedBox(width: 12),
          _buildStatCard(colors, '涨跌', '$_upCount/$_downCount', _upCount >= _downCount ? colors.up : colors.down),
        ],
      ),
    );
  }

  Widget _buildStatCard(AppColorScheme colors, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: colors.textHint)),
          ],
        ),
      ),
    );
  }

  Widget _buildStockList(AppColorScheme colors) {
    if (_stocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: colors.textHint),
            const SizedBox(height: 12),
            Text('未找到符合条件的股票', style: TextStyle(fontSize: 16, color: colors.textSecondary)),
            const SizedBox(height: 8),
            Text('请尝试放宽筛选条件', style: TextStyle(fontSize: 13, color: colors.textHint)),
          ],
        ),
      );
    }

    // 检查是否启用了外资持股筛选
    final hasForeignFilter = widget.criteria.foreignHolderFilter != null &&
        widget.criteria.foreignHolderFilter!.hasFilter;

    return Column(
      children: [
        // 表头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colors.surface,
          child: Row(
            children: [
              SizedBox(width: 30, child: Text('#', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600))),
              Expanded(flex: 3, child: Text('名称', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600))),
              SizedBox(width: 70, child: Text('PE', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
              if (hasForeignFilter)
                SizedBox(width: 70, child: Text('外资', style: TextStyle(fontSize: 12, color: colors.primary, fontWeight: FontWeight.w600), textAlign: TextAlign.right))
              else
                SizedBox(width: 65, child: Text('ROE', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
              SizedBox(width: 65, child: Text('涨跌幅', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
            ],
          ),
        ),
        // 股票列表
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              itemCount: _stocks.length,
              itemBuilder: (ctx, i) => _buildStockRow(colors, _stocks[i], i + 1, hasForeignFilter),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockRow(AppColorScheme colors, Map<String, dynamic> stock, int rank, bool hasForeignFilter) {
    final name = stock['name']?.toString() ?? '';
    final code = stock['code']?.toString() ?? '';
    final pe = _safeDouble(stock['pe']);
    final roe = _safeDouble(stock['roe']);
    final chg = _safeDouble(stock['change_pct']);
    final foreignRatio = _safeDouble(stock['foreign_ratio']);
    final foreignChange = _safeDouble(stock['foreign_change']);
    final isUp = chg >= 0;
    final color = isUp ? colors.up : colors.down;

    // 外资持股颜色：增持=红，减持=绿
    final foreignColor = foreignChange > 0
        ? colors.up
        : foreignChange < 0
            ? colors.down
            : colors.textSecondary;

    return InkWell(
      onTap: () => _onStockTap(stock),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: rank % 2 == 0 ? Colors.transparent : colors.textPrimary.withOpacity(0.02),
          border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
        ),
        child: Row(
          children: [
            SizedBox(width: 30, child: Text('$rank', style: TextStyle(fontSize: 12, color: colors.textHint, fontWeight: FontWeight.w600))),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontSize: 14, color: colors.textPrimary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(code, style: TextStyle(fontSize: 11, color: colors.textHint, fontFamily: 'monospace')),
                ],
              ),
            ),
            SizedBox(width: 70, child: Text(pe > 0 ? pe.toStringAsFixed(1) : '--', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: colors.textPrimary, fontFamily: 'monospace'))),
            if (hasForeignFilter)
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(foreignRatio > 0 ? '${foreignRatio.toStringAsFixed(2)}%' : '--',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, color: colors.primary, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                    if (foreignRatio > 0)
                      Text('${foreignChange > 0 ? "+" : ""}${foreignChange.toStringAsFixed(2)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 10, color: foreignColor, fontFamily: 'monospace')),
                  ],
                ),
              )
            else
              SizedBox(width: 65, child: Text(roe > 0 ? '${roe.toStringAsFixed(1)}%' : '--', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: colors.textPrimary, fontFamily: 'monospace'))),
            SizedBox(width: 65, child: Text('${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700, fontFamily: 'monospace'))),
          ],
        ),
      ),
    );
  }

  void _onStockTap(Map<String, dynamic> stock) async {
    final symbol = stock['symbol']?.toString() ?? '';
    if (symbol.isEmpty) return;

    // 返回股票代码给首页搜索
    Navigator.pop(context, symbol);
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    final s = v.toString();
    if (s == '-' || s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }
}
