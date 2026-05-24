import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final String? Function(String?)? validator;
  final int maxLines;
  final String? suffixText;
  final String? hintText;

  const CustomTextField({
    super.key,
    required this.label,
    required this.controller,
    this.numeric = false,
    this.validator,
    this.maxLines = 1,
    this.suffixText,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : maxLines > 1
            ? TextInputType.multiline
            : TextInputType.text,
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
            : null,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          suffixText: suffixText,
          suffixStyle: suffixText != null
              ? TextStyle(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )
              : null,
        ),
        validator: validator,
      ),
    );
  }
}
