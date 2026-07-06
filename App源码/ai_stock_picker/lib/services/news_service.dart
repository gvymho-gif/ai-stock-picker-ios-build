import 'dart:convert';
import 'package:http/http.dart' as http;

/// 东方财富新闻服务 - 实时财经资讯
class NewsService {
  static const String _baseUrl = 'https://np-listapi.eastmoney.com/comm/web/getListInfo';
  static final http.Client _client = http.Client();

  /// 获取最新财经新闻
  /// [pageSize] 每页条数，默认10条
  /// [type] 1=财经要闻
  static Future<List<Map<String, dynamic>>> fetchLatestNews({int pageSize = 10}) async {
    try {
      final resp = await _client.get(
        Uri.parse('$_baseUrl?client=web&pageSize=$pageSize&type=1&mTypeAndCode=1.000001'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://so.eastmoney.com/',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200 || resp.body.isEmpty) return [];

      final data = json.decode(resp.body);
      if (data['code'] != 1) return [];

      final list = data['data']?['list'] as List? ?? [];
      return list.map<Map<String, dynamic>>((item) {
        return {
          'title': item['Art_Title']?.toString() ?? '',
          'code': item['Art_Code']?.toString() ?? '',
          'time': item['Art_ShowTime']?.toString() ?? '',
          'url': item['Art_Url']?.toString() ?? '',
        };
      }).where((item) => item['title']!.isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }

  /// 抓取新闻正文内容
  /// 从东方财富新闻页面提取正文
  static Future<String> fetchNewsContent(String url) async {
    try {
      final resp = await _client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://so.eastmoney.com/',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200 || resp.body.isEmpty) {
        return '无法加载新闻内容，请检查网络连接。';
      }

      final html = resp.body;

      // 匹配 id="ContentBody" 的正文div
      final contentMatch = RegExp(
        "<div[^>]*id=[\"']ContentBody[\"'][^>]*>(.*?)</div>",
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);

      if (contentMatch == null) {
        return '暂无新闻正文内容。';
      }

      // 去除HTML标签
      String content = contentMatch.group(1) ?? '';
      content = content.replaceAll(RegExp(r'<[^>]+>'), '');
      // 去除多余空白
      content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      // 去除文章来源
      content = content.replaceAll(RegExp(r'（文章来源：[^）]+）'), '');

      return content.isNotEmpty ? content : '暂无新闻正文内容。';
    } catch (e) {
      return '加载新闻内容失败：$e';
    }
  }

  /// 格式化时间显示
  static String formatTime(String timeStr) {
    try {
      final dt = DateTime.parse(timeStr);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timeStr;
    }
  }
}
