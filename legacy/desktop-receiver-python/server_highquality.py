"""
High-performance virtual camera server using shared memory and minimal compression.
Receives WebRTC stream and outputs to a virtual camera device via pyvirtualcam.
Uses NVDEC hardware-accelerated decoding by patching aiortc's decoder.
"""
import argparse
import asyncio
import logging
import time
from typing import List, Optional
import numpy as np
import av
from av import VideoFrame

from aiohttp import web
from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceServer, RTCConfiguration
from aiortc.contrib.media import MediaBlackhole
from aiortc.codecs import get_decoder
from aiortc.codecs.h264 import H264Decoder
import pyvirtualcam

logging.basicConfig(level=logging.INFO)
LOG = logging.getLogger("receiver")

# Patch H264Decoder to use NVDEC
class NvdecH264Decoder(H264Decoder):
    """H264 decoder using NVDEC hardware acceleration."""
    
    def __init__(self):
        self._codec = None
        self._codec_context = None
        
    def decode(self, encoded_frame):
        """Decode using NVDEC (GPU only, no CPU fallback)."""
        if self._codec_context is None:
            # Initialize NVDEC decoder
            codec = av.codec.Codec("h264_cuvid", "r")
            self._codec_context = codec.create()
            LOG.info("Initialized NVDEC H264 decoder")
        
        try:
            packet = av.Packet(encoded_frame)
            frames = self._codec_context.decode(packet)
            return [VideoFrame.from_ndarray(frame.to_ndarray(format="yuv420p"), format="yuv420p") for frame in frames]
        except Exception as e:
            LOG.error(f"Decode error: {e}")
            return []

# Monkey-patch aiortc to use our NVDEC decoder
original_get_decoder = get_decoder

def patched_get_decoder(codec):
    """Return NVDEC decoder for H264, default for others."""
    if codec.name == "H264":
        return NvdecH264Decoder()
    return original_get_decoder(codec)

# Apply the patch
import aiortc.codecs
aiortc.codecs.get_decoder = patched_get_decoder

pcs: List[RTCPeerConnection] = []
virtual_cam: Optional[pyvirtualcam.Camera] = None
connection_active: bool = False  # Track if a connection is active


async def consume_video(track):
    """Read frames from track and send directly to virtual camera with NVDEC hardware decoding."""
    global virtual_cam
    
    # Target frame timing for CPU throttling (16.67ms for 60fps)
    target_frame_time = 1.0 / 60.0
    last_frame_time = 0
    
    try:
        LOG.info("Video track started, waiting for first frame to initialize camera...")
        LOG.info("Using NVDEC hardware decoder (if available)")
        
        # Get first frame to determine resolution
        first_frame = await track.recv()
        img = first_frame.to_ndarray(format="bgr24")
        height, width = img.shape[:2]
        
        # Validate frame data
        if img.size == 0 or not img.data.contiguous:
            LOG.error("Invalid frame data received")
            return
        
        # Initialize virtual camera with actual resolution from stream
        # Use 60 FPS to match the phone's 60fps output
        virtual_cam = pyvirtualcam.Camera(
            width=width, 
            height=height, 
            fps=60,
            fmt=pyvirtualcam.PixelFormat.BGR,
            backend='unitycapture'
        )
        LOG.info(f"Virtual camera initialized (Unity Capture): {width}x{height}@60fps device={virtual_cam.device}")
        
        # Send first frame
        virtual_cam.send(img)
        
        # Stream remaining frames - handle resolution changes
        frame_count = 0
        current_resolution = (width, height)
        
        while True:
            frame = await track.recv()
            
            # Validate frame before conversion
            if frame is None:
                LOG.warning("Received null frame, skipping")
                continue
                
            img = frame.to_ndarray(format="bgr24")
            h, w = img.shape[:2]
            
            # Validate converted frame
            if img.size == 0 or w == 0 or h == 0:
                LOG.warning("Invalid frame dimensions, skipping")
                continue
            
            # Check if resolution changed (WebRTC adaptive bitrate)
            if (w, h) != current_resolution:
                LOG.warning(f"Resolution changed from {current_resolution[0]}x{current_resolution[1]} to {w}x{h}")
                LOG.info("Reinitializing virtual camera with new resolution...")
                
                # Close old camera
                virtual_cam.close()
                
                # Reinitialize with new resolution
                virtual_cam = pyvirtualcam.Camera(
                    width=w, 
                    height=h, 
                    fps=60,
                    fmt=pyvirtualcam.PixelFormat.BGR,
                    backend='unitycapture'
                )
                LOG.info(f"Virtual camera reinitialized (Unity Capture): {w}x{h}@60fps")
                
                current_resolution = (w, h)
            
            # Ensure frame is contiguous before sending
            if not img.data.contiguous:
                img = np.ascontiguousarray(img)
            
            # Throttle to prevent CPU spinning if frames arrive faster than target rate
            current_time = time.perf_counter()
            elapsed = current_time - last_frame_time
            if elapsed < target_frame_time:
                await asyncio.sleep(target_frame_time - elapsed)
            last_frame_time = time.perf_counter()
            
            virtual_cam.send(img)
            frame_count += 1
                
    except asyncio.CancelledError:
        LOG.info("Video track cancelled")
    except Exception as e:
        LOG.error(f"Video consumer error: {e}", exc_info=True)
    finally:
        if virtual_cam:
            virtual_cam.close()
            LOG.info("Virtual camera closed")


async def consume_audio(track):
    """Discard audio for now."""
    try:
        while True:
            await track.recv()
    except asyncio.CancelledError:
        pass


async def offer(request: web.Request):
    global connection_active
    
    # Reject if a connection is already active
    if connection_active:
        LOG.warning("Connection rejected - already have an active connection")
        return web.json_response(
            {"error": "Server busy - already handling a connection"},
            status=503
        )
    
    params = await request.json()
    offer_sdp = params["sdp"]
    offer_type = params.get("type", "offer")

    pc = RTCPeerConnection(request.app["rtc_config"])
    pcs.append(pc)
    connection_active = True
    LOG.info("Created PeerConnection %s (now active)", id(pc))

    @pc.on("connectionstatechange")
    async def on_connectionstatechange():
        global connection_active
        LOG.info("Connection state: %s", pc.connectionState)
        if pc.connectionState in ["failed", "closed"]:
            LOG.info("Connection ended - ready for new connections")
            connection_active = False
            if pc in pcs:
                pcs.remove(pc)

    @pc.on("track")
    def on_track(track):
        LOG.info("Track %s kind=%s", track.id, track.kind)
        if track.kind == "video":
            asyncio.create_task(consume_video(track))
        else:
            asyncio.create_task(consume_audio(track))

        @track.on("ended")
        async def on_ended():
            LOG.info("Track %s ended", track.id)

    await pc.setRemoteDescription(RTCSessionDescription(sdp=offer_sdp, type=offer_type))
    
    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)
    LOG.info("Answer created for %s", id(pc))

    return web.json_response({"sdp": pc.localDescription.sdp, "type": pc.localDescription.type})


async def status(request: web.Request):
    """Simple status endpoint"""
    return web.json_response({
        "peers": len(pcs),
        "connection_active": connection_active,
        "camera_active": virtual_cam is not None,
        "camera_device": virtual_cam.device if virtual_cam else None
    })


async def on_shutdown(app: web.Application):
    global connection_active, virtual_cam
    
    LOG.info("Shutting down, closing %d peer(s)", len(pcs))
    coros = [pc.close() for pc in pcs]
    if coros:
        await asyncio.gather(*coros, return_exceptions=True)
    pcs.clear()
    connection_active = False
    
    if virtual_cam:
        virtual_cam.close()
        virtual_cam = None


def create_app(args: argparse.Namespace) -> web.Application:
    stun_servers = []
    if args.stun:
        stun_servers.append(RTCIceServer(args.stun))
    rtc_config = RTCConfiguration(iceServers=stun_servers)

    app = web.Application()
    app["rtc_config"] = rtc_config
    app.router.add_post("/offer", offer)
    app.router.add_get("/status", status)
    app.on_shutdown.append(on_shutdown)
    return app


def main():
    parser = argparse.ArgumentParser(
        description="PhoneCam high-quality virtual camera receiver"
    )
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind (default: 8000)")
    parser.add_argument("--stun", help="STUN server URL (e.g., stun:stun.l.google.com:19302)")
    args = parser.parse_args()

    app = create_app(args)
    
    print("=" * 70)
    print("PhoneCam Virtual Camera Server (NVDEC GPU Decoding)")
    print("=" * 70)
    print(f"Server listening on: http://{args.host}:{args.port}")
    print(f"Status endpoint: http://{args.host}:{args.port}/status")
    print()
    print("REQUIRES:")
    print("  - Unity Capture virtual camera driver")
    print("  - NVIDIA GPU with NVDEC support")
    print()
    print("Features:")
    print("  - 1920x1080@60fps capture")
    print("  - Bitrate: 5-100 Mbps")
    print("  - NVDEC GPU-accelerated H.264 decoding (NVIDIA GPUs only)")
    print("  - Dynamic resolution handling")
    print("=" * 70)
    
    web.run_app(app, host=args.host, port=args.port, access_log=None)


if __name__ == "__main__":
    main()