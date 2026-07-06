/// 聊天消息模型
class ChatMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime time;

  /// 消息类型: text / chart / report
  final String messageType;

  /// 图表数据 (messageType=chart 时使用)
  final Map<String, dynamic>? chartData;

  /// K线数据列表 (OHLCV)
  final List<Map<String, double>>? klineData;

  /// AI回复后的推荐追问列表
  final List<String>? suggestedQuestions;

  /// 数据来源标签（AI消息使用）
  final List<String>? dataSources;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.time,
    this.messageType = 'text',
    this.chartData,
    this.klineData,
    this.suggestedQuestions,
    this.dataSources,
  });

  bool get isChartMessage => messageType == 'chart';
  bool get isReportMessage => messageType == 'report';

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isUser,
    DateTime? time,
    String? messageType,
    Map<String, dynamic>? chartData,
    List<Map<String, double>>? klineData,
    List<String>? suggestedQuestions,
    List<String>? dataSources,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      time: time ?? this.time,
      messageType: messageType ?? this.messageType,
      chartData: chartData ?? this.chartData,
      klineData: klineData ?? this.klineData,
      suggestedQuestions: suggestedQuestions ?? this.suggestedQuestions,
      dataSources: dataSources ?? this.dataSources,
    );
  }
}
