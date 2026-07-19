#!/usr/bin/env python3
"""
PhoneCam RTSP Receiver GUI - Receives H.264 stream and outputs to virtual camera

Features:
- Modern GUI with connection status
- Unity Capture virtual camera output
- Real-time FPS and bitrate display
- One-click start/stop
- Rotation support (receives rotation from phone)
- Low-latency CPU decoding with multithreading
"""

import logging
import os
import socket
import sys
import threading
import time
import tkinter as tk
from tkinter import ttk
from typing import Optional

import numpy as np
import cv2

# PyAV for H.264 decoding
try:
    import av
    PYAV_AVAILABLE = True
except ImportError:
    PYAV_AVAILABLE = False

try:
    import pyvirtualcam
    PYVIRTUALCAM_AVAILABLE = True
except ImportError:
    PYVIRTUALCAM_AVAILABLE = False

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

# Rotation protocol: 0xFF + 'R' + 'T' + rotation_value + 0xAA (5 bytes total)
# Using non-ASCII prefix/suffix to avoid false positives in H.264 data
ROTATION_MAGIC_PREFIX = b'\xffRT'
ROTATION_SUFFIX = 0xAA


class H264StreamDecoder:
    """Low-latency H.264 decoder using PyAV with multithreading"""
    
    def __init__(self):
        self.frame_count = 0
        self.start_time = time.time()
        self.hw_accel = None
        self.codec = None
        # Try NVDEC (GPU) first, with all low-latency options
        try:
            self.codec = av.CodecContext.create('h264_cuvid', 'r')
            self.codec.options = {'flags': 'low_delay', 'flags2': 'fast', 'delay': '0', 'fflags': 'nobuffer'}
            self.hw_accel = "GPU (NVDEC)"
            logger.info("H.264 decoder initialized (PyAV, NVDEC GPU, low-latency)")
        except Exception as e:
            logger.warning(f"NVDEC not available: {e}. Falling back to CPU decoding.")
            self.codec = av.CodecContext.create('h264', 'r')
            self.codec.thread_type = 'SLICE'
            self.codec.thread_count = 8
            self.codec.options = {'flags': 'low_delay', 'flags2': 'fast', 'delay': '0', 'fflags': 'nobuffer'}
            self.hw_accel = "CPU (8 threads)"
            logger.info("H.264 decoder initialized (PyAV, 8 threads, low-latency)")
        
    def decode(self, data: bytes) -> list:
        """Decode H.264 NAL unit data and return BGR frames"""
        frames = []
        try:
            packet = av.Packet(data)
            for frame in self.codec.decode(packet):
                img = frame.to_ndarray(format='bgr24')
                frames.append(img)
                self.frame_count += 1
        except Exception as e:
            pass  # Skip decode errors (common with streaming)
        return frames
    
    def close(self):
        pass  # Nothing to clean up
    
    @property
    def fps(self) -> float:
        elapsed = time.time() - self.start_time
        return self.frame_count / elapsed if elapsed > 0 else 0


class VirtualCamera:
    """Unity Capture virtual camera wrapper"""
    
    def __init__(self, width=1920, height=1080, fps=60):
        self.width = width
        self.height = height
        self.fps = fps
        self.camera = None
        
    def start(self) -> bool:
        if not PYVIRTUALCAM_AVAILABLE:
            return False
        try:
            self.camera = pyvirtualcam.Camera(
                width=self.width, height=self.height, fps=self.fps,
                fmt=pyvirtualcam.PixelFormat.BGR, backend='unitycapture'
            )
            logger.info(f"Virtual camera: {self.camera.device}")
            return True
        except Exception as e:
            logger.error(f"Virtual camera failed: {e}")
            return False
    
    def send(self, frame: np.ndarray):
        if self.camera:
            if frame.shape[1] != self.width or frame.shape[0] != self.height:
                import cv2
                frame = cv2.resize(frame, (self.width, self.height))
            self.camera.send(frame)
    
    def stop(self):
        if self.camera:
            self.camera.close()
            self.camera = None


class StreamServer:
    """TCP server for receiving H.264 stream"""
    
    def __init__(self, port: int, status_callback, stats_callback, decoder_callback=None):
        self.port = port
        self.status_callback = status_callback
        self.stats_callback = stats_callback
        self.decoder_callback = decoder_callback
        self.running = False
        self.server_socket = None
        self.client_socket = None
        self.decoder = None
        self.virtual_cam = None
        self.thread = None
        
    def start(self):
        self.running = True
        self.thread = threading.Thread(target=self._run_server, daemon=True)
        self.thread.start()
        
    def stop(self):
        self.running = False
        if self.client_socket:
            try:
                self.client_socket.close()
            except:
                pass
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
                
    def _run_server(self):
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(1)
            self.server_socket.settimeout(1.0)
            
            local_ip = self._get_local_ip()
            self.status_callback(f"Waiting for connection on {local_ip}:{self.port}")
            
            while self.running:
                try:
                    self.client_socket, addr = self.server_socket.accept()
                    self.client_socket.settimeout(2.0)
                    # Low-latency socket options
                    self.client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    self.client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8192)  # Lower buffer for less latency
                    
                    logger.info(f"Client connected: {addr}")
                    self.status_callback(f"Connected: {addr[0]}")
                    
                    self._handle_client()
                    
                except socket.timeout:
                    continue
                except Exception as e:
                    if self.running:
                        logger.error(f"Accept error: {e}")
                        
        except Exception as e:
            logger.error(f"Server error: {e}")
            self.status_callback(f"Error: {e}")
        finally:
            if self.server_socket:
                self.server_socket.close()
            self.status_callback("Server stopped")
    
    def _handle_client(self):
        self.decoder = H264StreamDecoder()
        self.virtual_cam = VirtualCamera()
        
        if not self.virtual_cam.start():
            self.status_callback("Virtual camera failed! Install Unity Capture")
        
        # Show decoder type
        decoder_info = self.decoder.hw_accel if self.decoder.hw_accel else "CPU (Software)"
        self.status_callback("Connected")
        if self.decoder_callback:
            self.decoder_callback(f"Decoder: {decoder_info}")
        
        buffer = bytearray()
        bytes_received = 0
        last_stats_time = time.time()
        current_rotation = 0  # Rotation in degrees (0, 90, 180, 270)
        
        try:
            while self.running:
                try:
                    # Smaller recv for lower latency (process data sooner)
                    data = self.client_socket.recv(32768)
                except socket.timeout:
                    continue
                    
                if not data:
                    break
                    
                buffer.extend(data)
                bytes_received += len(data)
                
                # Check for rotation messages in the buffer
                # Protocol: 0xFF + 'R' + 'T' + rotation_value + 0xAA (5 bytes total)
                while True:
                    rot_idx = buffer.find(ROTATION_MAGIC_PREFIX)
                    if rot_idx >= 0 and rot_idx + 5 <= len(buffer):
                        # Found potential rotation message, verify suffix
                        rotation_value = buffer[rot_idx + 3]
                        suffix_byte = buffer[rot_idx + 4]
                        
                        # Validate: rotation must be 0-3 and suffix must be 0xAA
                        if rotation_value <= 3 and suffix_byte == ROTATION_SUFFIX:
                            current_rotation = rotation_value * 90  # 0, 90, 180, or 270
                            logger.info(f"Rotation updated: {current_rotation} degrees")
                            # Remove rotation message from buffer
                            buffer = buffer[:rot_idx] + buffer[rot_idx + 5:]
                        else:
                            # False positive - pattern appeared in video data
                            # Just skip past the prefix to continue searching
                            buffer = buffer[:rot_idx] + buffer[rot_idx + 3:]
                    else:
                        break
                
                # Process NAL units
                while True:
                    start = self._find_start_code(buffer, 0)
                    if start < 0:
                        break
                    next_start = self._find_start_code(buffer, start + 4)
                    if next_start < 0:
                        break
                    
                    nal_data = bytes(buffer[start:next_start])
                    buffer = buffer[next_start:]
                    
                    frames = self.decoder.decode(nal_data)
                    for frame in frames:
                        # Apply rotation if needed
                        if current_rotation != 0:
                            frame = self._rotate_frame(frame, current_rotation)
                        self.virtual_cam.send(frame)
                
                # Update stats
                now = time.time()
                if now - last_stats_time >= 1.0:
                    mbps = (bytes_received * 8) / (1024 * 1024)
                    rot_str = f" | Rot: {current_rotation}°" if current_rotation != 0 else ""
                    self.stats_callback(f"{self.decoder.fps:.1f} fps | {mbps:.1f} Mbps{rot_str}")
                    bytes_received = 0
                    last_stats_time = now
                    
        except Exception as e:
            if self.running:
                logger.error(f"Client error: {e}")
        finally:
            self.virtual_cam.stop()
            if self.client_socket:
                self.client_socket.close()
            self.status_callback("Disconnected - waiting for connection...")
            self.stats_callback("")
    
    def _rotate_frame(self, frame: np.ndarray, degrees: int) -> np.ndarray:
        """Rotate frame by specified degrees (90, 180, 270)"""
        if degrees == 90:
            return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
        elif degrees == 180:
            return cv2.rotate(frame, cv2.ROTATE_180)
        elif degrees == 270:
            return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
        return frame
    
    def _find_start_code(self, data: bytearray, start: int) -> int:
        # Use bytes.find() which is implemented in C - much faster than Python loop
        START_CODE = b'\x00\x00\x00\x01'
        return bytes(data).find(START_CODE, start)
    
    def _get_local_ip(self) -> str:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "127.0.0.1"


class PhoneCamGUI:
    """Main GUI application with modern Windows dark theme"""
    
    # Color scheme
    BG_DARK = '#1e1e1e'
    BG_CARD = '#2d2d2d'
    BG_HOVER = '#3d3d3d'
    ACCENT = '#0078d4'
    ACCENT_HOVER = '#1a86d9'
    TEXT = '#ffffff'
    TEXT_DIM = '#888888'
    SUCCESS = '#4ec9b0'
    WARNING = '#dcdcaa'
    ERROR = '#f14c4c'
    
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("PhoneCam Receiver")
        self.root.geometry("400x400")
        self.root.resizable(False, False)
        self.root.configure(bg=self.BG_DARK)
        
        # Remove default title bar styling on Windows
        try:
            from ctypes import windll, byref, sizeof, c_int
            HWND = windll.user32.GetParent(self.root.winfo_id())
            # Enable dark mode title bar
            DWMWA_USE_IMMERSIVE_DARK_MODE = 20
            windll.dwmapi.DwmSetWindowAttribute(HWND, DWMWA_USE_IMMERSIVE_DARK_MODE, byref(c_int(1)), sizeof(c_int))
        except:
            pass
        
        # Server
        self.server = None
        self.port = 5000
        self.is_running = False
        
        self._create_styles()
        self._create_ui()
        self._update_connection_info()
        
    def _create_styles(self):
        """Configure ttk styles for dark theme"""
        style = ttk.Style()
        style.theme_use('clam')
        
        # Frame styles
        style.configure('Dark.TFrame', background=self.BG_DARK)
        style.configure('Card.TFrame', background=self.BG_CARD)
        
        # Label styles
        style.configure('Title.TLabel', 
                       background=self.BG_DARK, 
                       foreground=self.TEXT,
                       font=('Segoe UI', 18, 'bold'))
        style.configure('Subtitle.TLabel',
                       background=self.BG_DARK,
                       foreground=self.TEXT_DIM,
                       font=('Segoe UI', 9))
        style.configure('Dark.TLabel',
                       background=self.BG_CARD,
                       foreground=self.TEXT,
                       font=('Segoe UI', 10))
        style.configure('IP.TLabel',
                       background=self.BG_CARD,
                       foreground=self.ACCENT,
                       font=('Consolas', 14, 'bold'))
        style.configure('Status.TLabel',
                       background=self.BG_CARD,
                       foreground=self.TEXT_DIM,
                       font=('Segoe UI', 10))
        style.configure('Stats.TLabel',
                       background=self.BG_CARD,
                       foreground=self.SUCCESS,
                       font=('Consolas', 11))
        style.configure('Warning.TLabel',
                       background=self.BG_DARK,
                       foreground=self.WARNING,
                       font=('Segoe UI', 9))
        
        # Button styles
        style.configure('Accent.TButton',
                       background=self.ACCENT,
                       foreground=self.TEXT,
                       font=('Segoe UI', 10, 'bold'),
                       padding=(20, 10))
        style.map('Accent.TButton',
                 background=[('active', self.ACCENT_HOVER), ('pressed', self.ACCENT)])
        
        style.configure('Secondary.TButton',
                       background=self.BG_CARD,
                       foreground=self.TEXT,
                       font=('Segoe UI', 10),
                       padding=(20, 10))
        style.map('Secondary.TButton',
                 background=[('active', self.BG_HOVER)])
        
    def _create_ui(self):
        # Main container
        main = ttk.Frame(self.root, style='Dark.TFrame', padding=24)
        main.pack(fill=tk.BOTH, expand=True)
        
        # Header
        ttk.Label(main, text="PhoneCam", style='Title.TLabel').pack(anchor=tk.W)
        ttk.Label(main, text="Virtual Camera Receiver", style='Subtitle.TLabel').pack(anchor=tk.W, pady=(0, 20))
        
        # Connection card
        card = tk.Frame(main, bg=self.BG_CARD, padx=16, pady=14)
        card.pack(fill=tk.X, pady=(0, 12))
        
        # IP Address display
        ip_header = tk.Label(card, text="CONNECT TO", bg=self.BG_CARD, fg=self.TEXT_DIM, 
                            font=('Segoe UI', 8), anchor='w')
        ip_header.pack(fill=tk.X)
        
        self.ip_label = tk.Label(card, text="Loading...", bg=self.BG_CARD, fg=self.ACCENT,
                                 font=('Consolas', 16, 'bold'), anchor='w')
        self.ip_label.pack(fill=tk.X, pady=(2, 0))
        
        # Status card
        status_card = tk.Frame(main, bg=self.BG_CARD, padx=16, pady=12)
        status_card.pack(fill=tk.X, pady=(0, 16))
        
        status_header = tk.Label(status_card, text="STATUS", bg=self.BG_CARD, fg=self.TEXT_DIM,
                                font=('Segoe UI', 8), anchor='w')
        status_header.pack(fill=tk.X)
        
        self.status_label = tk.Label(status_card, text="Ready", bg=self.BG_CARD, fg=self.TEXT,
                                     font=('Segoe UI', 11), anchor='w')
        self.status_label.pack(fill=tk.X, pady=(2, 0))
        
        self.stats_label = tk.Label(status_card, text="", bg=self.BG_CARD, fg=self.SUCCESS,
                                    font=('Consolas', 10), anchor='w')
        self.stats_label.pack(fill=tk.X)
        
        self.decoder_label = tk.Label(status_card, text="", bg=self.BG_CARD, fg=self.TEXT_DIM,
                                      font=('Segoe UI', 9), anchor='w')
        self.decoder_label.pack(fill=tk.X)
        
        # Buttons
        btn_frame = tk.Frame(main, bg=self.BG_DARK)
        btn_frame.pack(fill=tk.X, pady=(4, 0))
        
        self.start_btn = tk.Button(btn_frame, text="Start Server", 
                                   bg=self.ACCENT, fg=self.TEXT,
                                   activebackground=self.ACCENT_HOVER, activeforeground=self.TEXT,
                                   font=('Segoe UI', 10, 'bold'),
                                   relief='flat', cursor='hand2',
                                   padx=20, pady=8,
                                   command=self._toggle_server)
        self.start_btn.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 6))
        
        quit_btn = tk.Button(btn_frame, text="Quit",
                            bg=self.BG_CARD, fg=self.TEXT,
                            activebackground=self.BG_HOVER, activeforeground=self.TEXT,
                            font=('Segoe UI', 10),
                            relief='flat', cursor='hand2',
                            padx=20, pady=8,
                            command=self._quit)
        quit_btn.pack(side=tk.RIGHT, expand=True, fill=tk.X, padx=(6, 0))
        
        # Virtual camera warning
        if not PYVIRTUALCAM_AVAILABLE:
            warn = tk.Label(main, text="⚠ Virtual camera not available", 
                           bg=self.BG_DARK, fg=self.WARNING,
                           font=('Segoe UI', 9))
            warn.pack(pady=(12, 0))
    
    def _update_connection_info(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            self.ip_label.config(text=f"{ip}:{self.port}")
        except:
            self.ip_label.config(text="Unable to detect IP")
    
    def _toggle_server(self):
        if self.server is None:
            self._start_server()
        else:
            self._stop_server()
    
    def _start_server(self):
        self.server = StreamServer(
            self.port,
            lambda s: self.root.after(0, lambda: self._update_status(s)),
            lambda s: self.root.after(0, lambda: self.stats_label.config(text=s)),
            lambda s: self.root.after(0, lambda: self.decoder_label.config(text=s))
        )
        self.server.start()
        self.is_running = True
        self.start_btn.config(text="Stop Server", bg=self.ERROR, activebackground='#ff6b6b')
        self.status_label.config(text="Starting...", fg=self.TEXT)
        self.decoder_label.config(text="")
    
    def _stop_server(self):
        if self.server:
            self.server.stop()
            self.server = None
        self.is_running = False
        self.start_btn.config(text="Start Server", bg=self.ACCENT, activebackground=self.ACCENT_HOVER)
        self.status_label.config(text="Stopped", fg=self.TEXT_DIM)
        self.stats_label.config(text="")
        self.decoder_label.config(text="")
    
    def _update_status(self, status: str):
        self.status_label.config(text=status)
        # Color code status
        if "Connected" in status:
            self.status_label.config(fg=self.SUCCESS)
        elif "Waiting" in status:
            self.status_label.config(fg=self.TEXT)
        elif "Error" in status or "failed" in status.lower():
            self.status_label.config(fg=self.ERROR)
        else:
            self.status_label.config(fg=self.TEXT)
    
    def _quit(self):
        self._stop_server()
        self.root.quit()
    
    def run(self):
        # Center window on screen
        self.root.update_idletasks()
        x = (self.root.winfo_screenwidth() - self.root.winfo_width()) // 2
        y = (self.root.winfo_screenheight() - self.root.winfo_height()) // 2
        self.root.geometry(f"+{x}+{y}")
        self.root.mainloop()


def main():
    # Check dependencies
    if not PYAV_AVAILABLE:
        print("ERROR: PyAV not installed!")
        print("Install with: pip install av")
        sys.exit(1)
    
    print("PhoneCam Receiver starting...")
    print(f"  Decoder: PyAV CPU (8 threads, low-latency)")
    print(f"  Virtual Camera: {'Available' if PYVIRTUALCAM_AVAILABLE else 'Not available'}")
    
    if not PYVIRTUALCAM_AVAILABLE:
        print("WARNING: pyvirtualcam not installed. Virtual camera output disabled.")
        print("Install with: pip install pyvirtualcam")
    
    app = PhoneCamGUI()
    app.run()


if __name__ == '__main__':
    main()
