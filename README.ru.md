# Markdown Lister Plugin для Total Commander (64-битная версия)

Основано на [плагине wlx-markdown-viewer](https://github.com/rg-software/wlx-markdown-viewer), 
обновлено для использования процессора [Markdig](https://github.com/xoofx/markdig) с поддержкой современного синтаксиса Markdown.

**Ключевое улучшение:** Эта версия использует .NET Native AOT для компиляции движка Markdig в автономную нативную DLL. 
**Конечному пользователю НЕ требуется установка .NET Runtime.**

## Возможности
- Полная поддержка современного Markdown (GFM, таблицы, эмодзи и т.д.) через Markdig.
- Автономность: Отсутствие внешних зависимостей от .NET Runtime.
- Современный дизайн в стиле GitHub.
- Быстрая и легкая работа.

## Примечания

- **GitHub-эмодзи `:shortcode:`**: парсер эмодзи Markdig требует пробел перед `:shortcode:`. На GitHub часто встречается `:shortcode:` внутри ссылок (например, `[:arrow_up:Оглавление](#...)`), поэтому в `MarkdigNative/Lib.cs` добавлена предобработка ограниченного набора shortcodes (вне fenced-кода ```), чтобы отображение совпадало с GitHub.
- **Производительность**: глобальный перехват ресурсов WebView2 (например, `WebResourceRequested` для `*`) заметно замедляет открытие небольших Markdown с картинками — избегать без крайней необходимости.

## Тонкая настройка

Конфигурация плагина задается в файле `MarkdownView.ini`. Настройки Markdown:

- `Extensions: MarkdownExtensions` — расширения файлов, распознаваемые плагином как Markdown.
- `Renderer: Extensions` — коллекция расширений для процессора Markdig. [Подробнее о расширениях Markdig](https://github.com/xoofx/markdig/blob/master/readme.md)  
  Поддерживаются следующие расширения: common, advanced, alerts, pipetables, gfm-pipetables, emphasisextras, listextras, hardlinebreak, footnotes, footers, citations, attributes, gridtables, abbreviations, emojis, definitionlists, customcontainers, figures, mathematics, bootstrap, medialinks, smartypants, autoidentifiers, tasklists, diagrams, nofollowlinks, noopenerlinks, noreferrerlinks, nohtml, yaml, nonascii-noescape, autolinks, globalization.
- `Renderer: CustomCSS` — путь к файлу CSS для настройки внешнего вида документа. В комплект включены стили от [Markdown CSS](https://markdowncss.github.io/) и темы в стиле Github от S. Kuznetsov.

## Обновление Internet Explorer

Плагин использует движок Internet Explorer, который можно обновить через [реестр](https://github.com/rg-software/wlx-markdown-viewer/raw/master/ie_upgrade_registry.zip) (подробности в [MSDN](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/general-info/ee330730(v=vs.85)?redirectedfrom=MSDN#browser-emulation)).

## Установка

Архив с бинарными файлами плагина поставляется со скриптом установки. Просто откройте архив в Total Commander и подтвердите установку.

## Установка вручную (после сборки)

Total Commander **не копирует** и **не создаёт** папку плагина автоматически. В настройках Lister вы указываете путь к файлу `.wlx64`, и плагин затем работает **из этой папки** (там же ищет `MarkdownView.ini`, `css\` и DLL через `GetModuleFileName`).

- **Вариант A (проще):** указать в TC путь на `bin\Release\MarkdownView.wlx64`. Тогда корневой каталог плагина — `bin\Release\` (и `bin\Release\css\`).
- **Вариант B (отдельная папка):** создать папку (например, `c:\Program Files\totalcmd\plugins\wlx\MarkdownView`) и скопировать туда: `MarkdownView.wlx64`, `Markdown-x64.dll`, `MarkdigNative-x64.dll`, `MarkdownView.ini` и папку `css\`. Затем в TC указать путь на `…\MarkdownView\MarkdownView.wlx64`.

После успешной сборки `BuildAll.bat` может автоматически обновлять Вариант B (при закрытом Total Commander).

> Примечание: запись в `c:\Program Files\...` обычно требует запуск `BuildAll.bat` **от имени администратора**. Если используете Вариант A (TC указывает на `bin\Release`), деплой в Program Files не нужен.
