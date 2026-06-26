@echo off
setlocal
cd /d "%~dp0"
set PUBLISH_DIR=build\windows\x64\runner\Release
rmdir /s /q build 2>nul
flutter build windows --release
if %errorlevel% neq 0 goto :error
echo --- 体积核验 ---
powershell -Command "$d='%PUBLISH_DIR%'; $mb='{0:N2}' -f ((Get-ChildItem $d -Recurse | Measure-Object Length -Sum).Sum/1MB); Write-Host "Windows Release 体积: $mb MB""
exit /b 0
:error
echo Publish failed.
exit /b 1
