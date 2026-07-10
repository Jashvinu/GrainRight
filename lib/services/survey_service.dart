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

  Future<Map<String, dynamic>?> fetchLatestWithPolygonForPhone(
    String phoneDigits,
  ) async {
    final normalizedPhone = phoneDigits.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone.isEmpty) return null;

    final data = await _table
        .select()
        .not('farm_polygon', 'is', null)
        .order('created_at', ascending: false)
        .limit(30);
    final rows = data as List;
    for (final row in rows) {
      if (row is! Map) continue;
      final survey = Map<String, dynamic>.from(row);
      final surveyPhone = '${survey['mobile_number'] ?? ''}'.replaceAll(
        RegExp(r'\D'),
        '',
      );
      if (surveyPhone.isEmpty) continue;
      if (surveyPhone == normalizedPhone ||
          surveyPhone.endsWith(normalizedPhone) ||
          normalizedPhone.endsWith(surveyPhone)) {
        return survey;
      }
    }
    return null;
  }

  Future<void> insert(Map<String, dynamic> survey) async {
    await insertWithChildren(survey, const [], const [], const []);
  }

  Future<String> insertWithChildren(
    Map<String, dynamic> parent,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) async {
    String? surveyId;
    final storageParent = _storageParent(parent);
    final clientUuid = storageParent['client_uuid']?.toString();
    surveyId = await _findSurveyIdByClientUuid(clientUuid);
    if (surveyId != null) {
      await _table.update(storageParent).eq('id', surveyId);
      await _replaceRows(
        table: 'survey_kharif_crops',
        surveyId: surveyId,
        rows: kharif,
        columns: _kharifCropColumns,
      );
      await _replaceRows(
        table: 'survey_main_crop_yearly',
        surveyId: surveyId,
        rows: yearly,
        columns: _yearlyCropColumns,
      );
      await _replaceRows(
        table: 'survey_crop_practices',
        surveyId: surveyId,
        rows: practices,
        columns: _cropPracticeColumns,
      );
      return surveyId;
    }

    try {
      final inserted = await _table.insert(storageParent).select('id').single();
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
    } on PostgrestException catch (e) {
      final existingId = await _findSurveyIdAfterConflict(e, clientUuid);
      if (existingId != null) {
        await _table.update(storageParent).eq('id', existingId);
        await _replaceRows(
          table: 'survey_kharif_crops',
          surveyId: existingId,
          rows: kharif,
          columns: _kharifCropColumns,
        );
        await _replaceRows(
          table: 'survey_main_crop_yearly',
          surveyId: existingId,
          rows: yearly,
          columns: _yearlyCropColumns,
        );
        await _replaceRows(
          table: 'survey_crop_practices',
          surveyId: existingId,
          rows: practices,
          columns: _cropPracticeColumns,
        );
        return existingId;
      }
      if (surveyId != null) {
        await _table.delete().eq('id', surveyId);
      }
      rethrow;
    } catch (_) {
      if (surveyId != null) {
        await _table.delete().eq('id', surveyId);
      }
      rethrow;
    }
  }

  Future<void> update(String id, Map<String, dynamic> survey) async {
    await _table.update(_storageParent(survey)).eq('id', id);
  }

  Future<void> updateWithChildren(
    String id,
    Map<String, dynamic> survey,
    List<Map<String, dynamic>> kharif,
    List<Map<String, dynamic>> yearly,
    List<Map<String, dynamic>> practices,
  ) async {
    await _table.update(_storageParent(survey)).eq('id', id);
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

  Future<String?> _findSurveyIdAfterConflict(
    PostgrestException error,
    String? clientUuid,
  ) async {
    if (clientUuid == null || clientUuid.isEmpty) return null;
    if (error.code != '23505' && !error.message.contains('client_uuid')) {
      return null;
    }
    return _findSurveyIdByClientUuid(clientUuid);
  }

  Future<String?> _findSurveyIdByClientUuid(String? clientUuid) async {
    if (clientUuid == null || clientUuid.isEmpty) return null;
    final rows = await _table
        .select('id')
        .eq('client_uuid', clientUuid)
        .limit(1);
    if (rows is! List || rows.isEmpty) return null;
    final first = rows.first;
    if (first is! Map) return null;
    return first['id']?.toString();
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

  Map<String, dynamic> _storageParent(Map<String, dynamic> parent) {
    final output = <String, dynamic>{};
    final extra = <String, dynamic>{};

    final existingExtra = parent['extra_details'];
    if (existingExtra is Map) {
      existingExtra.forEach((key, value) {
        if (value == null) return;
        final columnKey = key.toString();
        if (_farmerSurveyColumns.contains(columnKey)) {
          output[columnKey] = value;
        } else if (columnKey != 'cropping_pattern') {
          extra[columnKey] = value;
        }
      });
      final croppingPattern = existingExtra['cropping_pattern'];
      if (croppingPattern is Map) {
        final disease = croppingPattern['disease'];
        if (disease is Map) {
          disease.forEach((key, value) {
            if (value == null) return;
            final columnKey = key.toString();
            if (_farmerSurveyColumns.contains(columnKey)) {
              output.putIfAbsent(columnKey, () => value);
            }
          });
        }
      }
    }

    for (final entry in parent.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null ||
          key == 'extra_details' ||
          _systemParentKeys.contains(key)) {
        continue;
      }

      if (_farmerSurveyColumns.contains(key)) {
        output[key] = value;
      } else {
        extra[key] = value;
      }
    }

    if (_farmerSurveyColumns.contains('total_cultivation_cost')) {
      output['total_cultivation_cost'] = _toNumericOrZero(
        output['total_cultivation_cost'],
      );
    }

    if (extra.isNotEmpty) output['extra_details'] = extra;
    return output;
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
            if (v == null) return;
            final columnKey = k.toString();
            if (columns.contains(columnKey)) {
              output[columnKey] = v;
            } else {
              extra[columnKey] = v;
            }
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

    if (columns.contains('sold_where_options') &&
        !output.containsKey('sold_where_options')) {
      output['sold_where_options'] = <String>[];
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

  double _toNumericOrZero(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }
}

const _systemRowKeys = {'id', 'survey_id', 'created_at', 'updated_at'};
const _systemParentKeys = {'id', 'created_at', 'updated_at'};

const _farmerSurveyColumns = {
  'client_uuid',
  'user_id',
  'survey_date',
  'language',
  'location_lat',
  'location_lng',
  'location_accuracy_m',
  'started_at',
  'submitted_at',
  'farmer_name',
  'village',
  'gram_panchayat',
  'taluka',
  'district',
  'mobile_number',
  'aadhaar_number',
  'date_of_birth',
  'education',
  'gender',
  'category',
  'income_sources',
  'income_sources_other',
  'farming_type',
  'farming_type_other',
  'owns_farmland',
  'total_land_area_acre',
  'irrigated_land_acre',
  'dry_land_acre',
  'fallow_land_acre',
  'leased_land_acre',
  'rain_based_area_acre',
  'has_forest_patta',
  'forest_patta_acre',
  'applied_for_forest_patta',
  'main_crop',
  'main_crop_other',
  'main_crop_land_acre',
  'other_crop_land_acre',
  'other_crop_details',
  'farm_polygon',
  'annual_agri_income',
  'non_agri_income',
  'total_cultivation_cost',
  'total_annual_income',
  'makes_food_products',
  'food_products_list',
  'food_product_training_received',
  'food_product_training_source',
  'disease_present',
  'disease_name',
  'affected_crop',
  'disease_severity',
  'symptoms_observed',
  'treatment_taken',
};

const _kharifCropColumns = {
  'position',
  'crop_name',
  'other_crop_name',
  'other_crop_details',
  'cultivated_area_acre',
  'crop_variety',
  'production_qty',
  'production_qty_unit',
  'avg_estimated_cost',
  'extra_details',
};

const _yearlyCropColumns = {
  'year',
  'area_acre',
  'total_production',
  'total_production_unit',
  'yield_avg_per_acre',
  'yield_avg_per_acre_unit',
  'home_consumption',
  'home_consumption_unit',
  'quantity_sold',
  'quantity_sold_unit',
  'sold_where',
  'sold_where_options',
  'sold_where_other',
  'selling_price',
  'extra_details',
};

const _cropPracticeColumns = {
  'crop_role',
  'grown_on',
  'grown_on_other',
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
  'seed_treatment_materials_other',
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
  'transplant_method_other',
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
  'matka_per_acre_unit',
  'neem_per_acre',
  'neem_per_acre_unit',
  'jeevamrut_per_acre',
  'jeevamrut_per_acre_unit',
  'pesticide_per_acre',
  'pesticide_per_acre_unit',
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
  'monitoring_methods_other',
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
