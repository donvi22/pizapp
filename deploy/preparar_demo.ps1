$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$appPath = Join-Path $projectRoot 'App'
$backendPath = Join-Path $projectRoot 'backend'
$outputPath = Join-Path $PSScriptRoot 'output'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stagingPath = Join-Path $outputPath $stamp
$stagedBackend = Join-Path $stagingPath 'backend'

Push-Location $appPath
try {
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Corrige flutter analyze antes de compilar.' }
    flutter build web --release --base-href=/app/ --dart-define=MAX_UPLOAD_MB=20
    if ($LASTEXITCODE -ne 0) { throw 'No se ha podido compilar Flutter web.' }
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Path $stagedBackend -Force | Out-Null
Get-ChildItem -Path $backendPath -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($backendPath.Length).TrimStart([char[]]'\/')
    $parts = $relativePath -split '[\\/]'
    $excluded = @('.venv', 'venv', 'media', 'staticfiles', '__pycache__', 'webapp')
    $skip = @($parts | Where-Object { $excluded -contains $_ }).Count -gt 0
    $allowed = $_.Extension -eq '.py' -or $relativePath -eq 'requirements-production.txt'
    if (!$skip -and $allowed) {
        $destination = Join-Path $stagedBackend $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination
    }
}
Copy-Item -Path (Join-Path $appPath 'build\web') -Destination (Join-Path $stagedBackend 'webapp') -Recurse
$zipPath = Join-Path $outputPath ('pizapp_demo_' + $stamp + '.zip')
Compress-Archive -Path (Join-Path $stagingPath '*') -DestinationPath $zipPath
Write-Host ('Paquete creado: ' + $zipPath)
