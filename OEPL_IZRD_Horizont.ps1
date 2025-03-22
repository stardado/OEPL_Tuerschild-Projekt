# === KONFIGURATION ===============================
$tenantId     = "<ms365-tenantId>"
$clientId     = "<ms365-clientId>"
$clientSecret = ConvertTo-SecureString "<ms365-clientSecret>" -AsPlainText -Force
$mailbox      = "raum.horizont@kunde.de"

$oeplUrl      = "http://192.168.0.200/api/upload"
$displayId    = "epd-350-horizont"

$outFile       = "$PSScriptRoot\raum_horizont.png"
$signatureFile = "$PSScriptRoot\raum_horizont.lastcontent.txt"
# =================================================

# === AUTHENTIFIZIERUNG ===========================
Import-Module MSAL.PS
$scope = "https://graph.microsoft.com/.default"
$token = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Scopes $scope -ClientSecret $clientSecret
$accessToken = $token.AccessToken

# === TERMINE ABRUFEN =============================
$today = Get-Date
$start = $today.ToString("yyyy-MM-ddT00:00:00Z")
$end   = $today.ToString("yyyy-MM-ddT23:59:59Z")
$url = "https://graph.microsoft.com/v1.0/users/$mailbox/calendarView?startDateTime=$start&endDateTime=$end&`$orderby=start/dateTime"

$headers = @{
    Authorization = "Bearer $accessToken"
    Accept        = "application/json"
}

$response = Invoke-RestMethod -Method GET -Uri $url -Headers $headers
$now = Get-Date
$events = $response.value | Where-Object {
    ([datetime]::Parse($_.end.dateTime).ToLocalTime()) -ge $now
}

# === TEXTSIGNATUR & MD5 ==========================
function Get-TextSignature([Array]$events) {
    $lines = foreach ($evt in ($events | Sort-Object { $_.start.dateTime })) {
        $start = [datetime]::Parse($evt.start.dateTime).ToLocalTime().ToString("HH:mm")
        $end   = [datetime]::Parse($evt.end.dateTime).ToLocalTime().ToString("HH:mm")
        $subject = if ($evt.subject) { $evt.subject.Trim() -replace '\s+', '' } else { "[keinBetreff]" }
        "$start-$end$subject"
    }
    return ($lines -join "|")
}

function Get-TextMD5($text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

$textSignature = Get-TextSignature $events
$currentHash = Get-TextMD5 $textSignature

$lastHash = ""
if (Test-Path $signatureFile) {
    $lastHash = Get-Content $signatureFile -Raw | Out-String
    $lastHash = $lastHash.Trim()
}

if ($currentHash -eq $lastHash) {
    Write-Host "🟡 Kein sichtbarer Unterschied – kein Bild/Upload nötig." -ForegroundColor Yellow
    return
}

# === BILD ERZEUGEN ===============================
Add-Type -AssemblyName System.Drawing

$width = 384
$height = 184
$bmp = New-Object System.Drawing.Bitmap $width, $height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = "AntiAlias"
$gfx.Clear([System.Drawing.Color]::White)

# Schriftarten & Farben
$fontTitle  = New-Object System.Drawing.Font "Arial", 14, ([System.Drawing.FontStyle]::Bold)
$fontTime   = New-Object System.Drawing.Font "Arial", 14
$fontText   = New-Object System.Drawing.Font "Arial", 13
$black      = [System.Drawing.Brushes]::Black
$red        = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,0,0))

# Kopfzeile
$gfx.DrawString("Raum Horizont", $fontTitle, $red, 10, 5)
$izrdText = "IZRD e.V."
$size = $gfx.MeasureString($izrdText, $fontTitle)
$gfx.DrawString($izrdText, $fontTitle, $black, $width - $size.Width - 10, 5)
$gfx.DrawLine([System.Drawing.Pens]::Black, 0, 35, $width, 35)

# Termine zeichnen
$y = 40
if ($events.Count -eq 0) {
    $gfx.DrawString("Heute keine Termine.", $fontText, $black, 10, $y)
} else {
    foreach ($evt in $events) {
        $startDT = [datetime]::Parse($evt.start.dateTime).ToLocalTime()
        $endDT   = [datetime]::Parse($evt.end.dateTime).ToLocalTime()
        $subject = if ($evt.subject) { $evt.subject } else { "[kein Betreff]" }

        $startTime = $startDT.ToString("HH:mm")
        $endTime   = $endDT.ToString("HH:mm")

        $blockY = $y

        # Zeit
        $gfx.DrawString("$startTime - $endTime"+":", $fontTime, $black, 10, $y)
        $y += 17

        # Textblock mehrzeilig zeichnen
        $rectX = 10
        $rectW = [float]($width - 20)
        $rect = New-Object System.Drawing.RectangleF($rectX, $y, $rectW, 999)
        $sf   = New-Object System.Drawing.StringFormat
        $gfx.DrawString($subject, $fontText, $black, $rect, $sf)

        $textSize = $gfx.MeasureString($subject, $fontText, $width - 20)
        $totalHeight = [Math]::Ceiling($textSize.Height)
        $y += $totalHeight + 4

        # Aktuellen Termin hervorheben
        if ($now -ge $startDT -and $now -lt $endDT) {
            $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::Red)
            $gfx.DrawRectangle($borderPen, $rectX - 2, $blockY - 2, $rectW + 2, $y - $blockY + 2)
            $borderPen.Dispose()
        }
    }

    if ($events.Count -eq 1) {
        $gfx.DrawString("Heute keine weiteren Termine.", $fontText, $black, 10, $y + 5)
    }
}

# === BILD SPEICHERN ==============================
$bmp.Save($outFile, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "✅ Bild gespeichert unter: $outFile" -ForegroundColor Green

# === BILD AN OEPL SENDEN =========================
Write-Host "📤 Sende Bild an OEPL..." -ForegroundColor Cyan
curl.exe -X POST $oeplUrl `
    -F "file=@$outFile" `
    -F "id=$displayId" `
    -H "accept: application/json" | Out-Null
Write-Host "✅ Bild erfolgreich an $displayId gesendet." -ForegroundColor Green

# === SIGNATUR AKTUALISIEREN ======================
$currentHash | Out-File -FilePath $signatureFile -Encoding ASCII
