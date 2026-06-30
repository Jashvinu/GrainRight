import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../models/form_config.dart';
import '../dynamic_field.dart';

class BotFieldPrompt extends StatelessWidget {
  final FormFieldConfig field;
  final VoidCallback onContinue;
  final VoidCallback? onSkip;

  const BotFieldPrompt({
    super.key,
    required this.field,
    required this.onContinue,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final label = field.localizedLabel(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.greenPale,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.isRequired ? '$label *' : label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DynamicField(config: field),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSkip != null)
                    TextButton(onPressed: onSkip, child: const Text('Skip')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: onContinue,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
