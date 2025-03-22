# === KONFIGURATION ===============================
$outFile = "$PSScriptRoot\raum3.png"
$raumName   = "Raum 3"
$abteilung  = "Verwaltung"
$names = @(
    "Maxi Muster",
    "Fritz Baumeister",
    "Lisa Lotte"
)

$oeplUrl   = "http://192.168.0.200/api/upload"
$displayId = "epd-350-raum3"
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
$fontTitle     = New-Object System.Drawing.Font "Arial", 16, ([System.Drawing.FontStyle]::Bold)
$fontAbteilung = New-Object System.Drawing.Font "Arial", 15, ([System.Drawing.FontStyle]::Bold)
$fontName      = New-Object System.Drawing.Font "Arial", 14
$black         = [System.Drawing.Brushes]::Black
$red           = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,0,0))

# === KOPFZEILE ===================================
$gfx.DrawString($raumName, $fontTitle, $red, 3, 5)
$izrdText = "IZRD e.V."
$size     = $gfx.MeasureString($izrdText, $fontTitle)
$gfx.DrawString($izrdText, $fontTitle, $black, $width - $size.Width - 3, 5)

# === TRENNLINIE ==================================
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

# === ABTEILUNG ===================================
$gfx.DrawString($abteilung, $fontAbteilung, $red, 3, 40)

# === NAMEN =======================================
$y = 40 + $fontAbteilung.Height + 10  # mehr Abstand nach "Verwaltung"
foreach ($name in $names) {
    $gfx.DrawString($name, $fontName, $black, 3, $y)
    $y += $fontName.Height + 1  # sehr enger Abstand
}

# === BILD SPEICHERN ==============================
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()

Write-Host "✅ Türschild für '$raumName' gespeichert unter: $outFile" -ForegroundColor Green

# === BILD AN OEPL SENDEN =========================
Write-Host "📤 Sende Bild an OEPL..." -ForegroundColor Cyan
curl.exe -X POST $oeplUrl `
    -F "file=@$outFile" `
    -F "id=$displayId" `
    -H "accept: application/json" | Out-Null
Write-Host "✅ Bild erfolgreich an $displayId gesendet." -ForegroundColor Green

