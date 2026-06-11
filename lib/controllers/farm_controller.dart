import 'dart:math';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/auth_controller.dart';
import '../models/satellite/farm_model.dart';
import '../services/satellite_service.dart';

class FarmController extends GetxController {
  final _service = SatelliteService();

  final farms = <Farm>[].obs;
  final selectedFarm = Rxn<Farm>();
  final isLoading = false.obs;
  final hasError = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadFarms();
  }

  String get _jwt =>
      Get.isRegistered<AuthController>() ? Get.find<AuthController>().accessToken.value : '';

  Future<void> loadFarms() async {
    isLoading.value = true;
    hasError.value = false;
    try {
      final result = await _service.getFarms(_jwt);
      farms.assignAll(result);
      if (farms.isNotEmpty && selectedFarm.value == null) {
        selectedFarm.value = farms.first;
      }
    } on Exception catch (e) {
      hasError.value = true;
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void selectFarm(Farm farm) {
    selectedFarm.value = farm;
  }

  Future<bool> saveFarm({
    required String name,
    required List<LatLng> points,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final coords = points.map((p) => [p.longitude, p.latitude]).toList();
      // Close the ring
      if (coords.first[0] != coords.last[0] || coords.first[1] != coords.last[1]) {
        coords.add(List<double>.from(coords.first));
      }

      final geometry = <String, dynamic>{
        'type': 'Polygon',
        'coordinates': [coords],
      };

      // Compute rough bounding box
      double minLat = points.map((p) => p.latitude).reduce(min);
      double maxLat = points.map((p) => p.latitude).reduce(max);
      double minLng = points.map((p) => p.longitude).reduce(min);
      double maxLng = points.map((p) => p.longitude).reduce(max);

      final bounds = {
        'south': minLat,
        'north': maxLat,
        'west': minLng,
        'east': maxLng,
      };

      // Rough area estimate using shoelace formula in degrees → hectares
      final areaHa = _shoelaceAreaHectares(points);

      final userId = Get.isRegistered<AuthController>()
          ? Get.find<AuthController>().currentUser.value?.id
          : null;

      final farmJson = {
        'name': name,
        'geometry': geometry,
        'bounds': bounds,
        'area_hectares': areaHa,
        'area_acres': areaHa * 2.47105,
        'user_id': userId,
        ...metadata,
      };

      final farm = await _service.insertFarm(farmJson, _jwt);
      farms.insert(0, farm);
      selectedFarm.value = farm;
      return true;
    } catch (e) {
      Get.snackbar('Error', 'Could not save farm: $e',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  double _shoelaceAreaHectares(List<LatLng> pts) {
    if (pts.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].longitude * pts[j].latitude;
      area -= pts[j].longitude * pts[i].latitude;
    }
    area = area.abs() / 2.0;
    // Convert degrees² to m² (approx at equator) then to hectares
    const metersPerDegree = 111320.0;
    final areaM2 = area * metersPerDegree * metersPerDegree;
    return areaM2 / 10000.0;
  }
}
