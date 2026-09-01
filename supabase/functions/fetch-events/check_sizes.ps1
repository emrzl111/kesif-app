Add-Type -AssemblyName System.Drawing
$folder = "c:\KesifApp"
Get-ChildItem -Path $folder -Filter *.png | ForEach-Object {
    $img = [System.Drawing.Image]::FromFile($_.FullName)
    Write-Output ($_.Name + ": " + $img.Width + "x" + $img.Height)
    $img.Dispose()
}
