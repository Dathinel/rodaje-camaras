# Pruebas numéricas de las LUT de rodaje-camaras. Solo necesita Windows PowerShell 5.1.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File probar.ps1
# Genera las LUT en una carpeta temporal con generar.ps1 y, sin usar su código, comprueba:
#  - que las curvas de codificación, escritas aquí en el sentido contrario al del generador (lineal → log), dan los
#    valores que publica cada fabricante para el gris 18 % (y el blanco del 90 % donde el documento lo da);
#  - que la LUT, muestreada con interpolación trilineal en el gris 18 % y en el blanco de referencia de cada curva,
#    da lo que espera la cadena (mapeo de tonos y BT.1886 calculados aquí aparte);
#  - que el eje neutro sube siempre, que hay 33³ filas y que no hay valores fuera de 0–1 ni NaN.
# Sale con 0 si todo pasa.

$ErrorActionPreference = 'Stop'
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rodaje-camaras-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fallos = 0

function Revisar([string]$que, [double]$valor, [double]$esperado, [double]$tol) {
    $ok = [math]::Abs($valor - $esperado) -le $tol
    $color = if ($ok) { 'Gray' } else { 'Red' }
    Write-Host ("  {0,-46} {1,9:0.00000}  esperado {2,9:0.00000}  ±{3}" -f $que, $valor, $esperado, $tol) -ForegroundColor $color
    if (-not $ok) { $script:fallos++ }
}

# Lineal de escena (0,18 = gris 18 %) → valor de la curva, según cada documento.
function Codificar([string]$curva, [double]$x) {
    switch ($curva) {
        's-log3' { return (420.0 + [math]::Log10(($x + 0.01) / 0.19) * 261.5) / 1023.0 }
        'v-log' { return 0.241514 * [math]::Log10($x + 0.00873) + 0.598206 }
        'c-log2' { return 0.281863093 * [math]::Log10($x / 0.9 * 87.09937546 + 1) + 0.035388128 }
        'c-log3' { return 0.36726845 * [math]::Log10($x / 0.9 * 14.98325 + 1) + 0.12240537 }
        'log-c3' { return 0.247190 * [math]::Log10(5.555556 * $x + 0.052272) + 0.385537 }
        'bmd-film-gen5' { return 0.08692876065491224 * [math]::Log($x + 0.005494072432257808) + 0.5300133392291939 }
        'f-log' { return 0.344676 * [math]::Log10(0.555556 * $x + 0.009468) + 0.790453 }
        'n-log' { if ($x -ge 0.328) { return (150.0 * [math]::Log($x) + 619.0) / 1023.0 } else { return 650.0 * [math]::Pow($x + 0.0075, 1.0 / 3) / 1023.0 } }
    }
}

# Curvas en la escala de video (0 % = código 64) y las que van sobre el código de 0 a 1023.
$enVideo = @('c-log2', 'c-log3', 'hlg')
function NivelDeVideo([string]$curva, [double]$valor) {
    if ($enVideo -contains $curva) { return $valor } else { return ($valor * 1023.0 - 64.0) / 876.0 }
}

# HLG, BT.2100: inversa de la OETF.
function HlgLineal([double]$e) {
    if ($e -le 0.5) { return $e * $e / 3.0 }
    return ([math]::Exp(($e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0
}

# Mapeo de tonos y BT.1886 (gamma 2,4), calculados aparte del generador.
$p = 1.1; $A = [math]::Pow(16.0, $p); $G = [math]::Pow(0.18, $p); $t = [math]::Pow(0.43, 2.4)
$d = $A * $G * (1 - $t) / ($t * $A - $G); $c = ($A + $d) / $A
function Senal([double]$x) {
    if ($x -le 0) { return 0.0 }
    $xp = [math]::Pow($x, $p)
    return [math]::Pow([math]::Min(1.0, $c * $xp / ($xp + $d)), 1.0 / 2.4)
}

function LeerCube([string]$ruta) {
    $datos = New-Object 'double[]' (33 * 33 * 33 * 3)
    $i = 0
    foreach ($linea in [System.IO.File]::ReadAllLines($ruta)) {
        if ($linea.Length -eq 0 -or -not ([char]::IsDigit($linea[0]) -or $linea[0] -eq '-')) { continue }
        foreach ($n in $linea.Split(' ')) { $datos[$i] = [double]::Parse($n, $inv); $i++ }
    }
    if ($i -ne $datos.Length) { throw "$ruta tiene $($i / 3) filas en lugar de 35937." }
    return , $datos
}

function Muestra($lut, [double]$r, [double]$g, [double]$b, [int]$canal) {
    $n = 32
    $fx = $r * $n; $fy = $g * $n; $fz = $b * $n
    $x0 = [math]::Min([int][math]::Floor($fx), $n - 1); $y0 = [math]::Min([int][math]::Floor($fy), $n - 1); $z0 = [math]::Min([int][math]::Floor($fz), $n - 1)
    $tx = $fx - $x0; $ty = $fy - $y0; $tz = $fz - $z0
    $s = 0.0
    foreach ($dz in 0, 1) { foreach ($dy in 0, 1) { foreach ($dx in 0, 1) {
        $w = $(if ($dx) { $tx } else { 1 - $tx }) * $(if ($dy) { $ty } else { 1 - $ty }) * $(if ($dz) { $tz } else { 1 - $tz })
        $s += $w * $lut[((($z0 + $dz) * 33 + ($y0 + $dy)) * 33 + ($x0 + $dx)) * 3 + $canal]
    } } }
    return $s
}

# Interpolación tetraédrica en un punto del eje neutro: solo cuentan los dos nodos neutros de la celda.
function Neutro($lut, [double]$v, [int]$canal) {
    $f = $v * 32; $k = [math]::Min([int][math]::Floor($f), 31); $u = $f - $k
    $a = $lut[(($k * 33 + $k) * 33 + $k) * 3 + $canal]; $b = $lut[((($k + 1) * 33 + $k + 1) * 33 + $k + 1) * 3 + $canal]
    return $a + ($b - $a) * $u
}

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'generar.ps1') -Destino $tmp
    if ($LASTEXITCODE -ne 0) { throw "generar.ps1 falló." }

    Write-Host "Valores publicados por cada fabricante"
    Revisar 'S-Log3: 18 % → código 420' (Codificar 's-log3' 0.18) (420 / 1023.0) 0.0001
    Revisar 'S-Log3: 90 % → código 598' (Codificar 's-log3' 0.90) (598 / 1023.0) 0.0005
    Revisar 'V-Log: 18 % → 0,4233' (Codificar 'v-log' 0.18) 0.4233 0.0001
    Revisar 'Canon Log 2: 18 % → 39,2 %' (Codificar 'c-log2' 0.18) 0.392 0.0005
    Revisar 'Canon Log 3: 18 % → 34,3 %' (Codificar 'c-log3' 0.18) 0.343 0.0005
    Revisar 'Log C3 EI 800: 18 % → código 400' (Codificar 'log-c3' 0.18) (400 / 1023.0) 0.0002
    Revisar 'Film Gen 5: 18 % → 0,3836' (Codificar 'bmd-film-gen5' 0.18) 0.3836 0.0002
    Revisar 'F-Log: 18 % → código 470' (Codificar 'f-log' 0.18) (470 / 1023.0) 0.0005
    Revisar 'F-Log: 90 % → código 705' (Codificar 'f-log' 0.90) (705 / 1023.0) 0.0005
    Revisar 'N-Log: 18 % → código 372' (Codificar 'n-log' 0.18) (372 / 1023.0) 0.0005
    Revisar 'HLG: señal 0,5 ↔ lineal 1/12' (HlgLineal 0.5) (1 / 12.0) 0.000001
    Revisar 'HLG: 75 % (blanco BT.2408) → lineal 0,2650' (HlgLineal 0.75) 0.2650 0.0001

    # En el eje neutro la interpolación tetraédrica solo usa los dos nodos neutros de la celda: el error es el de la curva
    # entre dos nodos, por debajo de 0,002. La trilineal (la de la GPU) mezcla además seis nodos fuera del eje, donde la
    # matriz de gama ya cruza canales; en gamas anchas eso mueve hasta unas 0,007 (menos de 2 niveles de 8 bits).
    $tol = 0.002
    $tolTrilineal = 0.008
    foreach ($curva in 's-log3', 'v-log', 'c-log2', 'c-log3', 'log-c3', 'bmd-film-gen5', 'f-log', 'n-log', 'hlg') {
        Write-Host "`n$curva"
        $lut = LeerCube (Join-Path $tmp "luts\$curva.cube")
        if ($curva -eq 'hlg') {
            $escala = 0.18 / (HlgLineal 0.38)
            $blanco = (HlgLineal 0.75) * $escala
            $puntos = @(@('gris 18 % (señal 38 %)', 0.38, 0.18), @('blanco de referencia (señal 75 %)', 0.75, $blanco))
        } else {
            $puntos = @(@('gris 18 %', (NivelDeVideo $curva (Codificar $curva 0.18)), 0.18), @('blanco 90 %', (NivelDeVideo $curva (Codificar $curva 0.90)), 0.90))
        }
        foreach ($punto in $puntos) {
            $v = $punto[1]; $esperado = Senal $punto[2]
            foreach ($canal in 0, 1, 2) {
                Revisar ("{0} ({1:0.0000}), {2}, tetraédrica" -f $punto[0], $v, 'RGB'[$canal]) (Neutro $lut $v $canal) $esperado $tol
                Revisar ("{0} ({1:0.0000}), {2}, trilineal" -f $punto[0], $v, 'RGB'[$canal]) (Muestra $lut $v $v $v $canal) $esperado $tolTrilineal
            }
        }

        $previo = -1.0; $sube = $true; $rango = $true
        for ($k = 0; $k -lt 33; $k++) {
            $y = $lut[(($k * 33 + $k) * 33 + $k) * 3 + 1]
            if ($y -lt $previo) { $sube = $false }
            $previo = $y
        }
        foreach ($x in $lut) { if ([double]::IsNaN($x) -or $x -lt 0 -or $x -gt 1) { $rango = $false; break } }
        if ($sube -and $rango) { Write-Host '  eje neutro creciente, sin NaN ni valores fuera de 0–1' -ForegroundColor Gray }
        else { Write-Host "  eje neutro creciente: $sube; valores en 0–1: $rango" -ForegroundColor Red; $fallos++ }
    }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fallos -gt 0) { Write-Host "`n$fallos comprobaciones fallaron." -ForegroundColor Red; exit 1 }
Write-Host "`nTodo bien." -ForegroundColor Green
exit 0
