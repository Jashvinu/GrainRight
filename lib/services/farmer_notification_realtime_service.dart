import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'farm_status_notification_service.dart';

class FarmerNotificationRealtimeService {
  RealtimeChannel? _channel;

  Future<void> start({
    required FutureOr<void> Function(FarmerNotification notification)
    onNotification,
  }) async {
    await stop();
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    final channel = client.channel('farmer-notifications:$userId');
    _channel = channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'farmer_notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_user_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          onNotification(FarmerNotification.fromJson(row));
        },
      )
      ..subscribe();
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }
}
