import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _lastLatKey = 'last_location_lat';
  static const _lastLngKey = 'last_location_lng';
  static const _lastAccuracyKey = 'last_location_accuracy';

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
    if (!serviceEnabled) return getLastKnownLocation();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return getLastKnownLocation();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return getLastKnownLocation();
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final result = LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      await _saveLastKnownLocation(result);
      return result;
    } catch (_) {
      return getLastKnownLocation();
    }
  }

  Future<LocationResult?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        final result = LocationResult(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
        await _saveLastKnownLocation(result);
        return result;
      }
    } catch (_) {
      // Fall back to the app's persisted coordinates below.
    }

    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_lastLatKey);
    final lng = prefs.getDouble(_lastLngKey);
    if (lat == null || lng == null) return null;
    return LocationResult(
      latitude: lat,
      longitude: lng,
      accuracy: prefs.getDouble(_lastAccuracyKey) ?? 0,
    );
  }

  Future<void> _saveLastKnownLocation(LocationResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lastLatKey, result.latitude);
    await prefs.setDouble(_lastLngKey, result.longitude);
    await prefs.setDouble(_lastAccuracyKey, result.accuracy);
  }
}
