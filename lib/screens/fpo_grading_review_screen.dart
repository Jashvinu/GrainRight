import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/theme.dart';
import '../config/locale_text.dart';
import '../config/ui_strings.dart';
import '../services/grain_grading_service.dart';
import '../widgets/app_back_button.dart';

class FpoGradingReviewScreen extends StatefulWidget {
  const FpoGradingReviewScreen({super.key});

  @override
  State<FpoGradingReviewScreen> createState() => _FpoGradingReviewScreenState();
}

class _FpoGradingReviewScreenState extends State<FpoGradingReviewScreen> {
  final GrainGradingService _service = GrainGradingService();
  final List<GradingReviewJob> _jobs = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final jobs = await _service.fetchReviewJobs();
      if (!mounted) return;
      setState(() {
        _jobs
          ..clear()
          ..addAll(jobs);
        _loading = false;
      });
    } on GradingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _update(
    GradingReviewJob job,
    String status,
    String label,
  ) async {
    try {
      await _service.updateReviewJob(
        analysisId: job.id,
        reviewStatus: status,
        notes: label,
      );
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('review_updated'),
        label,
        snackPosition: SnackPosition.BOTTOM,
      );
      await _load();
    } on GradingException catch (e) {
      if (!mounted) return;
      Get.snackbar(
        UiStrings.t('review_failed'),
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        title: Text(UiStrings.t('grading_review')),
        actions: [
          IconButton(
            tooltip: UiStrings.t('refresh_farm'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 52),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(UiStrings.t('try_again')),
              ),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            UiStrings.t('no_grading_jobs_need_review'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (context, index) => _ReviewJobTile(
        job: _jobs[index],
        onApprove: () => _update(
          _jobs[index],
          'approved',
          UiStrings.t('approved'),
        ),
        onRecapture: () => _update(
          _jobs[index],
          'recapture_requested',
          UiStrings.t('recapture_requested'),
        ),
        onReject: () => _update(
          _jobs[index],
          'rejected',
          UiStrings.t('rejected'),
        ),
      ),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemCount: _jobs.length,
    );
  }
}

class _ReviewJobTile extends StatelessWidget {
  final GradingReviewJob job;
  final VoidCallback onApprove;
  final VoidCallback onRecapture;
  final VoidCallback onReject;

  const _ReviewJobTile({
    required this.job,
    required this.onApprove,
    required this.onRecapture,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final moisture = job.moisturePercent == null
        ? '--'
        : '${LocaleText.number(job.moisturePercent!, fractionDigits: 1)}%';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  job.finalGrade ?? '?',
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.batchId.isEmpty ? job.id : job.batchId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      UiStrings.f('crop_variety_moisture', {
                        'crop': job.cropType,
                        'variety': job.variety,
                        'moisture': moisture,
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: job.reviewStatus),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: UiStrings.t('role_farmer'), value: job.farmerId),
              _InfoChip(label: UiStrings.t('farm_label'), value: job.farmId),
              if (job.finalScore != null)
                _InfoChip(
                  label: UiStrings.t('score'),
                  value: LocaleText.number(job.finalScore!, fractionDigits: 0),
                ),
              if (job.moistureRisk.isNotEmpty)
                _InfoChip(label: UiStrings.t('risk'), value: job.moistureRisk),
            ],
          ),
          if (job.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              job.errorMessage,
              style: const TextStyle(color: AppTheme.error, height: 1.35),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(UiStrings.t('approve')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: UiStrings.t('request_recapture'),
                onPressed: onRecapture,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: UiStrings.t('reject'),
                onPressed: onReject,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(UiStrings.option(label)),
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        UiStrings.f('label_value', {
          'label': label,
          'value': value.isEmpty ? '--' : value,
        }),
      ),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      visualDensity: VisualDensity.compact,
    );
  }
}
