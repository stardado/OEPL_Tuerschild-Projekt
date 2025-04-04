# === KONFIGURATION ===============================
$oeplUrl       = "http://198.51.100.200/imgupload"  # BWY-Upload
$outDir        = "$PSScriptRoot"
$fontFamily    = "Segoe UI Emoji"

$displays = @(
    @{ Name = "Damen WC"; Mac = "FFFFFFFFE0001234" },
    @{ Name = "Herren WC"; Mac = "FFFFFFFF50011234" }
)
# =================================================

# === ERFORDERLICHE TYPEN =========================
Add-Type -AssemblyName System.Drawing

# === FUNKTION BILD ERZEUGEN ======================
function New-WcSign {
    param (
        [string]$roomName,
        [string]$macAddress,
        [string]$outFile
    )

    [int]$width  = 384
    [int]$height = 184

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.TextRenderingHint = 'AntiAlias'
    $gfx.SmoothingMode = 'AntiAlias'
    $gfx.Clear([System.Drawing.Color]::White)

    # Farben
    $black = [System.Drawing.Brushes]::Black
    $yellowColor = [System.Drawing.Color]::FromArgb(255, 255, 204, 0)
    $yellowBrush = New-Object System.Drawing.SolidBrush $yellowColor

    # Schriftarten
    $fontHeader  = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold)
    $fontIZRD    = $fontHeader
    $fontSymbol  = New-Object System.Drawing.Font($fontFamily, 70)

    # Hintergrund oben
    $gfx.FillRectangle($yellowBrush, 0, 0, $width, 35)

    # Kopfzeile
    $gfx.DrawString($roomName, $fontHeader, $black, 10, 5)
    $izrdSize = $gfx.MeasureString("IZRD e.V.", $fontIZRD)
    $gfx.DrawString("IZRD e.V.", $fontIZRD, $black, $width - $izrdSize.Width - 10, 5)

    # Trennlinie
    $gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

    # Symbole
    if ($roomName -like "*Damen*") {
        $icons = "🚺 ♀"
    } elseif ($roomName -like "*Herren*") {
        $icons = "🚹 ♂"
    } else {
        $icons = "🚻"
    }

    $textSize = $gfx.MeasureString($icons, $fontSymbol)
    $x = ($width - $textSize.Width) / 2
    $y = ($height - $textSize.Height) / 2 + 10

    $gfx.DrawString($icons, $fontSymbol, $black, $x, $y)

    # Speichern als JPEG in voller Qualität
    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, 100L)
    $bmp.Save($outFile, $jpegCodec, $encoderParams)

    $gfx.Dispose()
    $bmp.Dispose()

    Write-Host "✅ Bild erstellt: $outFile" -ForegroundColor Green
}

# === ALLE BILDER ERZEUGEN & SENDEN ===============
foreach ($display in $displays) {
    $filePath = Join-Path $outDir "$($display.Mac).jpg"
    New-WcSign -roomName $display.Name -macAddress $display.Mac -outFile $filePath

    # Upload
    Write-Host "📤 Sende Bild an $($display.Mac)..." -ForegroundColor Cyan
    $arguments = @(
        "-X", "POST", "$oeplUrl",
        "-F", "mac=$($display.Mac)",
        "-F", "dither=0",
        "-F", "image=@$filePath;type=image/jpeg",
        "-H", "accept: application/json"
    )
    Start-Process -FilePath "curl.exe" -ArgumentList $arguments -NoNewWindow -Wait
    Write-Host "✅ Bild an $($display.Mac) gesendet." -ForegroundColor Green
}
