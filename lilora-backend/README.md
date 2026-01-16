# LiLoRa Backend

FastAPI backend service for the LiLoRa LoRaWAN range tracking system. Receives uplink events from ChirpStack or TTN via webhooks, decodes GPS payloads, and broadcasts data to WebSocket clients for real-time visualization.

## Features

- **Webhook Endpoints**: Receive uplinks from ChirpStack v4 and The Things Network v3
- **Payload Decoder**: Decode binary GPS data from LoRaWAN payloads
- **WebSocket Broadcasting**: Real-time data streaming to connected clients
- **Distance Calculation**: Haversine formula for gateway-to-device distance
- **CORS Support**: Configurable cross-origin resource sharing

## Quick Start

### Using uv (Recommended)

```bash
# Install uv if not already installed
pip install uv

# Install dependencies
uv sync

# Run development server
uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Using pip

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run development server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Using Docker

```bash
# Build image
docker build -t lilora-backend .

# Run container
docker run -p 8000:8000 lilora-backend
```

## API Endpoints

### Root
- `GET /` - API information
- `GET /health` - Health check

### Webhooks
- `POST /webhook/chirpstack` - ChirpStack v4 uplink webhook
- `POST /webhook/ttn` - The Things Network v3 uplink webhook
- `GET /webhook/test` - Test endpoint

### WebSocket
- `WS /ws` - Real-time range data stream
- `GET /ws/status` - WebSocket connection status

### Documentation
- `GET /docs` - Swagger UI
- `GET /redoc` - ReDoc

## Configuration

Create a `.env` file based on `.env.example`:

```env
# API Authentication (optional)
API_KEY=your-secure-api-key

# CORS Origins
CORS_ORIGINS=http://localhost:3000,http://localhost:8080

# Server
HOST=0.0.0.0
PORT=8000
LOG_LEVEL=INFO
```

## Network Server Setup

### ChirpStack v4

1. Go to Application > Integrations > HTTP
2. Add integration with URL: `https://your-backend.com/webhook/chirpstack`
3. Set event types: Uplink events

### The Things Network v3

1. Go to Application > Integrations > Webhooks
2. Create webhook with base URL: `https://your-backend.com`
3. Set uplink path: `/webhook/ttn`
4. Enable uplink messages

## WebSocket Message Format

Connected clients receive JSON messages:

```json
{
    "timestamp": "2024-01-15T12:00:00",
    "device_eui": "0011223344556677",
    "frame_count": 123,
    "latitude": 46.123456,
    "longitude": 14.654321,
    "altitude": 300,
    "fix_quality": 1,
    "hdop": 1.2,
    "satellites": 8,
    "rssi": -105.0,
    "snr": 7.5,
    "spreading_factor": 7,
    "frequency": 868.1,
    "gateway_id": "gateway-01",
    "gateway_lat": 46.100000,
    "gateway_lon": 14.600000,
    "distance": 1234.5
}
```

## Payload Format

The backend expects a 13-byte binary payload:

| Bytes | Type | Description |
|-------|------|-------------|
| 0-3 | int32 | Latitude (scaled by 1e7) |
| 4-7 | int32 | Longitude (scaled by 1e7) |
| 8 | uint8 | Fix quality (0=none, 1=GPS, 2=DGPS) |
| 9-10 | int16 | Altitude (meters) |
| 11 | uint8 | HDOP (scaled by 10) |
| 12 | uint8 | Satellite count |

## Testing

```bash
# Run tests
uv run pytest

# Run with coverage
uv run pytest --cov=. --cov-report=html
```

## Development

```bash
# Install dev dependencies
uv sync --dev

# Run with auto-reload
uv run uvicorn main:app --reload

# Format code
uv run black .
uv run isort .
```

## License

MIT License - See LICENSE file for details.
