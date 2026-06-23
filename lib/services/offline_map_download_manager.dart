import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../config/runtime_config.dart';
import 'offline_map_service.dart';

const offlineMapDownloadTask = 'grainright.offlineMapDownload';

@pragma('vm:entry-point')
void offlineMapCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != offlineMapDownloadTask || inputData == null) return true;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await RuntimeConfig.initialize();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Offline map config init skipped: $error');
      }
    }
    final service = OfflineMapService();
    try {
      final place = OfflinePlaceResult(
        placeId: inputData['placeId']?.toString() ?? '',
        title: inputData['title']?.toString() ?? 'Offline map',
        address: inputData['address']?.toString() ?? '',
        latitude: _doubleFrom(inputData['latitude']),
        longitude: _doubleFrom(inputData['longitude']),
      );
      await service
          .downloadRegion(
            place: place,
            radiusKm: _doubleFrom(inputData['radiusKm']),
            minZoom: _intFrom(inputData['minZoom']),
            maxZoom: _intFrom(inputData['maxZoom']),
          )
          .drain<void>();
      return true;
    } finally {
      service.dispose();
    }
  });
}

class OfflineMapDownloadManager {
  OfflineMapDownloadManager._();

  static final instance = OfflineMapDownloadManager._();

  final _service = OfflineMapService();
  final _progressController =
      StreamController<OfflineMapDownloadProgress>.broadcast();

  StreamSubscription<OfflineMapDownloadProgress>? _subscription;
  OfflineMapDownloadProgress? _lastProgress;
  Object? _lastError;

  Stream<OfflineMapDownloadProgress> get progressStream =>
      _progressController.stream;
  OfflineMapDownloadProgress? get lastProgress => _lastProgress;
  Object? get lastError => _lastError;
  bool get isDownloading => _subscription != null;

  Future<void> startDownload({
    required OfflinePlaceResult place,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) async {
    await _subscription?.cancel();
    _lastError = null;
    _subscription = _service
        .downloadRegion(
          place: place,
          radiusKm: radiusKm,
          minZoom: minZoom,
          maxZoom: maxZoom,
        )
        .listen(
          (progress) {
            _lastProgress = progress;
            _progressController.add(progress);
          },
          onError: (Object error, StackTrace stackTrace) {
            _lastError = error;
            _subscription = null;
            _progressController.addError(error, stackTrace);
          },
          onDone: () {
            _subscription = null;
            final progress = _lastProgress;
            if (progress != null) _progressController.add(progress);
          },
          cancelOnError: true,
        );

    unawaited(
      scheduleAndroidResume(
        place: place,
        radiusKm: radiusKm,
        minZoom: minZoom,
        maxZoom: maxZoom,
      ),
    );
  }

  Future<void> scheduleAndroidResume({
    required OfflinePlaceResult place,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().registerOneOffTask(
        'offline-map-${place.placeId}',
        offlineMapDownloadTask,
        inputData: {
          'placeId': place.placeId,
          'title': place.title,
          'address': place.address,
          'latitude': place.latitude,
          'longitude': place.longitude,
          'radiusKm': radiusKm,
          'minZoom': minZoom,
          'maxZoom': maxZoom,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
        tag: offlineMapDownloadTask,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Offline map background resume skipped: $error');
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _progressController.close();
    _service.dispose();
  }
}

double _doubleFrom(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

int _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
