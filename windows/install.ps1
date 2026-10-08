$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:LOCALAPPDATA 'Programs/Glide'
if ((Get-Process Glide, glide-windows, glide-native-host -ErrorAction SilentlyContinue)) { throw 'Disable Glide Companion in Chrome and quit Glide before installing or upgrading.' }
New-Item -ItemType Directory -Force $destination | Out-Null
if ($PSScriptRoot -ne $destination) { Get-ChildItem $PSScriptRoot | Copy-Item -Destination $destination -Recurse -Force }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Glide.lnk'))
$shortcut.TargetPath = Join-Path $destination 'Glide.exe'
$shortcut.WorkingDirectory = $destination
$shortcut.Save()
Start-Process (Join-Path $destination 'Glide.exe')
Write-Output "Installed Glide at $destination"
