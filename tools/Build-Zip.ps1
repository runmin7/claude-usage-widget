# Builds dist\ClaudeUsageMonitor.zip: only what a recipient needs to run the program.
#
# Excluded on purpose:
#   config.json  machine-specific (widget position, per-user preferences); it is recreated
#   .docs        internal worklog and handover notes
#   tools        maintenance scripts, not needed to run
#   dist         the output itself
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Zip.ps1
#
# ASCII only.

$root = Split-Path $PSScriptRoot
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist '_stage'

& (Join-Path $PSScriptRoot 'Fix-Encoding.ps1') | Out-Null
'BOM checked'

New-Item -ItemType Directory -Path $dist -Force | Out-Null
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage 'lib') -Force | Out-Null

foreach ($name in @('ClaudeUsageMonitor.ps1', 'start.vbs', 'guide.html', 'MODULES.md')) {
    $from = Join-Path $root $name
    if (-not (Test-Path $from)) { throw "missing: $name" }
    Copy-Item $from (Join-Path $stage $name)
}

$libFiles = @(Get-ChildItem (Join-Path $root 'lib') -Filter '*.ps1' -File)
if ($libFiles.Count -eq 0) { throw 'lib/ is empty' }
foreach ($file in $libFiles) { Copy-Item $file.FullName (Join-Path $stage 'lib') }

$zip = Join-Path $dist 'ClaudeUsageMonitor.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Entries are added one by one instead of with CreateFromDirectory, because that helper
# writes the platform separator -- "lib\Api.ps1" -- and the ZIP format requires forward
# slashes. .NET's own extractor copes, but other tools can create a file literally named
# "lib\Api.ps1" instead of a lib folder.
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($file in (Get-ChildItem $stage -Recurse -File)) {
        $name = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $name, 'Optimal')
    }
}
finally { $archive.Dispose() }
Remove-Item $stage -Recurse -Force

'--- contents ---'
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
$archive.Entries | Sort-Object FullName | ForEach-Object {
    '  {0,-34} {1,7:N0} bytes' -f $_.FullName, $_.Length
}
$count = $archive.Entries.Count
$archive.Dispose()

''
"$count files, $([int]((Get-Item $zip).Length / 1024)) KB"
"-> $zip"
