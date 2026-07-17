import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:kalsubai_farms/screens/boundary_polygon_screen.dart';
import 'package:kalsubai_farms/screens/offline_maps_screen.dart';
import 'package:kalsubai_farms/services/local_app_database.dart';
import 'package:kalsubai_farms/services/offline_map_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.testMode = true;
  });

  testWidgets('browse mode does not add points but draw mode does', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = OfflineMapService(mapTilerApiKeyProvider: () => 'test-key');
    addTearDown(service.dispose);

    await tester.pumpWidget(
      GetMaterialApp(
        home: BoundaryPolygonScreen(mapService: service, loadMapTiles: false),
      ),
    );
    await tester.pump();

    final map = find.byKey(const Key('farm_boundary_map'));
    expect(map, findsOneWidget);
    expect(find.text('Roads'), findsOneWidget);
    expect(find.text('Farm'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);
    expect(find.text('Map view'), findsNothing);
    expect(find.text('Map action'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byTooltip('Save farm boundary'), findsOneWidget);
    expect(find.text('1. Choose map view'), findsNothing);
    expect(find.text('2. Move map or mark farm'), findsNothing);
    final roadControl = find.byKey(const Key('farm_boundary_road_map'));
    final farmControl = find.byKey(const Key('farm_boundary_satellite_map'));
    final moveControl = find.byKey(const Key('farm_boundary_browse_mode'));
    final markControl = find.byKey(const Key('farm_boundary_draw_mode'));
    expect(
      tester.getCenter(roadControl).dy,
      closeTo(tester.getCenter(farmControl).dy, 0.1),
    );
    expect(
      tester.getCenter(moveControl).dy,
      closeTo(tester.getCenter(markControl).dy, 0.1),
    );
    expect(
      tester.getCenter(roadControl).dy,
      closeTo(tester.getCenter(markControl).dy, 0.1),
    );
    final mapViewGroup = find.byKey(const Key('farm_boundary_map_view_group'));
    final mapActionGroup = find.byKey(
      const Key('farm_boundary_map_action_group'),
    );
    final compactControls = find.byKey(
      const Key('farm_boundary_compact_controls'),
    );
    expect(
      tester.getTopRight(mapViewGroup).dx,
      lessThan(tester.getTopLeft(mapActionGroup).dx),
    );
    expect(tester.getSize(mapViewGroup).height, lessThanOrEqualTo(50));
    expect(tester.getSize(compactControls).width, lessThanOrEqualTo(284));
    expect(tester.getCenter(compactControls).dx, greaterThan(180));
    expect(tester.getSize(roadControl).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(roadControl).height, lessThanOrEqualTo(52));
    final downloadControl = find.byKey(
      const Key('farm_boundary_download_maps_fab'),
    );
    final recenterControl = find.byKey(const Key('farm_boundary_recenter_fab'));
    final undoControl = find.byKey(const Key('farm_boundary_undo_button'));
    final clearControl = find.byKey(const Key('farm_boundary_clear_button'));
    expect(undoControl, findsOneWidget);
    expect(clearControl, findsOneWidget);
    expect(downloadControl, findsOneWidget);
    expect(recenterControl, findsOneWidget);
    expect(tester.getCenter(undoControl).dx, greaterThan(180));
    expect(tester.getCenter(clearControl).dx, greaterThan(180));
    expect(
      tester.getCenter(undoControl).dy,
      lessThan(tester.getCenter(downloadControl).dy),
    );
    expect(
      tester.getCenter(clearControl).dy,
      lessThan(tester.getCenter(downloadControl).dy),
    );
    expect(tester.getCenter(downloadControl).dx, greaterThan(180));
    expect(tester.getCenter(recenterControl).dx, greaterThan(180));
    expect(tester.getCenter(recenterControl).dy, greaterThan(320));
    final bottomPanel = find.byKey(const Key('farm_boundary_bottom_panel'));
    final confirmControl = find.byKey(
      const Key('farm_boundary_confirm_button'),
    );
    expect(tester.getSize(bottomPanel).width, lessThanOrEqualTo(304));
    expect(tester.getSize(bottomPanel).height, lessThanOrEqualTo(112));
    expect(tester.getSize(confirmControl).height, greaterThanOrEqualTo(48));
    expect(
      tester.getBottomRight(recenterControl).dy,
      lessThan(tester.getTopRight(bottomPanel).dy),
    );
    expect(_summaryText(tester), contains('3'));
    const tapPosition = TapPosition(Offset.zero, Offset.zero);
    const farmPoint = LatLng(19.54, 74.01);

    tester.widget<FlutterMap>(map).options.onTap!(tapPosition, farmPoint);
    await tester.pump();
    expect(_summaryText(tester), contains('3'));

    await tester.tap(find.byKey(const Key('farm_boundary_draw_mode')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Tap corners to build the farm boundary.'),
      findsOneWidget,
    );
    tester.widget<FlutterMap>(map).options.onTap!(tapPosition, farmPoint);
    await tester.pump();
    expect(_summaryText(tester), contains('2'));

    await tester.tap(find.byKey(const Key('farm_boundary_satellite_map')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_summaryText(tester), contains('2'));
    await tester.tap(find.byKey(const Key('farm_boundary_road_map')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_summaryText(tester), contains('2'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('search result pins the place and enables boundary drawing', (
    tester,
  ) async {
    final client = _FakeClient((_) async {
      return http.Response(
        jsonEncode({
          'features': [
            {
              'id': 'place.akole',
              'text': 'Akole',
              'place_name': 'Akole, Ahilyanagar, Maharashtra, India',
              'center': [74.005, 19.541],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = OfflineMapService(
      client: client,
      mapTilerApiKeyProvider: () => 'test-key',
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(
      GetMaterialApp(
        home: BoundaryPolygonScreen(mapService: service, loadMapTiles: false),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('farm_boundary_search')),
      'Akole',
    );
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();

    final resultTile = find.widgetWithText(ListTile, 'Akole');
    expect(resultTile, findsOneWidget);
    await tester.tap(resultTile);
    await tester.pump();

    expect(find.text('Place found'), findsOneWidget);
    expect(
      find.byKey(const Key('farm_boundary_search_marker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('farm_boundary_searched_place_label')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('farm_boundary_road_map')), findsOneWidget);
    expect(
      find.byKey(const Key('farm_boundary_satellite_map')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('farm_boundary_draw_mode')), findsOneWidget);

    const tapPosition = TapPosition(Offset.zero, Offset.zero);
    const farmPoint = LatLng(19.542, 74.006);
    final map = find.byKey(const Key('farm_boundary_map'));
    tester.widget<FlutterMap>(map).options.onTap!(tapPosition, farmPoint);
    await tester.pump();
    expect(_summaryText(tester), contains('2'));

    Get.closeCurrentSnackbar();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'empty downloaded maps opens downloads and back restores drawing state',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _EmptyOfflineMapService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        GetMaterialApp(
          home: BoundaryPolygonScreen(mapService: service, loadMapTiles: false),
          getPages: [
            GetPage(
              name: '/offline-maps',
              page: () => const OfflineMapsScreen(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('farm_boundary_draw_mode')));
      await tester.pump();
      const tapPosition = TapPosition(Offset.zero, Offset.zero);
      const farmPoint = LatLng(19.54, 74.01);
      final map = find.byKey(const Key('farm_boundary_map'));
      tester.widget<FlutterMap>(map).options.onTap!(tapPosition, farmPoint);
      await tester.pump();
      expect(_summaryText(tester), contains('2'));

      await tester.tap(
        find.byKey(const Key('farm_boundary_download_maps_fab')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(OfflineMapsScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BoundaryPolygonScreen), findsOneWidget);
      expect(_summaryText(tester), contains('2'));
      tester.widget<FlutterMap>(map).options.onTap!(
        tapPosition,
        const LatLng(19.541, 74.011),
      );
      await tester.pump();
      expect(_summaryText(tester), contains('1'));

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('map controls follow Hindi app language', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = OfflineMapService(mapTilerApiKeyProvider: () => 'test-key');
    addTearDown(service.dispose);

    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('hi'),
        home: BoundaryPolygonScreen(mapService: service, loadMapTiles: false),
      ),
    );
    await tester.pump();

    expect(find.text('सड़क'), findsOneWidget);
    expect(find.text('खेत'), findsOneWidget);
    expect(find.text('चलाएं'), findsOneWidget);
    expect(find.text('चिन्हित'), findsOneWidget);
    expect(find.text('सहेजें'), findsOneWidget);
    expect(find.byTooltip('खेत की सीमा सहेजें'), findsOneWidget);
    expect(find.byTooltip('पिछला बिंदु हटाएं'), findsOneWidget);
    expect(find.byTooltip('पूरी सीमा मिटाएं'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('map controls follow Marathi app language', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = OfflineMapService(mapTilerApiKeyProvider: () => 'test-key');
    addTearDown(service.dispose);

    await tester.pumpWidget(
      GetMaterialApp(
        locale: const Locale('mr'),
        home: BoundaryPolygonScreen(mapService: service, loadMapTiles: false),
      ),
    );
    await tester.pump();

    expect(find.text('रस्ते'), findsOneWidget);
    expect(find.text('शेत'), findsOneWidget);
    expect(find.text('हलवा'), findsOneWidget);
    expect(find.text('रेखाटा'), findsOneWidget);
    expect(find.text('जतन करा'), findsOneWidget);
    expect(find.byTooltip('शेत सीमा जतन करा'), findsOneWidget);
    expect(find.byTooltip('मागचा बिंदू काढा'), findsOneWidget);
    expect(find.byTooltip('संपूर्ण सीमा पुसा'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

String _summaryText(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const Key('boundary_point_summary')))
      .data!;
}

class _FakeClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;

  _FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
      headers: response.headers,
    );
  }
}

class _EmptyOfflineMapService extends OfflineMapService {
  _EmptyOfflineMapService() : super(mapTilerApiKeyProvider: () => 'test-key');

  @override
  Future<List<OfflineMapRegionRecord>> listRegions() async => const [];
}
