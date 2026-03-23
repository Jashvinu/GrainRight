import 'package:flutter/material.dart';
import '../../config/satellite_config.dart';
import '../../config/theme.dart';

class IndexSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const IndexSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Index',
        prefixIcon: Icon(Icons.layers_outlined),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      items: SatelliteConfig.allIndices.map((idx) {
        return DropdownMenuItem(
          value: idx,
          child: Text(
            SatelliteConfig.indexLabels[idx] ?? idx.toUpperCase(),
            style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
          ),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
