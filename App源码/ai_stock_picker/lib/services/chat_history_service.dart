import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天历史服务 - 保存和加载聊天记录
class ChatHistoryService {
  static const _keyChatHistory = 'chat_history_v1';
  static const int _maxHistoryCount = 20; // 最多保存20条记录

  /// 保存一条用户消息和AI回复
  static Future<void> saveMessage(String question, String answer) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();

    // 添加新的消息对
    history.add({
      'question': question,
      'answer': answer,
      'time': DateTime.now().toIso8601String(),
    });

    // 只保留最近20条
    if (history.length > _maxHistoryCount) {
      history.removeRange(0, history.length - _maxHistoryCount);
    }

    await prefs.setString(_keyChatHistory, json.encode(history));
  }

  /// 获取历史记录
  static Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyChatHistory);
    if (jsonStr == null) return [];

    try {
      final List<dynamic> list = json.decode(jsonStr);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// 清空历史记录
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyChatHistory);
  }
}
