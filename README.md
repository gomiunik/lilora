# LiLoRa - LoRaWAN Range Tracking System

A multi-repository solution for tracking LoRaWAN signal range and coverage using LilyGo T-Watch S3, mobile phone GPS, and real-time web services.

## Overview

**LiLoRa** combines wearable LoRaWAN hardware, mobile GPS forwarding, and cloud-based visualization to create comprehensive coverage maps for LoRaWAN networks. Perfect for testing gateway range, optimizing network deployment, and validating signal quality in real-world conditions.

### Key Features

- 📍 **GPS Tracking**: Mobile phone provides GPS coordinates to watch via Bluetooth LE
- 📡 **LoRaWAN Integration**: SX1262 radio connects to ChirpStack or The Things Network
- 🗺️ **Real-Time Mapping**: Live signal quality visualization on mobile app
- 📊 **Signal Metrics**: Track RSSI, SNR, spreading factor, and packet delivery
- 💾 **Session Recording**: Save and export range tests as GeoJSON/KML
- 🔋 **Low Power**: Optimized for extended field testing (940mAh battery)

## System Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Mobile Phone   │         │  T-Watch S3      │         │  LoRaWAN        │
│  (GPS Source)   │◄───BLE──┤  (ESP32-S3 +     │───LoRa──►│  Gateway        │
│                 │         │   SX1262 Radio)  │         │                 │
└─────────────────┘         └──────────────────┘         └────────┬────────┘
        │                                                          │
        │                                                          │
        │                   ┌──────────────────┐                  │
        └──────WebSocket────┤  FastAPI Backend │◄────Webhook─────┘
                            │  (Real-time Srv) │
                            └────────┬─────────┘
                                     │
                            ┌────────▼─────────┐
                            │  ChirpStack or   │
                            │  The Things Net  │
                            └──────────────────┘
```

## Repository Structure

This project is organized as a multi-repository setup:

```
lilora/                          # This repository (documentation & planning)
│
├── README.md                    # Project overview (this file)
├── CLAUDE.md                    # Development guide for Claude Code
├── PROJECT_PLAN.md              # Detailed phase-by-phase implementation plan
│
├── lilora-firmware/             # T-Watch S3 firmware (create separately)
│   ├── platformio.ini           # PlatformIO configuration
│   ├── src/
│   │   ├── main.cpp             # Main firmware loop
│   │   ├── lorawan_config.h     # LoRaWAN credentials (gitignored)
│   │   ├── bluetooth.cpp        # BLE NMEA server
│   │   ├── nmea_parser.cpp      # GPS data parser
│   │   └── payload_encoder.cpp  # Binary encoding
│   └── lib/                     # LilyGoLib, RadioLib
│
├── lilora-mobile/               # Flutter mobile app (create separately)
│   ├── pubspec.yaml             # Flutter dependencies
│   ├── lib/
│   │   ├── main.dart            # App entry point
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   └── map_screen.dart
│   │   ├── services/
│   │   │   ├── bluetooth_service.dart
│   │   │   ├── gps_service.dart
│   │   │   └── websocket_service.dart
│   │   └── models/
│   │       └── range_point.dart
│   └── android/ & ios/          # Platform-specific config
│
└── lilora-backend/              # FastAPI backend (create separately)
    ├── main.py                  # FastAPI app
    ├── requirements.txt         # Python dependencies
    ├── models/
    │   └── uplink.py            # ChirpStack/TTN schemas
    ├── services/
    │   ├── decoder.py           # Payload decoder
    │   └── websocket_manager.py # Connection manager
    └── Dockerfile               # Container deployment
```

## Quick Start

### Prerequisites

- **Hardware**:
  - LilyGo T-Watch S3 (with SX1262 LoRa radio, 868MHz or 915MHz)
  - Android or iOS smartphone with GPS
  - LoRaWAN gateway (or access to public TTN coverage)

- **Software**:
  - PlatformIO CLI (firmware development)
  - Flutter SDK 3.x (mobile app)
  - Python 3.10+ (backend service)
  - ChirpStack or TTN account

### Setup Steps

1. **Register LoRaWAN Device**:
   - Create account on [ChirpStack](https://www.chirpstack.io/) or [The Things Network](https://www.thethingsnetwork.org/)
   - Register new device with OTAA activation
   - Note DevEUI, AppEUI (JoinEUI), AppKey

2. **Flash Firmware**:
   ```bash
   cd lilora-firmware
   # Edit src/lorawan_config.h with your keys
   pio run --target upload
   ```

3. **Configure Backend**:
   ```bash
   cd lilora-backend
   # Using uv (recommended)
   uv sync
   uv run uvicorn main:app --host 0.0.0.0 --port 8000

   # Or using pip
   pip install -r requirements.txt
   uvicorn main:app --host 0.0.0.0 --port 8000

   # Add webhook integration in ChirpStack/TTN console
   ```

4. **Run Mobile App**:
   ```bash
   cd lilora-mobile
   flutter pub get
   flutter run
   ```

5. **Start Range Test**:
   - Open mobile app, connect to T-Watch via Bluetooth
   - Enable GPS forwarding
   - Walk away from gateway while watching signal quality
   - View real-time coverage map

## Development Phases

Development is structured in 5 phases (see [PROJECT_PLAN.md](PROJECT_PLAN.md) for details):

### Phase 1: Firmware Foundation ✅
- LoRaWAN OTAA join to ChirpStack/TTN
- Session persistence (NVS storage)
- Uplink/downlink tested and working

### Phase 2: Bluetooth GPS Integration ✅
- BLE Serial Server on T-Watch (Nordic UART Service)
- NMEA sentence generation in Flutter app
- GPS data encoding in LoRaWAN payload (13-byte binary format)

### Phase 3: Backend Service ✅
- FastAPI webhook receiver (ChirpStack & TTN)
- WebSocket broadcast manager for real-time updates
- Payload decoder with Haversine distance calculation
- 19/19 tests passing

### Phase 4: Mobile Visualization 🔜
- Map integration with range plotting
- Live signal metrics dashboard
- Session recording and export

### Phase 5: Enhancements 🔜
- Adaptive Data Rate monitoring
- Multi-gateway support
- Offline mode with sync

## Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Firmware** | PlatformIO + Arduino | ESP32-S3 development |
| | RadioLib 6.6.0 | LoRaWAN stack (SX1262) |
| | ESP32 BLE | Bluetooth LE server |
| **Mobile** | Flutter 3.x | Cross-platform UI |
| | flutter_blue_plus | Bluetooth LE client |
| | geolocator | GPS access |
| **Backend** | FastAPI + uv | Async web framework |
| | WebSockets | Real-time updates |
| | Pydantic | Data validation |
| **Network** | ChirpStack or TTN | LoRaWAN network server |

## Use Cases

- **Network Planning**: Map coverage before deploying IoT devices
- **Gateway Optimization**: Test antenna placement and configuration
- **Interference Analysis**: Identify signal dead zones and obstacles
- **Regulatory Compliance**: Verify duty cycle and power limits
- **Community Mapping**: Contribute to public LoRaWAN coverage databases

## Hardware Specifications

**LilyGo T-Watch S3**:
- ESP32-S3 dual-core @ 240MHz (16MB Flash, 8MB PSRAM)
- SX1262 LoRa transceiver (433/868/915MHz)
- Bluetooth 5.0 Low Energy
- 1.54" LCD touchscreen (240x240)
- BMA423 accelerometer
- 940mAh battery (USB-C charging)

**No GPS on watch**: GPS coordinates provided by mobile phone via Bluetooth LE using NMEA protocol.

## Contributing

This project is in active development. Contributions welcome!

1. Fork the relevant repository (firmware, mobile, or backend)
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add new feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Open Pull Request

## Troubleshooting

### Common Issues

**LoRaWAN Join Fails**:
- Verify OTAA keys match network server exactly
- Enable "Resets DevNonces" in device settings (development only)
- Check gateway is online and in range

**BLE Connection Drops**:
- Ensure location permissions granted on mobile app
- Keep phone within 10m of watch
- Disable battery optimization for app

**Backend Not Receiving Data**:
- Confirm webhook URL is publicly accessible
- Check network server integration logs
- Test with curl: `curl -X POST https://your-backend/webhook/chirpstack -d @sample.json`

See [CLAUDE.md](CLAUDE.md) for detailed troubleshooting guide.

## Resources

### Documentation
- [CLAUDE.md](CLAUDE.md) - Comprehensive development guide for Claude Code
- [LilyGo T-Watch S3 Wiki](https://wiki.lilygo.cc/get_started/en/Wearable/T-Watch-S3-PLUS/T-Watch-S3-PLUS.html)
- [ChirpStack Documentation](https://www.chirpstack.io/docs/)
- [The Things Network Docs](https://www.thethingsnetwork.org/docs/)

### Example Code
- [LoRaWAN Firmware Example](https://raw.githubusercontent.com/Xinyuan-LilyGO/LilyGoLib/refs/heads/master/examples/radio/SX1262/LoRaWAN/LoRaWAN.ino)
- [Flutter BLE Guide](https://pub.dev/packages/flutter_blue_plus)
- [FastAPI WebSocket Tutorial](https://fastapi.tiangolo.com/advanced/websockets/)

## License

This project is released under MIT License. Individual components (LilyGoLib, RadioLib, Flutter, FastAPI) retain their original licenses.

## Acknowledgments

- **LilyGo** - T-Watch S3 hardware platform
- **Jan Gromeš** - RadioLib LoRaWAN implementation
- **ChirpStack/TTN** - Open-source network server infrastructure
- **Flutter & FastAPI communities** - Excellent frameworks and documentation

---

**Project Status**: Phases 1-3 Complete - Firmware, mobile BLE app, and backend service all working. Ready for Phase 4 (Mobile Visualization).

**Maintainer**: Boris Gomiunik
**Created**: January 2026
**Last Updated**: January 2026
