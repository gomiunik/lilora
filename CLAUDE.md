# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LiLoRa** is a multi-repository LoRaWAN range tracking solution consisting of:
- **Wearable Device**: LilyGo T-Watch S3 (ESP32-S3 + SX1262 LoRa + BLE 5.0)
- **Mobile App**: Flutter application (GPS provider via Bluetooth LE)
- **Backend Service**: FastAPI server with WebSocket support
- **Network Server**: ChirpStack or The Things Network (TTN) integration

The system tracks LoRaWAN signal range and quality by combining GPS coordinates from a mobile phone (via BLE) with LoRaWAN uplink metadata (RSSI, SNR, spreading factor) received through network server integrations.

## Architecture

### System Data Flow

```
Mobile Phone (GPS) --[BLE NMEA]--> T-Watch S3 --[LoRaWAN]--> Gateway
                                         |
                                         v
                              ChirpStack/TTN Network Server
                                         |
                                         v
                              FastAPI Backend (WebSocket)
                                         |
                                         v
                                   Flutter App (Visualization)
```

### Repository Structure (Multi-Repo)

This project follows a multi-repository structure:

```
lilora/                          # Parent directory
├── lilora-firmware/             # T-Watch S3 firmware (PlatformIO/Arduino)
├── lilora-mobile/               # Flutter mobile app
├── lilora-backend/              # FastAPI backend service
└── CLAUDE.md                    # This file (shared documentation)
```

### Key Technical Decisions

1. **GPS via BLE, not on-device**: T-Watch S3 lacks GPS hardware. Mobile phone provides NMEA sentences over BLE Serial Profile (SPP emulation).

2. **LoRaWAN for Range Testing**: SX1262 radio uses LoRaWAN protocol (OTAA join) to communicate with ChirpStack/TTN, enabling real-world coverage mapping.

3. **WebSocket for Real-Time Updates**: FastAPI backend receives webhook events from network server and broadcasts to connected clients via WebSocket.

4. **Flutter for Cross-Platform**: Single codebase for Android/iOS with flutter_blue_plus for BLE and location services.

## Development Phases

### Phase 1: Firmware Foundation (lilora-firmware)
**Goal**: Establish stable LoRaWAN uplink with session persistence.

- Set up PlatformIO project with LilyGoLib and RadioLib dependencies
- Implement LoRaWAN OTAA join to ChirpStack/TTN (using example from https://raw.githubusercontent.com/Xinyuan-LilyGO/LilyGoLib/refs/heads/master/examples/radio/SX1262/LoRaWAN/LoRaWAN.ino)
- Add session management (EEPROM/NVS storage for DevNonces and session keys)
- Test uplink transmission with dummy payloads (3-byte sensor data format)
- Verify downlink reception and MAC command handling

**Key Files**:
- `src/main.cpp` - Main firmware loop with state machine (JOINING, JOINED, UPLINK)
- `src/lorawan_config.h` - OTAA credentials (DevEUI, AppEUI, AppKey)
- `src/storage.cpp` - NVS/EEPROM session persistence

**Hardware Requirements**:
- LilyGo T-Watch S3 (ESP32-S3, SX1262 LoRa, 868MHz or 915MHz)
- Registered device on ChirpStack or TTN with "Resets DevNonces" enabled

### Phase 2: Bluetooth GPS Integration (lilora-firmware + lilora-mobile)
**Goal**: Stream GPS coordinates from phone to watch over BLE.

**Firmware Side**:
- Implement BLE Serial Server (SPP-like characteristic for NMEA input)
- Parse NMEA sentences (GGA, RMC) to extract lat/lon and fix quality
- Encode GPS data into LoRaWAN uplink payload (compact binary format)

**Mobile App Side**:
- Create Flutter project with flutter_blue_plus and geolocator packages
- Request location permissions (Android: FINE_LOCATION, iOS: When In Use)
- Generate NMEA GGA/RMC sentences from LocationData
- Send NMEA strings to T-Watch via BLE characteristic writes

**Key Files**:
- Firmware: `src/bluetooth.cpp`, `src/nmea_parser.cpp`, `src/payload_encoder.cpp`
- Mobile: `lib/services/bluetooth_service.dart`, `lib/services/gps_service.dart`, `lib/utils/nmea_formatter.dart`

**Testing**:
- Mock GPS coordinates on phone (developer options)
- Verify NMEA parsing on firmware serial output
- Confirm encoded GPS in LoRaWAN uplink payload (use ChirpStack/TTN live data view)

### Phase 3: Backend Service (lilora-backend)
**Goal**: Receive LoRaWAN uplinks and broadcast range data via WebSocket.

- Set up FastAPI project with WebSocket support and CORS middleware
- Implement webhook endpoint for ChirpStack gRPC events (or TTN v3 HTTP integration)
- Parse uplink metadata: DevEUI, FCnt, RSSI, SNR, frequency, spreading factor, gateway location
- Decode binary payload to extract GPS coordinates
- Broadcast JSON message to all WebSocket clients: `{timestamp, lat, lon, rssi, snr, sf, distance}`
- Calculate distance between GPS position and gateway (Haversine formula)

**Key Files**:
- `main.py` - FastAPI app with webhook and WebSocket routes
- `models/uplink.py` - Pydantic models for ChirpStack/TTN JSON schemas
- `services/decoder.py` - Binary payload decoder (reverse of firmware encoder)
- `services/websocket_manager.py` - Broadcast manager for active connections

**API Endpoints**:
- `POST /webhook/chirpstack` or `/webhook/ttn` - Receives uplink events
- `GET /ws` - WebSocket connection for real-time updates
- `GET /api/sessions` - Historical session data (optional for Phase 4)

**Network Server Configuration**:
- ChirpStack: Add HTTP Integration pointing to `https://your-backend.com/webhook/chirpstack`
- TTN: Add Webhook Integration with uplink event subscription to `https://your-backend.com/webhook/ttn`

### Phase 4: Mobile Visualization (lilora-mobile)
**Goal**: Display real-time range map and session statistics.

- Add WebSocket client to connect to backend (`/ws` endpoint)
- Integrate map widget (flutter_map or google_maps_flutter) with custom markers
- Plot GPS positions colored by signal quality (green=good RSSI, red=weak)
- Display live metrics: current RSSI/SNR, max distance, packet loss rate
- Implement session recording (start/stop buttons, save to local DB)
- Export session data as GeoJSON or KML for external analysis

**Key Files**:
- `lib/screens/map_screen.dart` - Map view with range visualization
- `lib/services/websocket_service.dart` - Backend WebSocket client
- `lib/models/range_point.dart` - Data model for {lat, lon, rssi, snr, timestamp}
- `lib/database/session_db.dart` - SQLite/Hive storage for sessions

**UI Flow**:
1. Home Screen: Connect to T-Watch via BLE, start GPS forwarding
2. Map Screen: Real-time plotting of range points, live metrics overlay
3. Session List: View/export past range testing sessions

### Phase 5: Enhancements (Optional)
- **Adaptive Data Rate (ADR)**: Monitor spreading factor changes during test
- **Multi-Gateway Support**: Show coverage from multiple gateways on map
- **Offline Mode**: Queue uplinks when network unavailable, sync later
- **Firmware OTA**: Update T-Watch firmware remotely via BLE or Wi-Fi
- **Advanced Analytics**: Heatmap generation, predicted coverage zones

## Technology Stack

### Firmware (lilora-firmware)
- **Platform**: PlatformIO (Arduino framework for ESP32-S3)
- **Core Libraries**:
  - [LilyGoLib](https://github.com/Xinyuan-LilyGO/LilyGoLib) - Hardware abstraction for T-Watch S3
  - [RadioLib](https://github.com/jgromes/RadioLib) - LoRaWAN stack for SX1262
  - ESP32 BLE Arduino (built-in) - Bluetooth Low Energy
- **Storage**: ESP32 NVS (Non-Volatile Storage) for session persistence
- **Reference**: LoRaWAN example at https://raw.githubusercontent.com/Xinyuan-LilyGO/LilyGoLib/refs/heads/master/examples/radio/SX1262/LoRaWAN/LoRaWAN.ino

### Mobile App (lilora-mobile)
- **Framework**: Flutter 3.x (Dart)
- **Key Packages**:
  - `flutter_blue_plus` - Bluetooth LE communication (BLE Central role)
  - `geolocator` - Access device GPS and generate location data
  - `permission_handler` - Location and Bluetooth permission requests
  - `web_socket_channel` - WebSocket client for backend connection
  - `flutter_map` or `google_maps_flutter` - Map rendering and markers
  - `hive` or `sqflite` - Local database for session storage

### Backend (lilora-backend)
- **Framework**: FastAPI (Python 3.10+)
- **Key Libraries**:
  - `fastapi` - Async web framework with automatic OpenAPI docs
  - `uvicorn` - ASGI server for production deployment
  - `pydantic` - Data validation for webhook payloads
  - `websockets` - Built-in WebSocket support
  - `httpx` - Async HTTP client (optional, for ChirpStack gRPC REST proxy)
- **Deployment**: Docker container with `uvicorn` running on port 8000

### Network Server
- **Option A**: [ChirpStack v4](https://www.chirpstack.io/) (self-hosted, gRPC API)
- **Option B**: [The Things Network v3](https://www.thethingsnetwork.org/) (cloud, webhook integration)

## Build and Run Commands

### Firmware (lilora-firmware)
```bash
# Install PlatformIO CLI (using uv - recommended)
uv tool install platformio

# Or using pip
pip install platformio

# Build firmware
pio run

# Upload to T-Watch S3 (connect via USB-C)
pio run --target upload

# Monitor serial output (baudrate 115200)
pio device monitor

# Clean build artifacts
pio run --target clean
```

**platformio.ini configuration**:
```ini
[env:lilygo-t-watch-s3]
platform = espressif32
board = lilygo-t-watch-s3
framework = arduino
lib_deps =
    https://github.com/Xinyuan-LilyGO/LilyGoLib.git
    jgromes/RadioLib@^6.6.0
monitor_speed = 115200
```

### Mobile App (lilora-mobile)
```bash
# Install Flutter dependencies
flutter pub get

# Run on connected Android device
flutter run

# Run on iOS simulator (macOS only)
flutter run -d ios

# Build APK for Android
flutter build apk --release

# Build iOS app (requires Xcode)
flutter build ios --release

# Run tests
flutter test

# Generate code (if using freezed/json_serializable)
flutter pub run build_runner build --delete-conflicting-outputs
```

**Key Flutter Commands**:
- `flutter doctor` - Check development environment setup
- `flutter devices` - List connected devices/simulators
- `flutter clean` - Clear build cache

### Backend (lilora-backend)
```bash
# Using uv (recommended)
# Install dependencies and create virtual environment
uv sync

# Run development server (auto-reload enabled)
uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Run production server
uv run uvicorn main:app --workers 4 --host 0.0.0.0 --port 8000

# Run tests
uv run pytest tests/

# Or using traditional pip approach:
# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run development server
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Docker build and run
docker build -t lilora-backend .
docker run -p 8000:8000 lilora-backend
```

**pyproject.toml** (for uv):
```toml
[project]
name = "lilora-backend"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.27.0",
    "pydantic>=2.5.0",
    "websockets>=12.0",
    "python-dotenv>=1.0.0",
]

[tool.uv]
dev-dependencies = [
    "pytest>=8.0.0",
]
```

**requirements.txt** (for pip):
```
fastapi>=0.115.0
uvicorn[standard]>=0.27.0
pydantic>=2.5.0
websockets>=12.0
python-dotenv>=1.0.0
```

## Testing Strategy

### Firmware Testing
1. **LoRaWAN Join Test**: Verify OTAA join completes within 30 seconds
2. **Session Persistence**: Power cycle device, confirm session restored (no rejoin)
3. **BLE Serial Test**: Connect with Serial Bluetooth Terminal app, send NMEA sentences
4. **Payload Encoding**: Check uplink hex on ChirpStack/TTN matches expected format

### Mobile App Testing
1. **Location Permissions**: Test permission denial and grant flows
2. **BLE Scan and Connect**: Verify T-Watch appears in scan results, stable connection
3. **NMEA Generation**: Log generated sentences, validate checksum and format
4. **WebSocket Reconnection**: Simulate backend disconnect, confirm auto-reconnect

### Backend Testing
1. **Webhook Validation**: Send mock uplink JSON, verify parsing and broadcast
2. **WebSocket Load**: Connect 10+ clients, confirm no message loss
3. **Payload Decoding**: Test edge cases (invalid GPS, missing fields)

### Integration Testing
1. **End-to-End Flow**: GPS on phone → BLE → firmware → LoRaWAN → backend → WebSocket → app
2. **Range Walk Test**: Walk away from gateway, verify RSSI/SNR degrades as expected
3. **Session Export**: Record 100+ points, export GeoJSON, visualize in QGIS

## Network Server Setup

### ChirpStack Integration
1. Deploy ChirpStack v4 (Docker Compose: https://www.chirpstack.io/docs/getting-started/docker.html)
2. Create Tenant, Application, Device Profile (LoRaWAN 1.0.4 or 1.1, Class A)
3. Register T-Watch device with OTAA keys (DevEUI, AppEUI, AppKey)
4. Enable "Resets DevNonces" in device settings (for development)
5. Add HTTP Integration: `https://your-backend.com/webhook/chirpstack`
6. Use gRPC API (port 8080) or REST proxy for programmatic access

**Useful ChirpStack API Calls**:
- `/api/devices/{devEUI}` - Get device info
- `/api/devices/{devEUI}/events` - Stream device events (gRPC)

### The Things Network (TTN) Integration
1. Register account at https://console.cloud.thethings.network/
2. Create Application, register end device (OTAA)
3. Copy DevEUI, AppEUI (JoinEUI), AppKey to firmware config
4. Add Webhook Integration: `https://your-backend.com/webhook/ttn`
5. Subscribe to uplink messages and join accepts

**TTN Console Useful Views**:
- Live Data tab - Real-time uplink/downlink visualization
- Storage Integration - Historical data query (batch writes, not real-time)

## Common Development Workflows

### Adding a New Sensor to Payload
1. Update `src/payload_encoder.cpp` (firmware) to add sensor bytes
2. Update `services/decoder.py` (backend) to parse new fields
3. Update `models/range_point.dart` (mobile) to include new properties
4. Modify WebSocket message format and map visualization if needed

### Changing LoRaWAN Region
1. Edit `src/lorawan_config.h`: Set `LORAWAN_REGION` (e.g., EU868, US915, AS923)
2. Update antenna frequency in ChirpStack/TTN device profile
3. Adjust duty cycle limits in firmware per regional regulations

### Debugging BLE Connection Issues
1. Enable verbose BLE logs in firmware: `BLEDevice::setDebugLevel(ESP_LOG_VERBOSE)`
2. Check mobile app logs: `flutter logs --verbose`
3. Use nRF Connect app (Android/iOS) to inspect T-Watch services and characteristics
4. Verify BLE characteristic UUIDs match between firmware and app

### Debugging LoRaWAN Join Failures
1. Check DevEUI, AppEUI, AppKey match network server exactly
2. Verify "Resets DevNonces" is enabled (dev mode only)
3. Confirm gateway is online and in range (check ChirpStack/TTN Gateway page)
4. Increase join timeout in firmware (default 30s may be too short)
5. Monitor network server logs for join-request and join-accept messages

## Security Considerations

- **LoRaWAN Keys**: Never commit `lorawan_config.h` with production keys (add to `.gitignore`)
- **Backend Authentication**: Add API key or JWT authentication for webhook endpoints in production
- **WebSocket Security**: Use WSS (WebSocket Secure) with TLS certificates
- **BLE Pairing**: Implement PIN-based pairing for sensitive deployments
- **Data Privacy**: GPS coordinates are personal data; comply with GDPR/local privacy laws

## Payload Format

### Uplink (T-Watch → Network Server)
**Binary format (13 bytes)**:
```
Byte 0-3:  Latitude (int32, scaled by 1e7)
Byte 4-7:  Longitude (int32, scaled by 1e7)
Byte 8:    GPS fix quality (0=no fix, 1=GPS, 2=DGPS)
Byte 9-10: Altitude (int16, meters above sea level)
Byte 11:   HDOP (horizontal dilution of precision, scaled by 10)
Byte 12:   Number of satellites
```

**Example decoder (Python)**:
```python
import struct

def decode_payload(hex_payload: str) -> dict:
    data = bytes.fromhex(hex_payload)
    lat, lon, fix, alt, hdop, sats = struct.unpack('>iiBhBB', data)
    return {
        "latitude": lat / 1e7,
        "longitude": lon / 1e7,
        "fix_quality": fix,
        "altitude": alt,
        "hdop": hdop / 10.0,
        "satellites": sats
    }
```

### Downlink (Network Server → T-Watch)
**Optional commands** (not required for basic range tracking):
- Port 1: Configuration update (spreading factor, tx power)
- Port 2: LED pattern (visual feedback on watch)

## Hardware Specifications

### LilyGo T-Watch S3
- **MCU**: ESP32-S3 (Xtensa dual-core 240MHz, 8MB PSRAM, 16MB Flash)
- **LoRa Radio**: SX1262 (long-range, low-power, 433/868/915MHz variants)
- **Display**: 1.54" 240x240 LCD with capacitive touch
- **Sensors**: BMA423 accelerometer (step counting, gesture detection)
- **Audio**: MAX98357A amplifier + PDM microphone
- **Battery**: 940mAh LiPo (USB-C charging)
- **Connectivity**: Wi-Fi 802.11b/g/n, Bluetooth 5.0 LE
- **Expansion**: I2C, SPI, UART pins exposed on back connector

**Power Consumption**:
- Deep sleep: ~0.3mA (LoRa radio off)
- Active LoRa TX: ~120mA (SF7, 14dBm)
- BLE connected: ~15mA

## Troubleshooting

### "Session does not exist" error after restart
- NVS session storage may be corrupted
- Solution: Erase flash (`pio run --target erase`) and reflash firmware
- Ensure `node.restore()` in firmware returns `RADIOLIB_ERR_NONE`

### GPS coordinates not updating on watch
- Check BLE connection status LED on watch
- Verify mobile app has location permissions granted
- Test NMEA generation: Print sentences to app console before sending
- Confirm BLE characteristic write succeeds (no error codes)

### Backend not receiving webhook events
- Check network server integration logs (ChirpStack/TTN console)
- Verify backend is publicly accessible (use ngrok for local testing)
- Test webhook manually with curl: `curl -X POST https://your-backend.com/webhook/chirpstack -d @sample_uplink.json`
- Ensure Content-Type is `application/json`

### Mobile app map shows wrong location
- Decoder mismatch: Verify backend decoder matches firmware encoder exactly
- Coordinate scaling: Latitude/longitude must be divided by 1e7
- Byte order: Use big-endian (`>`) or little-endian (`<`) consistently

## References and Resources

### Hardware
- [LilyGo T-Watch S3 Product Page](https://lilygo.cc/products/t-watch-s3)
- [LilyGo T-Watch S3 Wiki](https://wiki.lilygo.cc/get_started/en/Wearable/T-Watch-S3-PLUS/T-Watch-S3-PLUS.html)
- [LilyGoLib GitHub Repository](https://github.com/Xinyuan-LilyGO/LilyGoLib)
- [LoRaWAN Example Code](https://raw.githubusercontent.com/Xinyuan-LilyGO/LilyGoLib/refs/heads/master/examples/radio/SX1262/LoRaWAN/LoRaWAN.ino)

### LoRaWAN Protocol
- [LoRaWAN Specification 1.0.4](https://lora-alliance.org/resource_hub/lorawan-specification-v1-0-4/)
- [RadioLib Documentation](https://jgromes.github.io/RadioLib/)
- [ChirpStack Documentation](https://www.chirpstack.io/docs/)
- [The Things Network Documentation](https://www.thethingsnetwork.org/docs/)

### Flutter Development
- [flutter_blue_plus Package](https://pub.dev/packages/flutter_blue_plus)
- [geolocator Package](https://pub.dev/packages/geolocator)
- [Flutter Maps Comparison](https://fluttergems.dev/map/)

### FastAPI Development
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [FastAPI WebSocket Guide](https://fastapi.tiangolo.com/advanced/websockets/)

### NMEA Protocol
- [NMEA 0183 Specification](https://gpsd.gitlab.io/gpsd/NMEA.html)
- [Connecting NMEA via Bluetooth](https://www.jillybunch.com/sharegps/nmea-bluetooth-linux.html)

## License and Attribution

This project combines multiple open-source components:
- **LilyGoLib**: MIT License (Xinyuan-LilyGO)
- **RadioLib**: MIT License (Jan Gromeš)
- **Flutter**: BSD 3-Clause License (Google)
- **FastAPI**: MIT License (Sebastián Ramírez)
- **ChirpStack**: MIT License (Orne Brocaar)

Ensure compliance with all licenses when distributing or modifying this project.
