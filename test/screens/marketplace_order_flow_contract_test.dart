import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final functionSource = File(
    'supabase/functions/marketplace-listings/index.ts',
  ).readAsStringSync();
  final migrationSource = File(
    'supabase/migrations/20260727051441_marketplace_order_procurement_profit.sql',
  ).readAsStringSync();
  final startNegotiationMigrationSource = File(
    'supabase/migrations/20260727052301_marketplace_start_negotiation_atomic.sql',
  ).readAsStringSync();
  final screenSource = File(
    'lib/screens/apmc_market_screen.dart',
  ).readAsStringSync();
  final receiverSource = File(
    'lib/screens/fpo_receiver_screen.dart',
  ).readAsStringSync();

  test(
    'marketplace denies Field Officer and uses action-specific role gates',
    () {
      expect(functionSource, contains('field_officer_marketplace_forbidden'));
      expect(functionSource, contains('farmerOnlyActions'));
      expect(functionSource, contains('fpcOnlyActions'));
      expect(functionSource, contains('"confirm_final_rate"'));
      expect(functionSource, contains('"accept_procurement"'));
    },
  );

  test(
    'whole-lot acceptance and quarantine are atomic database operations',
    () {
      expect(
        startNegotiationMigrationSource,
        contains(
          'create or replace function public.marketplace_start_negotiation',
        ),
      );
      expect(functionSource, contains('"marketplace_start_negotiation"'));
      expect(
        migrationSource,
        contains('create or replace function public.marketplace_accept_offer'),
      );
      expect(
        migrationSource,
        contains('Marketplace orders must cover the whole listed lot'),
      );
      expect(
        migrationSource,
        contains(
          'create or replace function public.marketplace_record_arrival',
        ),
      );
      expect(migrationSource, contains("'quarantine'"));
      expect(
        migrationSource,
        contains(
          'create or replace function public.marketplace_finalize_procurement',
        ),
      );
      expect(
        migrationSource,
        contains('Farmer must confirm the final rate before procurement'),
      );
    },
  );

  test('marketplace write RPCs are service-role only', () {
    expect(
      migrationSource,
      contains(
        'revoke all on function public.marketplace_accept_offer(uuid, uuid, uuid, text)',
      ),
    );
    expect(
      migrationSource,
      contains(
        'grant execute on function public.marketplace_accept_offer(uuid, uuid, uuid, text)',
      ),
    );
    expect(migrationSource, contains('to service_role;'));
    expect(migrationSource, contains('with (security_invoker = true)'));
  });

  test('FPC profit includes revenue, acquisition and operating costs', () {
    expect(
      migrationSource,
      contains('create table if not exists public.fpc_cost_ledger'),
    );
    expect(
      migrationSource,
      contains('create or replace view public.fpc_profit_summary'),
    );
    expect(migrationSource, contains('acquisition_cost'));
    expect(migrationSource, contains('operating_cost'));
    expect(migrationSource, contains('net_margin'));
    expect(screenSource, contains('FPC net-margin summary'));
    expect(screenSource, contains('Record cost'));
  });

  test('screen presents Farmer and FPC workflows without Field Officer UI', () {
    expect(screenSource, contains('fpcWorkspace: widget.buyerMode'));
    expect(screenSource, contains('class _NegotiationsTab'));
    expect(screenSource, contains('class _OrdersTab'));
    expect(screenSource, contains('QR receive'));
    expect(screenSource, contains('Confirm final rate'));
    expect(screenSource, contains('Accept procurement'));
    expect(screenSource, isNot(contains('Field Officer marketplace')));
  });

  test('Farmer order QR enters the FPC quarantine receiver', () {
    expect(screenSource, contains('QrImageView'));
    expect(screenSource, contains("'type': 'grainright_marketplace_order'"));
    expect(screenSource, contains("Get.toNamed('/fpo/receiver')"));
    expect(receiverSource, contains('FpcReceiveQrParser.parse'));
    expect(receiverSource, contains('_marketplaceService.recordArrival'));
    expect(
      receiverSource,
      contains(
        'Arrival quarantined. Stock and farmer payment remain unposted.',
      ),
    );
  });
}
