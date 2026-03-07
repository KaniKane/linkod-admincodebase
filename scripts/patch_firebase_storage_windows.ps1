# Re-apply Windows fix for firebase_storage after `flutter pub get`.
# The Firebase C++ SDK for Windows does not include Storage::UseEmulator;
# this patches the plugin so the Windows build compiles.
# Run after: flutter pub get
# Example: .\scripts\patch_firebase_storage_windows.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$pluginCpp = Join-Path $projectRoot "windows\flutter\ephemeral\.plugin_symlinks\firebase_storage\windows\firebase_storage_plugin.cpp"

if (-not (Test-Path $pluginCpp)) {
  Write-Host "Run 'flutter pub get' first. File not found: $pluginCpp"
  exit 1
}

$content = Get-Content $pluginCpp -Raw

if ($content -match '#if !defined\(_WIN32\)') {
  Write-Host "Patch already applied. Skipping."
  exit 0
}

$needle = "  cpp_storage->UseEmulator(host, static_cast<int>(port));"
$replacement = @"
#if !defined(_WIN32)
  cpp_storage->UseEmulator(host, static_cast<int>(port));
#endif
"@
if ($content -notlike "*$needle*") {
  Write-Host "Pattern not found; plugin may have changed."
  exit 1
}
$content = $content.Replace($needle, $replacement)
Set-Content $pluginCpp $content -NoNewline
Write-Host "Patched firebase_storage for Windows build."
exit 0
