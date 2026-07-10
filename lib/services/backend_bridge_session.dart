import 'package:get/get.dart';

import '../config/runtime_config.dart';
import '../controllers/auth_controller.dart';

class BackendBridgeSession {
  final String accessToken;
  final String userId;
  final String email;

  const BackendBridgeSession({
    required this.accessToken,
    required this.userId,
    required this.email,
  });
}

Future<BackendBridgeSession> ensureBackendBridgeSession() async {
  final email = RuntimeConfig.backendAuthEmail.trim();
  final password = RuntimeConfig.backendAuthPassword.trim();
  if (email.isEmpty || password.isEmpty) {
    throw StateError(
      'Backend auth account is not configured. Set BACKEND_AUTH_PASSWORD.',
    );
  }

  final auth = Get.isRegistered<AuthController>()
      ? Get.find<AuthController>()
      : Get.put(AuthController());
  final result = await auth.ensureBackendAccountSession(
    email: email,
    password: password,
  );
  final token = result.accessToken.trim();
  final userId = result.userId.trim();
  if (token.isEmpty || userId.isEmpty) {
    throw StateError('Backend auth account did not return a usable session.');
  }
  return BackendBridgeSession(
    accessToken: token,
    userId: userId,
    email: result.email,
  );
}
