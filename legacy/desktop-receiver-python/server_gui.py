"""
PhoneCam Server GUI - Minimalistic liquid glass design
"""
import tkinter as tk
from tkinter import ttk, messagebox
import threading
import sys
import io
import logging
from contextlib import redirect_stdout, redirect_stderr
import asyncio
from aiohttp import web
from server_highquality import create_app, pcs, virtual_cam
import pyvirtualcam
import platform

class ServerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("PhoneCam Server")
        self.root.geometry("400x350")
        self.root.resizable(False, False)
        
        self.server_running = False
        self.server_thread = None
        self.runner = None
        self.site = None
        self.server_loop = None
        
        # Liquid glass theme
        self.setup_theme()
        
        # Configure logging
        self.setup_logging()
        
        # Create UI
        self.create_widgets()
        
        # Check Unity Capture on startup
        self.root.after(100, self.check_unity_capture)
        
        # Set up window close handler
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
        
    def setup_theme(self):
        """Setup theme"""
        # Color palette
        self.colors = {
            'bg': '#f0f0f0',
            'card': '#ffffff',
            'accent': '#0078d4',
            'accent_hover': '#005a9e',
            'success': '#107c10',
            'error': '#d13438',
            'text': '#000000',
            'text_dim': '#666666',
            'border': '#d1d1d1',
        }
        
        self.root.configure(bg=self.colors['bg'])
    
    def setup_logging(self):
        """Configure logging to capture output"""
        pass  # No logging needed
    
    def check_unity_capture(self):
        """Check if Unity Capture is installed and warn if not"""
        try:
            # Try to create a temporary camera to verify Unity Capture works
            test_cam = pyvirtualcam.Camera(width=640, height=480, fps=30, backend='unitycapture')
            test_cam.close()
        except Exception as e:
            result = messagebox.askquestion(
                "Unity Capture Not Found",
                "Unity Capture virtual camera driver is not installed or not working.\n\n"
                "Without it, the virtual camera will not appear in OBS/Zoom/etc.\n\n"
                "Do you want to see installation instructions?",
                icon='warning'
            )
            
            if result == 'yes':
                messagebox.showinfo(
                    "Unity Capture Installation",
                    "To install Unity Capture:\n\n"
                    "1. Download from:\n"
                    "   https://github.com/schellingb/UnityCapture/releases\n\n"
                    "2. Extract the ZIP file\n\n"
                    "3. Right-click 'Install.cmd' and select\n"
                    "   'Run as Administrator'\n\n"
                    "4. Restart this application\n\n"
                    "Note: The installer must be run from the same\n"
                    "folder location each time (not portable)."
                )
        
    def create_widgets(self):
        """Create UI"""
        # Main container
        main_container = tk.Frame(self.root, bg=self.colors['bg'])
        main_container.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Title
        title = tk.Label(
            main_container,
            text="PhoneCam Server",
            font=("Segoe UI", 16, "bold"),
            bg=self.colors['bg'],
            fg=self.colors['text']
        )
        title.pack(pady=(0, 15))
        
        # Status card
        card = tk.Frame(
            main_container,
            bg=self.colors['card'],
            relief=tk.SOLID,
            bd=1
        )
        card.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        # Connection status
        status_header = tk.Label(
            card,
            text="Connection Status",
            font=("Segoe UI", 10, "bold"),
            bg=self.colors['card'],
            fg=self.colors['text']
        )
        status_header.pack(pady=(15, 5))
        
        self.status_label = tk.Label(
            card,
            text="Server Stopped",
            font=("Segoe UI", 12),
            bg=self.colors['card'],
            fg=self.colors['error']
        )
        self.status_label.pack(pady=(0, 10))
        
        # Server info
        self.info_label = tk.Label(
            card,
            text="http://0.0.0.0:8000",
            font=("Segoe UI", 9),
            bg=self.colors['card'],
            fg=self.colors['text_dim']
        )
        self.info_label.pack(pady=(0, 15))
        
        # Start/Stop button
        self.start_stop_btn = tk.Button(
            main_container,
            text="Start Server",
            font=("Segoe UI", 11, "bold"),
            bg=self.colors['accent'],
            fg="white",
            activebackground=self.colors['accent_hover'],
            activeforeground="white",
            command=self.toggle_server,
            height=2,
            cursor="hand2",
            relief=tk.FLAT,
            bd=0
        )
        self.start_stop_btn.pack(fill=tk.X, pady=(0, 10))
        
        # Credits
        credits_label = tk.Label(
            main_container,
            text="By ScSyn for all Streamers",
            font=("Segoe UI", 8),
            bg=self.colors['bg'],
            fg=self.colors['text_dim']
        )
        credits_label.pack()
        
        # Start monitoring
        self.monitor_connections()
        
    def monitor_connections(self):
        """Monitor connection status and update indicator"""
        if self.server_running:
            from server_highquality import connection_active
            if connection_active:
                self.status_label.config(text="Connected", fg=self.colors['success'])
            else:
                self.status_label.config(text="Waiting for Connection", fg=self.colors['accent'])
        else:
            self.status_label.config(text="Server Stopped", fg=self.colors['error'])
        
        # Check again in 500ms
        self.root.after(500, self.monitor_connections)
        
    def toggle_server(self):
        """Start or stop the server"""
        if not self.server_running:
            self.start_server()
        else:
            self.stop_server()
            
    def start_server(self):
        """Start the server in a background thread"""
        # Update UI
        self.server_running = True
        self.start_stop_btn.config(text="Stop Server", bg=self.colors['error'])
        
        # Start server in background thread
        self.server_thread = threading.Thread(target=self.run_server, daemon=True)
        self.server_thread.start()
        
    def run_server(self):
        """Run the server (called in background thread)"""
        try:
            # Create new event loop for this thread
            self.server_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self.server_loop)
            
            # Create app
            app = create_app(type('Args', (), {
                'host': '0.0.0.0',
                'port': 8000,
                'stun': 'stun:stun.l.google.com:19302'
            })())
            
            # Create and start runner
            self.runner = web.AppRunner(app)
            self.server_loop.run_until_complete(self.runner.setup())
            
            self.site = web.TCPSite(self.runner, '0.0.0.0', 8000)
            self.server_loop.run_until_complete(self.site.start())
            
            # Run until stopped
            self.server_loop.run_forever()
            
        except OSError as e:
            if e.errno == 10048 or "address already in use" in str(e).lower():
                self.root.after(0, lambda: messagebox.showerror(
                    "Port Already In Use",
                    "Port 8000 is already in use!\n\n"
                    "Another instance may be running, or the port is still closing.\n"
                    "Wait 30 seconds and try again, or close other instances."
                ))
            else:
                self.root.after(0, lambda: messagebox.showerror(
                    "Server Error",
                    f"Failed to start server:\n{str(e)}"
                ))
            self.root.after(0, lambda: self.force_stop())
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror(
                "Server Error",
                f"Failed to start server:\n{str(e)}"
            ))
            self.root.after(0, lambda: self.force_stop())
        finally:
            # Clean up loop
            if self.server_loop and not self.server_loop.is_closed():
                self.server_loop.close()
            
    def stop_server(self):
        """Stop the server"""
        if self.server_loop and self.server_thread and self.server_thread.is_alive():
            try:
                # Schedule cleanup in the server's event loop
                async def cleanup():
                    global pcs, virtual_cam
                    for pc in pcs:
                        await pc.close()
                    pcs.clear()
                    
                    if virtual_cam:
                        virtual_cam.close()
                        virtual_cam = None
                    
                    if self.site:
                        await self.site.stop()
                    if self.runner:
                        await self.runner.cleanup()
                
                # Run cleanup in the server loop and then stop it
                asyncio.run_coroutine_threadsafe(cleanup(), self.server_loop)
                
                # Give it a moment to cleanup
                import time
                time.sleep(0.5)
                
                # Stop the event loop
                self.server_loop.call_soon_threadsafe(self.server_loop.stop)
                
                # Wait for thread to finish
                self.server_thread.join(timeout=2.0)
                
            except Exception as e:
                pass
        
        # Update UI
        self.force_stop()
        
    def force_stop(self):
        """Force stop and update UI"""
        self.server_running = False
        self.start_stop_btn.config(text="Start Server", bg=self.colors['accent'])
        
    def on_closing(self):
        """Handle window close event"""
        if self.server_running:
            self.stop_server()
        self.root.destroy()


def main():
    root = tk.Tk()
    app = ServerGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
