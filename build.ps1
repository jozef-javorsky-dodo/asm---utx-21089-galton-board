gcc -O3 galton.s -o galton.exe
if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful. Running simulation..." -ForegroundColor Green
    Measure-Command { .\galton.exe }
    if (Test-Path "galton_asm.bmp") {
        Write-Host "Success! galton_asm.bmp generated." -ForegroundColor Green
    } else {
        Write-Host "Simulation ran but galton_asm.bmp was not found." -ForegroundColor Red
    }
} else {
    Write-Host "Build failed." -ForegroundColor Red
}
