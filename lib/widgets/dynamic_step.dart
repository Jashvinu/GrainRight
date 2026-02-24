import 'package:flutter/material.dart';
import '../models/form_config.dart';
import 'dynamic_field.dart';

class DynamicStep extends StatelessWidget {
  final FormSectionConfig section;

  const DynamicStep({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: section.fields
          .map((field) => DynamicField(config: field))
          .toList(),
    );
  }
}
