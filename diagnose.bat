@echo off
echo === Диагностика плагина Markdown Viewer ===
echo.

echo 1. Проверка файлов плагина:
if exist "MarkdownView.wlx64" (echo [OK] MarkdownView.wlx64) else (echo [FAIL] MarkdownView.wlx64 отсутствует)
if exist "Markdown-x64.dll" (echo [OK] Markdown-x64.dll) else (echo [FAIL] Markdown-x64.dll отсутствует)
if exist "MarkdigNative-x64.dll" (echo [OK] MarkdigNative-x64.dll) else (echo [FAIL] MarkdigNative-x64.dll отсутствует)
if exist "MarkdownView.ini" (echo [OK] MarkdownView.ini) else (echo [FAIL] MarkdownView.ini отсутствует)
echo.

echo 2. Проверка WebView2:
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" /v pv 2>nul
if %errorlevel%==0 (echo [OK] WebView2 найден в реестре) else (echo [WARN] WebView2 не найден в реестре)
echo.

echo 3. Проверка Visual C++ Redistributable:
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Dependencies\Microsoft.VS.VC_RuntimeMinimumVSU_amd64,v14" 2>nul
if %errorlevel%==0 (echo [OK] VC++ Redistributable найден) else (echo [WARN] VC++ Redistributable не найден)
echo.

echo 4. Тест загрузки DLL:
echo Тестируем Markdown-x64.dll...
rundll32 "Markdown-x64.dll",DllCanUnloadNow 2>nul
if %errorlevel%==0 (echo [OK] Markdown-x64.dll загружается) else (echo [FAIL] Ошибка загрузки Markdown-x64.dll)

echo.
echo 5. Информация о системе:
echo OS: %OS%
echo Архитектура: %PROCESSOR_ARCHITECTURE%
echo.

echo === Диагностика завершена ===
pause