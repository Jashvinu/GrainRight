class MarketplaceListing {
  final String id;
  final String ownerId;
  final String lotId;
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
  final String title;
  final String description;
  final String locationLabel;
  final String priceUnit;
  final List<String> imagePaths;
  final int viewCount;
  final DateTime? expiresAt;
  final DateTime? pausedAt;
  final String closedReason;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int interestCount;
  final bool interestedByMe;
  final String interestStatus;
  final String cropProgramEnrollmentId;
  final String exclusiveFpcId;
  final String saleChannel;
  final double? protectedFloorRate;

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
    this.ownerId = '',
    this.lotId = '',
    this.gradeScore,
    this.moisturePercent,
    this.askingPricePerUnit,
    this.listingNote = '',
    this.title = '',
    this.description = '',
    this.locationLabel = '',
    this.priceUnit = 'kg',
    this.imagePaths = const [],
    this.viewCount = 0,
    this.expiresAt,
    this.pausedAt,
    this.closedReason = '',
    this.createdAt,
    this.updatedAt,
    this.cropProgramEnrollmentId = '',
    this.exclusiveFpcId = '',
    this.saleChannel = 'open_market',
    this.protectedFloorRate,
  });

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) {
    return MarketplaceListing(
      id: _text(json['id']),
      ownerId: _text(json['owner_id'], _text(json['farmer_user_id'])),
      lotId: _text(json['lot_id']),
      inventoryItemId: _text(json['inventory_item_id']),
      farmerUserId: _text(json['farmer_user_id'], _text(json['owner_id'])),
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
      askingPricePerUnit: _double(
        json['asking_price_per_unit'] ?? json['asking_price_per_kg'],
      ),
      listingNote: _text(json['listing_note']),
      title: _text(json['title']),
      description: _text(json['description'], _text(json['listing_note'])),
      locationLabel: _text(
        json['location_label'],
        _text(json['farm_name'], _text(json['buyer_city'])),
      ),
      priceUnit: _text(json['price_unit'], _text(json['unit'], 'kg')),
      imagePaths: _stringList(json['image_paths']),
      viewCount: _int(json['view_count']) ?? 0,
      expiresAt: _date(json['expires_at']),
      pausedAt: _date(json['paused_at']),
      closedReason: _text(json['closed_reason']),
      status: _text(json['status'], 'listed'),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
      interestCount: _int(json['interest_count']) ?? 0,
      interestedByMe: _bool(json['interested_by_me']),
      interestStatus: _text(json['interest_status']),
      cropProgramEnrollmentId: _text(json['crop_program_enrollment_id']),
      exclusiveFpcId: _text(json['exclusive_fpc_id']),
      saleChannel: _text(json['sale_channel'], 'open_market'),
      protectedFloorRate: _double(json['protected_floor_rate']),
    );
  }

  String get displayProductName {
    if (title.trim().isNotEmpty) return title.trim();
    if (productName.trim().isNotEmpty) return productName.trim();
    final parts = [
      crop.trim(),
      variety.trim(),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? batchId : parts.join(' ');
  }

  bool get isActive {
    final value = status.toLowerCase();
    return value == 'active' || value == 'listed';
  }

  bool get isPaused => status.toLowerCase() == 'paused';
  bool get isFpcExclusive =>
      saleChannel == 'fpc_exclusive' && exclusiveFpcId.isNotEmpty;

  bool get isSold {
    final value = status.toLowerCase();
    return value == 'sold' || value == 'closed';
  }
}

class MarketplaceInputProduct {
  final String id;
  final String name;
  final String category;
  final String brand;
  final String description;
  final String packageSize;
  final double? price;
  final String priceUnit;
  final String imagePath;
  final String supplierName;
  final bool isVerified;

  const MarketplaceInputProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.brand,
    required this.description,
    required this.packageSize,
    required this.priceUnit,
    required this.imagePath,
    required this.supplierName,
    required this.isVerified,
    this.price,
  });

  factory MarketplaceInputProduct.fromJson(Map<String, dynamic> json) {
    return MarketplaceInputProduct(
      id: _text(json['id']),
      name: _text(json['name']),
      category: _text(json['category']),
      brand: _text(json['brand']),
      description: _text(json['description']),
      packageSize: _text(json['package_size']),
      price: _double(json['price']),
      priceUnit: _text(json['price_unit'], 'unit'),
      imagePath: _text(json['image_path']),
      supplierName: _text(json['supplier_name']),
      isVerified: _bool(json['is_verified']),
    );
  }
}

class MarketplaceOffer {
  final String id;
  final String requestId;
  final String offeredByRole;
  final double quantity;
  final String unit;
  final double pricePerUnit;
  final String message;
  final String status;
  final DateTime? createdAt;

  const MarketplaceOffer({
    required this.id,
    required this.requestId,
    required this.offeredByRole,
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.message,
    required this.status,
    this.createdAt,
  });

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    return MarketplaceOffer(
      id: _text(json['id']),
      requestId: _text(json['request_id']),
      offeredByRole: _text(json['offered_by_role']),
      quantity: _double(json['quantity']) ?? 0,
      unit: _text(json['unit'], 'kg'),
      pricePerUnit: _double(json['price_per_unit']) ?? 0,
      message: _text(json['message']),
      status: _text(json['status'], 'open'),
      createdAt: _date(json['created_at']),
    );
  }

  bool get isOpen => status.toLowerCase() == 'open';
}

class MarketplaceNegotiation {
  final String id;
  final String currentOfferId;
  final String status;
  final String message;
  final MarketplaceListing listing;
  final List<MarketplaceOffer> offers;
  final DateTime? updatedAt;

  const MarketplaceNegotiation({
    required this.id,
    required this.currentOfferId,
    required this.status,
    required this.message,
    required this.listing,
    required this.offers,
    this.updatedAt,
  });

  factory MarketplaceNegotiation.fromJson(Map<String, dynamic> json) {
    final listingJson = _map(json['listing']);
    final offerRows = json['offers'];
    return MarketplaceNegotiation(
      id: _text(json['id']),
      currentOfferId: _text(json['current_offer_id']),
      status: _text(json['status'], 'submitted'),
      message: _text(json['message']),
      listing: MarketplaceListing.fromJson(listingJson),
      offers: offerRows is List
          ? offerRows
                .whereType<Map>()
                .map(
                  (row) =>
                      MarketplaceOffer.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(growable: false)
          : const [],
      updatedAt: _date(json['updated_at']),
    );
  }

  MarketplaceOffer? get currentOffer {
    for (final offer in offers) {
      if (offer.id == currentOfferId) return offer;
    }
    for (final offer in offers) {
      if (offer.isOpen) return offer;
    }
    return offers.isEmpty ? null : offers.first;
  }

  bool get isOpen {
    final value = status.toLowerCase();
    return value == 'submitted' || value == 'countered';
  }
}

class MarketplaceOrder {
  final String id;
  final String orderNumber;
  final String listingId;
  final String status;
  final double quantity;
  final String unit;
  final double provisionalRate;
  final double provisionalAmount;
  final double? arrivalQuantityKg;
  final String arrivalGrade;
  final double? arrivalMoisturePercent;
  final double? finalRate;
  final double? finalAmount;
  final MarketplaceListing listing;
  final Map<String, dynamic> qrPayload;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MarketplaceOrder({
    required this.id,
    required this.orderNumber,
    required this.listingId,
    required this.status,
    required this.quantity,
    required this.unit,
    required this.provisionalRate,
    required this.provisionalAmount,
    required this.arrivalGrade,
    required this.listing,
    required this.qrPayload,
    this.arrivalQuantityKg,
    this.arrivalMoisturePercent,
    this.finalRate,
    this.finalAmount,
    this.createdAt,
    this.updatedAt,
  });

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrder(
      id: _text(json['id']),
      orderNumber: _text(json['order_number']),
      listingId: _text(json['listing_id']),
      status: _text(json['status'], 'awaiting_arrival'),
      quantity: _double(json['quantity']) ?? 0,
      unit: _text(json['unit'], 'kg'),
      provisionalRate: _double(json['provisional_rate']) ?? 0,
      provisionalAmount: _double(json['provisional_amount']) ?? 0,
      arrivalQuantityKg: _double(json['arrival_quantity_kg']),
      arrivalGrade: _text(json['arrival_grade']),
      arrivalMoisturePercent: _double(json['arrival_moisture_percent']),
      finalRate: _double(json['final_rate']),
      finalAmount: _double(json['final_amount']),
      listing: MarketplaceListing.fromJson(_map(json['listing'])),
      qrPayload: _map(json['qr_payload']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  bool get needsFarmerConfirmation =>
      status.toLowerCase() == 'final_rate_pending';

  bool get canReceive {
    final value = status.toLowerCase();
    return value == 'awaiting_arrival' || value == 'dispatched';
  }

  bool get canProposeFinalRate {
    final value = status.toLowerCase();
    return value == 'arrived_quarantine' ||
        value == 'grading' ||
        value == 'final_rate_pending';
  }

  bool get canAcceptProcurement =>
      status.toLowerCase() == 'final_rate_confirmed';
}

class FpcProfitSummary {
  final double acquisitionCost;
  final double operatingCost;
  final double revenue;
  final double netMargin;

  const FpcProfitSummary({
    required this.acquisitionCost,
    required this.operatingCost,
    required this.revenue,
    required this.netMargin,
  });

  factory FpcProfitSummary.fromJson(Map<String, dynamic> json) {
    return FpcProfitSummary(
      acquisitionCost: _double(json['acquisition_cost']) ?? 0,
      operatingCost: _double(json['operating_cost']) ?? 0,
      revenue: _double(json['revenue']) ?? 0,
      netMargin: _double(json['net_margin']) ?? 0,
    );
  }

  static const zero = FpcProfitSummary(
    acquisitionCost: 0,
    operatingCost: 0,
    revenue: 0,
    netMargin: 0,
  );
}

class ApmcMarketRate {
  final String id;
  final String state;
  final String district;
  final String market;
  final String commodity;
  final String variety;
  final String grade;
  final DateTime? arrivalDate;
  final double minPrice;
  final double maxPrice;
  final double modalPrice;
  final DateTime? syncedAt;

  const ApmcMarketRate({
    required this.id,
    required this.state,
    required this.district,
    required this.market,
    required this.commodity,
    required this.variety,
    required this.grade,
    required this.minPrice,
    required this.maxPrice,
    required this.modalPrice,
    this.arrivalDate,
    this.syncedAt,
  });

  factory ApmcMarketRate.fromJson(Map<String, dynamic> json) {
    return ApmcMarketRate(
      id: _text(json['id']),
      state: _text(json['state']),
      district: _text(json['district']),
      market: _text(json['market']),
      commodity: _text(json['commodity']),
      variety: _text(json['variety']),
      grade: _text(json['grade']),
      arrivalDate: _date(json['arrival_date']),
      minPrice: _double(json['min_price']) ?? 0,
      maxPrice: _double(json['max_price']) ?? 0,
      modalPrice: _double(json['modal_price']) ?? 0,
      syncedAt: _date(json['synced_at']),
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

bool _bool(Object? raw) {
  if (raw is bool) return raw;
  final text = _text(raw).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map(_text)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
