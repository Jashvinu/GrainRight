import 'farm_health_score.dart';

class FpcCoordinate {
  final double latitude;
  final double longitude;

  const FpcCoordinate(this.latitude, this.longitude);
}

class FpcFarmMapPoint {
  final String linkId;
  final String farmerName;
  final String farmName;
  final String crop;
  final String village;
  final double latitude;
  final double longitude;
  final String readiness;
  final bool needsReview;

  const FpcFarmMapPoint({
    required this.linkId,
    required this.farmerName,
    required this.farmName,
    required this.crop,
    required this.village,
    required this.latitude,
    required this.longitude,
    required this.readiness,
    required this.needsReview,
  });

  factory FpcFarmMapPoint.fromJson(Map<String, dynamic> json) {
    return FpcFarmMapPoint(
      linkId: _text(json['link_id']),
      farmerName: _text(json['farmer_name'], 'Farmer'),
      farmName: _text(json['farm_name'], 'Farm'),
      crop: _text(json['crop']),
      village: _text(json['village']),
      latitude: _number(json['centroid_lat']),
      longitude: _number(json['centroid_lng']),
      readiness: _text(json['readiness'], 'not_planned'),
      needsReview: json['needs_review'] == true,
    );
  }

  factory FpcFarmMapPoint.fromFarm(FpcFarmWorkCard farm) {
    return FpcFarmMapPoint(
      linkId: farm.linkId,
      farmerName: farm.farmerName,
      farmName: farm.farmName,
      crop: farm.crop,
      village: farm.village,
      latitude: farm.centroidLatitude!,
      longitude: farm.centroidLongitude!,
      readiness: farm.readiness,
      needsReview: farm.needsReview,
    );
  }

  bool get isReady => {
    'ready',
    'harvest_ready',
    'ready_to_harvest',
    'ready for harvest',
  }.contains(readiness.toLowerCase());
}

class FpcOperatingCluster {
  final String id;
  final String name;
  final String district;
  final String state;
  final String preferredApmcMarket;
  final bool active;
  final int farmCount;
  final int readyCount;
  final double expectedQuantityKg;

  const FpcOperatingCluster({
    required this.id,
    required this.name,
    required this.district,
    required this.state,
    required this.preferredApmcMarket,
    required this.active,
    required this.farmCount,
    required this.readyCount,
    required this.expectedQuantityKg,
  });

  factory FpcOperatingCluster.fromJson(Map<String, dynamic> json) {
    return FpcOperatingCluster(
      id: _text(json['id']),
      name: _text(json['name']),
      district: _text(json['district']),
      state: _text(json['state'], 'Maharashtra'),
      preferredApmcMarket: _text(json['preferred_apmc_market']),
      active: json['active'] != false,
      farmCount: _integer(json['farm_count']),
      readyCount: _integer(json['ready_count']),
      expectedQuantityKg: _number(json['expected_quantity_kg']),
    );
  }
}

class FpcGradeCount {
  final String grade;
  final int count;

  const FpcGradeCount({required this.grade, required this.count});

  factory FpcGradeCount.fromJson(Map<String, dynamic> json) {
    return FpcGradeCount(
      grade: normalizeFpcGrade(json['grade']),
      count: _integer(json['count']),
    );
  }
}

class FpcProcurementSummary {
  final int networkFarms;
  final int readyFarms;
  final double expectedProcurementKg;
  final int openLots;
  final int needsReview;
  final int? healthAverage;
  final int healthCoverage;
  final List<FpcGradeCount> gradeMix;

  const FpcProcurementSummary({
    required this.networkFarms,
    required this.readyFarms,
    required this.expectedProcurementKg,
    required this.openLots,
    required this.needsReview,
    required this.healthAverage,
    required this.healthCoverage,
    required this.gradeMix,
  });

  factory FpcProcurementSummary.fromJson(Map<String, dynamic> json) {
    return FpcProcurementSummary(
      networkFarms: _integer(json['network_farms']),
      readyFarms: _integer(json['ready_farms']),
      expectedProcurementKg: _number(json['expected_procurement_kg']),
      openLots: _integer(json['open_lots']),
      needsReview: _integer(json['needs_review']),
      healthAverage: _nullableInteger(json['health_average']),
      healthCoverage: _integer(json['health_coverage']),
      gradeMix: _mapList(json['grade_mix'], FpcGradeCount.fromJson),
    );
  }

  static const empty = FpcProcurementSummary(
    networkFarms: 0,
    readyFarms: 0,
    expectedProcurementKg: 0,
    openLots: 0,
    needsReview: 0,
    healthAverage: null,
    healthCoverage: 0,
    gradeMix: [],
  );
}

class FpcFarmWorkCard {
  final String linkId;
  final String? clusterId;
  final String farmerId;
  final String farmerName;
  final String farmerPhone;
  final String farmId;
  final String farmName;
  final String village;
  final String crop;
  final String kycStatus;
  final double? areaAcres;
  final DateTime? sowingDate;
  final String currentStatus;
  final String currentStatusStage;
  final List<List<FpcCoordinate>> polygons;
  final double? centroidLatitude;
  final double? centroidLongitude;
  final String? harvestPlanId;
  final DateTime? expectedHarvestDate;
  final double? expectedQuantityKg;
  final String expectedGrade;
  final String readiness;
  final bool isReady;
  final String latestGrade;
  final DateTime? latestGradeAt;
  final bool needsReview;
  final int openLots;
  final int? healthScore;
  final DateTime? snapshotDate;
  final double? waterStressScore;
  final double? weatherRisk;
  final double? diseaseRisk;
  final String? photoUrl;
  final DateTime? dataUpdatedAt;

  const FpcFarmWorkCard({
    required this.linkId,
    required this.clusterId,
    required this.farmerId,
    required this.farmerName,
    required this.farmerPhone,
    required this.farmId,
    required this.farmName,
    required this.village,
    required this.crop,
    required this.kycStatus,
    required this.areaAcres,
    required this.sowingDate,
    required this.currentStatus,
    required this.currentStatusStage,
    required this.polygons,
    required this.centroidLatitude,
    required this.centroidLongitude,
    required this.harvestPlanId,
    required this.expectedHarvestDate,
    required this.expectedQuantityKg,
    required this.expectedGrade,
    required this.readiness,
    required this.isReady,
    required this.latestGrade,
    required this.latestGradeAt,
    required this.needsReview,
    required this.openLots,
    required this.healthScore,
    required this.snapshotDate,
    required this.waterStressScore,
    required this.weatherRisk,
    required this.diseaseRisk,
    required this.photoUrl,
    required this.dataUpdatedAt,
  });

  factory FpcFarmWorkCard.fromJson(Map<String, dynamic> json) {
    final waterStress = _nullableNumber(json['water_stress_score']);
    final weatherRisk = _nullableNumber(json['weather_risk']);
    final diseaseRisk = _nullableNumber(json['disease_risk']);
    return FpcFarmWorkCard(
      linkId: _text(json['link_id']),
      clusterId: _nullableText(json['cluster_id']),
      farmerId: _text(json['farmer_id']),
      farmerName: _text(json['farmer_name'], 'Farmer'),
      farmerPhone: _text(json['farmer_phone']),
      farmId: _text(json['farm_id']),
      farmName: _text(json['farm_name'], 'Farm'),
      village: _text(json['village']),
      crop: _text(json['crop']),
      kycStatus: _text(json['kyc_status']),
      areaAcres: _nullableNumber(json['area_acres']),
      sowingDate: _date(json['sowing_date']),
      currentStatus: _text(json['current_status']),
      currentStatusStage: _text(json['current_status_stage']),
      polygons: _parsePolygons(json['geometry']),
      centroidLatitude: _nullableNumber(json['centroid_lat']),
      centroidLongitude: _nullableNumber(json['centroid_lng']),
      harvestPlanId: _nullableText(json['harvest_plan_id']),
      expectedHarvestDate: _date(json['expected_harvest_date']),
      expectedQuantityKg: _nullableNumber(json['expected_quantity_kg']),
      expectedGrade: _text(json['expected_grade']),
      readiness: _text(json['readiness'], 'not_planned'),
      isReady: json['is_ready'] == true,
      latestGrade: normalizeFpcGrade(json['latest_grade']),
      latestGradeAt: _date(json['latest_grade_at']),
      needsReview: json['needs_review'] == true,
      openLots: _integer(json['open_lots']),
      healthScore:
          _nullableInteger(json['health_score']) ??
          FarmHealthScore.calculate(
            waterStress: waterStress,
            weatherRisk: weatherRisk,
            diseaseRisk: diseaseRisk,
          ),
      snapshotDate: _date(json['snapshot_date']),
      waterStressScore: waterStress,
      weatherRisk: weatherRisk,
      diseaseRisk: diseaseRisk,
      photoUrl: _nullableText(json['photo_url']),
      dataUpdatedAt: _date(json['data_updated_at']),
    );
  }

  bool get hasMapLocation =>
      centroidLatitude != null && centroidLongitude != null;

  bool get hasHealthData => healthScore != null;

  bool get isDataStale {
    final updated = dataUpdatedAt;
    return updated != null &&
        DateTime.now().difference(updated.toLocal()) >
            const Duration(hours: 48);
  }
}

class FpcSeedRequestSummary {
  final int total;
  final int submitted;
  final int awaitingFarmer;
  final int readyToIssue;
  final int inDelivery;
  final int completed;

  const FpcSeedRequestSummary({
    required this.total,
    required this.submitted,
    required this.awaitingFarmer,
    required this.readyToIssue,
    required this.inDelivery,
    required this.completed,
  });

  const FpcSeedRequestSummary.empty()
    : total = 0,
      submitted = 0,
      awaitingFarmer = 0,
      readyToIssue = 0,
      inDelivery = 0,
      completed = 0;

  factory FpcSeedRequestSummary.fromJson(Map<String, dynamic> json) {
    return FpcSeedRequestSummary(
      total: _integer(json['total']),
      submitted: _integer(json['submitted']),
      awaitingFarmer: _integer(json['awaiting_farmer']),
      readyToIssue: _integer(json['ready_to_issue']),
      inDelivery: _integer(json['in_delivery']),
      completed: _integer(json['completed']),
    );
  }

  int get actionRequired => submitted + readyToIssue;
}

class FpcProcurementDashboardSnapshot {
  final String fpcId;
  final String? selectedClusterId;
  final DateTime generatedAt;
  final int unassignedFarmCount;
  final List<FpcOperatingCluster> clusters;
  final FpcProcurementSummary summary;
  final FpcSeedRequestSummary seedRequests;
  final List<FpcFarmWorkCard> farms;

  const FpcProcurementDashboardSnapshot({
    required this.fpcId,
    required this.selectedClusterId,
    required this.generatedAt,
    required this.unassignedFarmCount,
    required this.clusters,
    required this.summary,
    this.seedRequests = const FpcSeedRequestSummary.empty(),
    required this.farms,
  });

  factory FpcProcurementDashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final seedRequests = json['seed_requests'];
    return FpcProcurementDashboardSnapshot(
      fpcId: _text(json['fpc_id']),
      selectedClusterId: _nullableText(json['selected_cluster_id']),
      generatedAt: _date(json['generated_at']) ?? DateTime.now(),
      unassignedFarmCount: _integer(json['unassigned_farm_count']),
      clusters: _mapList(json['clusters'], FpcOperatingCluster.fromJson),
      summary: summary is Map
          ? FpcProcurementSummary.fromJson(Map<String, dynamic>.from(summary))
          : FpcProcurementSummary.empty,
      seedRequests: seedRequests is Map
          ? FpcSeedRequestSummary.fromJson(
              Map<String, dynamic>.from(seedRequests),
            )
          : const FpcSeedRequestSummary.empty(),
      farms: _mapList(json['farms'], FpcFarmWorkCard.fromJson),
    );
  }

  FpcOperatingCluster? get selectedCluster {
    final selected = selectedClusterId;
    if (selected == null) return null;
    for (final cluster in clusters) {
      if (cluster.id == selected) return cluster;
    }
    return null;
  }
}

class FpcFarmQueuePage {
  final List<FpcFarmWorkCard> farms;
  final bool hasMore;
  final int nextOffset;

  const FpcFarmQueuePage({
    required this.farms,
    required this.hasMore,
    required this.nextOffset,
  });

  factory FpcFarmQueuePage.fromJson(Map<String, dynamic> json) {
    return FpcFarmQueuePage(
      farms: _mapList(json['farms'], FpcFarmWorkCard.fromJson),
      hasMore: json['has_more'] == true,
      nextOffset: _integer(json['next_offset']),
    );
  }
}

String normalizeFpcGrade(Object? raw) {
  final original = _text(raw);
  if (original.isEmpty || original.toLowerCase() == 'not graded') {
    return 'Not graded';
  }
  final normalized = original.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  if (const {'a', 'gradea', 'premium', 'premiumgrade'}.contains(normalized)) {
    return 'Grade A';
  }
  if (const {'b', 'gradeb', 'standard', 'standardgrade'}.contains(normalized)) {
    return 'Grade B';
  }
  if (const {
    'c',
    'gradec',
    'commercial',
    'commercialgrade',
  }.contains(normalized)) {
    return 'Grade C';
  }
  return original;
}

List<List<FpcCoordinate>> _parsePolygons(Object? raw) {
  if (raw is! Map) return const [];
  final geometry = Map<String, dynamic>.from(raw);
  final type = _text(geometry['type']);
  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return const [];
  if (type == 'Polygon') {
    return coordinates.isEmpty
        ? const []
        : [_coordinateRing(coordinates.first)];
  }
  if (type == 'MultiPolygon') {
    return coordinates
        .whereType<List>()
        .where((polygon) => polygon.isNotEmpty)
        .map((polygon) => _coordinateRing(polygon.first))
        .where((ring) => ring.length >= 3)
        .toList(growable: false);
  }
  return const [];
}

List<FpcCoordinate> _coordinateRing(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<List>()
      .where((pair) => pair.length >= 2)
      .map((pair) => FpcCoordinate(_number(pair[1]), _number(pair[0])))
      .toList(growable: false);
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) factory) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => factory(Map<String, dynamic>.from(row)))
      .toList(growable: false);
}

String _text(Object? raw, [String fallback = '']) {
  final text = raw == null ? '' : '$raw'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

String? _nullableText(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : text;
}

double _number(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw)) ?? 0;
}

double? _nullableNumber(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw));
}

int _integer(Object? raw) => _nullableInteger(raw) ?? 0;

int? _nullableInteger(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(_text(raw));
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
