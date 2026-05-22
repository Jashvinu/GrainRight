import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_survey.dart';

class SurveyService {
  static const kharifRowsKey = '__kharif_rows';
  static const yearlyRowsKey = '__yearly_rows';
  static const practiceRowsKey = '__practice_rows';

  final _client = Supabase.instance.client;
  dynamic get _table => _client.from('farmer_surveys');

  Future<List<FarmerSurvey>> fetchAll() async {
    final data = await _table.select().order('created_at', ascending: false);
    return (data as List).map((e) => FarmerSurvey.fromJson(e)).toList();
  }

  Future<FarmerSurvey> fetchById(String id) async {
    final data = await _table.select().eq('id', id).single();
    return FarmerSurvey.fromJson(data);
  }

  Future<Map<String, dynamic>> fetchEditableById(String id) async {
    final parent = await _table.select().eq('id', id).single();
    final rows = await Future.wait([
      _client
          .from('survey_kharif_crops')
          .select()
          .eq('survey_id', id)
          .order('position'),
      _client
          .from('survey_main_crop_yearly')
          .select()
          .eq('survey_id', id)
          .order('year'),
      _client
          .from('survey_crop_practices')
          .select()
          .eq('survey_id', id)
          .order('crop_role'),
    ]);

    return {
      ...Map<String, dynamic>.from(parent as Map),
      kharifRowsKey: _flattenRows(rows[0]),
      yearlyRowsKey: _flattenRows(rows[1]),
      practiceRowsKey: _flattenRows(rows[2]),
    };
  }

  Future<Map<String, dynamic>?> fetchLatestWithPolygon() async {
    final data = await _table
        .select()
        .not('farm_polygon', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);
    final rows = data as List;
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
  }

  Future<void> insert(Map<String, dynamic> survey) async {
    await _table.insert(survey);
  }

  Future<String> insertWithChildren(
    Map<String, dynamic> parent,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) async {
    String? surveyId;
    try {
      final inserted = await _table.insert(parent).select('id').single();
      surveyId = inserted['id'] as String;

      if (kharif.isNotEmpty) {
        await _client
            .from('survey_kharif_crops')
            .insert(
              _storageRows(
                kharif,
                _kharifCropColumns,
              ).map((row) => {...row, 'survey_id': surveyId}).toList(),
            );
      }
      if (yearly.isNotEmpty) {
        await _client
            .from('survey_main_crop_yearly')
            .insert(
              _storageRows(
                yearly,
                _yearlyCropColumns,
              ).map((row) => {...row, 'survey_id': surveyId}).toList(),
            );
      }
      if (practices.isNotEmpty) {
        await _client
            .from('survey_crop_practices')
            .insert(
              _storageRows(
                practices,
                _cropPracticeColumns,
              ).map((row) => {...row, 'survey_id': surveyId}).toList(),
            );
      }

      return surveyId;
    } catch (_) {
      if (surveyId != null) {
        await _table.delete().eq('id', surveyId);
      }
      rethrow;
    }
  }

  Future<void> update(String id, Map<String, dynamic> survey) async {
    await _table.update(survey).eq('id', id);
  }

  Future<void> updateWithChildren(
    String id,
    Map<String, dynamic> survey,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) async {
    await _table.update(survey).eq('id', id);
    await _replaceRows(
      table: 'survey_kharif_crops',
      surveyId: id,
      rows: kharif,
      columns: _kharifCropColumns,
    );
    await _replaceRows(
      table: 'survey_main_crop_yearly',
      surveyId: id,
      rows: yearly,
      columns: _yearlyCropColumns,
    );
    await _replaceRows(
      table: 'survey_crop_practices',
      surveyId: id,
      rows: practices,
      columns: _cropPracticeColumns,
    );
  }

  Future<bool> delete(String id) async {
    final rows = await _table.delete().eq('id', id).select('id');
    return rows is List && rows.isNotEmpty;
  }

  Future<void> _replaceRows({
    required String table,
    required String surveyId,
    required List<Map<String, dynamic>> rows,
    required Set<String> columns,
  }) async {
    await _client.from(table).delete().eq('survey_id', surveyId);
    final storageRows = _storageRows(
      rows,
      columns,
    ).map((row) => {...row, 'survey_id': surveyId}).toList();
    if (storageRows.isNotEmpty) {
      await _client.from(table).insert(storageRows);
    }
  }

  List<Map<String, dynamic>> _storageRows(
    List<Map<String, dynamic>> rows,
    Set<String> columns,
  ) {
    return rows
        .map((row) => _storageRow(row, columns))
        .where((row) => row.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _storageRow(
    Map<String, dynamic> row,
    Set<String> columns,
  ) {
    final output = <String, dynamic>{};
    final extra = <String, dynamic>{};

    for (final entry in row.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null || _systemRowKeys.contains(key)) continue;
      if (key == 'extra_details') {
        if (value is Map) {
          value.forEach((k, v) {
            if (v != null) extra[k.toString()] = v;
          });
        }
        continue;
      }
      if (columns.contains(key)) {
        output[key] = value;
      } else {
        extra[key] = value;
      }
    }

    if (extra.isNotEmpty && columns.contains('extra_details')) {
      output['extra_details'] = extra;
    }
    return output;
  }

  List<Map<String, dynamic>> _flattenRows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => _flattenExtraDetails(Map<String, dynamic>.from(row)))
        .toList();
  }

  Map<String, dynamic> _flattenExtraDetails(Map<String, dynamic> row) {
    final source = Map<String, dynamic>.from(row)
      ..removeWhere((key, _) => _systemRowKeys.contains(key));
    final extra = source.remove('extra_details');
    if (extra is Map) {
      extra.forEach((key, value) {
        source.putIfAbsent(key.toString(), () => value);
      });
    }
    return source;
  }
}

const _systemRowKeys = {'id', 'survey_id', 'created_at', 'updated_at'};

const _kharifCropColumns = {
  'position',
  'crop_name',
  'cultivated_area_acre',
  'crop_variety',
  'production_qty',
  'avg_estimated_cost',
  'extra_details',
};

const _yearlyCropColumns = {
  'year',
  'area_acre',
  'total_production',
  'home_consumption',
  'quantity_sold',
  'sold_where',
  'selling_price',
  'extra_details',
};

const _cropPracticeColumns = {
  'crop_role',
  'grown_on',
  'same_land_every_year',
  'land_topology',
  'land_topology_other',
  'seed_sources',
  'seed_source_other',
  'pop_training_received',
  'pop_training_source',
  'farming_method',
  'treats_seeds',
  'seed_treatment_materials',
  'seedling_method',
  'seedling_method_other',
  'seedling_ready_days',
  'seedling_method_difference',
  'land_prep_tractor_days',
  'land_prep_tractor_cost',
  'land_prep_bullock_days',
  'land_prep_bullock_cost',
  'land_prep_by_hand',
  'transplant_method',
  'dip_in_jeevamrut',
  'plant_spacing_cm',
  'transplant_days',
  'needs_transplant_labour',
  'transplant_labourers',
  'transplant_daily_wage',
  'does_weeding',
  'weeding_after_days',
  'sprays_for_pest',
  'spray_methods',
  'matka_per_acre',
  'neem_per_acre',
  'spray_methods_other',
  'organic_fert_helps_disease',
  'planting_to_flowering_days',
  'uses_fertilizer',
  'fertilizer_names',
  'fertilizer_qty_per_acre',
  'flowering_pest_problem',
  'flowering_pest_type',
  'flowering_sprays_used',
  'maturity_days',
  'monitors_crop',
  'monitoring_methods',
  'harvest_method',
  'harvest_labour_type',
  'harvest_daily_wage',
  'harvest_labourers',
  'harvest_days',
  'ready_to_eat_or_sell_days',
  'sells_main_crop',
  'selling_time',
  'extra_details',
};
