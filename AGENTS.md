# Project: Markdown Lister for Total Commander (AOT Version)

This project is a high-performance Markdown viewer plugin (.wlx) for Total Commander, optimized for zero external dependencies.

## Architecture

1.  **Rendering Engine (C# Native AOT)**:
    -   Location: `MarkdigNative/`
    -   Library: [Markdig](https://github.com/xoofx/markdig)
    -   Technology: .NET 8 Native AOT (Ahead-of-Time compilation).
    -   Output: `MarkdigNative-x64.dll` (a standalone native DLL with no .NET runtime requirement).
    -   Exports: `ConvertMarkdownToHtml`, `FreeHtmlBuffer`.

2.  **Bridge Layer (Pure C++)**:
    -   Location: `Markdown/`
    -   Role: Acts as a middleman between the Lister plugin and the AOT engine.
    -   Loading: Uses dynamic loading (`LoadLibraryW`) to find the AOT DLL relative to its own path.
    -   Compatibility: Replaces the old C++/CLI implementation to remove managed code dependencies.

3.  **Lister Plugin (C++)**:
    -   Location: `MarkdownView/`
    -   Role: Implements Total Commander's Lister API.
    -   UI: Uses **WebView2 (Edge/Chromium)** for HTML rendering (preferred). May fall back to the legacy IE WebBrowser control if WebView2 initialization fails.
    -   Output: `MarkdownView.wlx64`.

## Build System

-   **Tool**: `BuildAll.bat`
-   **Requirements**: 
    -   Visual Studio 2026 (v145 toolset).
    -   .NET 8.0 SDK (for AOT compilation).
-   **Platform**: Currently optimized for **x64**. (Note: .NET 8 Native AOT does not support x86).

## Key Components

-   `MarkdigNative/Lib.cs`: Contains the `[UnmanagedCallersOnly]` C# functions exported to C++.
-   `Markdown/markdown.cpp`: Handles dynamic loading of the engine and character encoding (UTF-8/UTF-16).
-   `Build/css/github.css`: A modern GitHub-like style optimized for the IE engine.
-   `Build/MarkdownView.ini`: Configuration for extensions and Markdig options.

## Important for AI Agents

-   **Memory Management**: Strings returned from C# AOT must be freed using the exported `FreeHtmlBuffer` function to avoid leaks.
-   **Path Resolution**: The bridge DLL (`Markdown-x64.dll`) looks for `MarkdigNative-x64.dll` in the same directory.
-   **Emoji shortcodes**: GitHub-style `:shortcode:` inside links (e.g. `[:arrow_up:Title](#...)`) is preprocessed in `MarkdigNative/Lib.cs` because Markdig’s emoji parser requires whitespace before the shortcode.
-   **Performance note**: Avoid per-request WebView2 interception (e.g. global `WebResourceRequested` filters) unless strictly required; it adds noticeable latency for small Markdown files.
-   **No CLR**: The C++ projects (`Markdown` and `MarkdownView`) MUST NOT have `/clr` enabled. They are pure native.
