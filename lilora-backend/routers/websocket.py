"""WebSocket endpoint for real-time range data streaming."""

import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.websocket_manager import manager

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time range data.

    Clients connect to this endpoint to receive broadcasts of decoded
    GPS/LoRaWAN range points as they arrive from the network server webhooks.

    Message format (JSON):
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
    """
    await manager.connect(websocket)

    # Send welcome message with connection info
    await manager.send_personal(
        websocket,
        {
            "type": "connected",
            "message": "Connected to LiLoRa backend",
            "active_connections": manager.connection_count,
        },
    )

    try:
        while True:
            # Keep connection alive and handle any client messages
            data = await websocket.receive_text()

            # Handle ping/pong for keepalive
            if data == "ping":
                await manager.send_personal(websocket, {"type": "pong"})
            else:
                # Echo or handle other client messages if needed
                logger.debug(f"Received from client: {data}")

    except WebSocketDisconnect:
        await manager.disconnect(websocket)
        logger.info("WebSocket client disconnected normally")
    except Exception as e:
        await manager.disconnect(websocket)
        logger.error(f"WebSocket error: {e}")


@router.get("/ws/status")
async def websocket_status():
    """Get WebSocket connection status."""
    return {
        "active_connections": manager.connection_count,
        "status": "ok",
    }
