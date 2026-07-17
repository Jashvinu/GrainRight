import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/local_app_database.dart';

void main() {
  late LocalAppDatabase database;

  setUp(() {
    database = LocalAppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('stores farmer profile cache by normalized phone', () async {
    await database.upsertFarmerProfileCache(
      record: const LocalFarmerProfileRecord(
        phone: '+91 98765 43210',
        farmerId: 'FMR-9876543210',
        farmerName: 'Test Farmer',
        userId: 'user-1',
        defaultLocation: 'Akole',
        preferredLanguage: 'en',
        profileComplete: true,
        lastVerifiedAt: '2026-06-18T10:00:00.000Z',
        syncedAt: '2026-06-18T10:00:00.000Z',
      ),
    );

    final cached = await database.readFarmerProfileByPhone('9876543210');

    expect(cached, isNotNull);
    expect(cached!.phone, '9876543210');
    expect(cached.farmerId, 'FMR-9876543210');
    expect(cached.farmerName, 'Test Farmer');
    expect(cached.profileComplete, isTrue);
  });

  test('loads only farms for the requested farmer phone', () async {
    await database.replaceFarmCacheForFarmer(
      farmerPhone: '9876543210',
      farmerId: 'FMR-9876543210',
      farms: [
        _farm(
          farmId: 'farm-a',
          farmerPhone: '9876543210',
          farmerId: 'FMR-9876543210',
          name: 'North Field',
          selected: true,
        ),
      ],
    );
    await database.replaceFarmCacheForFarmer(
      farmerPhone: '9123456789',
      farmerId: 'FMR-9123456789',
      farms: [
        _farm(
          farmId: 'farm-b',
          farmerPhone: '9123456789',
          farmerId: 'FMR-9123456789',
          name: 'South Field',
        ),
      ],
    );

    final firstFarmerFarms = await database.loadCachedFarmsForFarmer(
      farmerPhone: '+91 98765 43210',
      farmerId: 'FMR-9876543210',
    );

    expect(firstFarmerFarms, hasLength(1));
    expect(firstFarmerFarms.single.farmId, 'farm-a');
    expect(firstFarmerFarms.single.name, 'North Field');
    expect(firstFarmerFarms.single.selected, isTrue);
    expect(firstFarmerFarms.single.currentStatus, 'Crop looks healthy');
    expect(firstFarmerFarms.single.currentStatusStage, 'Tillering');
    expect(
      firstFarmerFarms.single.currentStatusUpdatedAt,
      '2026-06-18T10:00:00.000Z',
    );
  });

  test('loads farms by login phone even when farmer id changes', () async {
    await database.replaceFarmCacheForFarmer(
      farmerPhone: '+91 98765 43210',
      farmerId: 'FMR-OLD',
      farms: [
        _farm(
          farmId: 'marked-farm',
          farmerPhone: '9876543210',
          farmerId: 'FMR-OLD',
          name: 'Marked Farm',
          selected: true,
        ),
      ],
    );

    final samePhoneFarms = await database.loadCachedFarmsForFarmer(
      farmerPhone: '9876543210',
      farmerId: 'FMR-NEW',
    );
    final otherPhoneFarms = await database.loadCachedFarmsForFarmer(
      farmerPhone: '9123456789',
      farmerId: 'FMR-OTHER',
    );

    expect(samePhoneFarms, hasLength(1));
    expect(samePhoneFarms.single.farmId, 'marked-farm');
    expect(samePhoneFarms.single.farmerIdValue, 'FMR-OLD');
    expect(samePhoneFarms.single.selected, isTrue);
    expect(otherPhoneFarms, isEmpty);
  });

  test(
    'loads farmer inventory by login phone even when farmer id changes',
    () async {
      await database.upsertInventoryCache(
        _inventory(
          localId: 'manual-product',
          farmerPhone: '+91 98765 43210',
          farmerId: 'FMR-OLD',
          productName: 'Ragi Flour',
          productCategory: 'processed_product',
        ),
      );
      await database.upsertInventoryCache(
        _inventory(
          localId: 'byproduct',
          farmerPhone: '9876543210',
          farmerId: null,
          productName: 'Ragi Straw',
          productCategory: 'byproduct',
        ),
      );
      await database.upsertInventoryCache(
        _inventory(
          localId: 'other-farmer-product',
          farmerPhone: '9123456789',
          farmerId: 'FMR-OTHER',
          productName: 'Other Product',
          productCategory: 'processed_product',
        ),
      );

      final cached = await database.loadCachedInventoryForFarmer(
        farmerPhone: '+91 98765 43210',
        farmerId: 'FMR-NEW',
      );

      expect(cached, hasLength(2));
      expect(
        cached.map((item) => item.localId),
        containsAll(['manual-product', 'byproduct']),
      );
      expect(
        cached.any((item) => item.localId == 'other-farmer-product'),
        isFalse,
      );
    },
  );
}

LocalFarmCacheRecord _farm({
  required String farmId,
  required String farmerPhone,
  required String farmerId,
  required String name,
  bool selected = false,
}) {
  return LocalFarmCacheRecord(
    farmId: farmId,
    userId: 'user-$farmId',
    farmerPhone: farmerPhone,
    farmerIdValue: farmerId,
    name: name,
    geometry: const {
      'type': 'Polygon',
      'coordinates': [
        [
          [74.0, 19.0],
          [74.1, 19.0],
          [74.1, 19.1],
          [74.0, 19.0],
        ],
      ],
    },
    areaHectares: 1.2,
    areaAcres: 2.96,
    crop: 'Finger millet',
    variety: 'Local',
    currentStatus: 'Crop looks healthy',
    currentStatusStage: 'Tillering',
    createdAt: '2026-06-18T09:00:00.000Z',
    updatedAt: '2026-06-18T10:00:00.000Z',
    selected: selected,
  );
}

LocalInventoryCacheRecord _inventory({
  required String localId,
  required String farmerPhone,
  required String? farmerId,
  required String productName,
  required String productCategory,
}) {
  return LocalInventoryCacheRecord(
    localId: localId,
    remoteId: 'remote-$localId',
    userId: 'user-1',
    farmerPhone: farmerPhone,
    farmerIdValue: farmerId,
    farmId: 'farm-a',
    farmName: 'North Field',
    batchId: localId,
    productCategory: productCategory,
    productName: productName,
    crop: 'Ragi',
    variety: '',
    quantity: 12,
    unit: 'kg',
    harvestedAt: '2026-06-26T10:00:00.000Z',
    imageName: '',
    sourceFlow: 'manual_inventory',
    notes: '',
    syncStatus: 'synced',
    createdAt: '2026-06-26T10:00:00.000Z',
    updatedAt: '2026-06-26T10:00:00.000Z',
    syncedAt: '2026-06-26T10:00:00.000Z',
  );
}
