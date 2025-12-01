# Remove Mark of the Web from all .resx files
# Run this script in PowerShell on Windows
#
# If you get an execution policy error, run ONE of these commands:
#
# Option 1: Run the script bypassing execution policy (one-time):
#   PowerShell -ExecutionPolicy Bypass -File .\remove-mark-of-web.ps1
#
# Option 2: Run the commands directly (copy/paste into PowerShell):
#   Get-ChildItem -Recurse -Filter "*.resx" | ForEach-Object { Unblock-File -Path $_.FullName; Write-Host "Unblocked: $($_.FullName)" }
#
# Option 3: Set execution policy for current user (permanent):
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

Write-Host "Removing Mark of the Web from .resx files..." -ForegroundColor Cyan

$resxFiles = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "*.resx"

foreach ($file in $resxFiles) {
    Write-Host "Processing: $($file.FullName)" -ForegroundColor Yellow
    
    # Remove the Zone.Identifier alternate data stream
    try {
        Unblock-File -Path $file.FullName -ErrorAction SilentlyContinue
        Write-Host "  ✓ Unblocked" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nDone! All .resx files have been processed." -ForegroundColor Cyan
Write-Host "You can now rebuild the solution." -ForegroundColor Cyan
