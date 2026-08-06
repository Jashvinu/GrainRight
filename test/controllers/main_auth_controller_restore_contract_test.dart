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
  final fpcServiceSource = File(
    'lib/services/fpc_operating_service.dart',
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
    expect(source, contains('.timeout(_fpcMembershipTimeout)'));
    expect(source, contains('if (membership == null)'));
    expect(source, contains("return '/fpo';"));
    expect(
      source,
      isNot(contains('final readiness = await FpcOperatingService()')),
    );
    expect(
      source,
      isNot(
        contains(
          "return const {'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'}.contains(role)",
        ),
      ),
    );
    expect(splashSource, contains('await auth.resolveFpcLoginRoute(user)'));
    expect(splashSource, contains('if (fpcRoute == null)'));
    expect(
      middlewareSource,
      contains("user.appMetadata['must_change_password']"),
    );
    expect(middlewareSource, contains('requireFpcBinding'));
    expect(middlewareSource, contains("user.appMetadata['fpc_id']"));
    expect(
      middlewareSource,
      contains("RouteSettings(name: '/account/change-password')"),
    );
  });

  test('restored FPC sessions do not wait for farmer or readiness reads', () {
    expect(source, contains('if (_auth.currentSession != null)'));
    expect(source, contains('_hasServerRole(currentUser, _fpcServerRoles)'));
    expect(fpcServiceSource, contains('static const _fpcReadTimeout'));
    expect(
      fpcServiceSource,
      contains(
        'loadSetupReadiness(membership)\n          .timeout(_fpcReadTimeout)',
      ),
    );
    expect(
      fpcServiceSource.indexOf('_countActiveFieldOfficers(context.fpcId)'),
      lessThan(fpcServiceSource.indexOf("_countWhere('collection_centers'")),
    );
  });
}
