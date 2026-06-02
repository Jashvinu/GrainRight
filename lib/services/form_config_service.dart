import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/offline_form_seed.dart';
import '../models/form_config.dart';
import 'local_app_database.dart';
import 'network_status_service.dart';

class FormConfigService {
  static const sectionsCacheKey = 'form_sections_config_cache_v1';
  static const dropdownOptionsCacheKey = 'dropdown_options_cache_v1';
  static const dropdownOptionRowsCacheKey = 'dropdown_option_rows_cache_v1';
  static const _offlineFallbackTimeout = Duration(milliseconds: 650);

  final SupabaseClient _client;
  final NetworkStatusService? _networkStatusService;
  final LocalAppDatabase? _db;
  Future<bool>? _shouldFetchRemoteFuture;

  FormConfigService({
    SupabaseClient? client,
    NetworkStatusService? networkStatusService,
    LocalAppDatabase? database,
  }) : _client = client ?? Supabase.instance.client,
       _networkStatusService = networkStatusService ?? NetworkStatusService(),
       _db = database ?? LocalAppDatabase.maybeInstance;

  Future<List<FormSectionConfig>> fetchFormConfig() async {
    final cached = await _cachedList(sectionsCacheKey);
    if (cached != null) {
      final sections = _sectionsFromRows(cached);
      if (_hasRequiredSections(sections)) {
        unawaited(_refreshFormConfigCache());
        return sections;
      }
      debugPrint('[FormConfigService] Ignoring incomplete cached form config');
    }

    final remote = await _fetchRemoteFormConfig();
    if (remote != null) return remote;
    return OfflineFormSeed.sections();
  }

  Future<Map<String, List<String>>> fetchDropdownOptions() async {
    final cached = await _cachedList(dropdownOptionsCacheKey);
    if (cached != null) {
      final options = _dropdownMapFromRows(cached);
      if (_hasRequiredDropdowns(options)) {
        unawaited(_refreshDropdownOptionsCache());
        return options;
      }
      debugPrint('[FormConfigService] Ignoring incomplete cached dropdowns');
    }

    final remote = await _fetchRemoteDropdownOptions();
    if (remote != null) return remote;
    return OfflineFormSeed.dropdownOptions();
  }

  Future<List<Map<String, dynamic>>> fetchDropdownOptionRows() async {
    final cached = await _cachedList(dropdownOptionRowsCacheKey);
    if (cached != null) {
      final rows = _mapRows(cached);
      if (_hasRequiredDropdownRows(rows)) {
        unawaited(_refreshDropdownOptionRowsCache());
        return rows;
      }
      debugPrint('[FormConfigService] Ignoring incomplete cached labels');
    }

    final remote = await _fetchRemoteDropdownOptionRows();
    if (remote != null) return remote;
    return OfflineFormSeed.dropdownRows();
  }

  Future<List<FormSectionConfig>?> _fetchRemoteFormConfig() async {
    if (!await _shouldFetchRemote()) return null;
    try {
      final data = await _client
          .from('form_sections')
          .select('*, form_fields(*)')
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(sectionsCacheKey, data as List);
      final sections = _sectionsFromRows(data);
      if (_hasRequiredSections(sections)) return sections;
    } catch (e) {
      debugPrint('[FormConfigService] Remote form config failed: $e');
    }
    return null;
  }

  Future<void> _refreshFormConfigCache() async {
    await _fetchRemoteFormConfig();
  }

  Future<Map<String, List<String>>?> _fetchRemoteDropdownOptions() async {
    if (!await _shouldFetchRemote()) return null;
    try {
      final data = await _client
          .from('dropdown_options')
          .select()
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(dropdownOptionsCacheKey, data as List);
      final options = _dropdownMapFromRows(data);
      if (_hasRequiredDropdowns(options)) return options;
    } catch (e) {
      debugPrint('[FormConfigService] Remote dropdown options failed: $e');
    }
    return null;
  }

  Future<void> _refreshDropdownOptionsCache() async {
    await _fetchRemoteDropdownOptions();
  }

  Future<List<Map<String, dynamic>>?> _fetchRemoteDropdownOptionRows() async {
    if (!await _shouldFetchRemote()) return null;
    try {
      final data = await _client
          .from('dropdown_options')
          .select('option_key,value,label,label_hi,label_mr,sort_order')
          .eq('is_active', true)
          .order('sort_order');
      await _cacheList(dropdownOptionRowsCacheKey, data as List);
      final rows = _mapRows(data);
      if (_hasRequiredDropdownRows(rows)) return rows;
    } catch (e) {
      debugPrint('[FormConfigService] Remote dropdown labels failed: $e');
    }
    return null;
  }

  Future<void> _refreshDropdownOptionRowsCache() async {
    await _fetchRemoteDropdownOptionRows();
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

  Future<bool> _shouldFetchRemote() async {
    final inFlight = _shouldFetchRemoteFuture;
    if (inFlight != null) return inFlight;

    final networkStatusService = _networkStatusService;
    if (networkStatusService == null) return true;
    final future = networkStatusService.isOnline(
      timeout: _offlineFallbackTimeout,
    );
    _shouldFetchRemoteFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_shouldFetchRemoteFuture, future)) {
        _shouldFetchRemoteFuture = null;
      }
    }
  }

  Future<void> _cacheList(String key, List data) async {
    final db = _db;
    if (db != null) {
      try {
        await db.cacheFormList(key: key, data: data);
      } catch (e) {
        debugPrint('[FormConfigService] Database cache write failed: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('[FormConfigService] Preferences cache write failed: $e');
    }
  }

  Future<List<dynamic>?> _cachedList(String key) async {
    final db = _db;
    if (db != null) {
      try {
        final record = await db.readFormList(key);
        if (record != null) return record.payload;
      } catch (e) {
        debugPrint('[FormConfigService] Database cache read failed: $e');
      }
    }
    return _legacyCachedList(key);
  }

  Future<List<dynamic>?> _legacyCachedList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final db = _db;
        if (db != null) {
          try {
            await db.cacheFormList(key: key, data: decoded);
          } catch (e) {
            debugPrint('[FormConfigService] Cache migration failed: $e');
          }
        }
        return decoded;
      }
    } catch (e) {
      debugPrint('[FormConfigService] Legacy cache read failed: $e');
    }
    return null;
  }

  bool _hasRequiredSections(List<FormSectionConfig> sections) {
    return sections
        .expand((section) => section.fields)
        .any((field) => field.fieldKey == 'farmer_name');
  }

  bool _hasRequiredDropdownRows(List<Map<String, dynamic>> rows) {
    return _hasRequiredDropdowns(_dropdownMapFromRows(rows));
  }

  bool _hasRequiredDropdowns(Map<String, List<String>> options) {
    return options['main_crop_v2']?.contains('paddy') == true &&
        options['income_sources_v2']?.contains('farming') == true;
  }
}
