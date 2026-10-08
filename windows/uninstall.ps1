$ErrorActionPreference = 'Stop'
if ((Get-Process Glide, glide-windows -ErrorAction SilentlyContinue)) { throw 'Quit Glide from its tray menu before uninstalling.' }
$directory = Join-Path $env:LOCALAPPDATA 'Programs/Glide'
$registry = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.himanshu.glide'
if (Test-Path $registry) {
    $manifest = (Get-Item $registry).GetValue('')
    if ([IO.Path]::GetFullPath($manifest) -eq [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Glide/native-host.json'))) { Remove-Item $registry }
}
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Glide.lnk'
if (Test-Path $shortcut) { Remove-Item $shortcut }
if (Test-Path $directory) { Remove-Item $directory -Recurse -Force }
Write-Output 'Glide removed. Preferences remain in %LOCALAPPDATA%\Glide. Remove the companion in chrome://extensions.'
