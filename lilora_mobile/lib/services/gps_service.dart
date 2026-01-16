import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gps_data.dart';
import '../utils/nmea_formatter.dart';

/// Service for streaming GPS coordinates and generating NMEA sentences
class GpsService extends ChangeNotifier {
  StreamSubscription<Position>? _positionSubscription;
  GpsData? _lastPosition;
  String? _lastNmeaSentence;
  bool _isTracking = false;
  String _statusMessage = 'Idle';

  GpsData? get lastPosition => _lastPosition;
  String? get lastNmeaSentence => _lastNmeaSentence;
  bool get isTracking => _isTracking;
  String get statusMessage => _statusMessage;

  /// Location settings for high-accuracy GPS
  LocationSettings get _locationSettings => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // Update every 1 meter of movement
      );

  /// Start tracking GPS position
  Future<void> startTracking() async {
    if (_isTracking) return;

    _statusMessage = 'Starting GPS...';
    notifyListeners();

    try {
      // Check if location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _statusMessage = 'Location service disabled';
        notifyListeners();
        return;
      }

      // Check permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _statusMessage = 'Permission denied';
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _statusMessage = 'Permission permanently denied';
        notifyListeners();
        return;
      }

      // Start position stream
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        _onPositionUpdate,
        onError: _onError,
      );

      _isTracking = true;
      _statusMessage = 'Waiting for GPS fix...';
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Error: $e';
      notifyListeners();
    }
  }

  /// Stop tracking GPS position
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _statusMessage = 'Stopped';
    notifyListeners();
  }

  /// Handle position update
  void _onPositionUpdate(Position position) {
    _lastPosition = GpsData(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    );

    // Generate NMEA sentence
    _lastNmeaSentence = NmeaFormatter.formatGGA(_lastPosition!);

    _statusMessage = 'GPS Active';
    notifyListeners();
  }

  /// Handle GPS error
  void _onError(dynamic error) {
    _statusMessage = 'GPS Error: $error';
    notifyListeners();
  }

  /// Get current position once (for testing)
  Future<GpsData?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return GpsData(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );
    } catch (e) {
      debugPrint('Error getting position: $e');
      return null;
    }
  }

  /// Generate NMEA GGA sentence from current position
  String? generateNmeaGGA() {
    if (_lastPosition == null) return null;
    return NmeaFormatter.formatGGA(_lastPosition!);
  }

  /// Generate NMEA RMC sentence from current position
  String? generateNmeaRMC() {
    if (_lastPosition == null) return null;
    return NmeaFormatter.formatRMC(_lastPosition!);
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
