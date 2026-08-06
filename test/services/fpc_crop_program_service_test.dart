import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/services/fpc_crop_program_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('FpcCropProgramService unavailable farm handling', () {
    test('recognizes the linked-farm P0001 response', () {
      const error = PostgrestException(
        message: 'Farmer farm not found',
        code: 'P0001',
      );

      expect(FpcCropProgramService.isUnavailableFarmerFarmError(error), isTrue);
    });

    test('does not hide unrelated database failures', () {
      const differentMessage = PostgrestException(
        message: 'Crop program is not active',
        code: 'P0001',
      );
      const differentCode = PostgrestException(
        message: 'Farmer farm not found',
        code: '42501',
      );

      expect(
        FpcCropProgramService.isUnavailableFarmerFarmError(differentMessage),
        isFalse,
      );
      expect(
        FpcCropProgramService.isUnavailableFarmerFarmError(differentCode),
        isFalse,
      );
    });
  });
}
