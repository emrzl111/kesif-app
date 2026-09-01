$brainDir = "C:\Users\Asus\.gemini\antigravity-ide\brain"
$dirs = Get-ChildItem -Path $brainDir -Directory | Where-Object { $_.Name -ne "tempmediaStorage" }

foreach ($dir in $dirs) {
    Write-Host "========================================"
    Write-Host "SESSION: $($dir.Name)"
    Write-Host "========================================"
    
    $mdFiles = Get-ChildItem -Path $dir.FullName -Filter "*.md"
    if ($mdFiles) {
        Write-Host "Artifacts:"
        foreach ($f in $mdFiles) {
            Write-Host "  - $($f.Name)"
        }
    }
    
    $tPath = Join-Path $dir.FullName ".system_generated\logs\transcript.jsonl"
    if (Test-Path $tPath) {
        $lines = Get-Content $tPath
        foreach ($line in $lines) {
            if ($line -like "*USER_INPUT*") {
                if ($line -match "<USER_REQUEST>(.*?)</USER_REQUEST>") {
                    Write-Host "  [USER REQUEST]: $($Matches[1].Trim())"
                } else {
                    Write-Host "  [RAW USER INPUT]: $($line.Substring(0, [Math]::Min(150, $line.Length)))"
                }
            }
        }
    }
    Write-Host "`n"
}
