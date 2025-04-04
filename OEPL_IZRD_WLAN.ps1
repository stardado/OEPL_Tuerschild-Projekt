# === TLS für HTTPS aktivieren =====================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# === QRCoder DLL aus NuGet extrahieren ============
$qrDllPath = "$PSScriptRoot\QRCoder.dll"
if (-not (Test-Path $qrDllPath)) {
    try {
        Write-Host "🔄 Lade QRCoder.dll von NuGet..." -ForegroundColor Cyan
        $nupkgUrl = "https://www.nuget.org/api/v2/package/QRCoder"
        $nupkgPath = "$PSScriptRoot\QRCoder.zip"
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath -UseBasicParsing

        $extractPath = "$PSScriptRoot\QRCoder_extract"
        Expand-Archive -Path $nupkgPath -DestinationPath $extractPath -Force

        $dllSource = Get-ChildItem -Path "$extractPath\lib" -Recurse -Filter "QRCoder.dll" | Where-Object { $_.FullName -match "netstandard|net\\d+" } | Select-Object -First 1
        if (-not $dllSource) { throw "QRCoder.dll nicht gefunden in NuGet-Paket." }

        Copy-Item -Path $dllSource.FullName -Destination $qrDllPath -Force
        Remove-Item $nupkgPath -Force
        Remove-Item $extractPath -Recurse -Force

        Write-Host "✅ QRCoder.dll gespeichert unter: $qrDllPath" -ForegroundColor Green
    } catch {
        Write-Host "❌ Fehler beim Herunterladen oder Extrahieren von QRCoder:`n$($_.Exception.Message)" -ForegroundColor Red
        exit
    }
}

try {
    Add-Type -Path $qrDllPath
} catch {
    Write-Host "❌ Fehler beim Laden der QRCoder.dll:`n$($_.Exception.Message)" -ForegroundColor Red
    exit
}

# === KONFIGURATION ===============================
$outFile1       = "$PSScriptRoot\wlan_guest.jpg"
$outFile2       = "$PSScriptRoot\wlan_guest_152x200.jpg"
$signatureFile1 = "$PSScriptRoot\wlan_guest.lastcontent.txt"
$signatureFile2 = "$PSScriptRoot\wlan_guest_152x200.lastcontent.txt"
$oeplUrl        = "http://198.51.100.200/imgupload"
$displayMac1    = "780105561C412345"
$displayMac2    = "DAFAFEFE7C012345"
$ssid           = "IZRD-Gast"
$rssUrls        = @("https://www.sportschau.de/index~rss2.xml","https://sportbild.bild.de/feed/sportbild-home.xml")
$qrCodePath     = "$PSScriptRoot\qrcode.png"
# =================================================

# === ERFORDELICHE TYPEN ==========================
Add-Type -AssemblyName System.Drawing

# === FUNKTION: RSS-Abruf mit Fallback und Retry ===

function Get-GuestPassword {
    Write-Host "🔍 Versuche Passwort aus RSS zu generieren..." -ForegroundColor Cyan
    $tries = 1
    $allWords = @()

    foreach ($rssUrl in $rssUrls) {
        for ($i = 1; $i -le $tries; $i++) {
            try {
                $headers = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
                $rss = [xml](Invoke-WebRequest -Uri $rssUrl -Headers $headers -UseBasicParsing -TimeoutSec 10).Content
                foreach ($item in $rss.rss.channel.item) {
                    $titleWords = ($item.title -split '\s+')
                    $filtered = $titleWords | Where-Object { $_ -cmatch '^[A-ZÄÖÜ][a-zäöüß]{2,}$' }
                    if ($filtered.Count -ge 2) {
                        $allWords += $filtered[1]
                    }
                }
                if ($allWords.Count -ge 5) { break }
            } catch {
                Write-Host "⚠️ Versuch $i mit Feed $rssUrl fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }

    $specialChar = Get-Random -InputObject @('!', '@', '#', '$', '%', '&', '*')
    $digits = Get-Random -Minimum 10 -Maximum 99

    do {
        $word1 = $allWords | Get-Random
        $word2 = ($allWords | Where-Object { $_ -ne $word1 }) | Get-Random
        $password = "$word1$word2$specialChar$digits"
    } while ($password.Length -lt 12 -or $password.Length -gt 20)

    if (-not $password) {
        Write-Host "❌ Fehler beim Generieren des Passworts – Fallback wird verwendet." -ForegroundColor Red
        return "GaesteWLAN!23"
    }

    return $password
}

# === PASSWORT ERZEUGEN ============================
$password = Get-GuestPassword

# === QR-CODE GENERIEREN (lokal mit QRCoder) =======
Write-Host "🔍 Erzeuge QR-Code lokal..." -ForegroundColor Cyan
$wifiQR = "WIFI:T:WPA;S:$ssid;P:$password;;"

$qrGenerator = New-Object QRCoder.QRCodeGenerator
$qrData = $qrGenerator.CreateQrCode($wifiQR, [QRCoder.QRCodeGenerator+ECCLevel]::Q)
$qrCodeBmp = New-Object QRCoder.QRCode -ArgumentList $qrData
$qrImage = $qrCodeBmp.GetGraphic(20, [System.Drawing.Color]::Black, [System.Drawing.Color]::White, $false)

$qrImage.Save($qrCodePath, [System.Drawing.Imaging.ImageFormat]::Png)
$qrCode = [System.Drawing.Image]::FromFile($qrCodePath)

# === BILDER GENERIEREN ===========================
function Generate-WLANImage {
    param(
        [int]$width,
        [int]$height,
        [string]$outputFile,
        [bool]$minimal = $false
    )

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.SmoothingMode = "AntiAlias"
    $gfx.TextRenderingHint = "AntiAlias"
    $gfx.Clear([System.Drawing.Color]::White)

    $black       = [System.Drawing.Brushes]::Black
    $yellowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 204, 0))
    $fontHeader  = New-Object System.Drawing.Font("Arial", 14, ([System.Drawing.FontStyle]::Bold))
    $fontLabel   = New-Object System.Drawing.Font("Segoe UI", 13.5, ([System.Drawing.FontStyle]::Bold))
    $fontValue   = New-Object System.Drawing.Font("Segoe UI", 14.5)
    $fontHint    = New-Object System.Drawing.Font("Segoe UI", 12, ([System.Drawing.FontStyle]::Bold))

    # === KOPFZEILE ===
    $gfx.FillRectangle($yellowBrush, 0, 0, $width, 33)
    $gfx.DrawString("Gäste-WLAN", $fontHeader, $black, 10, 5)
    if (-not $minimal) {
        $rightText = "IZRD e.V."
        $rightSize = $gfx.MeasureString($rightText, $fontHeader)
        $gfx.DrawString($rightText, $fontHeader, $black, $width - $rightSize.Width - 10, 5)
    }
    $gfx.DrawLine([System.Drawing.Pens]::Black, 0, 33, $width, 33)


    if (-not $minimal) {
        # === SSID & Passwort ===
        $gfx.DrawString("Netzwerkname:", $fontLabel, $black, 10, 35)
        $gfx.DrawString($ssid, $fontValue, $black, 10, 55)

        $gfx.DrawString("Passwort:", $fontLabel, $black, 10, 80)
        $gfx.DrawString($password, $fontValue, $black, 10, 100)

        $gfx.DrawString("Hinweis:", $fontLabel, $black, 10, 130)
        $gfx.DrawString("Nur heute gültig!", $fontValue, $black, 10, 150)

        # === QR-Code rechts zentriert ===
        $qrSize = 130
        $qrX = $width - $qrSize - 10
        $qrY = [Math]::Round(($height - 10 - $qrSize) / 2 + 21)
        $gfx.DrawImage($qrCode, $qrX, $qrY, $qrSize, $qrSize)
    } else {
        # === QR-Code mittig ===
        $qrSize = 120
        $qrX = [Math]::Round(($width - $qrSize) / 2)
        $qrY = [Math]::Round(($height - $qrSize) / 2) 
        $gfx.DrawImage($qrCode, $qrX, $qrY, $qrSize, $qrSize + 5)

        $hintText = "Jetzt scannen!"
        $hintSize = $gfx.MeasureString($hintText, $fontHint)
        $gfx.DrawString($hintText, $fontHint, $black, ($width - $hintSize.Width) / 2, $qrY + $qrSize + 5)
    }

    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, 100L)
    $bmp.Save($outputFile, $jpegCodec, $encoderParams)
    $gfx.Dispose()
    $bmp.Dispose()
    Write-Host "✅ Bild gespeichert: $outputFile" -ForegroundColor Green
}

Generate-WLANImage -width 384 -height 184 -outputFile $outFile1 -minimal:$false
Generate-WLANImage -width 152 -height 200 -outputFile $outFile2 -minimal:$true

# === UPLOAD AN OEPL ==============================
foreach ($entry in @(@{Mac=$displayMac1; File=$outFile1}, @{Mac=$displayMac2; File=$outFile2})) {
    Write-Host "📤 Lade Bild an Display $($entry.Mac) hoch..." -ForegroundColor Cyan
    $args = @(
        "-X", "POST", "$oeplUrl",
        "-F", "mac=$($entry.Mac)",
        "-F", "dither=0",
        "-F", "image=@$($entry.File);type=image/jpeg",
        "-H", "accept: application/json"
    )
    Start-Process -FilePath "curl.exe" -ArgumentList $args -NoNewWindow -Wait
    Write-Host "✅ Bild an Display $($entry.Mac) übertragen." -ForegroundColor Green
}
# === WLAN PW ÄndernRN ==========================

function Set-GuestWlanPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NewGuestPassword
    )

    # Zertifikat-Validierung global deaktivieren
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    # Feste Unify-Controller-Details
    $Controller = "https://198.51.100.201:8443"
    $Username   = "<admin-username>"
    $Password   = '<admin-pw>'
    # Hier den Site-Namen anpassen; laut deiner Sites-Abruf-Ergebnis ist es "default"
    $Site       = "default"

    # Erstelle eine persistente Web-Session
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    # Login-Payload
    $loginBody = @{
        username = $Username
        password = $Password
    } | ConvertTo-Json

    Write-Verbose "Versuche, mich am Controller anzumelden..."
    try {
        $loginResponse = Invoke-RestMethod -Uri "$Controller/api/login" -Method POST -Body $loginBody -ContentType "application/json" -WebSession $session
        Write-Verbose "Login Response: $($loginResponse | ConvertTo-Json -Depth 4)"
    }
    catch {
        Write-Error "Login fehlgeschlagen: $_"
        return $false
    }

    Write-Verbose "Abrufen der WLAN-Konfigurationen..."
    try {
        $wlanResponse = Invoke-RestMethod -Uri "$Controller/api/s/$Site/rest/wlanconf" -Method GET -WebSession $session
        Write-Verbose "WLAN-Konfigurationen: $($wlanResponse | ConvertTo-Json -Depth 4)"
    }
    catch {
        Write-Error "Fehler beim Abrufen der WLAN-Daten: $_"
        return $false
    }

    # Suche das WLAN, das Gäste enthält – passe den Filter bei Bedarf an
    $guestWlan = $wlanResponse.data | Where-Object { $_.name -like "*Gast*" }
    if (-not $guestWlan) {
        Write-Output "Gast WLAN nicht gefunden."
        return $false
    }

    # Setze das neue Kennwort über die Eigenschaft x_passphrase
    $guestWlan.x_passphrase = $NewGuestPassword
    $updateBody = $guestWlan | ConvertTo-Json

    Write-Verbose "Aktualisiere die WLAN-Konfiguration..."
    try {
        $updateResponse = Invoke-RestMethod -Uri "$Controller/api/s/$Site/rest/wlanconf/$($guestWlan._id)" -Method PUT -Body $updateBody -ContentType "application/json" -WebSession $session
        Write-Output "Das Gast WLAN-Kennwort wurde erfolgreich geändert."
        return $true
    }
    catch {
        Write-Error "Fehler beim Aktualisieren der WLAN-Daten: $_"
        return $false
    }
}

# Beispielaufruf der Funktion – alle Parameter sind fest, nur das neue Passwort wird übergeben
Set-GuestWlanPassword -NewGuestPassword $password

# === SIGNATUR SPEICHERN ==========================
$plainText = "$ssid|$password"
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
$md5 = [System.Security.Cryptography.MD5]::Create()
$hash = ([System.BitConverter]::ToString($md5.ComputeHash($hashBytes)) -replace "-", "").ToLower()
$hash | Out-File -FilePath $signatureFile1 -Encoding ASCII
$hash | Out-File -FilePath $signatureFile2 -Encoding ASCII

# === QR-CODE FREIGEBEN & ENTFERNEN ===============
$qrCode.Dispose()
Remove-Item $qrCodePath -Force
Write-Host "🧹 QR-Code-Bild entfernt: $qrCodePath" -ForegroundColor DarkGray
