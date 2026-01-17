import 'package:hive/hive.dart';

part 'range_point.g.dart';

/// A single range measurement point from LoRaWAN uplink.
/// Matches the backend WebSocket JSON format exactly.
@HiveType(typeId: 0)
class RangePoint extends HiveObject {
  @HiveField(0)
  final DateTime timestamp;

  @HiveField(1)
  final String deviceEui;

  @HiveField(2)
  final int frameCount;

  // GPS Data
  @HiveField(3)
  final double latitude;

  @HiveField(4)
  final double longitude;

  @HiveField(5)
  final int altitude;

  @HiveField(6)
  final int fixQuality;

  @HiveField(7)
  final double hdop;

  @HiveField(8)
  final int satellites;

  // LoRaWAN Metadata
  @HiveField(9)
  final double rssi;

  @HiveField(10)
  final double snr;

  @HiveField(11)
  final int spreadingFactor;

  @HiveField(12)
  final double frequency;

  // Gateway Info (optional)
  @HiveField(13)
  final String? gatewayId;

  @HiveField(14)
  final double? gatewayLat;

  @HiveField(15)
  final double? gatewayLon;

  @HiveField(16)
  final double? distance;

  // Session reference (for querying points by session)
  @HiveField(17)
  final String? sessionId;

  RangePoint({
    required this.timestamp,
    required this.deviceEui,
    required this.frameCount,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.fixQuality,
    required this.hdop,
    required this.satellites,
    required this.rssi,
    required this.snr,
    required this.spreadingFactor,
    required this.frequency,
    this.gatewayId,
    this.gatewayLat,
    this.gatewayLon,
    this.distance,
    this.sessionId,
  });

  /// Create from backend WebSocket JSON message
  factory RangePoint.fromJson(Map<String, dynamic> json, {String? sessionId}) {
    return RangePoint(
      timestamp: DateTime.parse(json['timestamp'] as String),
      deviceEui: json['device_eui'] as String,
      frameCount: json['frame_count'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: json['altitude'] as int,
      fixQuality: json['fix_quality'] as int,
      hdop: (json['hdop'] as num).toDouble(),
      satellites: json['satellites'] as int,
      rssi: (json['rssi'] as num).toDouble(),
      snr: (json['snr'] as num).toDouble(),
      spreadingFactor: json['spreading_factor'] as int,
      frequency: (json['frequency'] as num).toDouble(),
      gatewayId: json['gateway_id'] as String?,
      gatewayLat: (json['gateway_lat'] as num?)?.toDouble(),
      gatewayLon: (json['gateway_lon'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      sessionId: sessionId,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'device_eui': deviceEui,
      'frame_count': frameCount,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'fix_quality': fixQuality,
      'hdop': hdop,
      'satellites': satellites,
      'rssi': rssi,
      'snr': snr,
      'spreading_factor': spreadingFactor,
      'frequency': frequency,
      'gateway_id': gatewayId,
      'gateway_lat': gatewayLat,
      'gateway_lon': gatewayLon,
      'distance': distance,
    };
  }

  /// Convert to GeoJSON Feature for export
  Map<String, dynamic> toGeoJsonFeature() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude, altitude],
      },
      'properties': {
        'timestamp': timestamp.toIso8601String(),
        'device_eui': deviceEui,
        'frame_count': frameCount,
        'rssi': rssi,
        'snr': snr,
        'spreading_factor': spreadingFactor,
        'frequency': frequency,
        'distance': distance,
        'fix_quality': fixQuality,
        'hdop': hdop,
        'satellites': satellites,
      },
    };
  }

  /// Signal quality category (0-4 based on RSSI)
  /// 4 = Excellent, 3 = Good, 2 = Fair, 1 = Poor, 0 = Very Poor
  int get signalQuality {
    if (rssi > -80) return 4; // Excellent
    if (rssi > -100) return 3; // Good
    if (rssi > -110) return 2; // Fair
    if (rssi > -120) return 1; // Poor
    return 0; // Very poor
  }

  /// Human-readable signal quality string
  String get signalQualityText {
    switch (signalQuality) {
      case 4:
        return 'Excellent';
      case 3:
        return 'Good';
      case 2:
        return 'Fair';
      case 1:
        return 'Poor';
      default:
        return 'Very Poor';
    }
  }

  /// Check if this point has valid GPS coordinates
  bool get hasValidGps => fixQuality > 0 && latitude != 0 && longitude != 0;

  /// Check if gateway location is available
  bool get hasGatewayLocation => gatewayLat != null && gatewayLon != null;

  /// Unique key for Hive storage
  String get storageKey => '${sessionId ?? 'live'}_${timestamp.millisecondsSinceEpoch}';

  @override
  String toString() {
    return 'RangePoint(lat: $latitude, lon: $longitude, rssi: $rssi, snr: $snr, distance: $distance)';
  }
}
