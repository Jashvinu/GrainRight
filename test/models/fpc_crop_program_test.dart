import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/fpc_crop_program.dart';

void main() {
  test('parses the farmer seed-to-sale program snapshot', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'enrollment': {
        'id': 'enrollment-1',
        'status': 'on_hold',
        'policy_version': 2,
        'policy_snapshot': {'minimum_grade': 'B', 'max_moisture_percent': 13.5},
        'price_formula_snapshot': {'reference_rate_per_kg': 42},
      },
      'program': {'name': 'Kharif Ragi 2026'},
      'fpc': {'name': 'Kalsubai FPC'},
      'seed_issue': {
        'id': 'issue-1',
        'status': 'acknowledged',
        'quantity_kg': 8,
        'seed_batch': {'batch_code': 'RAGI-26-01'},
      },
      'checks': [
        {
          'required': true,
          'farmer_status': 'submitted',
          'officer_status': 'verified',
        },
        {
          'required': true,
          'farmer_status': 'submitted',
          'officer_status': 'failed',
        },
      ],
      'evaluations': [
        {
          'attempt_no': 1,
          'status': 'failed',
          'protected_floor_rate': 44,
          'reasons': ['Moisture is above the program limit'],
        },
      ],
    });

    expect(snapshot.exists, isTrue);
    expect(snapshot.programName, 'Kharif Ragi 2026');
    expect(snapshot.seedBatchCode, 'RAGI-26-01');
    expect(snapshot.verifiedCheckCount, 1);
    expect(snapshot.requiredCheckCount, 2);
    expect(snapshot.latestAttempt, 1);
    expect(snapshot.latestReasons, hasLength(1));
    expect(snapshot.referenceRatePerKg, 42);
    expect(snapshot.isSaleBlocked, isTrue);
  });

  test('marks compliant harvest as FPC exclusive', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'enrollment': {'id': 'enrollment-1', 'status': 'compliant'},
    });

    expect(snapshot.isExclusive, isTrue);
    expect(snapshot.isSaleBlocked, isFalse);
  });

  test('parses Farmer seed request context before enrollment', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'seed_request': {
        'id': 'request-1',
        'status': 'submitted',
        'requested_quantity_kg': 12.5,
        'farmer_note': 'Need before sowing',
        'program': {'name': 'Kharif Ragi 2026'},
        'fpc': {'name': 'Kalsubai FPC'},
      },
      'available_programs': [
        {
          'id': 'program-1',
          'name': 'Kharif Ragi 2026',
          'fpc_name': 'Kalsubai FPC',
          'request_allowed': true,
        },
      ],
    });

    expect(snapshot.exists, isFalse);
    expect(snapshot.hasContext, isTrue);
    expect(snapshot.hasActiveSeedRequest, isTrue);
    expect(snapshot.requestedQuantityKg, 12.5);
    expect(snapshot.requestedProgramName, 'Kharif Ragi 2026');
    expect(snapshot.sponsorName, 'Kalsubai FPC');
    expect(snapshot.canRequestSeed, isFalse);
  });

  test(
    'keeps matching programs visible when Farmer verification is pending',
    () {
      final snapshot = FpcCropProgramSnapshot.fromJson({
        'available_programs': [
          {
            'id': 'program-1',
            'name': 'Bajra 2002',
            'fpc_name': 'MilletsNow',
            'farm_matches_crop': true,
            'request_allowed': false,
          },
        ],
      });

      expect(snapshot.hasContext, isTrue);
      expect(snapshot.availablePrograms, hasLength(1));
      expect(snapshot.requestablePrograms, isEmpty);
      expect(snapshot.hasFarmMatchingProgram, isTrue);
      expect(snapshot.canRequestSeed, isFalse);
    },
  );

  test('keeps FPC programs visible for a different selected farm crop', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'available_programs': [
        {
          'id': 'program-1',
          'name': 'Bajra 2002',
          'fpc_name': 'MilletsNow',
          'farm_matches_crop': false,
          'request_allowed': false,
        },
      ],
    });

    expect(snapshot.hasContext, isTrue);
    expect(snapshot.availablePrograms, hasLength(1));
    expect(snapshot.hasFarmMatchingProgram, isFalse);
    expect(snapshot.requestablePrograms, isEmpty);
  });

  test('exposes priced certified batch cards for an unsown farm', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'seed_buying_eligible': true,
      'available_batches': [
        {
          'id': 'batch-1',
          'unit_price_paise': 4250,
          'sellable_quantity_kg': 80,
          'request_allowed': true,
        },
      ],
    });

    expect(snapshot.seedBuyingEligible, isTrue);
    expect(snapshot.requestableBatches, hasLength(1));
    expect(snapshot.canRequestSeed, isTrue);
  });

  test('blocks new buying when the server marks a farm as sown', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'seed_buying_eligible': false,
      'available_batches': [
        {
          'id': 'batch-1',
          'unit_price_paise': 4250,
          'sellable_quantity_kg': 80,
          'request_allowed': true,
        },
      ],
    });

    expect(snapshot.seedBuyingEligible, isFalse);
    expect(snapshot.canRequestSeed, isFalse);
  });

  test('allows checkout only during an approved active reservation', () {
    final snapshot = FpcCropProgramSnapshot.fromJson({
      'seed_request': {
        'id': 'request-1',
        'status': 'approved',
        'payment_status': 'awaiting_payment',
        'unit_price_paise': 4250,
        'amount_paise': 42500,
        'reservation_expires_at': DateTime.now()
            .add(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
      },
    });

    expect(snapshot.seedRequestUnitPricePaise, 4250);
    expect(snapshot.seedRequestAmountPaise, 42500);
    expect(snapshot.canPaySeedRequest, isTrue);
    expect(snapshot.seedPaymentCaptured, isFalse);
  });
}
