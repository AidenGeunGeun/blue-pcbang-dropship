@echo off
:: Self-elevate to admin, then run setup.ps1 (window stays open so you can read output)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/k cd /d \"%~dp0\" && \"%~f0\"'"
    exit /b
)
cd /d "%~dp0"
powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
