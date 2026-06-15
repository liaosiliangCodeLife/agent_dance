# Android Release APK build (AGENTS.md packaging rules)
# Usage: powershell -ExecutionPolicy Bypass -File .\scripts\build_android_apk.ps1

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

# 访问 GitHub 等国外资源时走本地代理
$ProxyUrl = "http://127.0.0.1:7897"
$env:HTTP_PROXY = $ProxyUrl
$env:HTTPS_PROXY = $ProxyUrl
$env:ALL_PROXY = $ProxyUrl
$env:NO_PROXY = "localhost,127.0.0.1"
$env:http_proxy = $ProxyUrl
$env:https_proxy = $ProxyUrl

$GradleProps = Join-Path $ProjectRoot "android\gradle.properties"
$ProxyLines = @(
    "systemProp.http.proxyHost=127.0.0.1",
    "systemProp.http.proxyPort=7897",
    "systemProp.https.proxyHost=127.0.0.1",
    "systemProp.https.proxyPort=7897"
)
$GradleContent = if (Test-Path $GradleProps) { Get-Content $GradleProps -Raw } else { "" }
foreach ($line in $ProxyLines) {
    $key = ($line -split '=')[0]
    if ($GradleContent -notmatch [regex]::Escape($key)) {
        Add-Content -Path $GradleProps -Value $line -Encoding UTF8
    }
}

$VersionFile = Join-Path $ProjectRoot "VERSION"
if (-not (Test-Path $VersionFile)) {
    throw "VERSION file not found"
}
$MainVersion = (Get-Content $VersionFile -Raw).Trim()
if ($MainVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must be x.y.z, got: $MainVersion"
}

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$PubspecLines = Get-Content $PubspecPath -Encoding UTF8
$BuildNumber = 1
for ($i = 0; $i -lt $PubspecLines.Count; $i++) {
    if ($PubspecLines[$i] -match '^version:\s*\d+\.\d+\.\d+\+(\d+)') {
        $BuildNumber = [int]$Matches[1]
        $PubspecLines[$i] = "version: $MainVersion+$BuildNumber"
        break
    }
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($PubspecPath, $PubspecLines, $Utf8NoBom)

$BuildDate = Get-Date -Format "yyyyMMdd"
$OutputName = "agent_dance-$MainVersion-$BuildDate.apk"
$OutputPath = Join-Path $ProjectRoot $OutputName

Write-Host "Version: $MainVersion"
Write-Host "Build date: $BuildDate"
Write-Host "Output: $OutputName"

# 从 icon.svg 生成启动图标
$IconScript = Join-Path $ProjectRoot "scripts\generate_app_icon.ps1"
if (Test-Path $IconScript) {
    & powershell -ExecutionPolicy Bypass -File $IconScript
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Push-Location (Join-Path $ProjectRoot "android")
& .\gradlew.bat --stop 2>$null
Pop-Location

if (Test-Path (Join-Path $ProjectRoot "build")) {
    Remove-Item -Recurse -Force (Join-Path $ProjectRoot "build") -ErrorAction SilentlyContinue
}

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build apk --release --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$BuiltApk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $BuiltApk)) {
    throw "Built APK not found: $BuiltApk"
}

Copy-Item -Path $BuiltApk -Destination $OutputPath -Force
Write-Host "Done: $OutputPath"
Get-Item $OutputPath | Format-List Name, Length, LastWriteTime
