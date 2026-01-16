# LiLoRa GPS - Mobile App

Flutter mobile application that streams GPS coordinates to the LiLoRa T-Watch S3 via Bluetooth Low Energy (BLE). The watch then transmits your location over LoRaWAN for range testing.

## Features

- **BLE Scanner**: Finds nearby LiLoRa devices automatically
- **GPS Streaming**: Continuous high-accuracy position updates
- **NMEA Generation**: Formats GPS data as standard NMEA GGA sentences
- **Auto-Forwarding**: Sends position updates every second when enabled
- **Permission Management**: Handles Location and Bluetooth permissions gracefully
- **Cross-Platform**: Works on Android and iOS

## Prerequisites

### Development Environment

- **Flutter SDK** 3.7.0 or later
- **Dart SDK** 3.0.0 or later
- **Android Studio** (for Android development)
- **Xcode** (for iOS development, macOS only)

### Install Flutter

1. Download Flutter from https://docs.flutter.dev/get-started/install
2. Add Flutter to your PATH
3. Run `flutter doctor` to verify installation

```bash
flutter doctor
```

### Android Requirements

- Android SDK with API level 21+ (Android 5.0 Lollipop)
- Android device or emulator with Bluetooth and GPS
- USB debugging enabled on physical device

### iOS Requirements

- macOS with Xcode 14+
- iOS device (BLE doesn't work well in simulator)
- Apple Developer account (for device deployment)

## Installation

### 1. Clone and Navigate

```bash
cd lilora/lilora_mobile
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Verify Setup

```bash
flutter analyze
```

## Running the App

### Android

```bash
# Connect Android device via USB with debugging enabled
flutter run

# Or build APK for installation
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`

### iOS

```bash
# Open in Xcode first to configure signing
open ios/Runner.xcworkspace

# Then run
flutter run -d ios

# Or build for release
flutter build ios --release
```

## Deployment

### Android Release Build

1. Generate a keystore (one-time):
   ```bash
   keytool -genkey -v -keystore ~/lilora-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias lilora
   ```

2. Create `android/key.properties`:
   ```properties
   storePassword=<your-password>
   keyPassword=<your-password>
   keyAlias=lilora
   storeFile=/path/to/lilora-release.jks
   ```

3. Build release APK:
   ```bash
   flutter build apk --release
   ```

4. Install on device:
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

### iOS Release Build

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select your Development Team in Signing & Capabilities
3. Build archive: **Product > Archive**
4. Distribute via App Store Connect or Ad Hoc

## Usage

### 1. Grant Permissions

On first launch, grant both permissions when prompted:
- **Location**: Required for GPS coordinates
- **Bluetooth**: Required for BLE communication

### 2. Connect to T-Watch

1. Ensure T-Watch is powered on with LiLoRa firmware
2. Tap **Scan** to find nearby devices
3. Look for device named "LiLoRa-XXXX"
4. Tap **Connect** next to the device

### 3. Start GPS Forwarding

1. Tap **Start** in the GPS Status section
2. Wait for GPS fix (may take 30+ seconds outdoors)
3. Toggle **GPS Forwarding** switch to ON
4. NMEA sentences are now sent every second

### 4. Verify on T-Watch

Check the T-Watch display shows:
- BLE: Connected
- GPS: Fix (X sats)

## Project Structure

```
lilora_mobile/
├── lib/
│   ├── main.dart                 # App entry point with Provider setup
│   ├── models/
│   │   └── gps_data.dart         # GPS data model
│   ├── services/
│   │   ├── permission_service.dart   # Permission handling
│   │   ├── gps_service.dart          # GPS streaming
│   │   └── bluetooth_service.dart    # BLE communication
│   ├── screens/
│   │   └── home_screen.dart      # Main UI
│   └── utils/
│       └── nmea_formatter.dart   # NMEA sentence generation
├── android/                      # Android platform code
├── ios/                          # iOS platform code
├── test/                         # Unit tests
└── pubspec.yaml                  # Dependencies
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | ^1.32.0 | BLE communication |
| geolocator | ^13.0.0 | GPS location services |
| permission_handler | ^11.3.0 | Runtime permissions |
| provider | ^6.1.0 | State management |

## Troubleshooting

### "No LiLoRa devices found"

- Ensure T-Watch is powered on and running LiLoRa firmware
- Check Bluetooth is enabled on your phone
- Move closer to the T-Watch (within 10 meters)
- Try restarting the T-Watch

### "Permission denied"

- Go to phone Settings > Apps > LiLoRa GPS > Permissions
- Enable Location and Bluetooth permissions manually
- On Android 12+, ensure "Nearby devices" permission is granted

### GPS not getting fix

- Go outdoors with clear sky view
- Wait up to 60 seconds for initial fix
- Check Location is enabled in phone settings
- Disable battery saver mode (may limit GPS)

### Connection drops frequently

- Stay within 10 meters of T-Watch
- Avoid obstacles between phone and watch
- Ensure phone screen stays on (disable sleep)
- Check T-Watch battery level

### NMEA not appearing on T-Watch

- Verify BLE connection is active (display shows "Connected")
- Check GPS Forwarding switch is ON
- Ensure GPS has a fix (not "Waiting for GPS fix")
- Monitor T-Watch Serial output at 115200 baud

## NMEA Format

The app generates NMEA 0183 GGA sentences:

```
$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,47.0,M,,*47
```

| Field | Example | Description |
|-------|---------|-------------|
| Time | 123519 | UTC time (hhmmss) |
| Latitude | 4807.038,N | Degrees + minutes, hemisphere |
| Longitude | 01131.000,E | Degrees + minutes, hemisphere |
| Fix | 1 | Fix quality (1=GPS) |
| Satellites | 08 | Number in use |
| HDOP | 0.9 | Horizontal dilution |
| Altitude | 545.4,M | Meters above sea level |
| Checksum | *47 | XOR checksum |

## Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Submit pull request

## License

MIT License - See project root for details
