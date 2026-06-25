@echo off
set PUBLISH_DIR=CodingPlanTimeRefresh\bin\Release\net10.0-windows10.0.19041.0\win-x64\publish
rmdir /s /q "%PUBLISH_DIR%" 2>nul
dotnet publish CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0 -c Release -r win-x64
if %errorlevel% neq 0 goto :error
echo Cleaning up language folders...
for /d %%d in ("%PUBLISH_DIR%\*-*") do (
    echo %%~nd | findstr /i /r "^en ^zh-CN ^zh-Hans ^zh-Hant ^zh-TW$" >nul || (
        rmdir /s /q "%%d" 2>nul
    )
)
for /d %%d in ("%PUBLISH_DIR%\??") do (
    echo %%~nd | findstr /i /r "^en$" >nul || (
        rmdir /s /q "%%d" 2>nul
    )
)
echo Cleaning up unused files...
del /q "%PUBLISH_DIR%\appiconLargeTile*" "%PUBLISH_DIR%\appiconLogo*" "%PUBLISH_DIR%\appiconMediumTile*" "%PUBLISH_DIR%\appiconSmallTile*" "%PUBLISH_DIR%\appiconStoreLogo*" "%PUBLISH_DIR%\appiconWideTile*" "%PUBLISH_DIR%\splashSplashScreen*" "%PUBLISH_DIR%\dotnet_bot*" "%PUBLISH_DIR%\AboutAssets.txt" 2>nul
pause
exit /b 0
:error
echo Publish failed.
pause
