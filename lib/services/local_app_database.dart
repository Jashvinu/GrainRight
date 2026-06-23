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

class LocalFarmerProfileRecord {
  final String phone;
  final String farmerId;
  final String farmerName;
  final String userId;
  final String defaultLocation;
  final String preferredLanguage;
  final bool profileComplete;
  final String lastVerifiedAt;
  final String syncedAt;

  const LocalFarmerProfileRecord({
    required this.phone,
    required this.farmerId,
    required this.farmerName,
    required this.userId,
    required this.defaultLocation,
    required this.preferredLanguage,
    required this.profileComplete,
    required this.lastVerifiedAt,
    required this.syncedAt,
  });
}

class LocalFarmCacheRecord {
  final String farmId;
  final String? userId;
  final String? farmerPhone;
  final String? farmerIdValue;
  final String name;
  final Map<String, dynamic> geometry;
  final Map<String, dynamic>? bounds;
  final double? areaHectares;
  final double? areaAcres;
  final String? crop;
  final String? variety;
  final String? previousCrop;
  final String? season;
  final String? irrigation;
  final String? soilType;
  final String? ownershipType;
  final String? seedSource;
  final String? harvestIntent;
  final String? sowingDate;
  final String? currentStatus;
  final String? currentStatusStage;
  final String? currentStatusUpdatedAt;
  final String createdAt;
  final String updatedAt;
  final bool selected;

  const LocalFarmCacheRecord({
    required this.farmId,
    required this.name,
    required this.geometry,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.farmerPhone,
    this.farmerIdValue,
    this.bounds,
    this.areaHectares,
    this.areaAcres,
    this.crop,
    this.variety,
    this.previousCrop,
    this.season,
    this.irrigation,
    this.soilType,
    this.ownershipType,
    this.seedSource,
    this.harvestIntent,
    this.sowingDate,
    this.currentStatus,
    this.currentStatusStage,
    this.currentStatusUpdatedAt,
    this.selected = false,
  });
}

class LocalAppDatabase extends GeneratedDatabase {
  static bool get isSupported => isLocalDatabaseSupported();

  static LocalAppDatabase? get maybeInstance {
    if (!isSupported) return null;
    return instance;
  }

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
      CREATE TABLE IF NOT EXISTS local_farmer_profile_cache (
        phone TEXT PRIMARY KEY,
        farmer_id TEXT NOT NULL,
        farmer_name TEXT NOT NULL,
        user_id TEXT NOT NULL DEFAULT '',
        default_location TEXT NOT NULL DEFAULT '',
        preferred_language TEXT NOT NULL DEFAULT 'en',
        profile_complete INTEGER NOT NULL DEFAULT 0,
        last_verified_at TEXT NOT NULL,
        synced_at TEXT NOT NULL
      );
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_farmer_profile_farmer_id ON local_farmer_profile_cache(farmer_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_farmer_profile_user_id ON local_farmer_profile_cache(user_id);',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS local_farms_cache (
        farm_id TEXT PRIMARY KEY,
        user_id TEXT,
        farmer_phone TEXT,
        farmer_id TEXT,
        name TEXT NOT NULL,
        geometry_json TEXT NOT NULL,
        bounds_json TEXT,
        area_hectares REAL,
        area_acres REAL,
        crop TEXT,
        variety TEXT,
        previous_crop TEXT,
        season TEXT,
        irrigation TEXT,
        soil_type TEXT,
        ownership_type TEXT,
        seed_source TEXT,
        harvest_intent TEXT,
        sowing_date TEXT,
        current_status TEXT,
        current_status_stage TEXT,
        current_status_updated_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        selected INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_farms_farmer ON local_farms_cache(farmer_phone, farmer_id);',
    );
    try {
      await customStatement(
        'ALTER TABLE local_farms_cache ADD COLUMN sowing_date TEXT;',
      );
    } catch (_) {
      // Existing caches already have this column.
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_farms_user_id ON local_farms_cache(user_id);',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_local_farms_selected ON local_farms_cache(farmer_phone, selected);',
    );
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

  Future<void> upsertFarmerProfileCache({
    required LocalFarmerProfileRecord record,
  }) async {
    await ensureInitialized();
    await customUpdate(
      '''
      INSERT INTO local_farmer_profile_cache (
        phone, farmer_id, farmer_name, user_id, default_location,
        preferred_language, profile_complete, last_verified_at, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(phone) DO UPDATE SET
        farmer_id = excluded.farmer_id,
        farmer_name = excluded.farmer_name,
        user_id = excluded.user_id,
        default_location = excluded.default_location,
        preferred_language = excluded.preferred_language,
        profile_complete = excluded.profile_complete,
        last_verified_at = excluded.last_verified_at,
        synced_at = excluded.synced_at
      ''',
      variables: [
        Variable.withString(_normalizePhone(record.phone)),
        Variable.withString(record.farmerId),
        Variable.withString(record.farmerName),
        Variable.withString(record.userId),
        Variable.withString(record.defaultLocation),
        Variable.withString(record.preferredLanguage),
        Variable.withInt(record.profileComplete ? 1 : 0),
        Variable.withString(record.lastVerifiedAt),
        Variable.withString(record.syncedAt),
      ],
    );
  }

  Future<LocalFarmerProfileRecord?> readFarmerProfileByPhone(
    String phone,
  ) async {
    await ensureInitialized();
    final digits = _normalizePhone(phone);
    if (digits.isEmpty) return null;
    final rows = await customSelect(
      '''
      SELECT * FROM local_farmer_profile_cache
      WHERE phone = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(digits)],
    ).get();
    if (rows.isEmpty) return null;
    return _farmerProfileFromRow(rows.first);
  }

  Future<void> replaceFarmCacheForFarmer({
    required String farmerPhone,
    required String? farmerId,
    required List<LocalFarmCacheRecord> farms,
  }) async {
    await ensureInitialized();
    final digits = _normalizePhone(farmerPhone);
    if (digits.isEmpty) return;
    await transaction(() async {
      await customUpdate(
        'DELETE FROM local_farms_cache WHERE farmer_phone = ?',
        variables: [Variable.withString(digits)],
      );
      for (final farm in farms) {
        final currentStatusUpdatedAt =
            farm.currentStatusUpdatedAt ??
            ((farm.currentStatus?.trim().isNotEmpty == true ||
                    farm.currentStatusStage?.trim().isNotEmpty == true)
                ? farm.updatedAt
                : null);
        await customUpdate(
          '''
          INSERT INTO local_farms_cache (
            farm_id, user_id, farmer_phone, farmer_id, name, geometry_json,
            bounds_json, area_hectares, area_acres, crop, variety,
            previous_crop, season, irrigation, soil_type, ownership_type,
            seed_source, harvest_intent, sowing_date, current_status,
            current_status_stage, current_status_updated_at, created_at,
            updated_at, selected
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(farm_id) DO UPDATE SET
            user_id = excluded.user_id,
            farmer_phone = excluded.farmer_phone,
            farmer_id = excluded.farmer_id,
            name = excluded.name,
            geometry_json = excluded.geometry_json,
            bounds_json = excluded.bounds_json,
            area_hectares = excluded.area_hectares,
            area_acres = excluded.area_acres,
            crop = excluded.crop,
            variety = excluded.variety,
            previous_crop = excluded.previous_crop,
            season = excluded.season,
            irrigation = excluded.irrigation,
            soil_type = excluded.soil_type,
            ownership_type = excluded.ownership_type,
            seed_source = excluded.seed_source,
            harvest_intent = excluded.harvest_intent,
            sowing_date = excluded.sowing_date,
            current_status = excluded.current_status,
            current_status_stage = excluded.current_status_stage,
            current_status_updated_at = excluded.current_status_updated_at,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            selected = excluded.selected
          ''',
          variables: [
            Variable.withString(farm.farmId),
            Variable(farm.userId),
            Variable.withString(digits),
            Variable(farm.farmerIdValue ?? farmerId),
            Variable.withString(farm.name),
            Variable.withString(jsonEncode(farm.geometry)),
            Variable(farm.bounds == null ? null : jsonEncode(farm.bounds)),
            Variable(farm.areaHectares),
            Variable(farm.areaAcres),
            Variable(farm.crop),
            Variable(farm.variety),
            Variable(farm.previousCrop),
            Variable(farm.season),
            Variable(farm.irrigation),
            Variable(farm.soilType),
            Variable(farm.ownershipType),
            Variable(farm.seedSource),
            Variable(farm.harvestIntent),
            Variable(farm.sowingDate),
            Variable(farm.currentStatus),
            Variable(farm.currentStatusStage),
            Variable(currentStatusUpdatedAt),
            Variable.withString(farm.createdAt),
            Variable.withString(farm.updatedAt),
            Variable.withInt(farm.selected ? 1 : 0),
          ],
        );
      }
    });
  }

  Future<List<LocalFarmCacheRecord>> loadCachedFarmsForFarmer({
    required String farmerPhone,
    String? farmerId,
  }) async {
    await ensureInitialized();
    final digits = _normalizePhone(farmerPhone);
    if (digits.isEmpty) return const [];
    final farmerIdValue = farmerId?.trim();
    final rows = await customSelect(
      farmerIdValue == null || farmerIdValue.isEmpty
          ? '''
            SELECT * FROM local_farms_cache
            WHERE farmer_phone = ?
            ORDER BY selected DESC, created_at DESC
            '''
          : '''
            SELECT * FROM local_farms_cache
            WHERE farmer_phone = ?
              AND (farmer_id IS NULL OR farmer_id = '' OR farmer_id = ?)
            ORDER BY selected DESC, created_at DESC
            ''',
      variables: farmerIdValue == null || farmerIdValue.isEmpty
          ? [Variable.withString(digits)]
          : [Variable.withString(digits), Variable.withString(farmerIdValue)],
    ).get();
    return rows.map(_farmCacheFromRow).toList();
  }

  Future<void> setSelectedFarmCache({
    required String farmerPhone,
    required String farmId,
  }) async {
    await ensureInitialized();
    final digits = _normalizePhone(farmerPhone);
    if (digits.isEmpty || farmId.trim().isEmpty) return;
    await transaction(() async {
      await customUpdate(
        '''
        UPDATE local_farms_cache
        SET selected = 0
        WHERE farmer_phone = ?
        ''',
        variables: [Variable.withString(digits)],
      );
      await customUpdate(
        '''
        UPDATE local_farms_cache
        SET selected = 1
        WHERE farmer_phone = ? AND farm_id = ?
        ''',
        variables: [
          Variable.withString(digits),
          Variable.withString(farmId),
        ],
      );
    });
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
    var rows = await customSelect(
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
    if (rows.isEmpty && !sourceId.contains('#region=')) {
      rows = await customSelect(
        '''
        SELECT bytes, content_type FROM offline_tile_cache
        WHERE source_id LIKE ? AND z = ? AND x = ? AND y = ?
        ORDER BY updated_at DESC
        LIMIT 1
        ''',
        variables: [
          Variable.withString('$sourceId#region=%'),
          Variable.withInt(z),
          Variable.withInt(x),
          Variable.withInt(y),
        ],
      ).get();
    }
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

  LocalFarmerProfileRecord _farmerProfileFromRow(QueryRow row) {
    return LocalFarmerProfileRecord(
      phone: row.read<String>('phone'),
      farmerId: row.read<String>('farmer_id'),
      farmerName: row.read<String>('farmer_name'),
      userId: row.read<String>('user_id'),
      defaultLocation: row.read<String>('default_location'),
      preferredLanguage: row.read<String>('preferred_language'),
      profileComplete: row.read<int>('profile_complete') == 1,
      lastVerifiedAt: row.read<String>('last_verified_at'),
      syncedAt: row.read<String>('synced_at'),
    );
  }

  LocalFarmCacheRecord _farmCacheFromRow(QueryRow row) {
    return LocalFarmCacheRecord(
      farmId: row.read<String>('farm_id'),
      userId: row.readNullable<String>('user_id'),
      farmerPhone: row.readNullable<String>('farmer_phone'),
      farmerIdValue: row.readNullable<String>('farmer_id'),
      name: row.read<String>('name'),
      geometry: _decodeMap(row.read<String>('geometry_json')),
      bounds: _decodeNullableMap(row.readNullable<String>('bounds_json')),
      areaHectares: row.readNullable<double>('area_hectares'),
      areaAcres: row.readNullable<double>('area_acres'),
      crop: row.readNullable<String>('crop'),
      variety: row.readNullable<String>('variety'),
      previousCrop: row.readNullable<String>('previous_crop'),
      season: row.readNullable<String>('season'),
      irrigation: row.readNullable<String>('irrigation'),
      soilType: row.readNullable<String>('soil_type'),
      ownershipType: row.readNullable<String>('ownership_type'),
      seedSource: row.readNullable<String>('seed_source'),
      harvestIntent: row.readNullable<String>('harvest_intent'),
      sowingDate: row.readNullable<String>('sowing_date'),
      currentStatus: row.readNullable<String>('current_status'),
      currentStatusStage: row.readNullable<String>('current_status_stage'),
      currentStatusUpdatedAt:
          row.readNullable<String>('current_status_updated_at'),
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
      selected: row.read<int>('selected') == 1,
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
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic>? _decodeNullableMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = _decodeMap(raw);
    return decoded.isEmpty ? null : decoded;
  }

  List<Map<String, dynamic>> _decodeRows(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }
}
