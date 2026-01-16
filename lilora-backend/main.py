"""
LiLoRa Backend Service

FastAPI application for receiving LoRaWAN uplinks via webhook
and broadcasting decoded GPS data to WebSocket clients.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import settings
from routers import webhook_router, websocket_router

# Configure logging
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper()),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    logger.info("Starting LiLoRa Backend Service")
    logger.info(f"CORS origins: {settings.cors_origins_list}")
    yield
    logger.info("Shutting down LiLoRa Backend Service")


# Create FastAPI application
app = FastAPI(
    title="LiLoRa Backend",
    description="LoRaWAN range tracking webhook and WebSocket server",
    version="0.1.0",
    lifespan=lifespan,
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(webhook_router)
app.include_router(websocket_router)


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "LiLoRa Backend",
        "version": "0.1.0",
        "description": "LoRaWAN range tracking service",
        "endpoints": {
            "webhook_chirpstack": "/webhook/chirpstack",
            "webhook_ttn": "/webhook/ttn",
            "websocket": "/ws",
            "websocket_status": "/ws/status",
            "docs": "/docs",
        },
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring."""
    from services.websocket_manager import manager

    return {
        "status": "healthy",
        "websocket_connections": manager.connection_count,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=True,
    )
