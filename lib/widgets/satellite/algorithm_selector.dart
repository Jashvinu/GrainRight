import 'package:flutter/material.dart';
import '../../config/satellite_config.dart';
import '../../config/theme.dart';

class AlgorithmSelector extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const AlgorithmSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SatelliteConfig.advancedAlgorithms.map((alg) {
        final isSelected = selected.contains(alg);
        return FilterChip(
          label: Text(
            SatelliteConfig.algorithmLabels[alg] ?? alg,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? AppTheme.greenDark : AppTheme.textMuted,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          selected: isSelected,
          selectedColor: AppTheme.greenPale,
          checkmarkColor: AppTheme.green,
          backgroundColor: Colors.white,
          side: BorderSide(
            color: isSelected ? AppTheme.green : Colors.grey.shade300,
          ),
          onSelected: (val) {
            final updated = List<String>.from(selected);
            if (val) {
              updated.add(alg);
            } else {
              updated.remove(alg);
            }
            onChanged(updated);
          },
        );
      }).toList(),
    );
  }
}
