param(
    [Parameter(Mandatory = $true, Position = 0)][string]$File,
    [ValidateSet('png', 'svg')][string]$Format = 'png',
    [string]$OutDir = (Join-Path $env:TEMP 'puml-out'),
    [switch]$Check
)
# Renderiza un .puml con PlantUML + Graphviz y, opcionalmente, verifica que no haya cruces.
$ErrorActionPreference = 'Stop'

# 1) plantuml.jar: variable PLANTUML_JAR o extensión de VS Code / Antigravity
$jar = $env:PLANTUML_JAR
if (-not $jar) {
    $jar = Get-ChildItem -Path "$env:USERPROFILE\.vscode*\extensions", "$env:USERPROFILE\.antigravity*\extensions" `
        -Recurse -Filter 'plantuml*.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $jar) { throw 'No se encontró plantuml.jar. Define PLANTUML_JAR.' }

# 2) Graphviz: GRAPHVIZ_DOT, PATH o carpetas comunes
if (-not $env:GRAPHVIZ_DOT) {
    $dot = Get-Command dot -ErrorAction SilentlyContinue
    if (-not $dot) {
        $dot = Get-ChildItem 'C:\Program Files\Graphviz*\bin\dot.exe', 'C:\Program Files (x86)\Graphviz*\bin\dot.exe' `
            -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $dot) { throw 'No se encontró Graphviz (dot). Instálalo o define GRAPHVIZ_DOT.' }
    $env:GRAPHVIZ_DOT = if ($dot.Source) { $dot.Source } else { $dot.FullName }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
java -jar $jar -charset UTF-8 "-t$Format" -o $OutDir $File
if ($LASTEXITCODE -ne 0) { throw 'PlantUML devolvió errores.' }

$base = [IO.Path]::GetFileNameWithoutExtension($File)
$out = Join-Path $OutDir "$base.$Format"
Write-Host "Generado: $out"

if ($Check) {
    if ($Format -ne 'svg') { throw '-Check requiere -Format svg.' }
    python (Join-Path $PSScriptRoot 'check_crossings.py') $out
    exit $LASTEXITCODE
}
