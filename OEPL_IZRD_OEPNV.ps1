# === KONFIGURATION ===============================
$stopId        = "900160544"
$departuresUrl = "https://v6.bvg.transport.rest/stops/$stopId/departures?duration=60&results=50"
$outFile       = "$PSScriptRoot\opnv_rathaus.jpg"
$signatureFile = "$PSScriptRoot\opnv_rathaus.lastcontent.txt"
$oeplUrl       = "http://198.51.100.200/imgupload"
$displayMac    = "780105561CB1234"
# =================================================

# === ERFORDELICHE TYPEN ==========================
Add-Type -AssemblyName System.Drawing
# === ABFAHRTSDATEN ABRUFEN =======================
try {
    $departuresRaw = Invoke-RestMethod -Uri $departuresUrl
} catch {
    Write-Host "❌ Fehler beim Abrufen der Abfahrtsdaten: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# === DATEN FILTERN ===============================
$departuresList = @()
foreach ($dep in $departuresRaw.departures) {
    if ($dep.when -and $dep.line.name -and $dep.direction) {
        try {
            $when = [DateTime]$dep.when
            $departuresList += [PSCustomObject]@{
                Line      = $dep.line.name
                Product   = $dep.line.productName
                Direction = $dep.direction
                When      = $when
            }
        } catch {
            continue
        }
    }
}

if ($departuresList.Count -eq 0) {
    Write-Host "⚠️ Keine gültigen Abfahrtsdaten gefunden." -ForegroundColor Yellow
    exit
}

# === GRUPPIEREN ==================================
$grouped = $departuresList | Group-Object -Property Line, Product, Direction

# === BILD ERSTELLEN ==============================
[int]$width = 384
[int]$height = 184
$bmp  = New-Object System.Drawing.Bitmap $width, $height
$gfx  = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = "AntiAlias"
$gfx.TextRenderingHint = "AntiAlias"
$gfx.Clear([System.Drawing.Color]::White)

# === FARBEN & SCHRIFTEN ==========================
$black       = [System.Drawing.Brushes]::Black
$red         = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 0, 0))
$yellowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 204, 0))
$fontHeader  = New-Object System.Drawing.Font("Arial", 15, [System.Drawing.FontStyle]::Bold)
$fontLine    = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontTimes   = New-Object System.Drawing.Font("Segoe UI", 11)

# === KOPFZEILE ===================================
$gfx.FillRectangle($yellowBrush, 0, 0, $width, 27)
$gfx.DrawString("BVG Rathaus Lichtenberg", $fontHeader, $black, 10, 3)
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 27, $width, 27)

# === ICONS =======================================
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$iconTram = [System.Drawing.Image]::FromFile("$scriptRoot\tram.png")
$iconBus  = [System.Drawing.Image]::FromFile("$scriptRoot\bus.png")

# === INHALT ======================================
$y = 32
foreach ($group in $grouped) {
    $first     = $group.Group[0]
    $icon      = if ($first.Product -eq "Bus") { $iconBus } else { $iconTram }
    $direction = $first.Direction
    $line      = $first.Line

    # Symbol (16x16)
    $gfx.DrawImage($icon, 10, $y, 16, 16)

    # Linie & Richtung
    $gfx.DrawString("$line → $direction", $fontLine, $black, 30, $y)
    $y += 17

    # Uhrzeiten
    $times = $group.Group | Sort-Object When | ForEach-Object { $_.When.ToString("HH:mm") }
    $gfx.DrawString(($times -join ", "), $fontTimes, $black, 30, $y)
    $y += 22
}

# === BILD SPEICHERN ==============================
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoder = [System.Drawing.Imaging.Encoder]::Quality
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, 100L)
$bmp.Save($outFile, $jpegCodec, $encoderParams)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "✅ Bild gespeichert: $outFile" -ForegroundColor Green

# === UPLOAD AN OEPL ==============================
Write-Host "📤 Lade Bild an Display hoch..." -ForegroundColor Cyan
$arguments = @(
    "-X", "POST", "$oeplUrl",
    "-F", "mac=$displayMac",
    "-F", "dither=0",
    "-F", "image=@$outFile;type=image/jpeg",
    "-H", "accept: application/json"
)
Start-Process -FilePath "curl.exe" -ArgumentList $arguments -NoNewWindow -Wait
Write-Host "✅ Bild an Display übertragen." -ForegroundColor Green

# === SIGNATUR SPEICHERN ==========================
$plainText = ($departuresList | ForEach-Object { "$_" }) -join "|"
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = ([System.BitConverter]::ToString($md5.ComputeHash($hashBytes)) -replace "-", "").ToLower()
$hash | Out-File -FilePath $signatureFile -Encoding ASCII
