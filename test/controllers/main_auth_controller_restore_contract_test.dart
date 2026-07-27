import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/controllers/main_auth_controller.dart',
  ).readAsStringSync();
  final splashSource = File(
    'lib/screens/splash_screen.dart',
  ).readAsStringSync();
  final middlewareSource = File(
    'lib/app/routes/role_route_middleware.dart',
  ).readAsStringSync();

  test('restored farmer profiles repair the remote link before use', () {
    final lookupStart = source.indexOf(
      'Future<List<dynamic>> _farmerProfileRowsForUser',
    );
    final restoreStart = source.indexOf(
      'Future<VerifiedFarmerRecord?> _loadRemoteFarmerProfile',
    );
    final restoreEnd = source.indexOf(
      'Future<VerifiedFarmerRecord> _createFarmerProfileFromCurrentUser',
    );

    expect(lookupStart, isNonNegative);
    expect(restoreStart, greaterThan(lookupStart));
    expect(restoreEnd, greaterThan(restoreStart));

    final lookupSource = source.substring(lookupStart, restoreStart);
    final restoreSource = source.substring(restoreStart, restoreEnd);

    expect(lookupSource, contains('status'));
    expect(restoreSource, contains("row['status']"));
    expect(restoreSource, contains('await _linkRemoteFarmerPhone'));
    expect(restoreSource, isNot(contains('unawaited(_linkRemoteFarmerPhone')));
  });

  test('concurrent verified-profile refreshes share one operation', () {
    expect(source, contains('_verifiedProfileRefreshInFlight'));
    expect(source, contains('_refreshVerifiedProfileOnce'));
  });

  test('restored FPC sessions revalidate membership and password state', () {
    expect(source, contains('Future<String?> resolveFpcLoginRoute'));
    expect(source, contains("select('role,status,must_change_password"));
    expect(splashSource, contains('await auth.resolveFpcLoginRoute(user)'));
    expect(splashSource, contains('if (fpcRoute == null)'));
    expect(
      middlewareSource,
      contains("user.appMetadata['must_change_password']"),
    );
    expect(
      middlewareSource,
      contains("RouteSettings(name: '/account/change-password')"),
    );
  });
}
