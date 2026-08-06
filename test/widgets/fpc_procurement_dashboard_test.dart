import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/models/fpc_procurement_dashboard.dart';
import 'package:kalsubai_farms/models/marketplace_listing.dart';
import 'package:kalsubai_farms/widgets/fpc_procurement_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'phone layout shows live KPIs, filters, and incomplete map data',
    (tester) async {
      await _setViewport(tester, const Size(390, 844));
      var manageTapped = false;
      FpcFarmWorkCard? plannedFarm;
      await tester.pumpWidget(
        _harness(
          snapshot: _snapshot(),
          onManageClusters: () => manageTapped = true,
          onPlanProcurement: (farm) => plannedFarm = farm,
        ),
      );
      await tester.pump();

      expect(find.text('Network farms'), findsOneWidget);
      expect(find.text('Expected procurement'), findsOneWidget);
      expect(find.text('Grade mix'), findsOneWidget);
      expect(find.byKey(const Key('fpc-farm-search')), findsOneWidget);
      expect(find.text('Farm map'), findsOneWidget);

      await tester.tap(find.byKey(const Key('manage-clusters-button')));
      await tester.pump();
      expect(manageTapped, isTrue);

      await tester.scrollUntilVisible(
        find.text('Plan procurement'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Plan procurement'));
      await tester.pump();
      expect(plannedFarm?.linkId, 'link-1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cluster selector and queue search update the dashboard state', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1000));
    String? selected;
    await tester.pumpWidget(
      _harness(
        snapshot: _snapshot(),
        onClusterChanged: (value) => selected = value,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('fpc-cluster-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nashik belt · 1').last);
    await tester.pumpAndSettle();
    expect(selected, 'cluster-1');

    await tester.enterText(
      find.byKey(const Key('fpc-farm-search')),
      'missing farm',
    );
    await tester.pump();
    expect(find.text('No farms match these filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop and scaled text keep the two-column command center', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 1100));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1440, 1100),
          textScaler: TextScaler.linear(1.25),
        ),
        child: _harness(snapshot: _snapshot(twoFarms: true)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('fpc-kpi-grid')), findsOneWidget);
    expect(find.byKey(const Key('fpc-farm-selector-list')), findsOneWidget);
    expect(find.textContaining('West plot'), findsWidgets);
    expect(find.textContaining('East plot'), findsWidgets);
    expect(find.text('Choose one cluster'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading, partial failure, and empty setup states are honest', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(_harness(loading: true));
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pumpWidget(
      _harness(
        snapshot: _emptySnapshot(),
        error: 'The live snapshot could not be refreshed.',
      ),
    );
    await tester.pump();
    expect(
      find.text('The live snapshot could not be refreshed.'),
      findsOneWidget,
    );
    expect(find.text('Set up your procurement regions'), findsOneWidget);
    expect(find.text('Manage clusters'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop visual regression', (tester) async {
    await tester.runAsync(_loadVisualFonts);
    await _setViewport(tester, const Size(1024, 541));
    await tester.pumpWidget(
      _harness(
        snapshot: _snapshot(
          twoFarms: true,
          selectedCluster: true,
          withCoordinates: true,
        ),
        apmcRates: [
          ApmcMarketRate(
            id: 'rate-1',
            state: 'Maharashtra',
            district: 'Nashik',
            market: 'Nashik APMC',
            commodity: 'Finger Millet',
            variety: 'Local',
            grade: 'FAQ',
            minPrice: 2900,
            maxPrice: 3300,
            modalPrice: 3180,
            arrivalDate: DateTime(2026, 7, 27),
          ),
          ApmcMarketRate(
            id: 'rate-2',
            state: 'Maharashtra',
            district: 'Nashik',
            market: 'Nashik APMC',
            commodity: 'Pearl Millet',
            variety: 'Hybrid',
            grade: 'FAQ',
            minPrice: 2450,
            maxPrice: 2800,
            modalPrice: 2690,
            arrivalDate: DateTime(2026, 7, 27),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/fpc_procurement_dashboard_desktop.png'),
    );
  });
}

Future<void> _loadVisualFonts() async {
  Directory? flutterRoot;
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    flutterRoot = Directory(configuredRoot);
  } else {
    var candidate = File(Platform.resolvedExecutable).parent;
    while (candidate.parent.path != candidate.path) {
      final fontDirectory = Directory(
        [
          candidate.path,
          'bin',
          'cache',
          'artifacts',
          'material_fonts',
        ].join(Platform.pathSeparator),
      );
      if (fontDirectory.existsSync()) {
        flutterRoot = candidate;
        break;
      }
      candidate = candidate.parent;
    }
  }
  if (flutterRoot == null) {
    throw StateError('Could not locate the Flutter SDK material fonts.');
  }
  final separator = Platform.pathSeparator;
  final fontRoot = [
    flutterRoot.path,
    'bin',
    'cache',
    'artifacts',
    'material_fonts',
  ].join(separator);

  Future<ByteData> load(String fileName) async {
    final bytes = await File('$fontRoot$separator$fileName').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final roboto = FontLoader('Roboto')..addFont(load('roboto-regular.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(load('materialicons-regular.otf'));
  await Future.wait([roboto.load(), icons.load()]);
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget _harness({
  FpcProcurementDashboardSnapshot? snapshot,
  bool loading = false,
  String error = '',
  ValueChanged<String?>? onClusterChanged,
  VoidCallback? onManageClusters,
  ValueChanged<FpcFarmWorkCard>? onPlanProcurement,
  List<ApmcMarketRate> apmcRates = const [],
}) {
  return GetMaterialApp(
    theme: AppTheme.theme.copyWith(
      textTheme: AppTheme.theme.textTheme.apply(fontFamily: 'Roboto'),
      primaryTextTheme: AppTheme.theme.primaryTextTheme.apply(
        fontFamily: 'Roboto',
      ),
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FpcProcurementDashboard(
          snapshot: snapshot,
          farms: snapshot?.farms ?? const [],
          mapPoints: [
            for (final farm in snapshot?.farms ?? const <FpcFarmWorkCard>[])
              FpcFarmMapPoint(
                linkId: farm.linkId,
                farmerName: farm.farmerName,
                farmName: farm.farmName,
                crop: farm.crop,
                village: farm.village,
                latitude: 19.75 + (farm.linkId == 'link-2' ? 0.03 : 0),
                longitude: 75.71 + (farm.linkId == 'link-2' ? 0.03 : 0),
                readiness: farm.readiness,
                needsReview: farm.needsReview,
              ),
          ],
          loading: loading,
          queueLoading: false,
          queueHasMore: false,
          queueError: '',
          mapLoading: false,
          mapError: '',
          error: error,
          apmcRates: apmcRates,
          apmcLoading: false,
          apmcError: '',
          enableMapTiles: false,
          onClusterChanged: onClusterChanged ?? (_) {},
          onRefresh: () async {},
          onLoadMoreFarms: () async {},
          onLoadFarmDetail: (farm) async => farm,
          onLoadMapFarmDetail: (linkId) async => (snapshot?.farms ?? const [])
              .firstWhere((farm) => farm.linkId == linkId),
          onManageClusters: onManageClusters ?? () {},
          onRetryApmc: () {},
          onPlanProcurement: onPlanProcurement ?? (_) {},
        ),
      ),
    ),
  );
}

FpcProcurementDashboardSnapshot _snapshot({
  bool twoFarms = false,
  bool selectedCluster = false,
  bool withCoordinates = false,
}) {
  final farms = [
    _farm(
      linkId: 'link-1',
      farmName: 'West plot',
      ready: true,
      withCoordinates: withCoordinates,
    ),
    if (twoFarms)
      _farm(
        linkId: 'link-2',
        farmName: 'East plot',
        ready: false,
        withCoordinates: withCoordinates,
      ),
  ];
  return FpcProcurementDashboardSnapshot(
    fpcId: 'fpc-1',
    selectedClusterId: selectedCluster ? 'cluster-1' : null,
    generatedAt: DateTime(2026, 7, 28, 8, 15),
    unassignedFarmCount: 0,
    clusters: const [
      FpcOperatingCluster(
        id: 'cluster-1',
        name: 'Nashik belt',
        district: 'Nashik',
        state: 'Maharashtra',
        preferredApmcMarket: 'Nashik APMC',
        active: true,
        farmCount: 1,
        readyCount: 1,
        expectedQuantityKg: 1100,
      ),
    ],
    summary: FpcProcurementSummary(
      networkFarms: farms.length,
      readyFarms: 1,
      expectedProcurementKg: 1100,
      openLots: 2,
      needsReview: 1,
      healthAverage: 82,
      healthCoverage: farms.length,
      gradeMix: const [
        FpcGradeCount(grade: 'Grade A', count: 1),
        FpcGradeCount(grade: 'Not graded', count: 1),
      ],
    ),
    farms: farms,
  );
}

FpcProcurementDashboardSnapshot _emptySnapshot() {
  return FpcProcurementDashboardSnapshot(
    fpcId: 'fpc-1',
    selectedClusterId: null,
    generatedAt: DateTime(2026, 7, 28),
    unassignedFarmCount: 0,
    clusters: const [],
    summary: FpcProcurementSummary.empty,
    farms: const [],
  );
}

FpcFarmWorkCard _farm({
  required String linkId,
  required String farmName,
  required bool ready,
  bool withCoordinates = false,
}) {
  final latitude = ready ? 20.0123 : 20.0341;
  final longitude = ready ? 73.7844 : 73.8126;
  return FpcFarmWorkCard(
    linkId: linkId,
    clusterId: 'cluster-1',
    farmerId: 'farmer-$linkId',
    farmerName: ready ? 'Savita Pawara' : 'Ramesh Pawara',
    farmerPhone: '',
    farmId: 'farm-$linkId',
    farmName: farmName,
    village: 'Nashik',
    crop: 'Pearl millet',
    kycStatus: 'verified',
    areaAcres: 2.4,
    sowingDate: DateTime(2026, 6, 18),
    currentStatus: ready ? 'ready' : 'monitoring',
    currentStatusStage: 'grain filling',
    polygons: withCoordinates
        ? [
            [
              FpcCoordinate(latitude - 0.003, longitude - 0.003),
              FpcCoordinate(latitude - 0.003, longitude + 0.003),
              FpcCoordinate(latitude + 0.003, longitude + 0.003),
              FpcCoordinate(latitude + 0.003, longitude - 0.003),
              FpcCoordinate(latitude - 0.003, longitude - 0.003),
            ],
          ]
        : const [],
    centroidLatitude: withCoordinates ? latitude : null,
    centroidLongitude: withCoordinates ? longitude : null,
    harvestPlanId: 'plan-$linkId',
    expectedHarvestDate: DateTime(2026, 9, 17),
    expectedQuantityKg: 1100,
    expectedGrade: 'Grade A',
    readiness: ready ? 'ready' : 'monitoring',
    isReady: ready,
    latestGrade: ready ? 'Grade A' : 'Not graded',
    latestGradeAt: ready ? DateTime(2026, 7, 26) : null,
    needsReview: !ready,
    openLots: ready ? 1 : 0,
    healthScore: ready ? 84 : 74,
    snapshotDate: DateTime(2026, 7, 27),
    waterStressScore: 0.1,
    weatherRisk: 0.1,
    diseaseRisk: 0.1,
    photoUrl: null,
    dataUpdatedAt: DateTime.now(),
  );
}
