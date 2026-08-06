import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class FpcNotificationRealtimeService {
  SupabaseClient? _client;
  RealtimeChannel? _channel;

  Future<void> start({
    required FutureOr<void> Function(Map<String, dynamic> notification)
    onNotification,
  }) async {
    await stop();
    final client = _initializedClient();
    if (client == null) return;
    final userId = client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    _client = client;
    final channel = client.channel('fpc-notifications:$userId');
    _channel = channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'fpc_notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_user_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isNotEmpty) onNotification(row);
        },
      )
      ..subscribe();
  }

  Future<void> stop() async {
    final client = _client;
    final channel = _channel;
    _client = null;
    _channel = null;
    if (client != null && channel != null) {
      await client.removeChannel(channel);
    }
  }

  SupabaseClient? _initializedClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
