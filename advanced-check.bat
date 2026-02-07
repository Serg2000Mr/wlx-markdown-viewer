@echo off
echo === Расширенная диагностика плагина ===
echo.

echo 1. Проверка архитектуры Total Commander:
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\ghisler\Total Commander" /v InstallDir 2>nul
if %errorlevel%==0 (
    echo [INFO] Total Commander найден в реестре
) else (
    echo [WARN] Total Commander не найден в реестре x64
)

reg query "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\ghisler\Total Commander" /v InstallDir 2>nul
if %errorlevel%==0 (
    echo [INFO] Total Commander найден в реестре WOW64 (32-bit)
) else (
    echo [INFO] Total Commander не найден в реестре WOW64
)

echo.
echo 2. Тест загрузки DLL напрямую:
echo Тестируем загрузку Markdown-x64.dll...

powershell -Command "try { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class DllTest { [DllImport(\"kernel32.dll\")] public static extern IntPtr LoadLibrary(string lpFileName); [DllImport(\"kernel32.dll\")] public static extern bool FreeLibrary(IntPtr hModule); [DllImport(\"kernel32.dll\")] public static extern uint GetLastError(); }'; $dll = [DllTest]::LoadLibrary('.\Markdown-x64.dll'); if ($dll -ne [IntPtr]::Zero) { Write-Host '[OK] Markdown-x64.dll загружается'; [DllTest]::FreeLibrary($dll) } else { $err = [DllTest]::GetLastError(); Write-Host '[FAIL] Ошибка загрузки Markdown-x64.dll. Код:' $err } } catch { Write-Host '[ERROR]' $_.Exception.Message }"

echo.
echo Тестируем загрузку MarkdigNative-x64.dll...

powershell -Command "try { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class DllTest2 { [DllImport(\"kernel32.dll\")] public static extern IntPtr LoadLibrary(string lpFileName); [DllImport(\"kernel32.dll\")] public static extern bool FreeLibrary(IntPtr hModule); [DllImport(\"kernel32.dll\")] public static extern uint GetLastError(); }'; $dll = [DllTest2]::LoadLibrary('.\MarkdigNative-x64.dll'); if ($dll -ne [IntPtr]::Zero) { Write-Host '[OK] MarkdigNative-x64.dll загружается'; [DllTest2]::FreeLibrary($dll) } else { $err = [DllTest2]::GetLastError(); Write-Host '[FAIL] Ошибка загрузки MarkdigNative-x64.dll. Код:' $err } } catch { Write-Host '[ERROR]' $_.Exception.Message }"

echo.
echo 3. Проверка прав доступа:
icacls MarkdownView.wlx64
icacls Markdown-x64.dll
icacls MarkdigNative-x64.dll

echo.
echo 4. Проверка цифровых подписей:
powershell -Command "Get-AuthenticodeSignature MarkdownView.wlx64 | Select-Object Status, StatusMessage"
powershell -Command "Get-AuthenticodeSignature Markdown-x64.dll | Select-Object Status, StatusMessage"
powershell -Command "Get-AuthenticodeSignature MarkdigNative-x64.dll | Select-Object Status, StatusMessage"

echo.
echo 5. Информация о системе:
echo Версия Windows: 
ver
echo Архитектура: %PROCESSOR_ARCHITECTURE%
echo Пользователь: %USERNAME%

echo.
echo === Диагностика завершена ===
pause