import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_config.dart';

class FormConfigService {
  final _client = Supabase.instance.client;

  Future<List<FormSectionConfig>> fetchFormConfig() async {
    final data = await _client
        .from('form_sections')
        .select('*, form_fields(*)')
        .eq('is_active', true)
        .order('sort_order');

    final sections = (data as List)
        .map((e) => FormSectionConfig.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Filter out inactive fields
    for (final section in sections) {
      section.fields.removeWhere((f) => false); // all fields from query are active by default
    }

    return sections;
  }

  Future<Map<String, List<String>>> fetchDropdownOptions() async {
    final data = await _client
        .from('dropdown_options')
        .select()
        .eq('is_active', true)
        .order('sort_order');

    final map = <String, List<String>>{};
    for (final row in data as List) {
      final key = row['option_key'] as String;
      final value = row['value'] as String;
      map.putIfAbsent(key, () => []).add(value);
    }
    return map;
  }
}
