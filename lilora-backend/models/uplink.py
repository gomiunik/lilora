"""Pydantic models for LoRaWAN network server webhook payloads."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class GatewayMetadata(BaseModel):
    """Gateway information from uplink metadata."""

    gateway_id: str = Field(default="", alias="gatewayId")
    rssi: float = 0
    snr: float = 0
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None


class ChirpStackRxInfo(BaseModel):
    """ChirpStack v4 rxInfo structure."""

    gateway_id: str = Field(default="", alias="gatewayId")
    rssi: int = 0
    snr: float = 0
    location: Optional[dict] = None

    def to_gateway_metadata(self) -> GatewayMetadata:
        """Convert to common GatewayMetadata format."""
        lat = None
        lon = None
        alt = None
        if self.location:
            lat = self.location.get("latitude")
            lon = self.location.get("longitude")
            alt = self.location.get("altitude")

        return GatewayMetadata(
            gatewayId=self.gateway_id,
            rssi=float(self.rssi),
            snr=self.snr,
            latitude=lat,
            longitude=lon,
            altitude=alt,
        )


class ChirpStackTxInfo(BaseModel):
    """ChirpStack v4 txInfo structure."""

    frequency: int = 0
    modulation: Optional[dict] = None

    @property
    def spreading_factor(self) -> int:
        """Extract spreading factor from modulation info."""
        if self.modulation and "lora" in self.modulation:
            return self.modulation["lora"].get("spreadingFactor", 0)
        return 0

    @property
    def bandwidth(self) -> int:
        """Extract bandwidth from modulation info."""
        if self.modulation and "lora" in self.modulation:
            return self.modulation["lora"].get("bandwidth", 0)
        return 0


class ChirpStackDeviceInfo(BaseModel):
    """ChirpStack v4 deviceInfo structure."""

    dev_eui: str = Field(default="", alias="devEui")
    device_name: str = Field(default="", alias="deviceName")
    application_id: str = Field(default="", alias="applicationId")
    application_name: str = Field(default="", alias="applicationName")


class ChirpStackUplink(BaseModel):
    """ChirpStack v4 uplink webhook payload."""

    device_info: ChirpStackDeviceInfo = Field(default_factory=ChirpStackDeviceInfo, alias="deviceInfo")
    dev_addr: str = Field(default="", alias="devAddr")
    adr: bool = False
    dr: int = 0
    f_cnt: int = Field(default=0, alias="fCnt")
    f_port: int = Field(default=0, alias="fPort")
    confirmed: bool = False
    data: str = ""  # Base64 encoded payload
    rx_info: list[ChirpStackRxInfo] = Field(default_factory=list, alias="rxInfo")
    tx_info: ChirpStackTxInfo = Field(default_factory=ChirpStackTxInfo, alias="txInfo")
    time: Optional[datetime] = None

    @property
    def dev_eui(self) -> str:
        return self.device_info.dev_eui

    @property
    def frame_count(self) -> int:
        return self.f_cnt

    @property
    def payload_hex(self) -> str:
        """Convert base64 payload to hex string."""
        import base64

        if not self.data:
            return ""
        try:
            decoded = base64.b64decode(self.data)
            return decoded.hex()
        except Exception:
            return ""

    @property
    def best_gateway(self) -> Optional[GatewayMetadata]:
        """Get gateway with best RSSI."""
        if not self.rx_info:
            return None
        best = max(self.rx_info, key=lambda x: x.rssi)
        return best.to_gateway_metadata()

    @property
    def frequency_mhz(self) -> float:
        return self.tx_info.frequency / 1_000_000

    @property
    def spreading_factor(self) -> int:
        return self.tx_info.spreading_factor

    @property
    def all_gateways(self) -> list[GatewayMetadata]:
        """Get all gateways that received this uplink."""
        return [rx.to_gateway_metadata() for rx in self.rx_info]


class TTNUplinkMessage(BaseModel):
    """TTN v3 uplink_message structure."""

    f_port: int = Field(default=0, alias="f_port")
    f_cnt: int = Field(default=0, alias="f_cnt")
    frm_payload: str = Field(default="", alias="frm_payload")  # Base64 encoded
    rx_metadata: list[dict] = Field(default_factory=list, alias="rx_metadata")
    settings: dict = Field(default_factory=dict)

    @property
    def payload_hex(self) -> str:
        """Convert base64 payload to hex string."""
        import base64

        if not self.frm_payload:
            return ""
        try:
            decoded = base64.b64decode(self.frm_payload)
            return decoded.hex()
        except Exception:
            return ""


class TTNEndDeviceIds(BaseModel):
    """TTN v3 end_device_ids structure."""

    device_id: str = Field(default="", alias="device_id")
    dev_eui: str = Field(default="", alias="dev_eui")
    application_ids: dict = Field(default_factory=dict, alias="application_ids")


class TTNUplink(BaseModel):
    """The Things Network v3 uplink webhook payload."""

    end_device_ids: TTNEndDeviceIds = Field(default_factory=TTNEndDeviceIds, alias="end_device_ids")
    uplink_message: TTNUplinkMessage = Field(default_factory=TTNUplinkMessage, alias="uplink_message")
    received_at: Optional[datetime] = None

    @property
    def dev_eui(self) -> str:
        return self.end_device_ids.dev_eui

    @property
    def frame_count(self) -> int:
        return self.uplink_message.f_cnt

    @property
    def payload_hex(self) -> str:
        return self.uplink_message.payload_hex

    @property
    def best_gateway(self) -> Optional[GatewayMetadata]:
        """Get gateway with best RSSI from rx_metadata."""
        if not self.uplink_message.rx_metadata:
            return None

        best = max(self.uplink_message.rx_metadata, key=lambda x: x.get("rssi", -999))
        location = best.get("location", {})

        return GatewayMetadata(
            gatewayId=best.get("gateway_ids", {}).get("gateway_id", ""),
            rssi=float(best.get("rssi", 0)),
            snr=float(best.get("snr", 0)),
            latitude=location.get("latitude"),
            longitude=location.get("longitude"),
            altitude=location.get("altitude"),
        )

    @property
    def frequency_mhz(self) -> float:
        settings = self.uplink_message.settings
        freq = settings.get("frequency", 0)
        # Handle both string and int frequency values
        return float(freq) / 1_000_000

    @property
    def spreading_factor(self) -> int:
        settings = self.uplink_message.settings
        data_rate = settings.get("data_rate", {})
        lora = data_rate.get("lora", {})
        return lora.get("spreading_factor", 0)

    @property
    def all_gateways(self) -> list[GatewayMetadata]:
        """Get all gateways that received this uplink."""
        gateways = []
        for rx in self.uplink_message.rx_metadata:
            location = rx.get("location", {})
            gateways.append(
                GatewayMetadata(
                    gatewayId=rx.get("gateway_ids", {}).get("gateway_id", ""),
                    rssi=float(rx.get("rssi", 0)),
                    snr=float(rx.get("snr", 0)),
                    latitude=location.get("latitude"),
                    longitude=location.get("longitude"),
                    altitude=location.get("altitude"),
                )
            )
        return gateways
