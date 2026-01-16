import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/permission_service.dart';
import 'services/gps_service.dart';
import 'services/bluetooth_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      ],
      child: MaterialApp(
        title: 'LiLoRa GPS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
