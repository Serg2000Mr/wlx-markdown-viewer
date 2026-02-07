# Диагностика плагина Markdown Viewer
Write-Host "=== Диагностика плагина Markdown Viewer ===" -ForegroundColor Green
Write-Host ""

# Проверка файлов
Write-Host "1. Проверка файлов плагина:" -ForegroundColor Yellow
$files = @("MarkdownView.wlx64", "Markdown-x64.dll", "MarkdigNative-x64.dll", "MarkdownView.ini")
foreach ($file in $files) {
    if (Test-Path $file) {
        $size = [math]::Round((Get-Item $file).Length / 1KB, 2)
        Write-Host "[OK] $file ($size KB)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $file отсутствует" -ForegroundColor Red
    }
}
Write-Host ""

# Проверка WebView2
Write-Host "2. Проверка WebView2:" -ForegroundColor Yellow
try {
    $webview2 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -Name pv -ErrorAction Stop
    Write-Host "[OK] WebView2 версия: $($webview2.pv)" -ForegroundColor Green
} catch {
    Write-Host "[WARN] WebView2 не найден в реестре" -ForegroundColor Yellow
}
Write-Host ""

# Проверка зависимостей DLL
Write-Host "3. Проверка зависимостей:" -ForegroundColor Yellow
try {
    Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class DllTest {
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern IntPtr LoadLibrary(string lpFileName);
            
            [DllImport("kernel32.dll", SetLastError = true)]
            public static extern bool FreeLibrary(IntPtr hModule);
        }
"@
    
    $dll = [DllTest]::LoadLibrary(".\Markdown-x64.dll")
    if ($dll -ne [IntPtr]::Zero) {
        Write-Host "[OK] Markdown-x64.dll загружается успешно" -ForegroundColor Green
        [DllTest]::FreeLibrary($dll) | Out-Null
    } else {
        Write-Host "[FAIL] Не удается загрузить Markdown-x64.dll" -ForegroundColor Red
        Write-Host "Код ошибки: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())" -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Ошибка при тестировании DLL: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Информация о системе
Write-Host "4. Информация о системе:" -ForegroundColor Yellow
Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Host "Архитектура: $([System.Environment]::Is64BitOperatingSystem)"
Write-Host ".NET Framework: $([System.Environment]::Version)"
Write-Host ""

Write-Host "=== Диагностика завершена ===" -ForegroundColor Green
Read-Host "Нажмите Enter для выхода"