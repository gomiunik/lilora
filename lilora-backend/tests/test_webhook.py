"""Tests for webhook endpoints."""

import pytest
import base64
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from fastapi.testclient import TestClient
from main import app
from services.decoder import encode_payload
from models.range_point import GPSData


@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


@pytest.fixture
def sample_gps_payload():
    """Create a sample GPS payload for testing."""
    gps = GPSData(
        latitude=46.0569465,
        longitude=14.5057515,
        fix_quality=1,
        altitude=300,
        hdop=1.2,
        satellites=8,
    )
    hex_payload = encode_payload(gps)
    # Convert hex to base64 for ChirpStack format
    return base64.b64encode(bytes.fromhex(hex_payload)).decode()


class TestRootEndpoint:
    """Tests for root endpoint."""

    def test_root(self, client):
        """Test root endpoint returns API info."""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["name"] == "LiLoRa Backend"
        assert "endpoints" in data


class TestHealthEndpoint:
    """Tests for health check endpoint."""

    def test_health(self, client):
        """Test health check endpoint."""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"


class TestWebhookTest:
    """Tests for webhook test endpoint."""

    def test_webhook_test(self, client):
        """Test webhook test endpoint."""
        response = client.get("/webhook/test")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"


class TestChirpStackWebhook:
    """Tests for ChirpStack webhook endpoint."""

    def test_valid_uplink(self, client, sample_gps_payload):
        """Test processing a valid ChirpStack uplink."""
        payload = {
            "deviceInfo": {
                "devEui": "0011223344556677",
                "deviceName": "test-device",
                "applicationId": "test-app",
                "applicationName": "Test Application",
            },
            "devAddr": "01234567",
            "fCnt": 123,
            "fPort": 1,
            "data": sample_gps_payload,
            "rxInfo": [
                {
                    "gatewayId": "gateway-01",
                    "rssi": -105,
                    "snr": 7.5,
                    "location": {
                        "latitude": 46.05,
                        "longitude": 14.50,
                        "altitude": 295,
                    },
                }
            ],
            "txInfo": {
                "frequency": 868100000,
                "modulation": {
                    "lora": {
                        "spreadingFactor": 7,
                        "bandwidth": 125000,
                    }
                },
            },
        }

        response = client.post("/webhook/chirpstack", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["decoded"] is True

    def test_empty_payload(self, client):
        """Test handling uplink with empty payload."""
        payload = {
            "deviceInfo": {"devEui": "0011223344556677"},
            "fCnt": 1,
            "data": "",
            "rxInfo": [],
            "txInfo": {"frequency": 868100000},
        }

        response = client.post("/webhook/chirpstack", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["decoded"] is False

    def test_invalid_json(self, client):
        """Test handling invalid JSON."""
        response = client.post(
            "/webhook/chirpstack",
            content="not valid json",
            headers={"Content-Type": "application/json"},
        )
        assert response.status_code == 400


class TestTTNWebhook:
    """Tests for TTN webhook endpoint."""

    def test_valid_uplink(self, client, sample_gps_payload):
        """Test processing a valid TTN uplink."""
        payload = {
            "end_device_ids": {
                "device_id": "test-device",
                "dev_eui": "0011223344556677",
                "application_ids": {"application_id": "test-app"},
            },
            "uplink_message": {
                "f_port": 1,
                "f_cnt": 123,
                "frm_payload": sample_gps_payload,
                "rx_metadata": [
                    {
                        "gateway_ids": {"gateway_id": "gateway-01"},
                        "rssi": -105,
                        "snr": 7.5,
                        "location": {
                            "latitude": 46.05,
                            "longitude": 14.50,
                            "altitude": 295,
                        },
                    }
                ],
                "settings": {
                    "frequency": "868100000",
                    "data_rate": {
                        "lora": {
                            "spreading_factor": 7,
                            "bandwidth": 125000,
                        }
                    },
                },
            },
        }

        response = client.post("/webhook/ttn", json=payload)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["decoded"] is True


class TestWebSocketStatus:
    """Tests for WebSocket status endpoint."""

    def test_ws_status(self, client):
        """Test WebSocket status endpoint."""
        response = client.get("/ws/status")
        assert response.status_code == 200
        data = response.json()
        assert "active_connections" in data
        assert data["status"] == "ok"
