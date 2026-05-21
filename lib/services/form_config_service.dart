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

    // "Other Crops" duplicates the "Kharif Crops" editor — the "Other" choice
    // now lives inside the Kharif crop-name dropdown, so drop the standalone
    // section here. (Ideally also deactivated in Supabase form_sections.)
    sections.removeWhere((s) => s.title == 'Other Crops');

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

  Future<List<Map<String, dynamic>>> fetchDropdownOptionRows() async {
    final data = await _client
        .from('dropdown_options')
        .select('option_key,value,label,label_hi,label_mr,sort_order')
        .eq('is_active', true)
        .order('sort_order');

    return (data as List).cast<Map<String, dynamic>>();
  }
}
