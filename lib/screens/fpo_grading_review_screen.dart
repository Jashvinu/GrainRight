import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/theme.dart';
import '../services/grain_grading_service.dart';

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
      Get.snackbar('Review updated', label, snackPosition: SnackPosition.BOTTOM);
      await _load();
    } on GradingException catch (e) {
      if (!mounted) return;
      Get.snackbar('Review failed', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Grading Review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
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
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No grading jobs need review.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (context, index) => _ReviewJobTile(
        job: _jobs[index],
        onApprove: () => _update(_jobs[index], 'approved', 'Approved'),
        onRecapture: () => _update(
          _jobs[index],
          'recapture_requested',
          'Recapture requested',
        ),
        onReject: () => _update(_jobs[index], 'rejected', 'Rejected'),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
        : '${job.moisturePercent!.toStringAsFixed(1)}%';
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
                      '${job.cropType} ${job.variety} • Moisture $moisture',
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
              _InfoChip(label: 'Farmer', value: job.farmerId),
              _InfoChip(label: 'Farm', value: job.farmId),
              if (job.finalScore != null)
                _InfoChip(label: 'Score', value: job.finalScore!.toStringAsFixed(0)),
              if (job.moistureRisk.isNotEmpty)
                _InfoChip(label: 'Risk', value: job.moistureRisk),
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
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Request recapture',
                onPressed: onRecapture,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Reject',
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
      label: Text(label),
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
      label: Text('$label: ${value.isEmpty ? '--' : value}'),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      visualDensity: VisualDensity.compact,
    );
  }
}
