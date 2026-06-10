import '../models/form_config.dart';

class OfflineFormSeed {
  static List<FormSectionConfig> sections() {
    return [
      _section('family', 10, 'Family Information', 'person', [
        _field('farmer_name', 'Farmer Name', 'text', 10, required: true),
        _field('village', 'Village', 'text', 20, required: true),
        _field('gram_panchayat', 'Gram Panchayat', 'text', 30, required: true),
        _field('taluka', 'Taluka', 'text', 40, required: true),
        _field('district', 'District', 'text', 50, required: true),
        _field(
          'mobile_number',
          'Mobile No.',
          'mobile',
          60,
          validation: {
            'regex': r'^[0-9]{10}$',
            'regex_message': 'Enter a 10 digit mobile number',
          },
        ),
        _field(
          'aadhaar_number',
          'Aadhaar No.',
          'aadhar',
          70,
          validation: {
            'regex': r'^[0-9]{12}$',
            'regex_message': 'Enter a 12 digit Aadhaar number',
          },
          hintText: 'XXXX XXXX XXXX',
        ),
        _field(
          'date_of_birth',
          'Date of Birth',
          'date',
          80,
          validation: {'date_min': '1930-01-01', 'date_max': 'today'},
        ),
        _field(
          'education',
          'Education',
          'dropdown',
          90,
          dropdownOptionsKey: 'education_v2',
        ),
        _field(
          'gender',
          'Gender',
          'dropdown',
          100,
          dropdownOptionsKey: 'gender_v2',
        ),
        _field(
          'category',
          'Category',
          'dropdown',
          110,
          dropdownOptionsKey: 'category_v2',
        ),
      ]),
      _section('land', 20, 'Land / Farming', 'landscape', [
        _field(
          'income_sources',
          'Income sources',
          'multiselect',
          10,
          required: true,
          dropdownOptionsKey: 'income_sources_v2',
        ),
        _field(
          'farming_type',
          'Farming type',
          'multiselect',
          20,
          required: true,
          dropdownOptionsKey: 'farming_type_v2',
        ),
        _field(
          'owns_farmland',
          'Owns farmland?',
          'boolean',
          30,
          required: true,
        ),
        _field(
          'total_land_area_acre',
          'Total land area',
          'acre',
          40,
          required: true,
          suffixText: 'acre',
        ),
        _field(
          'irrigated_land_acre',
          'Irrigated land',
          'acre',
          50,
          suffixText: 'acre',
        ),
        _field('dry_land_acre', 'Dry land', 'acre', 60, suffixText: 'acre'),
        _field(
          'fallow_land_acre',
          'Fallow land',
          'acre',
          70,
          suffixText: 'acre',
        ),
        _field(
          'leased_land_acre',
          'Leased land',
          'acre',
          80,
          suffixText: 'acre',
        ),
        _field(
          'rain_based_area_acre',
          'Rain-based area',
          'acre',
          90,
          suffixText: 'acre',
        ),
      ]),
      _section('forest', 30, 'Forest Patta', 'forest', [
        _field(
          'has_forest_patta',
          'Has forest patta?',
          'boolean',
          10,
          required: true,
        ),
        _field(
          'forest_patta_acre',
          'Forest patta area',
          'acre',
          20,
          visibilityRule: {
            'depends_on': 'has_forest_patta',
            'operator': 'equals',
            'value': true,
          },
          suffixText: 'acre',
        ),
        _field(
          'applied_for_forest_patta',
          'Applied for forest patta?',
          'boolean',
          30,
          visibilityRule: {
            'depends_on': 'has_forest_patta',
            'operator': 'equals',
            'value': false,
          },
        ),
      ]),
      _section('boundary', 40, 'Farm Boundary', 'map', [
        _field(
          'farm_polygon',
          'Farm Boundary Polygon (optional)',
          'polygon_pencil',
          10,
          hintText: 'Draw if time permits; submission is allowed without it.',
        ),
      ]),
      _section('main_crop', 50, 'Main Crop', 'grass', [
        _field(
          'main_crop',
          'Main crop',
          'dropdown',
          10,
          required: true,
          dropdownOptionsKey: 'main_crop_v2',
        ),
        _field(
          'main_crop_other',
          'Other crop name',
          'text',
          20,
          visibilityRule: {
            'depends_on': 'main_crop',
            'operator': 'equals',
            'value': 'other',
          },
        ),
        _field(
          'other_crop_details',
          'Other crop details',
          'text',
          30,
          visibilityRule: {
            'depends_on': 'main_crop',
            'operator': 'equals',
            'value': 'other',
          },
          hintText: 'Variety, local name, or field notes',
        ),
        _field(
          'main_crop_land_acre',
          'Land under main crop',
          'acre',
          40,
          suffixText: 'acre',
        ),
        _field(
          'other_crop_land_acre',
          'Land under other crop',
          'acre',
          50,
          visibilityRule: {
            'depends_on': 'main_crop',
            'operator': 'contains_any',
            'value': ['bajra', 'other'],
          },
          suffixText: 'acre',
        ),
      ]),
      _section('kharif', 60, 'Kharif Crops', 'eco', [
        _field(
          'repeat_kharif_crops',
          'Crops taken in Kharif season',
          'text',
          10,
          hintText:
              'Add each crop with area, variety, production, and estimated cost.',
          repeatGroup: 'kharif_crops',
        ),
      ]),
      _section('main_practices', 70, 'Main Crop Agronomy', 'agriculture', [
        _field(
          'repeat_main_crop_practices',
          'Rice/Ragi crop agronomy practices',
          'text',
          10,
          visibilityRule: {
            'depends_on': 'main_crop',
            'operator': 'contains_any',
            'value': ['paddy', 'nachani'],
          },
          hintText:
              'Seed, nursery, land preparation, transplanting, pest, fertilizer, monitoring, and harvest details.',
          cropRole: 'main',
          repeatGroup: 'crop_practices',
        ),
      ]),
      _section('other_practices', 75, 'Other Crop Agronomy', 'agriculture', [
        _field(
          'repeat_other_crop_practices',
          'Bajra/Other crop agronomy practices',
          'text',
          10,
          visibilityRule: {
            'depends_on': 'main_crop',
            'operator': 'contains_any',
            'value': ['bajra', 'other'],
          },
          hintText:
              'Fill seed, land preparation, pest, fertilizer, monitoring, harvest, and selling details.',
          cropRole: 'other',
          repeatGroup: 'crop_practices',
        ),
      ]),
      _section(
        'main_crop_yearly',
        80,
        'Main Crop 3-Year Production',
        'bar_chart',
        [
          _field(
            'repeat_main_crop_yearly',
            'Main crop production for last 3 years',
            'text',
            10,
            hintText: 'Production history for 2023, 2024, and 2025.',
            repeatGroup: 'main_crop_yearly',
          ),
        ],
      ),
      _section('income_food', 90, 'Income & Food Products', 'currency_rupee', [
        _field(
          'annual_agri_income',
          'Annual agricultural income',
          'currency',
          10,
        ),
        _field('non_agri_income', 'Non-agricultural income', 'currency', 20),
        _field(
          'total_cultivation_cost',
          'Total cost of cultivation',
          'currency',
          27,
        ),
        _field(
          'total_annual_income',
          'Total annual income',
          'auto_calc',
          30,
          autoCalcFormula: {
            'operation': 'sum_then_subtract_last',
            'operands': [
              'annual_agri_income',
              'non_agri_income',
              'total_cultivation_cost',
            ],
          },
        ),
        _field('makes_food_products', 'Makes food products?', 'boolean', 40),
        _field(
          'food_products_list',
          'Food products list',
          'text',
          50,
          visibilityRule: {
            'depends_on': 'makes_food_products',
            'operator': 'equals',
            'value': true,
          },
        ),
        _field(
          'food_product_training_received',
          'Food product training received?',
          'boolean',
          60,
          visibilityRule: {
            'depends_on': 'makes_food_products',
            'operator': 'equals',
            'value': true,
          },
        ),
        _field(
          'food_product_training_source',
          'Food product training source',
          'text',
          70,
          visibilityRule: {
            'depends_on': 'food_product_training_received',
            'operator': 'equals',
            'value': true,
          },
        ),
      ]),
      _section('disease', 100, 'Disease', 'eco_outlined', [
        _field('disease_present', 'Any Disease Observed?', 'boolean', 1),
        _field(
          'disease_name',
          'Disease Name',
          'dropdown',
          2,
          validation: {'min_length': 2},
          visibilityRule: {
            'depends_on': 'disease_present',
            'operator': 'equals',
            'value': true,
          },
          dropdownOptionsKey: 'disease_name_common',
          hintText: 'Select disease name',
        ),
        _field(
          'affected_crop',
          'Affected Crop',
          'dropdown',
          3,
          visibilityRule: {
            'depends_on': 'disease_present',
            'operator': 'equals',
            'value': true,
          },
          dropdownOptionsKey: 'affected_crop_fallback',
          hintText: 'Select affected crop',
        ),
        _field(
          'disease_severity',
          'Disease Severity',
          'dropdown',
          4,
          visibilityRule: {
            'depends_on': 'disease_present',
            'operator': 'equals',
            'value': true,
          },
          dropdownOptionsKey: 'disease_severity',
        ),
        _field(
          'symptoms_observed',
          'Symptoms Observed',
          'textarea',
          5,
          visibilityRule: {
            'depends_on': 'disease_present',
            'operator': 'equals',
            'value': true,
          },
          hintText: 'Write key symptoms',
        ),
        _field(
          'treatment_taken',
          'Treatment Taken',
          'textarea',
          6,
          visibilityRule: {
            'depends_on': 'disease_present',
            'operator': 'equals',
            'value': true,
          },
          hintText: 'Fungicide, biocontrol, etc.',
        ),
      ]),
    ];
  }

  static Map<String, List<String>> dropdownOptions() {
    final map = <String, List<String>>{};
    for (final row in dropdownRows()) {
      final key = row['option_key'] as String;
      final value = row['value'] as String;
      map.putIfAbsent(key, () => []).add(value);
    }
    return map;
  }

  static List<Map<String, dynamic>> dropdownRows() {
    return [
      _option('education_v2', 'illiterate', 'Illiterate', 10),
      _option('education_v2', 'primary', 'Primary', 20),
      _option('education_v2', 'secondary', 'Secondary', 30),
      _option('education_v2', 'graduate', 'Graduate', 40),
      _option('gender_v2', 'male', 'Male', 10),
      _option('gender_v2', 'female', 'Female', 20),
      _option('gender_v2', 'other', 'Other', 30),
      _option('category_v2', 'general', 'General', 10),
      _option('category_v2', 'sc', 'SC', 20),
      _option('category_v2', 'st', 'ST', 30),
      _option('category_v2', 'obc', 'OBC', 40),
      _option('income_sources_v2', 'farming', 'Farming', 10),
      _option('income_sources_v2', 'private_job', 'Private Job', 20),
      _option('income_sources_v2', 'govt_job', 'Government Job', 30),
      _option('income_sources_v2', 'business', 'Business', 40),
      _option('income_sources_v2', 'other', 'Other', 50),
      _option('farming_type_v2', 'rainfed', 'Rainfed', 10),
      _option('farming_type_v2', 'irrigated', 'Irrigated', 20),
      _option('farming_type_v2', 'other', 'Other', 30),
      _option('main_crop_v2', 'paddy', 'Paddy (Rice)', 10),
      _option('main_crop_v2', 'nachani', 'Nachani (Ragi)', 20),
      _option('main_crop_v2', 'bajra', 'Bajra', 30),
      _option('main_crop_v2', 'other', 'Other', 40),
      _option('disease_severity', 'Mild', 'Mild', 10),
      _option('disease_severity', 'Moderate', 'Moderate', 20),
      _option('disease_severity', 'Severe', 'Severe', 30),
      _option('disease_name_common', 'Blast', 'Blast', 10),
      _option('disease_name_common', 'Brown spot', 'Brown spot', 20),
      _option('disease_name_common', 'Rust', 'Rust', 30),
      _option('disease_name_common', 'Smut', 'Smut', 40),
      _option('disease_name_common', 'Other', 'Other', 50),
      _option('affected_crop_fallback', 'bajra', 'Bajra', 10),
      _option('affected_crop_fallback', 'nachani', 'Nachani (Ragi)', 20),
      _option('affected_crop_fallback', 'paddy', 'Paddy (Rice)', 30),
      _option('affected_crop_fallback', 'Other', 'Other', 40),
    ];
  }

  static FormSectionConfig _section(
    String id,
    int sortOrder,
    String title,
    String iconName,
    List<FormFieldConfig> fields,
  ) {
    return FormSectionConfig(
      id: 'offline_$id',
      sortOrder: sortOrder,
      title: title,
      iconName: iconName,
      fields: fields,
    );
  }

  static FormFieldConfig _field(
    String key,
    String label,
    String inputType,
    int sortOrder, {
    bool required = false,
    Map<String, dynamic> validation = const {},
    Map<String, dynamic>? visibilityRule,
    Map<String, dynamic>? autoCalcFormula,
    String? dropdownOptionsKey,
    String? hintText,
    String? suffixText,
    String? cropRole,
    String? repeatGroup,
  }) {
    return FormFieldConfig(
      id: 'offline_$key',
      fieldKey: key,
      label: label,
      inputType: inputType,
      sortOrder: sortOrder,
      isRequired: required,
      validation: validation,
      visibilityRule: visibilityRule,
      autoCalcFormula: autoCalcFormula,
      dropdownOptionsKey: dropdownOptionsKey,
      hintText: hintText,
      suffixText: suffixText,
      cropRole: cropRole,
      repeatGroup: repeatGroup,
    );
  }

  static Map<String, dynamic> _option(
    String optionKey,
    String value,
    String label,
    int sortOrder,
  ) {
    return {
      'option_key': optionKey,
      'value': value,
      'label': label,
      'label_hi': '',
      'label_mr': '',
      'sort_order': sortOrder,
    };
  }
}
