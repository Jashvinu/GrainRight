import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/auth_controller.dart';
import '../models/satellite/farm_model.dart';
import '../services/satellite_service.dart';
import '../utils/polygon_geometry.dart';

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
      if (points.length < 3) {
        Get.snackbar(
          'Too few points',
          'Add at least 3 boundary points before saving the farm.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      }

      final geometry = {
        'type': 'Polygon',
        'coordinates': [PolygonGeometry.toGeoJsonRing(points)],
      };

      final bounds = PolygonGeometry.bounds(points);
      final areaHa = PolygonGeometry.areaHectares(points);

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
}
