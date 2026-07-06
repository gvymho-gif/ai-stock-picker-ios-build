/// 新闻详情页 - 显示新闻内容 + 极智AI解读
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/ai_qa_service.dart';
import '../services/ai_model_service.dart';
import '../services/news_service.dart';
import '../models/ai_model_config.dart';

class NewsDetailScreen extends StatefulWidget {
  final Map<String, dynamic> news;

  const NewsDetailScreen({Key? key, required this.news}) : super(key: key);

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  String? _aiAnalysis;
  bool _analyzing = false;
  AIModelConfig? _activeModel;

  // 新闻正文相关状态
  String _content = '';
  bool _loadingContent = true;
  String? _contentError;

  @override
  void initState() {
    super.initState();
    _loadActiveModel();
    _loadNewsContent();
  }

  void _loadActiveModel() async {
    final model = await AIModelService.getActiveModel();
    if (mounted) setState(() => _activeModel = model);
  }

  /// 加载新闻正文
  void _loadNewsContent() async {
    final url = widget.news['url']?.toString() ?? '';
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _content = '暂无新闻链接，无法获取正文内容。';
          _loadingContent = false;
        });
      }
      return;
    }

    final content = await NewsService.fetchNewsContent(url);
    if (mounted) {
      setState(() {
        _content = content;
        _loadingContent = false;
      });
    }
  }

  void _analyzeNews() async {
    if (_activeModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置AI模型')),
      );
      return;
    }

    setState(() { _analyzing = true; _aiAnalysis = null; });

    final title = widget.news['title']?.toString() ?? '';
    final time = widget.news['time']?.toString() ?? '';
    final content = _content.isNotEmpty ? _content : title;

    final prompt = '请用通俗易懂的语言，对以下财经新闻进行简要分析（总字数控制在800字以内）：\n\n'
        '【新闻标题】$title\n'
        '【发布时间】$time\n'
        '【新闻内容】$content\n\n'
        '请按以下4个要点回答，每点简明扼要：\n\n'
        '一、新闻说了啥\n'
        '用1-2句话概括这条新闻的核心内容，让普通人也能听懂。\n\n'
        '二、为啥会有这事\n'
        '简单说明背后的原因，是什么政策、市场变化或行业趋势导致的。\n\n'
        '三、利好谁、利空谁\n'
        '点明对哪些行业或板块是利好，对哪些是利空。\n\n'
        '四、投资机会与风险\n'
        '给出1-2条具体投资建议，并简要提示风险。\n\n'
        '【格式要求】\n'
        '- 语言口语化、接地气，少用专业术语\n'
        '- 不要用Markdown标记（如###、**、*等）\n'
        '- 每点直接写内容，不要空行\n'
        '- 结论要明确，不要模棱两可\n'
        '- 严禁编造具体数据';

    try {
      final service = AIQAService();
      final result = await service.askQuestion(prompt);
      if (mounted) setState(() { _aiAnalysis = AIQAService.cleanMarkdown(result); _analyzing = false; });
    } catch (e) {
      if (mounted) setState(() { _aiAnalysis = '分析失败：$e'; _analyzing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = widget.news['title']?.toString() ?? '';
    final time = widget.news['time']?.toString() ?? '';

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
          title: Text('新闻详情', style: AppText.h3.copyWith(color: colors.textPrimary)),
          centerTitle: true,
          actions: [
            // 极智解读按钮
            TextButton.icon(
              onPressed: _analyzing ? null : _analyzeNews,
              icon: _analyzing
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(colors.primary)))
                  : Icon(Icons.auto_awesome, size: 18, color: colors.primary),
              label: Text(
                _analyzing ? '分析中...' : '极智解读',
                style: AppText.body2.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 新闻标题
              Text(
                title,
                style: AppText.h2.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // 分隔线
              Divider(color: colors.border),
              const SizedBox(height: AppSpacing.md),

              // 发布时间
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: colors.textHint),
                  const SizedBox(width: 6),
                  Text(
                    '发布时间：$time',
                    style: AppText.body2.copyWith(color: colors.textHint),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // 新闻正文内容（普通文本排版，无框线）
              _loadingContent
                  ? Center(
                      child: Column(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(colors.primary),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '正在加载新闻内容...',
                            style: AppText.body2.copyWith(color: colors.textHint),
                          ),
                        ],
                      ),
                    )
                  : SelectableText(
                      _content,
                      style: AppText.body1.copyWith(
                        color: colors.textPrimary,
                        height: 1.8,
                        fontSize: 16,
                      ),
                    ),
              const SizedBox(height: AppSpacing.xl),

              // 极智分析结果
              if (_aiAnalysis != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors.primary.withOpacity(0.1), colors.primary.withOpacity(0.05)],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 18, color: colors.primary),
                          const SizedBox(width: 8),
                          Text(
                            '极智分析',
                            style: AppText.h3.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SelectableText(
                        _aiAnalysis!,
                        style: AppText.body1.copyWith(
                          color: colors.textPrimary,
                          height: 1.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
