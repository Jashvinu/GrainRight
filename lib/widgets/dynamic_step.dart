import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../models/form_config.dart';
import 'chat/repeat_group_prompt.dart';
import 'dynamic_field.dart';

class DynamicStep extends StatelessWidget {
  final FormSectionConfig section;

  const DynamicStep({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final renderedGroups = <String>{};

    for (final field in section.fields) {
      final repeatGroup = field.repeatGroup;
      if (repeatGroup == null) {
        widgets.add(DynamicField(config: field));
        continue;
      }

      final groupKey = '$repeatGroup:${field.cropRole ?? ''}';
      if (!renderedGroups.add(groupKey)) continue;

      widgets.add(
        _ClassicRepeatGroupField(field: field, groupKey: repeatGroup),
      );
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }
}

class _ClassicRepeatGroupField extends StatelessWidget {
  final FormFieldConfig field;
  final String groupKey;

  const _ClassicRepeatGroupField({required this.field, required this.groupKey});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<FormController>();
    if (groupKey != 'crop_practices') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepeatGroupPrompt(
              key: ValueKey('classic-repeat-$groupKey-${field.cropRole ?? ''}'),
              groupKey: groupKey,
              title: field.localizedLabel(context),
              cropRole: field.cropRole,
              formController: c,
              initialRows: _initialRows(c, field.cropRole),
              onChanged: (rows) => _saveRows(c, rows, cropRole: field.cropRole),
              onDone: (rows) => _saveRows(
                c,
                rows,
                cropRole: field.cropRole,
                showSnackbar: true,
              ),
            ),
            const SizedBox(height: 8),
            Obx(() => _savedCountText(_savedCount(c, field.cropRole))),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Obx(() {
        final effectiveCropRole = _effectiveCropRole(c);
        final count = _savedCount(c, effectiveCropRole);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepeatGroupPrompt(
              key: ValueKey(
                'classic-repeat-$groupKey-${field.cropRole ?? ''}-$effectiveCropRole',
              ),
              groupKey: groupKey,
              title: _promptTitle(context, effectiveCropRole),
              cropRole: effectiveCropRole,
              formController: c,
              initialRows: _initialRows(c, effectiveCropRole),
              onChanged: (rows) =>
                  _saveRows(c, rows, cropRole: effectiveCropRole),
              onDone: (rows) => _saveRows(
                c,
                rows,
                cropRole: effectiveCropRole,
                showSnackbar: true,
              ),
            ),
            const SizedBox(height: 8),
            _savedCountText(count),
          ],
        );
      }),
    );
  }

  int _savedCount(FormController c, String? effectiveCropRole) {
    return switch (groupKey) {
      'kharif_crops' => c.kharifRows.length,
      'other_crops' => c.kharifRows.length,
      'main_crop_yearly' => c.yearlyRows.length,
      'crop_practices' =>
        c.practiceRows
            .where((row) => row['crop_role'] == effectiveCropRole)
            .length,
      _ => 0,
    };
  }

  Widget _savedCountText(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Text(
      '$count row${count == 1 ? '' : 's'} saved',
      style: TextStyle(
        color: Colors.grey.shade700,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String? _effectiveCropRole(FormController c) {
    if (groupKey != 'crop_practices') return field.cropRole;
    final primaryRole = _primaryPracticeRole(c);
    return field.cropRole == 'other' ? _oppositeRole(primaryRole) : primaryRole;
  }

  String _promptTitle(BuildContext context, String? effectiveCropRole) {
    if (groupKey != 'crop_practices') return field.localizedLabel(context);
    final slotTitle = field.cropRole == 'other'
        ? 'Other Crop Agronomy'
        : 'Main Crop Agronomy';
    return '$slotTitle - ${_cropPracticeGroupTitle(effectiveCropRole)}';
  }

  List<Map<String, dynamic>> _initialRows(
    FormController c,
    String? effectiveCropRole,
  ) {
    return switch (groupKey) {
      'kharif_crops' || 'other_crops' => c.kharifRows.toList(),
      'main_crop_yearly' => c.yearlyRows.toList(),
      'crop_practices' =>
        c.practiceRows
            .where((row) => row['crop_role'] == effectiveCropRole)
            .toList(),
      _ => const [],
    };
  }

  void _saveRows(
    FormController c,
    List<Map<String, dynamic>> rows, {
    String? cropRole,
    bool showSnackbar = false,
  }) {
    switch (groupKey) {
      case 'kharif_crops':
      case 'other_crops':
        c.setKharifRows(rows);
      case 'main_crop_yearly':
        c.setYearlyRows(rows);
      case 'crop_practices':
        final role =
            cropRole ??
            field.cropRole ??
            (rows.isNotEmpty ? rows.first['crop_role']?.toString() : null);
        final existing = c.practiceRows
            .where((row) => row['crop_role'] != role)
            .toList();
        final normalizedRows = role == null
            ? rows
            : rows.map((row) => {...row, 'crop_role': role}).toList();
        c.setPracticeRows([...existing, ...normalizedRows]);
    }
    if (showSnackbar) {
      Get.snackbar('Saved', '${field.label} saved');
    }
  }

  static String _primaryPracticeRole(FormController c) {
    for (final row in c.kharifRows) {
      final role = _practiceRoleForCrop(row['crop_name']);
      if (role != null) return role;
    }
    return _practiceRoleForCrop(c.valueFor('main_crop')) ?? 'main';
  }

  static String? _practiceRoleForCrop(dynamic value) {
    final crop = value?.toString();
    if (crop == 'bajra' || crop == 'other') return 'other';
    if (crop == 'paddy' || crop == 'nachani') return 'main';
    return null;
  }

  static String _oppositeRole(String role) =>
      role == 'other' ? 'main' : 'other';

  static String _cropPracticeGroupTitle(String? cropRole) {
    return cropRole == 'other'
        ? 'Bajra/Other crop practices'
        : 'Rice/Ragi crop practices';
  }
}
