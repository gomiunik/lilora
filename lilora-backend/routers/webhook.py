"""Webhook endpoints for ChirpStack and TTN uplink events."""

import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request

from models import ChirpStackUplink, TTNUplink, RangePoint
from services.decoder import decode_payload, calculate_distance
from services.websocket_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/webhook", tags=["webhook"])


def _create_range_point(
    dev_eui: str,
    frame_count: int,
    payload_hex: str,
    rssi: float,
    snr: float,
    spreading_factor: int,
    frequency: float,
    gateway_id: Optional[str],
    gateway_lat: Optional[float],
    gateway_lon: Optional[float],
    timestamp: Optional[datetime] = None,
) -> Optional[RangePoint]:
    """
    Create a RangePoint from uplink data.

    Args:
        Various uplink parameters

    Returns:
        RangePoint or None if payload decoding fails
    """
    gps_data = decode_payload(payload_hex)
    if not gps_data:
        logger.warning(f"Failed to decode payload: {payload_hex}")
        return None

    # Calculate distance from gateway if coordinates available
    distance = None
    if gateway_lat is not None and gateway_lon is not None:
        distance = calculate_distance(
            gps_data.latitude,
            gps_data.longitude,
            gateway_lat,
            gateway_lon,
        )

    return RangePoint(
        timestamp=timestamp or datetime.utcnow(),
        device_eui=dev_eui,
        frame_count=frame_count,
        latitude=gps_data.latitude,
        longitude=gps_data.longitude,
        altitude=gps_data.altitude,
        fix_quality=gps_data.fix_quality,
        hdop=gps_data.hdop,
        satellites=gps_data.satellites,
        rssi=rssi,
        snr=snr,
        spreading_factor=spreading_factor,
        frequency=frequency,
        gateway_id=gateway_id,
        gateway_lat=gateway_lat,
        gateway_lon=gateway_lon,
        distance=distance,
    )


@router.post("/chirpstack")
async def chirpstack_webhook(
    request: Request,
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """
    Receive uplink events from ChirpStack v4.

    ChirpStack sends JSON webhook events for device uplinks.
    This endpoint decodes the GPS payload and broadcasts to WebSocket clients.
    """
    # Optional API key validation
    # if settings.api_key and x_api_key != settings.api_key:
    #     raise HTTPException(status_code=401, detail="Invalid API key")

    try:
        body = await request.json()
        uplink = ChirpStackUplink.model_validate(body)
    except Exception as e:
        logger.error(f"Failed to parse ChirpStack webhook: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid payload: {e}")

    logger.info(
        f"ChirpStack uplink: DevEUI={uplink.dev_eui}, "
        f"FCnt={uplink.frame_count}, Payload={uplink.payload_hex}"
    )

    # Get best gateway info
    gateway = uplink.best_gateway

    range_point = _create_range_point(
        dev_eui=uplink.dev_eui,
        frame_count=uplink.frame_count,
        payload_hex=uplink.payload_hex,
        rssi=gateway.rssi if gateway else 0,
        snr=gateway.snr if gateway else 0,
        spreading_factor=uplink.spreading_factor,
        frequency=uplink.frequency_mhz,
        gateway_id=gateway.gateway_id if gateway else None,
        gateway_lat=gateway.latitude if gateway else None,
        gateway_lon=gateway.longitude if gateway else None,
        timestamp=uplink.time,
    )

    if range_point:
        await manager.broadcast(range_point.to_broadcast_dict())
        logger.info(
            f"Broadcast range point: lat={range_point.latitude:.6f}, "
            f"lon={range_point.longitude:.6f}, rssi={range_point.rssi}"
        )

    return {"status": "ok", "decoded": range_point is not None}


@router.post("/ttn")
async def ttn_webhook(
    request: Request,
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
):
    """
    Receive uplink events from The Things Network v3.

    TTN sends JSON webhook events for device uplinks.
    This endpoint decodes the GPS payload and broadcasts to WebSocket clients.
    """
    try:
        body = await request.json()
        uplink = TTNUplink.model_validate(body)
    except Exception as e:
        logger.error(f"Failed to parse TTN webhook: {e}")
        raise HTTPException(status_code=400, detail=f"Invalid payload: {e}")

    logger.info(
        f"TTN uplink: DevEUI={uplink.dev_eui}, "
        f"FCnt={uplink.frame_count}, Payload={uplink.payload_hex}"
    )

    # Get best gateway info
    gateway = uplink.best_gateway

    range_point = _create_range_point(
        dev_eui=uplink.dev_eui,
        frame_count=uplink.frame_count,
        payload_hex=uplink.payload_hex,
        rssi=gateway.rssi if gateway else 0,
        snr=gateway.snr if gateway else 0,
        spreading_factor=uplink.spreading_factor,
        frequency=uplink.frequency_mhz,
        gateway_id=gateway.gateway_id if gateway else None,
        gateway_lat=gateway.latitude if gateway else None,
        gateway_lon=gateway.longitude if gateway else None,
        timestamp=uplink.received_at,
    )

    if range_point:
        await manager.broadcast(range_point.to_broadcast_dict())
        logger.info(
            f"Broadcast range point: lat={range_point.latitude:.6f}, "
            f"lon={range_point.longitude:.6f}, rssi={range_point.rssi}"
        )

    return {"status": "ok", "decoded": range_point is not None}


@router.get("/test")
async def test_webhook():
    """Test endpoint to verify webhook router is working."""
    return {
        "status": "ok",
        "message": "Webhook endpoints ready",
        "endpoints": ["/webhook/chirpstack", "/webhook/ttn"],
    }
