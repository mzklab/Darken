# Fetches the third-party libraries into Libs/.
# The libraries are not kept in the repository — they can always be fetched
# again.
# Run from the addon's root:  powershell -ExecutionPolicy Bypass -File tools/fetch-libs.ps1

$ErrorActionPreference = 'Stop'

# Ace3 is pinned to an exact commit. A floating master would mean that two
# developers — or one of them on different days — build a different addon, and
# none of that is visible in git. Raise the version deliberately only: change
# the sha, re-run the script and check the addon on all three clients.
# 1e98fc0 is master of github.com/WoWUIDev/Ace3 as of 2026-09-23.
$ace3Commit = '1e98fc00874779334d7a3f0cb399c7ae9a15fead'
$root = Split-Path -Parent $PSScriptRoot
$libs = Join-Path $root 'Libs'
$tmp  = Join-Path $env:TEMP ('umbra-libs-' + [guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $libs | Out-Null
New-Item -ItemType Directory -Force -Path $tmp  | Out-Null

try {
    Write-Host "Downloading Ace3 ($ace3Commit)..."
    $ace3 = Join-Path $tmp 'Ace3'
    git clone --quiet https://github.com/WoWUIDev/Ace3.git $ace3
    if ($LASTEXITCODE -ne 0) { throw 'failed to clone Ace3' }
    git -C $ace3 checkout --quiet $ace3Commit
    if ($LASTEXITCODE -ne 0) { throw "failed to check out the Ace3 commit: $ace3Commit" }

    $modules = @(
        'LibStub',
        'CallbackHandler-1.0',
        'AceAddon-3.0',
        'AceEvent-3.0',
        'AceConsole-3.0',
        'AceDB-3.0',
        'AceDBOptions-3.0',
        'AceGUI-3.0',
        'AceConfig-3.0'
    )
    foreach ($m in $modules) {
        $src = Join-Path $tmp "Ace3\$m"
        if (-not (Test-Path $src)) { throw "Ace3 module not found: $m" }
        Copy-Item $src -Destination $libs -Recurse -Force
        Write-Host "  + $m"
    }

    Write-Host 'Unpacking LibSharedMedia-3.0 out of MediaBarsX.zip...'
    $zip = Join-Path $root 'MediaBarsX.zip'
    if (-not (Test-Path $zip)) { throw "$zip is missing - there is nowhere to take LibSharedMedia from" }
    Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'mbx') -Force
    $lsm = Join-Path $tmp 'mbx\MediaBarsX\Libs\LibSharedMedia-3.0'
    if (-not (Test-Path $lsm)) { throw 'the archive holds no LibSharedMedia-3.0' }
    Copy-Item $lsm -Destination $libs -Recurse -Force
    Write-Host '  + LibSharedMedia-3.0'

    Write-Host ''
    Write-Host 'Done. The contents of Libs:'
    Get-ChildItem $libs -Directory | ForEach-Object { '  ' + $_.Name }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
