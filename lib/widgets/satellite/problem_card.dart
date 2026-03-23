import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/satellite_config.dart';
import '../../models/satellite/diagnostics_model.dart';

class ProblemCard extends StatelessWidget {
  final Problem problem;

  const ProblemCard({super.key, required this.problem});

  @override
  Widget build(BuildContext context) {
    final isThreshold = problem.type == 'threshold';
    final bgColor =
        isThreshold ? const Color(0xFFFFF3CD) : const Color(0xFFFEE2E2);
    final borderColor =
        isThreshold ? const Color(0xFFFFD700) : Colors.red.shade200;
    final icon = isThreshold ? Icons.warning_amber_outlined : Icons.trending_down;
    final iconColor = isThreshold ? Colors.orange.shade700 : Colors.red.shade600;

    final indexLabel = SatelliteConfig.indexLabels[problem.index] ??
        problem.index.toUpperCase();

    String description;
    if (isThreshold && problem.avgValue != null && problem.threshold != null) {
      description =
          'Value ${problem.avgValue!.toStringAsFixed(1)} is below threshold of ${problem.threshold!.toStringAsFixed(1)}';
    } else if (problem.avgDecline != null) {
      description =
          'Declining trend: ${problem.avgDecline!.toStringAsFixed(2)}/day';
    } else {
      description = problem.type.replaceAll('_', ' ');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(indexLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textDark)),
                const SizedBox(height: 3),
                Text(description,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
