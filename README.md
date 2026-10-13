<p align="center">
  <a href="https://github.com/Dathinel/rodaje"><img src="https://raw.githubusercontent.com/Dathinel/rodaje/main/assets/marca/rodaje.svg" alt="Logotipo de Rodaje" width="104"></a>
</p>

<h1 align="center">rodaje-camaras</h1>

<p align="center">
  Complemento opcional para <a href="https://github.com/Dathinel/rodaje">Rodaje</a>: LUT 3D (33³) de log de cámara a Rec. 709, calculadas con las fórmulas que publica cada fabricante.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-CC0_1.0-E8833A?style=flat-square&labelColor=1D1D1D" alt="Licencia CC0 1.0"></a>
  <a href="https://github.com/Dathinel/rodaje-camaras/releases/latest"><img src="https://img.shields.io/github/v/release/Dathinel/rodaje-camaras?style=flat-square&labelColor=1D1D1D&color=E8833A&label=versi%C3%B3n" alt="Última versión"></a>
  <img src="https://img.shields.io/badge/contenido-9_LUT_de_c%C3%A1mara-E8833A?style=flat-square&labelColor=1D1D1D" alt="Contenido: 9 LUT de cámara">
  <img src="https://img.shields.io/badge/formato-.paquete-E8833A?style=flat-square&labelColor=1D1D1D" alt="Formato .paquete">
  <a href="https://github.com/Dathinel/rodaje"><img src="https://img.shields.io/badge/para-Rodaje-E8833A?style=flat-square&labelColor=1D1D1D" alt="Para Rodaje"></a>
</p>

Nueve conversiones, cada una un filtro listo para aplicar y una LUT suelta. Todas salen de `generar.ps1`: ninguna deriva de una LUT ajena.

| Id | Curva y gama | Documento técnico del que salen las fórmulas |
|---|---|---|
| `s-log3` | S-Log3, S-Gamut3.Cine | Sony, *Technical Summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3* (2014) |
| `v-log` | V-Log, V-Gamut | Panasonic, *V-Log/V-Gamut Reference Manual* (2014) |
| `c-log2` | Canon Log 2, Cinema Gamut | Canon, *Canon Log Gamma Curves: Description of the Canon Log, Canon Log 2 and Canon Log 3*, v1.2 (2018) |
| `c-log3` | Canon Log 3, Cinema Gamut | El mismo documento de Canon |
| `log-c3` | LogC3 a EI 800, ARRI Wide Gamut 3 | ARRI, *ALEXA Log C Curve: Usage in VFX* (2017) |
| `bmd-film-gen5` | Blackmagic Film y Wide Gamut de 5.ª generación | Blackmagic Design, *Blackmagic Generation 5 Color Science* (2021) |
| `f-log` | F-Log, F-Gamut (BT.2020) | Fujifilm, *F-Log Data Sheet* v1.0 (2016) |
| `n-log` | N-Log, BT.2020 | Nikon, *N-Log Specification Document* v1.0.0 (2018) |
| `hlg` | HLG, BT.2020, a rango estándar | ITU-R BT.2100-2 (2018) y ITU-R BT.2408 (2018) |

Los nombres de las cámaras y de sus curvas son marcas de sus dueños y aquí solo dicen con qué grabación funciona cada LUT. Las fórmulas son públicas: cada fabricante las publica para que se puedan usar en otros programas.

## Cómo se calculan

1. **Nivel de video → código.** Rodaje entrega la imagen en rango de video (0 es el código 64 y 1 el 940 en 10 bits). Las curvas de Sony, Panasonic, ARRI, Blackmagic, Fujifilm y Nikon están escritas sobre el código de 0 a 1023; las de Canon y HLG ya van en la escala de video.
2. **Log → lineal de escena** con la fórmula del documento (0,18 = gris 18 %). En HLG, la inversa de la OETF de la BT.2100, escalada para que el gris de la BT.2408 (38 % de señal) dé 0,18.
3. **Gama → BT.709** con una matriz calculada en el script desde las primarias y el blanco publicados (todas D65).
4. **Tonos**, por canal: `T(x) = c·x^1,1 / (x^1,1 + d)`, con el gris 18 % en 0,43 de señal y el lineal 16 (unos 6,5 pasos sobre el gris) en 1. Es un hombro suave, sin recorte duro.
5. **Señal BT.709** para pantalla: inversa de la BT.1886 con gamma 2,4.

## Pruebas

```
powershell -NoProfile -ExecutionPolicy Bypass -File probar.ps1
```

Comprueba los valores que publica cada documento (S-Log3: 18 % → código 420; V-Log: 0,4233; Canon Log 2: 39,2 %; Canon Log 3: 34,3 %; LogC3: código 400; Film Gen 5: 0,3836; F-Log: 470 y 705; N-Log: 372; HLG: el 75 % es el blanco de referencia), y muestrea cada LUT en el gris 18 % y en el blanco (90 %, o el 75 % de HLG) contra la cadena calculada aparte: error por debajo de 0,0004 en el eje neutro (0,002 de tolerancia) y de 0,006 con interpolación trilineal (0,008). Además, el eje neutro sube siempre y no hay valores fuera de 0–1.

## Instalar en Rodaje

En Rodaje, Complementos → Instalar lo baja, comprueba su firma y lo instala. A mano: descarga `rodaje-camaras-<versión>.paquete` de las [releases](https://github.com/Dathinel/rodaje-camaras/releases) y usa «Instalar desde archivo…» en Complementos o suéltalo sobre la biblioteca. Las conversiones aparecen en Filtros; aplica la de tu cámara al clip antes de corregir el color. Más detalles en la [guía de complementos](https://github.com/Dathinel/rodaje/blob/main/docs/guia/complementos.md).

## Construir el paquete

```
powershell -NoProfile -ExecutionPolicy Bypass -File empaquetar.ps1
```

Solo hace falta Windows PowerShell 5.1. Genera las LUT, comprueba los archivos del manifiesto y deja `dist\rodaje-camaras-<versión>.paquete` con orden y fecha fijos: las mismas fuentes dan el mismo archivo byte a byte.

| Archivo | Qué es |
|---|---|
| `paquete.json` | Manifiesto: 9 `filter` y 9 `lut` |
| `filtros/*.json` | `rodaje.filter` v1: `rodaje.color` con su LUT (`./lut-<id>`) |
| `generar.ps1` | Las fórmulas; escribe `luts/*.cube` |
| `probar.ps1` | Las pruebas numéricas |
| `empaquetar.ps1` | Arma el `.paquete` |

## Licencia

CC0 1.0 (dominio público), ver `LICENSE`. El logotipo de Rodaje es marca de su autor y no forma parte de este contenido ([TRADEMARK.md](https://github.com/Dathinel/rodaje/blob/main/TRADEMARK.md)).
