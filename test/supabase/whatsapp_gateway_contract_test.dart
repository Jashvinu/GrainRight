import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final gateway = File(
    'supabase/functions/whatsapp-grainright/index.ts',
  ).readAsStringSync();
  final dispatch = File(
    'supabase/functions/whatsapp-notification-dispatch/index.ts',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/20260813100000_whatsapp_gateway.sql',
  ).readAsStringSync();
  final deliveryMigration = File(
    'supabase/migrations/20260813144601_openwa_whatsapp_delivery_sync.sql',
  ).readAsStringSync();

  test('whatsapp gateway exposes all node menu actions', () {
    for (final action in [
      'health',
      'session_load',
      'session_save',
      'webhook_claim',
      'webhook_prepare',
      'webhook_complete',
      'webhook_fail',
      'notification_preference',
      'delivery_status',
      'set_language',
      'request_otp',
      'verify_otp',
      'fpc_request_otp',
      'fpc_verify_otp',
      'fpc_dashboard',
      'fpc_alerts',
      'fpc_members',
      'farm_alerts',
      'farm_summary',
      'status_update',
      'ai_chat',
      'grading_media',
      'grading_submit',
      'market_rates',
      'farm_setup_link',
      'daily_tasks',
      'inventory',
      'inventory_add',
      'economics',
      'harvest',
      'marketplace',
    ]) {
      expect(gateway, contains('action === "$action"'));
    }
  });

  test('whatsapp gateway uses production table column aliases', () {
    expect(gateway, contains('apmc_market_rate_history'));
    expect(gateway, contains('market_name:market'));
    expect(gateway, contains('whatsapp_official_market_rates'));
    expect(
      gateway,
      contains('commodity:crop,market_name,modal_price:modal_rate'),
    );
    expect(gateway, contains('min_price:min_rate'));
    expect(gateway, contains('arrival_date:rate_date'));
    expect(
      gateway,
      contains('title:title_key,description:description_key'),
    );
    expect(gateway, contains('farmer_inventory_items'));
    expect(gateway, contains('farm_economic_plans'));
    expect(gateway, contains('farm_harvest_zone_plans'));
    expect(gateway, contains('marketplace_listings'));
    expect(gateway, contains('boundaryMapUrl'));
    expect(gateway, contains('whatsapp-farm-boundary?'));
  });

  test('private writes remain behind the internal whatsapp bridge', () {
    expect(gateway, contains('GRAINRIGHT_WHATSAPP_API_TOKEN'));
    expect(gateway, contains('GRAINRIGHT_WHATSAPP_INTERNAL_TOKEN'));
    expect(gateway, contains('Deno.env.get("SUPABASE_ANON_KEY")'));
    expect(gateway, contains(r'authorization: `Bearer ${anonKey}`'));
    expect(gateway, contains('apikey: anonKey'));
    expect(gateway, contains('invokeInternal("farm-status-update"'));
    expect(gateway, contains('invokeInternal("farm-assistant-chat"'));
    expect(gateway, contains('invokeInternal("grain-grade"'));
    expect(gateway, contains('x-grainright-whatsapp-internal'));
  });

  test('unresolved farms return linked farm choices', () {
    expect(gateway, contains('readonly details: Row = {}'));
    expect(gateway, contains('farms: farms.slice(0, 8).map'));
    expect(gateway, contains('Choose one of your linked farms first.'));
    expect(gateway, contains('...error.details'));
    expect(gateway, contains('corsHeaders'));
  });

  test('whatsapp notifications are queued and dispatched through the OpenWA relay', () {
    expect(migration, contains('whatsapp_notification_outbox'));
    expect(migration, contains('enqueue_farmer_whatsapp_notification'));
    expect(migration, contains('grainright-whatsapp-notification-dispatch'));
    expect(dispatch, contains('WHATSAPP_NOTIFICATION_RELAY_URL'));
    expect(dispatch, contains('WHATSAPP_NOTIFICATION_RELAY_TOKEN'));
    expect(dispatch, contains("status: \"accepted\""));
    expect(dispatch, contains('whatsapp_notification_outbox'));
    expect(deliveryMigration, contains('whatsapp_webhook_events'));
    expect(deliveryMigration, contains('claim_whatsapp_webhook_event'));
    expect(deliveryMigration, contains('bot_state'));
    expect(deliveryMigration, contains('accepted_at'));
  });
}
