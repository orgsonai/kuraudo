param(
    [switch]$SkipBuild,
    [string]$GoogleClientSecretFile,
    [switch]$DeleteSecretFileAfterBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot

$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
if (-not $versionLine) {
    throw 'Could not read the application version from pubspec.yaml.'
}
$version = $versionLine.Matches[0].Groups[1].Value

try {
    if (-not $SkipBuild) {
        $flutterArgs = @('build', 'windows', '--release')
        if ($GoogleClientSecretFile) {
            if (-not (Test-Path -LiteralPath $GoogleClientSecretFile)) {
                throw "Google OAuth client JSON not found: $GoogleClientSecretFile"
            }
            $oauthJson = Get-Content -LiteralPath $GoogleClientSecretFile -Raw | ConvertFrom-Json
            $oauthClient = if ($oauthJson.installed) { $oauthJson.installed } else { $oauthJson.web }
            if (-not $oauthClient.client_secret) {
                throw 'client_secret was not found in the Google OAuth JSON.'
            }
            $flutterArgs += "--dart-define=GOOGLE_CLIENT_SECRET=$($oauthClient.client_secret)"
        }

        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
        flutter @flutterArgs
        if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    }
} finally {
    if ($DeleteSecretFileAfterBuild -and $GoogleClientSecretFile -and
        (Test-Path -LiteralPath $GoogleClientSecretFile)) {
        Remove-Item -LiteralPath $GoogleClientSecretFile -Force
    }
}

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $releaseDir 'kuraudo.exe'))) {
    throw "Release executable not found: $releaseDir"
}

$distDir = Join-Path $repoRoot 'dist\windows'
New-Item -ItemType Directory -Force $distDir | Out-Null

$portableZip = Join-Path $distDir "Kuraudo-$version-windows-x64-portable.zip"
if (Test-Path $portableZip) {
    Remove-Item $portableZip
}
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $portableZip -CompressionLevel Optimal

$isccCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw 'Inno Setup 6 is not installed.'
}

& $iscc "/DMyAppVersion=$version" (Join-Path $PSScriptRoot 'kuraudo.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }

Get-ChildItem $distDir -File | ForEach-Object {
    $hash = Get-FileHash $_.FullName -Algorithm SHA256
    [PSCustomObject]@{
        Name = $_.Name
        Bytes = $_.Length
        SHA256 = $hash.Hash
    }
} | Format-Table -AutoSize
