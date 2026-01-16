"""Tests for payload decoder and distance calculation."""

import pytest
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from services.decoder import decode_payload, calculate_distance, encode_payload
from models.range_point import GPSData


class TestDecodePayload:
    """Tests for the decode_payload function."""

    def test_valid_payload(self):
        """Test decoding a valid GPS payload."""
        # Create test GPS data
        test_gps = GPSData(
            latitude=46.0569465,
            longitude=14.5057515,
            fix_quality=1,
            altitude=300,
            hdop=1.2,
            satellites=8,
        )

        # Encode and decode
        hex_payload = encode_payload(test_gps)
        decoded = decode_payload(hex_payload)

        assert decoded is not None
        assert abs(decoded.latitude - test_gps.latitude) < 0.0000001
        assert abs(decoded.longitude - test_gps.longitude) < 0.0000001
        assert decoded.fix_quality == test_gps.fix_quality
        assert decoded.altitude == test_gps.altitude
        assert abs(decoded.hdop - test_gps.hdop) < 0.1
        assert decoded.satellites == test_gps.satellites

    def test_negative_coordinates(self):
        """Test decoding with negative (Southern/Western) coordinates."""
        test_gps = GPSData(
            latitude=-33.8688197,  # Sydney
            longitude=151.2092955,
            fix_quality=2,
            altitude=58,
            hdop=0.9,
            satellites=12,
        )

        hex_payload = encode_payload(test_gps)
        decoded = decode_payload(hex_payload)

        assert decoded is not None
        assert abs(decoded.latitude - test_gps.latitude) < 0.0000001
        assert abs(decoded.longitude - test_gps.longitude) < 0.0000001

    def test_empty_payload(self):
        """Test decoding an empty payload."""
        assert decode_payload("") is None
        assert decode_payload(None) is None

    def test_short_payload(self):
        """Test decoding a payload that's too short."""
        assert decode_payload("0011223344") is None

    def test_invalid_hex(self):
        """Test decoding invalid hex string."""
        assert decode_payload("GHIJ") is None


class TestCalculateDistance:
    """Tests for the Haversine distance calculation."""

    def test_same_point(self):
        """Test distance between same point is zero."""
        distance = calculate_distance(46.0569, 14.5057, 46.0569, 14.5057)
        assert distance < 1  # Should be essentially 0

    def test_known_distance(self):
        """Test distance between two known points (Ljubljana to Vienna ~278km)."""
        # Ljubljana
        lat1, lon1 = 46.0569, 14.5057
        # Vienna
        lat2, lon2 = 48.2082, 16.3738

        distance = calculate_distance(lat1, lon1, lat2, lon2)

        # Should be approximately 277-280 km
        assert 270000 < distance < 285000

    def test_short_distance(self):
        """Test short distance calculation (100m)."""
        # Start point
        lat1, lon1 = 46.0569465, 14.5057515
        # Point approximately 100m north
        lat2, lon2 = 46.0578465, 14.5057515

        distance = calculate_distance(lat1, lon1, lat2, lon2)

        # Should be approximately 100m
        assert 95 < distance < 105

    def test_equator_distance(self):
        """Test distance calculation at equator."""
        # Points at equator, 1 degree apart
        lat1, lon1 = 0.0, 0.0
        lat2, lon2 = 0.0, 1.0

        distance = calculate_distance(lat1, lon1, lat2, lon2)

        # 1 degree at equator is approximately 111km
        assert 110000 < distance < 112000


class TestEncodePayload:
    """Tests for the encode_payload function (used for testing)."""

    def test_round_trip(self):
        """Test encoding and decoding produces same data."""
        original = GPSData(
            latitude=46.0569465,
            longitude=14.5057515,
            fix_quality=1,
            altitude=300,
            hdop=1.2,
            satellites=8,
        )

        hex_payload = encode_payload(original)
        decoded = decode_payload(hex_payload)

        assert decoded is not None
        assert abs(decoded.latitude - original.latitude) < 0.0000001
        assert abs(decoded.longitude - original.longitude) < 0.0000001

    def test_payload_length(self):
        """Test encoded payload is correct length (13 bytes = 26 hex chars)."""
        gps = GPSData(
            latitude=46.0,
            longitude=14.0,
            fix_quality=1,
            altitude=100,
            hdop=1.0,
            satellites=5,
        )

        hex_payload = encode_payload(gps)
        assert len(hex_payload) == 26  # 13 bytes * 2 hex chars per byte
