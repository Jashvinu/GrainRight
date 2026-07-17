class StakeholderLandRecordDetails {
  static const surveyGatLabel = 'Survey/Gat number';
  static const subDivisionLabel = 'Sub-division number';
  static const villageLabel = 'Village';
  static const talukaLabel = 'Taluka';
  static const districtLabel = 'District';
  static const ownerNameLabel = 'Owner name on 7/12';
  static const landAreaLabel = 'Land area';
  static const cultivableAreaLabel = 'Cultivable area';
  static const khataNumberLabel = 'Khata number';
  static const cropOrUseLabel = 'Crop/land use';
  static const irrigationSourceLabel = 'Irrigation source';
  static const mutationEntryLabel = 'Mutation entry number';
  static const landRevenueLabel = 'Land revenue';
  static const otherRightsLabel = 'Other rights/encumbrance';

  final String surveyGatNumber;
  final String subDivisionNumber;
  final String village;
  final String taluka;
  final String district;
  final String ownerName;
  final String landArea;
  final String cultivableArea;
  final String khataNumber;
  final String cropOrUse;
  final String irrigationSource;
  final String mutationEntryNumber;
  final String landRevenue;
  final String otherRights;
  final String legacyDetails;

  const StakeholderLandRecordDetails({
    this.surveyGatNumber = '',
    this.subDivisionNumber = '',
    this.village = '',
    this.taluka = '',
    this.district = '',
    this.ownerName = '',
    this.landArea = '',
    this.cultivableArea = '',
    this.khataNumber = '',
    this.cropOrUse = '',
    this.irrigationSource = '',
    this.mutationEntryNumber = '',
    this.landRevenue = '',
    this.otherRights = '',
    this.legacyDetails = '',
  });

  factory StakeholderLandRecordDetails.fromSummary(String value) {
    final fields = <_LandRecordField, String>{};
    final looseLines = <String>[];
    for (final rawLine in value.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separatorIndex = line.indexOf(':');
      if (separatorIndex <= 0) {
        looseLines.add(line);
        continue;
      }
      final field = _fieldForLabel(line.substring(0, separatorIndex));
      final fieldValue = line.substring(separatorIndex + 1).trim();
      if (field == null || fieldValue.isEmpty) {
        looseLines.add(line);
        continue;
      }
      fields[field] = fieldValue;
    }

    return StakeholderLandRecordDetails(
      surveyGatNumber: fields[_LandRecordField.surveyGatNumber] ?? '',
      subDivisionNumber: fields[_LandRecordField.subDivisionNumber] ?? '',
      village: fields[_LandRecordField.village] ?? '',
      taluka: fields[_LandRecordField.taluka] ?? '',
      district: fields[_LandRecordField.district] ?? '',
      ownerName: fields[_LandRecordField.ownerName] ?? '',
      landArea: fields[_LandRecordField.landArea] ?? '',
      cultivableArea: fields[_LandRecordField.cultivableArea] ?? '',
      khataNumber: fields[_LandRecordField.khataNumber] ?? '',
      cropOrUse: fields[_LandRecordField.cropOrUse] ?? '',
      irrigationSource: fields[_LandRecordField.irrigationSource] ?? '',
      mutationEntryNumber: fields[_LandRecordField.mutationEntryNumber] ?? '',
      landRevenue: fields[_LandRecordField.landRevenue] ?? '',
      otherRights: fields[_LandRecordField.otherRights] ?? '',
      legacyDetails: looseLines.join('\n'),
    );
  }

  bool get hasRequiredManualDetails =>
      surveyGatNumber.trim().isNotEmpty &&
      village.trim().length >= 2 &&
      taluka.trim().length >= 2 &&
      district.trim().length >= 2 &&
      ownerName.trim().length >= 2 &&
      landArea.trim().isNotEmpty;

  bool get hasAnySpecificDetails =>
      surveyGatNumber.trim().isNotEmpty ||
      subDivisionNumber.trim().isNotEmpty ||
      village.trim().isNotEmpty ||
      taluka.trim().isNotEmpty ||
      district.trim().isNotEmpty ||
      ownerName.trim().isNotEmpty ||
      landArea.trim().isNotEmpty ||
      cultivableArea.trim().isNotEmpty ||
      khataNumber.trim().isNotEmpty ||
      cropOrUse.trim().isNotEmpty ||
      irrigationSource.trim().isNotEmpty ||
      mutationEntryNumber.trim().isNotEmpty ||
      landRevenue.trim().isNotEmpty ||
      otherRights.trim().isNotEmpty;

  String get summary {
    final lines = <String>[];
    void add(String label, String value) {
      final clean = value.trim();
      if (clean.isNotEmpty) lines.add('$label: $clean');
    }

    add(surveyGatLabel, surveyGatNumber);
    add(subDivisionLabel, subDivisionNumber);
    add(villageLabel, village);
    add(talukaLabel, taluka);
    add(districtLabel, district);
    add(ownerNameLabel, ownerName);
    add(landAreaLabel, landArea);
    add(cultivableAreaLabel, cultivableArea);
    add(khataNumberLabel, khataNumber);
    add(cropOrUseLabel, cropOrUse);
    add(irrigationSourceLabel, irrigationSource);
    add(mutationEntryLabel, mutationEntryNumber);
    add(landRevenueLabel, landRevenue);
    add(otherRightsLabel, otherRights);
    if (lines.isEmpty) return legacyDetails.trim();
    return lines.join('\n');
  }

  String get compactLabel {
    if (!hasAnySpecificDetails) return legacyDetails.trim();
    final parts = <String>[
      if (surveyGatNumber.trim().isNotEmpty)
        'Survey/Gat ${surveyGatNumber.trim()}',
      if (village.trim().isNotEmpty) village.trim(),
      if (landArea.trim().isNotEmpty) landArea.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' - ');
    return summary.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isCompleteSummary(String value) {
    return StakeholderLandRecordDetails.fromSummary(
      value,
    ).hasRequiredManualDetails;
  }

  static _LandRecordField? _fieldForLabel(String label) {
    switch (label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')) {
      case 'surveygatnumber':
      case 'surveygat':
      case 'surveynumber':
      case 'gatnumber':
      case 'gatno':
      case 'surveyno':
        return _LandRecordField.surveyGatNumber;
      case 'subdivisionnumber':
      case 'subdivision':
      case 'hissanumber':
      case 'hissano':
      case 'subdivisionno':
        return _LandRecordField.subDivisionNumber;
      case 'village':
        return _LandRecordField.village;
      case 'taluka':
      case 'tehsil':
        return _LandRecordField.taluka;
      case 'district':
        return _LandRecordField.district;
      case 'ownernameon712':
      case 'ownername':
      case 'landowner':
        return _LandRecordField.ownerName;
      case 'landarea':
      case 'area':
      case 'totalarea':
      case 'totalholding':
        return _LandRecordField.landArea;
      case 'cultivablearea':
      case 'cultivatedarea':
      case 'potkharabarea':
      case 'noncultivablearea':
        return _LandRecordField.cultivableArea;
      case 'khatanumber':
      case 'khatano':
      case 'accountnumber':
      case 'accountno':
        return _LandRecordField.khataNumber;
      case 'croplanduse':
      case 'crop':
      case 'landuse':
        return _LandRecordField.cropOrUse;
      case 'irrigationsource':
      case 'irrigation':
      case 'watersource':
        return _LandRecordField.irrigationSource;
      case 'mutationentrynumber':
      case 'mutationentry':
      case 'mutationnumber':
      case 'ferfarnumber':
      case 'ferfarno':
        return _LandRecordField.mutationEntryNumber;
      case 'landrevenue':
      case 'revenue':
      case 'assessment':
        return _LandRecordField.landRevenue;
      case 'otherrightsencumbrance':
      case 'otherrights':
      case 'encumbrance':
      case 'loancharge':
      case 'boja':
        return _LandRecordField.otherRights;
    }
    return null;
  }
}

enum _LandRecordField {
  surveyGatNumber,
  subDivisionNumber,
  village,
  taluka,
  district,
  ownerName,
  landArea,
  cultivableArea,
  khataNumber,
  cropOrUse,
  irrigationSource,
  mutationEntryNumber,
  landRevenue,
  otherRights,
}
