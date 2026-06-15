# 从 icon.svg 生成 Android / iOS 启动图标
# 用法: powershell -ExecutionPolicy Bypass -File .\scripts\generate_app_icon.ps1

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$SvgPath = Join-Path $ProjectRoot "icon.svg"
$AssetsDir = Join-Path $ProjectRoot "assets"
$PngPath = Join-Path $AssetsDir "icon.png"

if (-not (Test-Path $SvgPath)) {
    throw "icon.svg not found: $SvgPath"
}

New-Item -ItemType Directory -Force -Path $AssetsDir | Out-Null

Write-Host "Converting icon.svg -> assets/icon.png (1024x1024)..."
npx --yes @resvg/resvg-js-cli $SvgPath $PngPath --fit-width 1024 --fit-height 1024
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dart run flutter_launcher_icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "App icons generated from icon.svg"
