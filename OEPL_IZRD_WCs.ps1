# === KONFIGURATION ===============================
$oeplUrl       = "http://10.44.45.246/api/upload"
$outDir        = "$PSScriptRoot"
$fontFamily    = "Segoe UI Emoji"

$displays = @(
    @{ Name = "Damen WC"; DisplayId = "epd-350-damenwc" },
    @{ Name = "Herren WC"; DisplayId = "epd-350-herrenwc" }
)
# =================================================

# === ERFORDERLICHE TYPEN =========================
Add-Type -AssemblyName System.Drawing

# === FUNKTION BILD ERZEUGEN ======================
function New-WcSign {
    param (
        [string]$roomName,
        [string]$displayId,
        [string]$outFile
    )

    [int]$width  = 384
    [int]$height = 184

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.TextRenderingHint = 'AntiAlias'
    $gfx.SmoothingMode = 'AntiAlias'
    $gfx.Clear([System.Drawing.Color]::White)

    # Schriftarten
    $fontHeader  = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
    $fontIZRD    = $fontHeader
    $fontSymbol  = New-Object System.Drawing.Font($fontFamily, 70) # doppelte Größe

    # Farben
    $black = [System.Drawing.Brushes]::Black
    $red   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,0,0))

    # Kopfzeile
    $gfx.DrawString($roomName, $fontHeader, $red, 10, 5)
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

    # Speichern
    $bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose()
    $bmp.Dispose()

    Write-Host "✅ Bild erstellt: $outFile" -ForegroundColor Green
}

# === ALLE BILDER ERZEUGEN & SENDEN ===============
foreach ($display in $displays) {
    $filePath = Join-Path $outDir "$($display.DisplayId).png"
    New-WcSign -roomName $display.Name -displayId $display.DisplayId -outFile $filePath

    # Upload
    Write-Host "📤 Sende Bild an $($display.DisplayId)..." -ForegroundColor Cyan
    curl.exe -X POST $oeplUrl `
        -F "file=@$filePath" `
        -F "id=$($display.DisplayId)" `
        -H "accept: application/json" | Out-Null
    Write-Host "✅ Bild an $($display.DisplayId) gesendet." -ForegroundColor Green
}
