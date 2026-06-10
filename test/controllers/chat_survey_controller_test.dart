import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/config/offline_form_seed.dart';
import 'package:kalsubai_farms/controllers/chat_survey_controller.dart';

void main() {
  test('fresh offline chat flow starts at Farmer Name', () {
    final keys = ChatSurveyController.debugStepKeysForSections(
      OfflineFormSeed.sections(),
    );

    expect(keys, isNotEmpty);
    expect(keys.first, 'farmer_name');
  });

  test('production history stays after the main crop questions', () {
    final keys = ChatSurveyController.debugStepKeysForSections(
      OfflineFormSeed.sections(),
    );

    final farmerName = keys.indexOf('farmer_name');
    final mainCrop = keys.indexOf('main_crop');
    final mainCropLand = keys.indexOf('main_crop_land_acre');
    final productionHistory = keys.indexOf('repeat:main_crop_yearly');

    expect(farmerName, 0);
    expect(mainCrop, greaterThan(farmerName));
    expect(mainCropLand, greaterThan(mainCrop));
    expect(productionHistory, greaterThan(mainCropLand));
  });

  test(
    'rice/ragi agronomy appears before bajra/other when rice/ragi is first',
    () {
      final keys = ChatSurveyController.debugStepKeysForSections(
        OfflineFormSeed.sections(),
        cropPracticeRoleOrder: const ['main', 'other'],
      );

      final kharif = keys.indexOf('repeat:kharif_crops');
      final riceRagiPractices = keys.indexOf('repeat:crop_practices:main');
      final bajraOtherPractices = keys.indexOf('repeat:crop_practices:other');
      final productionHistory = keys.indexOf('repeat:main_crop_yearly');

      expect(kharif, greaterThan(keys.indexOf('main_crop_land_acre')));
      expect(riceRagiPractices, greaterThan(kharif));
      expect(bajraOtherPractices, greaterThan(riceRagiPractices));
      expect(productionHistory, greaterThan(bajraOtherPractices));
    },
  );

  test('bajra/other agronomy appears before rice/ragi when bajra is first', () {
    final keys = ChatSurveyController.debugStepKeysForSections(
      OfflineFormSeed.sections(),
      cropPracticeRoleOrder: const ['other', 'main'],
    );

    final kharif = keys.indexOf('repeat:kharif_crops');
    final bajraOtherPractices = keys.indexOf('repeat:crop_practices:other');
    final riceRagiPractices = keys.indexOf('repeat:crop_practices:main');
    final productionHistory = keys.indexOf('repeat:main_crop_yearly');

    expect(kharif, greaterThan(keys.indexOf('main_crop_land_acre')));
    expect(bajraOtherPractices, greaterThan(kharif));
    expect(riceRagiPractices, greaterThan(bajraOtherPractices));
    expect(productionHistory, greaterThan(riceRagiPractices));
  });

  test('first Kharif crop decides crop practice role order', () {
    expect(
      ChatSurveyController.debugCropPracticeRoleOrder(
        mainCrop: 'paddy',
        kharifRows: const [
          {'crop_name': 'bajra'},
        ],
      ),
      const ['other', 'main'],
    );

    expect(
      ChatSurveyController.debugCropPracticeRoleOrder(
        mainCrop: 'bajra',
        kharifRows: const [
          {'crop_name': 'nachani'},
        ],
      ),
      const ['main', 'other'],
    );
  });

  test('main agronomy title follows selected Kharif crop group', () {
    final titles = ChatSurveyController.debugRepeatStepTitlesForSections(
      OfflineFormSeed.sections(),
      cropPracticeRoleOrder: const ['other', 'main'],
    );

    expect(titles, contains('Main Crop Agronomy - Bajra/Other crop practices'));
    expect(titles, contains('Other Crop Agronomy - Rice/Ragi crop practices'));
  });

  test('other agronomy title shows opposite crop group', () {
    final titles = ChatSurveyController.debugRepeatStepTitlesForSections(
      OfflineFormSeed.sections(),
      cropPracticeRoleOrder: const ['main', 'other'],
    );

    expect(titles, contains('Main Crop Agronomy - Rice/Ragi crop practices'));
    expect(
      titles,
      contains('Other Crop Agronomy - Bajra/Other crop practices'),
    );
  });
}
