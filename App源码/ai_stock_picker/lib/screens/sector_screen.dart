/// 板块详情页 - 年轻化设计
///
/// 深蓝紫渐变 + 玻璃态效果

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/local_data_service.dart';
import 'stock_analysis_screen.dart';

class SectorScreen extends StatefulWidget {
  final String sectorName;
  final String sectorCode;
  final String market;
  final LocalDataService api;

  const SectorScreen({Key? key, required this.sectorName, required this.sectorCode, required this.market, required this.api}) : super(key: key);
  @override
  State<SectorScreen> createState() => _SectorScreenState();
}

class _SectorScreenState extends State<SectorScreen> {
  List<Map<String, dynamic>> _stocks = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() { super.initState(); _loadStocks(); }

  void _loadStocks() async {
    setState(() { _loading = true; _err = null; });
    try {
      final data = await widget.api.fetchSectorStocks(widget.sectorCode, widget.market);
      if (mounted) setState(() { _stocks = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _err = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(icon: Icon(Icons.arrow_back_ios_new, size: 20, color: colors.textPrimary), onPressed: () => Navigator.pop(context)),
          title: Text(widget.sectorName, style: AppText.h2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800)),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors.backgroundGradient)),
          ),
          actions: [IconButton(icon: Icon(Icons.refresh, color: colors.textPrimary), onPressed: _loadStocks)],
        ),
        body: _loading ? _buildLoading(colors) : (_err != null ? _buildError(colors) : _buildList(colors)),
      ),
    );
  }

  Widget _buildLoading(AppColorScheme colors) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(colors.primary)),
      const SizedBox(height: AppSpacing.lg),
      Text('加载板块数据...', style: AppText.body2.copyWith(color: colors.textSecondary)),
    ]));
  }

  Widget _buildError(AppColorScheme colors) {
    return Center(child: Container(
      margin: const EdgeInsets.all(AppSpacing.xxl),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface, borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.error.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: colors.error),
        const SizedBox(height: AppSpacing.md),
        Text('加载失败', style: AppText.h3.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text(_err ?? '', style: AppText.body2.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton.icon(onPressed: _loadStocks, icon: const Icon(Icons.refresh, size: 18), label: const Text('重试')),
      ]),
    ));
  }

  Widget _buildList(AppColorScheme colors) {
    if (_stocks.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(color: colors.surfaceVariant, shape: BoxShape.circle),
          child: Icon(Icons.inbox_outlined, size: 40, color: colors.textHint),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('暂无数据', style: AppText.body2.copyWith(color: colors.textSecondary)),
      ]));
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        color: colors.surface.withOpacity(0.8),
        child: Row(children: [
          SizedBox(width: 32, child: Text('#', style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
          Expanded(flex: 3, child: Text('名称', style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
          SizedBox(width: 80, child: Text('代码', style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
          SizedBox(width: 75, child: Text('最新价', textAlign: TextAlign.right, style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
          SizedBox(width: 70, child: Text('涨跌', textAlign: TextAlign.right, style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
        ]),
      ),
      Expanded(child: RefreshIndicator(
        onRefresh: () async => _loadStocks(),
        child: ListView.builder(itemCount: _stocks.length, itemBuilder: (ctx, i) => _buildRow(_stocks[i], i + 1, colors)),
      )),
    ]);
  }

  Widget _buildRow(Map<String, dynamic> s, int rank, AppColorScheme colors) {
    final name = s['name']?.toString() ?? '';
    final symbol = s['symbol']?.toString() ?? s['code']?.toString() ?? '';
    final price = s['price'] as double? ?? 0.0;
    final chg = s['change_pct'] as double? ?? 0.0;
    final isUp = chg >= 0;
    final chgColor = isUp ? colors.up : colors.down;
    final displayCode = symbol.split('.').first;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onStockTap(s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: rank % 2 == 0 ? Colors.transparent : colors.surface.withOpacity(0.3),
            border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
          ),
          child: Row(children: [
            SizedBox(width: 32, child: Text('$rank', style: AppText.caption.copyWith(color: colors.textHint, fontWeight: FontWeight.w600))),
            Expanded(flex: 3, child: Text(name, style: AppText.body2.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 80, child: Text(displayCode, style: AppText.caption.copyWith(color: colors.textHint))),
            SizedBox(width: 75, child: Text(price.toStringAsFixed(price > 100 ? 2 : 3), textAlign: TextAlign.right,
              style: AppText.body2.copyWith(color: chgColor, fontWeight: FontWeight.w700))),
            SizedBox(width: 70, child: Text('${isUp ? "+" : ""}${chg.toStringAsFixed(2)}%', textAlign: TextAlign.right,
              style: AppText.body2.copyWith(color: chgColor, fontWeight: FontWeight.w800))),
          ]),
        ),
      ),
    );
  }

  void _onStockTap(Map<String, dynamic> stock) {
    // 优先使用symbol字段(如600519.SS)，其次用code字段
    String code = stock['symbol']?.toString() ?? stock['code']?.toString() ?? '';
    if (code.isEmpty) return;
    
    // 如果是纯6位数字代码，根据首位数字添加市场后缀
    if (!code.contains('.')) {
      if (code.startsWith('6')) code = '$code.SS';
      else if (code.startsWith('0') || code.startsWith('3')) code = '$code.SZ';
      else if (code.startsWith('8') || code.startsWith('4')) code = '$code.BJ';
    }
    
    // 转换代码格式：新浪API用.SH/.SZ，本项目用.SS/.SZ
    final parts = code.split('.');
    final numCode = parts[0];
    final suffix = parts.length > 1 ? parts[1] : '';
    String query;
    if (suffix == 'HK') { query = '${numCode.padLeft(5, '0')}.HK'; }
    else if (suffix == 'SH' || suffix == 'SS') { query = '$numCode.SS'; }
    else if (suffix == 'SZ') { query = '$numCode.SZ'; }
    else if (suffix == 'BJ') { query = '$numCode.BJ'; }
    else if (suffix == 'US') { query = numCode; }
    else { query = numCode; }

    // 直接导航到个股分析页面
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => StockAnalysisScreen(symbol: query),
    ));
  }
}
