Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Türkçe Karakter Dönüştürme
function tr ($txt) {
    $txt = $txt -creplace "{S}", ([char]0x015e)
    $txt = $txt -creplace "{s}", ([char]0x015f)
    $txt = $txt -creplace "{G}", ([char]0x011e)
    $txt = $txt -creplace "{g}", ([char]0x011f)
    $txt = $txt -creplace "{I}", ([char]0x0130)
    $txt = $txt -creplace "{i}", ([char]0x0131)
    $txt = $txt -creplace "{O}", ([char]0x00d6)
    $txt = $txt -creplace "{o}", ([char]0x00f6)
    $txt = $txt -creplace "{U}", ([char]0x00dc)
    $txt = $txt -creplace "{u}", ([char]0x00fc)
    $txt = $txt -creplace "{C}", ([char]0x00c7)
    $txt = $txt -creplace "{c}", ([char]0x00e7)
    return $txt
}

$bgPath = "c:\KesifApp\marketing_assets\bg_template.png"
$cardPath = "c:\KesifApp\marketing_assets\gold_card_template.png"
$logoPath = "c:\KesifApp\real_logo.png"
$mapPath = "c:\KesifApp\screenshot.jpg"

$outputMaster = "c:\KesifApp\kesif_perfect_master.png"
$outputDir = "c:\KesifApp\kesif_grid_posts"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir
}

$bmpMaster = New-Object System.Drawing.Bitmap(1200, 1200)
$g = [System.Drawing.Graphics]::FromImage($bmpMaster)
$g.SmoothingMode = "HighQuality"
$g.InterpolationMode = "HighQualityBicubic"
$g.PixelOffsetMode = "HighQuality"
$g.TextRenderingHint = "ClearTypeGridFit"

# Arka Plan
if (Test-Path $bgPath) {
    $bgImg = [System.Drawing.Image]::FromFile($bgPath)
    $g.DrawImage($bgImg, 0, 0, 1200, 1200)
    $bgImg.Dispose()
} else {
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0,0)), 
        (New-Object System.Drawing.Point(0,1200)), 
        [System.Drawing.Color]::FromArgb(10, 14, 39), 
        [System.Drawing.Color]::FromArgb(26, 26, 46)
    )
    $g.FillRectangle($brush, 0, 0, 1200, 1200)
    $brush.Dispose()
}

# MODERN & PREMİUM YAZI TİPLERİ
# Başlıklar için güçlü geometrik "Century Gothic"
# Açıklamalar (Beyazlar ve Kutu İçi Metinler) için çok daha zarif ve okunaklı "Corbel" fontu
$fontTitle = New-Object System.Drawing.Font("Century Gothic", 22, [System.Drawing.FontStyle]::Bold)
$fontSub = New-Object System.Drawing.Font("Corbel", 14, [System.Drawing.FontStyle]::Regular)
$fontCardHeader = New-Object System.Drawing.Font("Century Gothic", 16, [System.Drawing.FontStyle]::Bold)
$fontCardBody = New-Object System.Drawing.Font("Corbel", 13, [System.Drawing.FontStyle]::Regular)

$brushWhite = [System.Drawing.Brushes]::White
$brushGold = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(212, 175, 55))
$brushDark = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(10, 14, 39))

function Get-RoundedRectPath ($x, $y, $w, $h, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $arcRect = New-Object System.Drawing.RectangleF($x, $y, $diameter, $diameter)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $x + $w - $diameter
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $y + $h - $diameter
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = $x
    $path.AddArc($arcRect, 90, 90)
    $path.CloseFigure()
    return $path
}

# ----------------- 9 KARE ÇİZİMİ -----------------

# [KARE 1] Row 0, Col 0 - Keşif Başlık
$rect1 = New-Object System.Drawing.RectangleF(40, 60, 320, 160)
$g.DrawString((tr "{S}ehrinin`nGizli Yerlerini`nKe{s}fet!"), $fontTitle, $brushGold, $rect1)
$rect1Sub = New-Object System.Drawing.RectangleF(40, 220, 320, 120)
$g.DrawString((tr "8 farklı kategori filtresiyle en şık kafeleri, saklı manzaraları ve tarihi mekanları haritada anında bul."), $fontSub, $brushWhite, $rect1Sub)

# [KARE 2] Row 0, Col 1 - Logo ve Başlık
if (Test-Path $logoPath) {
    $logoImg = [System.Drawing.Image]::FromFile($logoPath)
    $g.DrawImage($logoImg, 525, 80, 150, 150)
    $logoImg.Dispose()
}
$g.DrawString((tr "KE{S}{I}F"), $fontTitle, $brushGold, 540, 250)
$g.DrawString((tr "Sosyal Harita & Ke{s}if"), $fontSub, $brushWhite, 500, 310)

# [KARE 3] Row 0, Col 2 - Pati Dostu Mekanlar
if (Test-Path $cardPath) {
    $cardImg = [System.Drawing.Image]::FromFile($cardPath)
    $g.DrawImage($cardImg, 830, 60, 340, 280)
    $cardImg.Dispose()
}
$g.DrawString((tr "Pati Dostu Yerler"), $fontCardHeader, $brushDark, 890, 105)
$rect3Body = New-Object System.Drawing.RectangleF(890, 150, 220, 160)
$g.DrawString((tr "Evcil hayvanınla birlikte gidebileceğin en samimi ve dost mekanları süzerek zahmetsizce keşfet."), $fontCardBody, $brushDark, $rect3Body)

# [KARE 4] Row 1, Col 0 - Telefon Mockup
$phoneW = 240.0
$phoneH = 490.0
$phoneX = 80.0
$phoneY = 355.0

$shadowPath = Get-RoundedRectPath ($phoneX + 8) ($phoneY + 8) $phoneW $phoneH 36
$shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120, 0, 0, 0))
$g.FillPath($shadowBrush, $shadowPath)
$shadowBrush.Dispose()
$shadowPath.Dispose()

$outerPath = Get-RoundedRectPath $phoneX $phoneY $phoneW $phoneH 36
$goldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(212, 175, 55))
$g.FillPath($goldBrush, $outerPath)
$outerPath.Dispose()
$goldBrush.Dispose()

$innerPath = Get-RoundedRectPath ($phoneX + 4) ($phoneY + 4) ($phoneW - 8) ($phoneH - 8) 32
$g.FillPath([System.Drawing.Brushes]::Black, $innerPath)
$innerPath.Dispose()

$screenX = $phoneX + 8
$screenY = $phoneY + 8
$screenW = $phoneW - 16
$screenH = $phoneH - 16
$screenPath = Get-RoundedRectPath $screenX $screenY $screenW $screenH 28

if (Test-Path $mapPath) {
    $mapImg = [System.Drawing.Image]::FromFile($mapPath)
    $srcW = $mapImg.Width
    $srcH = $mapImg.Height
    $ratioX = $screenW / $srcW
    $ratioY = $screenH / $srcH
    $ratio = [Math]::Max($ratioX, $ratioY)
    $drawW = $srcW * $ratio
    $drawH = $srcH * $ratio
    $drawX = $screenX + ($screenW - $drawW) / 2
    $drawY = $screenY + ($screenH - $drawH) / 2
    $oldClip = $g.Clip
    $g.SetClip($screenPath)
    $g.DrawImage($mapImg, [float]$drawX, [float]$drawY, [float]$drawW, [float]$drawH)
    $g.Clip = $oldClip
    $mapImg.Dispose()
}
$screenPath.Dispose()

$islandX = $phoneX + ($phoneW / 2) - 45
$islandY = $phoneY + 20
$islandPath = Get-RoundedRectPath $islandX $islandY 90 20 10
$g.FillPath([System.Drawing.Brushes]::Black, $islandPath)
$islandPath.Dispose()

# [KARE 5] Row 1, Col 1 - Merkez Slogan
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = "Center"
$g.DrawString((tr "{S}EHR{I}N{I}N`n{I}LK SOSYAL`nHAR{I}TASI"), $fontTitle, $brushGold, (New-Object System.Drawing.RectangleF(400, 500, 400, 200)), $sf)

# [KARE 6] Row 1, Col 2 - Canlı Rota
if (Test-Path $cardPath) {
    $cardImg = [System.Drawing.Image]::FromFile($cardPath)
    $g.DrawImage($cardImg, 830, 460, 340, 280)
    $cardImg.Dispose()
}
$g.DrawString((tr "Yürüyüş & Rota Takibi"), $fontCardHeader, $brushDark, 890, 505)
$rect6Body = New-Object System.Drawing.RectangleF(890, 550, 220, 160)
$g.DrawString((tr "Yürüdüğün yolları canlı GPS ile kaydet; mesafe, süre ve harita rotanı profilinde arşivle."), $fontCardBody, $brushDark, $rect6Body)

# [KARE 7] Row 2, Col 0 - Nöbetçi Eczaneler
if (Test-Path $cardPath) {
    $cardImg = [System.Drawing.Image]::FromFile($cardPath)
    $g.DrawImage($cardImg, 30, 860, 340, 280)
    $cardImg.Dispose()
}
$g.DrawString((tr "Nöbetçi Eczaneler"), $fontCardHeader, $brushDark, 90, 905)
$rect7Body = New-Object System.Drawing.RectangleF(90, 950, 220, 160)
$g.DrawString((tr "Acil durumlarda vakit kaybetme. Canlı nöbetçi eczaneleri haritada listele ve tek tıkla yol tarifi al."), $fontCardBody, $brushDark, $rect7Body)

# [KARE 8] Row 2, Col 1 - Arkadaşlık & Konum
$g.DrawString((tr "Arkadaşlık & Sohbet"), $fontTitle, $brushGold, 440, 900)
$rect8Body = New-Object System.Drawing.RectangleF(440, 960, 320, 180)
$g.DrawString((tr "Arkadaşlar ekle, haritadan canlı konumlarını gör ve dahili sohbetle anında yürüyüş ve kahve planları yap."), $fontSub, $brushWhite, $rect8Body)

# [KARE 9] Row 2, Col 2 - İndirme & Mağazalar
$g.DrawString((tr "Gizli Yerlerini Ekle"), $fontTitle, $brushGold, 850, 900)
$rect9Body = New-Object System.Drawing.RectangleF(850, 1000, 320, 150)
$g.DrawString((tr "Haritada olmayan gizli mekanları fotoğrafını çekerek ekle, diğer kaşiflerle anında paylaş!"), $fontSub, $brushWhite, $rect9Body)

$bmpMaster.Save($outputMaster, [System.Drawing.Imaging.ImageFormat]::Png)

$tileWidth = 400
$tileHeight = 400
$index = 1
for ($row = 0; $row -lt 3; $row++) {
    for ($col = 0; $col -lt 3; $col++) {
        $x = $col * $tileWidth
        $y = $row * $tileHeight
        $rect = New-Object System.Drawing.Rectangle($x, $y, $tileWidth, $tileHeight)
        $bmpTile = New-Object System.Drawing.Bitmap($tileWidth, $tileHeight)
        $gTile = [System.Drawing.Graphics]::FromImage($bmpTile)
        $gTile.SmoothingMode = "HighQuality"
        $gTile.DrawImage($bmpMaster, (New-Object System.Drawing.Rectangle(0, 0, $tileWidth, $tileHeight)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
        $outputPath = Join-Path $outputDir "kesif_grid_post_$index.png"
        $bmpTile.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $gTile.Dispose()
        $bmpTile.Dispose()
        $index++
    }
}

$g.Dispose()
$bmpMaster.Dispose()
Write-Host "Corbel font guncellemesi tamamlandi!"
