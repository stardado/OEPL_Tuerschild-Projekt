# === KONFIGURATION ===============================
$oeplUrl       = "http://192.168.0.200/api/upload"
$displayId     = "epd-350-kueche"
$outFile       = "$PSScriptRoot\kueche.png"
$signatureFile = "$PSScriptRoot\kueche.lastcontent.txt"
$apiKey        = "<deepl-apiKey"
# =================================================

# === Erforderliche Typen =========================
Add-Type -AssemblyName System.Drawing

# === Zitat abrufen ===============================
$keyword = "happiness"
$apiUrl = "https://zenquotes.io/api/quotes/keyword=$keyword"

try {
    $quoteData = Invoke-RestMethod -Uri $apiUrl
    $randomIndex = Get-Random -Minimum 0 -Maximum $quoteData.Length
    $quoteText = $quoteData[$randomIndex].q
    $quoteAuthor = $quoteData[$randomIndex].a
} catch {
    Write-Host "❌ Fehler beim Abrufen – Fallback-Zitat wird verwendet." -ForegroundColor Yellow
    $quoteText = "Sei du selbst; alle anderen sind bereits vergeben."
    $quoteAuthor = "Oscar Wilde"
}

# === Übersetzung mit DeepL (UTF-8 sicher) ========
try {
    $deeplRequestBody = @{
        auth_key    = $apiKey
        text        = $quoteText
        target_lang = "DE"
    }

    $deeplResponse = Invoke-WebRequest -Method Post `
        -Uri "https://api-free.deepl.com/v2/translate" `
        -ContentType "application/x-www-form-urlencoded; charset=utf-8" `
        -Body $deeplRequestBody

    # Manuelle Verarbeitung der Antwort als UTF-8
    $responseStream = [System.IO.StreamReader]::new($deeplResponse.RawContentStream, [System.Text.Encoding]::UTF8)
    $deeplJson = $responseStream.ReadToEnd() | ConvertFrom-Json
    $translatedText = $deeplJson.translations[0].text
    Write-Host "✅ DeepL-Übersetzung empfangen." -ForegroundColor Green
} catch {
    Write-Host "⚠️ Fehler bei DeepL – Originaltext wird verwendet." -ForegroundColor Yellow
    $translatedText = $quoteText
}

# === Signatur berechnen ==========================
$plainText = ($translatedText + $quoteAuthor).Trim() -replace '\s+', ''
$md5 = [System.Security.Cryptography.MD5]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
$hash = [System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace "-", ""

# === Vorherige Signatur prüfen ====================
$lastHash = ""
if (Test-Path $signatureFile) {
    $lastHash = Get-Content $signatureFile -Raw
}
if ($hash -eq $lastHash) {
    Write-Host "🟡 Kein neuer Inhalt – Upload übersprungen." -ForegroundColor Yellow
    return
}

# === Bild vorbereiten =============================
[int]$width = 384
[int]$height = 184
$bmp = New-Object System.Drawing.Bitmap $width, $height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.TextRenderingHint = 'AntiAlias'
$gfx.SmoothingMode = 'AntiAlias'
$gfx.Clear([System.Drawing.Color]::White)

# === Schriftarten ================================
$fontHeader     = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
$fontSubHeader  = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontQuoteStyle = New-Object System.Drawing.Font("Segoe UI", 11, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic))
$fontAuthor     = New-Object System.Drawing.Font("Segoe UI", 8)

# === Farben ======================================
$black = [System.Drawing.Brushes]::Black
$red   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,0,0))

# === Kopfzeile (links/rechts) ====================
$gfx.DrawString("Küche", $fontHeader, $red, 10, 5)
$izrdSize = $gfx.MeasureString("IZRD e.V.", $fontHeader)
$gfx.DrawString("IZRD e.V.", $fontHeader, $black, $width - $izrdSize.Width - 10, 5)

# === Trennlinie ==================================
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

# === "Zitat des Tages" ===========================
$subHeaderText = "Zitat des Tages"
$subHeaderSize = $gfx.MeasureString($subHeaderText, $fontSubHeader)
$gfx.DrawString($subHeaderText, $fontSubHeader, $red, ($width - $subHeaderSize.Width) / 2, 40)

# === Zitat-Text vorbereiten ======================
$quoteY = 60
$quotedText = "„"$translatedText"“"

# === Zitat zentriert in Rechteck =================
$rectQuote = New-Object System.Drawing.RectangleF(
    [float]10,
    [float]$quoteY,
    [float]($width - 20),
    [float]80
)

$sfCenter = New-Object System.Drawing.StringFormat
$sfCenter.Alignment = 'Center'
$sfCenter.LineAlignment = 'Center'
$sfCenter.Trimming = 'Word'
$sfCenter.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit

$gfx.DrawString($quotedText, $fontQuoteStyle, $black, $rectQuote, $sfCenter)

# === Autor zentriert darunter ====================
$authorText = "$quoteAuthor"
$authorSize = $gfx.MeasureString($authorText, $fontAuthor)
$gfx.DrawString($authorText, $fontAuthor, $black, ($width - $authorSize.Width) / 2, $quoteY + 75)

# === Bild speichern ===============================
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "✅ Bild gespeichert: $outFile" -ForegroundColor Green

# === Bild an OEPL senden ==========================
Write-Host "📤 Lade Bild an Display hoch..." -ForegroundColor Cyan
curl.exe -X POST $oeplUrl `
    -F "file=@$outFile" `
    -F "id=$displayId" `
    -H "accept: application/json" | Out-Null
Write-Host "✅ Bild an $displayId übertragen." -ForegroundColor Green

# === Neue Signatur speichern ======================
$hash | Out-File $signatureFile -Encoding ASCII
