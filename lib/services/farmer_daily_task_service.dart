import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/farmer_daily_task.dart';

class FarmerDailyTaskService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<FarmerDailyTask>> syncDecisionTasks({
    required String farmId,
    required String growthStage,
    required double? waterStress,
    required double? soilMoisture,
    required double rainMm,
    required double diseaseRisk,
    required List<FarmerDailyTask> fallback,
  }) async {
    try {
      final data = await _invoke({
        'action': 'sync',
        'farmId': farmId,
        'context': {
          'growthStage': growthStage,
          'waterStress': waterStress,
          'soilMoisture': soilMoisture,
          'rainMm': rainMm,
          'diseaseRisk': diseaseRisk,
        },
      });
      final rows = data['tasks'];
      if (rows is! List) return fallback;
      return rows
          .whereType<Map>()
          .map(
            (row) => FarmerDailyTask.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false);
    } catch (_) {
      return _syncDerivedTasksDirect(farmId: farmId, derived: fallback);
    }
  }

  Future<List<FarmerDailyTask>> _syncDerivedTasksDirect({
    required String farmId,
    required List<FarmerDailyTask> derived,
  }) async {
    final userId = _client.auth.currentUser?.id ?? '';
    if (userId.isEmpty || farmId.isEmpty || derived.isEmpty) return derived;
    final day = _dateOnly(DateTime.now());
    final existingRows = await _client
        .from('farmer_daily_tasks')
        .select('*')
        .eq('user_id', userId)
        .eq('farm_id', farmId)
        .eq('task_date', day);
    final existing = <String, FarmerDailyTask>{
      for (final row in (existingRows as List).whereType<Map>())
        '${row['task_key'] ?? ''}': FarmerDailyTask.fromJson(
          Map<String, dynamic>.from(row),
        ),
    };
    final payload = derived
        .map((task) {
          final saved = existing[task.taskKey];
          return task
              .copyWith(
                id: saved?.id,
                status: saved?.status,
                completedAt: saved?.completedAt,
                snoozedUntil: saved?.snoozedUntil,
              )
              .toInsertJson(userId);
        })
        .toList(growable: false);
    final rows = await _client
        .from('farmer_daily_tasks')
        .upsert(payload, onConflict: 'user_id,farm_id,task_date,task_key')
        .select('*');
    return (rows as List)
        .whereType<Map>()
        .map((row) => FarmerDailyTask.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> setStatus(
    FarmerDailyTask task, {
    required String status,
    DateTime? snoozedUntil,
  }) async {
    if (task.id.isEmpty) return;
    try {
      await _invoke({
        'action': 'update_status',
        'taskId': task.id,
        'status': status,
        'snoozedUntil': snoozedUntil?.toUtc().toIso8601String(),
      });
    } catch (_) {
      await _client
          .from('farmer_daily_tasks')
          .update({
            'status': status,
            'completed_at': status == 'done'
                ? DateTime.now().toUtc().toIso8601String()
                : null,
            'snoozed_until': snoozedUntil?.toUtc().toIso8601String(),
          })
          .eq('id', task.id);
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final response = await _client.functions.invoke(
      'farmer-daily-tasks',
      headers: _authHeaders(),
      body: body,
    );
    final data = _responseMap(response.data);
    if (data['success'] == false) {
      throw Exception('${data['error'] ?? 'Daily task request failed.'}');
    }
    return data;
  }

  Map<String, String>? _authHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _responseMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
