import 'package:latlong2/latlong.dart';

class SatelliteConfig {
  static const String url = 'https://udbnskydigoqpxmmduvr.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkYm5za3lkaWdvcXB4bW1kdXZyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI3MTM2MzgsImV4cCI6MjA3ODI4OTYzOH0.asXaM2V47DiP8-Wr-Kk44Xs2INT8flGYy51Vz47NQvM';
  static const String edgeFunctionsBase = '$url/functions/v1';
  static const String restBase = '$url/rest/v1';
  static const String authBase = '$url/auth/v1';

  static const String defaultFarmId = 'df43eedf-850d-454c-9fbf-36a052be10c0';
  static final LatLng defaultCenter = const LatLng(12.3919, 77.7736);
  static const double defaultZoom = 15.0;

  static const List<String> allIndices = [
    'ndvi', 'evi', 'savi', 'msavi', 'gndvi', 'ndre', 'ndwi',
    'nitrogen', 'phosphorus', 'potassium', 'salinity', 'ph', 'moisture', 'carbon',
  ];

  static const Map<String, String> indexLabels = {
    'ndvi': 'NDVI',
    'evi': 'EVI',
    'savi': 'SAVI',
    'msavi': 'MSAVI',
    'gndvi': 'GNDVI',
    'ndre': 'NDRE',
    'ndwi': 'NDWI',
    'nitrogen': 'Nitrogen',
    'phosphorus': 'Phosphorus',
    'potassium': 'Potassium',
    'salinity': 'Salinity',
    'ph': 'Soil pH',
    'moisture': 'Moisture',
    'carbon': 'Carbon',
  };

  static const List<String> advancedAlgorithms = [
    'optram_moisture',
    'sar_moisture_change',
    'sar_moisture_fusion',
    'pca_phosphorus',
    'pca_potassium',
    'nitrogen_gndvi',
    'nitrogen_ndre',
  ];

  static const Map<String, String> algorithmLabels = {
    'optram_moisture': 'OPTRAM Soil Moisture',
    'sar_moisture_change': 'SAR Moisture Change',
    'sar_moisture_fusion': 'Fused Moisture',
    'pca_phosphorus': 'Phosphorus Index (PCA)',
    'pca_potassium': 'Potassium Index (PCA)',
    'nitrogen_gndvi': 'Nitrogen (GNDVI)',
    'nitrogen_ndre': 'Nitrogen (NDRE)',
  };

  static const Map<String, String> algorithmUnits = {
    'optram_moisture': '%',
    'sar_moisture_change': 'ΔdB',
    'sar_moisture_fusion': '%',
    'pca_phosphorus': 'Index',
    'pca_potassium': 'Index',
    'nitrogen_gndvi': 'Index',
    'nitrogen_ndre': 'Index',
  };
}
