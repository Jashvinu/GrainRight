import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PolygonMapField extends StatefulWidget {
  final String label;
  final bool hasError;
  final Rxn<List<List<double>>> polygonState;

  const PolygonMapField({
    super.key,
    required this.label,
    this.hasError = false,
    required this.polygonState,
  });

  @override
  State<PolygonMapField> createState() => _PolygonMapFieldState();
}

class _Prediction {
  final String placeId;
  final String description;
  _Prediction(this.placeId, this.description);
}

class _PolygonMapFieldState extends State<PolygonMapField> {
  final Completer<GoogleMapController> _controller = Completer();
  late final String _apiKey;
  
  final _searchController = TextEditingController();
  List<_Prediction> _predictions = [];

  final Set<Polygon> _polygons = {};
  List<LatLng> _currentPoints = [];

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(20.5937, 78.9629),
    zoom: 5.0,
  );

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.env['VITE_GOOGLE_MAPS_API_KEY'] ?? dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    if (widget.polygonState.value != null && widget.polygonState.value!.isNotEmpty) {
      _currentPoints = widget.polygonState.value!.map((pt) => LatLng(pt[1], pt[0])).toList();
      _updatePolygons();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _currentPoints.add(position);
      _updatePolygons();
    });
  }

  void _updatePolygons() {
    _polygons.clear();
    if (_currentPoints.isNotEmpty) {
      _polygons.add(
        Polygon(
          polygonId: const PolygonId('farm_polygon'),
          points: _currentPoints,
          strokeWidth: 3,
          strokeColor: Colors.blue,
          fillColor: Colors.blue.withValues(alpha: 0.2),
        ),
      );
    }
    _updateState();
  }

  void _undoLastPoint() {
    if (_currentPoints.isNotEmpty) {
      setState(() {
        _currentPoints.removeLast();
        _updatePolygons();
      });
    }
  }

  void _clearPolygon() {
    setState(() {
      _currentPoints.clear();
      _updatePolygons();
    });
  }

  void _updateState() {
    if (_currentPoints.isEmpty) {
      widget.polygonState.value = null;
    } else {
      widget.polygonState.value = _currentPoints.map((pt) => [pt.longitude, pt.latitude]).toList();
    }
  }

  Future<void> _searchPlaces(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    if (_apiKey.isEmpty) return;

    try {
      final url = Uri.parse('https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$_apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          setState(() {
            _predictions = (data['predictions'] as List).map((p) => _Prediction(p['place_id'], p['description'])).toList();
          });
        } else {
          setState(() => _predictions = []);
        }
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  Future<void> _goToPlace(_Prediction p) async {
    setState(() {
      _predictions = [];
      _searchController.text = p.description;
    });
    FocusScope.of(context).unfocus();

    try {
      final url = Uri.parse('https://maps.googleapis.com/maps/api/place/details/json?place_id=${p.placeId}&key=$_apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final loc = data['result']['geometry']['location'];
          final lat = loc['lat'];
          final lng = loc['lng'];
          
          final GoogleMapController controller = await _controller.future;
          controller.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(lat, lng), zoom: 16),
          ));
        }
      }
    } catch (e) {
      debugPrint('Details error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Container(
          height: 400,
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.hasError ? Colors.red : Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                GoogleMap(
                  mapType: MapType.satellite,
                  initialCameraPosition: _initialPosition,
                  polygons: _polygons,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                    // If we already have points, center the camera around them
                    if (_currentPoints.isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        controller.animateCamera(CameraUpdate.newLatLngBounds(
                          _getBounds(_currentPoints), 50,
                        ));
                      });
                    }
                  },
                  onTap: _onMapTap,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                
                // Search Bar Overlay
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _searchPlaces,
                          decoration: InputDecoration(
                            hintText: 'Search location...',
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _predictions = []);
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      if (_predictions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _predictions.length,
                            itemBuilder: (context, index) {
                              final p = _predictions[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on, color: Colors.grey),
                                title: Text(p.description),
                                onTap: () => _goToPlace(p),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Controls Overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'undo_btn',
                        backgroundColor: Colors.white,
                        onPressed: _currentPoints.isNotEmpty ? _undoLastPoint : null,
                        child: Icon(Icons.undo, color: _currentPoints.isNotEmpty ? Colors.black87 : Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'clear_btn',
                        backgroundColor: Colors.white,
                        onPressed: _currentPoints.isNotEmpty ? _clearPolygon : null,
                        child: Icon(Icons.delete_outline, color: _currentPoints.isNotEmpty ? Colors.red : Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.hasError)
          const Padding(
            padding: EdgeInsets.only(top: 8.0, left: 12.0),
            child: Text(
              'Location matching farm is required',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
