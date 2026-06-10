class MapTileCacheService {
  static const defaultTileUrl = '';
  static const fallbackCenterLatitude = 19.7515;
  static const fallbackCenterLongitude = 75.7139;
  static const statusUnknown = 'unknown';
  static const statusWaitingForInternet = 'waiting_for_internet';
  static const statusDownloading = 'downloading';
  static const statusReady = 'ready';
  static const statusPartial = 'partial';
  static const statusFailed = 'failed';

  static const coreRegions = [
    OfflineMapRegion(
      id: 'nashik',
      label: 'Nashik',
      latitude: 19.9975,
      longitude: 73.7898,
      radiusKm: 35,
    ),
    OfflineMapRegion(
      id: 'akole',
      label: 'Akole',
      latitude: 19.5406,
      longitude: 74.0054,
      radiusKm: 28,
    ),
    OfflineMapRegion(
      id: 'sangamner',
      label: 'Sangamner',
      latitude: 19.5678,
      longitude: 74.2115,
      radiusKm: 28,
    ),
  ];

  Future<String?> localTileTemplate() async => null;

  Future<List<MapTileCacheSnapshot>> loadRegionSnapshots() async => const [];

  Future<void> prefetchCoreRegions({
    String urlTemplate = defaultTileUrl,
    bool force = false,
  }) async {}

  Future<void> prefetchWideRegion({
    required double latitude,
    required double longitude,
    String urlTemplate = defaultTileUrl,
    bool force = false,
  }) async {}

  Future<MapTileCacheSnapshot> prefetchRegion({
    required OfflineMapRegion region,
    String urlTemplate = defaultTileUrl,
    bool force = false,
    List<PrefetchPlan> plans = defaultPrefetchPlans,
  }) async {
    return MapTileCacheSnapshot(
      regionId: region.id,
      label: region.label,
      latitude: region.latitude,
      longitude: region.longitude,
      radiusKm: region.radiusKm,
      zooms: plans.map((plan) => plan.zoom).toList(),
      status: statusUnknown,
      updatedAt: null,
      completedTiles: 0,
      totalTiles: 0,
    );
  }
}

const defaultPrefetchPlans = [
  PrefetchPlan(zoom: 12, radiusKm: 40),
  PrefetchPlan(zoom: 13, radiusKm: 25),
  PrefetchPlan(zoom: 14, radiusKm: 12),
  PrefetchPlan(zoom: 15, radiusKm: 6),
  PrefetchPlan(zoom: 16, radiusKm: 3),
  PrefetchPlan(zoom: 17, radiusKm: 1.5),
];

class OfflineMapRegion {
  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusKm;

  const OfflineMapRegion({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });
}

class MapTileCacheSnapshot {
  final String regionId;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final List<int> zooms;
  final String status;
  final DateTime? updatedAt;
  final int completedTiles;
  final int totalTiles;
  final int downloadedTiles;
  final int failedTiles;
  final String? error;

  const MapTileCacheSnapshot({
    required this.regionId,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.zooms,
    required this.status,
    required this.updatedAt,
    required this.completedTiles,
    required this.totalTiles,
    this.downloadedTiles = 0,
    this.failedTiles = 0,
    this.error,
  });
}

class PrefetchPlan {
  final int zoom;
  final double radiusKm;

  const PrefetchPlan({required this.zoom, required this.radiusKm});
}
