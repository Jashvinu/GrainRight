import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/farmer_home_screen.dart').readAsStringSync();

  test('farm overview cards grow with the device text scale', () {
    final overviewStart = source.indexOf('class _RedesignedFarmsOverview');
    final cardStart = source.indexOf('class _RedesignedFarmCard');

    expect(overviewStart, isNonNegative);
    expect(cardStart, greaterThan(overviewStart));

    final overviewSource = source.substring(overviewStart, cardStart);
    expect(overviewSource, contains('MediaQuery.textScalerOf(context)'));
    expect(overviewSource, contains('_farmOverviewCardHeight'));
    expect(overviewSource, isNot(contains('height: 174')));
  });

  test('farm page refresh repairs the farmer session before service calls', () {
    final refreshStart = source.indexOf('Future<void> _refreshFarmPageData');
    final buildStart = source.indexOf('@override', refreshStart);

    expect(refreshStart, isNonNegative);
    expect(buildStart, greaterThan(refreshStart));

    final refreshSource = source.substring(refreshStart, buildStart);
    final sessionRepair = refreshSource.indexOf('syncFarmerData(');
    final weatherRefresh = refreshSource.indexOf('_loadLiveWeatherForFarm');
    expect(sessionRepair, isNonNegative);
    expect(weatherRefresh, greaterThan(sessionRepair));
    expect(refreshSource, contains('forceRefresh: true'));
    expect(refreshSource, contains('showLoading: false'));
  });

  test('harvest hub uses responsive full-field zones and guided grading', () {
    final heroStart = source.indexOf('class _HarvestChecklistHero');
    final labelStart = source.indexOf('class _HarvestZoneLabelMarker');

    expect(heroStart, isNonNegative);
    expect(labelStart, greaterThan(heroStart));

    final harvestSource = source.substring(heroStart, labelStart);
    expect(harvestSource, contains('LayoutBuilder'));
    expect(harvestSource, contains('overlayPolygons'));
    expect(harvestSource, contains('PolygonGeometry.containsPoint'));
    expect(harvestSource, contains('_HarvestGradeCoverageBanner'));
    expect(harvestSource, contains('_HarvestGradeCard'));
    expect(harvestSource, contains('borderColor: Colors.white'));
    expect(harvestSource, isNot(contains('areaPercent >= 8')));
    expect(harvestSource, isNot(contains('CircleMarker')));
    expect(source, contains('class _HarvestWorkflowStep'));
    expect(source, contains('_zonePlan?.isHarvestReady ?? false'));
  });

  test('harvest hub uses the marketplace branded app header', () {
    final pageStart = source.indexOf('class _HarvestHomePageState');
    final pageEnd = source.indexOf('Color _harvestGradeColor', pageStart);

    expect(pageStart, isNonNegative);
    expect(pageEnd, greaterThan(pageStart));

    final pageSource = source.substring(pageStart, pageEnd);
    expect(pageSource, contains('toolbarHeight: appHeaderToolbarHeight'));
    expect(pageSource, contains('centerTitle: true'));
    expect(pageSource, contains('leading: appBackButtonLeading(context)'));
    expect(pageSource, contains('title: const BrandText(fontSize: 21)'));
    expect(pageSource, contains('LanguageSelectorButton('));
  });
}
