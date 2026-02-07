# Install plugin script - run as Administrator
$pluginDir = "C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle"
$sourceDir = ".\bin\Release"

Write-Host "Installing plugin to $pluginDir"

# Create directories
if (!(Test-Path $pluginDir)) {
    New-Item -ItemType Directory -Path $pluginDir -Force
}
if (!(Test-Path "$pluginDir\css")) {
    New-Item -ItemType Directory -Path "$pluginDir\css" -Force
}
if (!(Test-Path "$pluginDir\runtimes\win-x64\native")) {
    New-Item -ItemType Directory -Path "$pluginDir\runtimes\win-x64\native" -Force
}

# Copy main plugin files
Copy-Item "$sourceDir\MarkdownView.wlx64" $pluginDir -Force
Copy-Item "$sourceDir\Markdown-x64.dll" $pluginDir -Force
Copy-Item "$sourceDir\MarkdigNative-x64.dll" $pluginDir -Force
Copy-Item "$sourceDir\MarkdownView.ini" $pluginDir -Force

# Copy CSS files
Copy-Item "$sourceDir\css\*" "$pluginDir\css\" -Force

# Copy WebView2Loader.dll
Copy-Item "GitHubRelease\runtimes\win-x64\native\WebView2Loader.dll" "$pluginDir\runtimes\win-x64\native\" -Force

Write-Host "Plugin installation completed!"
Write-Host "Files installed:"
Get-ChildItem $pluginDir -Recurse | ForEach-Object { Write-Host "  $($_.FullName)" }