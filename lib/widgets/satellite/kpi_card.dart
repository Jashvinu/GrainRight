import 'package:flutter/material.dart';
import '../../config/theme.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color? iconColor;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppTheme.green),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w400),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
