import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Nordic UART Service UUIDs (industry standard)
class NordicUartUuids {
  static const String service = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String rxChar = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // Write to device
  static const String txChar = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // Read from device
}

/// Service for BLE communication with T-Watch
class BluetoothService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notifySubscription;

  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String _statusMessage = 'Disconnected';
  String? _lastReceivedData;

  List<ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedDevice != null && _rxCharacteristic != null;
  String get statusMessage => _statusMessage;
  String? get connectedDeviceName => _connectedDevice?.platformName;
  String? get lastReceivedData => _lastReceivedData;

  /// Initialize Bluetooth service
  Future<void> initialize() async {
    // Check if Bluetooth is available
    if (await FlutterBluePlus.isSupported == false) {
      _statusMessage = 'Bluetooth not supported';
      notifyListeners();
      return;
    }

    // Listen for Bluetooth state changes
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        _statusMessage = 'Bluetooth is off';
        notifyListeners();
      }
    });
  }

  /// Start scanning for LiLoRa devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    if (_isScanning) return;

    _scanResults = [];
    _isScanning = true;
    _statusMessage = 'Scanning...';
    notifyListeners();

    try {
      // Listen for scan results
      final subscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          // Filter for LiLoRa devices
          _scanResults = results
              .where((r) =>
                  r.device.platformName.startsWith('LiLoRa') ||
                  r.advertisementData.advName.startsWith('LiLoRa'))
              .toList();
          notifyListeners();
        },
        onError: (e) => debugPrint('Scan error: $e'),
      );

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // Wait for scan to complete
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      subscription.cancel();

      _isScanning = false;
      _statusMessage = _scanResults.isEmpty
          ? 'No LiLoRa devices found'
          : 'Found ${_scanResults.length} device(s)';
      notifyListeners();
    } catch (e) {
      _isScanning = false;
      _statusMessage = 'Scan error: $e';
      notifyListeners();
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  /// Connect to a device
  Future<bool> connect(BluetoothDevice device) async {
    if (_isConnecting) return false;

    _isConnecting = true;
    _statusMessage = 'Connecting to ${device.platformName}...';
    notifyListeners();

    try {
      // Connect with timeout
      await device.connect(timeout: const Duration(seconds: 10));

      // Listen for connection state changes
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      // Discover services
      _statusMessage = 'Discovering services...';
      notifyListeners();

      final services = await device.discoverServices();

      // Find Nordic UART Service
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            NordicUartUuids.service.toLowerCase()) {
          // Find characteristics
          for (final char in service.characteristics) {
            final uuid = char.uuid.toString().toLowerCase();
            if (uuid == NordicUartUuids.rxChar.toLowerCase()) {
              _rxCharacteristic = char;
            } else if (uuid == NordicUartUuids.txChar.toLowerCase()) {
              _txCharacteristic = char;
            }
          }
          break;
        }
      }

      if (_rxCharacteristic == null) {
        throw Exception('Nordic UART RX characteristic not found');
      }

      // Subscribe to TX notifications if available
      if (_txCharacteristic != null && _txCharacteristic!.properties.notify) {
        await _txCharacteristic!.setNotifyValue(true);
        _notifySubscription = _txCharacteristic!.onValueReceived.listen((data) {
          _lastReceivedData = utf8.decode(data);
          notifyListeners();
        });
      }

      _connectedDevice = device;
      _isConnecting = false;
      _statusMessage = 'Connected to ${device.platformName}';
      notifyListeners();

      return true;
    } catch (e) {
      _isConnecting = false;
      _statusMessage = 'Connection failed: $e';
      _connectedDevice = null;
      _rxCharacteristic = null;
      _txCharacteristic = null;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    try {
      await _notifySubscription?.cancel();
      await _connectionSubscription?.cancel();
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }

    _onDisconnected();
  }

  /// Handle disconnection
  void _onDisconnected() {
    _connectedDevice = null;
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _connectionSubscription?.cancel();
    _notifySubscription?.cancel();
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  /// Send NMEA sentence to device
  Future<bool> sendNmea(String sentence) async {
    if (_rxCharacteristic == null) {
      debugPrint('Cannot send: not connected');
      return false;
    }

    try {
      final data = utf8.encode(sentence);

      // Write with response for reliability
      await _rxCharacteristic!.write(data, withoutResponse: false);

      debugPrint('Sent NMEA: ${sentence.trim()}');
      return true;
    } catch (e) {
      debugPrint('Send error: $e');
      _statusMessage = 'Send error: $e';
      notifyListeners();
      return false;
    }
  }

  /// Send raw bytes to device
  Future<bool> sendBytes(List<int> data) async {
    if (_rxCharacteristic == null) return false;

    try {
      await _rxCharacteristic!.write(data, withoutResponse: false);
      return true;
    } catch (e) {
      debugPrint('Send error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
