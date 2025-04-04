# === KONFIGURATION ===============================
$outFile = "$PSScriptRoot\raum1.jpg"
$raumName   = "Raum 1"
$abteilung  = "Abteilungsname"
$names = @(
    "Maxi Muster",
    "Fritz Baumeister",
    "Lisa Lotte"
)

$oeplUrl   = "http://198.51.100.200/imgupload"
$macAddress = "780105561CBC1234"
# =================================================

# === BILD INITIALISIEREN =========================
Add-Type -AssemblyName System.Drawing

$width  = 384
$height = 184
$bmp    = New-Object System.Drawing.Bitmap $width, $height
$gfx    = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = "AntiAlias"
$gfx.Clear([System.Drawing.Color]::White)

# === SCHRIFT & FARBEN ============================
$fontTitle     = New-Object System.Drawing.Font "Arial", 18, ([System.Drawing.FontStyle]::Bold)
$fontAbteilung = New-Object System.Drawing.Font "Arial", 18, ([System.Drawing.FontStyle]::Bold)
$fontName      = New-Object System.Drawing.Font "Arial", 16
$black         = [System.Drawing.Brushes]::Black
$yellowColor   = [System.Drawing.Color]::FromArgb(255, 255, 204, 0)
$yellowBrush   = New-Object System.Drawing.SolidBrush $yellowColor

# === GELBER HINTERGRUNDBALKEN ====================
$gfx.FillRectangle($yellowBrush, 0, 0, $width, 35)

# === KOPFZEILE ===================================
$gfx.DrawString($raumName, $fontTitle, $black, 10, 5)
$izrdText = "IZRD e.V."
$size     = $gfx.MeasureString($izrdText, $fontTitle)
$gfx.DrawString($izrdText, $fontTitle, $black, $width - $size.Width - 10, 5)

# === TRENNLINIE ==================================
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

# === ABTEILUNG ===================================
$gfx.DrawString($abteilung, $fontAbteilung, $black, 3, 40)

# === NAMEN =======================================
$y = 40 + $fontAbteilung.Height + 10  # mehr Abstand nach "Verwaltung"
foreach ($name in $names) {
    $gfx.DrawString($name, $fontName, $black, 3, $y)
    $y += $fontName.Height + 1  # enger Abstand
}

# === BILD SPEICHERN ==============================
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$gfx.Dispose()
$bmp.Dispose()

Write-Host "✅ Türschild für '$raumName' gespeichert unter: $outFile" -ForegroundColor Green

# === BILD AN OEPL SENDEN =========================
Write-Host "📤 Sende Bild an OEPL..." -ForegroundColor Cyan
$arguments = @(
    "-X", "POST", "$oeplUrl",
    "-F", "mac=$macAddress",
    "-F", "dither=0",
    "-F", "image=@$outFile;type=image/jpeg",
    "-H", "accept: application/json"
)
Start-Process -FilePath "curl.exe" -ArgumentList $arguments -NoNewWindow -Wait
Write-Host "✅ Bild erfolgreich an $macAddress gesendet." -ForegroundColor Green
