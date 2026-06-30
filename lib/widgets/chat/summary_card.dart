import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../utils/pii_masking.dart';

class SummaryCard extends StatelessWidget {
  final Map<String, dynamic> snapshot;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const SummaryCard({
    super.key,
    required this.snapshot,
    required this.isSubmitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.entries
        .where((entry) => entry.value != null && !entry.key.startsWith('__'))
        .take(8)
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.greenLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Review and submit',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${entry.key}: ${_displayValue(entry)}'),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSubmitting ? null : onSubmit,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayValue(MapEntry<String, dynamic> entry) {
    if (entry.key == 'aadhaar_number' || entry.key == 'aadhar_no') {
      return maskAadhaar(entry.value?.toString());
    }
    return entry.value.toString();
  }
}
