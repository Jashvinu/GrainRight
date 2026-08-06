import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();

  PushNotificationService._();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  bool _initialized = false;

  static void registerBackgroundHandler() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> initialize() async {
    if (_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _initialized = true;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
      (token) => unawaited(_saveTokenIfFpcAdmin(token)),
      onError: (Object error) {
        debugPrint('[FPCPush] token refresh failed: $error');
      },
    );
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => unawaited(_registerCurrentToken()),
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_showForegroundMessage(message)),
    );
    await _registerCurrentToken();
  }

  Future<void> _registerCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _saveTokenIfFpcAdmin(token);
      }
    } catch (error) {
      debugPrint('[FPCPush] token registration failed: $error');
    }
  }

  Future<void> _saveTokenIfFpcAdmin(String token) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    try {
      final membership = await client
          .from('fpc_memberships')
          .select('id')
          .eq('user_id', userId)
          .eq('role', 'fpc_admin')
          .eq('status', 'active')
          .limit(1)
          .maybeSingle();
      if (membership == null) return;
      await client.from('fpc_push_tokens').upsert({
        'user_id': userId,
        'token': token.trim(),
        'platform': 'android',
        'app_role': 'fpc_admin',
        'active': true,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (error) {
      debugPrint('[FPCPush] token save failed: $error');
    }
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title?.trim() ?? '';
    final body = notification?.body?.trim() ?? '';
    if (title.isEmpty || body.isEmpty) return;
    await LocalNotificationService.instance.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      message: body,
      payload: message.data['notification_id'] ?? '',
      type: message.data['event_key'] ?? 'fpc_push',
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _authSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _initialized = false;
  }
}
