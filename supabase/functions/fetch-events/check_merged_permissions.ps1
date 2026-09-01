$folder = "c:\KesifApp\kesif_app\build\app\intermediates\merged_manifests\release"
if (Test-Path $folder) {
    $manifestPath = Join-Path $folder "AndroidManifest.xml"
    if (Test-Path $manifestPath) {
        $content = Get-Content $manifestPath
        $content | Select-String "uses-permission" | ForEach-Object { Write-Output $_.ToString() }
    } else {
        Write-Output "Merged AndroidManifest.xml not found in release folder"
    }
} else {
    Write-Output "Release merged_manifests folder not found"
}
