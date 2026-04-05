@echo off
setlocal

echo === Restore NuGet packages ===
msbuild MarkdownView.sln -t:Restore
if errorlevel 1 goto :fail

echo === Build MarkdigNative (Native AOT x64) ===
dotnet publish MarkdigNative/MarkdigNative.csproj -c Release -r win-x64
if errorlevel 1 goto :fail

echo === Build C++ components (x64) ===
msbuild MarkdownView.sln /p:Configuration=Release /p:Platform=x64
if errorlevel 1 goto :fail

echo === Pack plugin ===
if exist pack rd /s /q pack
mkdir pack\css

copy Build\pluginst.inf pack\
copy Build\MarkdownView.ini pack\
copy Build\css\*.css pack\css\
copy bin\Release\MarkdownView.wlx64 pack\
copy bin\Release\Markdown-x64.dll pack\
copy MarkdigNative\bin\Release\net8.0\win-x64\publish\MarkdigNative.dll pack\MarkdigNative-x64.dll

pushd pack
powershell -NoProfile -Command "Compress-Archive -Path '.\*' -DestinationPath '..\MarkdownViewGitHubStyle.zip' -Force"
popd

rd /s /q pack

echo === Done: MarkdownViewGitHubStyle.zip ===
goto :eof

:fail
echo === Build failed ===
exit /b 1
