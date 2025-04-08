# === KONFIGURATION ===============================
$oeplUrl       = "http://198.51.100.200/imgupload"   # OEPL Upload-Endpunkt (Port 80)
$displayMac    = "FFFFFFFFE5001234"                  # MAC-Adresse deines Küchenschilds
$outFile       = "$PSScriptRoot\kueche.jpg"
$signatureFile = "$PSScriptRoot\kueche.lastcontent.txt"
$apiKey        = "<DeepL API-Key>"  # DeepL API-Key
$keyword       = "happiness"
# =================================================
# === TLS für HTTPS aktivieren =====================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# === SYSTEM.DRAWING INITIALISIEREN ==================
Add-Type -AssemblyName System.Drawing

# === ZITAT ABRUFEN VON ZENQUOTES ====================
do {
    try {
        $apiUrl = "https://zenquotes.io/api/quotes/keyword=$keyword"
        $quoteData = Invoke-RestMethod -Uri $apiUrl
        $randomIndex = Get-Random -Minimum 0 -Maximum $quoteData.Length
        $quoteText = $quoteData[$randomIndex].q
        $quoteAuthor = $quoteData[$randomIndex].a
    } catch {
        Write-Host "❌ Fehler beim Abrufen von ZenQuotes – Fallback-Zitat wird verwendet." -ForegroundColor Yellow
        $quoteText = "Be yourself; everyone else is already taken."
        $quoteAuthor = "Oscar Wilde"
        break
    }

    # === Übersetzung mit DeepL ========================
    try {
        $deeplRequestBody = @{ auth_key = $apiKey; text = $quoteText; target_lang = "DE" }
        $deeplResponse = Invoke-WebRequest -Method Post -Uri "https://api-free.deepl.com/v2/translate" -ContentType "application/x-www-form-urlencoded; charset=utf-8" -Body $deeplRequestBody
        $responseStream = [System.IO.StreamReader]::new($deeplResponse.RawContentStream, [System.Text.Encoding]::UTF8)
        $deeplJson = $responseStream.ReadToEnd() | ConvertFrom-Json
        $translatedText = $deeplJson.translations[0].text
        Write-Host "✅ DeepL-Übersetzung empfangen." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Fehler bei DeepL – Originaltext wird verwendet." -ForegroundColor Yellow
        $translatedText = $quoteText
    }

    # Prüfe, ob das Zitat maximal 3 Zeilen à 42 Zeichen hat
    $plain = $translatedText -replace '\s+', ''
    $quoted = "„"$translatedText"“"
    $lineCount = [Math]::Ceiling($quoted.Length / 42.0)

} while ($lineCount -gt 3)

# === SIGNATUR BERECHNEN =============================
$plainText = ($translatedText + $quoteAuthor).Trim() -replace '\s+', ''
$md5 = [System.Security.Cryptography.MD5]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
$hash = ([System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace "-", "").ToLower()

# === VORHERIGE SIGNATUR PRÜFEN ======================
$lastHash = ""
if (Test-Path $signatureFile) {
    $lastHash = (Get-Content $signatureFile -Raw).Trim()
}
if ($hash -eq $lastHash) {
    Write-Host "🟡 Kein neuer Inhalt – Upload übersprungen." -ForegroundColor Yellow
    return
}

# === BILD ERZEUGEN ==================================
[int]$width = 384
[int]$height = 184
$bmp = New-Object System.Drawing.Bitmap $width, $height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = "AntiAlias"
$gfx.TextRenderingHint = "AntiAlias"
$gfx.Clear([System.Drawing.Color]::White)

# === SCHRIFT & FARBEN ===============================
$fontHeader     = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Bold)
$fontSubHeader  = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$fontQuoteStyle = New-Object System.Drawing.Font("Segoe UI", 13, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic))
$fontAuthor     = New-Object System.Drawing.Font("Arial", 10)
$black          = [System.Drawing.Brushes]::Black
$yellowBrush    = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 204, 0))

# === KOPFZEILE ======================================
$gfx.FillRectangle($yellowBrush, 0, 0, $width, 35)
$gfx.DrawString("Küche", $fontHeader, $black, 10, 5)
$izrdSize = $gfx.MeasureString("IZRD e.V.", $fontHeader)
$gfx.DrawString("IZRD e.V.", $fontHeader, $black, $width - $izrdSize.Width - 10, 5)
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

# === ZITAT DES TAGES ===============================
$gfx.DrawString("Zitat des Tages", $fontSubHeader, $black, ($width - ($gfx.MeasureString("Zitat des Tages", $fontSubHeader)).Width) / 2, 45)

$quoteY = 70
$quoteHeight = 75
$rectQuote = New-Object System.Drawing.RectangleF([float]10,[float]$quoteY,[float]($width - 20),[float]$quoteHeight)
$sfCenter = New-Object System.Drawing.StringFormat
$sfCenter.Alignment = "Center"
$sfCenter.LineAlignment = "Center"
$sfCenter.Trimming = "Word"
$sfCenter.FormatFlags = [System.Drawing.StringFormatFlags]::LineLimit

$quotedText = "„"$translatedText"“"
$gfx.DrawString($quotedText, $fontQuoteStyle, $black, $rectQuote, $sfCenter)

# === AUTOR =========================================
$authorText = "$quoteAuthor"
$authorSize = $gfx.MeasureString($authorText, $fontAuthor)
$gfx.DrawString($authorText, $fontAuthor, $black, ($width - $authorSize.Width) / 2, $quoteY + $quoteHeight)

# === BILD SPEICHERN ================================
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encoder = [System.Drawing.Imaging.Encoder]::Quality
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, 100L)
$bmp.Save($outFile, $jpegCodec, $encoderParams)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "✅ Bild gespeichert: $outFile" -ForegroundColor Green

# === UPLOAD AN OEPL ================================
Write-Host "📤 Lade Bild an Display hoch..." -ForegroundColor Cyan
$arguments = @(
    "-X", "POST", "$oeplUrl",
    "-F", "mac=$displayMac",
    "-F", "dither=0",
    "-F", "image=@$outFile;type=image/jpeg",
    "-H", "accept: application/json"
)
#Start-Process -FilePath "curl.exe" -ArgumentList $arguments -NoNewWindow -Wait
Write-Host "✅ Bild an Display übertragen." -ForegroundColor Green

# === SIGNATUR SPEICHERN ============================
$hash | Out-File -FilePath $signatureFile -Encoding ASCII
