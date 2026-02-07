# Disable plugin script - run as Administrator
$pluginDir = "C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle"
$disabledDir = "C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle.DISABLED"

Write-Host "Disabling plugin..."

if (Test-Path $pluginDir) {
    if (Test-Path $disabledDir) {
        Remove-Item $disabledDir -Recurse -Force
    }
    Rename-Item $pluginDir $disabledDir -Force
    Write-Host "Plugin disabled successfully!"
} else {
    Write-Host "Plugin directory not found"
}
