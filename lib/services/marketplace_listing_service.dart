import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_listing.dart';

class MarketplaceListingException implements Exception {
  final String message;
  final String code;

  const MarketplaceListingException(this.message, {this.code = ''});

  @override
  String toString() => message;
}

class MarketplaceListingService {
  SupabaseClient get _client => Supabase.instance.client;

  String get currentUserId => _client.auth.currentUser?.id ?? '';

  Future<List<MarketplaceListing>> listFarmerListings() async {
    final data = await _invoke({'action': 'list_farmer'});
    return _listingsFrom(data);
  }

  Future<List<MarketplaceListing>> listFpcListings() async {
    final data = await _invoke({'action': 'list_sell'});
    return _listingsFrom(data);
  }

  Future<List<MarketplaceListing>> listSellListings() => listFpcListings();

  Future<List<MarketplaceInputProduct>> listBuyProducts() async {
    final data = await _invoke({'action': 'list_buy'});
    final rows = data['products'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) =>
              MarketplaceInputProduct.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<MarketplaceNegotiation>> listNegotiations({
    required bool fpcWorkspace,
  }) async {
    final data = await _invoke({
      'action': 'list_negotiations',
      'workspace': fpcWorkspace ? 'fpc_admin' : 'farmer',
    });
    final rows = data['negotiations'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) =>
              MarketplaceNegotiation.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<List<MarketplaceOrder>> listOrders({
    required bool fpcWorkspace,
  }) async {
    final data = await _invoke({
      'action': 'list_orders',
      'workspace': fpcWorkspace ? 'fpc_admin' : 'farmer',
    });
    final rows = data['orders'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => MarketplaceOrder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> counterOffer({
    required String requestId,
    required bool fpcWorkspace,
    required double pricePerUnit,
    String message = '',
  }) async {
    await _invoke({
      'action': 'counter_offer',
      'requestId': requestId,
      'actorRole': fpcWorkspace ? 'fpc_admin' : 'farmer',
      'pricePerUnit': pricePerUnit,
      'message': message,
    });
  }

  Future<MarketplaceOrder> acceptOffer({
    required String requestId,
    required bool fpcWorkspace,
    String offerId = '',
  }) async {
    final data = await _invoke({
      'action': 'accept_offer',
      'requestId': requestId,
      'offerId': offerId,
      'actorRole': fpcWorkspace ? 'fpc_admin' : 'farmer',
    });
    return _orderFrom(data);
  }

  Future<MarketplaceOrder> recordArrival({
    required String orderId,
    required double quantityKg,
    required String grade,
    double? moisturePercent,
    String analysisId = '',
    Map<String, dynamic> tracePayload = const {},
  }) async {
    final data = await _invoke({
      'action': 'record_arrival',
      'orderId': orderId,
      'quantityKg': quantityKg,
      'grade': grade,
      'moisturePercent': moisturePercent,
      'analysisId': analysisId,
      'tracePayload': tracePayload,
    });
    return _orderFrom(data);
  }

  Future<MarketplaceOrder> proposeFinalRate({
    required String orderId,
    required double finalRate,
  }) async {
    final data = await _invoke({
      'action': 'propose_final_rate',
      'orderId': orderId,
      'finalRate': finalRate,
    });
    return _orderFrom(data);
  }

  Future<MarketplaceOrder> confirmFinalRate(String orderId) async {
    final data = await _invoke({
      'action': 'confirm_final_rate',
      'orderId': orderId,
    });
    return _orderFrom(data);
  }

  Future<MarketplaceOrder> acceptProcurement(String orderId) async {
    final data = await _invoke({
      'action': 'accept_procurement',
      'orderId': orderId,
    });
    return _orderFrom(data);
  }

  Future<void> recordCost({
    required String orderId,
    required String category,
    required double amount,
    required String description,
  }) async {
    await _invoke({
      'action': 'record_cost',
      'marketplaceOrderId': orderId,
      'category': category,
      'amount': amount,
      'description': description,
    });
  }

  Future<FpcProfitSummary> profitSummary() async {
    final data = await _invoke({'action': 'profit_summary'});
    final summary = data['summary'];
    if (summary is Map<String, dynamic>) {
      return FpcProfitSummary.fromJson(summary);
    }
    if (summary is Map) {
      return FpcProfitSummary.fromJson(Map<String, dynamic>.from(summary));
    }
    return FpcProfitSummary.zero;
  }

  Future<MarketplaceListing> listingDetail(String listingId) async {
    final data = await _invoke({
      'action': 'listing_detail',
      'listingId': listingId,
    });
    return _listingFrom(data, 'listing');
  }

  Future<MarketplaceListing> createOrUpdateFromInventory({
    required String inventoryItemId,
    String inventoryId = '',
    String title = '',
    double? askingPricePerUnit,
    String listingNote = '',
    String description = '',
    String locationLabel = '',
    String priceUnit = '',
    String status = 'listed',
  }) async {
    final data = await _invoke({
      'action': 'create_or_update',
      'inventoryItemId': inventoryItemId,
      'inventoryId': inventoryId,
      'title': title,
      'askingPricePerUnit': askingPricePerUnit,
      'listingNote': listingNote,
      'description': description,
      'locationLabel': locationLabel,
      'priceUnit': priceUnit,
      'status': status,
    });
    return _listingFrom(data, 'listing');
  }

  Future<void> markInterest({
    required String listingId,
    String message = '',
  }) async {
    await _invoke({
      'action': 'mark_interest',
      'listingId': listingId,
      'message': message,
    });
  }

  Future<void> createPurchaseRequest({
    String listingId = '',
    String productId = '',
    String productName = '',
    double? quantity,
    String unit = 'unit',
    double? proposedPrice,
    String message = '',
  }) async {
    await _invoke({
      'action': 'create_purchase_request',
      'listingId': listingId,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unit': unit,
      'proposedPrice': proposedPrice,
      'message': message,
    });
  }

  Future<MarketplaceListing> updateListing({
    required String listingId,
    String? title,
    String? description,
    double? askingPricePerUnit,
    String? locationLabel,
  }) async {
    final data = await _invoke({
      'action': 'update_listing',
      'listingId': listingId,
      'title': ?title,
      'description': ?description,
      'askingPricePerUnit': ?askingPricePerUnit,
      'locationLabel': ?locationLabel,
    });
    return _listingFrom(data, 'listing');
  }

  Future<MarketplaceListing> updateStatus({
    required String listingId,
    required String status,
    String reason = '',
  }) async {
    final data = await _invoke({
      'action': 'update_status',
      'listingId': listingId,
      'status': status,
      'reason': reason,
    });
    return _listingFrom(data, 'listing');
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    try {
      final response = await _client.functions.invoke(
        'marketplace-listings',
        headers: _functionAuthHeaders(),
        body: body,
      );
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw _exceptionFrom(data);
      }
      return data;
    } on FunctionException catch (error) {
      throw _exceptionFrom(
        _responseMap(error.details),
        fallbackStatus: error.status,
      );
    }
  }

  List<MarketplaceListing> _listingsFrom(Map<String, dynamic> data) {
    final rows = data['listings'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => MarketplaceListing.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  MarketplaceListing _listingFrom(Map<String, dynamic> data, String key) {
    final listing = data[key];
    if (listing is Map<String, dynamic>) {
      return MarketplaceListing.fromJson(listing);
    }
    if (listing is Map) {
      return MarketplaceListing.fromJson(Map<String, dynamic>.from(listing));
    }
    throw const MarketplaceListingException('Marketplace listing not saved.');
  }

  MarketplaceOrder _orderFrom(Map<String, dynamic> data) {
    final order = data['order'];
    if (order is Map<String, dynamic>) {
      return MarketplaceOrder.fromJson(order);
    }
    if (order is Map) {
      return MarketplaceOrder.fromJson(Map<String, dynamic>.from(order));
    }
    throw const MarketplaceListingException('Marketplace order not saved.');
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
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  MarketplaceListingException _exceptionFrom(
    Map<String, dynamic> data, {
    int? fallbackStatus,
  }) {
    final code = '${data['code'] ?? ''}'.trim();
    final serverMessage = '${data['error'] ?? data['message'] ?? ''}'.trim();
    final message = switch (code) {
      'inventory_item_required' || 'inventory_item_not_found' =>
        'This inventory item is not synced for this farmer. Refresh Inventory and try again.',
      'listing_quantity_required' =>
        'Add a valid quantity to this inventory item before listing it.',
      'missing_auth_token' || 'invalid_auth_token' =>
        'Your farmer session expired. Login again and retry the listing.',
      'marketplace_listings_failed' =>
        'The listing could not be saved. Check its inventory details and try again.',
      _ when serverMessage.isNotEmpty => serverMessage,
      _ when fallbackStatus == 401 =>
        'Your farmer session expired. Login again and retry.',
      _ => 'Marketplace is temporarily unavailable. Please try again.',
    };
    return MarketplaceListingException(message, code: code);
  }
}
