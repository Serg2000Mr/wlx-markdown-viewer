@echo off
setlocal enabledelayedexpansion

:: Set working directory to the script's directory
cd /d "%~dp0"

:: Remove trailing backslash from current directory
set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"

echo.
echo === Build Script for wlx-markdown-viewer (Native AOT) ===
echo.

:: Close Total Commander if running
set "TC_WAS_RUNNING="
tasklist /FI "IMAGENAME eq TOTALCMD64.EXE" 2>nul | find /I "TOTALCMD64.EXE" >nul && set "TC_WAS_RUNNING=1"
tasklist /FI "IMAGENAME eq TOTALCMD.EXE" 2>nul | find /I "TOTALCMD.EXE" >nul && set "TC_WAS_RUNNING=1"

echo Closing TOTALCMD64.EXE if running...
taskkill /IM TOTALCMD64.EXE /F >nul 2>&1
if %ERRORLEVEL% EQU 0 (echo TOTALCMD64.EXE closed.) else (echo TOTALCMD64.EXE was not running.)
echo Closing TOTALCMD.EXE if running...
taskkill /IM TOTALCMD.EXE /F >nul 2>&1
if %ERRORLEVEL% EQU 0 (echo TOTALCMD.EXE closed.) else (echo TOTALCMD.EXE was not running.)
echo.

:: --- Configuration for Visual Studio 2026 (Internal version 18) ---
set "VS_PATH=C:\Program Files\Microsoft Visual Studio\18\Community"
set "MSBUILD=%VS_PATH%\MSBuild\Current\Bin\MSBuild.exe"
set "DOTNET=dotnet"

:: 1. Check MSBuild
if not exist "%MSBUILD%" (
    echo [DEBUG] MSBuild not found at expected path: %MSBUILD%
    echo Searching for MSBuild.exe in %VS_PATH%...
    for /f "delims=" %%i in ('where /R "%VS_PATH%" MSBuild.exe 2^>nul') do (
        set "MSBUILD=%%i"
        goto :found_msbuild
    )
    
    set "BT_PATH=C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools"
    echo Searching for MSBuild.exe in %BT_PATH%...
    for /f "delims=" %%i in ('where /R "%BT_PATH%" MSBuild.exe 2^>nul') do (
        set "MSBUILD=%%i"
        goto :found_msbuild
    )

    echo ERROR: MSBuild.exe not found. Please ensure Visual Studio 2026 is installed.
    timeout /t 5
    exit /b 1
)

:found_msbuild
echo Found MSBuild: "%MSBUILD%"

:: 2. Check Dotnet SDK
where dotnet >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Found dotnet in PATH
) else (
    echo dotnet not found in PATH, searching in %VS_PATH%...
    for /f "delims=" %%i in ('where /R "%VS_PATH%" dotnet.exe 2^>nul') do (
        set "DOTNET=%%i"
        goto :found_dotnet
    )
    echo ERROR: dotnet.exe not found. Please install .NET 8 SDK.
    timeout /t 5
    exit /b 1
)

:found_dotnet
echo Using dotnet: "%DOTNET%"

:: Create output directory
if not exist "bin\Release" mkdir "bin\Release"

:: Locate WebView2Loader.dll sources (NuGet packages folder)
set "WV2_PKG="
for /d %%D in ("packages\Microsoft.Web.WebView2.*") do set "WV2_PKG=%%D"
if defined WV2_PKG (
    echo Using WebView2 package: "!WV2_PKG!"
) else (
    echo WARNING: WebView2 NuGet package folder not found under "packages\". WebView2Loader.dll will not be copied.
)

:: --- 1. Build MarkdigNative (C# Native AOT) ---
echo.
echo === Building MarkdigNative (C# Native AOT) ===

:: Clean previous x64 renderer artifacts so a stale AOT DLL or managed folder
:: cannot be packaged together with a freshly produced one.
if exist "bin\Release\MarkdigNative-x64.dll" del /q "bin\Release\MarkdigNative-x64.dll"
if exist "bin\Release\MarkdigNative-x64.pdb" del /q "bin\Release\MarkdigNative-x64.pdb"
if exist "bin\Release\dotnet-x64" rmdir /s /q "bin\Release\dotnet-x64"

set "BUILD_MODE_X64="

:: Build x64
echo [x64] Building MarkdigNative...
cd MarkdigNative
"%DOTNET%" publish -r win-x64 -c Release /p:PublishAot=true /p:AssemblyName=MarkdigNative-x64
if errorlevel 1 goto markdignative_x64_managed
copy /y bin\Release\net8.0\win-x64\publish\MarkdigNative-x64.dll ..\bin\Release\
copy /y bin\Release\net8.0\win-x64\publish\MarkdigNative-x64.pdb ..\bin\Release\
set "BUILD_MODE_X64=aot"
cd ..
goto markdignative_x64_done

:markdignative_x64_managed
cd ..
if not defined ALLOW_MANAGED_FALLBACK_X64 (
    echo ERROR: MarkdigNative x64 NativeAOT build failed.
    echo        Fix the AOT toolchain, or set ALLOW_MANAGED_FALLBACK_X64=1 to allow
    echo        a managed fallback build that requires a .NET runtime on the target machine.
    timeout /t 5
    exit /b 1
)
echo WARNING: MarkdigNative x64 NativeAOT build failed. ALLOW_MANAGED_FALLBACK_X64 is set, falling back to managed (.NET runtime required).
cd MarkdigNative
"%DOTNET%" publish -r win-x64 -c Release /p:PublishAot=false /p:SelfContained=false /p:AssemblyName=MarkdigNative-x64
if errorlevel 1 (
    echo ERROR building MarkdigNative x64 (managed fallback)
    cd ..
    timeout /t 5
    exit /b %ERRORLEVEL%
)
if not exist "..\bin\Release\dotnet-x64" mkdir "..\bin\Release\dotnet-x64"
xcopy /s /e /y /i "bin\Release\net8.0\win-x64\publish" "..\bin\Release\dotnet-x64" >nul
set "BUILD_MODE_X64=managed"
cd ..

:markdignative_x64_done
:: Validate the selected artifact actually exists.
if "%BUILD_MODE_X64%"=="aot" (
    if not exist "bin\Release\MarkdigNative-x64.dll" (
        echo ERROR: AOT build reported success but bin\Release\MarkdigNative-x64.dll is missing.
        timeout /t 5
        exit /b 1
    )
) else if "%BUILD_MODE_X64%"=="managed" (
    if not exist "bin\Release\dotnet-x64\MarkdigNative-x64.dll" (
        echo ERROR: managed fallback reported success but bin\Release\dotnet-x64\MarkdigNative-x64.dll is missing.
        timeout /t 5
        exit /b 1
    )
) else (
    echo ERROR: x64 build mode was not determined.
    timeout /t 5
    exit /b 1
)
echo [x64] MarkdigNative build mode: %BUILD_MODE_X64%

cd MarkdigNative

:: Build x86
echo [x86] Building MarkdigNative (self-contained, app-local .NET runtime)...
"%DOTNET%" publish -r win-x86 -c Release /p:PublishAot=false /p:SelfContained=true /p:AssemblyName=MarkdigNative-x86
if %ERRORLEVEL% NEQ 0 (
    echo ERROR building MarkdigNative x86
    timeout /t 5
    exit /b %ERRORLEVEL%
)
if not exist "..\bin\Release\dotnet-x86" mkdir "..\bin\Release\dotnet-x86"
xcopy /s /e /y /i "bin\Release\net8.0\win-x86\publish" "..\bin\Release\dotnet-x86" >nul
cd ..

:: --- 2. Build Markdown (C++ Bridge) ---
echo.
echo === Building Markdown (C++ Bridge) ===

:: Build x64
echo [x64] Building Markdown bridge...
:: MSBuild trick: pass path with double backslash at the end to prevent quote escaping
"%MSBUILD%" Markdown\Markdown.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:SolutionDir="%ROOT_DIR%\\"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR building Markdown x64
    timeout /t 5
    exit /b %ERRORLEVEL%
)

:: Build x86
echo [x86] Building Markdown bridge...
"%MSBUILD%" Markdown\Markdown.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /p:SolutionDir="%ROOT_DIR%\\"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR building Markdown x86
    timeout /t 5
    exit /b %ERRORLEVEL%
)

:: --- 3. Build MarkdownView (Lister Plugin) ---
echo.
echo === Building MarkdownView (Lister Plugin) ===

:: Build x64
echo [x64] Building MarkdownView...
"%MSBUILD%" MarkdownView\MarkdownView.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64 /p:SolutionDir="%ROOT_DIR%\\"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR building MarkdownView x64
    timeout /t 5
    exit /b %ERRORLEVEL%
)
if defined WV2_PKG (
    if exist "!WV2_PKG!\build\native\x64\WebView2Loader.dll" (
        copy /y "!WV2_PKG!\build\native\x64\WebView2Loader.dll" "bin\Release\WebView2Loader-x64.dll" >nul
    )
)

:: Build x86
echo [x86] Building MarkdownView...
"%MSBUILD%" MarkdownView\MarkdownView.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=Win32 /p:SolutionDir="%ROOT_DIR%\\"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR building MarkdownView x86
    timeout /t 5
    exit /b %ERRORLEVEL%
)
if defined WV2_PKG (
    if exist "!WV2_PKG!\build\native\x86\WebView2Loader.dll" (
        copy /y "!WV2_PKG!\build\native\x86\WebView2Loader.dll" "bin\Release\WebView2Loader-x86.dll" >nul
    )
)

echo.
echo Required files for distribution:
echo   - MarkdownView.wlx64 (x64)
echo   - Markdown-x64.dll (x64)
echo   - MarkdigNative-x64.dll (x64, NativeAOT) OR dotnet-x64\* (managed fallback)
echo   - WebView2Loader-x64.dll (x64, rename to WebView2Loader.dll)
echo   - MarkdownView.wlx (x86)
echo   - Markdown-x86.dll (x86)
echo   - dotnet-x86\* (x86, app-local .NET runtime + MarkdigNative-x86.*)
echo   - WebView2Loader-x86.dll (x86, rename to WebView2Loader.dll)
echo   - dist-x64\* (x64-ready folder: WebView2Loader.dll already near other DLLs)
echo   - dist-x86\* (x86-ready folder: WebView2Loader.dll already near other DLLs)
echo.

:: Copy resources
echo Copying resources to bin\Release...
copy /y Build\MarkdownView.ini bin\Release\ >nul
xcopy /s /e /y /i Build\css bin\Release\css >nul

:: Create per-arch distribution folders (so WebView2Loader.dll can sit next to plugin DLLs)
set "DIST_X64=bin\Release\dist-x64"
set "DIST_X86=bin\Release\dist-x86"

if exist "%DIST_X64%" rmdir /s /q "%DIST_X64%"
if exist "%DIST_X86%" rmdir /s /q "%DIST_X86%"

mkdir "%DIST_X64%"
mkdir "%DIST_X64%\css"
copy /y "bin\Release\MarkdownView.wlx64" "%DIST_X64%\" >nul
copy /y "bin\Release\Markdown-x64.dll" "%DIST_X64%\" >nul
if "%BUILD_MODE_X64%"=="aot" (
    copy /y "bin\Release\MarkdigNative-x64.dll" "%DIST_X64%\" >nul
) else (
    if not exist "%DIST_X64%\dotnet-x64" mkdir "%DIST_X64%\dotnet-x64"
    xcopy /s /e /y /i "bin\Release\dotnet-x64" "%DIST_X64%\dotnet-x64" >nul
)
copy /y "bin\Release\MarkdownView.ini" "%DIST_X64%\" >nul
xcopy /s /e /y /i "bin\Release\css" "%DIST_X64%\css" >nul
if exist "bin\Release\WebView2Loader-x64.dll" (
    copy /y "bin\Release\WebView2Loader-x64.dll" "%DIST_X64%\WebView2Loader.dll" >nul
) else if exist "bin\Release\runtimes\win-x64\native\WebView2Loader.dll" (
    copy /y "bin\Release\runtimes\win-x64\native\WebView2Loader.dll" "%DIST_X64%\WebView2Loader.dll" >nul
)
> "%DIST_X64%\pluginst.inf" echo [plugininstall]
>> "%DIST_X64%\pluginst.inf" echo description=Markdown Viewer with GitHub-style rendering and Mermaid.js support
>> "%DIST_X64%\pluginst.inf" echo type=wlx64
>> "%DIST_X64%\pluginst.inf" echo file=MarkdownView.wlx64
>> "%DIST_X64%\pluginst.inf" echo defaultdir=MarkdownViewGitHubStyle

mkdir "%DIST_X86%"
mkdir "%DIST_X86%\css"
copy /y "bin\Release\MarkdownView.wlx" "%DIST_X86%\" >nul
copy /y "bin\Release\Markdown-x86.dll" "%DIST_X86%\" >nul
copy /y "bin\Release\MarkdownView.ini" "%DIST_X86%\" >nul
xcopy /s /e /y /i "bin\Release\css" "%DIST_X86%\css" >nul
if not exist "%DIST_X86%\dotnet-x86" mkdir "%DIST_X86%\dotnet-x86"
xcopy /s /e /y /i "bin\Release\dotnet-x86" "%DIST_X86%\dotnet-x86" >nul
if exist "bin\Release\WebView2Loader-x86.dll" (
    copy /y "bin\Release\WebView2Loader-x86.dll" "%DIST_X86%\WebView2Loader.dll" >nul
) else if exist "bin\Release\runtimes\win-x86\native\WebView2Loader.dll" (
    copy /y "bin\Release\runtimes\win-x86\native\WebView2Loader.dll" "%DIST_X86%\WebView2Loader.dll" >nul
)
> "%DIST_X86%\pluginst.inf" echo [plugininstall]
>> "%DIST_X86%\pluginst.inf" echo description=Markdown Viewer with GitHub-style rendering and Mermaid.js support
>> "%DIST_X86%\pluginst.inf" echo type=wlx
>> "%DIST_X86%\pluginst.inf" echo file=MarkdownView.wlx
>> "%DIST_X86%\pluginst.inf" echo defaultdir=MarkdownViewGitHubStyle

:: Create two zip archives ready for release
set "ZIP_X64=bin\Release\MarkdownViewGitHubStyle-x64.zip"
set "ZIP_X86=bin\Release\MarkdownViewGitHubStyle-x86.zip"
if exist "%ZIP_X64%" del /q "%ZIP_X64%"
if exist "%ZIP_X86%" del /q "%ZIP_X86%"

powershell.exe -nologo -noprofile -command "& { Compress-Archive -Path 'bin\Release\dist-x64\*' -DestinationPath '%ZIP_X64%' -Force }"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR creating x64 zip archive
    timeout /t 5
    exit /b %ERRORLEVEL%
)

powershell.exe -nologo -noprofile -command "& { Compress-Archive -Path 'bin\Release\dist-x86\*' -DestinationPath '%ZIP_X86%' -Force }"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR creating x86 zip archive
    timeout /t 5
    exit /b %ERRORLEVEL%
)

:: --- 4. Update installed plugin (Total Commander already closed above) ---
set "TC_PLUGIN=c:\Program Files\totalcmd\plugins\wlx\MarkdownView"
echo.
echo === Updating installed plugin at %TC_PLUGIN% ===
if not exist "%TC_PLUGIN%" (
    echo Creating folder...
    mkdir "%TC_PLUGIN%"
)
if not exist "%TC_PLUGIN%\css" (
    mkdir "%TC_PLUGIN%\css"
)
if not exist "%TC_PLUGIN%" (
    echo ERROR: Cannot access "%TC_PLUGIN%".
    echo        Most likely you need to run BuildAll.bat "as Administrator" to write into Program Files.
    echo        Skipping installed plugin update.
) else (
    copy /y bin\Release\MarkdownView.wlx64 "%TC_PLUGIN%"
    copy /y bin\Release\Markdown-x64.dll "%TC_PLUGIN%"
    :: Remove any previously-deployed renderer of the OTHER mode so AOT and managed
    :: artifacts cannot coexist and create version skew on the target machine.
    if "%BUILD_MODE_X64%"=="aot" (
        if exist "%TC_PLUGIN%\dotnet-x64" rmdir /s /q "%TC_PLUGIN%\dotnet-x64"
        copy /y bin\Release\MarkdigNative-x64.dll "%TC_PLUGIN%"
    ) else (
        if exist "%TC_PLUGIN%\MarkdigNative-x64.dll" del /q "%TC_PLUGIN%\MarkdigNative-x64.dll"
        if exist "%TC_PLUGIN%\MarkdigNative-x64.pdb" del /q "%TC_PLUGIN%\MarkdigNative-x64.pdb"
        if not exist "%TC_PLUGIN%\dotnet-x64" mkdir "%TC_PLUGIN%\dotnet-x64"
        xcopy /s /e /y /i bin\Release\dotnet-x64 "%TC_PLUGIN%\dotnet-x64" >nul
    )
    if exist "bin\Release\WebView2Loader-x64.dll" copy /y "bin\Release\WebView2Loader-x64.dll" "%TC_PLUGIN%\WebView2Loader.dll" >nul
    copy /y bin\Release\MarkdownView.ini "%TC_PLUGIN%"
    xcopy /s /e /y /i bin\Release\css "%TC_PLUGIN%\css"
    echo Plugin updated.
)

set "TC_PLUGIN32=c:\Program Files (x86)\totalcmd\plugins\wlx\MarkdownView"
echo.
echo === Updating installed plugin at %TC_PLUGIN32% ===
if not exist "%TC_PLUGIN32%" (
    echo Creating folder...
    mkdir "%TC_PLUGIN32%"
)
if not exist "%TC_PLUGIN32%\css" (
    mkdir "%TC_PLUGIN32%\css"
)
if not exist "%TC_PLUGIN32%" (
    echo ERROR: Cannot access "%TC_PLUGIN32%".
    echo        Most likely you need to run BuildAll.bat "as Administrator" to write into Program Files.
    echo        Skipping installed plugin update.
) else (
    copy /y bin\Release\MarkdownView.wlx "%TC_PLUGIN32%"
    copy /y bin\Release\Markdown-x86.dll "%TC_PLUGIN32%"
    if exist "bin\Release\WebView2Loader-x86.dll" copy /y "bin\Release\WebView2Loader-x86.dll" "%TC_PLUGIN32%\WebView2Loader.dll" >nul
    if not exist "%TC_PLUGIN32%\dotnet-x86" mkdir "%TC_PLUGIN32%\dotnet-x86"
    xcopy /s /e /y /i bin\Release\dotnet-x86 "%TC_PLUGIN32%\dotnet-x86" >nul
    copy /y bin\Release\MarkdownView.ini "%TC_PLUGIN32%"
    xcopy /s /e /y /i bin\Release\css "%TC_PLUGIN32%\css"
    echo Plugin updated.
)

echo.
echo === Build Successful (x64 + x86)! ===

if defined TC_WAS_RUNNING (
    echo Reopening Total Commander...
    start "" "c:\Program Files\totalcmd\TOTALCMD64.EXE"
    start "" "c:\Program Files (x86)\totalcmd\TOTALCMD.EXE"
    REM If TC is installed in another folder, change the path above.
)

timeout /t 2
