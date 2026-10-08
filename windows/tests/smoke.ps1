$ErrorActionPreference = 'Stop'
$package = Join-Path $PSScriptRoot '../dist/Glide'
$helper = Join-Path $package 'glide-native-host.exe'
$unexpected = & $helper 'chrome-extension://untrusted/'
if ($LASTEXITCODE -ne 1 -or $unexpected) { throw 'Native helper accepted an untrusted extension or wrote unexpected output' }
# GitHub's PowerShell wrapper propagates LASTEXITCODE at script completion.
# The helper's intentional origin rejection was successful verification.
$global:LASTEXITCODE = 0
$process = Start-Process (Join-Path $package 'Glide.exe') -PassThru
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
