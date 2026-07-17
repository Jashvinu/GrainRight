import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../services/admin_service.dart';

class AdminController extends GetxController {
  AdminController({AdminService? service})
    : _service = service ?? AdminService();

  final AdminService _service;

  final snapshot = Rxn<AdminDashboardSnapshot>();
  final isLoading = false.obs;
  final isReviewing = false.obs;
  final errorMessage = ''.obs;
  final adminNote = ''.obs;
  final stakeholderFilter = 'pending'.obs;

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
