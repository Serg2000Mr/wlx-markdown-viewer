@echo off
echo === Проверка зависимостей плагина ===
echo.

echo Проверка Visual C++ Redistributable файлов:
echo.

if exist "C:\Windows\System32\MSVCP140.dll" (
    echo [OK] MSVCP140.dll найден
) else (
    echo [FAIL] MSVCP140.dll ОТСУТСТВУЕТ
)

if exist "C:\Windows\System32\VCRUNTIME140.dll" (
    echo [OK] VCRUNTIME140.dll найден
) else (
    echo [FAIL] VCRUNTIME140.dll ОТСУТСТВУЕТ
)

if exist "C:\Windows\System32\VCRUNTIME140_1.dll" (
    echo [OK] VCRUNTIME140_1.dll найден
) else (
    echo [FAIL] VCRUNTIME140_1.dll ОТСУТСТВУЕТ
)

echo.
echo Проверка WebView2:
if exist "C:\Program Files (x86)\Microsoft\EdgeWebView\Application" (
    echo [OK] WebView2 найден
) else (
    echo [WARN] WebView2 может отсутствовать
)

echo.
echo === Рекомендации ===
echo Если какие-то файлы отсутствуют, установите:
echo Microsoft Visual C++ Redistributable for Visual Studio 2015-2022 (x64)
echo Ссылка: https://aka.ms/vs/17/release/vc_redist.x64.exe
echo.

pause