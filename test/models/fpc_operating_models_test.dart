import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/fpc_operating_models.dart';

void main() {
  test('membership context uses authoritative organization and role data', () {
    final context = FpcMembershipContext.fromJson({
      'id': 'membership-1',
      'fpc_id': 'fpc-1',
      'role': 'field_officer',
      'status': 'active',
      'must_change_password': true,
      'fpcs': {'name': 'Kalsubai Millet FPC', 'status': 'active'},
    });

    expect(context.fpcId, 'fpc-1');
    expect(context.fpcName, 'Kalsubai Millet FPC');
    expect(context.isFieldOfficer, isTrue);
    expect(context.isAdmin, isFalse);
    expect(context.mustChangePassword, isTrue);
  });

  test('operation record parses quantities, amounts and details', () {
    final record = FpcOperationRecord.fromJson({
      'id': 'record-1',
      'module': 'warehouse',
      'record_type': 'stock_audit',
      'title': 'Rack A audit',
      'status': 'completed',
      'quantity': '250.5',
      'amount': 1200,
      'details': {'notes': 'No damage'},
    });

    expect(record.module, 'warehouse');
    expect(record.quantity, 250.5);
    expect(record.amount, 1200);
    expect(record.details['notes'], 'No damage');
  });

  test('platform snapshot preserves applications and analytics', () {
    final snapshot = PlatformFpcSnapshot.fromJson({
      'applications': [
        {'id': 'app-1', 'status': 'pending'},
      ],
      'fpcs': [
        {'id': 'fpc-1', 'status': 'active'},
      ],
      'memberships': const [],
      'subscriptions': const [],
      'analytics': {'totalFpcs': 1, 'activeFpcs': 1},
    });

    expect(snapshot.applications.single['status'], 'pending');
    expect(snapshot.analytics['activeFpcs'], 1);
  });
}
