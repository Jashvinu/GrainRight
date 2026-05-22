import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import '../config/theme.dart';

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
  final _controller = MapController();
  late final String _apiKey;

  final _searchController = TextEditingController();
  List<_Prediction> _predictions = [];

  List<LatLng> _currentPoints = [];

  static const _initialCenter = LatLng(20.5937, 78.9629);
  static const _initialZoom = 5.0;

  @override
  void initState() {
    super.initState();
    _apiKey =
        dotenv.env['VITE_GOOGLE_MAPS_API_KEY'] ??
        dotenv.env['GOOGLE_MAPS_API_KEY'] ??
        '';

    if (widget.polygonState.value != null &&
        widget.polygonState.value!.isNotEmpty) {
      _currentPoints = widget.polygonState.value!
          .map((pt) => LatLng(pt[1], pt[0]))
          .toList();
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
      _updateState();
    });
  }

  void _undoLastPoint() {
    if (_currentPoints.isNotEmpty) {
      setState(() {
        _currentPoints.removeLast();
        _updateState();
      });
    }
  }

  void _clearPolygon() {
    setState(() {
      _currentPoints.clear();
      _updateState();
    });
  }

  void _updateState() {
    if (_currentPoints.isEmpty) {
      widget.polygonState.value = null;
    } else {
      widget.polygonState.value = _currentPoints
          .map((pt) => [pt.longitude, pt.latitude])
          .toList();
    }
  }

  Future<void> _searchPlaces(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    if (_apiKey.isEmpty) return;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$_apiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['predictions'] != null) {
          setState(() {
            _predictions = (data['predictions'] as List)
                .map((p) => _Prediction(p['place_id'], p['description']))
                .toList();
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
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=${p.placeId}&key=$_apiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final loc = data['result']['geometry']['location'];
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          _controller.move(LatLng(lat, lng), 16);
        }
      }
    } catch (e) {
      debugPrint('Details error: $e');
    }
  }

  void _zoomBy(double delta) {
    try {
      final camera = _controller.camera;
      _controller.move(camera.center, (camera.zoom + delta).clamp(3.0, 20.0));
    } catch (_) {}
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
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _currentPoints.isEmpty
                        ? _initialCenter
                        : _currentPoints.first,
                    initialZoom: _currentPoints.isEmpty ? _initialZoom : 16,
                    initialCameraFit: _currentPoints.length >= 3
                        ? CameraFit.bounds(
                            bounds: LatLngBounds.fromPoints(_currentPoints),
                            padding: const EdgeInsets.all(40),
                          )
                        : null,
                    onTap: (_, latLng) => _onMapTap(latLng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'grainright.wrkfarm',
                    ),
                    if (_currentPoints.length >= 3)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _currentPoints,
                            color: AppTheme.green.withValues(alpha: 0.22),
                            borderColor: AppTheme.green,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                    CircleLayer(
                      circles: _currentPoints
                          .map(
                            (point) => CircleMarker(
                              point: point,
                              radius: 7,
                              color: AppTheme.greenDark,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.5,
                            ),
                          )
                          .toList(),
                    ),
                  ],
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
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _searchPlaces,
                          decoration: InputDecoration(
                            hintText: 'Search location...',
                            border: InputBorder.none,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _predictions = []);
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
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
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _predictions.length,
                            itemBuilder: (context, index) {
                              final p = _predictions[index];
                              return ListTile(
                                leading: const Icon(
                                  Icons.location_on,
                                  color: Colors.grey,
                                ),
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
                        onPressed: _currentPoints.isNotEmpty
                            ? _undoLastPoint
                            : null,
                        child: Icon(
                          Icons.undo,
                          color: _currentPoints.isNotEmpty
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'clear_btn',
                        backgroundColor: Colors.white,
                        onPressed: _currentPoints.isNotEmpty
                            ? _clearPolygon
                            : null,
                        child: Icon(
                          Icons.delete_outline,
                          color: _currentPoints.isNotEmpty
                              ? Colors.red
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _MapZoomControls(
                    onZoomIn: () => _zoomBy(1),
                    onZoomOut: () => _zoomBy(-1),
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
}

class _MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
        ],
      ),
    );
  }
}
