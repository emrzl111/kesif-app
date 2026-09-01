Add-Type -AssemblyName System.Drawing
$width = 1024
$height = 500
$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)

# Enable high quality rendering
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

# Draw dark blue background (#0B0F19)
$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(11, 15, 25))
$g.FillRectangle($bgBrush, 0, 0, $width, $height)

# Draw some subtle abstract geometric background lines
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 212, 175, 55), 2)
$g.DrawEllipse($pen, -100, -100, 600, 600)
$g.DrawEllipse($pen, 600, 200, 600, 600)

# Draw the logo (compass)
$logoPath = "c:\KesifApp\app_icon.png"
if (Test-Path $logoPath) {
    $logo = [System.Drawing.Image]::FromFile($logoPath)
    $logoSize = 340
    $logoX = 100
    $logoY = [int](($height - $logoSize) / 2)
    $g.DrawImage($logo, $logoX, $logoY, $logoSize, $logoSize)
    $logo.Dispose()
}

# Construct "KEŞİF" safely
$titleText = "KE" + [char]0x015E + [char]0x0130 + "F"

# Construct "Arkadaşlarınızı ve şehrin en popüler" (Line 1)
$subTextLine1 = "Arkada" + [char]0x015F + "lar" + [char]0x0131 + "n" + [char]0x0131 + "z" + [char]0x0131 + " ve " + [char]0x015F + "ehrin en pop" + [char]0x00FC + "ler"

# Construct "mekanlarını haritada canlı keşfedin!" (Line 2)
$subTextLine2 = "mekanlar" + [char]0x0131 + "n" + [char]0x0131 + " haritada canl" + [char]0x0131 + " ke" + [char]0x015F + "fedin!"

# Draw text on the right side
$fontName = "Georgia"
$fontTitle = New-Object System.Drawing.Font($fontName, 58, [System.Drawing.FontStyle]::Bold)
$fontSub = New-Object System.Drawing.Font("Arial", 18, [System.Drawing.FontStyle]::Regular)

$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 195, 85)) # Warm Gold
$subBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 205, 215)) # Grayish white

# Position titles and subtitles nicely
$g.DrawString($titleText, $fontTitle, $textBrush, 480, 140)
$g.DrawString($subTextLine1, $fontSub, $subBrush, 485, 245)
$g.DrawString($subTextLine2, $fontSub, $subBrush, 485, 285)

# Clean up
$fontTitle.Dispose()
$fontSub.Dispose()
$textBrush.Dispose()
$subBrush.Dispose()
$bgBrush.Dispose()
$pen.Dispose()
$g.Dispose()

# Save
$bmp.Save("c:\KesifApp\real_feature_graphic.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
