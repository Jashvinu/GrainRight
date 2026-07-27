import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/screens/apmc_market_screen.dart';
import 'package:kalsubai_farms/widgets/farmer_floating_bottom_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  testWidgets('Farmer marketplace keeps navigation and role-specific tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FarmerBottomNavItem? selectedItem;

    await tester.pumpWidget(
      GetMaterialApp(
        home: MarketplacePage(
          inventoryLots: const [],
          onBottomNavSelected: (item) => selectedItem = item,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FarmerFloatingBottomNavDock), findsOneWidget);
    expect(find.text('APMC market rates'), findsNothing);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('APMC'), findsOneWidget);
    expect(find.text('My Listings'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    expect(selectedItem, FarmerBottomNavItem.home);
  });

  testWidgets('FPC marketplace exposes produce and negotiation workflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const GetMaterialApp(
        home: MarketplacePage(inventoryLots: [], buyerMode: true),
      ),
    );
    await tester.pump();

    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('APMC'), findsOneWidget);
    expect(find.text('Negotiations'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.byType(FarmerFloatingBottomNavDock), findsNothing);
    expect(find.text('My Listings'), findsNothing);
  });
}
