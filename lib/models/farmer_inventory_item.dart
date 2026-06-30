class FarmerInventoryProductCategory {
  static const cropLot = 'crop_lot';
  static const byproduct = 'byproduct';
  static const processedProduct = 'processed_product';

  static const values = [cropLot, byproduct, processedProduct];

  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    return values.contains(normalized) ? normalized : cropLot;
  }
}

class FarmerInventoryItem {
  final String localId;
  final String remoteId;
  final String userId;
  final String farmerPhone;
  final String farmerId;
  final String farmId;
  final String farmName;
  final String batchId;
  final String harvestBatchId;
  final String productCategory;
  final String productName;
  final String crop;
  final String variety;
  final double quantity;
  final String unit;
  final int? bagCount;
  final double? bagSizeKg;
  final double? moisturePercent;
  final String grade;
  final int? gradeScore;
  final String gradeBasis;
  final double? estimatedYieldKg;
  final DateTime harvestedAt;
  final double? latitude;
  final double? longitude;
  final String imageName;
  final String sourceFlow;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final DateTime? syncedAt;
  final String? lastError;

  const FarmerInventoryItem({
    required this.localId,
    required this.remoteId,
    required this.userId,
    required this.farmerPhone,
    required this.farmerId,
    required this.farmId,
    required this.farmName,
    required this.batchId,
    required this.harvestBatchId,
    required this.productCategory,
    required this.productName,
    required this.crop,
    required this.variety,
    required this.quantity,
    required this.unit,
    required this.harvestedAt,
    required this.imageName,
    required this.sourceFlow,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.bagCount,
    this.bagSizeKg,
    this.moisturePercent,
    this.grade = '',
    this.gradeScore,
    this.gradeBasis = '',
    this.estimatedYieldKg,
    this.latitude,
    this.longitude,
    this.syncedAt,
    this.lastError,
  });

  factory FarmerInventoryItem.fromRemoteJson(Map<String, dynamic> json) {
    final createdAt = _date(json['created_at']) ?? DateTime.now().toUtc();
    final updatedAt = _date(json['updated_at']) ?? createdAt;
    final inventoryId = _text(
      json['inventory_id'],
      _text(json['batch_id'], _text(json['id'])),
    );
    final harvestBatchId = _text(json['harvest_batch_id']);
    final displayBatchId = harvestBatchId.isEmpty
        ? inventoryId
        : harvestBatchId;
    return FarmerInventoryItem(
      localId: inventoryId,
      remoteId: _text(json['id']),
      userId: _text(json['user_id']),
      farmerPhone: _normalizePhone(_text(json['farmer_phone'])),
      farmerId: _text(json['farmer_id']),
      farmId: _text(json['farm_id']),
      farmName: _text(json['farm_name']),
      batchId: displayBatchId,
      harvestBatchId: harvestBatchId,
      productCategory: FarmerInventoryProductCategory.normalize(
        _text(json['product_category']),
      ),
      productName: _text(json['product_name']),
      crop: _text(json['crop']),
      variety: _text(json['variety']),
      quantity: _double(json['quantity']) ?? 0,
      unit: _text(json['unit'], 'kg'),
      bagCount: _int(json['bag_count']),
      bagSizeKg: _double(json['bag_size_kg']),
      moisturePercent: _double(json['moisture_percent']),
      grade: _text(json['grade']),
      gradeScore: _int(json['grade_score']),
      gradeBasis: _text(json['grade_basis']),
      estimatedYieldKg: _double(json['estimated_yield_kg']),
      harvestedAt: _date(json['harvested_at']) ?? createdAt,
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      imageName: _text(json['image_name']),
      sourceFlow: _text(json['source_flow'], 'inventory'),
      notes: _text(json['notes']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: 'synced',
      syncedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toRemoteJson({required String userId}) {
    return {
      'user_id': userId,
      'farmer_phone': _normalizePhone(farmerPhone),
      'farmer_id': farmerId,
      'farm_id': farmId,
      'farm_name': farmName,
      'inventory_id': localId,
      'harvest_batch_id': harvestBatchId.trim().isEmpty
          ? null
          : harvestBatchId.trim(),
      'product_category': FarmerInventoryProductCategory.normalize(
        productCategory,
      ),
      'product_name': productName,
      'crop': crop,
      'variety': variety,
      'quantity': quantity,
      'unit': unit,
      'bag_count': bagCount,
      'bag_size_kg': bagSizeKg,
      'moisture_percent': moisturePercent,
      'grade': grade,
      'grade_score': gradeScore,
      'grade_basis': gradeBasis,
      'estimated_yield_kg': estimatedYieldKg,
      'harvested_at': harvestedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'image_name': imageName,
      'source_flow': sourceFlow,
      'notes': notes,
    };
  }

  FarmerInventoryItem copyWith({
    String? localId,
    String? remoteId,
    String? userId,
    String? farmerPhone,
    String? farmerId,
    String? farmId,
    String? farmName,
    String? batchId,
    String? harvestBatchId,
    String? productCategory,
    String? productName,
    String? crop,
    String? variety,
    double? quantity,
    String? unit,
    int? bagCount,
    double? bagSizeKg,
    double? moisturePercent,
    String? grade,
    int? gradeScore,
    String? gradeBasis,
    double? estimatedYieldKg,
    DateTime? harvestedAt,
    double? latitude,
    double? longitude,
    String? imageName,
    String? sourceFlow,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
    DateTime? syncedAt,
    String? lastError,
  }) {
    return FarmerInventoryItem(
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      userId: userId ?? this.userId,
      farmerPhone: farmerPhone ?? this.farmerPhone,
      farmerId: farmerId ?? this.farmerId,
      farmId: farmId ?? this.farmId,
      farmName: farmName ?? this.farmName,
      batchId: batchId ?? this.batchId,
      harvestBatchId: harvestBatchId ?? this.harvestBatchId,
      productCategory: productCategory ?? this.productCategory,
      productName: productName ?? this.productName,
      crop: crop ?? this.crop,
      variety: variety ?? this.variety,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      bagCount: bagCount ?? this.bagCount,
      bagSizeKg: bagSizeKg ?? this.bagSizeKg,
      moisturePercent: moisturePercent ?? this.moisturePercent,
      grade: grade ?? this.grade,
      gradeScore: gradeScore ?? this.gradeScore,
      gradeBasis: gradeBasis ?? this.gradeBasis,
      estimatedYieldKg: estimatedYieldKg ?? this.estimatedYieldKg,
      harvestedAt: harvestedAt ?? this.harvestedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageName: imageName ?? this.imageName,
      sourceFlow: sourceFlow ?? this.sourceFlow,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncedAt: syncedAt ?? this.syncedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

String _text(Object? raw, [String fallback = '']) {
  final text = raw == null ? '' : '$raw'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

double? _double(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw));
}

int? _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(_text(raw));
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}

String _normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
}
