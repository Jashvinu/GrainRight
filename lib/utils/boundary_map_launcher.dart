import 'package:get/get.dart';

import '../screens/pencil_polygon_screen.dart';

Future<List<List<double>>?> openBoundaryDrawingMap({
  List<List<double>>? initialPolygon,
}) async {
  return Get.to<List<List<double>>>(
    () => PencilPolygonScreen(initialPolygon: initialPolygon),
  );
}
