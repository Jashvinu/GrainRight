import '../models/fpc_dashboard_summary.dart';
import 'fpc_procurement_service.dart';
import 'grain_grading_service.dart';
import 'marketplace_listing_service.dart';

class FpcDashboardService {
  final FpcProcurementService _procurementService;
  final MarketplaceListingService _marketplaceService;
  final GrainGradingService _gradingService;

  FpcDashboardService({
    FpcProcurementService? procurementService,
    MarketplaceListingService? marketplaceService,
    GrainGradingService? gradingService,
  }) : _procurementService = procurementService ?? FpcProcurementService(),
       _marketplaceService = marketplaceService ?? MarketplaceListingService(),
       _gradingService = gradingService ?? GrainGradingService();

  Future<FpcDashboardSummary> load() async {
    final procurementFuture = _load(
      _procurementService.fetchRecords,
      'Could not load procurement statistics.',
    );
    final reviewFuture = _load(
      _gradingService.fetchReviewJobs,
      'Could not load grading reviews.',
    );
    final listingFuture = _load(
      _marketplaceService.listFpcListings,
      'Could not load marketplace listings.',
    );

    final procurement = await procurementFuture;
    final reviews = await reviewFuture;
    final listings = await listingFuture;

    final procurementRecords = procurement.value;
    return FpcDashboardSummary(
      farmers: procurementRecords == null && listings.value == null
          ? FpcDashboardMetric.error(procurement.error ?? listings.error)
          : FpcDashboardMetric.value(
              <String>{
                ...?procurementRecords?.map((record) => record.farmerId.trim()),
                ...?listings.value?.map((listing) => listing.farmerId.trim()),
              }.where((id) => id.isNotEmpty).toSet().length,
            ),
      lots: procurementRecords == null
          ? FpcDashboardMetric.error(procurement.error)
          : FpcDashboardMetric.value(procurementRecords.length),
      reviews: reviews.value == null
          ? FpcDashboardMetric.error(reviews.error)
          : FpcDashboardMetric.value(reviews.value!.length),
      listings: listings.value == null
          ? FpcDashboardMetric.error(listings.error)
          : FpcDashboardMetric.value(
              listings.value!.where((listing) => listing.isActive).length,
            ),
      procurementRecords: procurementRecords ?? const [],
      reviewJobs: reviews.value ?? const [],
      marketplaceListings: listings.value ?? const [],
    );
  }

  void dispose() => _gradingService.dispose();

  Future<_LoadResult<T>> _load<T>(
    Future<T> Function() loader,
    String fallbackError,
  ) async {
    try {
      return _LoadResult(value: await loader());
    } catch (error) {
      final message = error.toString().trim();
      return _LoadResult(error: message.isEmpty ? fallbackError : message);
    }
  }
}

class _LoadResult<T> {
  final T? value;
  final String? error;

  const _LoadResult({this.value, this.error});
}
