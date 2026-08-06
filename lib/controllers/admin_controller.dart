import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../services/admin_service.dart';

class AdminController extends GetxController {
  AdminController({AdminService? service})
    : _service = service ?? AdminService();

  final AdminService _service;

  final snapshot = Rxn<AdminDashboardSnapshot>();
  final shareholderCandidatePage = Rxn<AdminShareholderCandidatePage>();
  final isLoading = false.obs;
  final isLoadingShareholderCandidates = false.obs;
  final isReviewing = false.obs;
  final errorMessage = ''.obs;
  final shareholderCandidateError = ''.obs;
  final adminNote = ''.obs;
  final stakeholderFilter = 'pending'.obs;
  final shareholderCandidateSearch = ''.obs;
  final shareholderCandidateVillage = ''.obs;
  final shareholderCandidateTaluka = ''.obs;
  final shareholderCandidateDistrict = ''.obs;

  static const shareholderCandidatePageSize = 100;
  int _candidateRequestToken = 0;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      unawaited(loadDashboard());
    });
  }

  Future<void> loadDashboard() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      snapshot.value = await _service.loadDashboard();
    } catch (error) {
      errorMessage.value = _cleanError(error);
      snapshot.value ??= AdminDashboardSnapshot.empty();
    } finally {
      isLoading.value = false;
    }
  }

  void setAdminNote(String value) {
    adminNote.value = value.trim();
  }

  void setStakeholderFilter(String value) {
    stakeholderFilter.value = value.trim().isEmpty ? 'pending' : value.trim();
  }

  Future<void> loadShareholderCandidates({
    bool resetOffset = false,
    int? offset,
  }) async {
    final requestToken = ++_candidateRequestToken;
    final currentOffset = resetOffset
        ? 0
        : (offset ?? shareholderCandidatePage.value?.offset ?? 0);
    isLoadingShareholderCandidates.value = true;
    shareholderCandidateError.value = '';
    try {
      final page = await _service.loadShareholderCandidates(
        search: shareholderCandidateSearch.value,
        village: shareholderCandidateVillage.value,
        taluka: shareholderCandidateTaluka.value,
        district: shareholderCandidateDistrict.value,
        offset: currentOffset,
        limit: shareholderCandidatePageSize,
      );
      if (requestToken == _candidateRequestToken) {
        shareholderCandidatePage.value = page;
      }
    } catch (error) {
      if (requestToken == _candidateRequestToken) {
        shareholderCandidateError.value = _cleanError(error);
        shareholderCandidatePage.value ??=
            AdminShareholderCandidatePage.empty();
      }
    } finally {
      if (requestToken == _candidateRequestToken) {
        isLoadingShareholderCandidates.value = false;
      }
    }
  }

  void searchShareholderCandidates(String value) {
    shareholderCandidateSearch.value = value.trim();
    unawaited(loadShareholderCandidates(resetOffset: true));
  }

  void setShareholderCandidateVillage(String value) {
    shareholderCandidateVillage.value = value.trim();
    unawaited(loadShareholderCandidates(resetOffset: true));
  }

  void setShareholderCandidateTaluka(String value) {
    shareholderCandidateTaluka.value = value.trim();
    unawaited(loadShareholderCandidates(resetOffset: true));
  }

  void setShareholderCandidateDistrict(String value) {
    shareholderCandidateDistrict.value = value.trim();
    unawaited(loadShareholderCandidates(resetOffset: true));
  }

  void previousShareholderCandidatePage() {
    final page = shareholderCandidatePage.value;
    if (page == null || page.offset <= 0) return;
    final offset = (page.offset - page.limit).clamp(0, page.totalCount).toInt();
    unawaited(loadShareholderCandidates(offset: offset));
  }

  void nextShareholderCandidatePage() {
    final page = shareholderCandidatePage.value;
    if (page == null || page.offset + page.rows.length >= page.totalCount) {
      return;
    }
    unawaited(loadShareholderCandidates(offset: page.offset + page.limit));
  }

  Future<bool> reviewStakeholder({
    required String applicationId,
    required String status,
    String? note,
  }) async {
    if (applicationId.trim().isEmpty) {
      errorMessage.value = 'Select a stakeholder application.';
      return false;
    }
    final reviewNote = note?.trim() ?? adminNote.value;
    if (status == 'rejected' && reviewNote.length < 5) {
      errorMessage.value = 'Add a clear rejection reason before rejecting.';
      return false;
    }
    isReviewing.value = true;
    errorMessage.value = '';
    try {
      await _service.reviewStakeholder(
        applicationId: applicationId,
        status: status,
        adminNote: reviewNote,
      );
      adminNote.value = '';
      await loadDashboard();
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isReviewing.value = false;
    }
  }

  Future<String?> stakeholderDocumentUrl(String documentPath) async {
    if (documentPath.trim().isEmpty) {
      errorMessage.value = 'Select a stakeholder document.';
      return null;
    }
    errorMessage.value = '';
    try {
      return await _service.createStakeholderDocumentUrl(documentPath.trim());
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return null;
    }
  }

  String _cleanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Admin workflow sync failed.' : text;
  }
}
