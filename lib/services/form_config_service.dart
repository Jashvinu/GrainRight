import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/form_config.dart';

class FormConfigService {
  static const _sectionsCacheKey = 'form_sections_config_cache_v1';
  static const _dropdownOptionsCacheKey = 'dropdown_options_cache_v1';
  static const _dropdownOptionRowsCacheKey = 'dropdown_option_rows_cache_v1';

  final _client = Supabase.instance.client;

  Future<List<FormSectionConfig>> fetchFormConfig() async {
    try {
      final data = await _client
          .from('form_sections')
          .select('*, form_fields(*)')
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(_sectionsCacheKey, data as List);
      return _sectionsFromRows(data);
    } catch (e) {
      final cached = await _cachedList(_sectionsCacheKey);
      if (cached != null) {
        debugPrint('[FormConfigService] Using cached form config: $e');
        return _sectionsFromRows(cached);
      }
      rethrow;
    }
  }

  Future<Map<String, List<String>>> fetchDropdownOptions() async {
    try {
      final data = await _client
          .from('dropdown_options')
          .select()
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(_dropdownOptionsCacheKey, data as List);
      return _dropdownMapFromRows(data);
    } catch (e) {
      final cached = await _cachedList(_dropdownOptionsCacheKey);
      if (cached != null) {
        debugPrint('[FormConfigService] Using cached dropdown options: $e');
        return _dropdownMapFromRows(cached);
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDropdownOptionRows() async {
    try {
      final data = await _client
          .from('dropdown_options')
          .select('option_key,value,label,label_hi,label_mr,sort_order')
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(_dropdownOptionRowsCacheKey, data as List);
      return _mapRows(data);
    } catch (e) {
      final cached = await _cachedList(_dropdownOptionRowsCacheKey);
      if (cached != null) {
        debugPrint('[FormConfigService] Using cached dropdown labels: $e');
        return _mapRows(cached);
      }
      rethrow;
    }
  }

  List<FormSectionConfig> _sectionsFromRows(List data) {
    final sections =
        data
            .map((e) => FormSectionConfig.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // "Other Crops" duplicates the "Kharif Crops" editor — the "Other" choice
    // now lives inside the Kharif crop-name dropdown, so drop the standalone
    // section here. (Ideally also deactivated in Supabase form_sections.)
    sections.removeWhere((s) => s.title == 'Other Crops');

    return sections;
  }

  Map<String, List<String>> _dropdownMapFromRows(List data) {
    final map = <String, List<String>>{};
    for (final row in data) {
      final key = row['option_key'] as String;
      final value = row['value'] as String;
      map.putIfAbsent(key, () => []).add(value);
    }
    return map;
  }

  List<Map<String, dynamic>> _mapRows(List data) {
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _cacheList(String key, List data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  Future<List<dynamic>?> _cachedList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : null;
  }
}
