import '../models/gps_data.dart';

/// NMEA 0183 sentence formatter
/// Generates GGA and RMC sentences from GPS data
class NmeaFormatter {
  /// Generate GPGGA sentence from GPS data
  /// Format: $GPGGA,hhmmss.ss,llll.ll,a,yyyyy.yy,a,x,xx,x.x,x.x,M,x.x,M,x.x,xxxx*hh
  static String formatGGA(GpsData gps) {
    final time = _formatTime(gps.timestamp);
    final lat = _formatLatitude(gps.latitude);
    final latDir = gps.latitude >= 0 ? 'N' : 'S';
    final lon = _formatLongitude(gps.longitude);
    final lonDir = gps.longitude >= 0 ? 'E' : 'W';
    final fix = gps.fixQuality.toString();
    final sats = gps.estimatedSatellites.toString().padLeft(2, '0');
    final hdop = gps.hdop.toStringAsFixed(1);
    final alt = gps.altitude.toStringAsFixed(1);

    // Build sentence without checksum
    final sentence =
        'GPGGA,$time,$lat,$latDir,$lon,$lonDir,$fix,$sats,$hdop,$alt,M,,M,,';

    // Calculate and append checksum
    final checksum = _calculateChecksum(sentence);
    return '\$$sentence*$checksum\r\n';
  }

  /// Generate GPRMC sentence from GPS data
  /// Format: $GPRMC,hhmmss.ss,A,llll.ll,a,yyyyy.yy,a,x.x,x.x,ddmmyy,x.x,a*hh
  static String formatRMC(GpsData gps) {
    final time = _formatTime(gps.timestamp);
    final status = gps.isValid ? 'A' : 'V';
    final lat = _formatLatitude(gps.latitude);
    final latDir = gps.latitude >= 0 ? 'N' : 'S';
    final lon = _formatLongitude(gps.longitude);
    final lonDir = gps.longitude >= 0 ? 'E' : 'W';
    final speed = _metersPerSecToKnots(gps.speed).toStringAsFixed(1);
    final course = gps.heading.toStringAsFixed(1);
    final date = _formatDate(gps.timestamp);

    // Build sentence without checksum
    final sentence =
        'GPRMC,$time,$status,$lat,$latDir,$lon,$lonDir,$speed,$course,$date,,';

    // Calculate and append checksum
    final checksum = _calculateChecksum(sentence);
    return '\$$sentence*$checksum\r\n';
  }

  /// Calculate NMEA checksum (XOR of all characters between $ and *)
  static String _calculateChecksum(String sentence) {
    int checksum = 0;
    for (int i = 0; i < sentence.length; i++) {
      checksum ^= sentence.codeUnitAt(i);
    }
    return checksum.toRadixString(16).toUpperCase().padLeft(2, '0');
  }

  /// Format time as HHMMSS.SS
  static String _formatTime(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}'
        '.${(utc.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  /// Format date as DDMMYY
  static String _formatDate(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.day.toString().padLeft(2, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${(utc.year % 100).toString().padLeft(2, '0')}';
  }

  /// Format latitude as DDMM.MMMM
  static String _formatLatitude(double lat) {
    final absLat = lat.abs();
    final degrees = absLat.floor();
    final minutes = (absLat - degrees) * 60;
    return '${degrees.toString().padLeft(2, '0')}'
        '${minutes.toStringAsFixed(4).padLeft(7, '0')}';
  }

  /// Format longitude as DDDMM.MMMM
  static String _formatLongitude(double lon) {
    final absLon = lon.abs();
    final degrees = absLon.floor();
    final minutes = (absLon - degrees) * 60;
    return '${degrees.toString().padLeft(3, '0')}'
        '${minutes.toStringAsFixed(4).padLeft(7, '0')}';
  }

  /// Convert meters/second to knots
  static double _metersPerSecToKnots(double mps) {
    return mps * 1.94384;
  }

  /// Validate NMEA checksum
  static bool validateChecksum(String sentence) {
    if (!sentence.startsWith('\$') || !sentence.contains('*')) {
      return false;
    }

    final asteriskIndex = sentence.indexOf('*');
    if (asteriskIndex < 0 || asteriskIndex + 2 >= sentence.length) {
      return false;
    }

    // Extract sentence content and provided checksum
    final content = sentence.substring(1, asteriskIndex);
    final providedChecksum =
        sentence.substring(asteriskIndex + 1, asteriskIndex + 3).toUpperCase();

    // Calculate expected checksum
    final expectedChecksum = _calculateChecksum(content);

    return providedChecksum == expectedChecksum;
  }
}
