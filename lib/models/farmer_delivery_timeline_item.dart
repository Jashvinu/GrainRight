class FarmerDeliveryTimelineItem {
  final String id;
  final String type;
  final String fpcId;
  final String fpcName;
  final String farmerId;
  final String farmId;
  final String title;
  final String status;
  final String paymentStatus;
  final double? quantityKg;
  final double? amount;
  final String currency;
  final DateTime? occurredAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> evidence;
  final Map<String, dynamic> metadata;
  final String acknowledgementAction;
  final String acknowledgeSeedIssueId;

  const FarmerDeliveryTimelineItem({
    required this.id,
    required this.type,
    required this.fpcId,
    required this.fpcName,
    required this.farmerId,
    required this.farmId,
    required this.title,
    required this.status,
    required this.paymentStatus,
    required this.quantityKg,
    required this.amount,
    required this.currency,
    required this.occurredAt,
    required this.updatedAt,
    required this.evidence,
    required this.metadata,
    required this.acknowledgementAction,
    required this.acknowledgeSeedIssueId,
  });

  factory FarmerDeliveryTimelineItem.fromJson(Map<String, dynamic> json) {
    return FarmerDeliveryTimelineItem(
      id: _text(json['timeline_id']),
      type: _text(json['record_type']),
      fpcId: _text(json['fpc_id']),
      fpcName: _text(json['fpc_name'], 'FPC'),
      farmerId: _text(json['farmer_id']),
      farmId: _text(json['farm_id']),
      title: _text(json['title'], 'Delivery update'),
      status: _text(json['status']),
      paymentStatus: _text(json['payment_status']),
      quantityKg: _number(json['quantity_kg']),
      amount: _number(json['amount']),
      currency: _text(json['currency'], 'INR'),
      occurredAt: DateTime.tryParse(_text(json['occurred_at'])),
      updatedAt: DateTime.tryParse(_text(json['updated_at'])),
      evidence: _map(json['evidence']),
      metadata: _map(json['metadata']),
      acknowledgementAction: _text(json['acknowledgement_action']),
      acknowledgeSeedIssueId: _text(json['acknowledge_seed_issue_id']),
    );
  }

  bool get needsSeedAcknowledgement =>
      acknowledgementAction == 'acknowledge_seed' &&
      acknowledgeSeedIssueId.isNotEmpty;

  bool get hasPaymentStatus => paymentStatus.trim().isNotEmpty;
  bool get hasEvidence => evidence.isNotEmpty;

  String get typeLabel => switch (type) {
    'seed_request' => 'Seed request',
    'seed_delivery' => 'Seed delivery',
    'procurement_delivery' => 'Procurement delivery',
    'procurement_lot' => 'Procurement lot',
    'farmer_payment' => 'Farmer payment',
    'buyer_dispatch' => 'Buyer dispatch',
    _ => title,
  };

  String get statusLabel => _label(status);
  String get paymentStatusLabel => _label(paymentStatus);

  static String _label(String value) {
    final normalized = value.trim().replaceAll('_', ' ');
    if (normalized.isEmpty) return '';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

String _text(Object? value, [String fallback = '']) {
  final text = value == null ? '' : '$value'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value));
}
