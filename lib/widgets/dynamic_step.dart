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
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RepeatGroupPrompt(
            groupKey: groupKey,
            title: field.localizedLabel(context),
            cropRole: field.cropRole,
            onDone: (rows) => _saveRows(c, rows),
          ),
          const SizedBox(height: 8),
          Obx(() {
            final count = switch (groupKey) {
              'kharif_crops' => c.kharifRows.length,
              'other_crops' => c.kharifRows.length,
              'main_crop_yearly' => c.yearlyRows.length,
              'crop_practices' =>
                c.practiceRows
                    .where((row) => row['crop_role'] == field.cropRole)
                    .length,
              _ => 0,
            };
            if (count == 0) return const SizedBox.shrink();
            return Text(
              '$count row${count == 1 ? '' : 's'} saved',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            );
          }),
        ],
      ),
    );
  }

  void _saveRows(FormController c, List<Map<String, dynamic>> rows) {
    switch (groupKey) {
      case 'kharif_crops':
      case 'other_crops':
        c.setKharifRows(rows);
      case 'main_crop_yearly':
        c.setYearlyRows(rows);
      case 'crop_practices':
        final existing = c.practiceRows
            .where((row) => row['crop_role'] != field.cropRole)
            .toList();
        c.setPracticeRows([...existing, ...rows]);
    }
    Get.snackbar('Saved', '${field.label} saved');
  }
}
