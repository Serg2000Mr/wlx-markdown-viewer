@echo off
echo ========================================
echo WebView2 Plugin Fix Script
echo ========================================
echo.
echo PROBLEM IDENTIFIED:
echo The Process Monitor log shows that WebView2Loader.dll is missing
echo from the runtimes\win-x64\native\ directory in the installed plugin.
echo.
echo This causes the plugin to fail with:
echo "Не удается подключить плагин. Возможно, для работы плагина требуются DLL-файлы, отсутствующие на вашей системе"
echo.

echo Checking current plugin installation directory...
if not exist "runtimes\win-x64\native\" (
    echo Creating missing directory structure...
    mkdir "runtimes\win-x64\native" 2>nul
)

echo Checking for WebView2Loader.dll in GitHubRelease...
if exist "GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll" (
    echo [FOUND] WebView2Loader.dll in GitHubRelease folder
    echo.
    echo Copying WebView2Loader.dll to correct location...
    copy "GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll" "runtimes\win-x64\native\" >nul
    
    if exist "runtimes\win-x64\native\WebView2Loader.dll" (
        echo [SUCCESS] WebView2Loader.dll copied successfully!
        echo.
        echo File details:
        dir "runtimes\win-x64\native\WebView2Loader.dll"
        echo.
        echo [NEXT STEP] Try installing the plugin again in Total Commander
        echo The plugin should now work correctly.
    ) else (
        echo [ERROR] Failed to copy WebView2Loader.dll
        echo Check file permissions and try running as Administrator
    )
) else (
    echo [ERROR] WebView2Loader.dll not found in GitHubRelease folder
    echo.
    echo ALTERNATIVE SOLUTION:
    echo 1. Download WebView2Loader.dll from Microsoft WebView2 package
    echo 2. Place it in: runtimes\win-x64\native\WebView2Loader.dll
    echo 3. Or reinstall WebView2 Runtime from Microsoft
)

echo.
echo ========================================
echo Fix completed
echo ========================================
pause