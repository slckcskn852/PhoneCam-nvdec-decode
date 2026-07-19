#!/usr/bin/env python3
"""
PhoneCam RTSP Receiver - Receives H.264 stream over TCP and outputs to virtual camera

This server:
1. Listens for TCP connections from the Android app
2. Receives raw H.264 Annex B NAL units
3. Decodes using FFmpeg/PyAV
4. Outputs to Unity Capture virtual camera

Usage:
    python rtsp_receiver.py --host 0.0.0.0 --port 5000
"""

import argparse
import asyncio
import logging
import signal
import sys
import threading
import time
from typing import Optional

import av
import numpy as np

try:
    import pyvirtualcam
    PYVIRTUALCAM_AVAILABLE = True
except ImportError:
    PYVIRTUALCAM_AVAILABLE = False
    print("WARNING: pyvirtualcam not installed. Virtual camera output disabled.")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)


class H264Decoder:
    """Decodes H.264 Annex B stream using PyAV/FFmpeg"""
    
    def __init__(self):
        self.frame_count = 0
        self.start_time = time.time()
        self.hw_accel = None
        self.codec = None
        # Try NVDEC (GPU) first
        try:
            self.codec = av.CodecContext.create('h264_cuvid', 'r')
            self.hw_accel = "GPU (NVDEC)"
            logger.info("H.264 decoder initialized (PyAV, NVDEC GPU)")
        except Exception as e:
            logger.warning(f"NVDEC not available: {e}. Falling back to CPU decoding.")
            self.codec = av.CodecContext.create('h264', 'r')
            self.codec.thread_type = 'SLICE'
            self.codec.thread_count = 4
            self.hw_accel = "CPU (4 threads)"
            logger.info("H.264 decoder initialized (PyAV, 4 threads, low-latency)")
        
    def decode(self, data: bytes) -> list:
        """Decode H.264 data and return list of numpy BGR frames"""
        frames = []
        
        try:
            # Create packet from raw data
            packet = av.Packet(data)
            
            # Decode
            for frame in self.codec.decode(packet):
                # Convert to numpy BGR
                img = frame.to_ndarray(format='bgr24')
                frames.append(img)
                self.frame_count += 1
                
        except Exception as e:
            # Decoder errors are common during stream startup
            if self.frame_count > 0:
                logger.debug(f"Decode error: {e}")
                
        return frames
    
    def flush(self) -> list:
        """Flush decoder buffer"""
        frames = []
        try:
            for frame in self.codec.decode(None):
                img = frame.to_ndarray(format='bgr24')
                frames.append(img)
        except:
            pass
        return frames
    
    def get_stats(self) -> str:
        elapsed = time.time() - self.start_time
        fps = self.frame_count / elapsed if elapsed > 0 else 0
        return f"{self.frame_count} frames, {fps:.1f} fps"


class VirtualCameraOutput:
    """Outputs frames to Unity Capture virtual camera"""
    
    def __init__(self, width: int = 1920, height: int = 1080, fps: int = 60):
        self.width = width
        self.height = height
        self.fps = fps
        self.camera: Optional[pyvirtualcam.Camera] = None
        self.frame_count = 0
        
    def start(self) -> bool:
        """Initialize virtual camera"""
        if not PYVIRTUALCAM_AVAILABLE:
            logger.warning("pyvirtualcam not available")
            return False
            
        try:
            # Try Unity Capture first
            self.camera = pyvirtualcam.Camera(
                width=self.width,
                height=self.height,
                fps=self.fps,
                fmt=pyvirtualcam.PixelFormat.BGR,
                backend='unitycapture'
            )
            logger.info(f"Virtual camera started: {self.camera.device}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start virtual camera: {e}")
            logger.info("Make sure Unity Capture is installed:")
            logger.info("  1. Download from https://github.com/schellingb/UnityCapture/releases")
            logger.info("  2. Run Install.bat as Administrator")
            return False
    
    def send_frame(self, frame: np.ndarray):
        """Send frame to virtual camera"""
        if self.camera is None:
            return
            
        try:
            # Resize if needed
            if frame.shape[1] != self.width or frame.shape[0] != self.height:
                import cv2
                frame = cv2.resize(frame, (self.width, self.height))
            
            self.camera.send(frame)
            self.frame_count += 1
            
        except Exception as e:
            logger.error(f"Failed to send frame: {e}")
    
    def stop(self):
        """Close virtual camera"""
        if self.camera:
            self.camera.close()
            self.camera = None


class RTSPServer:
    """TCP server that receives H.264 stream from Android app"""
    
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.decoder = H264Decoder()
        self.virtual_cam = VirtualCameraOutput()
        self.running = False
        self.client_connected = False
        
    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Handle incoming client connection"""
        addr = writer.get_extra_info('peername')
        logger.info(f"Client connected: {addr}")
        self.client_connected = True
        
        # Start virtual camera
        if not self.virtual_cam.start():
            logger.warning("Virtual camera not available, frames will be decoded but not output")
        
        # Reset decoder for new stream
        self.decoder = H264Decoder()
        
        buffer = bytearray()
        last_log_time = time.time()
        bytes_received = 0
        
        try:
            while self.running:
                # Read data from socket
                try:
                    data = await asyncio.wait_for(reader.read(65536), timeout=5.0)
                except asyncio.TimeoutError:
                    continue
                    
                if not data:
                    logger.info("Client disconnected")
                    break
                
                buffer.extend(data)
                bytes_received += len(data)
                
                # Find and process complete NAL units
                # H.264 Annex B uses 0x00000001 as start code
                while True:
                    # Find first start code
                    start_pos = self._find_start_code(buffer, 0)
                    if start_pos < 0:
                        break
                    
                    # Find next start code
                    next_pos = self._find_start_code(buffer, start_pos + 4)
                    if next_pos < 0:
                        # No complete NAL yet, wait for more data
                        break
                    
                    # Extract NAL unit (including start code)
                    nal_data = bytes(buffer[start_pos:next_pos])
                    buffer = buffer[next_pos:]
                    
                    # Decode
                    frames = self.decoder.decode(nal_data)
                    for frame in frames:
                        self.virtual_cam.send_frame(frame)
                
                # Log stats periodically
                now = time.time()
                if now - last_log_time >= 5.0:
                    mbps = (bytes_received * 8) / (1024 * 1024 * (now - last_log_time))
                    logger.info(f"Receiving: {mbps:.1f} Mbps, {self.decoder.get_stats()}")
                    bytes_received = 0
                    last_log_time = now
                    
        except Exception as e:
            logger.error(f"Client error: {e}")
        finally:
            self.client_connected = False
            self.virtual_cam.stop()
            writer.close()
            try:
                await writer.wait_closed()
            except:
                pass
            logger.info(f"Client session ended: {self.decoder.get_stats()}")
    
    def _find_start_code(self, data: bytearray, start: int) -> int:
        """Find H.264 Annex B start code (0x00000001) in data using optimized search"""
        # Use bytes.find() which is implemented in C and much faster than Python loop
        START_CODE = b'\x00\x00\x00\x01'
        pos = bytes(data).find(START_CODE, start)
        return pos
    
    async def start(self):
        """Start the TCP server"""
        self.running = True
        
        server = await asyncio.start_server(
            self.handle_client,
            self.host,
            self.port
        )
        
        addrs = ', '.join(str(sock.getsockname()) for sock in server.sockets)
        logger.info(f"Server listening on {addrs}")
        
        print("\n" + "=" * 60)
        print("PhoneCam RTSP Receiver (H.264 over TCP)")
        print("=" * 60)
        print(f"Listening on: {self.host}:{self.port}")
        print(f"\nOn your Android phone, enter:")
        print(f"  {self._get_local_ip()}:{self.port}")
        print("\nPress Ctrl+C to stop")
        print("=" * 60 + "\n")
        
        async with server:
            await server.serve_forever()
    
    def _get_local_ip(self) -> str:
        """Get local IP address"""
        import socket
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "YOUR_PC_IP"
    
    def stop(self):
        """Stop the server"""
        self.running = False
        self.virtual_cam.stop()


def main():
    parser = argparse.ArgumentParser(description='PhoneCam RTSP Receiver')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    parser.add_argument('--port', type=int, default=5000, help='Port to listen on')
    args = parser.parse_args()
    
    server = RTSPServer(args.host, args.port)
    print("PhoneCam RTSP Receiver starting...")
    print(f"  Decoder: {server.decoder.hw_accel}")
    print(f"  Virtual Camera: {'Available' if PYVIRTUALCAM_AVAILABLE else 'Not available'}")
    
    # Handle Ctrl+C
    def signal_handler(sig, frame):
        logger.info("Shutting down...")
        server.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Run server
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        server.stop()


if __name__ == '__main__':
    main()
