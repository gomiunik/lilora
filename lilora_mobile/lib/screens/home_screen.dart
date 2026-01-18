import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/permission_service.dart';
import '../services/gps_service.dart';
import '../services/bluetooth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isForwarding = false;
  Timer? _forwardTimer;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    // Check permissions on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PermissionService>().checkPermissions();
      context.read<BluetoothService>().initialize();

      // Listen for BLE connection changes to auto-enable GPS forwarding
      context.read<BluetoothService>().addListener(_onBluetoothStateChanged);
    });
  }

  void _onBluetoothStateChanged() {
    final bleService = context.read<BluetoothService>();
    final isConnected = bleService.isConnected;

    // Auto-enable GPS forwarding when BLE connects
    if (isConnected && !_wasConnected && !_isForwarding) {
      _wasConnected = true;
      // Use post frame callback to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isForwarding) {
          _toggleForwarding();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GPS Forwarding enabled')),
          );
        }
      });
    }

    // Auto-disable GPS forwarding when BLE disconnects
    if (!isConnected && _wasConnected && _isForwarding) {
      _wasConnected = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isForwarding) {
          _toggleForwarding();
        }
      });
    }

    // Update connection tracking
    _wasConnected = isConnected;
  }

  @override
  void dispose() {
    _forwardTimer?.cancel();
    // Disable wakelock when leaving screen
    WakelockPlus.disable();
    // Remove listener
    context.read<BluetoothService>().removeListener(_onBluetoothStateChanged);
    super.dispose();
  }

  void _toggleForwarding() {
    final bleService = context.read<BluetoothService>();
    final gpsService = context.read<GpsService>();

    if (!bleService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a device first')),
      );
      return;
    }

    setState(() {
      _isForwarding = !_isForwarding;
    });

    if (_isForwarding) {
      // Enable wakelock to prevent screen sleep during GPS forwarding
      WakelockPlus.enable();

      // Start GPS tracking if not already
      if (!gpsService.isTracking) {
        gpsService.startTracking();
      }

      // Start forwarding NMEA every second
      _forwardTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final nmea = gpsService.generateNmeaGGA();
        if (nmea != null) {
          bleService.sendNmea(nmea);
        }
      });
    } else {
      // Disable wakelock when GPS forwarding stops
      WakelockPlus.disable();

      _forwardTimer?.cancel();
      _forwardTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LiLoRa GPS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPermissionsCard(),
            const SizedBox(height: 16),
            _buildScanCard(),
            const SizedBox(height: 16),
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildGpsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return Consumer<PermissionService>(
      builder: (context, permService, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Permissions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildPermissionRow(
                  'Location',
                  permService.locationPermissionGranted && permService.locationServiceEnabled,
                  permService.locationStatusText,
                  () => permService.requestLocationPermission(),
                ),
                const SizedBox(height: 8),
                _buildPermissionRow(
                  'Bluetooth',
                  permService.bluetoothPermissionGranted,
                  permService.bluetoothStatusText,
                  () => permService.requestBluetoothPermission(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionRow(
    String name,
    bool granted,
    String status,
    VoidCallback onRequest,
  ) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle : Icons.cancel,
          color: granted ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$name: $status'),
        ),
        if (!granted)
          TextButton(
            onPressed: onRequest,
            child: const Text('Grant'),
          ),
      ],
    );
  }

  Widget _buildScanCard() {
    return Consumer<BluetoothService>(
      builder: (context, bleService, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan for Devices',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: bleService.isScanning
                          ? () => bleService.stopScan()
                          : () => bleService.startScan(),
                      icon: Icon(bleService.isScanning ? Icons.stop : Icons.search),
                      label: Text(bleService.isScanning ? 'Stop' : 'Scan'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  bleService.statusMessage,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                if (bleService.scanResults.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  ...bleService.scanResults.map((result) {
                    final name = result.device.platformName.isNotEmpty
                        ? result.device.platformName
                        : result.advertisementData.advName;
                    return ListTile(
                      leading: const Icon(Icons.watch),
                      title: Text(name),
                      subtitle: Text('RSSI: ${result.rssi} dBm'),
                      trailing: ElevatedButton(
                        onPressed: bleService.isConnecting
                            ? null
                            : () => bleService.connect(result.device),
                        child: const Text('Connect'),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard() {
    return Consumer<BluetoothService>(
      builder: (context, bleService, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      bleService.isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: bleService.isConnected ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bleService.isConnected
                                ? 'Connected to ${bleService.connectedDeviceName}'
                                : 'Not connected',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            bleService.statusMessage,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (bleService.isConnected)
                      TextButton(
                        onPressed: () {
                          if (_isForwarding) _toggleForwarding();
                          bleService.disconnect();
                        },
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
                if (bleService.isConnected) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Enable GPS Forwarding'),
                    subtitle: Text(_isForwarding ? 'Sending NMEA every second' : 'Disabled'),
                    value: _isForwarding,
                    onChanged: (_) => _toggleForwarding(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGpsCard() {
    return Consumer<GpsService>(
      builder: (context, gpsService, _) {
        final pos = gpsService.lastPosition;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'GPS Status',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton(
                      onPressed: gpsService.isTracking
                          ? () => gpsService.stopTracking()
                          : () => gpsService.startTracking(),
                      child: Text(gpsService.isTracking ? 'Stop' : 'Start'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      gpsService.isTracking ? Icons.gps_fixed : Icons.gps_off,
                      color: gpsService.isTracking ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(gpsService.statusMessage),
                  ],
                ),
                if (pos != null) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  _buildGpsRow('Latitude', pos.latitude.toStringAsFixed(6)),
                  _buildGpsRow('Longitude', pos.longitude.toStringAsFixed(6)),
                  _buildGpsRow('Altitude', '${pos.altitude.toStringAsFixed(1)} m'),
                  _buildGpsRow('Accuracy', '${pos.accuracy.toStringAsFixed(1)} m'),
                  _buildGpsRow('Satellites', '~${pos.estimatedSatellites}'),
                  if (gpsService.lastNmeaSentence != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Last NMEA:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        gpsService.lastNmeaSentence!.trim(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGpsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
