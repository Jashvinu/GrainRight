import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kalsubai_farms/services/form_config_service.dart';
import 'package:kalsubai_farms/services/network_status_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FormConfigService service;
  late _OfflineNetworkStatusService networkStatusService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    networkStatusService = _OfflineNetworkStatusService();
    service = FormConfigService(
      client: SupabaseClient('https://example.supabase.co', 'anon-key'),
      networkStatusService: networkStatusService,
    );
  });

  test(
    'falls back to built-in sections when offline and cache is empty',
    () async {
      final sections = await service.fetchFormConfig();

      expect(sections, isNotEmpty);
      expect(sections.first.fields.first.fieldKey, 'farmer_name');
    },
  );

  test('ignores cached sections that cannot start a farmer survey', () async {
    SharedPreferences.setMockInitialValues({
      FormConfigService.sectionsCacheKey: jsonEncode([
        {
          'id': 'cached-yearly',
          'sort_order': 1,
          'title': 'Main Crop 3-Year Production',
          'icon_name': 'bar_chart',
          'form_fields': [
            {
              'id': 'cached-repeat-yearly',
              'field_key': 'repeat_main_crop_yearly',
              'label': 'Main crop production for last 3 years',
              'input_type': 'text',
              'sort_order': 10,
              'is_required': false,
              'validation': {},
              'repeat_group': 'main_crop_yearly',
            },
          ],
        },
      ]),
    });

    final sections = await service.fetchFormConfig();

    expect(sections.first.fields.first.fieldKey, 'farmer_name');
    expect(
      sections.expand((section) => section.fields).first.fieldKey,
      isNot('repeat_main_crop_yearly'),
    );
  });

  test('ignores cached dropdowns missing required offline choices', () async {
    SharedPreferences.setMockInitialValues({
      FormConfigService.dropdownOptionsCacheKey: jsonEncode([
        {
          'option_key': 'disease_severity',
          'value': 'Mild',
          'label': 'Mild',
          'sort_order': 10,
        },
      ]),
    });

    final options = await service.fetchDropdownOptions();

    expect(options['main_crop_v2'], contains('paddy'));
    expect(options['income_sources_v2'], contains('farming'));
  });

  test(
    'shares one offline reachability check across parallel config reads',
    () async {
      await Future.wait<dynamic>([
        service.fetchFormConfig(),
        service.fetchDropdownOptions(),
        service.fetchDropdownOptionRows(),
      ]);

      expect(networkStatusService.callCount, 1);
    },
  );
}

class _OfflineNetworkStatusService extends NetworkStatusService {
  int callCount = 0;

  @override
  Future<bool> isOnline({Duration timeout = const Duration(seconds: 4)}) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return false;
  }
}
