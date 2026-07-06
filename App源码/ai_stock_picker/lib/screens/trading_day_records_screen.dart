/// 交易日记录页面
/// 表格形式展示历史记录和统计数据
/// 自动从专家收益统计导入数据

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trading_day_record.dart';
import '../services/trading_day_cloud_service.dart';
import '../services/expert_performance_service.dart';
import '../utils/trading_day_utils.dart';
import '../services/ai_qa_service.dart';
import '../services/ai_model_service.dart';
import '../services/local_data_service.dart';
import '../services/news_service.dart';
import '../models/ai_model_config.dart';
import 'dart:async';

class TradingDayRecordsScreen extends StatefulWidget {
  const TradingDayRecordsScreen({Key? key}) : super(key: key);

  @override
  State<TradingDayRecordsScreen> createState() => _TradingDayRecordsScreenState();
}

class _TradingDayRecordsScreenState extends State<TradingDayRecordsScreen> {
  List<TradingDayRecord> _records = [];
  TradingStatistics _statistics = TradingStatistics.fromRecords([]);
  bool _isLoading = true;
  bool _isSyncing = false;
  String _syncMessage = '';
  int _importedCount = 0;

  // 极智复盘相关（AI模型配置）
  AIModelConfig? _activeModel;

  // ★ 实时刷新相关
  Timer? _refreshTimer;
  bool _refreshing = false;

  // ★ 日历视图
  DateTime _currentCalendarMonth = DateTime.now();

  // A股节假日列表（2026年）
  static const Set<String> _kHolidayDates = {
    '2026-01-01',
    '2026-02-16', '2026-02-17', '2026-02-18', '2026-02-19',
    '2026-02-20', '2026-02-21', '2026-02-22',
    '2026-04-04', '2026-04-05', '2026-04-06',
    '2026-05-01', '2026-05-02', '2026-05-03', '2026-05-04', '2026-05-05',
    '2026-06-19', '2026-06-20', '2026-06-21',
    '2026-09-25', '2026-09-26', '2026-09-27',
    '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04',
    '2026-10-05', '2026-10-06', '2026-10-07',
  };

  /// 判断某日期是否为证券交易日（排除周末+节假日）
  bool _isSecuritiesTradingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (_kHolidayDates.contains(dateStr)) {
      return false;
    }
    return true;
  }

  /// 判断日期字符串是否为非交易日
  bool _isNonTradingDayStr(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return false;
    return !_isSecuritiesTradingDay(
      DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _loadActiveModel();
    _startLiveRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 启动实时刷新（结算窗口期每3秒刷新）
  void _startLiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isSettlementWindow()) _refreshLivePrices();
    });
  }

  /// 判断是否在结算窗口期（9:30-19:30）
  /// 此期间涨跌幅数据实时更新，15:05后才结算冻结
  /// ★ 非交易日（周末+节假日）不在结算窗口内
  bool _isSettlementWindow() {
    final now = DateTime.now();
    // 非交易日不刷新
    if (!_isSecuritiesTradingDay(now)) return false;
    final timeInMinutes = now.hour * 60 + now.minute;
    final windowStart = 9 * 60 + 30;   // ★ 9:30（集合竞价阶段9:15-9:30价格不稳定，不刷新）
    final windowEnd = 15 * 60 + 5;    // 15:05
    return timeInMinutes >= windowStart && timeInMinutes < windowEnd;
  }

  /// 获取今日日期字符串
  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 实时刷新当前有效期内记录的涨跌幅（结算窗口期内）
  /// 当前有效期内记录：20:00前显示昨天的记录，20:00后显示今天的记录
  Future<void> _refreshLivePrices() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;

    try {
      final now = DateTime.now();
      final today = _getTodayString();
      
      // 确定当前应该刷新哪天的记录
      // 20:00前 → 刷新昨天的记录（昨晚20:00创建的，有效期到今天19:00）
      // 20:00后 → 刷新今天的记录（今晚20:00刚创建的）
      // 如果昨天没有记录（如周一→周日），回退到最近的交易日记录
      String targetDate;
      if (now.hour >= 20) {
        targetDate = today;
      } else {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        targetDate = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      }
      
      // 找到目标日期的记录
      int targetIndex = _records.indexWhere((r) => r.date == targetDate);
      
      // ★ 如果目标日期没有记录（如周一→周日无记录），找最近的交易日记录
      if (targetIndex < 0 && _records.isNotEmpty) {
        // 从最新记录开始往前找，找到最近一条有效记录
        for (int i = 0; i < _records.length; i++) {
          if (_records[i].stockCodes.isNotEmpty) {
            targetIndex = i;
            break;
          }
        }
      }
      
      if (targetIndex < 0) return; // 没有找到任何记录

      final targetRecord = _records[targetIndex];
      if (targetRecord.stockCodes.isEmpty) return;

      final api = LocalDataService();
      double totalChange = 0;
      int successCount = 0;
      final newChanges = List<double>.from(targetRecord.stockChanges);

      for (int i = 0; i < targetRecord.stockCodes.length; i++) {
        try {
          final code = targetRecord.stockCodes[i];
          final stockData = await api.searchStock(code);
          if (stockData.isNotEmpty) {
            final changePct = _safeDouble(stockData['change_pct']);
            if (changePct != 0) {
              newChanges[i] = changePct;
              totalChange += changePct;
              successCount++;
            }
          }
        } catch (_) {}
      }

      if (successCount > 0) {
        final avgChange = totalChange / targetRecord.stockCodes.length;
        final newRecord = TradingDayRecord(
          date: targetRecord.date,
          stockCodes: targetRecord.stockCodes,
          stockNames: targetRecord.stockNames,
          stockChanges: newChanges,
          totalChangePercent: totalChange,
          avgChangePercent: avgChange,
          notes: targetRecord.notes,
          reviewContent: targetRecord.reviewContent,
          reviewGeneratedAt: targetRecord.reviewGeneratedAt,
        );
        _records[targetIndex] = newRecord;
        _statistics = TradingStatistics.fromRecords(_records);
        if (mounted) setState(() {});
        // ★ 保存到 SharedPreferences
        await TradingDayCloudService.addRecord(newRecord);
      }
    } catch (e) {
      print('[交易日记录] 实时刷新失败: $e');
    } finally {
      _refreshing = false;
    }
  }

  double _safeDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  void _loadActiveModel() async {
    final model = await AIModelService.getActiveModel();
    if (mounted) setState(() => _activeModel = model);
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      // 1. 首先检查交易日记录是否有数据
      var records = await TradingDayCloudService.getLocalRecords();

      // 2. 如果没有数据，从专家收益统计导入
      if (records.isEmpty) {
        print('[交易日记录] 本地无数据，尝试从专家收益导入...');
        final imported = await _importFromExpertPerformance();
        if (imported > 0) {
          records = await TradingDayCloudService.getLocalRecords();
          _importedCount = imported;
          print('[交易日记录] 成功导入 $imported 条记录');
        }
      }

      // 3. 过滤掉非交易日记录（周末+节假日），仅在展示层过滤
      //    同时清理本地存储中的无效记录
      final invalidDates = <String>[];
      for (final r in records) {
        if (_isNonTradingDayStr(r.date)) {
          invalidDates.add(r.date);
        }
      }
      if (invalidDates.isNotEmpty) {
        print('[交易日记录] 过滤非交易日记录: $invalidDates');
        records = records.where((r) => !_isNonTradingDayStr(r.date)).toList();
        // 从本地存储中删除无效记录
        for (final date in invalidDates) {
          final dummy = TradingDayRecord(
            date: date,
            stockCodes: [], stockNames: [], stockChanges: [],
            totalChangePercent: 0, avgChangePercent: 0,
            notes: '', reviewContent: null, reviewGeneratedAt: null,
          );
          await TradingDayCloudService.deleteRecord(date);
        }
      }

      setState(() {
        _records = records;
        _statistics = TradingStatistics.fromRecords(records);
        _isLoading = false;
      });

      // 显示导入提示
      if (_importedCount > 0) {
        _showSnackBar('已从收益统计导入 $_importedCount 条记录');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('加载失败: $e');
    }
  }

  /// 从专家收益统计导入数据
  /// 新增：对已存在的记录，如果结算数据有变化则更新
  /// 修复：现在也导入未结算的记录（显示为"待结算"状态）
  Future<int> _importFromExpertPerformance() async {
    try {
      final history = await ExpertPerformanceService.getHistory();
      if (history.isEmpty) return 0;

      final existingRecords = await TradingDayCloudService.getLocalRecords();
      final existingMap = {for (var r in existingRecords) r.date: r};

      int importedCount = 0;
      int updatedCount = 0;
      int skippedNonTrading = 0;
      for (var perf in history) {
        // ★ 跳过非交易日（周末+节假日），不导入
        if (_isNonTradingDayStr(perf.date)) {
          skippedNonTrading++;
          continue;
        }

        final codes = perf.stocks.map((s) => s.code).toList();
        final names = perf.stocks.map((s) => s.name).toList();

        // 根据是否已结算决定数据值
        double totalChange;
        double avgChange;
        List<double> changes;
        String notes;

        if (perf.isSettled) {
          // 已结算：使用实际数据
          changes = perf.stocks.map((s) => s.changePercent).toList();
          totalChange = perf.dailyAvgChange * perf.stocks.length;
          avgChange = perf.dailyAvgChange;
          notes = '从收益统计导入';
        } else {
          // 未结算：涨跌幅显示为0，标记为待结算
          changes = List.filled(perf.stocks.length, 0.0);
          totalChange = 0.0;
          avgChange = 0.0;
          notes = '待结算';
        }

        final existing = existingMap[perf.date];
        if (existing != null) {
          // ★ 修复：只有专家收益从"待结算"→"已结算"时才更新本地记录
          // 如果用户已手动编辑过（notes不是"从收益统计导入"也不是"待结算"），不覆盖用户修改
          final wasPending = existing.notes == '待结算' || existing.stockChanges.every((c) => c == 0.0);
          final nowSettled = perf.isSettled && changes.any((c) => c != 0.0);
          
          // 仅当从待结算变为已结算时更新（不覆盖用户手动修改的数据）
          if (wasPending && nowSettled) {
            final updatedRecord = TradingDayRecord(
              date: perf.date,
              stockCodes: codes,
              stockNames: names,
              stockChanges: changes,
              totalChangePercent: totalChange,
              avgChangePercent: avgChange,
              notes: '自动结算同步',
              reviewContent: existing.reviewContent, // 保留已有的复盘内容
              reviewGeneratedAt: existing.reviewGeneratedAt,
            );
            await TradingDayCloudService.addRecord(updatedRecord);
            updatedCount++;
            print('[交易日记录] 待结算→已结算，更新记录: ${perf.date}');
          }
          continue;
        }

        // 新记录：添加
        final record = TradingDayRecord(
          date: perf.date,
          stockCodes: codes,
          stockNames: names,
          stockChanges: changes,
          totalChangePercent: totalChange,
          avgChangePercent: avgChange,
          notes: notes,
          reviewContent: null,
          reviewGeneratedAt: null,
        );

        await TradingDayCloudService.addRecord(record);
        importedCount++;
        print('[交易日记录] 导入记录: ${perf.date}, 状态: $notes');
      }

      if (skippedNonTrading > 0) {
        print('[交易日记录] 跳过 $skippedNonTrading 条非交易日记录');
      }
      return importedCount + updatedCount;
    } catch (e) {
      print('[交易日记录] 导入失败: $e');
      return 0;
    }
  }

  Future<void> _syncWithCloud() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = '正在同步...';
    });

    try {
      final result = await TradingDayCloudService.syncWithCloud();

      setState(() {
        _isSyncing = false;
        if (result['ok'] == true) {
          _syncMessage = '同步成功！本地${result['localCount']}条，云端${result['cloudCount']}条，合并${result['mergedCount']}条';
        } else {
          // 更友好的错误提示
          final error = result['error']?.toString() ?? '';
          if (error.contains('未配置Gitee Token')) {
            _syncMessage = '未配置Gitee Token，请在设置中配置';
          } else if (error.contains('下载云端数据失败')) {
            _syncMessage = '云端暂无数据，本地数据已保留';
          } else {
            _syncMessage = '同步失败: $error';
          }
        }
      });

      // 重新加载记录
      await _loadRecords();

      // 3秒后清除消息
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _syncMessage = '');
      });
    } catch (e) {
      setState(() {
        _isSyncing = false;
        _syncMessage = '同步异常: $e';
      });
    }
  }

  /// 手动从专家收益统计导入
  Future<void> _manualImportFromExpert() async {
    setState(() => _isLoading = true);
    try {
      final count = await _importFromExpertPerformance();
      await _loadRecords();
      if (count > 0) {
        _showSnackBar('成功导入 $count 条记录');
      } else {
        _showSnackBar('没有新数据可导入');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('导入失败: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 安全转字符串辅助方法
  static String _s(dynamic v) {
    if (v == null) return '--';
    if (v is double) return v.toStringAsFixed(2);
    if (v is int) return v.toString();
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易日记录'),
        actions: [
          // 从收益统计导入按钮
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: _isLoading ? null : _manualImportFromExpert,
            tooltip: '从收益统计导入',
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_sync),
            onPressed: _isSyncing ? null : _syncWithCloud,
            tooltip: '同步云端',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecords,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 同步状态消息
                if (_syncMessage.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: _syncMessage.contains('成功') ? Colors.green[100] : Colors.orange[100],
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _syncMessage,
                      style: TextStyle(
                        color: _syncMessage.contains('成功') ? Colors.green[800] : Colors.orange[800],
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // 统计卡片
                _buildStatisticsCard(),

                // 日历视图
                Expanded(child: _buildCalendarView()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddRecordDialog(),
        child: const Icon(Icons.add),
        tooltip: '添加记录',
      ),
    );
  }

  /// 统计卡片
  Widget _buildStatisticsCard() {
    final theme = Theme.of(context);
    final labelColor = theme.textTheme.bodySmall?.color ?? Colors.grey[600];

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '收益统计',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.titleMedium?.color,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatItem('总交易日', '${_statistics.totalDays}天',
                    valueColor: Colors.amber[700], labelColor: labelColor),
                _buildStatItem('累计收益', _statistics.formattedCumulativeReturn,
                    labelColor: labelColor),
                _buildStatItem('日均收益', _statistics.formattedDailyAvgReturn,
                    labelColor: labelColor),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatItem('盈利率', _statistics.formattedWinRate,
                    valueColor: Colors.blue, labelColor: labelColor),
                _buildStatItem('盈利天数', '${_statistics.positiveDays}天',
                    valueColor: Colors.red, labelColor: labelColor),
                _buildStatItem('亏损天数', '${_statistics.negativeDays}天',
                    valueColor: Colors.green, labelColor: labelColor),
              ],
            ),
            if (_statistics.maxSingleDayGain > 0) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '最大单日涨幅: +${_statistics.maxSingleDayGain.toStringAsFixed(2)}% (${_statistics.maxGainDate})',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '最大单日跌幅: ${_statistics.maxSingleDayLoss.toStringAsFixed(2)}% (${_statistics.maxLossDate})',
                      style: const TextStyle(fontSize: 12, color: Colors.green),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? valueColor, Color? labelColor}) {
    final theme = Theme.of(context);
    final defaultTextColor = theme.textTheme.bodyMedium?.color ?? Colors.black87;

    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: labelColor ?? Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor ??
                  (value.startsWith('+')
                      ? Colors.red
                      : value.startsWith('-')
                          ? Colors.green
                          : defaultTextColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 日历视图 ====================

  /// 计算月末
  DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  /// 构建日历视图
  Widget _buildCalendarView() {
    final monthStart = DateTime(_currentCalendarMonth.year, _currentCalendarMonth.month, 1);
    final monthEnd = _endOfMonth(_currentCalendarMonth);
    final totalDays = monthEnd.day;

    // 当月1号是周几（周一=1, 周日=7）
    final firstWeekday = monthStart.weekday; // 1=Mon

    // 构建日期→记录映射
    final recordMap = <String, TradingDayRecord>{};
    for (final r in _records) {
      recordMap[r.date] = r;
    }

    return Column(
      children: [
        // 月份切换栏
        _buildMonthPicker(),
        const SizedBox(height: 8),
        // 星期头
        _buildWeekdayHeader(),
        const SizedBox(height: 4),
        // 日期网格
        Expanded(
          child: _buildCalendarGrid(firstWeekday, totalDays, monthStart, recordMap),
        ),
      ],
    );
  }

  /// 月份切换栏（含当月收益率统计）
  Widget _buildMonthPicker() {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color ?? Colors.white;
    final isDark = theme.brightness == Brightness.dark;
    final labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
    final label = '${_currentCalendarMonth.year}年${labels[_currentCalendarMonth.month - 1]}月';

    // 计算当月收益率
    final monthStr = '${_currentCalendarMonth.year}-${_currentCalendarMonth.month.toString().padLeft(2, '0')}';

    double monthTotal = 0.0;
    int monthTradingDays = 0;
    for (final r in _records) {
      if (!r.date.startsWith(monthStr)) continue;
      // ★ 尚未到下一个交易日确认时间的记录按0计算
      final change = TradingDayUtils.shouldRecordShowZero(r.date) ? 0.0 : r.avgChangePercent;
      monthTotal += change;
      monthTradingDays++;
    }
    final monthAvg = monthTradingDays > 0 ? monthTotal / monthTradingDays : 0.0;

    return Row(
      children: [
        // 月份切换（左侧留空让右侧统计居中）
        const Spacer(),
        IconButton(
          icon: Icon(Icons.chevron_left, color: textColor.withOpacity(0.7), size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36),
          onPressed: () {
            setState(() {
              _currentCalendarMonth = DateTime(_currentCalendarMonth.year, _currentCalendarMonth.month - 1, 1);
            });
          },
        ),
        GestureDetector(
          onTap: () => _showMonthYearPicker(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.5),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, color: textColor.withOpacity(0.7), size: 22),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36),
          onPressed: () {
            setState(() {
              _currentCalendarMonth = DateTime(_currentCalendarMonth.year, _currentCalendarMonth.month + 1, 1);
            });
          },
        ),
        const Spacer(),
        // 当月统计
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: monthTotal >= 0
                ? (isDark ? const Color(0x22EF5350) : const Color(0x18D32F2F))
                : (isDark ? const Color(0x2266BB6A) : const Color(0x182E7D32)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '月总收益 ${monthTotal >= 0 ? "+" : ""}${monthTotal.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: monthTotal >= 0
                      ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828))
                      : (isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32)),
                  height: 1.2,
                ),
              ),
              Text(
                '日均收益 ${monthAvg >= 0 ? "+" : ""}${monthAvg.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: monthAvg >= 0
                      ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828))
                      : (isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32)),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 快速选择年月
  void _showMonthYearPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            int year = _currentCalendarMonth.year;
            int month = _currentCalendarMonth.month;
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('选择年月', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.textTheme.bodyMedium?.color)),
                  const SizedBox(height: 16),
                  // 年份选择
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: theme.colorScheme.primary),
                        onPressed: () => setModalState(() => year--),
                      ),
                      Text('$year年', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                      IconButton(
                        icon: Icon(Icons.chevron_right, color: theme.colorScheme.primary),
                        onPressed: () => setModalState(() => year++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 月份网格
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: List.generate(12, (i) {
                      final m = i + 1;
                      final isSelected = m == month;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentCalendarMonth = DateTime(year, m, 1);
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 60,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$m月',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 星期头
  Widget _buildWeekdayHeader() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: weekdays.map((w) {
          final isWeekend = w == '六' || w == '日';
          return Expanded(
            child: Center(
              child: Text(
                w,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isWeekend
                      ? (isDark ? Colors.redAccent[200] : Colors.red[400])
                      : (isDark ? Colors.grey[500] : Colors.grey[600]),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 日期网格
  Widget _buildCalendarGrid(
    int firstWeekday,
    int totalDays,
    DateTime monthStart,
    Map<String, TradingDayRecord> recordMap,
  ) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 前置空白格（firstWeekday=1 表示周一，前面不需要空格）
    final leadingBlanks = firstWeekday - 1; // 周一=0空白

    final List<Widget> cells = [];

    // 填充前置空白
    for (int i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox());
    }

    // 填充日期
    for (int day = 1; day <= totalDays; day++) {
      final dateStr = '${monthStart.year}-${monthStart.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final record = recordMap[dateStr];
      final isToday = dateStr == todayStr;
      cells.add(_buildDayCell(day, record, isToday));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - 16) / 7;
        final cellH = (constraints.maxHeight) / 6; // 最多6行
        final actualCellH = cellH.clamp(44.0, 80.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            children: cells.map((cell) {
              return SizedBox(
                width: cellW,
                height: actualCellH,
                child: cell,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// 单个日期单元格
  Widget _buildDayCell(int day, TradingDayRecord? record, bool isToday) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodyMedium?.color ?? (isDark ? Colors.white : Colors.black87);

    // ★ 判断是否为非交易日（周末+节假日）
    final cellDate = DateTime(_currentCalendarMonth.year, _currentCalendarMonth.month, day);
    final bool isNonTradingDay = !_isSecuritiesTradingDay(cellDate);

    // 非交易日：灰色显示，不显示任何数据，不可点击
    if (isNonTradingDay) {
      return Container(
        margin: const EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: (isDark ? Colors.grey[700] : Colors.grey[350]),
              ),
            ),
          ],
        ),
      );
    }

    // ★ 判断该记录是否尚未到下一个交易日确认时间 → 显示 0.00%
    final bool isTodayNonTrading = record != null && TradingDayUtils.shouldRecordShowZero(record.date);

    // 待结算
    final bool isPending = record?.notes == '待结算';

    // 颜色
    Color dayColor;
    Color? bgColor;
    Color? borderColor;
    String changeText = '';

    if (record == null) {
      // 无记录
      dayColor = isDark ? Colors.grey[600]! : Colors.grey[400]!;
    } else if (isPending) {
      dayColor = Colors.orange;
      bgColor = Colors.orange.withOpacity(isDark ? 0.12 : 0.08);
      changeText = '待';
    } else {
      final change = isTodayNonTrading ? 0.0 : record.avgChangePercent;
      final isPositive = change >= 0;
      dayColor = isPositive
          ? (isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F))
          : (isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32));
      if (isPositive) {
        changeText = '+${change.toStringAsFixed(1)}%';
      } else {
        changeText = '${change.toStringAsFixed(1)}%';
      }
    }

    // 今天高亮
    if (isToday) {
      borderColor = theme.colorScheme.primary.withOpacity(0.7);
    }

    return GestureDetector(
      onTap: record != null ? () => _showRecordDetail(record) : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: borderColor != null ? Border.all(color: borderColor, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 日期号
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: dayColor,
              ),
            ),
            if (changeText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  changeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: dayColor,
                    height: 1.1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 日历视图 END ====================

  /// 表格头部
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[800], // 深色背景
        border: Border(
          bottom: BorderSide(color: Colors.grey[700]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _buildHeaderText('日期')),
          Expanded(flex: 3, child: _buildHeaderText('总涨跌')),
          Expanded(flex: 3, child: _buildHeaderText('平均涨跌')),
          const SizedBox(width: 40), // 操作按钮空间
        ],
      ),
    );
  }

  Widget _buildHeaderText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: Colors.white, // 白色文字在深色背景上
      ),
    );
  }

  /// 记录列表
  Widget _buildRecordsList() {
    if (_records.isEmpty) {
      return const Center(
        child: Text('暂无记录', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      itemCount: _records.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = _records[index];
        return _buildRecordItem(record);
      },
    );
  }

  Widget _buildRecordItem(TradingDayRecord record) {
    // 检查是否为待结算记录
    final bool isPending = record.notes == '待结算';
    // 获取当前主题颜色
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyMedium?.color ?? Colors.black87;

    // ★ 判断该记录是否尚未到下一个交易日确认时间 → 显示 0.00%
    final bool isTodayNonTrading = TradingDayUtils.shouldRecordShowZero(record.date);

    return InkWell(
      onTap: () => _showRecordDetail(record),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), // 增加垂直间距
        constraints: const BoxConstraints(minHeight: 60), // 最小行高
        color: isPending ? theme.colorScheme.surfaceVariant : null, // 待结算记录背景色（适配主题）
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Text(
                    record.displayDate,
                    style: TextStyle(
                      fontSize: 14,
                      color: isPending ? Colors.grey[600] : textColor, // 使用主题颜色，适配深色模式
                    ),
                    softWrap: false, // 禁止换行
                    overflow: TextOverflow.ellipsis, // 溢出显示省略号
                    maxLines: 1, // 最大1行
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '待',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                isPending || isTodayNonTrading
                    ? '--'
                    : '${record.totalChangePercent >= 0 ? '+' : ''}${record.totalChangePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  color: isPending || isTodayNonTrading
                      ? Colors.grey[400]
                      : (record.totalChangePercent >= 0 ? Colors.red : Colors.green),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                isPending || isTodayNonTrading
                    ? '--'
                    : '${record.avgChangePercent >= 0 ? '+' : ''}${record.avgChangePercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  fontSize: 14,
                  color: isPending || isTodayNonTrading
                      ? Colors.grey[400]
                      : (record.avgChangePercent >= 0 ? Colors.red : Colors.green),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () => _showRecordOptions(record),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示记录详情
  void _showRecordDetail(TradingDayRecord record) {
    final bool isPending = record.notes == '待结算';

    // ★ 判断当前是否在非交易时段（20:00-09:19）且记录是今天的
    // ★ 判断该记录是否尚未到下一个交易日确认时间 → 显示 0.00%
    final bool isTodayNonTrading = TradingDayUtils.shouldRecordShowZero(record.date);
    
    // 使用局部变量管理Dialog内状态（避免setState无法触发Dialog重建）
    bool dialogAnalyzing = false;
    // 如果有已保存的复盘内容，直接显示
    String? dialogResult = record.reviewContent;
    bool isReviewExpanded = record.reviewContent != null; // 有内容时默认展开

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // 极智复盘分析方法（使用setDialogState更新Dialog内部UI）
          Future<void> doAnalyze() async {
            if (_activeModel == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先在设置中配置AI模型'), duration: Duration(seconds: 2)),
              );
              return;
            }

            setDialogState(() { dialogAnalyzing = true; dialogResult = null; });

            // ── 1. 构建基础股票信息 ──
            final stocksInfo = StringBuffer();
            for (int i = 0; i < record.stockCodes.length; i++) {
              final code = record.stockCodes[i];
              final name = i < record.stockNames.length ? record.stockNames[i] : '';
              final change = i < record.stockChanges.length ? record.stockChanges[i] : 0.0;
              final changeStr = change >= 0 ? '+${change.toStringAsFixed(2)}%' : '${change.toStringAsFixed(2)}%';
              stocksInfo.writeln('${i + 1}. $code $name ($changeStr)');
            }

            // ── 2. 并发获取增强数据：证券实时行情 + 东方财富新闻 + 市场板块 ──
            String enrichedQuoteData = '';
            String enrichedNewsData = '';
            String marketSectorData = '';

            try {
              final stockService = LocalDataService();

              final quoteFutures = <Future<Map<String, dynamic>?>>[];
              final newsFutures = <Future<List<Map<String, String>>>>[];

              for (int i = 0; i < record.stockCodes.length; i++) {
                final code = record.stockCodes[i];
                quoteFutures.add(
                  stockService.searchStock(code)
                    .then<Map<String, dynamic>?>((d) => d)
                    .catchError((_) => null)
                );
                newsFutures.add(
                  stockService.fetchStockNews(code, count: 3)
                    .catchError((_) => <Map<String, String>>[])
                );
              }

              final sectorFuture = stockService.fetchHotSectors()
                .catchError((_) => <String, List<Map<String, dynamic>>>{});

              final results = await Future.wait([
                Future.wait(quoteFutures),
                Future.wait(newsFutures),
                sectorFuture,
              ]).timeout(
                const Duration(seconds: 25),
                onTimeout: () => [[], [], <String, List<Map<String, dynamic>>>{}],
              );

              final quoteResults = results[0] as List;
              final newsResults = results[1] as List;
              final sectorData = results[2] as Map<String, List<Map<String, dynamic>>>;

              // ── 构建证券实时行情数据 ──
              final quoteBuf = StringBuffer();
              quoteBuf.writeln('\n【证券实时行情数据】');
              for (int i = 0; i < record.stockCodes.length; i++) {
                final code = record.stockCodes[i];
                final name = i < record.stockNames.length ? record.stockNames[i] : '';
                final quote = quoteResults.isNotEmpty && i < quoteResults.length
                    ? quoteResults[i] as Map<String, dynamic>?
                    : null;

                if (quote != null && quote.isNotEmpty) {
                  quoteBuf.writeln('${i + 1}. [$name] $code');
                  quoteBuf.writeln('   现价:${_s(quote['price'])} | 市值:${_s(quote['market_cap_display'])} | PE:${_s(quote['pe_ratio'])} | PB:${_s(quote['pb_ratio'])} | ROE:${_s(quote['roe'])} | EPS:${_s(quote['eps'])}');
                  quoteBuf.writeln('   换手:${_s(quote['turnover_rate'])}% | 成交量:${_s(quote['volume'])} | 高:${_s(quote['high'])} | 低:${_s(quote['low'])} | 开:${_s(quote['open'])}');
                  quoteBuf.writeln('   营收增速:${_s(quote['revenue_growth'])} | 股息率:${_s(quote['dividend_yield'])} | 52周:${_s(quote['week52_low'])}-${_s(quote['week52_high'])}');

                  final analysis = quote['analysis'] as Map<String, dynamic>?;
                  if (analysis != null) {
                    final capitalFlow = analysis['capital_flow'] as Map<String, dynamic>?;
                    if (capitalFlow != null) {
                      quoteBuf.writeln('   资金面:${_s(capitalFlow['sentiment'])}(评分:${_s(capitalFlow['score'])})');
                    }
                    final priceMod = analysis['price'] as Map<String, dynamic>?;
                    final trendMod = analysis['trend'] as Map<String, dynamic>?;
                    final volMod = analysis['volume'] as Map<String, dynamic>?;
                    final momMod = analysis['momentum'] as Map<String, dynamic>?;
                    final valMod = analysis['valuation'] as Map<String, dynamic>?;
                    if (priceMod != null || trendMod != null || volMod != null) {
                      quoteBuf.write('   技术面:');
                      if (priceMod != null) quoteBuf.write(' 价格${_s(priceMod['sentiment'])}');
                      if (trendMod != null) quoteBuf.write(' 趋势${_s(trendMod['sentiment'])}');
                      if (volMod != null) quoteBuf.write(' 量能${_s(volMod['sentiment'])}');
                      if (momMod != null) quoteBuf.write(' 动量${_s(momMod['sentiment'])}');
                      if (valMod != null) quoteBuf.write(' 估值${_s(valMod['sentiment'])}');
                      quoteBuf.writeln();
                    }
                  }
                } else {
                  quoteBuf.writeln('${i + 1}. $code $name | 实时数据获取失败，基于涨跌数据分析');
                }
              }
              enrichedQuoteData = quoteBuf.toString();

              // ── 构建东方财富新闻数据 ──
              final newsBuf = StringBuffer();
              newsBuf.writeln('\n【东方财富相关新闻资讯】');
              bool hasNews = false;
              for (int i = 0; i < record.stockCodes.length; i++) {
                final name = i < record.stockNames.length ? record.stockNames[i] : '';
                final stockNews = newsResults.isNotEmpty && i < newsResults.length
                    ? newsResults[i] as List
                    : [];
                if (stockNews.isNotEmpty) {
                  hasNews = true;
                  newsBuf.writeln('$name:');
                  for (final n in stockNews) {
                    final m = n as Map<String, String>;
                    newsBuf.writeln('  · ${m['title'] ?? ''} [${m['source'] ?? ''} ${m['date'] ?? ''}]');
                  }
                }
              }
              if (!hasNews) {
                newsBuf.writeln('暂无相关新闻');
              }
              enrichedNewsData = newsBuf.toString();

              // ── 构建市场板块数据 ──
              final sectorBuf = StringBuffer();
              sectorBuf.writeln('\n【市场板块概况】');
              if (sectorData.isNotEmpty) {
                for (final entry in sectorData.entries) {
                  sectorBuf.write('${entry.key}: ');
                  final stocks = entry.value;
                  if (stocks.isNotEmpty) {
                    for (final s in stocks.take(3)) {
                      final sName = s['name']?.toString() ?? '';
                      final sChange = s['change_pct']?.toString() ?? '';
                      sectorBuf.write('$sName($sChange%) ');
                    }
                  }
                  sectorBuf.writeln();
                }
              } else {
                sectorBuf.writeln('市场板块数据获取失败');
              }
              marketSectorData = sectorBuf.toString();

            } catch (e) {
              enrichedQuoteData = '\n[证券实时行情数据获取失败，基于涨跌数据分析]';
              enrichedNewsData = '\n[东方财富新闻获取失败]';
              marketSectorData = '\n[市场板块数据获取失败]';
            }

            // ── 3. 构建增强版提示词 ──
            final prompt = '''作为资深证券分析师，对以下当日股票组合进行复盘分析：

【交易日期】${record.displayDate}
【组合表现】总收益${record.totalChangePercent >= 0 ? '+' : ''}${record.totalChangePercent.toStringAsFixed(2)}%，平均收益${record.avgChangePercent >= 0 ? '+' : ''}${record.avgChangePercent.toStringAsFixed(2)}%

【持仓股票当日涨跌】
${stocksInfo.toString()}
$enrichedQuoteData
$enrichedNewsData
$marketSectorData

请综合以上证券行情数据、资金面、技术面、新闻资讯和板块表现，按以下格式输出专业复盘报告（总字数控制在700字以内）：

一、涨跌归因（每只股票不超过100字，只分析涨跌原因）

1. 【股票名称】涨跌原因：（结合行情数据、资金面、技术面、新闻资讯，分析该股上涨或下跌的核心原因）

（依次分析6只股票，只写涨跌原因，不写操作建议）

二、组合优化方向（不超过100字）

针对当前6只股票组合的表现，提出具体的提升和优化方向，例如：
- 哪些股票可以替换、应换成什么方向的标的
- 组合的行业分布、风格配置是否需要调整
- 风险对冲或仓位优化的建议

【格式要求】
1. 不要加任何装饰性横线或框线，保持简洁
2. 每只股票只分析涨跌原因，不超过100字，不写操作建议
3. 组合优化方向不超过100字，聚焦如何提升和优化该6只股票组合
4. 严禁使用AI常用语如"值得注意的是"、"需要指出的是"、"从某种程度上说"等
5. 语言风格要像资深交易员的手写复盘笔记，直白、犀利、有干货
6. 不要出现"AI分析"、"模型预测"等字眼
7. 充分利用提供的证券行情数据、新闻资讯和板块数据进行交叉验证分析''';

            try {
              final service = AIQAService();
              final result = await service.askQuestion(prompt);
              final cleaned = AIQAService.cleanMarkdown(result).trim();
              if (Navigator.canPop(dialogContext)) {
                final finalResult = cleaned.isEmpty ? 'AI返回内容为空，请重试' : cleaned;
                setDialogState(() { 
                  dialogResult = finalResult; 
                  dialogAnalyzing = false; 
                  isReviewExpanded = true; // 分析完成后自动展开
                });
                // 保存复盘内容到记录
                if (cleaned.isNotEmpty) {
                  final updatedRecord = TradingDayRecord(
                    date: record.date,
                    stockCodes: record.stockCodes,
                    stockNames: record.stockNames,
                    stockChanges: record.stockChanges,
                    totalChangePercent: record.totalChangePercent,
                    avgChangePercent: record.avgChangePercent,
                    notes: record.notes,
                    reviewContent: finalResult,
                    reviewGeneratedAt: DateTime.now().toIso8601String(),
                  );
                  await TradingDayCloudService.addRecord(updatedRecord);
                  // ★ 修复：await 确保复盘内容上传到云端
                  await TradingDayCloudService.uploadToCloud();
                  
                  // ★★★ 关键修复：同步更新内存中的 _records 列表 ★★★
                  // 确保下次打开详情时直接显示已保存的复盘，不用重新生成
                  final recordIndex = _records.indexWhere((r) => r.date == record.date);
                  if (recordIndex >= 0) {
                    _records[recordIndex] = updatedRecord;
                  }
                }
              }
            } catch (e) {
              if (Navigator.canPop(dialogContext)) {
                setDialogState(() { 
                  dialogResult = '复盘分析失败：$e'; 
                  dialogAnalyzing = false; 
                });
              }
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Text('${record.displayDate} 详情'),
                if (isPending) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '待结算',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPending) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '该记录尚未结算，结算后显示实际收益',
                              style: TextStyle(color: Colors.orange[800], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    '总涨跌幅: ${isPending || isTodayNonTrading ? '--' : '${record.totalChangePercent >= 0 ? '+' : ''}${record.totalChangePercent.toStringAsFixed(2)}%'}',
                    style: TextStyle(
                      color: isPending || isTodayNonTrading ? Colors.grey : null,
                    ),
                  ),
                  Text(
                    '平均涨跌幅: ${isPending || isTodayNonTrading ? '--' : '${record.avgChangePercent >= 0 ? '+' : ''}${record.avgChangePercent.toStringAsFixed(2)}%'}',
                    style: TextStyle(
                      color: isPending || isTodayNonTrading ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('股票列表:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...List.generate(record.stockCodes.length, (i) {
                    final code = record.stockCodes[i];
                    final name = i < record.stockNames.length ? record.stockNames[i] : '';
                    final change = i < record.stockChanges.length ? record.stockChanges[i] : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('  ${i + 1}. $code ${name.isNotEmpty ? "($name)" : ""}'),
                          ),
                          Text(
                            isPending || isTodayNonTrading
                                ? '--'
                                : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: isPending || isTodayNonTrading
                                  ? Colors.grey[400]
                                  : (change >= 0 ? Colors.red : Colors.green),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (record.notes != null && record.notes!.isNotEmpty && !isPending) ...[
                    const SizedBox(height: 12),
                    Text('备注: ${record.notes}'),
                  ],
                  
                  // 极智复盘区域（折叠展开 + 分析按钮）
                  if (!isPending) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: [
                          // 折叠展开头部
                          InkWell(
                            onTap: dialogResult != null 
                              ? () => setDialogState(() => isReviewExpanded = !isReviewExpanded)
                              : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.analytics_outlined,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '极智复盘',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        if (record.reviewGeneratedAt != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            '生成于 ${record.reviewGeneratedAt!.substring(0, 16).replaceFirst('T', ' ')}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (dialogResult != null)
                                    AnimatedRotation(
                                      turns: isReviewExpanded ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 200),
                                      child: Icon(
                                        Icons.expand_more,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  else
                                    InkWell(
                                      onTap: dialogAnalyzing ? null : doAnalyze,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: dialogAnalyzing
                                          ? const Center(
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              ),
                                            )
                                          : const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // 展开内容区域
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  if (dialogResult == null)
                                    Center(
                                      child: Text(
                                        '点击下方按钮开始分析',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    )
                                  else if (dialogResult!.isEmpty)
                                    Center(
                                      child: Text(
                                        '分析结果为空，请重试',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    )
                                  else
                                    SelectableText(
                                      dialogResult!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.7,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  // 重新分析按钮（已有内容时显示）
                                  if (dialogResult != null && dialogResult!.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Center(
                                      child: TextButton.icon(
                                        onPressed: dialogAnalyzing ? null : doAnalyze,
                                        icon: dialogAnalyzing
                                          ? const SizedBox(
                                              width: 16, 
                                              height: 16, 
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.refresh, size: 18),
                                        label: Text(dialogAnalyzing ? '分析中...' : '重新分析'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            crossFadeState: isReviewExpanded 
                              ? CrossFadeState.showSecond 
                              : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 300),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示记录操作选项
  void _showRecordOptions(TradingDayRecord record) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                _showEditRecordDialog(record);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(record);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 确认删除
  void _confirmDelete(TradingDayRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${record.displayDate} 的记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await TradingDayCloudService.deleteRecord(record.date);
              // ★ 修复：await 确保删除操作同步到云端
              await TradingDayCloudService.uploadToCloud();
              _loadRecords();
              _showSnackBar('已删除');
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 添加记录对话框
  void _showAddRecordDialog() {
    _showRecordDialog(null);
  }

  /// 编辑记录对话框
  void _showEditRecordDialog(TradingDayRecord record) {
    _showRecordDialog(record);
  }

  /// 记录编辑对话框
  void _showRecordDialog(TradingDayRecord? existingRecord) {
    final dateController = TextEditingController(
      text: existingRecord?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final codesController = TextEditingController(
      text: existingRecord?.stockCodes.join(', ') ?? '',
    );
    final totalChangeController = TextEditingController(
      text: existingRecord?.totalChangePercent.toString() ?? '',
    );
    final avgChangeController = TextEditingController(
      text: existingRecord?.avgChangePercent.toString() ?? '',
    );
    final notesController = TextEditingController(
      text: existingRecord?.notes ?? '',
    );

    // 自动计算平均涨跌
    void calculateAvg() {
      final codes = codesController.text.split(',').where((s) => s.trim().isNotEmpty).toList();
      final total = double.tryParse(totalChangeController.text) ?? 0;
      if (codes.isNotEmpty) {
        final avg = total / codes.length;
        avgChangeController.text = avg.toStringAsFixed(2);
      }
    }

    totalChangeController.addListener(calculateAvg);
    codesController.addListener(calculateAvg);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingRecord == null ? '添加记录' : '编辑记录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: '日期 (YYYY-MM-DD)',
                  hintText: '2024-01-15',
                ),
              ),
              TextField(
                controller: codesController,
                decoration: const InputDecoration(
                  labelText: '股票代码 (用逗号分隔)',
                  hintText: '600000.SS, 000001.SZ, ...',
                ),
              ),
              TextField(
                controller: totalChangeController,
                decoration: const InputDecoration(
                  labelText: '总涨跌幅 (%)',
                  hintText: '例如: 5.32 或 -3.21',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: avgChangeController,
                decoration: const InputDecoration(
                  labelText: '平均涨跌幅 (%)',
                  hintText: '自动计算或手动输入',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: '备注 (可选)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              // 验证输入
              if (dateController.text.isEmpty || codesController.text.isEmpty) {
                _showSnackBar('请填写完整信息');
                return;
              }

              final codes = codesController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              if (codes.length != 6) {
                _showSnackBar('请输入6只股票代码');
                return;
              }

              // ★ 修复：编辑时保留原记录中的 stockNames、stockChanges、reviewContent、reviewGeneratedAt
              // 避免编辑总涨跌/平均涨跌时丢失这些字段
              final record = TradingDayRecord(
                date: dateController.text,
                stockCodes: codes,
                stockNames: existingRecord?.stockNames ?? [],
                stockChanges: existingRecord?.stockChanges ?? [],
                totalChangePercent: double.tryParse(totalChangeController.text) ?? 0,
                avgChangePercent: double.tryParse(avgChangeController.text) ?? 0,
                notes: notesController.text.isEmpty ? null : notesController.text,
                reviewContent: existingRecord?.reviewContent,
                reviewGeneratedAt: existingRecord?.reviewGeneratedAt,
              );

              await TradingDayCloudService.addRecord(record);
              Navigator.pop(context);
              // ★ 修复：await 确保上传完成再提示
              await TradingDayCloudService.uploadToCloud();
              _loadRecords();
              _showSnackBar(existingRecord == null ? '添加成功' : '更新成功');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
