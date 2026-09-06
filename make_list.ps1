# Creates list.json from all audio files in this folder and subfolders
# Place in the main shiurim folder and run:
#   powershell -ExecutionPolicy Bypass -File .\make_list.ps1

$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }

$files = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3)$' } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' } |
    Sort-Object

$json = ConvertTo-Json @($files) -Depth 1

# Save as UTF-8 without BOM so the site reads Hebrew correctly
[System.IO.File]::WriteAllText((Join-Path $root 'list.json'), $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host ("Created list.json with " + $files.Count + " files") -ForegroundColor Green
Write-Host "Now upload list.json to GitHub (replace the existing one)"
Write-Host ""
Read-Host "Press Enter to close"
