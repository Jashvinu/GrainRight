import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../models/farmer_survey.dart';

class SurveyListTile extends StatelessWidget {
  final FarmerSurvey survey;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool isDeleting;

  const SurveyListTile({
    super.key,
    required this.survey,
    required this.onTap,
    this.onDelete,
    this.isDeleting = false,
  });

  @override
  Widget build(BuildContext context) {
    final date = survey.surveyDate != null
        ? LocaleText.date(DateTime.parse(survey.surveyDate!))
        : UiStrings.t('no_date');

    final initials = (survey.farmerName ?? 'U')
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: AppTheme.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      survey.farmerName ?? UiStrings.t('unnamed_farmer'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (survey.villageGp != null &&
                            survey.villageGp!.isNotEmpty) ...[
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              [survey.villageGp, survey.district]
                                  .where((s) => s != null && s.isNotEmpty)
                                  .join(', '),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Date + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 32,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.grey[400],
                        ),
                        if (onDelete != null)
                          isDeleting
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: PopupMenuButton<_SurveyTileAction>(
                                    tooltip: UiStrings.t('survey_actions'),
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      size: 20,
                                      color: Colors.grey[500],
                                    ),
                                    onSelected: (action) {
                                      switch (action) {
                                        case _SurveyTileAction.delete:
                                          onDelete?.call();
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: _SurveyTileAction.delete,
                                        child: Row(
                                          children: [
                                            const Icon(Icons.delete_outline),
                                            const SizedBox(width: 10),
                                            Text(UiStrings.t('delete')),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                      ],
                    ),
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

enum _SurveyTileAction { delete }
