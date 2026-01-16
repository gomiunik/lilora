/// GPS data model for LiLoRa mobile app
class GpsData {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final int satellites;

  GpsData({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
    this.satellites = 0,
  });

  /// Check if GPS data is valid (has reasonable accuracy)
  bool get isValid => accuracy < 50.0; // Less than 50m accuracy

  /// Get fix quality (simplified from NMEA standard)
  int get fixQuality {
    if (accuracy > 50) return 0; // No fix
    if (accuracy < 10) return 2; // DGPS quality
    return 1; // GPS fix
  }

  /// Estimated satellite count based on accuracy
  /// Real satellite count not available from Geolocator
  int get estimatedSatellites {
    if (satellites > 0) return satellites;
    if (accuracy < 5) return 12;
    if (accuracy < 10) return 10;
    if (accuracy < 20) return 8;
    if (accuracy < 50) return 5;
    return 0;
  }

  /// HDOP estimate based on accuracy
  double get hdop {
    // HDOP * 5 meters roughly equals horizontal accuracy
    return (accuracy / 5.0).clamp(0.5, 25.5);
  }

  @override
  String toString() {
    return 'GpsData(lat: ${latitude.toStringAsFixed(6)}, '
        'lon: ${longitude.toStringAsFixed(6)}, '
        'alt: ${altitude.toStringAsFixed(1)}m, '
        'acc: ${accuracy.toStringAsFixed(1)}m)';
  }
}
