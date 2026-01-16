"""Payload decoder for LiLoRa GPS data and distance calculations."""

import struct
import math
from typing import Optional

from models.range_point import GPSData


def decode_payload(hex_payload: str) -> Optional[GPSData]:
    """
    Decode binary GPS payload from hex string.

    Payload format (13 bytes):
    - Byte 0-3:  Latitude (int32, scaled by 1e7, big-endian)
    - Byte 4-7:  Longitude (int32, scaled by 1e7, big-endian)
    - Byte 8:    Fix quality (0=no fix, 1=GPS, 2=DGPS)
    - Byte 9-10: Altitude (int16, meters, big-endian)
    - Byte 11:   HDOP (uint8, scaled by 10)
    - Byte 12:   Satellite count (uint8)

    Args:
        hex_payload: Hexadecimal string representing the payload

    Returns:
        GPSData object or None if decoding fails
    """
    if not hex_payload:
        return None

    try:
        data = bytes.fromhex(hex_payload)

        if len(data) < 13:
            return None

        # Unpack: >iiBhBB = big-endian int32, int32, int8, int16, uint8, uint8
        lat_raw, lon_raw, fix, alt, hdop_raw, sats = struct.unpack(">iiBhBB", data[:13])

        return GPSData(
            latitude=lat_raw / 1e7,
            longitude=lon_raw / 1e7,
            fix_quality=fix,
            altitude=alt,
            hdop=hdop_raw / 10.0,
            satellites=sats,
        )

    except (ValueError, struct.error) as e:
        # Log error in production
        print(f"Payload decode error: {e}")
        return None


def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate distance between two GPS coordinates using the Haversine formula.

    Args:
        lat1: Latitude of first point (degrees)
        lon1: Longitude of first point (degrees)
        lat2: Latitude of second point (degrees)
        lon2: Longitude of second point (degrees)

    Returns:
        Distance in meters
    """
    # Earth's radius in meters
    R = 6371000

    # Convert to radians
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    # Haversine formula
    a = math.sin(delta_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def encode_payload(gps_data: GPSData) -> str:
    """
    Encode GPS data to binary payload (for testing purposes).

    Args:
        gps_data: GPSData object to encode

    Returns:
        Hexadecimal string representing the payload
    """
    lat_raw = int(gps_data.latitude * 1e7)
    lon_raw = int(gps_data.longitude * 1e7)
    hdop_raw = int(gps_data.hdop * 10)

    data = struct.pack(
        ">iiBhBB",
        lat_raw,
        lon_raw,
        gps_data.fix_quality,
        gps_data.altitude,
        hdop_raw,
        gps_data.satellites,
    )

    return data.hex()
