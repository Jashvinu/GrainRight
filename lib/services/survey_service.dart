import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_survey.dart';

class SurveyService {
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
      final inserted = await _table
          .insert(parent)
          .select('id')
          .single();
      surveyId = inserted['id'] as String;

      if (kharif.isNotEmpty) {
        await _client.from('survey_kharif_crops').insert(
              kharif.map((row) => {...row, 'survey_id': surveyId}).toList(),
            );
      }
      if (yearly.isNotEmpty) {
        await _client.from('survey_main_crop_yearly').insert(
              yearly.map((row) => {...row, 'survey_id': surveyId}).toList(),
            );
      }
      if (practices.isNotEmpty) {
        await _client.from('survey_crop_practices').insert(
              practices.map((row) => {...row, 'survey_id': surveyId}).toList(),
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

  Future<void> delete(String id) async {
    await _table.delete().eq('id', id);
  }
}
