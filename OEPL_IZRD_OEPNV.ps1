# === KONFIGURATION ===============================
$stopId        = "900160544"
$departuresUrl = "https://v6.bvg.transport.rest/stops/$stopId/departures?duration=60&results=50"
$outFile       = "$PSScriptRoot\opnv_rathaus.png"
$signatureFile = "$PSScriptRoot\opnv_rathaus.lastcontent.txt"
$oeplUrl       = "http://192.168.0.200/api/upload"
$displayId     = "epd-350-opnv"
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

# === BILD ERSTELLEN ==============================
$width, $height = 384, 184
$bmp  = New-Object System.Drawing.Bitmap $width, $height
$gfx  = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = "AntiAlias"
$gfx.Clear([System.Drawing.Color]::White)

# === Kopfzeile ===================================
$gfx.DrawString("ÖPNV Rathaus Lichtenberg", $fontHeader, $red, 10, 5)
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 30, $width, 30)

# === Symbole laden ===============================
$iconTram = [System.Drawing.Image]::FromFile("$scriptRoot\tram.png")
$iconBus  = [System.Drawing.Image]::FromFile("$scriptRoot\bus.png")

# === Inhalt anzeigen =============================
$y = 35
foreach ($group in $grouped) {
    $first     = $group.Group[0]
    $icon      = if ($first.Product -eq "bus") { $iconBus } else { $iconTram }
    $direction = $first.Direction
    $line      = $first.Line

    # Symbol (16x16)
    $gfx.DrawImage($icon, 10, $y, 16, 16)

    # Linie & Richtung
    $gfx.DrawString("$line → $direction", $fontLine, $black, 30, $y)
    $y += 16

    # Uhrzeiten
    $times = $group.Group | Sort-Object When | ForEach-Object { $_.When.ToString("HH:mm") }
    $gfx.DrawString(($times -join ", "), $fontTimes, $black, 30, $y)
    $y += 20
}

# === Speichern & Senden ==========================
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "✅ Bild gespeichert: $outFile" -ForegroundColor Green

curl.exe -X POST $oeplUrl `
    -F "file=@$outFile" `
    -F "id=$displayId" `
    -H "accept: application/json" | Out-Null
Write-Host "📤 Bild an $displayId übertragen." -ForegroundColor Green

# === Signatur speichern ==========================
$hash | Out-File -FilePath $signatureFile -Encoding ASCII