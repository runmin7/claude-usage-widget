# Re-applies the UTF-8 BOM to every .ps1 in the project.
#
# PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI, which mangles the Korean text and
# makes the script fail to parse. Most editors and tools strip the BOM on save, so run
# this after editing any file.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Fix-Encoding.ps1
#
# ASCII only, so this file keeps working even when the others are broken.

$root = Split-Path $PSScriptRoot
$targets = @(Get-ChildItem $root -Filter '*.ps1' -Recurse -File |
    Where-Object { $_.FullName -notlike '*\dist\*' })

$fixed = 0
foreach ($file in $targets) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

    $relative = $file.FullName.Substring($root.Length + 1)
    if ($hasBom) {
        "  ok      $relative"
        continue
    }

    # Read as UTF-8 without a BOM, write it back with one. The text is unchanged.
    $text = [IO.File]::ReadAllText($file.FullName, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($file.FullName, $text, [Text.UTF8Encoding]::new($true))
    "  FIXED   $relative"
    $fixed++
}

''
"checked $($targets.Count) files, fixed $fixed"

# A missing BOM usually shows up as a parse error, so verify while we are here.
''
'--- parse check ---'
$bad = 0
foreach ($file in $targets) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$errors)
    if ($errors) {
        $bad++
        $relative = $file.FullName.Substring($root.Length + 1)
        "  ERROR   $relative : line $($errors[0].Extent.StartLineNumber) $($errors[0].Message)"
    }
}
if ($bad -eq 0) { '  all files parse clean' } else { "  $bad file(s) with errors" }
