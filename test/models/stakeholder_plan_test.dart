import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/stakeholder_plan.dart';

void main() {
  test('estimates shares from selected amount and share unit value', () {
    final plan = StakeholderPlan.fromJson({
      'id': 'plan-1',
      'plan_code': 'stakeholder-v1',
      'title': 'Plan',
      'currency': 'INR',
      'share_unit_value': 1000,
      'min_amount': 1000,
      'max_amount': 25000,
      'purpose': ['member interest'],
    });

    expect(plan.estimateShares(5000), 5);
    expect(plan.estimateShares(5500), 5);
    expect(plan.isValidAmount(1000), isTrue);
    expect(plan.isValidAmount(500), isFalse);
    expect(plan.isValidAmount(26000), isFalse);
  });

  test('parses stakeholder application aliases', () {
    final application = StakeholderApplication.fromJson({
      'id': 'app-1',
      'plan_id': 'plan-1',
      'user_id': 'user-1',
      'farmer_phone': '+91 98765 43210',
      'farmer_id': 'FMR-001',
      'farmer_name': 'Farmer',
      'agri_record_id': 'AGR-123',
      'aadhaar_last4': '6789',
      'selected_amount': '3000',
      'estimated_shares': '3',
      'status': 'under_review',
      'consent_interest_only': true,
      'consent_no_guaranteed_return': true,
      'consent_data_use': true,
    });

    expect(application.farmerPhone, '9876543210');
    expect(application.selectedAmount, 3000);
    expect(application.estimatedShares, 3);
    expect(application.status, StakeholderApplicationStatus.underReview);
    expect(application.consentInterestOnly, isTrue);
  });
}
