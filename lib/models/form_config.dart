class FormSectionConfig {
  final String id;
  final int sortOrder;
  final String title;
  final String iconName;
  final List<FormFieldConfig> fields;

  FormSectionConfig({
    required this.id,
    required this.sortOrder,
    required this.title,
    required this.iconName,
    required this.fields,
  });

  factory FormSectionConfig.fromJson(Map<String, dynamic> json) {
    final rawFields = json['form_fields'] as List? ?? [];
    final fields = rawFields
        .map((f) => FormFieldConfig.fromJson(f as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return FormSectionConfig(
      id: json['id'] as String,
      sortOrder: json['sort_order'] as int,
      title: json['title'] as String,
      iconName: json['icon_name'] as String,
      fields: fields,
    );
  }
}

class FormFieldConfig {
  final String id;
  final String fieldKey;
  final String label;
  final String inputType;
  final int sortOrder;
  final bool isRequired;
  final Map<String, dynamic> validation;
  final Map<String, dynamic>? visibilityRule;
  final Map<String, dynamic>? autoCalcFormula;
  final String? dropdownOptionsKey;
  final String? hintText;
  final String? suffixText;

  FormFieldConfig({
    required this.id,
    required this.fieldKey,
    required this.label,
    required this.inputType,
    required this.sortOrder,
    required this.isRequired,
    required this.validation,
    this.visibilityRule,
    this.autoCalcFormula,
    this.dropdownOptionsKey,
    this.hintText,
    this.suffixText,
  });

  factory FormFieldConfig.fromJson(Map<String, dynamic> json) {
    return FormFieldConfig(
      id: json['id'] as String,
      fieldKey: json['field_key'] as String,
      label: json['label'] as String,
      inputType: json['input_type'] as String,
      sortOrder: json['sort_order'] as int,
      isRequired: json['is_required'] as bool? ?? false,
      validation: (json['validation'] as Map<String, dynamic>?) ?? {},
      visibilityRule: json['visibility_rule'] as Map<String, dynamic>?,
      autoCalcFormula: json['auto_calc_formula'] as Map<String, dynamic>?,
      dropdownOptionsKey: json['dropdown_options_key'] as String?,
      hintText: json['hint_text'] as String?,
      suffixText: json['suffix_text'] as String?,
    );
  }
}
