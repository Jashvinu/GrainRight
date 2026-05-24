import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'secure_app_storage.dart';

class PendingSurveySubmission {
  final String localId;
  final String createdAt;
  final String expiresAt;
  final String status;
  final int attemptCount;
  final String? lastError;
  final Map<String, dynamic> parent;
  final List<Map<String, dynamic>> kharifRows;
  final List<Map<String, dynamic>> yearlyRows;
  final List<Map<String, dynamic>> practiceRows;

  const PendingSurveySubmission({
    required this.localId,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.attemptCount,
    required this.parent,
    required this.kharifRows,
    required this.yearlyRows,
    required this.practiceRows,
    this.lastError,
  });

  String get farmerName {
    final raw = parent['farmer_name']?.toString().trim();
    return raw == null || raw.isEmpty ? 'Unnamed' : raw;
  }

  String? get village {
    final raw = parent['village']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  String? get district {
    final raw = parent['district']?.toString().trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

  String? get surveyDate => parent['survey_date']?.toString();

  bool get isSyncing => status == OfflineSurveyQueueService.statusSyncing;
  bool get isFailed => status == OfflineSurveyQueueService.statusFailed;
  bool get isExpired {
    final expires = DateTime.tryParse(expiresAt);
    return expires != null && DateTime.now().toUtc().isAfter(expires);
  }

  PendingSurveySubmission copyWith({
    String? status,
    int? attemptCount,
    String? lastError,
  }) {
    return PendingSurveySubmission(
      localId: localId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError,
      parent: parent,
      kharifRows: kharifRows,
      yearlyRows: yearlyRows,
      practiceRows: practiceRows,
    );
  }

  factory PendingSurveySubmission.fromJson(Map<String, dynamic> json) {
    return PendingSurveySubmission(
      localId: json['local_id']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      expiresAt: _expiresAt(json),
      status:
          json['status']?.toString() ?? OfflineSurveyQueueService.statusPending,
      attemptCount: _toInt(json['attempt_count']),
      lastError: json['last_error']?.toString(),
      parent: _map(json['parent']),
      kharifRows: _rows(json['kharif_rows']),
      yearlyRows: _rows(json['yearly_rows']),
      practiceRows: _rows(json['practice_rows']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_id': localId,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'status': status,
      'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      'parent': parent,
      'kharif_rows': kharifRows,
      'yearly_rows': yearlyRows,
      'practice_rows': practiceRows,
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _expiresAt(Map<String, dynamic> json) {
    final raw = json['expires_at']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    return (createdAt ?? DateTime.now().toUtc())
        .add(OfflineSurveyQueueService.retention)
        .toIso8601String();
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

class OfflineSurveyQueueService {
  static const queueKey = 'pending_survey_submissions';
  static const statusPending = 'pending';
  static const statusSyncing = 'syncing';
  static const statusFailed = 'failed';
  static const retention = Duration(days: 30);

  final Connectivity _connectivity = Connectivity();
  final _secureStorage = SecureAppStorage();

  Stream<Object> get connectivityChanges =>
      _connectivity.onConnectivityChanged.map((event) => event as Object);

  Future<bool> isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasConnection(result);
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService.isOnline] $e');
      return true;
    }
  }

  Future<PendingSurveySubmission> enqueue({
    required Map<String, dynamic> parent,
    required List<Map<String, dynamic>> kharifRows,
    required List<Map<String, dynamic>> yearlyRows,
    required List<Map<String, dynamic>> practiceRows,
  }) async {
    final queue = await loadQueue();
    final now = DateTime.now().toUtc();
    final item = PendingSurveySubmission(
      localId: 'local-${now.microsecondsSinceEpoch}',
      createdAt: now.toIso8601String(),
      expiresAt: now.add(retention).toIso8601String(),
      status: statusPending,
      attemptCount: 0,
      parent: Map<String, dynamic>.from(parent),
      kharifRows: _copyRows(kharifRows),
      yearlyRows: _copyRows(yearlyRows),
      practiceRows: _copyRows(practiceRows),
    );
    await _saveQueue([item, ...queue]);
    return item;
  }

  Future<List<PendingSurveySubmission>> loadQueue() async {
    final raw = await _secureStorage.readString(queueKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final loaded = decoded
          .whereType<Map>()
          .map(
            (item) => PendingSurveySubmission.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.localId.isNotEmpty)
          .toList();
      final active = loaded
          .where((item) => item.isSyncing || !item.isExpired)
          .toList();
      if (active.length != loaded.length) {
        await _saveQueue(active);
      }
      return active;
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService.loadQueue] $e');
      return const [];
    }
  }

  Future<void> remove(String localId) async {
    final queue = await loadQueue();
    await _saveQueue(queue.where((item) => item.localId != localId).toList());
  }

  Future<void> markSyncing(String localId) async {
    await _update(localId, (item) {
      return item.copyWith(
        status: statusSyncing,
        attemptCount: item.attemptCount + 1,
      );
    });
  }

  Future<void> markFailed(String localId, Object error) async {
    await _update(localId, (item) {
      return item.copyWith(status: statusFailed, lastError: _shortError(error));
    });
  }

  Future<void> markPending(String localId) async {
    await _update(localId, (item) {
      return item.copyWith(status: statusPending);
    });
  }

  bool shouldQueueAfterError(Object error) {
    if (error is PostgrestException || error is AuthException) return false;
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('timeout');
  }

  bool _hasConnection(Object? result) {
    if (result is Iterable) {
      return result.any(_isConnectedResult);
    }
    return _isConnectedResult(result);
  }

  bool _isConnectedResult(Object? result) {
    return result is ConnectivityResult && result != ConnectivityResult.none;
  }

  Future<void> _update(
    String localId,
    PendingSurveySubmission Function(PendingSurveySubmission item) update,
  ) async {
    final queue = await loadQueue();
    await _saveQueue(
      queue
          .map((item) => item.localId == localId ? update(item) : item)
          .toList(),
    );
  }

  Future<void> _saveQueue(List<PendingSurveySubmission> queue) async {
    await _secureStorage.writeString(
      queueKey,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }

  List<Map<String, dynamic>> _copyRows(List<Map<String, dynamic>> rows) {
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String _shortError(Object error) {
    final text = error.toString();
    return text.length <= 240 ? text : '${text.substring(0, 240)}...';
  }
}
