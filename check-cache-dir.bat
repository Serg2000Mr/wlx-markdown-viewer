@echo off
echo === Диагностика каталога кэша плагина ===
echo.

set CACHE_DIR=%LOCALAPPDATA%\TotalCommanderMarkdownViewPlugin

echo Каталог кэша: %CACHE_DIR%
echo.

echo 1. Проверка существования каталога:
if exist "%CACHE_DIR%" (
    echo [OK] Каталог существует
    echo Содержимое:
    dir "%CACHE_DIR%" /a
) else (
    echo [INFO] Каталог не существует (будет создан автоматически)
)

echo.
echo 2. Проверка прав доступа:
echo Попытка создания тестового файла...
echo test > "%CACHE_DIR%\test.txt" 2>nul
if exist "%CACHE_DIR%\test.txt" (
    echo [OK] Права на запись есть
    del "%CACHE_DIR%\test.txt" 2>nul
) else (
    echo [FAIL] Нет прав на запись в каталог кэша
)

echo.
echo 3. Проверка переменных окружения:
echo LOCALAPPDATA: %LOCALAPPDATA%
echo USERNAME: %USERNAME%
echo USERPROFILE: %USERPROFILE%

echo.
echo 4. Попытка создания каталога:
mkdir "%CACHE_DIR%" 2>nul
if exist "%CACHE_DIR%" (
    echo [OK] Каталог создан или уже существует
) else (
    echo [FAIL] Не удается создать каталог кэша
)

echo.
echo === Решения ===
echo Если есть проблемы с каталогом кэша:
echo 1. Запустите Total Commander от имени администратора
echo 2. Или очистите каталог: rmdir /s "%CACHE_DIR%"
echo 3. Или измените права доступа к каталогу
echo.

pause