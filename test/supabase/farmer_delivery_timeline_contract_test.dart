import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260806065926_farmer_delivery_timeline.sql',
  ).readAsStringSync();

  test('timeline view is read-only and RLS filtered', () {
    expect(migration, contains('create view public.farmer_delivery_timeline'));
    expect(migration, contains('with (security_invoker = true)'));
    expect(
      migration,
      contains('grant select on public.farmer_delivery_timeline'),
    );
    expect(
      migration,
      contains('revoke all on public.farmer_delivery_timeline from anon'),
    );
    expect(migration, isNot(contains('security definer')));
  });

  test('farmers can read only their own procurement and payment rows', () {
    for (final policy in const [
      'farmers read own procurement lots',
      'farmers read own procurement records',
      'farmers read own payment ledger',
    ]) {
      expect(migration, contains(policy));
    }
    expect(migration, contains('profile.user_id = auth.uid()'));
    expect(
      migration,
      contains(
        "nullif(trim(profile.farmer_id), '') = procurement_lots.farmer_id",
      ),
    );
    expect(
      migration,
      contains(
        "nullif(trim(profile.farmer_id), '') = farmer_payment_ledger.farmer_id",
      ),
    );
  });

  test(
    'buyer dispatch visibility is tied to farmer-owned procurement lots',
    () {
      expect(migration, contains('farmers read sales items for own lots'));
      expect(migration, contains('farmers read sales orders for own lots'));
      expect(migration, contains('farmers read dispatches for own lots'));
      expect(migration, contains('item.procurement_lot_id'));
      expect(
        migration,
        contains('item.sales_order_id = dispatches.sales_order_id'),
      );
      expect(migration, contains("'buyer_dispatch'::text as record_type"));
    },
  );

  test(
    'timeline includes seed, procurement, payment and acknowledgement state',
    () {
      for (final recordType in const [
        'seed_request',
        'seed_delivery',
        'procurement_delivery',
        'procurement_lot',
        'farmer_payment',
        'buyer_dispatch',
      ]) {
        expect(migration, contains("'$recordType'::text as record_type"));
      }
      expect(migration, contains("then 'acknowledge_seed'"));
      expect(migration, contains('issue.delivery_evidence as evidence'));
      expect(migration, contains('request.payment_status'));
      expect(migration, contains('payment.final_amount'));
    },
  );
}
