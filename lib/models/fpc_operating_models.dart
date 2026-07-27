class FpcMembershipContext {
  final String membershipId;
  final String fpcId;
  final String fpcName;
  final String role;
  final String status;
  final bool mustChangePassword;

  const FpcMembershipContext({
    required this.membershipId,
    required this.fpcId,
    required this.fpcName,
    required this.role,
    required this.status,
    required this.mustChangePassword,
  });

  bool get isAdmin => role == 'fpc_admin';
  bool get isFieldOfficer => role == 'field_officer';

  factory FpcMembershipContext.fromJson(Map<String, dynamic> json) {
    final fpc = json['fpcs'];
    final fpcMap = fpc is Map
        ? Map<String, dynamic>.from(fpc)
        : const <String, dynamic>{};
    return FpcMembershipContext(
      membershipId: _text(json['id']),
      fpcId: _text(json['fpc_id']),
      fpcName: _text(fpcMap['name'], 'FPC workspace'),
      role: _text(json['role']),
      status: _text(json['status']),
      mustChangePassword: json['must_change_password'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': membershipId,
    'fpc_id': fpcId,
    'role': role,
    'status': status,
    'must_change_password': mustChangePassword,
    'fpcs': {'name': fpcName, 'status': 'active'},
  };
}

class FpcOperationRecord {
  final String id;
  final String module;
  final String recordType;
  final String title;
  final String status;
  final double? quantity;
  final double? amount;
  final DateTime? scheduledAt;
  final Map<String, dynamic> details;

  const FpcOperationRecord({
    required this.id,
    required this.module,
    required this.recordType,
    required this.title,
    required this.status,
    required this.details,
    this.quantity,
    this.amount,
    this.scheduledAt,
  });

  factory FpcOperationRecord.fromJson(Map<String, dynamic> json) {
    return FpcOperationRecord(
      id: _text(json['id']),
      module: _text(json['module']),
      recordType: _text(json['record_type']),
      title: _text(json['title']),
      status: _text(json['status']),
      quantity: _number(json['quantity']),
      amount: _number(json['amount']),
      scheduledAt: DateTime.tryParse(_text(json['scheduled_at'])),
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : const {},
    );
  }
}

class FieldAssignmentRecord {
  final String id;
  final String type;
  final String title;
  final String instructions;
  final String farmerId;
  final String farmId;
  final String status;
  final int serverVersion;
  final DateTime? scheduledFor;

  const FieldAssignmentRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.instructions,
    required this.farmerId,
    required this.farmId,
    required this.status,
    required this.serverVersion,
    this.scheduledFor,
  });

  factory FieldAssignmentRecord.fromJson(Map<String, dynamic> json) {
    return FieldAssignmentRecord(
      id: _text(json['id']),
      type: _text(json['assignment_type']),
      title: _text(json['title']),
      instructions: _text(json['instructions']),
      farmerId: _text(json['farmer_id']),
      farmId: _text(json['farm_id']),
      status: _text(json['status']),
      serverVersion: (json['server_version'] as num?)?.toInt() ?? 1,
      scheduledFor: DateTime.tryParse(_text(json['scheduled_for'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'assignment_type': type,
    'title': title,
    'instructions': instructions,
    'farmer_id': farmerId,
    'farm_id': farmId,
    'status': status,
    'server_version': serverVersion,
    if (scheduledFor != null)
      'scheduled_for': scheduledFor!.toUtc().toIso8601String(),
  };
}

class PlatformFpcSnapshot {
  final List<Map<String, dynamic>> applications;
  final List<Map<String, dynamic>> fpcs;
  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> subscriptions;
  final Map<String, dynamic> analytics;

  const PlatformFpcSnapshot({
    required this.applications,
    required this.fpcs,
    required this.memberships,
    required this.subscriptions,
    required this.analytics,
  });

  factory PlatformFpcSnapshot.fromJson(Map<String, dynamic> json) {
    return PlatformFpcSnapshot(
      applications: _rows(json['applications']),
      fpcs: _rows(json['fpcs']),
      memberships: _rows(json['memberships']),
      subscriptions: _rows(json['subscriptions']),
      analytics: json['analytics'] is Map
          ? Map<String, dynamic>.from(json['analytics'] as Map)
          : const {},
    );
  }
}

List<Map<String, dynamic>> _rows(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String _text(Object? value, [String fallback = '']) {
  final result = value == null ? '' : '$value'.trim();
  return result.isEmpty || result.toLowerCase() == 'null' ? fallback : result;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value));
}
