import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_stock.dart';
import '../models/favorite_category.dart';

/// 收藏服务 - 管理股票收藏和分类
class FavoriteService {
  static const _keyCategories = 'favorite_categories';
  static const _keyStocks = 'favorite_stocks';

  /// 获取所有分类
  static Future<List<FavoriteCategory>> getCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCategories);
    if (jsonStr == null) {
      return [];
    }
    try {
      final List<dynamic> jsonList = json.decode(jsonStr!);
      return jsonList
          .map((e) => FavoriteCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加自定义分类
  static Future<bool> addCategory(FavoriteCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    final categories = await getCategories();
    if (categories.any((c) => c.id == category.id)) {
      return false;
    }
    categories.add(category);
    await prefs.setString(_keyCategories, json.encode(categories));
    return true;
  }

  /// 删除分类
  static Future<bool> deleteCategory(String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final categories = await getCategories();
    categories.removeWhere((c) => c.id == categoryId);
    await prefs.setString(_keyCategories, json.encode(categories));

    // 删除该分类下的股票
    await clearCategory(categoryId);
    return true;
  }

  /// 重命名分类
  static Future<bool> renameCategory(String categoryId, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final categories = await getCategories();
    final index = categories.indexWhere((c) => c.id == categoryId);
    if (index >= 0) {
      categories[index] = categories[index].copyWith(name: newName);
      await prefs.setString(_keyCategories, json.encode(categories));
      return true;
    }
    return false;
  }

  /// 获取所有收藏股票
  static Future<List<FavoriteStock>> getStocks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyStocks);
    if (jsonStr == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonStr!);
      return jsonList
          .map((e) => FavoriteStock.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取指定分类的收藏股票
  static Future<List<FavoriteStock>> getStocksByCategory(String categoryId) async {
    final stocks = await getStocks();
    return stocks.where((s) => s.category == categoryId).toList();
  }

  /// 添加收藏股票
  static Future<bool> addStock(FavoriteStock stock) async {
    final prefs = await SharedPreferences.getInstance();
    final stocks = await getStocks();
    if (stocks.any((s) => s.symbol == stock.symbol)) {
      return false;
    }
    stocks.add(stock);
    await prefs.setString(_keyStocks, json.encode(stocks));
    return true;
  }

  /// 移除收藏股票
  static Future<bool> removeStock(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final stocks = await getStocks();
    final initialLength = stocks.length;
    stocks.removeWhere((s) => s.symbol == symbol);
    if (stocks.length < initialLength) {
      await prefs.setString(_keyStocks, json.encode(stocks));
      return true;
    }
    return false;
  }

  /// 更新收藏股票数据（价格、涨跌幅等）
  static Future<void> updateStock(FavoriteStock updatedStock) async {
    final prefs = await SharedPreferences.getInstance();
    final stocks = await getStocks();
    final index = stocks.indexWhere((s) => s.symbol == updatedStock.symbol);
    if (index >= 0) {
      stocks[index] = updatedStock;
      await prefs.setString(_keyStocks, json.encode(stocks));
    }
  }

  /// 检查股票是否已收藏
  static Future<bool> isFavorite(String symbol) async {
    final stocks = await getStocks();
    return stocks.any((s) => s.symbol == symbol);
  }

  /// 获取股票所在的分类ID
  static Future<String?> getStockCategory(String symbol) async {
    final stocks = await getStocks();
    final stock = stocks.cast<FavoriteStock?>().firstWhere(
      (s) => s?.symbol == symbol,
      orElse: () => null,
    );
    return stock?.category;
  }

  /// 清空所有收藏
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStocks);
  }

  /// 清空指定分类的收藏
  static Future<void> clearCategory(String categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final stocks = await getStocks();
    stocks.removeWhere((s) => s.category == categoryId);
    await prefs.setString(_keyStocks, json.encode(stocks));
  }
}
