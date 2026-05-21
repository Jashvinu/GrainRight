import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';

class CustomDropdown extends StatelessWidget {
  final String label;
  final List<String> items;
  final Rxn<String> selected;
  final String? optionKey;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    this.optionKey,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    final formController = Get.find<FormController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Obx(() {
        final _ = lang.language.value;
        return DropdownButtonFormField<String>(
          initialValue: items.contains(selected.value) ? selected.value : null,
          decoration: InputDecoration(labelText: label),
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          items: items.map((e) {
            final displayText = formController.localizedOptionLabel(
              optionKey,
              e,
            );
            return DropdownMenuItem(value: e, child: Text(displayText));
          }).toList(),
          onChanged: (v) => selected.value = v,
        );
      }),
    );
  }
}
