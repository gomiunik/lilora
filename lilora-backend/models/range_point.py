"""Data models for decoded GPS data and range points."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class GPSData(BaseModel):
    """Decoded GPS data from LoRaWAN payload."""

    latitude: float
    longitude: float
    fix_quality: int = Field(ge=0, le=2, description="0=no fix, 1=GPS, 2=DGPS")
    altitude: int = Field(description="Altitude in meters above sea level")
    hdop: float = Field(ge=0, description="Horizontal dilution of precision")
    satellites: int = Field(ge=0, description="Number of satellites in view")


class RangePoint(BaseModel):
    """Complete range measurement point for visualization."""

    timestamp: datetime = Field(default_factory=datetime.utcnow)
    device_eui: str
    frame_count: int

    # GPS Data
    latitude: float
    longitude: float
    altitude: int
    fix_quality: int
    hdop: float
    satellites: int

    # LoRaWAN Metadata
    rssi: float = Field(description="Received Signal Strength Indicator in dBm")
    snr: float = Field(description="Signal-to-Noise Ratio in dB")
    spreading_factor: int = Field(ge=7, le=12, description="LoRa spreading factor")
    frequency: float = Field(description="Frequency in MHz")

    # Gateway Info
    gateway_id: Optional[str] = None
    gateway_lat: Optional[float] = None
    gateway_lon: Optional[float] = None

    # Calculated Fields
    distance: Optional[float] = Field(default=None, description="Distance from gateway in meters")

    def to_broadcast_dict(self) -> dict:
        """Convert to dictionary for WebSocket broadcast."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "device_eui": self.device_eui,
            "frame_count": self.frame_count,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "altitude": self.altitude,
            "fix_quality": self.fix_quality,
            "hdop": self.hdop,
            "satellites": self.satellites,
            "rssi": self.rssi,
            "snr": self.snr,
            "spreading_factor": self.spreading_factor,
            "frequency": self.frequency,
            "gateway_id": self.gateway_id,
            "gateway_lat": self.gateway_lat,
            "gateway_lon": self.gateway_lon,
            "distance": self.distance,
        }
