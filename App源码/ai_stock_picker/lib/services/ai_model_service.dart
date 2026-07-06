import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_model_config.dart';

/// AI模型配置服务 - 管理AI模型API配置
class AIModelService {
  static const _keyModels = 'ai_model_configs';
  static const _keyActiveModel = 'active_ai_model';

  /// 获取所有AI模型配置
  static Future<List<AIModelConfig>> getModels() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyModels);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList
          .map((e) => AIModelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取启用的AI模型配置
  static Future<List<AIModelConfig>> getEnabledModels() async {
    final models = await getModels();
    return models.where((m) => m.isEnabled).toList();
  }

  /// 添加AI模型配置
  static Future<bool> addModel(AIModelConfig model) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getModels();
    if (models.any((m) => m.id == model.id)) {
      return false;
    }
    models.add(model);
    await prefs.setString(_keyModels, json.encode(models));
    return true;
  }

  /// 更新AI模型配置
  static Future<bool> updateModel(AIModelConfig updatedModel) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getModels();
    final index = models.indexWhere((m) => m.id == updatedModel.id);
    if (index >= 0) {
      models[index] = updatedModel;
      await prefs.setString(_keyModels, json.encode(models));
      return true;
    }
    return false;
  }

  /// 删除AI模型配置
  static Future<bool> deleteModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final models = await getModels();
    models.removeWhere((m) => m.id == modelId);
    await prefs.setString(_keyModels, json.encode(models));
    
    // 如果删除的是当前激活的模型，清除激活状态
    final activeId = await getActiveModelId();
    if (activeId == modelId) {
      await setActiveModelId(null);
    }
    return true;
  }

  /// 获取当前激活的模型ID
  static Future<String?> getActiveModelId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveModel);
  }

  /// 设置当前激活的模型ID
  static Future<void> setActiveModelId(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null) {
      await prefs.remove(_keyActiveModel);
    } else {
      await prefs.setString(_keyActiveModel, modelId);
    }
  }

  /// 获取当前激活的模型配置
  static Future<AIModelConfig?> getActiveModel() async {
    final activeId = await getActiveModelId();
    if (activeId == null) return null;
    final models = await getModels();
    return models.cast<AIModelConfig?>().firstWhere(
      (m) => m?.id == activeId,
      orElse: () => null,
    );
  }

  /// 清空所有配置
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyModels);
    await prefs.remove(_keyActiveModel);
  }
}