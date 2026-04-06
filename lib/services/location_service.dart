import 'package:geolocator/geolocator.dart';

enum LocationStatus { idle, fetching, acquired, denied, unavailable }

class LocationResult {
  final double latitude;
  final double longitude;
  final double accuracy;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

class LocationService {
  /// Returns true if location permission is granted (not denied forever).
  Future<bool> getPermissionStatus() async {
    final p = await Geolocator.checkPermission();
    return p != LocationPermission.denied &&
        p != LocationPermission.deniedForever;
  }

  /// Requests permission and returns the current position.
  /// Returns null if permission is denied or GPS is unavailable.
  Future<LocationResult?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      return null;
    }
  }
}
