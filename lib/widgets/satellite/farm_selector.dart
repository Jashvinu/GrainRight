import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/satellite/farm_model.dart';

class FarmSelector extends StatelessWidget {
  final List<Farm> farms;
  final Farm? selected;
  final ValueChanged<Farm> onChanged;
  final VoidCallback onAddFarm;

  const FarmSelector({
    super.key,
    required this.farms,
    required this.selected,
    required this.onChanged,
    required this.onAddFarm,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected?.id,
      decoration: const InputDecoration(
        labelText: 'Farm',
        prefixIcon: Icon(Icons.grass_outlined),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      items: [
        ...farms.map((f) => DropdownMenuItem(
              value: f.id,
              child: Text(
                f.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: AppTheme.textDark),
              ),
            )),
        const DropdownMenuItem(
          value: '__add__',
          child: Row(
            children: [
              Icon(Icons.add, size: 18, color: AppTheme.green),
              SizedBox(width: 6),
              Text('Add Farm',
                  style: TextStyle(color: AppTheme.green, fontSize: 14)),
            ],
          ),
        ),
      ],
      onChanged: (v) {
        if (v == '__add__') {
          onAddFarm();
          return;
        }
        final farm = farms.firstWhereOrNull((f) => f.id == v);
        if (farm != null) onChanged(farm);
      },
    );
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
