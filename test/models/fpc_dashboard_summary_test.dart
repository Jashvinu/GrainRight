import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/fpc_account_identity.dart';
import 'package:kalsubai_farms/models/fpc_dashboard_summary.dart';
import 'package:kalsubai_farms/models/marketplace_listing.dart';
import 'package:kalsubai_farms/services/fpc_procurement_service.dart';
import 'package:kalsubai_farms/services/grain_grading_service.dart';

void main() {
  group('FpcAccountIdentity', () {
    test('prefers organization name and trusted role metadata', () {
      final account = FpcAccountIdentity.fromMetadata(
        userMetadata: {
          'organization_name': 'Sahyadri FPC',
          'display_name': 'Asha Patil',
          'role': 'farmer',
        },
        appMetadata: {'role': 'fpc'},
        email: 'asha@example.com',
      );

      expect(account.name, 'Sahyadri FPC');
      expect(account.roleLabel, 'FPC');
      expect(account.email, 'asha@example.com');
    });

    test('falls back to display name and then workspace label', () {
      final named = FpcAccountIdentity.fromMetadata(
        userMetadata: {'display_name': 'Asha Patil'},
      );
      final empty = FpcAccountIdentity.fromMetadata();

      expect(named.name, 'Asha Patil');
      expect(empty.name, 'FPC workspace');
      expect(empty.email, 'FPC account');
    });
  });

  test('dashboard summary counts unique farmers and active listings', () {
    final summary = FpcDashboardSummary.fromData(
      procurementRecords: [
        _record(id: '1', farmerId: 'FMR-1'),
        _record(id: '2', farmerId: 'FMR-1'),
        _record(id: '3', farmerId: 'FMR-2'),
        _record(id: '4', farmerId: ''),
      ],
      reviewJobs: [_review('review-1'), _review('review-2')],
      marketplaceListings: [
        _listing('listing-1', 'active', interestedByMe: true),
        _listing('listing-2', 'closed'),
        _listing('listing-3', 'ACTIVE'),
      ],
    );

    expect(summary.farmers.value, 2);
    expect(summary.lots.value, 4);
    expect(summary.reviews.value, 2);
    expect(summary.listings.value, 2);
    expect(summary.interestedListings, 1);
    expect(summary.activeMarketplaceListings, hasLength(2));
    expect(summary.procurementRecords, hasLength(4));
    expect(summary.hasErrors, isFalse);
  });
}

FpcProcurementRecord _record({required String id, required String farmerId}) {
  return FpcProcurementRecord(
    id: id,
    batchId: 'B-$id',
    farmerId: farmerId,
    farmId: 'FARM-$id',
    customerName: 'Farmer',
    cropType: 'Ragi',
    variety: 'Local',
    grade: 'A',
    deliveryStatus: 'received',
  );
}

GradingReviewJob _review(String id) {
  return GradingReviewJob(
    id: id,
    batchId: 'B-$id',
    farmerId: 'FMR-1',
    farmId: 'FARM-1',
    cropType: 'Ragi',
    variety: 'Local',
    reviewStatus: 'pending',
    status: 'complete',
  );
}

MarketplaceListing _listing(
  String id,
  String status, {
  bool interestedByMe = false,
}) {
  return MarketplaceListing(
    id: id,
    inventoryItemId: 'INV-$id',
    farmerUserId: 'USER-1',
    farmerPhone: '9876543210',
    farmerId: 'FMR-1',
    farmId: 'FARM-1',
    farmName: 'Main farm',
    batchId: 'B-$id',
    productCategory: 'crop_lot',
    productName: 'Ragi',
    crop: 'Ragi',
    variety: 'Local',
    quantity: 100,
    unit: 'kg',
    grade: 'A',
    status: status,
    interestCount: 0,
    interestedByMe: interestedByMe,
    interestStatus: '',
  );
}
