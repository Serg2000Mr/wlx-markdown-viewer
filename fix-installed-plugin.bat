@echo off
echo ========================================
echo Quick Fix for Installed Plugin
echo ========================================
echo.

echo PROBLEM: WebView2Loader.dll is missing from the installed plugin
echo SOLUTION: Copy WebView2Loader.dll to the correct location
echo.

set "TC_PLUGIN=C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle"

echo Checking plugin installation...
if not exist "%TC_PLUGIN%\MarkdownView.wlx64" (
    echo ERROR: Plugin not found at %TC_PLUGIN%
    echo Please check if the plugin is installed in a different location.
    pause
    exit /b 1
)

echo Plugin found at: %TC_PLUGIN%
echo.

echo Creating WebView2 runtime directory...
if not exist "%TC_PLUGIN%\runtimes\win-x64\native" (
    mkdir "%TC_PLUGIN%\runtimes\win-x64\native"
    echo Directory created: %TC_PLUGIN%\runtimes\win-x64\native
)

echo Copying WebView2Loader.dll...
if exist "GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll" (
    copy /y "GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll" "%TC_PLUGIN%\runtimes\win-x64\native\"
    if %errorlevel% equ 0 (
        echo [SUCCESS] WebView2Loader.dll copied successfully!
        echo.
        echo File details:
        dir "%TC_PLUGIN%\runtimes\win-x64\native\WebView2Loader.dll"
        echo.
        echo [NEXT STEP] Now rebuild the plugin with the fixed code:
        echo   1. Run BuildAll.bat as Administrator
        echo   2. Or manually copy the new MarkdownView.wlx64 to the plugin folder
        echo.
        echo The plugin should now work correctly in Total Commander!
    ) else (
        echo [ERROR] Failed to copy WebView2Loader.dll
        echo This might be a permission issue. Try running as Administrator.
    )
) else (
    echo [ERROR] WebView2Loader.dll not found in GitHubRelease folder!
    echo Expected location: GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll
    echo.
    echo Please ensure the GitHubRelease folder contains the complete plugin files.
)

echo.
echo ========================================
echo Fix completed
echo ========================================
pause