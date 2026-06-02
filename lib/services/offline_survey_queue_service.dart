import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'local_app_database.dart';
import 'network_status_service.dart';
import 'secure_app_storage.dart';

class PendingSurveySubmission {
  final String localId;
  final String? remoteId;
  final String clientUuid;
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
    required this.clientUuid,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.attemptCount,
    required this.parent,
    required this.kharifRows,
    required this.yearlyRows,
    required this.practiceRows,
    this.remoteId,
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
    String? remoteId,
    String? status,
    int? attemptCount,
    String? lastError,
  }) {
    return PendingSurveySubmission(
      localId: localId,
      remoteId: remoteId ?? this.remoteId,
      clientUuid: clientUuid,
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
    final parent = _map(json['parent']);
    final clientUuid =
        json['client_uuid']?.toString() ??
        parent['client_uuid']?.toString() ??
        const Uuid().v4();
    parent['client_uuid'] = clientUuid;
    parent['total_cultivation_cost'] = _toNumericOrZero(
      parent['total_cultivation_cost'],
    );
    return PendingSurveySubmission(
      localId: json['local_id']?.toString() ?? '',
      remoteId: json['remote_id']?.toString(),
      clientUuid: clientUuid,
      createdAt: json['created_at']?.toString() ?? '',
      expiresAt: _expiresAt(json),
      status:
          json['status']?.toString() ?? OfflineSurveyQueueService.statusPending,
      attemptCount: _toInt(json['attempt_count']),
      lastError: json['last_error']?.toString(),
      parent: parent,
      kharifRows: _rows(json['kharif_rows']),
      yearlyRows: _rows(json['yearly_rows']),
      practiceRows: _rows(json['practice_rows']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_id': localId,
      if (remoteId != null) 'remote_id': remoteId,
      'client_uuid': clientUuid,
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

  static double _toNumericOrZero(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
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
  static const statusSynced = 'synced';
  static const retention = Duration(days: 30);

  final Connectivity _connectivity = Connectivity();
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();
  LocalAppDatabase? get _db => LocalAppDatabase.maybeInstance;
  bool _legacyMigrationChecked = false;

  Stream<Object> get connectivityChanges =>
      _connectivity.onConnectivityChanged.map((event) => event as Object);

  Future<bool> isOnline() async {
    try {
      return _networkStatusService.isOnline();
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService.isOnline] $e');
      return false;
    }
  }

  Future<PendingSurveySubmission> enqueue({
    required Map<String, dynamic> parent,
    required List<Map<String, dynamic>> kharifRows,
    required List<Map<String, dynamic>> yearlyRows,
    required List<Map<String, dynamic>> practiceRows,
  }) async {
    final now = DateTime.now().toUtc();
    final parentPayload = Map<String, dynamic>.from(parent);
    final clientUuid =
        parentPayload['client_uuid']?.toString().trim().isNotEmpty == true
        ? parentPayload['client_uuid'].toString()
        : const Uuid().v4();
    parentPayload['client_uuid'] = clientUuid;
    parentPayload['total_cultivation_cost'] =
        PendingSurveySubmission._toNumericOrZero(
          parentPayload['total_cultivation_cost'],
        );
    final item = PendingSurveySubmission(
      localId: 'local-${now.microsecondsSinceEpoch}',
      clientUuid: clientUuid,
      createdAt: now.toIso8601String(),
      expiresAt: now.add(retention).toIso8601String(),
      status: statusPending,
      attemptCount: 0,
      parent: parentPayload,
      kharifRows: _copyRows(kharifRows),
      yearlyRows: _copyRows(yearlyRows),
      practiceRows: _copyRows(practiceRows),
    );
    await _saveItem(item);
    return item;
  }

  Future<List<PendingSurveySubmission>> loadQueue() async {
    final db = _db;
    if (db == null) return _loadLegacyQueue();

    await _migrateLegacyQueue(db);
    try {
      final loaded = await db.loadLocalSurveys();
      final active = <PendingSurveySubmission>[];
      for (final record in loaded) {
        final item = _fromRecord(record);
        if (!item.isSyncing && item.isExpired) {
          await db.deleteLocalSurvey(item.localId);
          continue;
        }
        active.add(item);
      }
      return active;
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService.loadQueue.db] $e');
      return const [];
    }
  }

  Future<void> _migrateLegacyQueue(LocalAppDatabase db) async {
    if (_legacyMigrationChecked) return;
    _legacyMigrationChecked = true;
    final raw = await _secureStorage.readString(queueKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = decoded
          .whereType<Map>()
          .map(
            (item) => PendingSurveySubmission.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.localId.isNotEmpty)
          .toList();
      for (final item in loaded.where((item) => !item.isExpired)) {
        await _saveItemInDatabase(db, item);
      }
      await _secureStorage.remove(queueKey);
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService._migrateLegacyQueue] $e');
    }
  }

  Future<void> remove(String localId) async {
    final db = _db;
    if (db == null) {
      await _removeLegacyItem(localId);
      return;
    }
    await db.deleteLocalSurvey(localId);
  }

  Future<void> markSyncing(String localId) async {
    final db = _db;
    if (db == null) {
      await _updateLegacyItem(localId, (item) {
        return _copySubmission(
          item,
          status: statusSyncing,
          attemptCount: item.attemptCount + 1,
          clearLastError: true,
        );
      });
      return;
    }
    await db.markSurveySyncing(
      localId,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> markFailed(String localId, Object error) async {
    final db = _db;
    if (db == null) {
      await _updateLegacyItem(localId, (item) {
        return _copySubmission(
          item,
          status: statusFailed,
          lastError: _shortError(error),
        );
      });
      return;
    }
    await db.markSurveyFailed(
      localId: localId,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      lastError: _shortError(error),
    );
  }

  Future<void> markPending(String localId) async {
    final db = _db;
    if (db == null) {
      await _updateLegacyItem(localId, (item) {
        return _copySubmission(
          item,
          status: statusPending,
          clearLastError: true,
        );
      });
      return;
    }
    await db.markSurveyPending(
      localId,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> markSynced(String localId, String remoteId) async {
    final db = _db;
    if (db == null) {
      await _removeLegacyItem(localId);
      return;
    }
    await db.markSurveySynced(
      localId: localId,
      remoteId: remoteId,
      syncedAt: DateTime.now().toUtc().toIso8601String(),
    );
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

  PendingSurveySubmission _fromRecord(LocalSurveyRecord record) {
    final parent = Map<String, dynamic>.from(record.parent);
    parent['total_cultivation_cost'] =
        PendingSurveySubmission._toNumericOrZero(
          parent['total_cultivation_cost'],
        );
    return PendingSurveySubmission(
      localId: record.localId,
      remoteId: record.remoteId,
      clientUuid: record.clientUuid,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
      status: record.status,
      attemptCount: record.attemptCount,
      lastError: record.lastError,
      parent: parent,
      kharifRows: record.kharifRows,
      yearlyRows: record.yearlyRows,
      practiceRows: record.practiceRows,
    );
  }

  Future<void> _saveItem(PendingSurveySubmission item) async {
    final db = _db;
    if (db == null) {
      await _upsertLegacyItem(item);
      return;
    }
    await _saveItemInDatabase(db, item);
  }

  Future<void> _saveItemInDatabase(
    LocalAppDatabase db,
    PendingSurveySubmission item,
  ) async {
    await db.upsertLocalSurvey(
      localId: item.localId,
      remoteId: item.remoteId,
      clientUuid: item.clientUuid,
      userId: item.parent['user_id']?.toString(),
      parent: item.parent,
      kharifRows: item.kharifRows,
      yearlyRows: item.yearlyRows,
      practiceRows: item.practiceRows,
      status: item.status,
      attemptCount: item.attemptCount,
      createdAt: item.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      expiresAt: item.expiresAt,
      lastError: item.lastError,
    );
  }

  Future<List<PendingSurveySubmission>> _loadLegacyQueue() async {
    try {
      final loaded = await _readLegacyQueue();
      final active = loaded
          .where((item) => item.status != statusSynced && !item.isExpired)
          .toList();
      if (active.length != loaded.length) {
        await _writeLegacyQueue(active);
      }
      return active;
    } catch (e) {
      debugPrint('[OfflineSurveyQueueService.loadQueue.legacy] $e');
      return const [];
    }
  }

  Future<List<PendingSurveySubmission>> _readLegacyQueue() async {
    final raw = await _secureStorage.readString(queueKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              PendingSurveySubmission.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.localId.isNotEmpty)
        .toList();
  }

  Future<void> _writeLegacyQueue(List<PendingSurveySubmission> items) async {
    if (items.isEmpty) {
      await _secureStorage.remove(queueKey);
      return;
    }
    await _secureStorage.writeString(
      queueKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _upsertLegacyItem(PendingSurveySubmission item) async {
    final items = await _readLegacyQueue();
    final index = items.indexWhere(
      (existing) => existing.localId == item.localId,
    );
    if (index == -1) {
      items.add(item);
    } else {
      items[index] = item;
    }
    await _writeLegacyQueue(
      items
          .where((queued) => queued.status != statusSynced && !queued.isExpired)
          .toList(),
    );
  }

  Future<void> _removeLegacyItem(String localId) async {
    final items = await _readLegacyQueue();
    items.removeWhere((item) => item.localId == localId);
    await _writeLegacyQueue(items);
  }

  Future<void> _updateLegacyItem(
    String localId,
    PendingSurveySubmission Function(PendingSurveySubmission item) update,
  ) async {
    final items = await _readLegacyQueue();
    final index = items.indexWhere((item) => item.localId == localId);
    if (index == -1) return;
    items[index] = update(items[index]);
    await _writeLegacyQueue(
      items
          .where((queued) => queued.status != statusSynced && !queued.isExpired)
          .toList(),
    );
  }

  PendingSurveySubmission _copySubmission(
    PendingSurveySubmission item, {
    String? status,
    int? attemptCount,
    String? lastError,
    bool clearLastError = false,
  }) {
    return PendingSurveySubmission(
      localId: item.localId,
      remoteId: item.remoteId,
      clientUuid: item.clientUuid,
      createdAt: item.createdAt,
      expiresAt: item.expiresAt,
      status: status ?? item.status,
      attemptCount: attemptCount ?? item.attemptCount,
      lastError: clearLastError ? null : lastError ?? item.lastError,
      parent: item.parent,
      kharifRows: item.kharifRows,
      yearlyRows: item.yearlyRows,
      practiceRows: item.practiceRows,
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
