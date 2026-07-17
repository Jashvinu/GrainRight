import 'package:supabase_flutter/supabase_flutter.dart';

class FpcAccountIdentity {
  final String organizationName;
  final String displayName;
  final String email;
  final String role;
  final String userId;
  final String phone;

  const FpcAccountIdentity({
    required this.organizationName,
    required this.displayName,
    required this.email,
    required this.role,
    this.userId = '',
    this.phone = '',
  });

  String get name {
    if (organizationName.isNotEmpty) return organizationName;
    if (displayName.isNotEmpty) return displayName;
    return 'FPC workspace';
  }

  String get roleLabel => role.isEmpty ? 'FPC' : role.toUpperCase();

  factory FpcAccountIdentity.current() {
    final user = Supabase.instance.client.auth.currentUser;
    return FpcAccountIdentity.fromMetadata(
      userMetadata: user?.userMetadata,
      appMetadata: user?.appMetadata,
      email: user?.email,
      userId: user?.id,
    );
  }

  factory FpcAccountIdentity.fromMetadata({
    Map<String, dynamic>? userMetadata,
    Map<String, dynamic>? appMetadata,
    String? email,
    String? userId,
  }) {
    final user = userMetadata ?? const <String, dynamic>{};
    final app = appMetadata ?? const <String, dynamic>{};
    return FpcAccountIdentity(
      organizationName: '${user['organization_name'] ?? ''}'.trim(),
      displayName: '${user['display_name'] ?? user['full_name'] ?? ''}'.trim(),
      email: (email ?? '').trim().isEmpty ? 'FPC account' : email!.trim(),
      role: '${app['role'] ?? user['role'] ?? 'fpc'}'.trim(),
      userId: (userId ?? '').trim(),
      phone: '${user['phone'] ?? ''}'.trim(),
    );
  }
}
