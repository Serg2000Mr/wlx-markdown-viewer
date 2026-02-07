# Исправления плагина WebView2

## История изменений

### Попытка 1 (ОТКАЧЕНА)
**Проблема**: Плагин не загружался в Total Commander с ошибкой "Не удается подключить плагин"

**Неправильное решение**: Попытались указать явный путь к WebView2Loader.dll в параметре `browserExecutableFolder` функции `CreateCoreWebView2EnvironmentWithOptions`

**Результат**: Плагин показывал белый экран и переставал работать, потому что параметр `browserExecutableFolder` предназначен для указания пути к **браузеру Edge**, а не к загрузчику WebView2.

### Попытка 2 (ТЕКУЩЕЕ РЕШЕНИЕ)
**Решение**: Откатили изменения в коде и вернулись к использованию `nullptr` для автоматического обнаружения WebView2 Runtime

**Изменения**:
1. В `browserhost.cpp` используем `nullptr` вместо явного пути
2. Очистили кеш WebView2 из `%LOCALAPPDATA%\TotalCommanderMarkdownViewPlugin\wv2data`
3. Пересобрали плагин с исправленным кодом

## Исправления в скрипте сборки BuildAll.bat
- Исправлен путь к каталогу плагина: `MarkdownViewGitHubStyle` вместо `MarkdownView`
- Добавлено копирование WebView2Loader.dll в правильное место
- Добавлено автоматическое обновление каталога GitHubRelease

## Обновлены файлы релиза
- Все файлы в каталоге GitHubRelease обновлены свежими скомпилированными версиями
- Создан новый архив wlx-markdown-viewer-github-style.zip

## Результат
Плагин теперь должен работать корректно, используя автоматическое обнаружение WebView2 Runtime установленного в системе.

## Файлы для распространения
- `MarkdownView.wlx64` - основной файл плагина
- `Markdown-x64.dll` - C++ мост
- `MarkdigNative-x64.dll` - C# библиотека (Native AOT)
- `MarkdownView.ini` - конфигурация
- `css/` - стили CSS
- `runtimes/win-x64/native/WebView2Loader.dll` - загрузчик WebView2