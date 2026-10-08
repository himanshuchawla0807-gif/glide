$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot '../dist/Glide'
$helper = Join-Path $package 'glide-native-host.exe'
$unexpected = & $helper 'chrome-extension://untrusted/'
if ($LASTEXITCODE -ne 1 -or $unexpected) { throw 'Native helper accepted an untrusted extension or wrote unexpected output' }
# GitHub's PowerShell wrapper propagates LASTEXITCODE at script completion.
# The helper's intentional origin rejection was successful verification.
$global:LASTEXITCODE = 0
$installed = Join-Path $env:LOCALAPPDATA 'Programs/Glide'
& (Join-Path $package 'install.ps1')
Start-Sleep -Seconds 1
$process = Get-Process Glide -ErrorAction Stop
if (!(Test-Path (Join-Path $installed 'Companion/manifest.json'))) { throw 'Installed companion is missing' }
if (!(Test-Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'Glide.lnk'))) { throw 'Start Menu shortcut missing' }
try {
    Start-Sleep -Seconds 6
    $process.Refresh()
    if ($process.HasExited) { throw "Glide exited on startup: $($process.ExitCode)" }
    $key = Get-Item 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.himanshu.glide'
    $manifestPath = $key.GetValue('')
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.name -ne 'com.himanshu.glide' -or !(Test-Path $manifest.path)) { throw 'Invalid native host registration' }
    if ($manifest.allowed_origins.Count -ne 1 -or $manifest.allowed_origins[0] -ne 'chrome-extension://ampmdcedpokcijoakniagpieaebfooio/') { throw 'Unexpected extension allowlist' }
    $session = Get-Content (Join-Path $env:LOCALAPPDATA 'Glide/session.json') -Raw | ConvertFrom-Json
    if (!$session.name.StartsWith('glide-') -or !$session.token) { throw 'Named pipe discovery missing' }
    Write-Output 'Passed Windows startup, per-user registration, local pipe discovery and extension-origin rejection'
} finally { if (!$process.HasExited) { Stop-Process -Id $process.Id -Force } }

& (Join-Path $installed 'uninstall.ps1')
if ((Test-Path $installed) -or (Test-Path 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.himanshu.glide')) { throw 'Uninstall did not remove the application and registration' }
Write-Output 'Passed per-user installation and removal'
