/// AI模型配置模型
class AIModelConfig {
  final String id;
  final String name;
  final String provider;
  final String apiKey;
  final String baseUrl;
  final String model;
  final bool isEnabled;
  final DateTime? createdAt;

  // 高级参数 (v2.1+)
  final double temperature;
  final int maxTokens;
  final double? topP;
  final double? frequencyPenalty;
  final double? presencePenalty;

  const AIModelConfig({
    required this.id,
    required this.name,
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.isEnabled = true,
    this.createdAt,
    this.temperature = 0.7,
    this.maxTokens = 2500,
    this.topP,
    this.frequencyPenalty,
    this.presencePenalty,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'isEnabled': isEnabled,
      'createdAt': createdAt?.toIso8601String(),
      'temperature': temperature,
      'maxTokens': maxTokens,
      if (topP != null) 'topP': topP,
      if (frequencyPenalty != null) 'frequencyPenalty': frequencyPenalty,
      if (presencePenalty != null) 'presencePenalty': presencePenalty,
    };
  }

  factory AIModelConfig.fromJson(Map<String, dynamic> json) {
    return AIModelConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      isEnabled: json['isEnabled'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 2500,
      topP: (json['topP'] as num?)?.toDouble(),
      frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
      presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
    );
  }

  AIModelConfig copyWith({
    String? id,
    String? name,
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    bool? isEnabled,
    DateTime? createdAt,
    double? temperature,
    int? maxTokens,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
  }) {
    return AIModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
    );
  }

  /// 预设模板
  static AIModelConfig presetConservative(String id, {String apiKey = ''}) {
    return AIModelConfig(
      id: id, name: '保守模式', provider: 'Preset',
      apiKey: apiKey, baseUrl: 'https://api.openai.com/v1', model: '',
      temperature: 0.3, maxTokens: 1500, topP: 0.8,
    );
  }

  static AIModelConfig presetBalanced(String id, {String apiKey = ''}) {
    return AIModelConfig(
      id: id, name: '平衡模式', provider: 'Preset',
      apiKey: apiKey, baseUrl: 'https://api.openai.com/v1', model: '',
      temperature: 0.7, maxTokens: 2500, topP: 0.9,
    );
  }

  static AIModelConfig presetCreative(String id, {String apiKey = ''}) {
    return AIModelConfig(
      id: id, name: '创意模式', provider: 'Preset',
      apiKey: apiKey, baseUrl: 'https://api.openai.com/v1', model: '',
      temperature: 1.0, maxTokens: 3500, topP: 0.95,
    );
  }
}