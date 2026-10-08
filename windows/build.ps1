$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    cargo build --locked --release -p glide-windows
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed' }
    $package = Join-Path $PSScriptRoot 'dist/Glide'
    New-Item -ItemType Directory -Force $package | Out-Null
    Copy-Item 'target/release/glide-windows.exe' "$package/Glide.exe" -Force
    Copy-Item 'target/release/glide-native-host.exe' $package -Force
    Copy-Item '../Companion' "$package/Companion" -Recurse -Force
    Copy-Item 'install.ps1', 'uninstall.ps1', 'README.md' $package -Force
    Copy-Item '../LICENSE' $package -Force
    Compress-Archive -Path "$package/*" -DestinationPath 'dist/Glide-Windows.zip' -Force
} finally { Pop-Location }
