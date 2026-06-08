import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../controllers/survey_controller.dart';
import '../models/farmer_survey.dart';
import '../models/survey_launch.dart';
import '../services/offline_survey_queue_service.dart';
import '../widgets/survey_list_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<bool> _confirmDelete(BuildContext context, FarmerSurvey survey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Survey'),
        content: Text(
          'Delete survey for "${survey.farmerName ?? 'Unnamed'}" from the remote database and Google Sheet? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteFromMenu(
    BuildContext context,
    SurveyController controller,
    FarmerSurvey survey,
  ) async {
    final confirmed = await _confirmDelete(context, survey);
    if (!confirmed) return;

    final deleted = await controller.deleteSurvey(survey);
    if (deleted) _removeFromList(controller, survey);
  }

  bool _canDelete(FarmerSurvey survey) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && survey.userId == currentUserId;
  }

  void _removeFromList(SurveyController controller, FarmerSurvey survey) {
    final id = survey.id;
    if (id == null) {
      controller.surveys.remove(survey);
      return;
    }
    controller.surveys.removeWhere((item) => item.id == id);
  }

  Future<void> _openSurvey(
    SurveyController controller,
    SurveyLaunchArgs args,
  ) async {
    await Get.toNamed('/form', arguments: args);
    await controller.loadPendingSubmissions();
    await controller.refreshDraftState();
  }

  Future<void> _openNewSurvey(SurveyController controller) async {
    await _openSurvey(controller, const SurveyLaunchArgs.newSurvey());
  }

  Future<void> _resumeDraftSurvey(SurveyController controller) async {
    await _openSurvey(controller, const SurveyLaunchArgs.resumeDraft());
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SurveyController>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 70,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(BrandAssets.logo, height: 60),
            ),
            const SizedBox(width: 14),
            Text(
              'by',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'wrkfarm',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.green,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Back to roles',
            onPressed: () => Get.offAllNamed('/login'),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ],
      ),
      body: Obx(() {
        final pending = controller.pendingSubmissions;
        final hasDraft = controller.hasActiveDraft.value;
        if (controller.isLoading.value &&
            controller.surveys.isEmpty &&
            pending.isEmpty &&
            !hasDraft) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        if (controller.hasError.value &&
            controller.surveys.isEmpty &&
            pending.isEmpty &&
            !hasDraft) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 56,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.errorMessage.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: controller.loadSurveys,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (controller.surveys.isEmpty && pending.isEmpty && !hasDraft) {
          return RefreshIndicator(
            color: AppTheme.green,
            onRefresh: controller.loadSurveys,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(28, 96, 28, 28),
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  size: 58,
                  color: Colors.grey[350],
                ),
                const SizedBox(height: 18),
                const Text(
                  'No surveys found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.greenDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Farmer survey records will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Get.toNamed('/offline-maps'),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Offline Maps'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _openNewSurvey(controller),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Survey'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.greenPale,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${controller.surveys.length + pending.length} survey${controller.surveys.length + pending.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: AppTheme.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Farmer Baseline Surveys',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.greenDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (controller.hasError.value) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.errorMessage.value,
                      style: const TextStyle(
                        color: Color(0xFF856404),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Survey list
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.green,
                onRefresh: controller.loadSurveys,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount:
                      controller.surveys.length +
                      pending.length +
                      (hasDraft ? 1 : 0) +
                      1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      final hasDiagnostics = controller.surveys.any(
                        (survey) => survey.farmPolygon != null,
                      );
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (hasDiagnostics)
                              OutlinedButton.icon(
                                onPressed: () => Get.toNamed('/diagnostics'),
                                icon: const Icon(Icons.satellite_alt_outlined),
                                label: const Text('View Diagnostics'),
                              ),
                            if (hasDiagnostics) const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => Get.toNamed('/offline-maps'),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('Offline Maps'),
                            ),
                            TextButton(
                              onPressed: () => hasDraft
                                  ? _resumeDraftSurvey(controller)
                                  : _openNewSurvey(controller),
                              child: Text(
                                pending.isEmpty
                                    ? hasDraft
                                          ? 'Resume saved survey'
                                          : 'Start chat survey'
                                    : 'Continue / New Survey',
                              ),
                            ),
                            if (pending.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.greenPale,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    controller.isSyncingPending.value
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTheme.green,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.cloud_upload_outlined,
                                            color: AppTheme.green,
                                            size: 18,
                                          ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        controller.isSyncingPending.value
                                            ? 'Syncing offline surveys...'
                                            : '${pending.length} survey${pending.length == 1 ? '' : 's'} pending sync',
                                        style: const TextStyle(
                                          color: AppTheme.greenDark,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Retry sync',
                                      visualDensity: VisualDensity.compact,
                                      onPressed:
                                          controller.isSyncingPending.value
                                          ? null
                                          : controller.syncPendingSurveys,
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                        color: AppTheme.green,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    i -= 1;
                    if (hasDraft) {
                      if (i == 0) {
                        return _DraftSurveyTile(
                          onTap: () => _resumeDraftSurvey(controller),
                        );
                      }
                      i -= 1;
                    }
                    if (i < pending.length) {
                      return _PendingSurveyTile(
                        submission: pending[i],
                        isSyncing: controller.isSyncingPending.value,
                      );
                    }
                    i -= pending.length;
                    final survey = controller.surveys[i];
                    final canDelete = _canDelete(survey);
                    return Dismissible(
                      key: ValueKey(survey.id ?? 'survey-$i'),
                      direction: controller.isDeleting(survey.id) || !canDelete
                          ? DismissDirection.none
                          : DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          color: Colors.red.shade400,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        final confirmed = await _confirmDelete(context, survey);
                        if (!confirmed) return false;
                        return controller.deleteSurvey(survey);
                      },
                      onDismissed: (_) async {
                        _removeFromList(controller, survey);
                      },
                      child: SurveyListTile(
                        survey: survey,
                        onTap: () =>
                            Get.toNamed('/form/classic', arguments: survey.id),
                        onDelete: canDelete
                            ? () => _deleteFromMenu(context, controller, survey)
                            : null,
                        isDeleting: controller.isDeleting(survey.id),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewSurvey(controller),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Survey'),
      ),
    );
  }
}

class _DraftSurveyTile extends StatelessWidget {
  final VoidCallback onTap;

  const _DraftSurveyTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.green,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unfinished survey',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Continue from the last saved page',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSurveyTile extends StatelessWidget {
  final PendingSurveySubmission submission;
  final bool isSyncing;

  const _PendingSurveyTile({required this.submission, required this.isSyncing});

  @override
  Widget build(BuildContext context) {
    final location = [
      submission.village,
      submission.district,
    ].where((value) => value != null && value.isNotEmpty).join(', ');
    final syncing = submission.isSyncing || isSyncing;
    final statusText = submission.isFailed
        ? 'Sync failed'
        : syncing
        ? 'Syncing'
        : 'Pending sync';
    final statusColor = submission.isFailed
        ? Colors.red.shade600
        : syncing
        ? AppTheme.green
        : const Color(0xFFB8860B);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.greenPale,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                submission.isFailed
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_upload_outlined,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submission.farmerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      location,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (submission.lastError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      submission.lastError!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.red.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  submission.surveyDate ?? 'Saved offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
