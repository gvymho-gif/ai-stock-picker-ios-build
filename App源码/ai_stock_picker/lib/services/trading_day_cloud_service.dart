/// 交易日记录服务
/// 负责本地数据存储和从ExpertPerformance导入
/// 云端上传/下载统一由 BackupService 处理（合并为单个备份文件）

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trading_day_record.dart';
import '../utils/trading_day_utils.dart';
import 'backup_service.dart';

class TradingDayCloudService {
  static const String _kLocalStorageKey = 'trading_day_records';

  // ========== 本地存储 ==========

  /// 保存记录到本地
  static Future<void> saveRecordsLocally(List<TradingDayRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = records.map((r) => r.toJson()).toList();
    await prefs.setString(_kLocalStorageKey, jsonEncode(jsonList));
  }

  /// 从本地获取记录
  /// ★ 自动过滤并清理非交易日（周末+节假日）的脏数据
  static Future<List<TradingDayRecord>> getLocalRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kLocalStorageKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final allRecords = jsonList.map((j) => TradingDayRecord.fromJson(j)).toList();

      // ★ 源头清理：过滤掉非交易日记录，并持久化清理结果
      final cleanRecords = allRecords
          .where((r) => !TradingDayUtils.isNonTradingDayStr(r.date))
          .toList();

      // 如果有脏数据被清理，写回干净的数据
      if (cleanRecords.length != allRecords.length) {
        final removedDates = allRecords
            .where((r) => TradingDayUtils.isNonTradingDayStr(r.date))
            .map((r) => r.date)
            .toList();
        print('[交易日记录] 清理非交易日脏数据: $removedDates');
        final cleanJsonList = cleanRecords.map((r) => r.toJson()).toList();
        await prefs.setString(_kLocalStorageKey, jsonEncode(cleanJsonList));
      }

      return cleanRecords;
    } catch (e) {
      print('[交易日记录] 本地读取失败: $e');
      return [];
    }
  }

  /// 添加单条记录
  static Future<void> addRecord(TradingDayRecord record) async {
    final records = await getLocalRecords();
    // 如果日期已存在，先删除旧记录
    records.removeWhere((r) => r.date == record.date);
    records.add(record);
    // 按日期排序（最新的在前）
    records.sort((a, b) => b.date.compareTo(a.date));
    await saveRecordsLocally(records);
  }

  /// 删除记录
  static Future<void> deleteRecord(String date) async {
    final records = await getLocalRecords();
    records.removeWhere((r) => r.date == date);
    await saveRecordsLocally(records);
  }

  /// 同步本地和云端（智能合并数据）
  ///
  /// 修复点（v2）：
  /// 1. 合并策略改为「数据更丰富的版本优先」——保留 reviewContent、stockChanges 等本地修改
  /// 2. 合并后自动回传云端，确保本地新增/修改的数据同步上去
  static Future<Map<String, dynamic>> syncWithCloud() async {
    try {
      final token = await BackupService.getGiteeToken();
      final repoPath = await BackupService.getFullRepoPath();

      if (token == null || repoPath == null) {
        return {'ok': false, 'error': '未配置Gitee Token'};
      }

      // 1. 从云端下载合并备份
      final content = await BackupService.restoreFromGitee(token, repoPath);
      if (content == null) {
        return {'ok': false, 'error': '云端无备份数据'};
      }

      final data = jsonDecode(content);
      int cloudCount = 0;

      // 2. 获取云端交易日记录
      List<TradingDayRecord> cloudRecords = [];
      if (data is Map && data['tradingDayRecords'] is List) {
        cloudRecords = (data['tradingDayRecords'] as List)
            .map((j) => TradingDayRecord.fromJson(j))
            .toList();
        cloudCount = cloudRecords.length;
      }

      // 3. 获取本地记录
      final localRecords = await getLocalRecords();

      // 4. 智能合并数据（以日期为键，保留数据更丰富的版本）
      // 策略：对于同一日期的记录，选择数据更完整的版本（有复盘内容 > 无复盘内容）
      // 这避免了"云端旧数据覆盖本地新修改"的问题
      final mergedMap = <String, TradingDayRecord>{};
      for (var record in localRecords) {
        mergedMap[record.date] = record;
      }
      for (var record in cloudRecords) {
        final existing = mergedMap[record.date];
        if (existing == null) {
          // 云端有而本地没有，直接添加
          mergedMap[record.date] = record;
        } else {
          // 两边都有，选择数据更丰富的版本
          mergedMap[record.date] = _selectRicherRecord(existing, record);
        }
      }

      final mergedRecords = mergedMap.values.toList();
      mergedRecords.sort((a, b) => b.date.compareTo(a.date));

      // 5. 保存合并后的记录到本地
      await saveRecordsLocally(mergedRecords);

      // 6. 合并后自动回传云端（修复：之前只下载不同步回传）
      try {
        await uploadToCloud();
        print('[交易日记录] 同步后自动回传云端完成');
      } catch (e) {
        print('[交易日记录] 同步后回传云端失败（本地合并已保存）: $e');
      }

      return {
        'ok': true,
        'error': '',
        'localCount': localRecords.length,
        'cloudCount': cloudCount,
        'mergedCount': mergedRecords.length,
      };
    } catch (e) {
      return {'ok': false, 'error': '同步异常: $e'};
    }
  }

  /// 选择数据更丰富的记录（用于智能合并）
  ///
  /// 优先级规则：
  /// 1. 有极智复盘内容 > 无复盘内容
  /// 2. 有股票涨跌数据 > 无涨跌数据
  /// 3. 有备注 > 无备注
  /// 4. 以上都相同时，保留本地版本（用户端数据通常更新）
  static TradingDayRecord _selectRicherRecord(TradingDayRecord local, TradingDayRecord cloud) {
    // 规则1：有复盘内容的优先
    final localHasReview = local.reviewContent != null && local.reviewContent!.isNotEmpty;
    final cloudHasReview = cloud.reviewContent != null && cloud.reviewContent!.isNotEmpty;
    if (localHasReview && !cloudHasReview) return local;
    if (!localHasReview && cloudHasReview) return cloud;

    // 规则2：有涨跌数据的优先（非零涨跌幅条数更多）
    final localNonZeroChanges = local.stockChanges.where((c) => c != 0.0).length;
    final cloudNonZeroChanges = cloud.stockChanges.where((c) => c != 0.0).length;
    if (localNonZeroChanges > cloudNonZeroChanges) return local;
    if (localNonZeroChanges < cloudNonZeroChanges) return cloud;

    // 规则3：有备注的优先
    final localHasNotes = local.notes != null && local.notes!.isNotEmpty;
    final cloudHasNotes = cloud.notes != null && cloud.notes!.isNotEmpty;
    if (localHasNotes && !cloudHasNotes) return local;
    if (!localHasNotes && cloudHasNotes) return cloud;

    // 规则4：数据丰富度相同时，保留本地版本
    return local;
  }

  /// 将本地交易日记录 + 收益统计合并上传到云端
  /// 供交易日记录页面在编辑/删除后调用
  static Future<bool> uploadToCloud() async {
    try {
      final token = await BackupService.getGiteeToken();
      final repoPath = await BackupService.getFullRepoPath();
      if (token == null || token.isEmpty || repoPath == null) return false;

      // 获取交易日记录
      final tradingRecords = await getLocalRecords();

      // 获取收益统计数据
      final expertHistory = await _getExpertPerformanceJson();

      // 构建合并备份（version 2 格式）
      final combinedData = {
        'version': 2,
        'backupTime': DateTime.now().toIso8601String(),
        'expertPerformanceCount': expertHistory.length,
        'tradingDayCount': tradingRecords.length,
        'expertPerformance': expertHistory,
        'tradingDayRecords': tradingRecords.map((r) => r.toJson()).toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(combinedData);

      final result = await BackupService.backupToGiteeWithDetail(token, repoPath, json);
      if (result['ok'] == true) {
        print('[交易日记录] 云端上传成功（交易日${tradingRecords.length}条）');
        return true;
      } else {
        print('[交易日记录] 云端上传失败: ${result['error']}');
        return false;
      }
    } catch (e) {
      print('[交易日记录] 云端上传异常: $e');
      return false;
    }
  }

  /// 获取收益统计的JSON列表（用于构建合并备份）
  static Future<List<Map<String, dynamic>>> _getExpertPerformanceJson() async {
    try {
      // 间接通过 ExpertPerformanceService 获取数据
      // 避免循环依赖，这里直接读 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('expert_performance_history');
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      print('[交易日记录] 获取收益统计数据失败: $e');
      return [];
    }
  }

  /// 检查云端是否有记录
  static Future<bool> hasCloudRecords() async {
    try {
      final token = await BackupService.getGiteeToken();
      final repoPath = await BackupService.getFullRepoPath();
      if (token == null || repoPath == null) return false;

      final content = await BackupService.restoreFromGitee(token, repoPath);
      if (content == null) return false;

      final data = jsonDecode(content);
      return data is Map && data['tradingDayRecords'] is List;
    } catch (_) {
      return false;
    }
  }

  // ========== 从ExpertPerformance转换 ==========

  /// 将专家收益记录列表转换为交易日记录
  /// 调用方需要提供ExpertPerformanceService.getHistory()的结果
  static Future<int> importFromExpertPerformance(
    List<dynamic> expertHistory,
  ) async {
    try {
      final existingRecords = await getLocalRecords();
      final existingDates = existingRecords.map((r) => r.date).toSet();

      int importedCount = 0;
      for (var perf in expertHistory) {
        // 跳过已存在的日期
        if (existingDates.contains(perf.date)) continue;
        // 只导入已结算的记录
        if (!perf.isSettled) continue;

        final codes = perf.stocks.map((s) => s.code.toString()).toList();
        final names = perf.stocks.map((s) => s.name.toString()).toList();
        final changes = perf.stocks.map((s) => s.changePercent.toDouble()).toList();

        final record = TradingDayRecord(
          date: perf.date,
          stockCodes: codes,
          stockNames: names,
          stockChanges: changes,
          totalChangePercent: perf.dailyAvgChange * perf.stocks.length,
          avgChangePercent: perf.dailyAvgChange,
          notes: '从收益统计导入',
        );

        await addRecord(record);
        importedCount++;
      }

      print('[交易日记录] 从ExpertPerformance导入 $importedCount 条记录');
      return importedCount;
    } catch (e) {
      print('[交易日记录] 导入失败: $e');
      return 0;
    }
  }
}
