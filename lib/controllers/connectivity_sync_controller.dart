import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../services/offline_survey_queue_service.dart';
import 'survey_controller.dart';

class ConnectivitySyncController extends GetxController
    with WidgetsBindingObserver {
  final _offlineQueueService = OfflineSurveyQueueService();
  StreamSubscription<Object>? _connectivitySubscription;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = _offlineQueueService.connectivityChanges.listen(
      (_) => _syncPendingSurveys(),
    );
    unawaited(_syncPendingSurveys());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPendingSurveys());
    }
  }

  Future<void> _syncPendingSurveys() async {
    if (!Get.isRegistered<SurveyController>()) return;
    await Get.find<SurveyController>().syncPendingSurveys();
  }
}
