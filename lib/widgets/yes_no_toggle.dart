import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../config/translations.dart';
import '../controllers/form_controller.dart';
import '../controllers/language_controller.dart';

class YesNoToggle extends StatelessWidget {
  final String label;
  final Rxn<bool> value;

  const YesNoToggle({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Obx(() {
        final isMr = lang.isMarathi;
        final yes = isMr ? (AppTranslations.ui['Yes'] ?? 'होय') : 'Yes';
        final no = isMr ? (AppTranslations.ui['No'] ?? 'नाही') : 'No';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _chip(yes, value.value == true, () => _setValue(true)),
              const SizedBox(width: 6),
              _chip(no, value.value == false, () => _setValue(false)),
            ],
          ),
        );
      }),
    );
  }

  void _setValue(bool nextValue) {
    value.value = nextValue;
    if (Get.isRegistered<FormController>()) {
      Get.find<FormController>().saveDraft();
    }
  }

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.green : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
