class FarmTimelineEvent {
  final String id;
  final String farmId;
  final String farmerId;
  final String farmerPhone;
  final String eventType;
  final String title;
  final String message;
  final String stage;
  final String severity;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const FarmTimelineEvent({
    required this.id,
    required this.farmId,
    required this.farmerId,
    required this.farmerPhone,
    required this.eventType,
    required this.title,
    required this.message,
    required this.stage,
    required this.severity,
    required this.payload,
    required this.createdAt,
  });

  factory FarmTimelineEvent.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    return FarmTimelineEvent(
      id: '${json['id'] ?? ''}',
      farmId: '${json['farm_id'] ?? json['farmId'] ?? ''}',
      farmerId: '${json['farmer_id'] ?? json['farmerId'] ?? ''}',
      farmerPhone: '${json['farmer_phone'] ?? json['farmerPhone'] ?? ''}',
      eventType: '${json['event_type'] ?? json['eventType'] ?? ''}',
      title: '${json['title'] ?? ''}',
      message: '${json['message'] ?? ''}',
      stage: '${json['stage'] ?? ''}',
      severity: '${json['severity'] ?? 'info'}',
      payload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? json['createdAt'] ?? ''}') ??
          DateTime.now(),
    );
  }
}
