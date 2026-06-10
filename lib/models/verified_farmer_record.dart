class VerifiedFarmerRecord {
  final String phone;
  final String farmerId;
  final String farmerName;
  final String defaultLocation;
  final List<VerifiedFarmerLot> lots;

  const VerifiedFarmerRecord({
    required this.phone,
    required this.farmerId,
    required this.farmerName,
    required this.defaultLocation,
    required this.lots,
  });

  factory VerifiedFarmerRecord.fromJson(Map<String, dynamic> json) {
    final rawLots = json['lots'];
    return VerifiedFarmerRecord(
      phone: '${json['phone']}',
      farmerId: '${json['farmerId']}',
      farmerName: '${json['farmerName']}',
      defaultLocation: '${json['defaultLocation']}',
      lots: rawLots is List
          ? rawLots
              .whereType<Map<String, dynamic>>()
              .map(VerifiedFarmerLot.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class VerifiedFarmerLot {
  final String product;
  final String grain;
  final String harvestDate;
  final String location;
  final String variety;
  final String grade;

  const VerifiedFarmerLot({
    required this.product,
    required this.grain,
    required this.harvestDate,
    required this.location,
    required this.variety,
    required this.grade,
  });

  factory VerifiedFarmerLot.fromJson(Map<String, dynamic> json) {
    return VerifiedFarmerLot(
      product: '${json['product']}',
      grain: '${json['grain']}',
      harvestDate: '${json['harvestDate']}',
      location: '${json['location']}',
      variety: '${json['variety']}',
      grade: '${json['grade']}',
    );
  }
}
