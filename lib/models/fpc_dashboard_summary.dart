import '../models/marketplace_listing.dart';
import '../services/fpc_procurement_service.dart';
import '../services/grain_grading_service.dart';

class FpcDashboardMetric {
  final int? value;
  final String? error;

  const FpcDashboardMetric.value(int this.value) : error = null;

  const FpcDashboardMetric.error(this.error) : value = null;

  bool get failed => error != null;
}

class FpcDashboardSummary {
  final FpcDashboardMetric farmers;
  final FpcDashboardMetric lots;
  final FpcDashboardMetric reviews;
  final FpcDashboardMetric listings;
  final List<FpcProcurementRecord> procurementRecords;
  final List<GradingReviewJob> reviewJobs;
  final List<MarketplaceListing> marketplaceListings;

  const FpcDashboardSummary({
    required this.farmers,
    required this.lots,
    required this.reviews,
    required this.listings,
    this.procurementRecords = const [],
    this.reviewJobs = const [],
    this.marketplaceListings = const [],
  });

  factory FpcDashboardSummary.fromData({
    required List<FpcProcurementRecord> procurementRecords,
    required List<GradingReviewJob> reviewJobs,
    required List<MarketplaceListing> marketplaceListings,
  }) {
    final farmerIds = <String>{
      ...procurementRecords.map((record) => record.farmerId.trim()),
      ...marketplaceListings.map((listing) => listing.farmerId.trim()),
    }.where((id) => id.isNotEmpty).toSet();
    return FpcDashboardSummary(
      farmers: FpcDashboardMetric.value(farmerIds.length),
      lots: FpcDashboardMetric.value(procurementRecords.length),
      reviews: FpcDashboardMetric.value(reviewJobs.length),
      listings: FpcDashboardMetric.value(
        marketplaceListings.where((listing) => listing.isActive).length,
      ),
      procurementRecords: procurementRecords,
      reviewJobs: reviewJobs,
      marketplaceListings: marketplaceListings,
    );
  }

  int get interestedListings => marketplaceListings
      .where((listing) => listing.isActive && listing.interestedByMe)
      .length;

  double get receivedQuantityKg => procurementRecords.fold<double>(
    0,
    (total, record) => total + (record.quantityKg ?? 0),
  );

  double get receivedValue => procurementRecords.fold<double>(
    0,
    (total, record) => total + (record.totalValue ?? 0),
  );

  List<MarketplaceListing> get activeMarketplaceListings => marketplaceListings
      .where((listing) => listing.isActive)
      .toList(growable: false);

  bool get hasErrors =>
      farmers.failed || lots.failed || reviews.failed || listings.failed;
}
