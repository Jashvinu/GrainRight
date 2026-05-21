import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';
import '../models/chat_message.dart';
import '../models/form_config.dart';
import '../utils/polygon_geometry.dart';

sealed class _ChatStep {}

class _FieldStep extends _ChatStep {
  final FormFieldConfig field;

  _FieldStep(this.field);
}

class _RepeatStep extends _ChatStep {
  final String groupKey;
  final String title;
  final String? cropRole;

  _RepeatStep(this.groupKey, this.title, {this.cropRole});
}

class ChatSurveyController extends GetxController {
  final FormController formController;
  final LanguageController languageController;

  ChatSurveyController({
    required this.formController,
    required this.languageController,
  });

  final messages = <ChatMessage>[].obs;
  final activeField = Rxn<FormFieldConfig>();
  final isReady = false.obs;
  final isSubmitting = false.obs;

  List<_ChatStep> _steps = [];
  int _cursor = 0;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  Future<void> _start() async {
    await formController.loadConfig();
    final id = Get.arguments as String?;
    if (id != null) {
      await formController.loadSurvey(id);
    }
    _steps = _buildSteps();
    messages.add(
      BotTextMessage(
        "Welcome, I'm your survey assistant",
        quickReplies: const ['English', 'हिन्दी', 'मराठी'],
      ),
    );
    isReady.value = true;
  }

  Future<void> chooseLanguage(String language) async {
    final code = switch (language) {
      'हिन्दी' => 'hi',
      'मराठी' => 'mr',
      _ => 'en',
    };
    await languageController.setLanguage(code);
    formController.setValue('language', code);
    _steps = _buildSteps();
    _cursor = 0;
    messages.add(UserTextMessage(language));
    await _showNext();
  }

  Future<void> continueFromField(BuildContext context) async {
    final field = activeField.value;
    if (field == null) return;

    if (field.isRequired && !_hasAnswer(field)) {
      Get.snackbar('Required', 'Please answer this question');
      return;
    }
    final formatError = _formatError(field);
    if (formatError != null) {
      Get.snackbar('Invalid format', formatError);
      return;
    }

    final display = _displayValue(field, context);
    messages.add(UserFieldAnswerMessage(field, display));
    activeField.value = null;
    _cursor++;
    await formController.saveDraft();
    await _showNext();
  }

  Future<void> skipField() async {
    final field = activeField.value;
    if (field == null || field.isRequired) return;
    messages.add(UserTextMessage('Skipped'));
    activeField.value = null;
    _cursor++;
    await _showNext();
  }

  Future<void> acceptPolygon(List<List<double>> coords) async {
    final field = activeField.value;
    if (field == null) return;
    formController.setPolygon(field.fieldKey, coords);
    final ring = PolygonGeometry.fromGeoJsonRing(coords);
    messages.add(
      PolygonAnswerMessage(coords, PolygonGeometry.areaHectares(ring)),
    );
    activeField.value = null;
    _cursor++;
    await _showNext();
  }

  Future<void> saveRepeatGroup({
    required String groupKey,
    required String title,
    String? cropRole,
    required List<Map<String, dynamic>> rows,
  }) async {
    switch (groupKey) {
      case 'kharif_crops':
      case 'other_crops':
        formController.setKharifRows(rows);
      case 'main_crop_yearly':
        formController.setYearlyRows(rows);
      case 'crop_practices':
        final existing = formController.practiceRows
            .where((row) => row['crop_role'] != cropRole)
            .toList();
        formController.setPracticeRows([...existing, ...rows]);
    }
    messages.add(RepeatGroupAnswerMessage(title, rows.length));
    _cursor++;
    await _showNext();
  }

  Future<void> submit() async {
    isSubmitting.value = true;
    final submitted = await formController.submit(popOnSuccess: false);
    isSubmitting.value = false;
    if (!submitted) return;
    Get.offNamed('/home');
    Get.snackbar('Success', 'Survey submitted. Diagnostics now available.');
  }

  Future<void> _showNext() async {
    messages.add(TypingIndicatorMessage());
    await Future<void>.delayed(const Duration(milliseconds: 350));
    messages.removeWhere((message) => message is TypingIndicatorMessage);

    while (_cursor < _steps.length) {
      final step = _steps[_cursor];
      switch (step) {
        case _FieldStep(:final field):
          if (!formController.isFieldVisible(field)) {
            _cursor++;
            continue;
          }
          activeField.value = field;
          if (field.inputType == 'polygon_pencil') {
            messages.add(PolygonPromptMessage(field));
          } else {
            messages.add(BotFieldPromptMessage(field));
          }
          return;
        case _RepeatStep(:final groupKey, :final title, :final cropRole):
          if (!_shouldShowRepeatGroup(groupKey, cropRole)) {
            _cursor++;
            continue;
          }
          activeField.value = null;
          messages.add(
            RepeatGroupPromptMessage(
              groupKey,
              title: title,
              cropRole: cropRole,
            ),
          );
          return;
      }
    }

    messages.add(SummaryMessage(formController.toFlatJson()));
  }

  List<_ChatStep> _buildSteps() {
    final steps = <_ChatStep>[];
    final configuredGroups = <String>{};
    for (final section in formController.sections) {
      final repeatFields = section.fields
          .where((field) => field.repeatGroup != null)
          .toList();
      if (repeatFields.isNotEmpty) {
        for (final field in repeatFields) {
          final key = [
            field.repeatGroup,
            field.cropRole,
          ].whereType<String>().join(':');
          if (configuredGroups.add(key)) {
            steps.add(
              _RepeatStep(
                field.repeatGroup!,
                _localizedFieldLabel(field),
                cropRole: field.cropRole,
              ),
            );
          }
        }
      }

      for (final field in section.fields) {
        if (field.repeatGroup == null) {
          steps.add(_FieldStep(field));
        }
      }
    }

    void insertAfter(String fieldKey, _RepeatStep step) {
      if (steps.any(
        (s) =>
            s is _RepeatStep &&
            s.groupKey == step.groupKey &&
            s.cropRole == step.cropRole,
      )) {
        return;
      }
      final index = steps.indexWhere((s) {
        if (s is _FieldStep) return s.field.fieldKey == fieldKey;
        if (s is _RepeatStep) return s.groupKey == fieldKey;
        return false;
      });
      steps.insert(index == -1 ? steps.length : index + 1, step);
    }

    insertAfter(
      'main_crop_land_acre',
      _RepeatStep(
        'kharif_crops',
        _localizedRepeatGroupTitle('kharif_crops', null),
      ),
    );
    insertAfter(
      'kharif_crops',
      _RepeatStep(
        'crop_practices',
        _localizedRepeatGroupTitle('crop_practices', 'main'),
        cropRole: 'main',
      ),
    );
    insertAfter(
      'crop_practices',
      _RepeatStep(
        'main_crop_yearly',
        _localizedRepeatGroupTitle('main_crop_yearly', null),
      ),
    );
    insertAfter(
      'makes_food_products',
      _RepeatStep(
        'crop_practices',
        _localizedRepeatGroupTitle('crop_practices', 'other'),
        cropRole: 'other',
      ),
    );

    return steps;
  }

  bool _shouldShowRepeatGroup(String groupKey, String? cropRole) {
    if (cropRole == 'other') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'bajra' || mainCrop == 'other';
    }
    if (groupKey == 'kharif_crops' || cropRole == 'main') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'paddy' || mainCrop == 'nachani';
    }
    if (groupKey == 'other_crops') {
      final mainCrop = formController.valueFor('main_crop');
      return mainCrop == 'bajra' || mainCrop == 'other';
    }
    return true;
  }

  String _localizedFieldLabel(FormFieldConfig field) {
    return switch (languageController.language.value) {
      'hi' => field.labelHi?.isNotEmpty == true ? field.labelHi! : field.label,
      'mr' => field.labelMr?.isNotEmpty == true ? field.labelMr! : field.label,
      _ => field.label,
    };
  }

  String _localizedRepeatGroupTitle(String groupKey, String? cropRole) {
    final language = languageController.language.value;
    if (language == 'hi') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीफ फसलें',
        'other_crops' => 'ली गई अन्य फसलें',
        'main_crop_yearly' => 'मुख्य फसल उत्पादन इतिहास',
        'crop_practices' =>
          cropRole == 'other' ? 'अन्य फसल पद्धतियां' : 'मुख्य फसल पद्धतियां',
        _ => groupKey,
      };
    }
    if (language == 'mr') {
      return switch (groupKey) {
        'kharif_crops' => 'खरीप पिके',
        'other_crops' => 'घेतलेली इतर पिके',
        'main_crop_yearly' => 'मुख्य पीक उत्पादन इतिहास',
        'crop_practices' =>
          cropRole == 'other' ? 'इतर पीक पद्धती' : 'मुख्य पीक पद्धती',
        _ => groupKey,
      };
    }
    return switch (groupKey) {
      'kharif_crops' => 'Kharif crops',
      'other_crops' => 'Other crops taken',
      'main_crop_yearly' => 'Main crop production history',
      'crop_practices' =>
        cropRole == 'other' ? 'Other crop practices' : 'Main crop practices',
      _ => groupKey,
    };
  }

  bool _hasAnswer(FormFieldConfig field) {
    final value = formController.valueFor(field.fieldKey);
    return switch (field.inputType) {
      'text' ||
      'numeric' ||
      'currency' ||
      'acre' ||
      'mobile' ||
      'aadhar' => value is String && value.trim().isNotEmpty,
      'dropdown' => value != null && value.toString().isNotEmpty,
      'boolean' => value != null,
      'date' => value is DateTime,
      'polygon' || 'polygon_pencil' => value is List && value.isNotEmpty,
      'multiselect' => value is List && value.isNotEmpty,
      'auto_calc' => true,
      _ => true,
    };
  }

  String? _formatError(FormFieldConfig field) {
    final value = formController.valueFor(field.fieldKey)?.toString() ?? '';
    if (value.trim().isEmpty) return null;
    if (field.inputType == 'mobile' &&
        !RegExp(r'^[0-9]{10}$').hasMatch(value.trim())) {
      return 'Enter a 10 digit mobile number';
    }
    if (field.inputType == 'aadhar' &&
        !RegExp(r'^[0-9]{12}$').hasMatch(value.replaceAll(' ', '').trim())) {
      return 'Enter a 12 digit Aadhaar number';
    }
    return null;
  }

  String _displayValue(FormFieldConfig field, BuildContext context) {
    final value = formController.valueFor(field.fieldKey);
    if (value == null) return 'Skipped';
    if (value is DateTime) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is List) {
      if (field.inputType == 'polygon' || field.inputType == 'polygon_pencil') {
        final coords = value.map((point) {
          final p = point as List;
          return [(p[0] as num).toDouble(), (p[1] as num).toDouble()];
        }).toList();
        final ring = PolygonGeometry.fromGeoJsonRing(coords);
        return '${PolygonGeometry.areaHectares(ring).toStringAsFixed(2)} ha';
      }
      return value
          .map(
            (item) => formController.localizedOptionLabel(
              field.dropdownOptionsKey,
              item.toString(),
            ),
          )
          .join(', ');
    }
    if (field.inputType == 'dropdown') {
      return formController.localizedOptionLabel(
        field.dropdownOptionsKey,
        value.toString(),
      );
    }
    return value.toString();
  }
}
