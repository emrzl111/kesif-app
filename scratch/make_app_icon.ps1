# Yeni logodan (appicon-yeni.png) uygulama ikonlarını üretir.
# Eski ikonlar assets\icons\eski_ikonlar klasörüne yedeklenir.
$d = 'c:\KesifApp\kesif_app\assets\icons'

New-Item -ItemType Directory -Force "$d\eski_ikonlar" | Out-Null
Copy-Item "$d\app_icon.png" "$d\eski_ikonlar\app_icon.png" -Force
Copy-Item "$d\app_icon_foreground.png" "$d\eski_ikonlar\app_icon_foreground.png" -Force

Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile("$d\appicon-yeni.png")

function Make($path, $ratio, $bg) {
  $size = 1024
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.SmoothingMode = 'HighQuality'
  $g.PixelOffsetMode = 'HighQuality'
  if ($bg) { $g.Clear([System.Drawing.ColorTranslator]::FromHtml($bg)) }
  else { $g.Clear([System.Drawing.Color]::Transparent) }
  $scale = ($size * $ratio) / [Math]::Max($src.Width, $src.Height)
  $w = $src.Width * $scale
  $h = $src.Height * $scale
  $g.DrawImage($src, ($size - $w) / 2, ($size - $h) / 2, $w, $h)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# Normal ikon: beyaz zemin, logo %80
Make "$d\app_icon.png" 0.80 '#FFFFFF'
# Android uyarlanabilir ikon ön planı: şeffaf zemin, logo %60 (kırpılmaya karşı güvenli alan)
Make "$d\app_icon_foreground.png" 0.60 $null

$src.Dispose()
Write-Host "Tamam. Kaynak logo boyutu okundu, ikonlar üretildi." -ForegroundColor Green
