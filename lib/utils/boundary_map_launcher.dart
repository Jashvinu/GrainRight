import 'package:get/get.dart';

import '../screens/boundary_polygon_screen.dart';

Future<List<List<double>>?> openBoundaryDrawingMap({
  List<List<double>>? initialPolygon,
}) async {
  return Get.to<List<List<double>>>(
    () => BoundaryPolygonScreen(initialPolygon: initialPolygon),
  );
}
