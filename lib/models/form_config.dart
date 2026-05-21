import 'package:flutter/widgets.dart';

class FormSectionConfig {
  final String id;
  final int sortOrder;
  final String title;
  final String? titleHi;
  final String? titleMr;
  final String iconName;
  final List<FormFieldConfig> fields;

  FormSectionConfig({
    required this.id,
    required this.sortOrder,
    required this.title,
    this.titleHi,
    this.titleMr,
    required this.iconName,
    required this.fields,
  });

  factory FormSectionConfig.fromJson(Map<String, dynamic> json) {
    final rawFields = json['form_fields'] as List? ?? [];
    final fields =
        rawFields
            .map((f) => FormFieldConfig.fromJson(f as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return FormSectionConfig(
      id: json['id'] as String,
      sortOrder: json['sort_order'] as int,
      title: json['title'] as String,
      titleHi: json['title_hi'] as String?,
      titleMr: json['title_mr'] as String?,
      iconName: json['icon_name'] as String,
      fields: fields,
    );
  }

  String localizedTitle(BuildContext context) {
    return switch (Localizations.localeOf(context).languageCode) {
      'hi' => titleHi?.isNotEmpty == true ? titleHi! : title,
      'mr' => titleMr?.isNotEmpty == true ? titleMr! : title,
      _ => title,
    };
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
  final String? labelHi;
  final String? labelMr;
  final String? hintTextHi;
  final String? hintTextMr;
  final String? suffixText;
  final String? cropRole;
  final String? repeatGroup;

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
    this.labelHi,
    this.labelMr,
    this.hintTextHi,
    this.hintTextMr,
    this.suffixText,
    this.cropRole,
    this.repeatGroup,
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
      labelHi: json['label_hi'] as String?,
      labelMr: json['label_mr'] as String?,
      hintTextHi: json['hint_text_hi'] as String?,
      hintTextMr: json['hint_text_mr'] as String?,
      suffixText: json['suffix_text'] as String?,
      cropRole: json['crop_role'] as String?,
      repeatGroup: json['repeat_group'] as String?,
    );
  }

  String localizedLabel(BuildContext context) {
    return switch (Localizations.localeOf(context).languageCode) {
      'hi' => labelHi?.isNotEmpty == true ? labelHi! : label,
      'mr' => labelMr?.isNotEmpty == true ? labelMr! : label,
      _ => label,
    };
  }

  String? localizedHint(BuildContext context) {
    return switch (Localizations.localeOf(context).languageCode) {
      'hi' => hintTextHi?.isNotEmpty == true ? hintTextHi : hintText,
      'mr' => hintTextMr?.isNotEmpty == true ? hintTextMr : hintText,
      _ => hintText,
    };
  }
}
