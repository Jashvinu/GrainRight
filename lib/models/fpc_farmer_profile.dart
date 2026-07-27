class FpcFarmerProfile {
  final String linkId;
  final String farmerId;
  final String name;
  final String phone;
  final String village;
  final String farmId;
  final String primaryFarm;
  final String area;
  final String crop;
  final String variety;
  final String detail;
  final String lastYield;
  final String lastGrade;
  final String fpcRating;
  final String kycStatus;
  final String linkStatus;
  final String maskedIdentity;
  final DateTime? linkedAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> currentCrop;
  final List<Map<String, dynamic>> productionHistory;
  final List<Map<String, dynamic>> sellingHistory;

  const FpcFarmerProfile({
    required this.linkId,
    required this.farmerId,
    required this.name,
    required this.phone,
    required this.village,
    required this.farmId,
    required this.primaryFarm,
    required this.area,
    required this.crop,
    required this.variety,
    required this.detail,
    required this.lastYield,
    required this.lastGrade,
    required this.fpcRating,
    required this.kycStatus,
    required this.linkStatus,
    required this.maskedIdentity,
    required this.linkedAt,
    required this.updatedAt,
    required this.currentCrop,
    required this.productionHistory,
    required this.sellingHistory,
  });

  bool get isActive => linkStatus.toLowerCase() == 'active';

  bool get isVerified =>
      kycStatus.toLowerCase() == 'verified' || maskedIdentity.isNotEmpty;

  String get season => _first([currentCrop['season']]);

  String get expectedYield => _first([
    currentCrop['expectedYield'],
    currentCrop['expected_yield'],
    lastYield,
  ]);

  String get currentGrade => _first([currentCrop['grade'], lastGrade]);

  String get currentCropDetail => _first([currentCrop['detail']]);

  String get searchText => [
    name,
    farmerId,
    phone,
    village,
    primaryFarm,
    crop,
    variety,
    kycStatus,
  ].join(' ').toLowerCase();

  Map<String, dynamic> get gradingArguments => {
    'mode': 'fpc',
    'farmerId': farmerId,
    'farmerName': name,
    'fpcCustomerId': farmerId.isEmpty ? 'FPC-CUSTOMER' : farmerId,
    'fpcCustomerName': name,
    'farmId': farmId.isEmpty ? farmerId : farmId,
    'farmName': primaryFarm.isEmpty ? 'FPC customer farm' : primaryFarm,
    'crop': crop.isEmpty ? 'Finger Millet' : crop,
    'variety': variety.isEmpty ? 'Local' : variety,
    'village': village,
    'product': crop,
  };

  factory FpcFarmerProfile.fromLinkRow(Map<String, dynamic> row) {
    final source = _map(row['source_payload']);
    final currentCrop = _map(source['currentCrop'] ?? source['current_crop']);
    final last4 = _digits(
      _first([source['aadhaarLast4'], source['aadhaar_last4']]),
    );
    final providedMask = _first([
      source['aadhaarMasked'],
      source['aadhaar_masked'],
    ]);
    final maskedIdentity = providedMask.isNotEmpty
        ? providedMask
        : last4.length == 4
        ? 'XXXX XXXX $last4'
        : '';
    return FpcFarmerProfile(
      linkId: _first([row['id']]),
      farmerId: _first([
        row['farmer_id'],
        source['farmerId'],
        source['farmer_id'],
      ]),
      name: _first([
        row['farmer_name'],
        source['farmerName'],
        source['farmer_name'],
      ]),
      phone: _first([row['farmer_phone'], source['phone']]),
      village: _first([row['village'], source['village']]),
      farmId: _first([row['farm_id'], source['farmId'], source['farm_id']]),
      primaryFarm: _first([
        row['farm_name'],
        source['primaryFarm'],
        source['primary_farm'],
      ]),
      area: _first([source['area']]),
      crop: _first([row['crop'], currentCrop['crop'], source['crop']]),
      variety: _first([currentCrop['variety'], source['variety']]),
      detail: _first([source['detail']]),
      lastYield: _first([source['lastYield'], source['last_yield']]),
      lastGrade: _first([source['lastGrade'], source['last_grade']]),
      fpcRating: _first([source['fpcRating'], source['fpc_rating']]),
      kycStatus: _first([
        row['kyc_status'],
        source['verified'] == true ? 'verified' : '',
      ]),
      linkStatus: _first([row['status'], 'active']),
      maskedIdentity: maskedIdentity,
      linkedAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      currentCrop: currentCrop,
      productionHistory: _list(
        source['productionHistory'] ?? source['production_history'],
      ),
      sellingHistory: _list(
        source['sellingHistory'] ?? source['selling_history'],
      ),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static String _first(List<Object?> values) {
    for (final value in values) {
      final text = value == null ? '' : '$value'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value == null ? '' : '$value');
}
