using System.Collections.Concurrent;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Markdig;
using Markdig.Extensions.AutoIdentifiers;
using Markdig.Extensions.Yaml;
using Markdig.Renderers;
using Markdig.Renderers.Html;
using Markdig.Renderers.Html.Inlines;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;

namespace MarkdigNative;

public static class Lib
{
    static Lib()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    /// <summary>
    /// GitHub-style :shortcode: → Unicode emoji (Markdig requires space before shortcode, so we pre-process).
    /// </summary>
    private static readonly Dictionary<string, string> GitHubEmojiShortcodes = new(StringComparer.OrdinalIgnoreCase)
    {
        { ":arrow_up:", "⬆️" },
        { ":white_check_mark:", "✅" },
        { ":negative_squared_cross_mark:", "❎" },
        { ":black_square_button:", "🔲" },
    };

    private static string ReplaceGitHubEmojiShortcodes(string text)
    {
        foreach (var kv in GitHubEmojiShortcodes)
            text = text.Replace(kv.Key, kv.Value);
        return text;
    }

    /// <summary>
    /// Replace :shortcode: with emoji only outside fenced code blocks (```), so examples stay literal.
    /// </summary>
    private static string ReplaceGitHubEmojiOutsideCodeBlocks(string source)
    {
        string[] parts = source.Split("```");
        for (int i = 0; i < parts.Length; i += 2)
            parts[i] = ReplaceGitHubEmojiShortcodes(parts[i]);
        return string.Join("```", parts);
    }

    // Шаблоны опасных HTML-блоков, которые нужно удалять вместе с содержимым.
    // Markdig только парсит тег как HtmlInline, а текст внутри (`alert(99)`)
    // отдаётся как обычный LiteralInline и попадает в HTML как видимый текст.
    private static readonly Regex[] DangerousHtmlBlockPatterns = new[]
    {
        new Regex(@"<script\b[^>]*>[\s\S]*?</script\s*>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<style\b[^>]*>[\s\S]*?</style\s*>",  RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<noscript\b[^>]*>[\s\S]*?</noscript\s*>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<iframe\b[^>]*>[\s\S]*?</iframe\s*>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<object\b[^>]*>[\s\S]*?</object\s*>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<embed\b[^>]*/?>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new Regex(@"<applet\b[^>]*>[\s\S]*?</applet\s*>", RegexOptions.IgnoreCase | RegexOptions.Compiled),
    };

    // Удаляет опасные HTML-блоки (script, style, iframe и т.п.) вместе с содержимым.
    // Применяется только к сегментам markdown ВНЕ fenced code blocks (между ```),
    // чтобы не задеть примеры HTML в документации.
    private static string StripDangerousHtmlBlocks(string source)
    {
        string[] parts = source.Split("```");
        for (int i = 0; i < parts.Length; i += 2)
        {
            foreach (var pattern in DangerousHtmlBlockPatterns)
                parts[i] = pattern.Replace(parts[i], "");
        }
        return string.Join("```", parts);
    }

    private sealed record CssCacheEntry(DateTime LastWriteTimeUtc, string Content);

    private static readonly ConcurrentDictionary<string, CssCacheEntry> CssCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly ConcurrentDictionary<string, MarkdownPipeline> PipelineCache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Encoding Utf8Strict = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
    private static readonly Encoding SystemAnsi = GetSystemAnsiEncoding();

    private readonly record struct HtmlCacheKey(
        string FilenameKey,
        long MdLastWriteTicksUtc,
        long MdLength,
        string CssFileKey,
        long CssLastWriteTicksUtc,
        string ExtensionsKey
    );

    private const int HtmlCacheMaxEntries = 8;
    private const int HtmlCacheMaxCharsPerEntry = 2_000_000;
    private static readonly object HtmlCacheLock = new();
    private static readonly Dictionary<HtmlCacheKey, string> HtmlCache = new();
    private static readonly Dictionary<HtmlCacheKey, LinkedListNode<HtmlCacheKey>> HtmlCacheNodes = new();
    private static readonly LinkedList<HtmlCacheKey> HtmlCacheLru = new();

    internal static readonly Regex SafeIdPattern = new(
        @"^[\p{L}\p{N}_\-:.]+$",
        RegexOptions.Compiled);

    internal static readonly Regex AnchorOpenTagPattern = new(
        @"^<a\b(?=[^>]*\b(name|id)\s*=\s*([""'])([^""']*)\2)[^>]*>$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex AnchorCloseTagPattern = new(
        @"^</a\s*>$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex SelfClosingTagSuffix = new(
        @"/\s*>$",
        RegexOptions.Compiled);

    internal static readonly Regex HtmlHeadingBlockPattern = new(
        @"^\s*<(h[1-6])\b(?=[^>]*\bid\s*=\s*([""'])([^""']*)\2)[^>]*>([\s\S]*?)</\1\s*>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex StandaloneAnchorParagraphPattern = new(
        @"<p>\s*(<a\s+name=""[\p{L}\p{N}_\-:.]+""\s+id=""[\p{L}\p{N}_\-:.]+""></a>)\s*</p>",
        RegexOptions.Compiled);

    // ===== HTML allowlist расширение для GitHub-совместимых тегов =====

    // Inline void tags (без content): <br>, <br/>, <wbr>
    internal static readonly HashSet<string> SafeVoidInlineTags =
        new(StringComparer.OrdinalIgnoreCase) { "br", "wbr" };

    // Paired inline tags: <sub>X</sub>, <sup>X</sup>, <kbd>X</kbd>, <mark>X</mark>...
    internal static readonly HashSet<string> SafePairedInlineTags =
        new(StringComparer.OrdinalIgnoreCase)
        { "sub", "sup", "kbd", "mark", "ins", "del", "small", "abbr", "cite", "q" };

    internal static readonly Regex AnyVoidInlineTagPattern = new(
        @"^<(\w+)\b[^>]*/?>$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex AnyPairedOpenInlineTagPattern = new(
        @"^<(\w+)\b[^>]*>$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex AnyPairedCloseInlineTagPattern = new(
        @"^</(\w+)\s*>$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Block tag patterns: <hr>, <details>, <summary>
    internal static readonly Regex HtmlHrFragmentPattern = new(
        @"^\s*<hr\b[^>]*/?>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Compact full-block: <details ...>...inner...</details> в одном HtmlBlock
    // Группы: 1=attrs, 2=optional summary text, 3=inner после summary до </details>
    internal static readonly Regex HtmlDetailsFullBlockPattern = new(
        @"^\s*<details\b([^>]*)>\s*(?:<summary\b[^>]*>([\s\S]*?)</summary>)?([\s\S]*?)</details>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Open fragment: <details ...> [<summary>X</summary>] без </details>
    internal static readonly Regex HtmlDetailsOpenFragmentPattern = new(
        @"^\s*<details\b([^>]*)>\s*(?:<summary\b[^>]*>([\s\S]*?)</summary>)?\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex HtmlDetailsCloseFragmentPattern = new(
        @"^\s*</details\s*>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex HtmlSummaryFullFragmentPattern = new(
        @"^\s*<summary\b[^>]*>([\s\S]*?)</summary>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex HtmlSummaryOpenFragmentPattern = new(
        @"^\s*<summary\b[^>]*>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    internal static readonly Regex HtmlSummaryCloseFragmentPattern = new(
        @"^\s*</summary\s*>\s*$",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Точная проверка boolean атрибута open (исключает data-open и т.п.)
    internal static readonly Regex DetailsOpenAttrPattern = new(
        @"(?:^|\s)open(?:\s|=|$)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static bool TryGetCachedHtml(HtmlCacheKey key, out string html)
    {
        lock (HtmlCacheLock)
        {
            if (!HtmlCache.TryGetValue(key, out html!))
                return false;

            if (HtmlCacheNodes.TryGetValue(key, out var node))
            {
                HtmlCacheLru.Remove(node);
                HtmlCacheLru.AddFirst(node);
            }
            return true;
        }
    }

    private static void PutCachedHtml(HtmlCacheKey key, string html)
    {
        if (html.Length > HtmlCacheMaxCharsPerEntry)
            return;

        lock (HtmlCacheLock)
        {
            if (HtmlCache.TryGetValue(key, out _))
            {
                HtmlCache[key] = html;
                if (HtmlCacheNodes.TryGetValue(key, out var existing))
                {
                    HtmlCacheLru.Remove(existing);
                    HtmlCacheLru.AddFirst(existing);
                }
                else
                {
                    var node = new LinkedListNode<HtmlCacheKey>(key);
                    HtmlCacheNodes[key] = node;
                    HtmlCacheLru.AddFirst(node);
                }
                return;
            }

            HtmlCache[key] = html;
            var newNode = new LinkedListNode<HtmlCacheKey>(key);
            HtmlCacheNodes[key] = newNode;
            HtmlCacheLru.AddFirst(newNode);

            while (HtmlCache.Count > HtmlCacheMaxEntries)
            {
                var last = HtmlCacheLru.Last;
                if (last is null)
                    break;
                HtmlCacheLru.RemoveLast();
                HtmlCache.Remove(last.Value);
                HtmlCacheNodes.Remove(last.Value);
            }
        }
    }

    private static Encoding GetSystemAnsiEncoding()
    {
        try
        {
            int cp = CultureInfo.CurrentCulture.TextInfo.ANSICodePage;
            return Encoding.GetEncoding(cp);
        }
        catch
        {
            return Encoding.UTF8;
        }
    }

    private static string ReadAllTextSequential(string filename)
    {
        try
        {
            using var fs = new FileStream(
                filename,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite,
                bufferSize: 64 * 1024,
                options: FileOptions.SequentialScan);

            using var sr = new StreamReader(fs, Utf8Strict, detectEncodingFromByteOrderMarks: true, bufferSize: 64 * 1024);
            return sr.ReadToEnd();
        }
        catch (DecoderFallbackException)
        {
            using var fs = new FileStream(
                filename,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite,
                bufferSize: 64 * 1024,
                options: FileOptions.SequentialScan);

            using var sr = new StreamReader(fs, SystemAnsi, detectEncodingFromByteOrderMarks: true, bufferSize: 64 * 1024);
            return sr.ReadToEnd();
        }
    }

    private static string GetCssContent(string? cssFile)
    {
        if (string.IsNullOrWhiteSpace(cssFile) || !File.Exists(cssFile))
            return "";

        DateTime lastWrite = File.GetLastWriteTimeUtc(cssFile);
        if (CssCache.TryGetValue(cssFile, out var cached) && cached.LastWriteTimeUtc == lastWrite)
            return cached.Content;

        string content = File.ReadAllText(cssFile);
        CssCache[cssFile] = new CssCacheEntry(lastWrite, content);
        return content;
    }

    private static MarkdownPipeline GetPipeline(string? extensions)
    {
        string key = (extensions ?? "").Trim();
        return PipelineCache.GetOrAdd(key, static exts =>
        {
            var builder = new MarkdownPipelineBuilder();

            builder.UseEmphasisExtras()
                   .UseAutoLinks()
                   .UseListExtras()
                   .UseCustomContainers()
                   .UseGenericAttributes();

            bool all = string.IsNullOrEmpty(exts) || exts.Contains("advanced", StringComparison.OrdinalIgnoreCase);
            bool allowHtml = exts.Contains("allowhtml", StringComparison.OrdinalIgnoreCase) ||
                             exts.Contains("unsafehtml", StringComparison.OrdinalIgnoreCase);

            if (!allowHtml)
                builder.Extensions.Add(new SafeRawHtmlAllowlistExtension());

            if (all || exts.Contains("pipetables", StringComparison.OrdinalIgnoreCase)) builder.UsePipeTables();
            if (all || exts.Contains("gridtables", StringComparison.OrdinalIgnoreCase)) builder.UseGridTables();
            if (all || exts.Contains("footnotes", StringComparison.OrdinalIgnoreCase)) builder.UseFootnotes();
            if (all || exts.Contains("citations", StringComparison.OrdinalIgnoreCase)) builder.UseCitations();
            if (all || exts.Contains("abbreviations", StringComparison.OrdinalIgnoreCase)) builder.UseAbbreviations();
            if (all || exts.Contains("emojis", StringComparison.OrdinalIgnoreCase)) builder.UseEmojiAndSmiley();
            if (all || exts.Contains("definitionlists", StringComparison.OrdinalIgnoreCase)) builder.UseDefinitionLists();
            if (all || exts.Contains("figures", StringComparison.OrdinalIgnoreCase)) builder.UseFigures();
            if (all || exts.Contains("mathematics", StringComparison.OrdinalIgnoreCase)) builder.UseMathematics();
            if (all || exts.Contains("bootstrap", StringComparison.OrdinalIgnoreCase)) builder.UseBootstrap();
            if (all || exts.Contains("medialinks", StringComparison.OrdinalIgnoreCase)) builder.UseMediaLinks();
            if (all || exts.Contains("smartypants", StringComparison.OrdinalIgnoreCase)) builder.UseSmartyPants();
            if (all || exts.Contains("autoidentifiers", StringComparison.OrdinalIgnoreCase))
                builder.UseAutoIdentifiers(AutoIdentifierOptions.GitHub);  // GitHub-style: сохраняет кириллицу в id
            if (all || exts.Contains("tasklists", StringComparison.OrdinalIgnoreCase)) builder.UseTaskLists();
            if (all || exts.Contains("diagrams", StringComparison.OrdinalIgnoreCase)) builder.UseDiagrams();
            if (all || exts.Contains("yaml", StringComparison.OrdinalIgnoreCase))
            {
                builder.UseYamlFrontMatter();
                builder.Extensions.Add(new GitHubStyleYamlExtension());
            }

            return builder.Build();
        });
    }

    [UnmanagedCallersOnly(EntryPoint = "ConvertMarkdownToHtml", CallConvs = [typeof(CallConvStdcall)])]
    public static unsafe IntPtr ConvertMarkdownToHtml(IntPtr filenamePtr, IntPtr cssFilePtr, IntPtr extensionsPtr)
    {
        try
        {
            string filename = Marshal.PtrToStringAnsi(filenamePtr) ?? "";
            string cssFile = Marshal.PtrToStringAnsi(cssFilePtr) ?? "";
            string extensions = Marshal.PtrToStringAnsi(extensionsPtr) ?? "";

            if (!File.Exists(filename))
            {
                return CreateNativeString("<html><body><h1>Error</h1><p>File not found</p></body></html>");
            }

            var mdInfo = new FileInfo(filename);
            DateTime mdLastWriteUtc = mdInfo.LastWriteTimeUtc;
            long mdLength = mdInfo.Length;
            DateTime cssLastWriteUtc = File.Exists(cssFile) ? File.GetLastWriteTimeUtc(cssFile) : default;

            string filenameKey = filename.ToLowerInvariant();
            string cssFileKey = (cssFile ?? "").ToLowerInvariant();
            string extensionsKey = (extensions ?? "").Trim().ToLowerInvariant();

            var cacheKey = new HtmlCacheKey(
                FilenameKey: filenameKey,
                MdLastWriteTicksUtc: mdLastWriteUtc.Ticks,
                MdLength: mdLength,
                CssFileKey: cssFileKey,
                CssLastWriteTicksUtc: cssLastWriteUtc.Ticks,
                ExtensionsKey: extensionsKey);

            if (TryGetCachedHtml(cacheKey, out string cachedHtml))
            {
                return CreateNativeString(cachedHtml);
            }

            string source = ReadAllTextSequential(filename);
            source = ReplaceGitHubEmojiOutsideCodeBlocks(source);

            // Удаляем опасные HTML-блоки целиком (тег + содержимое), если HTML не разрешён
            bool _allowHtmlForStrip = extensionsKey.Contains("allowhtml", StringComparison.OrdinalIgnoreCase)
                                   || extensionsKey.Contains("unsafehtml", StringComparison.OrdinalIgnoreCase);
            if (!_allowHtmlForStrip)
                source = StripDangerousHtmlBlocks(source);

            var pipeline = GetPipeline(extensionsKey);

            bool all = extensionsKey.Length == 0 || extensionsKey.Contains("advanced", StringComparison.OrdinalIgnoreCase);
            bool diagramsEnabled = all || extensionsKey.Contains("diagrams", StringComparison.OrdinalIgnoreCase);

            // Feature flags coming from C++ via extensions string ("|sh:on|sh-theme:dark"), explicit token compare to avoid substring false positives.
            var extensionTokens = extensionsKey.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            bool syntaxHighlightEnabled = extensionTokens.Contains("sh:on", StringComparer.OrdinalIgnoreCase);
            bool syntaxHighlightDarkTheme = extensionTokens.Contains("sh-theme:dark", StringComparer.OrdinalIgnoreCase);

            string cssContent = GetCssContent(cssFile);

            var sb = new StringBuilder(source.Length + cssContent.Length + 2048);
            sb.AppendLine("<!DOCTYPE html>");
            sb.AppendLine("<html><head>");
            sb.AppendLine("<meta charset='utf-8'>");

            sb.Append("<style>");
            sb.Append(cssContent);
            sb.Append("</style>");
            if (diagramsEnabled)
            {
                sb.AppendLine("<script src='https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js' defer></script>");
                sb.AppendLine("<script>window.addEventListener('load',function(){if(window.mermaid){try{mermaid.initialize({startOnLoad:true,theme:'default'});}catch(e){}}});</script>");
            }
            if (syntaxHighlightEnabled)
            {
                string hljsTheme = syntaxHighlightDarkTheme ? "github-dark" : "github";
                sb.Append("<link rel='stylesheet' href='https://cdn.jsdelivr.net/npm/highlight.js@11/styles/").Append(hljsTheme).AppendLine(".min.css'>");
                sb.AppendLine("<script src='https://cdn.jsdelivr.net/npm/highlight.js@11/lib/common.min.js' defer></script>");
                sb.AppendLine("<script>window.addEventListener('load',function(){if(!window.hljs)return;var aliasMap={'c#':'csharp','f#':'fsharp'};document.querySelectorAll('pre code:not(.language-mermaid)').forEach(function(b){var lc=b.className.split(/\\s+/).find(function(c){return c.indexOf('language-')===0;});if(!lc)return;var lang=lc.substring(9).toLowerCase();lang=aliasMap[lang]||lang;if(!window.hljs.getLanguage(lang))return;try{var r=hljs.highlight(b.textContent||'',{language:lang,ignoreIllegals:true});b.innerHTML=r.value;b.classList.add('hljs');b.dataset.highlighted='yes';}catch(e){}});});</script>");
            }
            sb.AppendLine("</head>");
            sb.AppendLine("<body>");
            string renderedHtml = Markdown.ToHtml(source, pipeline);
            renderedHtml = StandaloneAnchorParagraphPattern.Replace(renderedHtml, "$1");
            sb.AppendLine(renderedHtml);
            sb.AppendLine("<script>(function(){var n=function(s){return (s||'').replace(/-/g,' ').trim().toLowerCase();};var hs=Array.prototype.slice.call(document.querySelectorAll('h1,h2,h3,h4,h5,h6'));document.querySelectorAll('a[href^=\"#\"]').forEach(function(a){a.removeAttribute('title');var href=a.getAttribute('href');if(!href||href.length<2)return;var frag=href.slice(1);var decoded;try{decoded=decodeURIComponent(frag);}catch(e){decoded=frag;}if(document.getElementById(decoded)||document.getElementById(frag))return;var norm=n(decoded);if(!norm)return;for(var i=0;i<hs.length;i++){var h=hs[i];if(n(h.textContent)===norm){if(h.id){var span=document.createElement('span');span.id=decoded;h.parentNode.insertBefore(span,h);}else{h.id=decoded;}break;}}});})();</script>");
            sb.AppendLine("<script>document.addEventListener('click',function(e){var a=e.target;while(a&&a.tagName!=='A'){a=a.parentElement;}if(!a)return;var href=a.getAttribute('href');if(!href||href.length<2||href[0]!=='#')return;e.preventDefault();},true);</script>");
            sb.AppendLine("</body>");
            sb.AppendLine("</html>");

            string html = sb.ToString();
            PutCachedHtml(cacheKey, html);
            return CreateNativeString(html);
        }
        catch (Exception ex)
        {
            return CreateNativeString($"<html><body><h1>Error</h1><p>{ex.Message}</p></body></html>");
        }
    }

    private static IntPtr CreateNativeString(string text)
    {
        byte[] utf8Bytes = Encoding.UTF8.GetBytes(text);
        IntPtr nativeString = Marshal.AllocHGlobal(utf8Bytes.Length + 1);
        Marshal.Copy(utf8Bytes, 0, nativeString, utf8Bytes.Length);
        Marshal.WriteByte(nativeString, utf8Bytes.Length, 0);
        return nativeString;
    }

    [UnmanagedCallersOnly(EntryPoint = "FreeHtmlBuffer", CallConvs = [typeof(CallConvStdcall)])]
    public static void FreeHtmlBuffer(IntPtr buffer)
    {
        if (buffer != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    sealed class SafeAnchorHtmlInlineRenderer : HtmlObjectRenderer<HtmlInline>
    {
        protected override void Write(HtmlRenderer renderer, HtmlInline obj)
        {
            string tag = obj.Tag ?? string.Empty;

            // Закрывающий </a>
            if (AnchorCloseTagPattern.IsMatch(tag))
            {
                renderer.Write("</a>");
                return;
            }

            // <a name|id="x"> якорь
            var m = AnchorOpenTagPattern.Match(tag);
            if (m.Success)
            {
                string id = m.Groups[3].Value;
                if (!SafeIdPattern.IsMatch(id)) return;

                renderer.Write("<a name=\"").Write(id).Write("\" id=\"").Write(id).Write("\">");

                if (SelfClosingTagSuffix.IsMatch(tag))
                    renderer.Write("</a>");
                return;
            }

            // Self-closing void inline теги: <br>, <br/>, <wbr>
            var voidMatch = AnyVoidInlineTagPattern.Match(tag);
            if (voidMatch.Success && SafeVoidInlineTags.Contains(voidMatch.Groups[1].Value))
            {
                renderer.Write("<").Write(voidMatch.Groups[1].Value.ToLowerInvariant()).Write(">");
                return;
            }

            // Открывающие paired inline теги: <sub>, <sup>, <kbd>, <mark>, <ins>, <del>, <small>, <abbr>, <cite>, <q>
            var pairedOpen = AnyPairedOpenInlineTagPattern.Match(tag);
            if (pairedOpen.Success && SafePairedInlineTags.Contains(pairedOpen.Groups[1].Value))
            {
                renderer.Write("<").Write(pairedOpen.Groups[1].Value.ToLowerInvariant()).Write(">");
                return;
            }

            // Закрывающие paired inline теги
            var pairedClose = AnyPairedCloseInlineTagPattern.Match(tag);
            if (pairedClose.Success && SafePairedInlineTags.Contains(pairedClose.Groups[1].Value))
            {
                renderer.Write("</").Write(pairedClose.Groups[1].Value.ToLowerInvariant()).Write(">");
                return;
            }

            // Всё остальное (script, style, img, iframe, etc.) — стрипаем
        }
    }

    sealed class SafeHtmlBlockRenderer : HtmlObjectRenderer<HtmlBlock>
    {
        protected override void Write(HtmlRenderer renderer, HtmlBlock obj)
        {
            var lines = obj.Lines.Lines;
            var sb = new StringBuilder();
            for (int i = 0; i < obj.Lines.Count; i++)
                sb.AppendLine(lines[i].Slice.ToString());
            string content = sb.ToString().Trim();

            // <hN id="x">text</hN>
            var hMatch = HtmlHeadingBlockPattern.Match(content);
            if (hMatch.Success)
            {
                string level = hMatch.Groups[1].Value.ToLowerInvariant();
                string id = hMatch.Groups[3].Value;
                string inner = hMatch.Groups[4].Value.Trim();

                if (!SafeIdPattern.IsMatch(id)) return;

                renderer.Write("<").Write(level).Write(" id=\"").Write(id).Write("\">");
                renderer.WriteEscape(inner);
                renderer.Write("</").Write(level).Write(">").WriteLine();
                return;
            }

            // <hr>
            if (HtmlHrFragmentPattern.IsMatch(content))
            {
                renderer.Write("<hr/>").WriteLine();
                return;
            }

            // Compact full-block <details ...>...</details> в одном HtmlBlock.
            // Должен проверяться ПЕРЕД open-fragment regex (иначе open-pattern сработает на полном блоке).
            var detailsFull = HtmlDetailsFullBlockPattern.Match(content);
            if (detailsFull.Success)
            {
                string attrs = detailsFull.Groups[1].Value;
                bool isOpen = DetailsOpenAttrPattern.IsMatch(attrs);

                renderer.Write(isOpen ? "<details open>" : "<details>");

                if (detailsFull.Groups[2].Success)
                {
                    renderer.Write("<summary>");
                    renderer.WriteEscape(detailsFull.Groups[2].Value);
                    renderer.Write("</summary>");
                }

                string inner = detailsFull.Groups[3].Value.Trim();
                if (!string.IsNullOrEmpty(inner))
                {
                    // Compact-mode: inner content рендерится как escape'нутый текст.
                    // Для markdown в details — использовать пустые строки (fragment mode).
                    renderer.Write("<p>");
                    renderer.WriteEscape(inner);
                    renderer.Write("</p>");
                }

                renderer.Write("</details>").WriteLine();
                return;
            }

            // <details ...> [+ optional <summary>X</summary>] (fragment mode, без </details>)
            var detailsOpen = HtmlDetailsOpenFragmentPattern.Match(content);
            if (detailsOpen.Success)
            {
                string attrs = detailsOpen.Groups[1].Value;
                bool isOpen = DetailsOpenAttrPattern.IsMatch(attrs);
                renderer.Write(isOpen ? "<details open>" : "<details>");

                if (detailsOpen.Groups[2].Success)
                {
                    renderer.Write("<summary>");
                    renderer.WriteEscape(detailsOpen.Groups[2].Value);
                    renderer.Write("</summary>");
                }
                renderer.WriteLine();
                return;
            }

            // </details>
            if (HtmlDetailsCloseFragmentPattern.IsMatch(content))
            {
                renderer.Write("</details>").WriteLine();
                return;
            }

            // <summary>full</summary>
            var summaryFull = HtmlSummaryFullFragmentPattern.Match(content);
            if (summaryFull.Success)
            {
                renderer.Write("<summary>");
                renderer.WriteEscape(summaryFull.Groups[1].Value);
                renderer.Write("</summary>").WriteLine();
                return;
            }

            // <summary> open
            if (HtmlSummaryOpenFragmentPattern.IsMatch(content))
            {
                renderer.Write("<summary>").WriteLine();
                return;
            }

            // </summary>
            if (HtmlSummaryCloseFragmentPattern.IsMatch(content))
            {
                renderer.Write("</summary>").WriteLine();
                return;
            }

            // Не наш формат — стрипаем (как DisableHtml)
        }
    }

    sealed class SafeRawHtmlAllowlistExtension : IMarkdownExtension
    {
        public void Setup(MarkdownPipelineBuilder pipeline) { }

        public void Setup(MarkdownPipeline pipeline, IMarkdownRenderer renderer)
        {
            if (renderer is not HtmlRenderer h) return;

            var inlineExisting = h.ObjectRenderers.FindExact<HtmlInlineRenderer>();
            if (inlineExisting != null) h.ObjectRenderers.Remove(inlineExisting);
            h.ObjectRenderers.Add(new SafeAnchorHtmlInlineRenderer());

            var blockExisting = h.ObjectRenderers.FindExact<HtmlBlockRenderer>();
            if (blockExisting != null) h.ObjectRenderers.Remove(blockExisting);
            h.ObjectRenderers.Add(new SafeHtmlBlockRenderer());
        }
    }

    sealed class GitHubStyleYamlFrontMatterRenderer : HtmlObjectRenderer<YamlFrontMatterBlock>
    {
        protected override void Write(HtmlRenderer renderer, YamlFrontMatterBlock obj)
        {
            renderer.Write("<table class=\"markdown-frontmatter\"><tbody>");

            for (int i = 0; i < obj.Lines.Count; i++)
            {
                string line = obj.Lines.Lines[i].Slice.ToString();
                string trimmed = line.Trim();

                // Пропускаем разделители "---" и пустые строки
                if (string.IsNullOrEmpty(trimmed) || trimmed == "---") continue;

                int colon = trimmed.IndexOf(':');
                if (colon <= 0) continue;

                string key = trimmed.Substring(0, colon).Trim();
                string value = trimmed.Substring(colon + 1).Trim();

                // Снимаем парные кавычки если есть
                if (value.Length >= 2 &&
                    (value[0] == '"' || value[0] == '\'') &&
                    value[value.Length - 1] == value[0])
                {
                    value = value.Substring(1, value.Length - 2);
                }

                renderer.Write("<tr><th>");
                renderer.WriteEscape(key);
                renderer.Write("</th><td>");
                renderer.WriteEscape(value);
                renderer.Write("</td></tr>");
            }

            renderer.Write("</tbody></table>");
            renderer.WriteLine();
        }
    }

    sealed class GitHubStyleYamlExtension : IMarkdownExtension
    {
        public void Setup(MarkdownPipelineBuilder pipeline) { }

        public void Setup(MarkdownPipeline pipeline, IMarkdownRenderer renderer)
        {
            if (renderer is not HtmlRenderer h) return;

            // Markdig 0.40.0 регистрирует пустой YamlFrontMatterHtmlRenderer (стрипает блок).
            // Заменяем на свой, рендерящий как GitHub-style таблицу.
            var existing = h.ObjectRenderers.FindExact<YamlFrontMatterHtmlRenderer>();
            if (existing != null) h.ObjectRenderers.Remove(existing);

            // КРИТИЧНО: Insert(0, ...) — YamlFrontMatterBlock наследуется от CodeBlock.
            // Если добавить в конец списка, CodeBlockRenderer перехватит блок и отрендерит как <pre><code>.
            // Insert в начало гарантирует, что наш renderer проверится первым.
            h.ObjectRenderers.Insert(0, new GitHubStyleYamlFrontMatterRenderer());
        }
    }
}
