import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'models/range_point.dart';
import 'models/session.dart';
import 'models/sent_transmission.dart';
import 'services/permission_service.dart';
import 'services/gps_service.dart';
import 'services/bluetooth_service.dart';
import 'services/websocket_service.dart';
import 'services/session_service.dart';
import 'widgets/nav_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Register Hive adapters
  Hive.registerAdapter(RangePointAdapter());
  Hive.registerAdapter(SessionAdapter());
  Hive.registerAdapter(SentTransmissionAdapter());

  runApp(const LiLoRaApp());
}

class LiLoRaApp extends StatelessWidget {
  const LiLoRaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PermissionService()),
        ChangeNotifierProvider(create: (_) => GpsService()),
        ChangeNotifierProvider(create: (_) => BluetoothService()),
        ChangeNotifierProvider(create: (_) {
          final wsService = WebSocketService();
          // Load saved URL from SharedPreferences on startup
          wsService.loadSavedUrl();
          return wsService;
        }),
        ChangeNotifierProvider(create: (_) => SessionService()),
      ],
      child: MaterialApp(
        title: 'LiLoRa GPS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const NavShell(),
      ),
    );
  }
}
