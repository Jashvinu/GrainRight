import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/farmer_home_screen.dart').readAsStringSync();

  test('farm services retain the signed-in Supabase JWT after navigation', () {
    final tokenMethodStart = source.indexOf('String _satelliteRequestToken()');
    final tokenMethodEnd = source.indexOf(
      'String? _verifiedFarmerPhone()',
      tokenMethodStart,
    );

    expect(tokenMethodStart, isNonNegative);
    expect(tokenMethodEnd, greaterThan(tokenMethodStart));

    final tokenMethod = source.substring(tokenMethodStart, tokenMethodEnd);
    expect(
      tokenMethod,
      contains('Supabase.instance.client.auth.currentSession?.accessToken'),
    );
    expect(
      tokenMethod.indexOf('if (sessionToken.isNotEmpty) return sessionToken;'),
      lessThan(
        tokenMethod.indexOf(
          "if (!Get.isRegistered<AuthController>()) return '';",
        ),
      ),
    );
  });

  test('daily tasks discard stale results after the selected farm changes', () {
    expect(source, contains('final farmId = widget.farmId.trim();'));
    expect(source, contains('final fingerprint = <String>['));
    expect(source, contains('int _syncGeneration = 0;'));
    expect(source, contains('generation == _syncGeneration'));
    expect(source, contains('widget.farmId.trim() == farmId'));
  });
}
