# Enable plugin script - run as Administrator
$disabledDir = "C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle.DISABLED"
$pluginDir = "C:\Program Files\totalcmd\plugins\wlx\MarkdownViewGitHubStyle"

Write-Host "Enabling plugin..."

if (Test-Path $disabledDir) {
    if (Test-Path $pluginDir) {
        Remove-Item $pluginDir -Recurse -Force
    }
    Rename-Item $disabledDir $pluginDir -Force
    Write-Host "Plugin enabled successfully!"
} else {
    Write-Host "Disabled plugin directory not found"
}
