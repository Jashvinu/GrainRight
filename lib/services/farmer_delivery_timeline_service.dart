import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/farmer_delivery_timeline_item.dart';

class FarmerDeliveryTimelineException implements Exception {
  final String message;
  const FarmerDeliveryTimelineException(this.message);
  @override
  String toString() => message;
}

class FarmerDeliveryTimelineService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<FarmerDeliveryTimelineItem>> loadForCurrentFarmer() async {
    if (_client.auth.currentUser == null) {
      throw const FarmerDeliveryTimelineException('Farmer login required.');
    }
    final rows = await _client
        .from('farmer_delivery_timeline')
        .select()
        .order('occurred_at', ascending: false)
        .limit(300);
    return _items(rows);
  }

  Future<void> acknowledgeSeed(String seedIssueId) async {
    final id = seedIssueId.trim();
    if (id.isEmpty) return;
    await _client.rpc(
      'farmer_acknowledge_crop_program_seed',
      params: {'p_seed_issue_id': id},
    );
  }

  List<FarmerDeliveryTimelineItem> _items(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (row) => FarmerDeliveryTimelineItem.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }
}
