# Анализ зависимостей DLL с помощью dumpbin
param(
    [string]$DllPath = "."
)

Write-Host "=== Анализ зависимостей DLL ===" -ForegroundColor Green
Write-Host ""

# Поиск dumpbin.exe для Visual Studio 18 (2022)
$dumpbinPaths = @(
    "${env:ProgramFiles}\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\18\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
    "${env:ProgramFiles}\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\18\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe"
)

$dumpbin = $null
foreach ($path in $dumpbinPaths) {
    $found = Get-ChildItem $path -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $dumpbin = $found.FullName
        break
    }
}

if (-not $dumpbin) {
    Write-Host "[ERROR] dumpbin.exe не найден. Убедитесь, что установлен Visual Studio с C++ компонентами." -ForegroundColor Red
    exit 1
}

Write-Host "Используется dumpbin: $dumpbin" -ForegroundColor Yellow
Write-Host ""

# Анализ каждой DLL
$dlls = @("Markdown-x64.dll", "MarkdigNative-x64.dll", "MarkdownView.wlx64")

foreach ($dll in $dlls) {
    $fullPath = Join-Path $DllPath $dll
    if (Test-Path $fullPath) {
        Write-Host "=== Анализ $dll ===" -ForegroundColor Cyan
        
        # Зависимости
        Write-Host "Зависимости:" -ForegroundColor Yellow
        & $dumpbin /dependents $fullPath
        
        Write-Host "`nИмпорты:" -ForegroundColor Yellow
        & $dumpbin /imports $fullPath | Select-String -Pattern "\.dll|DLL Name"
        
        Write-Host "`n" + "="*50
    } else {
        Write-Host "[SKIP] $dll не найден в $DllPath" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Анализ завершен ===" -ForegroundColor Green