import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_survey.dart';

class SurveyService {
  final _table = Supabase.instance.client.from('farmer_surveys');

  Future<List<FarmerSurvey>> fetchAll() async {
    final data = await _table.select().order('created_at', ascending: false);
    return (data as List).map((e) => FarmerSurvey.fromJson(e)).toList();
  }

  Future<FarmerSurvey> fetchById(String id) async {
    final data = await _table.select().eq('id', id).single();
    return FarmerSurvey.fromJson(data);
  }

  Future<void> insert(Map<String, dynamic> survey) async {
    await _table.insert(survey);
  }

  Future<void> update(String id, Map<String, dynamic> survey) async {
    await _table.update(survey).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _table.delete().eq('id', id);
  }
}
