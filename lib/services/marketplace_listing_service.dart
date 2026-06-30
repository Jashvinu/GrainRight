import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_listing.dart';

class MarketplaceListingException implements Exception {
  final String message;

  const MarketplaceListingException(this.message);

  @override
  String toString() => message;
}

class MarketplaceListingService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<MarketplaceListing>> listFarmerListings() async {
    final data = await _invoke({'action': 'list_farmer'});
    return _listingsFrom(data);
  }

  Future<List<MarketplaceListing>> listFpcListings() async {
    final data = await _invoke({'action': 'list_fpc'});
    return _listingsFrom(data);
  }

  Future<MarketplaceListing> createOrUpdateFromInventory({
    required String inventoryItemId,
    String inventoryId = '',
    double? askingPricePerUnit,
    String listingNote = '',
    String status = 'active',
  }) async {
    final data = await _invoke({
      'action': 'create_or_update',
      'inventoryItemId': inventoryItemId,
      'inventoryId': inventoryId,
      'askingPricePerUnit': askingPricePerUnit,
      'listingNote': listingNote,
      'status': status,
    });
    final listing = data['listing'];
    if (listing is Map<String, dynamic>) {
      return MarketplaceListing.fromJson(listing);
    }
    if (listing is Map) {
      return MarketplaceListing.fromJson(Map<String, dynamic>.from(listing));
    }
    throw const MarketplaceListingException('Marketplace listing not saved.');
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

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final response = await _client.functions.invoke(
      'marketplace-listings',
      headers: _functionAuthHeaders(),
      body: body,
    );
    final data = _responseMap(response.data);
    if (data['success'] == false) {
      throw MarketplaceListingException(
        '${data['error'] ?? 'Marketplace request failed.'}',
      );
    }
    return data;
  }

  List<MarketplaceListing> _listingsFrom(Map<String, dynamic> data) {
    final rows = data['listings'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => MarketplaceListing.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
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
}
