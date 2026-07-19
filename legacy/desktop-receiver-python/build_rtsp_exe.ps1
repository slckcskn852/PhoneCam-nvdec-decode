# Build script for PhoneCam RTSP Receiver GUI executable
# Run this to create a standalone .exe file

Write-Host "Building PhoneCam RTSP Receiver..." -ForegroundColor Green
Write-Host ""

# Activate virtual environment if exists
if (Test-Path ".\.venv\Scripts\Activate.ps1") {
    Write-Host "Activating virtual environment..." -ForegroundColor Yellow
    .\.venv\Scripts\Activate.ps1
}

# Install pyinstaller if needed
Write-Host "Installing build dependencies..." -ForegroundColor Yellow
python -m pip install pyinstaller --quiet

# Build the executable
Write-Host ""
Write-Host "Building executable..." -ForegroundColor Yellow
pyinstaller --name "PhoneCam-RTSP-Receiver" `
    --onefile `
    --windowed `
    --icon=NONE `
    --hidden-import=av `
    --hidden-import=pyvirtualcam `
    --hidden-import=numpy `
    --hidden-import=tkinter `
    --hidden-import=threading `
    --hidden-import=socket `
    --collect-all=av `
    --collect-all=pyvirtualcam `
    rtsp_receiver_gui.py

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Build successful!" -ForegroundColor Green
    Write-Host "Executable location: dist\PhoneCam-RTSP-Receiver.exe" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now:" -ForegroundColor Yellow
    Write-Host "  1. Double-click dist\PhoneCam-RTSP-Receiver.exe to launch" -ForegroundColor White
    Write-Host "  2. Copy the .exe to any Windows PC with Unity Capture installed" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "Build failed!" -ForegroundColor Red
}
