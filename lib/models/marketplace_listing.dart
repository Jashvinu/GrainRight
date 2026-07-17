class MarketplaceListing {
  final String id;
  final String inventoryItemId;
  final String farmerUserId;
  final String farmerPhone;
  final String farmerId;
  final String farmId;
  final String farmName;
  final String batchId;
  final String productCategory;
  final String productName;
  final String crop;
  final String variety;
  final double quantity;
  final String unit;
  final String grade;
  final int? gradeScore;
  final double? moisturePercent;
  final double? askingPricePerUnit;
  final String listingNote;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int interestCount;
  final bool interestedByMe;
  final String interestStatus;

  const MarketplaceListing({
    required this.id,
    required this.inventoryItemId,
    required this.farmerUserId,
    required this.farmerPhone,
    required this.farmerId,
    required this.farmId,
    required this.farmName,
    required this.batchId,
    required this.productCategory,
    required this.productName,
    required this.crop,
    required this.variety,
    required this.quantity,
    required this.unit,
    required this.grade,
    required this.status,
    required this.interestCount,
    required this.interestedByMe,
    required this.interestStatus,
    this.gradeScore,
    this.moisturePercent,
    this.askingPricePerUnit,
    this.listingNote = '',
    this.createdAt,
    this.updatedAt,
  });

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) {
    return MarketplaceListing(
      id: _text(json['id']),
      inventoryItemId: _text(json['inventory_item_id']),
      farmerUserId: _text(json['farmer_user_id']),
      farmerPhone: _text(json['farmer_phone']),
      farmerId: _text(json['farmer_id']),
      farmId: _text(json['farm_id']),
      farmName: _text(json['farm_name']),
      batchId: _text(json['batch_id']),
      productCategory: _text(json['product_category'], 'crop_lot'),
      productName: _text(json['product_name']),
      crop: _text(json['crop']),
      variety: _text(json['variety']),
      quantity: _double(json['quantity']) ?? 0,
      unit: _text(json['unit'], 'kg'),
      grade: _text(json['grade']),
      gradeScore: _int(json['grade_score']),
      moisturePercent: _double(json['moisture_percent']),
      askingPricePerUnit: _double(json['asking_price_per_unit']),
      listingNote: _text(json['listing_note']),
      status: _text(json['status'], 'active'),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      interestCount: _int(json['interest_count']) ?? 0,
      interestedByMe: _bool(json['interested_by_me']),
      interestStatus: _text(json['interest_status']),
    );
  }

  String get displayProductName {
    if (productName.trim().isNotEmpty) return productName.trim();
    final parts = [crop.trim(), variety.trim()]
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? batchId : parts.join(' ');
  }

  bool get isActive => status.toLowerCase() == 'active';
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

bool _bool(Object? raw) {
  if (raw is bool) return raw;
  final text = _text(raw).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
