$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    cargo build --locked --release -p glide-windows
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed' }
    $package = Join-Path $PSScriptRoot 'dist/Glide'
    if (Test-Path $package) { Remove-Item $package -Recurse -Force }
    New-Item -ItemType Directory -Force $package | Out-Null
    Copy-Item 'target/release/glide-windows.exe' "$package/Glide.exe" -Force
    Copy-Item 'target/release/glide-native-host.exe' $package -Force
    Copy-Item '../Companion' "$package/Companion" -Recurse -Force
    Copy-Item 'install.ps1', 'uninstall.ps1', 'README.md' $package -Force
    Copy-Item '../LICENSE' $package -Force
    # Include license files for the crates downloaded by this Rust build.
    $cargoDirectory = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
    $registries = Get-ChildItem (Join-Path $cargoDirectory 'registry/src') -Directory
    foreach ($registry in $registries) {
        foreach ($crate in (Get-ChildItem $registry.FullName -Directory)) {
            $notices = Get-ChildItem $crate.FullName -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE)(\.|-|$)' }
            $licenseDirectory = Join-Path $package "licenses/$($crate.Name)"
            New-Item -ItemType Directory -Force $licenseDirectory | Out-Null
            Copy-Item (Join-Path $crate.FullName 'Cargo.toml') $licenseDirectory
            $notices | Copy-Item -Destination $licenseDirectory
        }
    }
    Compress-Archive -Path "$package/*" -DestinationPath 'dist/Glide-Windows.zip' -Force
} finally { Pop-Location }
