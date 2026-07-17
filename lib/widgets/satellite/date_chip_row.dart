import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../../models/satellite/satellite_date_model.dart';

class DateChipRow extends StatelessWidget {
  final List<SatelliteDate> dates;
  final SatelliteDate? selected;
  final ValueChanged<SatelliteDate> onSelected;

  const DateChipRow({
    super.key,
    required this.dates,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (dates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          UiStrings.t('no_dates_available'),
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final d = dates[index];
          final isSelected = d.date == selected?.date;
          return GestureDetector(
            onTap: () => onSelected(d),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.green : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppTheme.green : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateLabel(d.date),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      d.satelliteShort,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : AppTheme.greenDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? LocaleText.digits(value)
        : LocaleText.date(date, pattern: 'dd MMM');
  }
}
