/// AI模型预设模板 - 各提供商最强模型配置
class AIModelPreset {
  final String name;
  final String provider;
  final String baseUrl;
  final String model;
  final String icon;

  const AIModelPreset({
    required this.name,
    required this.provider,
    required this.baseUrl,
    required this.model,
    this.icon = '🤖',
  });

  // 预设模板列表 - 各提供商最强模型
  static const List<AIModelPreset> presets = [
    // Agnes AI - 免费全模态旗舰模型 (Sapiens AI)
    AIModelPreset(
      name: 'Agnes-2.0-Flash',
      provider: 'Agnes AI',
      baseUrl: 'https://apihub.agnes-ai.com/v1',
      model: 'agnes-2.0-flash',
      icon: '💎',
    ),
    // 智谱AI - GLM-5.1 最新旗舰推理模型
    AIModelPreset(
      name: 'GLM-5.1',
      provider: '智谱AI',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-5.1',
      icon: '🟢',
    ),
    // 智谱AI - GLM-4.7-Flash 轻量极速模型（免费）
    AIModelPreset(
      name: 'GLM-4.7-Flash',
      provider: '智谱AI',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-4.7-flash',
      icon: '⚡',
    ),
    // 月之暗面 - Kimi K2.6 最强旗舰模型
    AIModelPreset(
      name: 'Kimi-K2.6',
      provider: '月之暗面',
      baseUrl: 'https://api.moonshot.cn/v1',
      model: 'kimi-k2.6',
      icon: '🌙',
    ),
    // DeepSeek - V4-Pro 最强推理模型 (1.6T参数)
    AIModelPreset(
      name: 'DeepSeek-V4-Pro',
      provider: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-v4-pro',
      icon: '🔵',
    ),
    // OpenAI - GPT-4o 旗舰最强模型
    AIModelPreset(
      name: 'GPT-4o',
      provider: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o',
      icon: '🟣',
    ),
    // Anthropic - Claude Opus 4.6 最强模型
    AIModelPreset(
      name: 'Claude-Opus-4.6',
      provider: 'Anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      model: 'claude-opus-4-6',
      icon: '🟠',
    ),
    // 阿里云 - Qwen-Max 最强模型
    AIModelPreset(
      name: 'Qwen-Max',
      provider: '阿里云',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen-max',
      icon: '🟡',
    ),
    // Groq - Llama 4 Maverick 最强Llama模型
    AIModelPreset(
      name: 'Llama-4-Maverick',
      provider: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-4-maverick',
      icon: '⚡',
    ),
  ];
}
