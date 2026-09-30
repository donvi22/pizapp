$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $raiz 'backend\manage.py')) -or -not (Test-Path (Join-Path $raiz 'App\pubspec.yaml'))) {
    throw 'Extrae el paquete en la raiz de PizarraApp, junto a App y backend.'
}
$utf8 = [System.Text.UTF8Encoding]::new($false)
$rutaIgnore = Join-Path $raiz '.gitignore'
$contenido = if (Test-Path $rutaIgnore) { [System.IO.File]::ReadAllText($rutaIgnore, [System.Text.Encoding]::UTF8) } else { '' }
$existentes = @($contenido -split '\r?\n')
$nuevas = @([System.IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'gitignore_pizapp.txt'), [System.Text.Encoding]::UTF8) | Where-Object { $_ -and $_ -notin $existentes })
if ($nuevas.Count -gt 0) {
    if ($contenido -and -not $contenido.EndsWith("`n")) { $contenido += "`r`n" }
    $contenido += ($nuevas -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($rutaIgnore, $contenido, $utf8)
}
$rutaReadme = Join-Path $raiz 'README.md'
$readme = [System.IO.File]::ReadAllText($rutaReadme, [System.Text.Encoding]::UTF8)
$capturas = @(
    @{ Nombre = '01-proyectos.png'; Texto = 'Proyectos' },
    @{ Nombre = '02-pizarra.png'; Texto = 'Pizarra de una tarea' },
    @{ Nombre = '03-reparto.png'; Texto = 'Reparto de responsables' },
    @{ Nombre = '04-resumen.png'; Texto = 'Resumen del proyecto' },
    @{ Nombre = '05-historial.png'; Texto = 'Historial de actividad' }
)
$bloques = @()
foreach ($captura in $capturas) {
    if (Test-Path (Join-Path $raiz ('docs\capturas\' + $captura.Nombre))) {
        $bloques += ('![' + $captura.Texto + '](docs/capturas/' + $captura.Nombre + ')')
    }
}
if ($bloques.Count -gt 0) {
    $patron = '(?s)<!-- CAPTURAS_INICIO -->.*?<!-- CAPTURAS_FIN -->'
    if (-not [regex]::IsMatch($readme, $patron)) { throw 'No se encuentran los marcadores de capturas en README.md.' }
    $bloque = "<!-- CAPTURAS_INICIO -->`n`n## Capturas`n`n" + ($bloques -join "`n`n") + "`n`n<!-- CAPTURAS_FIN -->"
    $readme = [regex]::Replace($readme, $patron, $bloque)
    [System.IO.File]::WriteAllText($rutaReadme, $readme, $utf8)
}
Write-Host 'README y reglas de exclusion preparados.'
Write-Host ('Capturas disponibles: ' + $bloques.Count)
Write-Host 'Antes de hacer commit, revisa git status y la guia portfolio/LEEME_github.md.'
