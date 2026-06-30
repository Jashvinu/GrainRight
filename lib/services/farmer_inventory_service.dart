import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/farmer_inventory_item.dart';
import 'local_app_database.dart';

class FarmerInventoryException implements Exception {
  final String message;

  const FarmerInventoryException(this.message);

  @override
  String toString() => message;
}

class FarmerInventoryService {
  SupabaseClient get _client => Supabase.instance.client;

  LocalAppDatabase? get _localDb => LocalAppDatabase.maybeInstance;

  String? get _uid => _client.auth.currentUser?.id.trim();

  Future<List<FarmerInventoryItem>> syncInventoryForFarmer({
    required String farmerPhone,
    String? farmerId,
  }) async {
    final phone = _normalizePhone(farmerPhone);
    if (phone.isEmpty) return const [];
    final cached = await _loadCached(phone, farmerId);
    final userId = _uid;
    if (userId == null || userId.isEmpty) return cached;

    await _flushPending(phone: phone, farmerId: farmerId, userId: userId);

    try {
      final remoteItems = await _syncRemoteViaFunction(
        phone: phone,
        farmerId: farmerId,
      );
      await _replaceCache(phone: phone, farmerId: farmerId, items: remoteItems);
      final pending = await _loadPending(phone, farmerId);
      return _mergeInventory(remoteItems, pending);
    } catch (_) {
      return cached;
    }
  }

  Future<FarmerInventoryItem> saveInventoryItem(
    FarmerInventoryItem item,
  ) async {
    final phone = _normalizePhone(item.farmerPhone);
    final farmId = item.farmId.trim();
    if (phone.isEmpty) {
      throw const FarmerInventoryException(
        'Farmer login is required before saving inventory.',
      );
    }
    if (farmId.isEmpty) {
      throw const FarmerInventoryException(
        'Sync this farm before saving inventory.',
      );
    }

    final now = DateTime.now().toUtc();
    final pending = item.copyWith(
      farmerPhone: phone,
      syncStatus: 'pending',
      updatedAt: now,
      lastError: null,
    );
    await _upsertCache(pending);

    final userId = _uid;
    if (userId == null || userId.isEmpty) return pending;

    try {
      final saved = await _saveRemote(pending, userId: userId);
      await _upsertCache(saved);
      return saved;
    } catch (error) {
      final failed = pending.copyWith(
        lastError: error.toString(),
        updatedAt: DateTime.now().toUtc(),
      );
      await _upsertCache(failed);
      return failed;
    }
  }

  Future<FarmerInventoryItem> _saveRemote(
    FarmerInventoryItem item, {
    required String userId,
  }) async {
    try {
      return await _saveRemoteViaFunction(
        item,
      ).then((saved) => saved.copyWith(localId: item.localId));
    } catch (_) {
      // Fall back to direct table access when the edge function is not deployed.
    }
    final saved = await _client
        .from('farmer_inventory_items')
        .upsert(
          item.toRemoteJson(userId: userId),
          onConflict: 'user_id,inventory_id',
        )
        .select()
        .single();
    return FarmerInventoryItem.fromRemoteJson(
      Map<String, dynamic>.from(saved as Map),
    ).copyWith(localId: item.localId);
  }

  Future<List<FarmerInventoryItem>> _syncRemoteViaFunction({
    required String phone,
    required String? farmerId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'farmer-inventory-sync',
        headers: _functionAuthHeaders(),
        body: {'action': 'sync', 'phone': phone, 'farmerId': farmerId ?? ''},
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw FarmerInventoryException(
          '${data['error'] ?? 'Inventory sync failed.'}',
        );
      }
      final rows = data['items'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map(
            (row) => FarmerInventoryItem.fromRemoteJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      final rows = await _client
          .from('farmer_inventory_items')
          .select()
          .eq('farmer_phone', phone)
          .order('created_at', ascending: false)
          .limit(200);
      return rows
          .whereType<Map>()
          .map(
            (row) => FarmerInventoryItem.fromRemoteJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false);
    }
  }

  Future<FarmerInventoryItem> _saveRemoteViaFunction(
    FarmerInventoryItem item,
  ) async {
    final response = await _client.functions.invoke(
      'farmer-inventory-sync',
      headers: _functionAuthHeaders(),
      body: {
        'action': 'save',
        'phone': _normalizePhone(item.farmerPhone),
        'farmerId': item.farmerId,
        'item': item.toRemoteJson(userId: _uid ?? item.userId),
      },
    );
    final data = _responseMap(response.data);
    if (data['success'] == false) {
      throw FarmerInventoryException(
        '${data['error'] ?? 'Inventory save failed.'}',
      );
    }
    final row = data['item'];
    if (row is! Map) {
      throw const FarmerInventoryException('Inventory save response missing.');
    }
    return FarmerInventoryItem.fromRemoteJson(Map<String, dynamic>.from(row));
  }

  Map<String, String>? _functionAuthHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _responseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  Future<void> _flushPending({
    required String phone,
    required String? farmerId,
    required String userId,
  }) async {
    final pending = await _loadPending(phone, farmerId);
    for (final item in pending) {
      try {
        final saved = await _saveRemote(item, userId: userId);
        await _upsertCache(saved);
      } catch (error) {
        final db = _localDb;
        if (db == null) continue;
        await db.markInventoryPending(
          localId: item.localId,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          lastError: error.toString(),
        );
      }
    }
  }

  Future<List<FarmerInventoryItem>> _loadCached(
    String phone,
    String? farmerId,
  ) async {
    final db = _localDb;
    if (db == null) return const [];
    final records = await db.loadCachedInventoryForFarmer(
      farmerPhone: phone,
      farmerId: farmerId,
    );
    return records.map(_fromLocal).toList(growable: false);
  }

  Future<List<FarmerInventoryItem>> _loadPending(
    String phone,
    String? farmerId,
  ) async {
    final db = _localDb;
    if (db == null) return const [];
    final records = await db.loadPendingInventoryForFarmer(
      farmerPhone: phone,
      farmerId: farmerId,
    );
    return records.map(_fromLocal).toList(growable: false);
  }

  Future<void> _replaceCache({
    required String phone,
    required String? farmerId,
    required List<FarmerInventoryItem> items,
  }) async {
    final db = _localDb;
    if (db == null) return;
    await db.replaceInventoryCacheForFarmer(
      farmerPhone: phone,
      farmerId: farmerId,
      items: items.map(_toLocal).toList(growable: false),
    );
  }

  Future<void> _upsertCache(FarmerInventoryItem item) async {
    final db = _localDb;
    if (db == null) return;
    await db.upsertInventoryCache(
      _toLocal(item),
      fallbackFarmerId: item.farmerId,
    );
  }

  List<FarmerInventoryItem> _mergeInventory(
    List<FarmerInventoryItem> remote,
    List<FarmerInventoryItem> pending,
  ) {
    if (pending.isEmpty) return remote;
    final seen = remote.map((item) => item.localId).toSet();
    return [
      ...pending.where((item) => !seen.contains(item.localId)),
      ...remote,
    ];
  }

  FarmerInventoryItem _fromLocal(LocalInventoryCacheRecord record) {
    final createdAt =
        DateTime.tryParse(record.createdAt) ?? DateTime.now().toUtc();
    return FarmerInventoryItem(
      localId: record.localId,
      remoteId: record.remoteId ?? '',
      userId: record.userId ?? '',
      farmerPhone: record.farmerPhone,
      farmerId: record.farmerIdValue ?? '',
      farmId: record.farmId,
      farmName: record.farmName,
      batchId: record.batchId,
      harvestBatchId: record.harvestBatchId,
      productCategory: FarmerInventoryProductCategory.normalize(
        record.productCategory,
      ),
      productName: record.productName,
      crop: record.crop,
      variety: record.variety,
      quantity: record.quantity,
      unit: record.unit,
      bagCount: record.bagCount,
      bagSizeKg: record.bagSizeKg,
      moisturePercent: record.moisturePercent,
      grade: record.grade,
      gradeScore: record.gradeScore,
      gradeBasis: record.gradeBasis,
      estimatedYieldKg: record.estimatedYieldKg,
      harvestedAt: DateTime.tryParse(record.harvestedAt) ?? createdAt,
      latitude: record.latitude,
      longitude: record.longitude,
      imageName: record.imageName,
      sourceFlow: record.sourceFlow,
      notes: record.notes,
      createdAt: createdAt,
      updatedAt: DateTime.tryParse(record.updatedAt) ?? createdAt,
      syncStatus: record.syncStatus,
      syncedAt: record.syncedAt == null
          ? null
          : DateTime.tryParse(record.syncedAt!),
      lastError: record.lastError,
    );
  }

  LocalInventoryCacheRecord _toLocal(FarmerInventoryItem item) {
    return LocalInventoryCacheRecord(
      localId: item.localId,
      remoteId: item.remoteId.isEmpty ? null : item.remoteId,
      userId: item.userId.isEmpty ? null : item.userId,
      farmerPhone: _normalizePhone(item.farmerPhone),
      farmerIdValue: item.farmerId.isEmpty ? null : item.farmerId,
      farmId: item.farmId,
      farmName: item.farmName,
      batchId: item.batchId,
      harvestBatchId: item.harvestBatchId,
      productCategory: FarmerInventoryProductCategory.normalize(
        item.productCategory,
      ),
      productName: item.productName,
      crop: item.crop,
      variety: item.variety,
      quantity: item.quantity,
      unit: item.unit,
      bagCount: item.bagCount,
      bagSizeKg: item.bagSizeKg,
      moisturePercent: item.moisturePercent,
      grade: item.grade,
      gradeScore: item.gradeScore,
      gradeBasis: item.gradeBasis,
      estimatedYieldKg: item.estimatedYieldKg,
      harvestedAt: item.harvestedAt.toUtc().toIso8601String(),
      latitude: item.latitude,
      longitude: item.longitude,
      imageName: item.imageName,
      sourceFlow: item.sourceFlow,
      notes: item.notes,
      syncStatus: item.syncStatus,
      createdAt: item.createdAt.toUtc().toIso8601String(),
      updatedAt: item.updatedAt.toUtc().toIso8601String(),
      syncedAt: item.syncedAt?.toUtc().toIso8601String(),
      lastError: item.lastError,
    );
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }
}
