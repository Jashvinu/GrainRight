class FarmerDailyTask {
  final String id;
  final String farmId;
  final DateTime taskDate;
  final String taskKey;
  final String taskType;
  final String titleKey;
  final String descriptionKey;
  final String priority;
  final String status;
  final String sourceType;
  final String sourceId;
  final String actionRoute;
  final Map<String, dynamic> metadata;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? snoozedUntil;

  const FarmerDailyTask({
    this.id = '',
    required this.farmId,
    required this.taskDate,
    required this.taskKey,
    required this.taskType,
    required this.titleKey,
    required this.descriptionKey,
    required this.priority,
    this.status = 'pending',
    required this.sourceType,
    this.sourceId = '',
    this.actionRoute = '',
    this.metadata = const {},
    this.dueAt,
    this.completedAt,
    this.snoozedUntil,
  });

  factory FarmerDailyTask.fromJson(Map<String, dynamic> json) {
    return FarmerDailyTask(
      id: _text(json['id']),
      farmId: _text(json['farm_id']),
      taskDate: DateTime.tryParse(_text(json['task_date'])) ?? DateTime.now(),
      taskKey: _text(json['task_key']),
      taskType: _text(json['task_type']),
      titleKey: _text(json['title_key']),
      descriptionKey: _text(json['description_key']),
      priority: _text(json['priority'], 'normal'),
      status: _text(json['status'], 'pending'),
      sourceType: _text(json['source_type']),
      sourceId: _text(json['source_id']),
      actionRoute: _text(json['action_route']),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      dueAt: _date(json['due_at']),
      completedAt: _date(json['completed_at']),
      snoozedUntil: _date(json['snoozed_until']),
    );
  }

  FarmerDailyTask copyWith({
    String? id,
    String? status,
    DateTime? completedAt,
    DateTime? snoozedUntil,
    bool clearCompletedAt = false,
    bool clearSnoozedUntil = false,
  }) {
    return FarmerDailyTask(
      id: id ?? this.id,
      farmId: farmId,
      taskDate: taskDate,
      taskKey: taskKey,
      taskType: taskType,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
      priority: priority,
      status: status ?? this.status,
      sourceType: sourceType,
      sourceId: sourceId,
      actionRoute: actionRoute,
      metadata: metadata,
      dueAt: dueAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      snoozedUntil: clearSnoozedUntil
          ? null
          : snoozedUntil ?? this.snoozedUntil,
    );
  }

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'farm_id': farmId,
    'task_date': _dateOnly(taskDate),
    'task_key': taskKey,
    'task_type': taskType,
    'title_key': titleKey,
    'description_key': descriptionKey,
    'priority': priority,
    'status': status,
    'source_type': sourceType,
    'source_id': sourceId,
    'action_route': actionRoute,
    'metadata': metadata,
    'due_at': dueAt?.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'snoozed_until': snoozedUntil?.toUtc().toIso8601String(),
  };
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _text(Object? raw, [String fallback = '']) {
  final value = raw == null ? '' : '$raw'.trim();
  return value.isEmpty || value.toLowerCase() == 'null' ? fallback : value;
}

DateTime? _date(Object? raw) {
  final value = _text(raw);
  return value.isEmpty ? null : DateTime.tryParse(value);
}
