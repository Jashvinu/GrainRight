import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';

class YesNoToggle extends StatelessWidget {
  final String label;
  final Rxn<bool> value;

  const YesNoToggle({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Obx(() => Container(
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
                    style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
                  ),
                ),
                const SizedBox(width: 12),
                _chip('Yes', value.value == true, () => value.value = true),
                const SizedBox(width: 6),
                _chip('No', value.value == false, () => value.value = false),
              ],
            ),
          )),
    );
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
