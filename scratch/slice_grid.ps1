Add-Type -AssemblyName System.Drawing

$sourcePath = "c:\KesifApp\kesif_3x3_master.png"
$outputDir = "c:\KesifApp\kesif_grid_posts"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir
}

# Resmi Yükle
$img = [System.Drawing.Image]::FromFile($sourcePath)
$width = $img.Width
$height = $img.Height

# 3x3 bölme için boyutları hesapla
$tileWidth = [int]($width / 3)
$tileHeight = [int]($height / 3)

Write-Host "Resim boyutu: $width x $height"
Write-Host "Parça boyutu: $tileWidth x $tileHeight"

# Döngüyle 9 parçaya kes (Satır ve Sütun)
# Instagram'da doğru görünmesi için:
# Sıra 1: S1(sol-üst), S2(orta-üst), S3(sağ-üst)
# Sıra 2: S4(sol-orta), S5(merkez), S6(sağ-orta)
# Sıra 3: S7(sol-alt), S8(orta-alt), S9(sağ-alt)

$index = 1
for ($row = 0; $row -lt 3; $row++) {
    for ($col = 0; $col -lt 3; $col++) {
        $x = $col * $tileWidth
        $y = $row * $tileHeight
        
        # Kırpılacak alanı tanımla
        $rect = New-Object System.Drawing.Rectangle($x, $y, $tileWidth, $tileHeight)
        $bmp = New-Object System.Drawing.Bitmap($tileWidth, $tileHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        
        $graphics.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $tileWidth, $tileHeight)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
        
        # Parçayı Kaydet
        $outputPath = Join-Path $outputDir "kesif_grid_post_$index.png"
        $bmp.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        
        $graphics.Dispose()
        $bmp.Dispose()
        
        Write-Host "Kaydedildi: kesif_grid_post_$index.png"
        $index++
    }
}

$img.Dispose()
Write-Host "Dilimleme işlemi tamamlandı! Parçalar c:\KesifApp\kesif_grid_posts klasöründe."
