import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/farmer_delivery_timeline_item.dart';

void main() {
  test('parses delivery timeline rows and acknowledgement action', () {
    final item = FarmerDeliveryTimelineItem.fromJson({
      'timeline_id': 'seed_delivery:issue-1',
      'record_type': 'seed_delivery',
      'fpc_id': 'fpc-1',
      'fpc_name': 'Sagar',
      'farmer_id': 'FMR-1',
      'farm_id': 'farm-1',
      'title': 'Seed delivery',
      'status': 'delivered',
      'payment_status': 'captured',
      'quantity_kg': 25,
      'amount': 1250.5,
      'currency': 'INR',
      'occurred_at': '2026-08-06T06:40:00Z',
      'updated_at': '2026-08-06T06:42:00Z',
      'evidence': {'photos': []},
      'metadata': {'seedIssueId': 'issue-1'},
      'acknowledgement_action': 'acknowledge_seed',
      'acknowledge_seed_issue_id': 'issue-1',
    });

    expect(item.typeLabel, 'Seed delivery');
    expect(item.statusLabel, 'Delivered');
    expect(item.paymentStatusLabel, 'Captured');
    expect(item.quantityKg, 25);
    expect(item.amount, 1250.5);
    expect(item.hasEvidence, isTrue);
    expect(item.needsSeedAcknowledgement, isTrue);
  });

  test('normalizes empty values without fake actions', () {
    final item = FarmerDeliveryTimelineItem.fromJson({
      'timeline_id': 'farmer_payment:payment-1',
      'record_type': 'farmer_payment',
      'status': 'paid',
      'payment_status': 'paid',
      'evidence': {},
      'metadata': {},
    });

    expect(item.typeLabel, 'Farmer payment');
    expect(item.fpcName, 'FPC');
    expect(item.hasEvidence, isFalse);
    expect(item.needsSeedAcknowledgement, isFalse);
  });
}
