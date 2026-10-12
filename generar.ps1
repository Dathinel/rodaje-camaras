# Genera las LUT de rodaje-camaras en <Destino>\luts\: de la curva logarítmica de cada cámara a Rec. 709, con las
# fórmulas que publica cada fabricante. Ninguna LUT ajena: todo sale de las fórmulas de abajo y la salida es la misma
# byte a byte en cualquier equipo. Lo llaman empaquetar.ps1 y probar.ps1.
#
# Cadena de cada LUT (entrada y salida son RGB de video de 0 a 1, como los ve Rodaje tras decodificar):
#  1. Nivel de video → valor de código. Los archivos van en rango limitado: 0 es el código 64 y 1 el 940 (10 bits).
#     Las curvas de Sony, Panasonic, ARRI, Blackmagic, Fujifilm y Nikon están escritas sobre el código de 0 a 1023;
#     las de Canon y la HLG de la BT.2100 ya están en esa escala de video (0 % = código 64).
#  2. Curva logarítmica → lineal de escena (0,18 = gris 18 %), con la fórmula publicada.
#  3. Gama de la cámara → primarias BT.709, con una matriz calculada aquí desde las primarias y el blanco publicados
#     (todos D65, así que no hace falta adaptación cromática).
#  4. Mapeo de tonos propio, por canal: T(x) = c·x^p / (x^p + d), p = 1,1. c y d salen de dos condiciones: el gris 18 %
#     da 0,43 de señal y el lineal 16 (unos 6,5 pasos sobre el gris) da 1. Por encima se recorta, pero la pendiente ya es
#     casi nula: el hombro llega suave.
#  5. Señal BT.709 para pantalla: inversa de la EOTF de la BT.1886 con gamma 2,4 y negro en 0 (V = L^(1/2,4)).
param([Parameter(Mandatory = $true)][string]$Destino)

$ErrorActionPreference = 'Stop'

if (-not ('RodajeCamaras.Curvas' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace RodajeCamaras
{
    public static class Curvas
    {
        public const int Size = 33;
        public const double Gray = 0.18;
        public const double GraySignal = 0.43;
        public const double WhiteLinear = 16.0;
        public const double Power = 1.1;

        public static readonly string[] Names = { "s-log3", "v-log", "c-log2", "c-log3", "log-c3", "bmd-film-gen5", "f-log", "n-log", "hlg" };

        private static readonly double C, D;

        static Curvas()
        {
            double a = Math.Pow(WhiteLinear, Power), g = Math.Pow(Gray, Power), t = Math.Pow(GraySignal, 2.4);
            D = a * g * (1 - t) / (t * a - g);
            C = (a + D) / a;
        }

        // Nivel de video (0 = código 64, 1 = código 940) → lineal de escena.
        public static double Decode(string name, double v)
        {
            double cv = (v * 876.0 + 64.0) / 1023.0;
            switch (name)
            {
                case "s-log3":
                    // Sony, «Technical Summary for S-Gamut3.Cine/S-Log3 and S-Gamut3/S-Log3» (2014).
                    return cv >= 171.2102946929 / 1023.0
                        ? Math.Pow(10.0, (cv * 1023.0 - 420.0) / 261.5) * (0.18 + 0.01) - 0.01
                        : (cv * 1023.0 - 95.0) * 0.01125000 / (171.2102946929 - 95.0);
                case "v-log":
                    // Panasonic, «V-Log/V-Gamut Reference Manual» (2014).
                    return cv < 0.181 ? (cv - 0.125) / 5.6 : Math.Pow(10.0, (cv - 0.598206) / 0.241514) - 0.00873;
                case "c-log2":
                    // Canon, «Canon Log Gamma Curves: Canon Log, Canon Log 2 and Canon Log 3», v1.2 (2018). Entrada en
                    // reflectancia / 0,9; la salida ya está en la escala de video.
                    return 0.9 * (v < 0.035388128
                        ? -(Math.Pow(10.0, (0.035388128 - v) / 0.281863093) - 1.0) / 87.09937546
                        : (Math.Pow(10.0, (v - 0.035388128) / 0.281863093) - 1.0) / 87.09937546);
                case "c-log3":
                {
                    // Mismo documento de Canon, v1.2: tramo lineal entre −0,014 y 0,014 de reflectancia / 0,9.
                    double lo = 0.12512219 - 1.9754798 * 0.014, hi = 0.12512219 + 1.9754798 * 0.014;
                    double x = v < lo ? -(Math.Pow(10.0, (0.12783901 - v) / 0.36726845) - 1.0) / 14.98325
                        : v <= hi ? (v - 0.12512219) / 1.9754798
                        : (Math.Pow(10.0, (v - 0.12240537) / 0.36726845) - 1.0) / 14.98325;
                    return 0.9 * x;
                }
                case "log-c3":
                    // ARRI, «ALEXA Log C Curve: Usage in VFX» (2017), Log C3 a EI 800.
                    return cv > 5.367655 * 0.010591 + 0.092809
                        ? (Math.Pow(10.0, (cv - 0.385537) / 0.247190) - 0.052272) / 5.555556
                        : (cv - 0.092809) / 5.367655;
                case "bmd-film-gen5":
                {
                    // Blackmagic Design, «Blackmagic Generation 5 Color Science» (2021).
                    const double A = 0.08692876065491224, B = 0.005494072432257808, Cc = 0.5300133392291939;
                    const double Dd = 8.283605932402494, E = 0.09246575342465753, Cut = 0.005;
                    return cv < Dd * Cut + E ? (cv - E) / Dd : Math.Exp((cv - Cc) / A) - B;
                }
                case "f-log":
                    // Fujifilm, «F-Log Data Sheet» v1.0 (2016).
                    return cv >= 0.100537775223865
                        ? (Math.Pow(10.0, (cv - 0.790453) / 0.344676) - 0.009468) / 0.555556
                        : (cv - 0.092864) / 8.735631;
                case "n-log":
                    // Nikon, «N-Log Specification Document» v1.0.0 (2018).
                    return cv < 452.0 / 1023.0
                        ? Math.Pow(cv * 1023.0 / 650.0, 3.0) - 0.0075
                        : Math.Exp((cv * 1023.0 - 619.0) / 150.0);
                case "hlg":
                {
                    // ITU-R BT.2100-2 (2018), inversa de la OETF de HLG, y BT.2408 (2018): el gris 18 % va al 38 % de
                    // señal; se escala para que ese gris dé 0,18 (el blanco de referencia del 75 % queda en 0,99).
                    const double a = 0.17883277, b = 0.28466892, c = 0.55991073;
                    double e = v <= 0.5 ? v * v / 3.0 : (Math.Exp((v - c) / a) + b) / 12.0;
                    return e * Gray / (0.38 * 0.38 / 3.0);
                }
                default:
                    throw new ArgumentException("Curva desconocida: " + name);
            }
        }

        // Primarias y blanco (xy) de la gama de cada curva.
        public static double[] Primaries(string name)
        {
            switch (name)
            {
                case "s-log3": return new[] { 0.766, 0.275, 0.225, 0.800, 0.089, -0.087, 0.3127, 0.3290 }; // S-Gamut3.Cine
                case "v-log": return new[] { 0.730, 0.280, 0.165, 0.840, 0.100, -0.030, 0.3127, 0.3290 }; // V-Gamut
                case "c-log2":
                case "c-log3": return new[] { 0.740, 0.270, 0.170, 1.140, 0.080, -0.100, 0.3127, 0.3290 }; // Cinema Gamut
                case "log-c3": return new[] { 0.6840, 0.3130, 0.2210, 0.8480, 0.0861, -0.1020, 0.3127, 0.3290 }; // ARRI Wide Gamut 3
                case "bmd-film-gen5": return new[] { 0.7177215, 0.3171181, 0.2280410, 0.8615690, 0.1005841, -0.0820452, 0.3127170, 0.3290312 };
                case "f-log":
                case "n-log":
                case "hlg": return new[] { 0.708, 0.292, 0.170, 0.797, 0.131, 0.046, 0.3127, 0.3290 }; // BT.2020
                default: throw new ArgumentException("Curva desconocida: " + name);
            }
        }

        private static readonly double[] Bt709 = { 0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290 };

        // RGB → XYZ desde las primarias y el blanco (la matriz de primarias normalizada de SMPTE RP 177).
        public static double[,] Npm(double[] p)
        {
            var m = new double[3, 3];
            for (int i = 0; i < 3; i++)
            {
                double x = p[2 * i], y = p[2 * i + 1];
                m[0, i] = x / y; m[1, i] = 1.0; m[2, i] = (1 - x - y) / y;
            }
            double wx = p[6], wy = p[7];
            double[] w = { wx / wy, 1.0, (1 - wx - wy) / wy };
            double[] s = Solve(m, w);
            for (int i = 0; i < 3; i++) for (int r = 0; r < 3; r++) m[r, i] *= s[i];
            return m;
        }

        public static double[,] ToBt709(string name)
        {
            double[,] inv = Inverse(Npm(Bt709)), src = Npm(Primaries(name));
            var m = new double[3, 3];
            for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++)
            {
                double s = 0; for (int k = 0; k < 3; k++) s += inv[r, k] * src[k, c];
                m[r, c] = s;
            }
            return m;
        }

        public static double Tone(double x)
        {
            if (x <= 0) return 0;
            double xp = Math.Pow(x, Power);
            return Math.Min(1.0, C * xp / (xp + D));
        }

        public static double Signal(double linear) { return Math.Pow(Tone(linear), 1.0 / 2.4); }

        public static string Cube(string name)
        {
            double[,] m = ToBt709(name);
            var text = new StringBuilder(1200000);
            text.Append("# rodaje-camaras: ").Append(name).Append(" a Rec. 709. Generada por generar.ps1 de rodaje-camaras (CC0-1.0),\n");
            text.Append("# con las fórmulas publicadas por el fabricante; no deriva de ninguna LUT ajena.\n");
            text.Append("TITLE \"").Append(name).Append(" a Rec. 709\"\nLUT_3D_SIZE ").Append(Size).Append("\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n");
            var lin = new double[3];
            for (int b = 0; b < Size; b++)
            {
                for (int g = 0; g < Size; g++)
                {
                    for (int r = 0; r < Size; r++)
                    {
                        lin[0] = Decode(name, r / (double)(Size - 1));
                        lin[1] = Decode(name, g / (double)(Size - 1));
                        lin[2] = Decode(name, b / (double)(Size - 1));
                        for (int c = 0; c < 3; c++)
                        {
                            double o = m[c, 0] * lin[0] + m[c, 1] * lin[1] + m[c, 2] * lin[2];
                            text.Append(F(Signal(o))).Append(c < 2 ? ' ' : '\n');
                        }
                    }
                }
            }

            return text.ToString();
        }

        public static void Write(string folder)
        {
            Directory.CreateDirectory(folder);
            foreach (string name in Names)
            {
                File.WriteAllText(Path.Combine(folder, name + ".cube"), Cube(name), new UTF8Encoding(false));
            }
        }

        private static string F(double x) { return (x < 0 ? 0 : x > 1 ? 1 : x).ToString("0.000000", CultureInfo.InvariantCulture); }

        private static double[] Solve(double[,] m, double[] v)
        {
            double[,] inv = Inverse(m);
            var r = new double[3];
            for (int i = 0; i < 3; i++) r[i] = inv[i, 0] * v[0] + inv[i, 1] * v[1] + inv[i, 2] * v[2];
            return r;
        }

        private static double[,] Inverse(double[,] m)
        {
            double a = m[0, 0], b = m[0, 1], c = m[0, 2], d = m[1, 0], e = m[1, 1], f = m[1, 2], g = m[2, 0], h = m[2, 1], i = m[2, 2];
            double det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
            return new double[,]
            {
                { (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det },
                { (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det },
                { (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det },
            };
        }
    }
}
'@
}

[RodajeCamaras.Curvas]::Write((Join-Path ([System.IO.Path]::GetFullPath($Destino)) 'luts'))
