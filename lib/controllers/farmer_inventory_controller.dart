import 'package:get/get.dart';

import '../models/farmer_inventory_item.dart';
import '../services/farmer_inventory_service.dart';

class FarmerInventoryController extends GetxController {
  FarmerInventoryController({FarmerInventoryService? service})
    : _service = service ?? FarmerInventoryService();

  final FarmerInventoryService _service;

  final items = <FarmerInventoryItem>[].obs;
  final isLoading = false.obs;
  final pendingSyncCount = 0.obs;
  final errorMessage = ''.obs;

  Future<void> syncForFarmer({
    required String farmerPhone,
    String? farmerId,
  }) async {
    final phone = _normalizePhone(farmerPhone);
    if (phone.isEmpty) {
      items.clear();
      pendingSyncCount.value = 0;
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final synced = await _service.syncInventoryForFarmer(
        farmerPhone: phone,
        farmerId: farmerId,
      );
      items.assignAll(synced);
      _updatePendingCount();
    } catch (error) {
      errorMessage.value = error.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<FarmerInventoryItem> saveItem(FarmerInventoryItem item) async {
    final saved = await _service.saveInventoryItem(item);
    _upsertVisibleItem(saved);
    return saved;
  }

  void clear() {
    items.clear();
    pendingSyncCount.value = 0;
    errorMessage.value = '';
  }

  void _upsertVisibleItem(FarmerInventoryItem item) {
    final index = items.indexWhere(
      (existing) =>
          existing.localId == item.localId || existing.batchId == item.batchId,
    );
    if (index >= 0) {
      items[index] = item;
    } else {
      items.insert(0, item);
    }
    _updatePendingCount();
  }

  void _updatePendingCount() {
    pendingSyncCount.value = items
        .where((item) => item.syncStatus != 'synced')
        .length;
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }
}
