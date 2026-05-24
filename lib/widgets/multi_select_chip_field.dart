import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';

class MultiSelectChipField extends StatelessWidget {
  final String label;
  final List<String> options;
  final RxList<String> selected;
  final String? optionKey;

  const MultiSelectChipField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    this.optionKey,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    final formController = Get.find<FormController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Obx(() {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((option) {
                final isSelected = selected.contains(option);
                final displayText = formController.localizedOptionLabel(
                  optionKey,
                  option,
                );
                return GestureDetector(
                  onTap: () {
                    if (isSelected) {
                      selected.remove(option);
                    } else {
                      selected.add(option);
                    }
                    formController.saveDraft();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.green : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.green
                            : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          displayText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          }),
          Obx(() {
            if (selected.isEmpty) {
              final hint = lang.isMarathi
                  ? 'किमान एक पर्याय निवडा'
                  : 'Select at least one option';
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }
}
