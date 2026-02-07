@echo off
chcp 65001 >nul
echo ========================================
echo Применение оптимизаций плагина
echo ========================================
echo.

REM Проверка наличия файлов
if not exist "MarkdownView\browserhost.cpp" (
    echo ОШИБКА: Файл browserhost.cpp не найден!
    pause
    exit /b 1
)

if not exist "MarkdownView\browserhost_optimized.cpp" (
    echo ОШИБКА: Файл browserhost_optimized.cpp не найден!
    pause
    exit /b 1
)

echo Шаг 1: Создание резервных копий...
copy /Y "MarkdownView\browserhost.cpp" "MarkdownView\browserhost.cpp.backup" >nul
copy /Y "MarkdownView\browserhost.h" "MarkdownView\browserhost.h.backup" >nul
echo ✓ Резервные копии созданы

echo.
echo Шаг 2: Применение оптимизаций к browserhost.h...

REM Добавляем static sSharedEnvironment в browserhost.h
powershell -Command "(Get-Content 'MarkdownView\browserhost.h') -replace 'bool mIsWebView2Initialized;', 'bool mIsWebView2Initialized;`r`n`tstatic CComPtr<ICoreWebView2Environment> sSharedEnvironment;' | Set-Content 'MarkdownView\browserhost.h'"

echo ✓ browserhost.h обновлен

echo.
echo Шаг 3: Замена browserhost.cpp оптимизированной версией...
copy /Y "MarkdownView\browserhost_optimized.cpp" "MarkdownView\browserhost.cpp" >nul
echo ✓ browserhost.cpp заменен

echo.
echo Шаг 4: Компиляция проекта...
echo.
call BuildAll.bat

if errorlevel 1 (
    echo.
    echo ========================================
    echo ОШИБКА КОМПИЛЯЦИИ!
    echo ========================================
    echo.
    echo Восстановление из резервных копий...
    copy /Y "MarkdownView\browserhost.cpp.backup" "MarkdownView\browserhost.cpp" >nul
    copy /Y "MarkdownView\browserhost.h.backup" "MarkdownView\browserhost.h" >nul
    echo ✓ Файлы восстановлены
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo ОПТИМИЗАЦИИ УСПЕШНО ПРИМЕНЕНЫ!
echo ========================================
echo.
echo Скомпилированный плагин находится в:
echo bin\x64\Release\MarkdownView.wlx64
echo.
echo Следующие шаги:
echo 1. Закройте Total Commander
echo 2. Скопируйте MarkdownView.wlx64 в папку плагинов
echo 3. Запустите Total Commander и протестируйте
echo.
echo Резервные копии сохранены:
echo - MarkdownView\browserhost.cpp.backup
echo - MarkdownView\browserhost.h.backup
echo.
pause
