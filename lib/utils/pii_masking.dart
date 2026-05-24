String maskAadhaar(String? value) {
  final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.isEmpty) return '';
  final visible = digits.length <= 4
      ? digits
      : digits.substring(digits.length - 4);
  return 'XXXX XXXX $visible';
}

Map<String, dynamic> sanitizeSurveyForSheet(Map<String, dynamic> surveyData) {
  final out = Map<String, dynamic>.from(surveyData);

  void alias(
    String from,
    String to, {
    Object? Function(Object? value)? convert,
  }) {
    if (!out.containsKey(to) && out.containsKey(from)) {
      final value = out[from];
      out[to] = convert == null ? value : convert(value);
    }
  }

  alias('_id', 'id');
  alias(
    'aadhaar_number',
    'aadhar_no',
    convert: (value) => maskAadhaar(value?.toString()),
  );
  alias('mobile_number', 'mobile_no');
  alias('education', 'education_level');
  alias('village', 'village_gp');
  alias('taluka', 'block');
  alias('total_land_area_acre', 'land_owned');
  alias('leased_land_acre', 'land_leased');
  alias('rain_based_area_acre', 'total_rainfed_land');
  alias('irrigated_land_acre', 'total_irrigated_land');
  alias('main_crop_land_acre', 'land_under_millet');
  alias('other_crop_land_acre', 'land_under_other_crops');
  alias('non_agri_income', 'annual_non_agri_income');
  alias('income_sources', 'sources_of_income');
  alias('location_lat', 'form_latitude');
  alias('location_lng', 'form_longitude');
  alias('location_accuracy_m', 'form_location_accuracy');
  alias('started_at', 'form_started_at');

  if (out.containsKey('aadhaar_number')) {
    out['aadhaar_number'] = maskAadhaar(out['aadhaar_number']?.toString());
  }
  if (out.containsKey('aadhar_no')) {
    out['aadhar_no'] = maskAadhaar(out['aadhar_no']?.toString());
  }

  final extra = out['extra_details'];
  if (extra is Map) {
    final milletAreas = extra['millet_land_areas'];
    if (milletAreas != null && !out.containsKey('millet_land_areas')) {
      out['millet_land_areas'] = milletAreas;
    }
    final otherCropDetails = extra['other_crop_details'];
    if (otherCropDetails != null && !out.containsKey('other_crop_details')) {
      out['other_crop_details'] = otherCropDetails;
    }
    final croppingPattern = extra['cropping_pattern'];
    if (croppingPattern is Map) {
      final disease = croppingPattern['disease'];
      if (disease is Map) {
        for (final key in _diseaseSheetFields) {
          final value = disease[key];
          if (value != null && !out.containsKey(key)) {
            out[key] = value;
          }
        }
      }
    }
  }

  return out;
}

const _diseaseSheetFields = {
  'disease_present',
  'disease_name',
  'affected_crop',
  'disease_severity',
  'symptoms_observed',
  'treatment_taken',
};
