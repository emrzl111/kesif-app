Add-Type -AssemblyName System.Drawing
$folder = "C:\Users\Asus\.gemini\antigravity-ide\brain\3f392ce1-2549-49b4-aaa0-aa3bc8f3a249"
Get-ChildItem -Path $folder -Filter *.png | ForEach-Object {
    try {
        $img = [System.Drawing.Image]::FromFile($_.FullName)
        if ($img.Width -eq 1024 -and $img.Height -eq 500) {
            Write-Output ($_.Name + ": " + $img.Width + "x" + $img.Height)
        }
        $img.Dispose()
    } catch {}
}
