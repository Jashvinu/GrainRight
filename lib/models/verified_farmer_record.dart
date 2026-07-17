class VerifiedFarmerRecord {
  final String phone;
  final String farmerId;
  final String farmerName;
  final String defaultLocation;
  final String agriRecordId;
  final String aadhaarNumber;
  final String aadhaarMasked;
  final String aadhaarLast4;
  final String identityDocumentPath;
  final List<VerifiedFarmerLot> lots;

  const VerifiedFarmerRecord({
    required this.phone,
    required this.farmerId,
    required this.farmerName,
    required this.defaultLocation,
    this.agriRecordId = '',
    this.aadhaarNumber = '',
    this.aadhaarMasked = '',
    this.aadhaarLast4 = '',
    this.identityDocumentPath = '',
    required this.lots,
  });

  factory VerifiedFarmerRecord.fromJson(Map<String, dynamic> json) {
    final rawLots = json['lots'];
    return VerifiedFarmerRecord(
      phone: '${json['phone']}',
      farmerId: '${json['farmerId']}',
      farmerName: '${json['farmerName']}',
      defaultLocation: '${json['defaultLocation']}',
      agriRecordId: '${json['agriRecordId'] ?? json['agri_record_id'] ?? ''}'
          .trim(),
      aadhaarNumber: '${json['aadhaarNumber'] ?? json['aadhaar_number'] ?? ''}'
          .trim(),
      aadhaarMasked: '${json['aadhaarMasked'] ?? json['aadhaar_masked'] ?? ''}'
          .trim(),
      aadhaarLast4: '${json['aadhaarLast4'] ?? json['aadhaar_last4'] ?? ''}'
          .trim(),
      identityDocumentPath:
          '${json['identityDocumentPath'] ?? json['identity_document_path'] ?? ''}'
              .trim(),
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
