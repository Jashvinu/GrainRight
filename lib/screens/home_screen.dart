import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../controllers/survey_controller.dart';
import '../models/farmer_survey.dart';
import '../widgets/brand_text.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SurveyController>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/logo.jpeg', height: 60),
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
            const BrandText(fontSize: 16),
          ],
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        if (controller.hasError.value) {
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
        if (controller.surveys.isEmpty) {
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
                  child: ElevatedButton.icon(
                    onPressed: () => Get.toNamed('/form'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New Survey'),
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
                          '${controller.surveys.length} survey${controller.surveys.length == 1 ? '' : 's'}',
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
                  itemCount: controller.surveys.length + 1,
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
                            TextButton(
                              onPressed: () => Get.toNamed('/form/classic'),
                              child: const Text('Use classic form'),
                            ),
                          ],
                        ),
                      );
                    }
                    i -= 1;
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
        onPressed: () => Get.toNamed('/form'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Survey'),
      ),
    );
  }
}
