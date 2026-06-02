import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/farmer_survey.dart';
import '../services/network_status_service.dart';
import '../services/offline_survey_queue_service.dart';
import '../services/secure_app_storage.dart';
import '../services/survey_service.dart';
import '../services/sheets_sync_service.dart';

class SurveyController extends GetxController {
  final _service = SurveyService();
  final _sheetsService = SheetsSyncService();
  final _offlineQueueService = OfflineSurveyQueueService();
  final _networkStatusService = NetworkStatusService();
  final _secureStorage = SecureAppStorage();
  final surveys = <FarmerSurvey>[].obs;
  final pendingSubmissions = <PendingSurveySubmission>[].obs;
  final hasActiveDraft = false.obs;
  final isLoading = false.obs;
  final isSyncingPending = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;
  final deletingSurveyIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadSurveys();
    unawaited(syncPendingSurveys());
  }

  Future<void> loadSurveys() async {
    isLoading.value = true;
    hasError.value = false;
    errorMessage.value = '';
    await refreshDraftState();
    await loadPendingSubmissions();
    try {
      final online = await _networkStatusService.isOnline();
      if (!online) return;
      surveys.value = await _service.fetchAll();
    } catch (e, st) {
      debugPrint('[SurveyController.loadSurveys] $e\n$st');
      if (_networkStatusService.looksOffline(e)) {
        hasError.value = false;
        errorMessage.value = '';
        return;
      }
      hasError.value = true;
      errorMessage.value = _friendlyError(e);
    } finally {
      isLoading.value = false;
    }
    unawaited(syncPendingSurveys());
  }

  Future<void> loadPendingSubmissions() async {
    pendingSubmissions.value = await _offlineQueueService.loadQueue();
  }

  Future<void> refreshDraftState() async {
    try {
      final raw = await _secureStorage.readString('form_draft');
      if (raw == null || raw.isEmpty) {
        hasActiveDraft.value = false;
        return;
      }
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      final expiresAt = DateTime.tryParse(
        draft['__expires_at']?.toString() ?? '',
      );
      if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
        await _secureStorage.remove('form_draft');
        hasActiveDraft.value = false;
        return;
      }
      final dataKeys = draft.keys.where((key) => !key.startsWith('__'));
      final step = draft['__current_step'];
      hasActiveDraft.value =
          dataKeys.isNotEmpty ||
          (step is int && step > 0) ||
          draft['__kharif_rows'] is List ||
          draft['__yearly_rows'] is List ||
          draft['__practice_rows'] is List ||
          draft['__millet_land_areas'] is Map;
    } catch (_) {
      hasActiveDraft.value = false;
    }
  }

  Future<void> syncPendingSurveys() async {
    if (isSyncingPending.value) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    await loadPendingSubmissions();
    if (pendingSubmissions.isEmpty) return;
    if (!await _offlineQueueService.isOnline()) return;

    isSyncingPending.value = true;
    var syncedAny = false;
    try {
      for (final item in pendingSubmissions.toList()) {
        await _offlineQueueService.markSyncing(item.localId);
        await loadPendingSubmissions();
        try {
          final remoteId = await _service.insertWithChildren(
            item.parent,
            item.kharifRows,
            item.yearlyRows,
            item.practiceRows,
          );
          unawaited(
            _sheetsService.syncToSheet({...item.parent, '_id': remoteId}),
          );
          await _offlineQueueService.markSynced(item.localId, remoteId);
          syncedAny = true;
        } catch (e, st) {
          debugPrint('[SurveyController.syncPendingSurveys] $e\n$st');
          await _offlineQueueService.markFailed(item.localId, e);
          if (!await _offlineQueueService.isOnline()) break;
        }
        await loadPendingSubmissions();
      }
    } finally {
      isSyncingPending.value = false;
      await loadPendingSubmissions();
    }

    if (syncedAny) {
      try {
        surveys.value = await _service.fetchAll();
        hasError.value = false;
        Get.snackbar('Synced', 'Offline surveys synced to the database');
      } catch (e, st) {
        debugPrint('[SurveyController.syncPendingSurveys.refresh] $e\n$st');
      }
    }
  }

  bool isDeleting(String? surveyId) =>
      surveyId != null && deletingSurveyIds.contains(surveyId);

  /// Deletes the survey from Supabase, then mirrors the delete to Google Sheets.
  Future<bool> deleteSurvey(FarmerSurvey survey) async {
    final id = survey.id;
    if (id == null || id.isEmpty) {
      Get.snackbar('Delete failed', 'This survey is missing a database id.');
      return false;
    }
    if (deletingSurveyIds.contains(id)) return false;

    deletingSurveyIds.add(id);
    try {
      final deleted = await _service.delete(id);
      if (!deleted) {
        Get.snackbar(
          'Delete failed',
          'Survey was not deleted. It may already be gone, or this user may not own it.',
        );
        return false;
      }

      unawaited(
        _sheetsService.deleteFromSheet(
          farmerName: survey.farmerName ?? '',
          surveyDate: survey.surveyDate,
          mobileNo: survey.mobileNo,
        ),
      );
      Get.snackbar('Deleted', 'Survey deleted from the remote database');
      return true;
    } catch (e, st) {
      debugPrint('[SurveyController.deleteSurvey] $e\n$st');
      Get.snackbar('Error', _friendlyError(e));
      return false;
    } finally {
      deletingSurveyIds.remove(id);
    }
  }

  static String _friendlyError(Object e) {
    if (e is PostgrestException && e.code == '525') {
      return 'Server is temporarily unavailable. Please try again in a moment.';
    }
    return 'Something went wrong. Please check your connection and try again.';
  }
}
