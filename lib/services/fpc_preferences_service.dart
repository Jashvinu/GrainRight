import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FpcPreferences {
  static const _autoRefreshKey = 'fpc_auto_refresh_ledgers';
  static const _reviewAlertsKey = 'fpc_review_queue_alerts';
  static const _marketAlertsKey = 'fpc_marketplace_interest_alerts';
  static const _scanSoundKey = 'fpc_scanner_sound_feedback';

  final bool autoRefreshLedgers;
  final bool reviewQueueAlerts;
  final bool marketplaceInterestAlerts;
  final bool scannerSoundFeedback;

  const FpcPreferences({
    this.autoRefreshLedgers = true,
    this.reviewQueueAlerts = true,
    this.marketplaceInterestAlerts = true,
    this.scannerSoundFeedback = false,
  });

  static Future<FpcPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return FpcPreferences(
      autoRefreshLedgers: prefs.getBool(_autoRefreshKey) ?? true,
      reviewQueueAlerts: prefs.getBool(_reviewAlertsKey) ?? true,
      marketplaceInterestAlerts: prefs.getBool(_marketAlertsKey) ?? true,
      scannerSoundFeedback: prefs.getBool(_scanSoundKey) ?? false,
    );
  }

  static Future<void> playScannerFeedbackIfEnabled() async {
    final preferences = await load();
    if (preferences.scannerSoundFeedback) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(_autoRefreshKey, autoRefreshLedgers),
      prefs.setBool(_reviewAlertsKey, reviewQueueAlerts),
      prefs.setBool(_marketAlertsKey, marketplaceInterestAlerts),
      prefs.setBool(_scanSoundKey, scannerSoundFeedback),
    ]);
  }

  FpcPreferences copyWith({
    bool? autoRefreshLedgers,
    bool? reviewQueueAlerts,
    bool? marketplaceInterestAlerts,
    bool? scannerSoundFeedback,
  }) {
    return FpcPreferences(
      autoRefreshLedgers: autoRefreshLedgers ?? this.autoRefreshLedgers,
      reviewQueueAlerts: reviewQueueAlerts ?? this.reviewQueueAlerts,
      marketplaceInterestAlerts:
          marketplaceInterestAlerts ?? this.marketplaceInterestAlerts,
      scannerSoundFeedback: scannerSoundFeedback ?? this.scannerSoundFeedback,
    );
  }
}
