import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final marketSource = File(
    'lib/screens/apmc_market_screen.dart',
  ).readAsStringSync();
  final taskServiceSource = File(
    'lib/services/farmer_daily_task_service.dart',
  ).readAsStringSync();
  final taskFunctionSource = File(
    'supabase/functions/farmer-daily-tasks/index.ts',
  ).readAsStringSync();
  final marketplaceFunctionSource = File(
    'supabase/functions/marketplace-listings/index.ts',
  ).readAsStringSync();
  final apmcMigrationSource = File(
    'supabase/migrations/20260720104458_schedule_daily_apmc_sync.sql',
  ).readAsStringSync();

  test('market keeps role-aware Farmer and FPC marketplace tabs', () {
    expect(marketSource, contains('TabController(length: 4'));
    expect(marketSource, contains('FarmerFloatingBottomNavDock('));
    expect(marketSource, contains('class _MarketplaceSectionTabs'));
    expect(marketSource, contains("fpcWorkspace ? 'Produce' : 'Buy'"));
    expect(marketSource, contains("_marketText('APMC')"));
    expect(
      marketSource,
      contains("fpcWorkspace ? 'Negotiations' : 'My Listings'"),
    );
    expect(marketSource, contains("'Negotiations'"));
    expect(marketSource, contains("_marketText('Orders')"));
    expect(marketSource, contains("'Produce'"));
    expect(marketSource, isNot(contains('class _MarketplaceBottomNavigation')));
    expect(marketSource, isNot(contains('class _SellTab')));
    expect(marketSource, isNot(contains("Tab(text: _marketText('Sell'))")));
    expect(marketSource, isNot(contains("_marketText('Add to cart')")));
  });

  test('buy tab omits APMC preview and rates load only when requested', () {
    final buyTabStart = marketSource.indexOf('class _BuyTab');
    final buyTabEnd = marketSource.indexOf(
      'class _MarketplaceSectionHeader',
      buyTabStart,
    );
    final buyTabSource = marketSource.substring(buyTabStart, buyTabEnd);
    expect(buyTabSource, isNot(contains('ApmcMarketRate')));
    expect(buyTabSource, isNot(contains('APMC market rates')));
    expect(buyTabSource, isNot(contains('MarketplaceListing')));
    expect(buyTabSource, contains('Verified farm inputs'));
    expect(
      marketSource,
      contains('if (_tabs.index == 1 && !_hasRequestedRates)'),
    );
    expect(marketSource, isNot(contains('Future<void> _loadMarketplace()')));
  });

  test('active inventory listings feed the marketplace browse section', () {
    expect(marketSource, contains('listings: _visibleSellListings'));
    expect(marketSource, contains('final List<MarketplaceListing> listings'));
    expect(marketSource, contains('_MarketplaceListingTile('));
    expect(
      marketSource,
      contains('Your inventory product is now live in Marketplace.'),
    );
    expect(
      marketplaceFunctionSource,
      contains('canAccessInventoryItem(supabase, userId, item)'),
    );
    expect(marketplaceFunctionSource, contains('.eq("status", "active")'));
  });

  test('ungraded inventory is normalized before creating a market lot', () {
    expect(
      marketplaceFunctionSource,
      contains('function marketplaceGrade(raw: unknown): string'),
    );
    expect(
      marketplaceFunctionSource,
      contains('grade: marketplaceGrade(item.grade) || null'),
    );
    expect(
      marketplaceFunctionSource,
      contains('const title = text(body.title) || productName'),
    );
    expect(marketSource, contains('title: result.title'));
  });

  test('marketplace and APMC failures are isolated by section', () {
    expect(marketSource, contains('Future<void> _loadListingData()'));
    expect(marketSource, contains('Future<void> _loadInitialRates()'));
    expect(marketSource, contains("String _marketplaceError = ''"));
    expect(marketSource, contains("String _apmcError = ''"));
    expect(
      marketSource,
      contains('showingApmc ? _apmcError : _marketplaceError'),
    );
  });

  test('farmer can list selected-farm inventory from My Listings', () {
    expect(
      marketSource,
      contains('List<Map<String, String>> get _listableInventoryLots'),
    );
    expect(marketSource, contains('belongsToSelectedFarm'));
    expect(marketSource, contains('class _InventoryListingCandidateCard'));
    expect(marketSource, contains("_marketText('List in market')"));
    expect(marketSource, contains('onListInventory: _openListingForm'));
  });

  test('own listings do not expose the purchase action', () {
    expect(marketSource, contains('ownerMode: true'));
    expect(marketSource, contains('bottomNavigationBar: widget.ownerMode'));
  });

  test('today tasks use the authenticated backend rule endpoint', () {
    expect(taskServiceSource, contains("'farmer-daily-tasks'"));
    expect(taskServiceSource, contains("'action': 'sync'"));
    expect(taskFunctionSource, contains('requireUserId(supabase, req)'));
    expect(taskFunctionSource, contains('.eq("user_id", userId)'));
    expect(taskFunctionSource, contains('deriveTasks(userId, farmId, body)'));
    expect(taskFunctionSource, contains('"update_status"'));
  });

  test('official APMC refresh is scheduled with a private database token', () {
    expect(
      apmcMigrationSource,
      contains('create extension if not exists pg_net'),
    );
    expect(
      apmcMigrationSource,
      contains('grainright-daily-official-apmc-rates'),
    );
    expect(apmcMigrationSource, contains('x-apmc-cron-token'));
    expect(
      apmcMigrationSource,
      contains('revoke all on public.apmc_sync_control'),
    );
  });
}
