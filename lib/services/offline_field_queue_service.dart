import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/fpc_operating_models.dart';
import 'fpc_operating_service.dart';
import 'local_app_database.dart';
import 'network_status_service.dart';
import 'secure_app_storage.dart';

class OfflineFieldQueueItem {
  final String localId;
  final String clientUuid;
  final String status;
  final int attempts;
  final Map<String, dynamic> payload;
  final String? error;

  const OfflineFieldQueueItem({
    required this.localId,
    required this.clientUuid,
    required this.status,
    required this.attempts,
    required this.payload,
    this.error,
  });

  factory OfflineFieldQueueItem.fromJson(Map<String, dynamic> json) {
    return OfflineFieldQueueItem(
      localId: '${json['local_id'] ?? ''}',
      clientUuid: '${json['client_uuid'] ?? ''}',
      status: '${json['status'] ?? 'pending'}',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      error: json['error']?.toString(),
    );
  }

  factory OfflineFieldQueueItem.fromRecord(LocalFieldQueueRecord record) =>
      OfflineFieldQueueItem(
        localId: record.localId,
        clientUuid: record.clientUuid,
        status: record.status,
        attempts: record.attemptCount,
        payload: record.payload,
        error: record.lastError,
      );

  Map<String, dynamic> toJson() => {
    'local_id': localId,
    'client_uuid': clientUuid,
    'status': status,
    'attempts': attempts,
    'payload': payload,
    if (error != null) 'error': error,
  };
}

class OfflineFieldContext {
  final FpcMembershipContext membership;
  final List<FieldAssignmentRecord> assignments;

  const OfflineFieldContext({
    required this.membership,
    required this.assignments,
  });
}

class OfflineFieldQueueService {
  static const _legacyKey = 'pending_field_officer_visits';
  final SecureAppStorage _storage = SecureAppStorage();
  final NetworkStatusService _network = NetworkStatusService();
  final FpcOperatingService _remote = FpcOperatingService();
  LocalAppDatabase? get _db => LocalAppDatabase.maybeInstance;
  String get _userId => Supabase.instance.client.auth.currentUser?.id ?? '';
  bool _legacyMigrated = false;

  Future<List<OfflineFieldQueueItem>> load() async {
    final userId = _userId;
    if (userId.isEmpty) return const [];
    final db = _db;
    if (db == null) return _loadLegacy();
    await _migrateLegacy(db, userId);
    return (await db.loadLocalFieldQueue(
      userId,
    )).map(OfflineFieldQueueItem.fromRecord).toList(growable: false);
  }

  Future<void> enqueue(Map<String, dynamic> visit) async {
    await _enqueuePayload({...visit, '_queue_type': 'field_visit'});
  }

  Future<void> enqueueAssignmentStatus(
    FieldAssignmentRecord assignment,
    String status,
  ) async {
    await _enqueuePayload({
      '_queue_type': 'assignment_status',
      'assignment_id': assignment.id,
      'status': status,
      'server_version': assignment.serverVersion,
      'client_uuid': const Uuid().v4(),
    });
  }

  Future<void> _enqueuePayload(Map<String, dynamic> visit) async {
    final userId = _userId;
    if (userId.isEmpty) {
      throw const FpcOperatingException('Field Officer login required.');
    }
    final clientUuid = '${visit['client_uuid'] ?? const Uuid().v4()}';
    final now = DateTime.now().toUtc().toIso8601String();
    final item = OfflineFieldQueueItem(
      localId: 'field-${DateTime.now().microsecondsSinceEpoch}',
      clientUuid: clientUuid,
      status: 'pending',
      attempts: 0,
      payload: {...visit, 'client_uuid': clientUuid},
    );
    final db = _db;
    if (db == null) {
      final items = await _loadLegacy();
      items.add(item);
      await _writeLegacy(items);
      return;
    }
    await db.upsertLocalFieldQueue(
      localId: item.localId,
      officerUserId: userId,
      clientUuid: clientUuid,
      payload: item.payload,
      status: item.status,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int> sync() async {
    if (!await _network.isOnline()) return 0;
    final items = await load();
    var synced = 0;
    final db = _db;
    final legacyRemaining = <OfflineFieldQueueItem>[];
    for (final item in items) {
      final now = DateTime.now().toUtc().toIso8601String();
      if (db != null) {
        await db.markLocalFieldQueue(
          localId: item.localId,
          status: 'syncing',
          updatedAt: now,
          incrementAttempts: true,
        );
      }
      try {
        if (item.payload['_queue_type'] == 'assignment_status') {
          await _remote.updateAssignmentStatus(
            '${item.payload['assignment_id']}',
            '${item.payload['status']}',
            (item.payload['server_version'] as num?)?.toInt() ?? 1,
          );
        } else {
          final visit = Map<String, dynamic>.from(item.payload)
            ..remove('_queue_type');
          await _remote.saveFieldVisit(visit);
        }
        synced++;
        if (db != null) {
          await db.deleteLocalFieldQueue(item.localId);
        }
      } catch (error) {
        final conflict = error.toString().toLowerCase().contains('conflict');
        if (db != null) {
          await db.markLocalFieldQueue(
            localId: item.localId,
            status: conflict ? 'conflict' : 'failed',
            updatedAt: DateTime.now().toUtc().toIso8601String(),
            lastError: _shortError(error),
          );
        } else {
          legacyRemaining.add(
            OfflineFieldQueueItem(
              localId: item.localId,
              clientUuid: item.clientUuid,
              status: conflict ? 'conflict' : 'failed',
              attempts: item.attempts + 1,
              payload: item.payload,
              error: _shortError(error),
            ),
          );
        }
      }
    }
    if (db == null) {
      await _writeLegacy(legacyRemaining);
    }
    return synced;
  }

  bool shouldQueueAfterError(Object error) {
    if (error is PostgrestException || error is AuthException) return false;
    final value = '$error'.toLowerCase();
    return value.contains('socket') ||
        value.contains('network') ||
        value.contains('connection') ||
        value.contains('host lookup') ||
        value.contains('clientexception') ||
        value.contains('xmlhttprequest') ||
        value.contains('timeout');
  }

  Future<void> cacheContext(
    FpcMembershipContext membership,
    List<FieldAssignmentRecord> assignments,
  ) async {
    final userId = _userId;
    final db = _db;
    if (userId.isEmpty || db == null) return;
    await db.saveLocalFieldContext(
      officerUserId: userId,
      membership: membership.toJson(),
      assignments: assignments.map((item) => item.toJson()).toList(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<OfflineFieldContext?> loadCachedContext() async {
    final userId = _userId;
    final db = _db;
    if (userId.isEmpty || db == null) return null;
    final cached = await db.loadLocalFieldContext(userId);
    if (cached == null) return null;
    return OfflineFieldContext(
      membership: FpcMembershipContext.fromJson(cached.membership),
      assignments: cached.assignments
          .map(FieldAssignmentRecord.fromJson)
          .toList(growable: false),
    );
  }

  Future<void> _migrateLegacy(LocalAppDatabase db, String userId) async {
    if (_legacyMigrated) return;
    _legacyMigrated = true;
    final items = await _loadLegacy();
    for (final item in items) {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.upsertLocalFieldQueue(
        localId: item.localId,
        officerUserId: userId,
        clientUuid: item.clientUuid,
        payload: item.payload,
        status: item.status,
        attemptCount: item.attempts,
        createdAt: now,
        updatedAt: now,
        lastError: item.error,
      );
    }
    if (items.isNotEmpty) await _storage.remove(_legacyKey);
  }

  Future<List<OfflineFieldQueueItem>> _loadLegacy() async {
    try {
      final raw = await _storage.readString(_legacyKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                OfflineFieldQueueItem.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (error) {
      debugPrint('[OfflineFieldQueueService.load] $error');
      return [];
    }
  }

  Future<void> _writeLegacy(List<OfflineFieldQueueItem> items) async {
    if (items.isEmpty) {
      await _storage.remove(_legacyKey);
      return;
    }
    await _storage.writeString(
      _legacyKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  String _shortError(Object error) {
    final value = '$error';
    return value.length <= 240 ? value : '${value.substring(0, 240)}...';
  }
}
