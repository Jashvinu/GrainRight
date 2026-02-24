import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomDropdown extends StatelessWidget {
  final String label;
  final List<String> items;
  final Rxn<String> selected;

  const CustomDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Obx(() => DropdownButtonFormField<String>(
            initialValue: items.contains(selected.value) ? selected.value : null,
            decoration: InputDecoration(labelText: label),
            isExpanded: true,
            borderRadius: BorderRadius.circular(12),
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => selected.value = v,
          )),
    );
  }
}
