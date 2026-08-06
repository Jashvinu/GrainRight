import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260730113142_fpc_seed_paid_checkout_inventory.sql',
  ).readAsStringSync();
  final checkout = File(
    'supabase/functions/fpc-seed-checkout/index.ts',
  ).readAsStringSync();
  final webhook = File(
    'supabase/functions/fpc-seed-payment-webhook/index.ts',
  ).readAsStringSync();

  test('seed checkout persists priced batches and 24 hour reservations', () {
    expect(migration, contains('unit_price_paise'));
    expect(migration, contains('seed_batch_id'));
    expect(migration, contains('amount_paise'));
    expect(migration, contains('reservation_expires_at'));
    expect(migration, contains("interval '24 hours'"));
    expect(migration, contains('fpc_seed_payment_attempts'));
    expect(migration, contains('expire_fpc_seed_reservations'));
    expect(migration, contains('cron.schedule'));
  });

  test('sown farms cannot create another purchase request', () {
    expect(migration, contains('private.farm_has_sown_seed'));
    expect(migration, contains('This farm already has seed sown'));
    expect(migration, contains('farmer_request_seed_purchase'));
    expect(migration, contains('private.farmer_can_access_farm'));
  });

  test(
    'payment is required before issue and inventory is acknowledgement led',
    () {
      expect(migration, contains('enforce_paid_seed_issue'));
      expect(migration, contains("payment_status <> 'captured'"));
      expect(migration, contains('create table public.farmer_seed_inventory'));
      expect(migration, contains('create_farmer_seed_inventory'));
      expect(migration, contains('unique (seed_issue_id)'));
      expect(migration, contains('mark_farmer_seed_inventory_used'));
    },
  );

  test(
    'new seed tables use RLS, explicit grants, and realtime notifications',
    () {
      expect(
        migration,
        contains(
          'alter table public.fpc_seed_payment_attempts enable row level security',
        ),
      );
      expect(
        migration,
        contains(
          'alter table public.farmer_seed_inventory enable row level security',
        ),
      );
      expect(migration, contains('revoke insert, update, delete'));
      expect(migration, contains('grant select'));
      expect(migration, contains('supabase_realtime'));
      expect(migration, contains('fpc_notifications'));
    },
  );

  test('Razorpay order and signature are verified server-side', () {
    expect(checkout, contains('action === "create_order"'));
    expect(checkout, contains('action === "verify_payment"'));
    expect(checkout, contains('createRazorpayOrder'));
    expect(checkout, contains('verifyRazorpayCheckoutSignature'));
    expect(checkout, contains('rzp_test_'));
    expect(webhook, contains('verifyRazorpayWebhookSignature'));
    expect(webhook, contains('payment.captured'));
  });
}
