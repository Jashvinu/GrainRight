import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';
import 'package:kalsubai_farms/models/fpc_procurement_dashboard.dart';
import 'package:kalsubai_farms/models/marketplace_listing.dart';
import 'package:kalsubai_farms/screens/fpo_home_screen.dart';
import 'package:kalsubai_farms/services/apmc_market_service.dart';
import 'package:kalsubai_farms/services/fpc_dashboard_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  });

  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(Get.reset);

  testWidgets(
    'invalid saved cluster falls back to All clusters and is removed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'fpc_dashboard_cluster_anonymous_fpc-1': 'deleted-cluster',
      });
      final service = _FakeDashboardService(_snapshot());

      await tester.pumpWidget(_app(service: service));
      await tester.pumpAndSettle();

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('fpc_dashboard_cluster_anonymous_fpc-1'),
        isNull,
      );
      expect(service.loadedClusterIds, [null]);
    },
  );

  testWidgets('cluster manager creates, renames, deactivates, and assigns', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1100, 900));
    final service = _FakeDashboardService(_snapshot());

    await tester.pumpWidget(_app(service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-clusters-button')));
    await tester.pumpAndSettle();
    expect(find.text('Manage operating clusters'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-cluster-button')));
    await tester.pumpAndSettle();
    final createFields = find.byType(TextFormField);
    await tester.enterText(createFields.at(0), 'Sinnar cluster');
    await tester.enterText(createFields.at(1), 'Nashik');
    await tester.enterText(createFields.at(2), 'Maharashtra');
    await tester.enterText(createFields.at(3), 'Sinnar APMC');
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(service.createdName, 'Sinnar cluster');

    final firstClusterMenu = find.byIcon(Icons.more_vert).first;
    await tester.ensureVisible(firstClusterMenu);
    await tester.pumpAndSettle();
    await tester.tap(firstClusterMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename and edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Renamed belt');
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(service.updatedName, 'Renamed belt');

    final renamedClusterMenu = find.byIcon(Icons.more_vert).first;
    await tester.ensureVisible(renamedClusterMenu);
    await tester.pumpAndSettle();
    await tester.tap(renamedClusterMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(service.deactivatedClusterId, 'cluster-1');

    await tester.tap(find.text('Farm assignments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assignment-link-1-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinnar cluster').last);
    await tester.pumpAndSettle();

    expect(service.assignedLinkId, 'link-1');
    expect(service.assignedClusterId, 'cluster-created');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plan procurement opens harvest planning with farm prefill', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    final service = _FakeDashboardService(_snapshot());
    Object? capturedArguments;

    await tester.pumpWidget(
      _app(
        service: service,
        operationsPage: () {
          capturedArguments = Get.arguments;
          return const Scaffold(body: Text('Operations target'));
        },
      ),
    );
    await tester.pumpAndSettle();

    final planProcurement = find.text('Plan procurement');
    await tester.ensureVisible(planProcurement);
    await tester.pumpAndSettle();
    await tester.tap(planProcurement);
    await tester.pumpAndSettle();

    expect(find.text('Operations target'), findsOneWidget);
    final arguments = Map<String, dynamic>.from(capturedArguments! as Map);
    expect(arguments['module'], 'harvest_planning');
    expect(arguments['open_operation'], 'create_harvest_plan');
    expect(arguments['prefill'], {
      'farm_id': 'farm-1',
      'crop': 'Finger millet',
      'village': 'Sinnar',
      'expected_harvest_date': '2026-08-15',
      'expected_quantity_kg': 1250.0,
      'expected_grade': 'Grade A',
      'readiness': 'ready',
      'priority': 'high',
    });
  });
}

Widget _app({
  required FpcDashboardService service,
  Widget Function()? operationsPage,
}) {
  return GetMaterialApp(
    getPages: [
      GetPage(
        name: '/fpo/operations',
        page: operationsPage ?? () => const SizedBox.shrink(),
      ),
    ],
    home: FpoHomeScreen(
      dashboardService: service,
      apmcService: _FakeApmcMarketService(),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

FpcProcurementDashboardSnapshot _snapshot({
  List<FpcOperatingCluster>? clusters,
  List<FpcFarmWorkCard>? farms,
}) {
  return FpcProcurementDashboardSnapshot(
    fpcId: 'fpc-1',
    selectedClusterId: null,
    generatedAt: DateTime.utc(2026, 7, 28, 4),
    unassignedFarmCount: 1,
    clusters:
        clusters ??
        const [
          FpcOperatingCluster(
            id: 'cluster-1',
            name: 'Nashik belt',
            district: 'Nashik',
            state: 'Maharashtra',
            preferredApmcMarket: 'Nashik APMC',
            active: true,
            farmCount: 0,
            readyCount: 0,
            expectedQuantityKg: 0,
          ),
        ],
    summary: const FpcProcurementSummary(
      networkFarms: 1,
      readyFarms: 1,
      expectedProcurementKg: 1250,
      openLots: 1,
      needsReview: 1,
      healthAverage: 74,
      healthCoverage: 1,
      gradeMix: [FpcGradeCount(grade: 'Grade A', count: 1)],
    ),
    farms: farms ?? [_farm()],
  );
}

FpcFarmWorkCard _farm() {
  return FpcFarmWorkCard(
    linkId: 'link-1',
    clusterId: null,
    farmerId: 'farmer-1',
    farmerName: 'Savita Pawara',
    farmerPhone: '9999999999',
    farmId: 'farm-1',
    farmName: 'West plot',
    village: 'Sinnar',
    crop: 'Finger millet',
    kycStatus: 'verified',
    areaAcres: 2.4,
    sowingDate: DateTime.utc(2026, 6, 1),
    currentStatus: 'Ready',
    currentStatusStage: 'Harvest',
    polygons: const [],
    centroidLatitude: null,
    centroidLongitude: null,
    harvestPlanId: null,
    expectedHarvestDate: DateTime.utc(2026, 8, 15),
    expectedQuantityKg: 1250,
    expectedGrade: 'Grade B',
    readiness: 'ready',
    isReady: true,
    latestGrade: 'Grade A',
    latestGradeAt: DateTime.utc(2026, 7, 27),
    needsReview: true,
    openLots: 1,
    healthScore: 74,
    snapshotDate: DateTime.utc(2026, 7, 27),
    waterStressScore: 0.2,
    weatherRisk: 0.1,
    diseaseRisk: 0.1,
    photoUrl: null,
    dataUpdatedAt: DateTime.utc(2026, 7, 28),
  );
}

class _FakeDashboardService extends FpcDashboardService {
  FpcProcurementDashboardSnapshot snapshot;
  final List<String?> loadedClusterIds = [];
  String? createdName;
  String? updatedName;
  String? deactivatedClusterId;
  String? assignedLinkId;
  String? assignedClusterId;

  _FakeDashboardService(this.snapshot);

  @override
  Future<FpcProcurementDashboardSnapshot> load({String? clusterId}) async {
    loadedClusterIds.add(clusterId);
    return snapshot;
  }

  @override
  Future<FpcProcurementDashboardSnapshot> loadOverview({
    String? clusterId,
  }) async {
    loadedClusterIds.add(clusterId);
    return snapshot;
  }

  @override
  Future<FpcFarmQueuePage> loadFarmQueue({
    String? clusterId,
    required int offset,
    int limit = 5,
  }) async {
    final farms = snapshot.farms
        .skip(offset)
        .take(limit)
        .toList(growable: false);
    return FpcFarmQueuePage(
      farms: farms,
      hasMore: offset + farms.length < snapshot.farms.length,
      nextOffset: offset + farms.length,
    );
  }

  @override
  Future<List<FpcFarmMapPoint>> loadFarmMapPoints({String? clusterId}) async =>
      [
        for (final farm in snapshot.farms)
          FpcFarmMapPoint(
            linkId: farm.linkId,
            farmerName: farm.farmerName,
            farmName: farm.farmName,
            crop: farm.crop,
            village: farm.village,
            latitude: farm.centroidLatitude ?? 19.75,
            longitude: farm.centroidLongitude ?? 75.71,
            readiness: farm.readiness,
            needsReview: farm.needsReview,
          ),
      ];

  @override
  Future<FpcFarmWorkCard> loadFarmDetail({
    required String farmerLinkId,
    String? clusterId,
  }) async {
    return snapshot.farms.firstWhere((farm) => farm.linkId == farmerLinkId);
  }

  @override
  Future<FpcOperatingCluster> createCluster({
    required String name,
    required String district,
    required String state,
    required String preferredApmcMarket,
  }) async {
    createdName = name;
    final cluster = FpcOperatingCluster(
      id: 'cluster-created',
      name: name,
      district: district,
      state: state,
      preferredApmcMarket: preferredApmcMarket,
      active: true,
      farmCount: 0,
      readyCount: 0,
      expectedQuantityKg: 0,
    );
    snapshot = _replaceSnapshot(
      snapshot,
      clusters: [...snapshot.clusters, cluster],
    );
    return cluster;
  }

  @override
  Future<void> updateCluster({
    required String clusterId,
    required String name,
    required String district,
    required String state,
    required String preferredApmcMarket,
  }) async {
    updatedName = name;
    snapshot = _replaceSnapshot(
      snapshot,
      clusters: [
        for (final cluster in snapshot.clusters)
          if (cluster.id == clusterId)
            FpcOperatingCluster(
              id: cluster.id,
              name: name,
              district: district,
              state: state,
              preferredApmcMarket: preferredApmcMarket,
              active: cluster.active,
              farmCount: cluster.farmCount,
              readyCount: cluster.readyCount,
              expectedQuantityKg: cluster.expectedQuantityKg,
            )
          else
            cluster,
      ],
    );
  }

  @override
  Future<void> deactivateCluster(String clusterId) async {
    deactivatedClusterId = clusterId;
    snapshot = _replaceSnapshot(
      snapshot,
      clusters: snapshot.clusters
          .where((cluster) => cluster.id != clusterId)
          .toList(growable: false),
    );
  }

  @override
  Future<void> assignFarmToCluster({
    required String farmerLinkId,
    String? clusterId,
  }) async {
    assignedLinkId = farmerLinkId;
    assignedClusterId = clusterId;
  }
}

class _FakeApmcMarketService extends ApmcMarketService {
  @override
  Future<ApmcMarketResult> search({
    String query = '',
    String state = '',
    String district = '',
    String market = '',
    bool refresh = false,
  }) async {
    return const ApmcMarketResult(
      rates: <ApmcMarketRate>[],
      source: 'test',
      refreshed: false,
      refreshReason: '',
    );
  }
}

FpcProcurementDashboardSnapshot _replaceSnapshot(
  FpcProcurementDashboardSnapshot original, {
  required List<FpcOperatingCluster> clusters,
}) {
  return FpcProcurementDashboardSnapshot(
    fpcId: original.fpcId,
    selectedClusterId: original.selectedClusterId,
    generatedAt: original.generatedAt,
    unassignedFarmCount: original.unassignedFarmCount,
    clusters: clusters,
    summary: original.summary,
    farms: original.farms,
  );
}
