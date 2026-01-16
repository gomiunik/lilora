import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

/// Service for handling runtime permissions (Location and Bluetooth)
class PermissionService extends ChangeNotifier {
  bool _locationPermissionGranted = false;
  bool _bluetoothPermissionGranted = false;
  bool _locationServiceEnabled = false;

  bool get locationPermissionGranted => _locationPermissionGranted;
  bool get bluetoothPermissionGranted => _bluetoothPermissionGranted;
  bool get locationServiceEnabled => _locationServiceEnabled;
  bool get allPermissionsGranted =>
      _locationPermissionGranted && _bluetoothPermissionGranted && _locationServiceEnabled;

  /// Check all permissions on app start
  Future<void> checkPermissions() async {
    await _checkLocationService();
    await _checkLocationPermission();
    await _checkBluetoothPermission();
    notifyListeners();
  }

  /// Check if location services are enabled
  Future<void> _checkLocationService() async {
    _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
  }

  /// Check current location permission status
  Future<void> _checkLocationPermission() async {
    final status = await Permission.locationWhenInUse.status;
    _locationPermissionGranted = status.isGranted;
  }

  /// Check current Bluetooth permission status
  Future<void> _checkBluetoothPermission() async {
    if (Platform.isAndroid) {
      // Android 12+ requires separate Bluetooth permissions
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;
      _bluetoothPermissionGranted = scanStatus.isGranted && connectStatus.isGranted;
    } else {
      // iOS handles Bluetooth permissions differently
      final status = await Permission.bluetooth.status;
      _bluetoothPermissionGranted = status.isGranted || status.isLimited;
    }
  }

  /// Request location permission
  Future<bool> requestLocationPermission() async {
    // First check if location service is enabled
    if (!await Geolocator.isLocationServiceEnabled()) {
      _locationServiceEnabled = false;
      notifyListeners();
      return false;
    }
    _locationServiceEnabled = true;

    // Request permission
    final status = await Permission.locationWhenInUse.request();
    _locationPermissionGranted = status.isGranted;
    notifyListeners();

    if (status.isPermanentlyDenied) {
      // User must manually enable from settings
      return false;
    }

    return _locationPermissionGranted;
  }

  /// Request Bluetooth permissions
  Future<bool> requestBluetoothPermission() async {
    if (Platform.isAndroid) {
      // Request both scan and connect permissions for Android 12+
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      _bluetoothPermissionGranted = results[Permission.bluetoothScan]!.isGranted &&
          results[Permission.bluetoothConnect]!.isGranted;
    } else {
      // iOS
      final status = await Permission.bluetooth.request();
      _bluetoothPermissionGranted = status.isGranted || status.isLimited;
    }

    notifyListeners();
    return _bluetoothPermissionGranted;
  }

  /// Open app settings for manually granting permissions
  Future<void> openAppSettings() async {
    await openAppSettings();
  }

  /// Open location settings
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Get human-readable status for location permission
  String get locationStatusText {
    if (!_locationServiceEnabled) return 'Location Off';
    if (_locationPermissionGranted) return 'Granted';
    return 'Not Granted';
  }

  /// Get human-readable status for Bluetooth permission
  String get bluetoothStatusText {
    if (_bluetoothPermissionGranted) return 'Granted';
    return 'Not Granted';
  }
}
