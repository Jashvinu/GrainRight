import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class _TrustedRoleMiddleware extends GetMiddleware {
  Set<String> get roles;
  bool get requireFpcBinding => false;

  @override
  RouteSettings? redirect(String? route) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const RouteSettings(name: '/login');
    if (route != '/account/change-password' &&
        user.appMetadata['must_change_password'] == true) {
      return const RouteSettings(name: '/account/change-password');
    }
    final role = '${user.appMetadata['role'] ?? ''}'.trim().toLowerCase();
    final rawRoles = user.appMetadata['roles'];
    final serverRoles = <String>{role};
    if (rawRoles is Iterable) {
      serverRoles.addAll(
        rawRoles.map((value) => '$value'.trim().toLowerCase()),
      );
    }
    if (serverRoles.any(roles.contains)) {
      if (requireFpcBinding &&
          '${user.appMetadata['fpc_id'] ?? ''}'.trim().isEmpty) {
        return const RouteSettings(name: '/login');
      }
      return null;
    }
    return const RouteSettings(name: '/login');
  }
}

class AdminRouteMiddleware extends _TrustedRoleMiddleware {
  @override
  Set<String> get roles => const {'admin'};
}

class FpcAdminRouteMiddleware extends _TrustedRoleMiddleware {
  @override
  Set<String> get roles => const {
    'fpc',
    'fpo',
    'fpo_fpc',
    'fpo/fpc',
    'fpc_admin',
  };

  @override
  bool get requireFpcBinding => true;
}

class FieldOfficerRouteMiddleware extends _TrustedRoleMiddleware {
  @override
  Set<String> get roles => const {'field_officer'};

  @override
  bool get requireFpcBinding => true;
}

class FpcLoginRouteMiddleware extends _TrustedRoleMiddleware {
  @override
  Set<String> get roles => const {
    'fpc',
    'fpo',
    'fpo_fpc',
    'fpo/fpc',
    'fpc_admin',
    'field_officer',
  };

  @override
  bool get requireFpcBinding => true;
}
