import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/config/offline_form_seed.dart';

void main() {
  test('built-in offline form starts with Farmer Name', () {
    final sections = OfflineFormSeed.sections();

    expect(sections, isNotEmpty);
    expect(sections.first.fields, isNotEmpty);
    expect(sections.first.fields.first.fieldKey, 'farmer_name');
    expect(sections.first.fields.first.label, 'Farmer Name');
    expect(sections.first.fields.first.isRequired, isTrue);
  });

  test('built-in offline form includes boundary polygon storage field', () {
    final fields = OfflineFormSeed.sections().expand(
      (section) => section.fields,
    );

    final polygon = fields.singleWhere(
      (field) => field.fieldKey == 'farm_polygon',
    );
    expect(polygon.inputType, 'polygon_pencil');
  });

  test('built-in offline form has one cultivation cost income field', () {
    final fields = OfflineFormSeed.sections()
        .expand((section) => section.fields)
        .toList();

    expect(
      fields.where(
        (field) =>
            field.fieldKey == 'avg_cost_cultivation_millets' ||
            field.fieldKey == 'avg_cost_cultivation_other',
      ),
      isEmpty,
    );

    final totalCost = fields.singleWhere(
      (field) => field.fieldKey == 'total_cultivation_cost',
    );
    expect(totalCost.inputType, 'currency');

    final totalIncome = fields.singleWhere(
      (field) => field.fieldKey == 'total_annual_income',
    );
    expect(totalIncome.autoCalcFormula?['operation'], 'sum_then_subtract_last');
    expect(totalIncome.autoCalcFormula?['operands'], [
      'annual_agri_income',
      'non_agri_income',
      'total_cultivation_cost',
    ]);
  });

  test('Kharif crop selector is available for every main crop', () {
    final fields = OfflineFormSeed.sections()
        .expand((section) => section.fields)
        .toList();

    final kharif = fields.singleWhere(
      (field) => field.fieldKey == 'repeat_kharif_crops',
    );

    expect(kharif.visibilityRule, isNull);
  });
}
