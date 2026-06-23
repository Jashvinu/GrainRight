import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

class FarmerNotification {
  final String id;
  final String farmerId;
  final String farmId;
  final String type;
  final String title;
  final String message;
  final String farmName;
  final DateTime createdAt;
  final DateTime? readAt;

  const FarmerNotification({
    required this.id,
    required this.farmerId,
    required this.farmId,
    required this.type,
    required this.title,
    required this.message,
    required this.farmName,
    required this.createdAt,
    required this.readAt,
  });

  bool get isRead => readAt != null;

  FarmerNotification copyWith({DateTime? readAt}) {
    return FarmerNotification(
      id: id,
      farmerId: farmerId,
      farmId: farmId,
      type: type,
      title: title,
      message: message,
      farmName: farmName,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  factory FarmerNotification.fromJson(Map<String, dynamic> json) {
    DateTime readDate(dynamic raw) {
      return DateTime.tryParse('${raw ?? ''}') ?? DateTime.now();
    }

    DateTime? readNullableDate(dynamic raw) {
      final text = '${raw ?? ''}'.trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    return FarmerNotification(
      id: '${json['id'] ?? ''}',
      farmerId: '${json['farmer_id'] ?? json['farmerId'] ?? ''}',
      farmId: '${json['farm_id'] ?? json['farmId'] ?? ''}',
      type: '${json['type'] ?? 'farm_status_update'}',
      title: '${json['title'] ?? ''}',
      message: '${json['message'] ?? ''}',
      farmName: '${json['farm_name'] ?? json['farmName'] ?? ''}',
      createdAt: readDate(json['created_at'] ?? json['createdAt']),
      readAt: readNullableDate(json['read_at'] ?? json['readAt']),
    );
  }
}

class FarmStatusNotificationService {
  static const _notifyFunctionUrl =
      '${SupabaseConfig.edgeFunctionsBase}/farm-status-notify';
  final http.Client _client;

  FarmStatusNotificationService({http.Client? client})
    : _client = client ?? http.Client();

  Future<FarmerNotification?> sendFarmStatusNotification({
    required String farmerId,
    required String farmerName,
    String? farmId,
    required String farmName,
    required String crop,
    required String variety,
    required String location,
    required String stage,
    required String stageQuestion,
    required int daysAfterSowing,
    required String statusText,
    String? farmerPhone,
    String? priorStatus,
    String? title,
    String? message,
    String? authToken,
  }) async {
    final payload = <String, dynamic>{
      'action': 'create',
      'type': 'farm_status_update',
      'farmerId': farmerId,
      'farmId': farmId,
      'farmerPhone': farmerPhone,
      'farmerName': farmerName,
      'farmName': farmName,
      'crop': crop,
      'variety': variety,
      'location': location,
      'stage': stage,
      'stageQuestion': stageQuestion,
      'daysAfterSowing': daysAfterSowing,
      'statusText': statusText,
      'priorStatus': priorStatus,
      'title': title,
      'message': message,
      'source': 'farmer_dashboard_status_chat',
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final data = await _post(payload, authToken: authToken);
    return _notificationFromResponse(data);
  }

  Future<FarmerNotification?> sendFarmAlertNotification({
    required String farmerId,
    required String farmerName,
    required String farmId,
    required String farmName,
    required String crop,
    required String variety,
    required String location,
    required String title,
    required String message,
    String? farmerPhone,
    String type = 'farm_alert',
    String? stage,
    String? stageQuestion,
    int? daysAfterSowing,
    String? statusText,
    String? priorStatus,
    String source = 'farmer_dashboard_alert',
    Map<String, dynamic> payload = const {},
    String? authToken,
  }) async {
    final safeTitle = title.trim();
    final safeMessage = message.trim();
    if (safeTitle.isEmpty || safeMessage.isEmpty) return null;

    final data = await _post({
      'action': 'create',
      'type': type,
      'farmerId': farmerId,
      'farmId': farmId,
      'farmerPhone': farmerPhone,
      'farmerName': farmerName,
      'farmName': farmName,
      'crop': crop,
      'variety': variety,
      'location': location,
      'stage': stage,
      'stageQuestion': stageQuestion,
      'daysAfterSowing': daysAfterSowing,
      'statusText': statusText,
      'priorStatus': priorStatus,
      'title': safeTitle,
      'message': safeMessage,
      'source': source,
      'payload': payload,
      'updatedAt': DateTime.now().toIso8601String(),
    }, authToken: authToken);
    return _notificationFromResponse(data);
  }

  Future<List<FarmerNotification>> listNotifications({
    required String farmerId,
    String? farmerPhone,
    String? farmId,
    String? authToken,
  }) async {
    final data = await _post({
      'action': 'list',
      'farmerId': farmerId,
      'farmerPhone': farmerPhone,
      'farmId': farmId,
    }, authToken: authToken);
    final raw = data['notifications'];
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => FarmerNotification.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<bool> markNotificationRead({
    required String farmerId,
    required String notificationId,
    String? farmerPhone,
    String? authToken,
  }) async {
    final data = await _post({
      'action': 'mark_read',
      'farmerId': farmerId,
      'farmerPhone': farmerPhone,
      'notificationId': notificationId,
    }, authToken: authToken);
    return data['marked_read'] == true || data['notification'] is Map;
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    String? authToken,
  }) async {
    final token = authToken == null || authToken.trim().isEmpty
        ? SupabaseConfig.anonKey
        : authToken.trim();
    try {
      final response = await _client.post(
        Uri.parse(_notifyFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode != 200) {
        debugPrint(
          '[FarmerNotification] ${response.statusCode} ${response.body}',
        );
        return const <String, dynamic>{};
      }
      final decoded = jsonDecode(response.body);
      final root = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      return root['data'] is Map
          ? Map<String, dynamic>.from(root['data'] as Map)
          : root;
    } catch (e) {
      debugPrint('[FarmerNotification] $e');
      return const <String, dynamic>{};
    }
  }

  FarmerNotification? _notificationFromResponse(Map<String, dynamic> data) {
    final raw = data['notification'];
    if (raw is Map) {
      return FarmerNotification.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }
}
