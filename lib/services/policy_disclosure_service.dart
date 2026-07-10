import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ui_strings.dart';

class PolicyDisclosureService {
  static const _locationAcceptedKey = 'policy_location_disclosure_accepted';
  static const _photoAcceptedKey = 'policy_photo_disclosure_accepted';

  PolicyDisclosureService._();

  static Future<bool> confirmLocationUse(BuildContext context) {
    return _confirmOnce(
      context: context,
      preferenceKey: _locationAcceptedKey,
      title: UiStrings.t('location_disclosure_title'),
      message: UiStrings.t('location_disclosure_body'),
    );
  }

  static Future<bool> confirmPhotoUse(BuildContext context) {
    return _confirmOnce(
      context: context,
      preferenceKey: _photoAcceptedKey,
      title: UiStrings.t('photo_disclosure_title'),
      message: UiStrings.t('photo_disclosure_body'),
    );
  }

  static Future<bool> _confirmOnce({
    required BuildContext context,
    required String preferenceKey,
    required String title,
    required String message,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(preferenceKey) == true) return true;
    if (!context.mounted) return false;

    final accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(UiStrings.t('not_now')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(UiStrings.t('continue_')),
                ),
              ],
            );
          },
        ) ??
        false;

    if (accepted) {
      await prefs.setBool(preferenceKey, true);
    }
    return accepted;
  }
}
