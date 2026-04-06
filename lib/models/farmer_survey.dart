class FarmerSurvey {
  final String? id;
  final String? surveyDate;
  final String? season;
  final String? farmerName;
  final String? gender;
  final String? dateOfBirth;
  final String? category;
  final String? educationLevel;
  final String? villageGp;
  final String? block;
  final String? district;
  final String? fpcName;
  final String? aadharNo;
  final String? mobileNo;

  // Landholding
  final double? landOwned;
  final double? landLeased;
  final double? totalRainfedLand;
  final double? totalIrrigatedLand;

  // Cropping Pattern
  final double? landUnderMillet;
  final double? landUnderOtherCrops;
  final double? croppingIntensity;
  final String? majorCropsGrown;
  final List<String>? milletSeedType;
  final String? milletSeedVariety;

  // Input Usage
  final double? seedUsedKgPerAcre;
  final double? fertilizerUsedKgPerAcre;
  final double? pesticideUsedLitresPerAcre;
  final bool? useBioFertilizer;
  final bool? accessToCredit;
  final bool? accessToExtensionServices;
  final String? mechanizationAccess;

  // Production & Productivity
  final double? milletProductivity;
  final double? otherCropsProductivity;
  final double? totalMilletProduction;
  final double? quantityMilletSold;
  final double? quantityHomeConsumption;
  final double? quantityUsedAsSeed;
  final double? avgMilletSellingPrice;

  // Post-Harvest & Marketing
  final String? postHarvestPractices;
  final String? whereProduceSold;
  final bool? trainingReceived;
  final String? trainingSource;

  // Cost & Income
  final double? avgCostCultivationMillets;
  final double? netIncomeMillets;
  final double? avgCostCultivationOther;
  final double? netIncomeOtherCrops;
  final String? sourcesOfIncome;
  final double? annualAgriIncome;
  final double? annualNonAgriIncome;
  final double? totalAnnualIncome;

  final String? createdAt;
  final String? updatedAt;

  FarmerSurvey({
    this.id,
    this.surveyDate,
    this.season,
    this.farmerName,
    this.gender,
    this.dateOfBirth,
    this.category,
    this.educationLevel,
    this.villageGp,
    this.block,
    this.district,
    this.fpcName,
    this.aadharNo,
    this.mobileNo,
    this.landOwned,
    this.landLeased,
    this.totalRainfedLand,
    this.totalIrrigatedLand,
    this.landUnderMillet,
    this.landUnderOtherCrops,
    this.croppingIntensity,
    this.majorCropsGrown,
    this.milletSeedType,
    this.milletSeedVariety,
    this.seedUsedKgPerAcre,
    this.fertilizerUsedKgPerAcre,
    this.pesticideUsedLitresPerAcre,
    this.useBioFertilizer,
    this.accessToCredit,
    this.accessToExtensionServices,
    this.mechanizationAccess,
    this.milletProductivity,
    this.otherCropsProductivity,
    this.totalMilletProduction,
    this.quantityMilletSold,
    this.quantityHomeConsumption,
    this.quantityUsedAsSeed,
    this.avgMilletSellingPrice,
    this.postHarvestPractices,
    this.whereProduceSold,
    this.trainingReceived,
    this.trainingSource,
    this.avgCostCultivationMillets,
    this.netIncomeMillets,
    this.avgCostCultivationOther,
    this.netIncomeOtherCrops,
    this.sourcesOfIncome,
    this.annualAgriIncome,
    this.annualNonAgriIncome,
    this.totalAnnualIncome,
    this.createdAt,
    this.updatedAt,
  });

  factory FarmerSurvey.fromJson(Map<String, dynamic> json) {
    return FarmerSurvey(
      id: json['id'] as String?,
      surveyDate: json['survey_date'] as String?,
      season: json['season'] as String?,
      farmerName: json['farmer_name'] as String?,
      gender: json['gender'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      category: json['category'] as String?,
      educationLevel: json['education_level'] as String?,
      villageGp: json['village_gp'] as String?,
      block: json['block'] as String?,
      district: json['district'] as String?,
      fpcName: json['fpc_name'] as String?,
      aadharNo: json['aadhar_no'] as String?,
      mobileNo: json['mobile_no'] as String?,
      landOwned: _toDouble(json['land_owned']),
      landLeased: _toDouble(json['land_leased']),
      totalRainfedLand: _toDouble(json['total_rainfed_land']),
      totalIrrigatedLand: _toDouble(json['total_irrigated_land']),
      landUnderMillet: _toDouble(json['land_under_millet']),
      landUnderOtherCrops: _toDouble(json['land_under_other_crops']),
      croppingIntensity: _toDouble(json['cropping_intensity']),
      majorCropsGrown: json['major_crops_grown'] as String?,
      milletSeedType: (json['millet_seed_type'] as List?)?.map((e) => e.toString()).toList(),
      milletSeedVariety: json['millet_seed_variety'] as String?,
      seedUsedKgPerAcre: _toDouble(json['seed_used_kg_per_acre']),
      fertilizerUsedKgPerAcre: _toDouble(json['fertilizer_used_kg_per_acre']),
      pesticideUsedLitresPerAcre:
          _toDouble(json['pesticide_used_litres_per_acre']),
      useBioFertilizer: json['use_bio_fertilizer'] as bool?,
      accessToCredit: json['access_to_credit'] as bool?,
      accessToExtensionServices:
          json['access_to_extension_services'] as bool?,
      mechanizationAccess: json['mechanization_access'] as String?,
      milletProductivity: _toDouble(json['millet_productivity']),
      otherCropsProductivity: _toDouble(json['other_crops_productivity']),
      totalMilletProduction: _toDouble(json['total_millet_production']),
      quantityMilletSold: _toDouble(json['quantity_millet_sold']),
      quantityHomeConsumption: _toDouble(json['quantity_home_consumption']),
      quantityUsedAsSeed: _toDouble(json['quantity_used_as_seed']),
      avgMilletSellingPrice: _toDouble(json['avg_millet_selling_price']),
      postHarvestPractices: json['post_harvest_practices'] as String?,
      whereProduceSold: json['where_produce_sold'] as String?,
      trainingReceived: json['training_received'] as bool?,
      trainingSource: json['training_source'] as String?,
      avgCostCultivationMillets:
          _toDouble(json['avg_cost_cultivation_millets']),
      netIncomeMillets: _toDouble(json['net_income_millets']),
      avgCostCultivationOther:
          _toDouble(json['avg_cost_cultivation_other']),
      netIncomeOtherCrops: _toDouble(json['net_income_other_crops']),
      sourcesOfIncome: json['sources_of_income'] as String?,
      annualAgriIncome: _toDouble(json['annual_agri_income']),
      annualNonAgriIncome: _toDouble(json['annual_non_agri_income']),
      totalAnnualIncome: _toDouble(json['total_annual_income']),
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (surveyDate != null) map['survey_date'] = surveyDate;
    if (season != null) map['season'] = season;
    if (farmerName != null) map['farmer_name'] = farmerName;
    if (gender != null) map['gender'] = gender;
    if (dateOfBirth != null) map['date_of_birth'] = dateOfBirth;
    if (category != null) map['category'] = category;
    if (educationLevel != null) map['education_level'] = educationLevel;
    if (villageGp != null) map['village_gp'] = villageGp;
    if (block != null) map['block'] = block;
    if (district != null) map['district'] = district;
    if (fpcName != null) map['fpc_name'] = fpcName;
    if (aadharNo != null) map['aadhar_no'] = aadharNo;
    if (mobileNo != null) map['mobile_no'] = mobileNo;
    if (landOwned != null) map['land_owned'] = landOwned;
    if (landLeased != null) map['land_leased'] = landLeased;
    if (totalRainfedLand != null) map['total_rainfed_land'] = totalRainfedLand;
    if (totalIrrigatedLand != null) map['total_irrigated_land'] = totalIrrigatedLand;
    if (landUnderMillet != null) map['land_under_millet'] = landUnderMillet;
    if (landUnderOtherCrops != null) map['land_under_other_crops'] = landUnderOtherCrops;
    if (croppingIntensity != null) map['cropping_intensity'] = croppingIntensity;
    if (majorCropsGrown != null) map['major_crops_grown'] = majorCropsGrown;
    if (milletSeedType != null) map['millet_seed_type'] = milletSeedType;
    if (milletSeedVariety != null) map['millet_seed_variety'] = milletSeedVariety;
    if (seedUsedKgPerAcre != null) map['seed_used_kg_per_acre'] = seedUsedKgPerAcre;
    if (fertilizerUsedKgPerAcre != null) map['fertilizer_used_kg_per_acre'] = fertilizerUsedKgPerAcre;
    if (pesticideUsedLitresPerAcre != null) map['pesticide_used_litres_per_acre'] = pesticideUsedLitresPerAcre;
    if (useBioFertilizer != null) map['use_bio_fertilizer'] = useBioFertilizer;
    if (accessToCredit != null) map['access_to_credit'] = accessToCredit;
    if (accessToExtensionServices != null) map['access_to_extension_services'] = accessToExtensionServices;
    if (mechanizationAccess != null) map['mechanization_access'] = mechanizationAccess;
    if (milletProductivity != null) map['millet_productivity'] = milletProductivity;
    if (otherCropsProductivity != null) map['other_crops_productivity'] = otherCropsProductivity;
    if (totalMilletProduction != null) map['total_millet_production'] = totalMilletProduction;
    if (quantityMilletSold != null) map['quantity_millet_sold'] = quantityMilletSold;
    if (quantityHomeConsumption != null) map['quantity_home_consumption'] = quantityHomeConsumption;
    if (quantityUsedAsSeed != null) map['quantity_used_as_seed'] = quantityUsedAsSeed;
    if (avgMilletSellingPrice != null) map['avg_millet_selling_price'] = avgMilletSellingPrice;
    if (postHarvestPractices != null) map['post_harvest_practices'] = postHarvestPractices;
    if (whereProduceSold != null) map['where_produce_sold'] = whereProduceSold;
    if (trainingReceived != null) map['training_received'] = trainingReceived;
    if (trainingSource != null) map['training_source'] = trainingSource;
    if (avgCostCultivationMillets != null) map['avg_cost_cultivation_millets'] = avgCostCultivationMillets;
    if (netIncomeMillets != null) map['net_income_millets'] = netIncomeMillets;
    if (avgCostCultivationOther != null) map['avg_cost_cultivation_other'] = avgCostCultivationOther;
    if (netIncomeOtherCrops != null) map['net_income_other_crops'] = netIncomeOtherCrops;
    if (sourcesOfIncome != null) map['sources_of_income'] = sourcesOfIncome;
    if (annualAgriIncome != null) map['annual_agri_income'] = annualAgriIncome;
    if (annualNonAgriIncome != null) map['annual_non_agri_income'] = annualNonAgriIncome;
    if (totalAnnualIncome != null) map['total_annual_income'] = totalAnnualIncome;
    return map;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
