import 'dart:convert';

import 'package:drift/drift.dart';

import 'local_database_connection.dart';

class LocalSurveyRecord {
  final String localId;
  final String? remoteId;
  final String clientUuid;
  final String? userId;
  final String status;
  final int attemptCount;
  final String createdAt;
  final String updatedAt;
  final String expiresAt;
  final String? lastAttemptAt;
  final String? syncedAt;
  final String? lastError;
  final Map<String, dynamic> parent;
  final List<Map<String, dynamic>> kharifRows;
  final List<Map<String, dynamic>> yearlyRows;
  final List<Map<String, dynamic>> practiceRows;

  const LocalSurveyRecord({
    required this.localId,
    required this.clientUuid,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.parent,
    required this.kharifRows,
    required this.yearlyRows,
    required this.practiceRows,
    this.remoteId,
    this.userId,
    this.lastAttemptAt,
    this.syncedAt,
    this.lastError,
  });
}

class OfflineMapRegionRecord {
  final String regionId;
  final String label;
  final double centerLat;
  final double centerLng;
  final double radiusKm;
  final int minZoom;
  final int maxZoom;
  final String status;
  final int tileCount;
  final int downloadedTileCount;
  final int sizeBytes;
  final String sourceId;
  final String? downloadedAt;
  final String updatedAt;
  final String? lastError;

  const OfflineMapRegionRecord({
    required this.regionId,
    required this.label,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
    required this.minZoom,
    required this.maxZoom,
    required this.status,
    required this.tileCount,
    required this.downloadedTileCount,
    required this.sizeBytes,
    required this.sourceId,
    required this.updatedAt,
    this.downloadedAt,
    this.lastError,
  });

  double get progress {
    if (tileCount <= 0) return status == 'ready' ? 1 : 0;
    return downloadedTileCount / tileCount;
  }
}

class CachedTileRecord {
  final Uint8List bytes;
  final String contentType;

  const CachedTileRecord({required this.bytes, required this.contentType});
}

class FormConfigCacheRecord {
  final String cacheKey;
  final List<dynamic> payload;
  final String? language;
  final Map<String, dynamic> metadata;
  final String fetchedAt;

  const FormConfigCacheRecord({
    required this.cacheKey,
    required this.payload,
    required this.metadata,
    required this.fetchedAt,
    this.language,
  });
}

class LocalAppDatabase extends GeneratedDatabase {
  static final LocalAppDatabase instance = LocalAppDatabase(
    openLocalDatabaseConnection(),
  );

  LocalAppDatabase(super.executor);

  bool _initialized = false;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_surveys (
        local_id TEXT PRIMARY KEY,
        remote_id TEXT,
        client_uuid TEXT NOT NULL UNIQUE,
        user_id TEXT,
        parent_payload TEXT NOT NULL,
        kharif_payload TEXT NOT NULL,
        yearly_payload TEXT NOT NULL,
        practice_payload TEXT NOT NULL,
        status TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        last_attempt_at TEXT,
        synced_at TEXT,
        last_error TEXT
      );
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_surveys_status ON local_surveys(status);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_surveys_user_id ON local_surveys(user_id);',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS form_config_cache (
        cache_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        language TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        fetched_at TEXT NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_map_regions (
        region_id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        center_lat REAL NOT NULL,
        center_lng REAL NOT NULL,
        radius_km REAL NOT NULL,
        min_zoom INTEGER NOT NULL,
        max_zoom INTEGER NOT NULL,
        status TEXT NOT NULL,
        downloaded_at TEXT,
        updated_at TEXT NOT NULL,
        tile_count INTEGER NOT NULL DEFAULT 0,
        downloaded_tile_count INTEGER NOT NULL DEFAULT 0,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        source_id TEXT NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_tile_cache (
        source_id TEXT NOT NULL,
        z INTEGER NOT NULL,
        x INTEGER NOT NULL,
        y INTEGER NOT NULL,
        content_type TEXT NOT NULL,
        bytes BLOB NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (source_id, z, x, y)
      );
    ''');
    _initialized = true;
  }

  Future<void> upsertLocalSurvey({
    required String localId,
    required String clientUuid,
    required Map<String, dynamic> parent,
    required List<Map<String, dynamic>> kharifRows,
    required List<Map<String, dynamic>> yearlyRows,
    required List<Map<String, dynamic>> practiceRows,
    required String status,
    required int attemptCount,
    required String createdAt,
    required String updatedAt,
    required String expiresAt,
    String? remoteId,
    String? userId,
    String? lastAttemptAt,
    String? syncedAt,
    String? lastError,
  }) async {
    await ensureInitialized();
    await customUpdate(
      '''
      INSERT INTO local_surveys (
        local_id, remote_id, client_uuid, user_id, parent_payload,
        kharif_payload, yearly_payload, practice_payload, status,
        attempt_count, created_at, updated_at, expires_at, last_attempt_at,
        synced_at, last_error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(local_id) DO UPDATE SET
        remote_id = excluded.remote_id,
        client_uuid = excluded.client_uuid,
        user_id = excluded.user_id,
        parent_payload = excluded.parent_payload,
        kharif_payload = excluded.kharif_payload,
        yearly_payload = excluded.yearly_payload,
        practice_payload = excluded.practice_payload,
        status = excluded.status,
        attempt_count = excluded.attempt_count,
        updated_at = excluded.updated_at,
        expires_at = excluded.expires_at,
        last_attempt_at = excluded.last_attempt_at,
        synced_at = excluded.synced_at,
        last_error = excluded.last_error
      ''',
      variables: [
        Variable.withString(localId),
        Variable(remoteId),
        Variable.withString(clientUuid),
        Variable(userId),
        Variable.withString(jsonEncode(parent)),
        Variable.withString(jsonEncode(kharifRows)),
        Variable.withString(jsonEncode(yearlyRows)),
        Variable.withString(jsonEncode(practiceRows)),
        Variable.withString(status),
        Variable.withInt(attemptCount),
        Variable.withString(createdAt),
        Variable.withString(updatedAt),
        Variable.withString(expiresAt),
        Variable(lastAttemptAt),
        Variable(syncedAt),
        Variable(lastError),
      ],
    );
  }

  Future<List<LocalSurveyRecord>> loadLocalSurveys({
    bool includeSynced = false,
  }) async {
    await ensureInitialized();
    final rows = await customSelect(
      includeSynced
          ? 'SELECT * FROM local_surveys ORDER BY created_at DESC'
          : "SELECT * FROM local_surveys WHERE status != 'synced' ORDER BY created_at DESC",
    ).get();
    return rows.map(_surveyFromRow).toList();
  }

  Future<void> deleteLocalSurvey(String localId) async {
    await ensureInitialized();
    await customUpdate(
      'DELETE FROM local_surveys WHERE local_id = ?',
      variables: [Variable.withString(localId)],
    );
  }

  Future<void> markSurveySyncing(String localId, String updatedAt) async {
    await ensureInitialized();
    await customUpdate(
      '''
      UPDATE local_surveys
      SET status = 'syncing',
          attempt_count = attempt_count + 1,
          updated_at = ?,
          last_attempt_at = ?,
          last_error = NULL
      WHERE local_id = ?
      ''',
      variables: [
        Variable.withString(updatedAt),
        Variable.withString(updatedAt),
        Variable.withString(localId),
      ],
    );
  }

  Future<void> markSurveyFailed({
    required String localId,
    required String updatedAt,
    required String lastError,
  }) async {
    await ensureInitialized();
    await customUpdate(
      '''
      UPDATE local_surveys
      SET status = 'failed', updated_at = ?, last_error = ?
      WHERE local_id = ?
      ''',
      variables: [
        Variable.withString(updatedAt),
        Variable.withString(lastError),
        Variable.withString(localId),
      ],
    );
  }

  Future<void> markSurveyPending(String localId, String updatedAt) async {
    await ensureInitialized();
    await customUpdate(
      '''
      UPDATE local_surveys
      SET status = 'pending', updated_at = ?, last_error = NULL
      WHERE local_id = ?
      ''',
      variables: [Variable.withString(updatedAt), Variable.withString(localId)],
    );
  }

  Future<void> markSurveySynced({
    required String localId,
    required String remoteId,
    required String syncedAt,
  }) async {
    await ensureInitialized();
    await customUpdate(
      '''
      UPDATE local_surveys
      SET status = 'synced',
          remote_id = ?,
          synced_at = ?,
          updated_at = ?,
          last_error = NULL
      WHERE local_id = ?
      ''',
      variables: [
        Variable.withString(remoteId),
        Variable.withString(syncedAt),
        Variable.withString(syncedAt),
        Variable.withString(localId),
      ],
    );
  }

  Future<void> cacheFormList({
    required String key,
    required List data,
    String? language,
    Map<String, dynamic> metadata = const {},
  }) async {
    await ensureInitialized();
    final now = DateTime.now().toUtc().toIso8601String();
    await customUpdate(
      '''
      INSERT INTO form_config_cache (
        cache_key, payload_json, language, metadata_json, fetched_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(cache_key) DO UPDATE SET
        payload_json = excluded.payload_json,
        language = excluded.language,
        metadata_json = excluded.metadata_json,
        fetched_at = excluded.fetched_at
      ''',
      variables: [
        Variable.withString(key),
        Variable.withString(jsonEncode(data)),
        Variable(language),
        Variable.withString(jsonEncode(metadata)),
        Variable.withString(now),
      ],
    );
  }

  Future<FormConfigCacheRecord?> readFormList(String key) async {
    await ensureInitialized();
    final rows = await customSelect(
      'SELECT * FROM form_config_cache WHERE cache_key = ? LIMIT 1',
      variables: [Variable.withString(key)],
    ).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    final payload = jsonDecode(row.read<String>('payload_json'));
    final metadata = jsonDecode(row.read<String>('metadata_json'));
    return FormConfigCacheRecord(
      cacheKey: row.read<String>('cache_key'),
      payload: payload is List ? payload : const [],
      language: row.readNullable<String>('language'),
      metadata: metadata is Map
          ? Map<String, dynamic>.from(metadata)
          : const <String, dynamic>{},
      fetchedAt: row.read<String>('fetched_at'),
    );
  }

  Future<void> upsertOfflineMapRegion({
    required OfflineMapRegionRecord region,
  }) async {
    await ensureInitialized();
    await customUpdate(
      '''
      INSERT INTO offline_map_regions (
        region_id, label, center_lat, center_lng, radius_km, min_zoom,
        max_zoom, status, downloaded_at, updated_at, tile_count,
        downloaded_tile_count, size_bytes, last_error, source_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(region_id) DO UPDATE SET
        label = excluded.label,
        center_lat = excluded.center_lat,
        center_lng = excluded.center_lng,
        radius_km = excluded.radius_km,
        min_zoom = excluded.min_zoom,
        max_zoom = excluded.max_zoom,
        status = excluded.status,
        downloaded_at = excluded.downloaded_at,
        updated_at = excluded.updated_at,
        tile_count = excluded.tile_count,
        downloaded_tile_count = excluded.downloaded_tile_count,
        size_bytes = excluded.size_bytes,
        last_error = excluded.last_error,
        source_id = excluded.source_id
      ''',
      variables: [
        Variable.withString(region.regionId),
        Variable.withString(region.label),
        Variable.withReal(region.centerLat),
        Variable.withReal(region.centerLng),
        Variable.withReal(region.radiusKm),
        Variable.withInt(region.minZoom),
        Variable.withInt(region.maxZoom),
        Variable.withString(region.status),
        Variable(region.downloadedAt),
        Variable.withString(region.updatedAt),
        Variable.withInt(region.tileCount),
        Variable.withInt(region.downloadedTileCount),
        Variable.withInt(region.sizeBytes),
        Variable(region.lastError),
        Variable.withString(region.sourceId),
      ],
    );
  }

  Future<List<OfflineMapRegionRecord>> loadOfflineMapRegions() async {
    await ensureInitialized();
    final rows = await customSelect(
      'SELECT * FROM offline_map_regions ORDER BY updated_at DESC',
    ).get();
    return rows.map(_mapRegionFromRow).toList();
  }

  Future<void> deleteOfflineMapRegion(String regionId, String sourceId) async {
    await ensureInitialized();
    await transaction(() async {
      await customUpdate(
        'DELETE FROM offline_map_regions WHERE region_id = ?',
        variables: [Variable.withString(regionId)],
      );
      await customUpdate(
        'DELETE FROM offline_tile_cache WHERE source_id = ?',
        variables: [Variable.withString(sourceId)],
      );
    });
  }

  Future<void> writeTile({
    required String sourceId,
    required int z,
    required int x,
    required int y,
    required Uint8List bytes,
    String contentType = 'image/png',
  }) async {
    await ensureInitialized();
    final now = DateTime.now().toUtc().toIso8601String();
    await customUpdate(
      '''
      INSERT INTO offline_tile_cache (
        source_id, z, x, y, content_type, bytes, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_id, z, x, y) DO UPDATE SET
        content_type = excluded.content_type,
        bytes = excluded.bytes,
        updated_at = excluded.updated_at
      ''',
      variables: [
        Variable.withString(sourceId),
        Variable.withInt(z),
        Variable.withInt(x),
        Variable.withInt(y),
        Variable.withString(contentType),
        Variable.withBlob(bytes),
        Variable.withString(now),
        Variable.withString(now),
      ],
    );
  }

  Future<CachedTileRecord?> readTile({
    required String sourceId,
    required int z,
    required int x,
    required int y,
  }) async {
    await ensureInitialized();
    final rows = await customSelect(
      '''
      SELECT bytes, content_type FROM offline_tile_cache
      WHERE source_id = ? AND z = ? AND x = ? AND y = ?
      LIMIT 1
      ''',
      variables: [
        Variable.withString(sourceId),
        Variable.withInt(z),
        Variable.withInt(x),
        Variable.withInt(y),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return CachedTileRecord(
      bytes: rows.first.read<Uint8List>('bytes'),
      contentType: rows.first.read<String>('content_type'),
    );
  }

  Future<void> deleteTilesForSource(String sourceId) async {
    await ensureInitialized();
    await customUpdate(
      'DELETE FROM offline_tile_cache WHERE source_id = ?',
      variables: [Variable.withString(sourceId)],
    );
  }

  LocalSurveyRecord _surveyFromRow(QueryRow row) {
    return LocalSurveyRecord(
      localId: row.read<String>('local_id'),
      remoteId: row.readNullable<String>('remote_id'),
      clientUuid: row.read<String>('client_uuid'),
      userId: row.readNullable<String>('user_id'),
      status: row.read<String>('status'),
      attemptCount: row.read<int>('attempt_count'),
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
      expiresAt: row.read<String>('expires_at'),
      lastAttemptAt: row.readNullable<String>('last_attempt_at'),
      syncedAt: row.readNullable<String>('synced_at'),
      lastError: row.readNullable<String>('last_error'),
      parent: _decodeMap(row.read<String>('parent_payload')),
      kharifRows: _decodeRows(row.read<String>('kharif_payload')),
      yearlyRows: _decodeRows(row.read<String>('yearly_payload')),
      practiceRows: _decodeRows(row.read<String>('practice_payload')),
    );
  }

  OfflineMapRegionRecord _mapRegionFromRow(QueryRow row) {
    return OfflineMapRegionRecord(
      regionId: row.read<String>('region_id'),
      label: row.read<String>('label'),
      centerLat: row.read<double>('center_lat'),
      centerLng: row.read<double>('center_lng'),
      radiusKm: row.read<double>('radius_km'),
      minZoom: row.read<int>('min_zoom'),
      maxZoom: row.read<int>('max_zoom'),
      status: row.read<String>('status'),
      downloadedAt: row.readNullable<String>('downloaded_at'),
      updatedAt: row.read<String>('updated_at'),
      tileCount: row.read<int>('tile_count'),
      downloadedTileCount: row.read<int>('downloaded_tile_count'),
      sizeBytes: row.read<int>('size_bytes'),
      lastError: row.readNullable<String>('last_error'),
      sourceId: row.read<String>('source_id'),
    );
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  List<Map<String, dynamic>> _decodeRows(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
