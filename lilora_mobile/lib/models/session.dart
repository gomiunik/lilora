import 'package:hive/hive.dart';

part 'session.g.dart';

/// A recording session containing multiple range points.
/// Sessions track statistics as points are added.
@HiveType(typeId: 1)
class Session extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  final DateTime startTime;

  @HiveField(3)
  DateTime? endTime;

  @HiveField(4)
  String? deviceEui;

  @HiveField(5)
  String? notes;

  // Statistics (updated as points are added)
  @HiveField(6)
  int pointCount;

  @HiveField(7)
  double? maxDistance;

  @HiveField(8)
  double? minRssi;

  @HiveField(9)
  double? maxRssi;

  @HiveField(10)
  double? avgRssi;

  @HiveField(11)
  double? minSnr;

  @HiveField(12)
  double? maxSnr;

  @HiveField(13)
  double? avgSnr;

  // Running sum for calculating averages
  @HiveField(14)
  double _rssiSum;

  @HiveField(15)
  double _snrSum;

  Session({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.deviceEui,
    this.notes,
    this.pointCount = 0,
    this.maxDistance,
    this.minRssi,
    this.maxRssi,
    this.avgRssi,
    this.minSnr,
    this.maxSnr,
    this.avgSnr,
    double rssiSum = 0,
    double snrSum = 0,
  })  : _rssiSum = rssiSum,
        _snrSum = snrSum;

  /// Whether the session is currently being recorded
  bool get isActive => endTime == null;

  /// Duration of the session
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// Human-readable duration string
  String get durationText {
    final d = duration;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  /// Update statistics when a new point is added
  void updateStats({
    required double rssi,
    required double snr,
    double? distance,
    String? deviceEui,
  }) {
    pointCount++;

    // Track device EUI from first point
    if (this.deviceEui == null && deviceEui != null) {
      this.deviceEui = deviceEui;
    }

    // Update RSSI statistics
    _rssiSum += rssi;
    minRssi = minRssi == null ? rssi : (rssi < minRssi! ? rssi : minRssi);
    maxRssi = maxRssi == null ? rssi : (rssi > maxRssi! ? rssi : maxRssi);
    avgRssi = _rssiSum / pointCount;

    // Update SNR statistics
    _snrSum += snr;
    minSnr = minSnr == null ? snr : (snr < minSnr! ? snr : minSnr);
    maxSnr = maxSnr == null ? snr : (snr > maxSnr! ? snr : maxSnr);
    avgSnr = _snrSum / pointCount;

    // Update max distance
    if (distance != null) {
      maxDistance =
          maxDistance == null ? distance : (distance > maxDistance! ? distance : maxDistance);
    }
  }

  /// Stop the recording session
  void stop() {
    if (isActive) {
      endTime = DateTime.now();
    }
  }

  /// Create a copy with a new name
  Session copyWith({String? name, String? notes}) {
    return Session(
      id: id,
      name: name ?? this.name,
      startTime: startTime,
      endTime: endTime,
      deviceEui: deviceEui,
      notes: notes ?? this.notes,
      pointCount: pointCount,
      maxDistance: maxDistance,
      minRssi: minRssi,
      maxRssi: maxRssi,
      avgRssi: avgRssi,
      minSnr: minSnr,
      maxSnr: maxSnr,
      avgSnr: avgSnr,
      rssiSum: _rssiSum,
      snrSum: _snrSum,
    );
  }

  /// Summary statistics as a map
  Map<String, dynamic> get statsMap => {
        'pointCount': pointCount,
        'duration': durationText,
        'maxDistance': maxDistance,
        'minRssi': minRssi,
        'maxRssi': maxRssi,
        'avgRssi': avgRssi,
        'minSnr': minSnr,
        'maxSnr': maxSnr,
        'avgSnr': avgSnr,
      };

  @override
  String toString() {
    return 'Session(id: $id, name: $name, points: $pointCount, active: $isActive)';
  }
}
