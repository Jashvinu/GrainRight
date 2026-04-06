import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/form_controller.dart';
import 'acre_input.dart';

class MilletLandPickerField extends StatelessWidget {
  final String label;

  const MilletLandPickerField({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<FormController>();

    return Obx(() {
      final mode = c.milletLandMode.value;
      final selectedMillets = c.multiSelectValue('millet_seed_type');
      final total = c.milletLandTotal.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode toggle
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.greenLight.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to enter millet land area?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.greenDark,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ModeChip(
                      label: 'One total area',
                      icon: Icons.straighten_rounded,
                      selected: mode == 'total',
                      onTap: () {
                        c.milletLandMode.value = 'total';
                        c.clearMilletLandAreas();
                      },
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      label: 'Per millet type',
                      icon: Icons.grid_view_rounded,
                      selected: mode == 'per_type',
                      onTap: () => c.milletLandMode.value = 'per_type',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Input area
          if (mode == 'total')
            AcreInput(
              label: label,
              controller: c.textController('land_under_millet'),
            )
          else ...[
            if (selectedMillets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.orange[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Select millet types above first',
                      style: TextStyle(
                          fontSize: 13, color: Colors.orange[700]),
                    ),
                  ],
                ),
              )
            else
              for (final millet in selectedMillets)
                AcreInput(
                  label: 'Land under $millet',
                  controller: c.milletLandController(millet),
                ),

            // Auto-summed total display
            if (total > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total land under millet',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.greenDark,
                      ),
                    ),
                    Text(
                      '${total.toStringAsFixed(2)} ac',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      );
    });
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.green : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppTheme.green : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : Colors.grey[600]),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
