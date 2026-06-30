import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/farmer_inventory_item.dart';

void main() {
  group('FarmerInventoryItem', () {
    test('saves manual products with farmer inventory id, not harvest id', () {
      final item = _inventoryItem(
        localId: 'manual-product-1',
        batchId: 'manual-product-1',
        productCategory: FarmerInventoryProductCategory.byproduct,
        sourceFlow: 'manual_inventory',
      );

      final json = item.toRemoteJson(userId: 'auth-user-1');

      expect(json['user_id'], 'auth-user-1');
      expect(json['farmer_phone'], '9876543210');
      expect(json['farmer_id'], 'farmer-42');
      expect(json['inventory_id'], 'manual-product-1');
      expect(json['harvest_batch_id'], isNull);
      expect(json.containsKey('batch_id'), isFalse);
    });

    test('keeps harvest batch only as a crop lot reference', () {
      final item = _inventoryItem(
        localId: 'inventory-harvest-1',
        batchId: 'harvest-batch-1',
        harvestBatchId: 'harvest-batch-1',
        productCategory: FarmerInventoryProductCategory.cropLot,
        sourceFlow: 'harvest',
      );

      final json = item.toRemoteJson(userId: 'auth-user-1');

      expect(json['inventory_id'], 'inventory-harvest-1');
      expect(json['harvest_batch_id'], 'harvest-batch-1');
      expect(json.containsKey('batch_id'), isFalse);
    });

    test('loads remote inventory id separately from optional harvest id', () {
      final manualProduct = FarmerInventoryItem.fromRemoteJson({
        'id': 'remote-row-1',
        'user_id': 'auth-user-1',
        'farmer_phone': '+91 98765 43210',
        'farmer_id': 'farmer-42',
        'farm_id': 'farm-1',
        'farm_name': 'North Farm',
        'inventory_id': 'manual-product-2',
        'product_category': FarmerInventoryProductCategory.processedProduct,
        'product_name': 'Ragi Flour',
        'quantity': 12,
        'unit': 'kg',
        'created_at': '2026-06-26T10:00:00Z',
        'updated_at': '2026-06-26T10:00:00Z',
      });

      expect(manualProduct.localId, 'manual-product-2');
      expect(manualProduct.batchId, 'manual-product-2');
      expect(manualProduct.harvestBatchId, '');
      expect(
        manualProduct.productCategory,
        FarmerInventoryProductCategory.processedProduct,
      );

      final cropLot = FarmerInventoryItem.fromRemoteJson({
        'id': 'remote-row-2',
        'user_id': 'auth-user-1',
        'farmer_phone': '9876543210',
        'farmer_id': 'farmer-42',
        'farm_id': 'farm-1',
        'farm_name': 'North Farm',
        'inventory_id': 'inventory-harvest-2',
        'harvest_batch_id': 'harvest-batch-2',
        'product_category': FarmerInventoryProductCategory.cropLot,
        'product_name': 'Ragi',
        'quantity': 100,
        'unit': 'kg',
        'created_at': '2026-06-26T10:00:00Z',
        'updated_at': '2026-06-26T10:00:00Z',
      });

      expect(cropLot.localId, 'inventory-harvest-2');
      expect(cropLot.batchId, 'harvest-batch-2');
      expect(cropLot.harvestBatchId, 'harvest-batch-2');
    });
  });
}

FarmerInventoryItem _inventoryItem({
  required String localId,
  required String batchId,
  String harvestBatchId = '',
  required String productCategory,
  required String sourceFlow,
}) {
  final now = DateTime.utc(2026, 6, 26, 10);
  return FarmerInventoryItem(
    localId: localId,
    remoteId: '',
    userId: 'auth-user-1',
    farmerPhone: '+91 98765 43210',
    farmerId: 'farmer-42',
    farmId: 'farm-1',
    farmName: 'North Farm',
    batchId: batchId,
    harvestBatchId: harvestBatchId,
    productCategory: productCategory,
    productName: productCategory == FarmerInventoryProductCategory.cropLot
        ? 'Ragi'
        : 'Ragi Flour',
    crop: 'Ragi',
    variety: '',
    quantity: 12,
    unit: 'kg',
    harvestedAt: now,
    imageName: '',
    sourceFlow: sourceFlow,
    notes: '',
    createdAt: now,
    updatedAt: now,
    syncStatus: 'pending',
  );
}
