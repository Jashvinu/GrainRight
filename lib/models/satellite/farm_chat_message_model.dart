class FarmChatMessageDraft {
  final String role;
  final String source;
  final String message;
  final String language;
  final String? growthStage;
  final int? daysAfterSowing;
  final Map<String, dynamic> weatherSnapshot;
  final Map<String, dynamic> farmContext;
  final DateTime? createdAt;

  const FarmChatMessageDraft({
    required this.role,
    required this.source,
    required this.message,
    this.language = 'en',
    this.growthStage,
    this.daysAfterSowing,
    this.weatherSnapshot = const <String, dynamic>{},
    this.farmContext = const <String, dynamic>{},
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'source': source,
      'message': message,
      'language': language,
      if (growthStage != null && growthStage!.trim().isNotEmpty)
        'growthStage': growthStage,
      if (daysAfterSowing != null) 'daysAfterSowing': daysAfterSowing,
      if (weatherSnapshot.isNotEmpty) 'weatherSnapshot': weatherSnapshot,
      if (farmContext.isNotEmpty) 'farmContext': farmContext,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }

  static String normalizeRole(String value) {
    final role = value.trim().toLowerCase();
    if (role == 'farmer' || role == 'assistant' || role == 'system') {
      return role;
    }
    return 'system';
  }

  static String normalizeSource(String value) {
    final source = value.trim().toLowerCase();
    return source.isEmpty ? 'ai_chat' : source;
  }
}

class FarmChatMemoryEntry extends FarmChatMessageDraft {
  final String id;
  final String farmId;
  final String? farmerPhone;
  final String? farmerId;

  const FarmChatMemoryEntry({
    required this.id,
    required this.farmId,
    this.farmerPhone,
    this.farmerId,
    required super.role,
    required super.source,
    required super.message,
    super.language,
    super.growthStage,
    super.daysAfterSowing,
    super.weatherSnapshot,
    super.farmContext,
    super.createdAt,
  });

  factory FarmChatMemoryEntry.fromJson(Map<String, dynamic> json) {
    return FarmChatMemoryEntry(
      id: '${json['id'] ?? ''}'.trim(),
      farmId: '${json['farm_id'] ?? json['farmId'] ?? ''}'.trim(),
      farmerPhone: _optionalText(json['farmer_phone'] ?? json['farmerPhone']),
      farmerId: _optionalText(json['farmer_id'] ?? json['farmerId']),
      role: FarmChatMessageDraft.normalizeRole('${json['role'] ?? ''}'),
      source: FarmChatMessageDraft.normalizeSource('${json['source'] ?? ''}'),
      message: '${json['message'] ?? ''}'.trim(),
      language: '${json['language'] ?? 'en'}'.trim().isEmpty
          ? 'en'
          : '${json['language'] ?? 'en'}'.trim(),
      growthStage: _optionalText(json['growth_stage'] ?? json['growthStage']),
      daysAfterSowing: _intOrNull(
        json['days_after_sowing'] ?? json['daysAfterSowing'],
      ),
      weatherSnapshot: _mapOrEmpty(
        json['weather_snapshot'] ?? json['weatherSnapshot'],
      ),
      farmContext: _mapOrEmpty(json['farm_context'] ?? json['farmContext']),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    );
  }

  static String? _optionalText(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static Map<String, dynamic> _mapOrEmpty(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
