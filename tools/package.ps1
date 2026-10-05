# Builds the archive to publish on the project page.
# The archive holds exactly what a player needs: the Darken folder with the
# code, the locales, the media and the libraries. Neither docs, nor tests, nor
# tools, nor .git, nor .superpowers get in there — they have no business in the
# game.
# Run from the addon's root:  powershell -ExecutionPolicy Bypass -File tools/package.ps1
#
# There is one archive because there is one addon. Eleven separate module
# addons used to lie beside the core, and each had an archive of its own, a
# version of its own and a row of its own in the list on the character select
# screen; the player saw eleven addons where there is one thing. They are parts
# inside Darken now (the Features folder) and have no separate delivery.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$name = 'Darken'

# What goes into the archive. The list enumerates what is taken rather than
# what is thrown out: a list of exclusions silently lets every new directory
# through, while a list of inclusions silently loses it — and the loss is
# visible in the listing of contents the script prints at the end.
$folders = @('Libs', 'Core', 'Config', 'Skin', 'Modules', 'Features', 'Locale', 'Media')
$files = @(
    'Darken.toc',
    'Darken_Vanilla.toc',
    'Darken_Camelot.toc',
    'Darken_TBC.toc',
    'Darken_Mists.toc',
    'LICENSE',
    'README.md'
)

# The version is taken from the TOC rather than set by hand: otherwise the
# archive's name and what the addon shows in the "General" section would
# diverge.
$toc = Join-Path $root 'Darken.toc'
if (-not (Test-Path $toc)) { throw "$toc not found" }
$version = (Select-String -Path $toc -Pattern '^## Version:\s*(.+?)\s*$').Matches[0].Groups[1].Value
if (-not $version) { throw 'Darken.toc has no ## Version field' }

# The libraries are not kept in the repository. An archive without them would
# install and silently fail to work, so the check comes before the build rather
# than after it.
$libs = Join-Path $root 'Libs'
$needed = @(
    'LibStub', 'CallbackHandler-1.0', 'AceAddon-3.0', 'AceEvent-3.0',
    'AceConsole-3.0', 'AceDB-3.0', 'AceDBOptions-3.0', 'AceGUI-3.0',
    'AceConfig-3.0', 'LibSharedMedia-3.0'
)
foreach ($lib in $needed) {
    if (-not (Test-Path (Join-Path $libs $lib))) {
        throw "Libs\$lib is missing - run tools/fetch-libs.ps1 first"
    }
}

$dist = Join-Path $root 'dist'
$zip = Join-Path $dist ("{0}-{1}.zip" -f $name, $version)

# The archives of the same addon's previous versions are removed from dist.
#
# An archive's name carries the version, so a new build does not replace the old
# one but lies beside it. Two archives of one addon in one folder means a
# previous version gets published: the mistake is a silent one and is noticed by
# players. Only our own is deleted and only by the exact pattern
# "name-version.zip": somebody else's file may have got into dist by hand, and
# erasing it is not our business.
function Remove-OldArchives {
    param([string]$Dist, [string]$AddOn, [string]$Keep)

    if (-not (Test-Path $Dist)) { return }
    Get-ChildItem $Dist -Filter '*.zip' -File |
        Where-Object { $_.Name -match ('^' + [regex]::Escape($AddOn) + '-[0-9][0-9.]*\.zip$') } |
        Where-Object { $_.Name -ne $Keep } |
        ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Host ("  - old archive " + $_.Name)
        }
}
$tmp = Join-Path $env:TEMP ('darken-package-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $tmp $name

New-Item -ItemType Directory -Force -Path $dist  | Out-Null
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
    foreach ($folder in $folders) {
        $src = Join-Path $root $folder
        if (-not (Test-Path $src)) { throw "directory not found: $folder" }
        Copy-Item $src -Destination $stage -Recurse -Force
        Write-Host "  + $folder"
    }
    foreach ($file in $files) {
        $src = Join-Path $root $file
        if (-not (Test-Path $src)) { throw "file not found: $file" }
        Copy-Item $src -Destination $stage -Force
        Write-Host "  + $file"
    }

    # Housekeeping files from git and the editors must not get into the
    # archive, even when they lie inside a directory that was taken.
    Get-ChildItem $stage -Recurse -Force -Include '.git*', 'Thumbs.db', 'desktop.ini', '*.bak', '*.tmp' |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # The storefront art goes out again. Media/shots is the CurseForge
    # gallery and Media/branding holds the logo at every size it is needed
    # in - both live under Media so the addon keeps its art in one place,
    # but the player downloads the addon, not the storefront. Together they
    # are two megabytes of what nothing in the game ever opens.
    #
    # Two files there are the exception, and they are named rather than
    # guessed: the game can only load TGA, so the two TGAs under branding
    # are exactly the ones the addon draws with - the minimap button
    # (Modules/Launcher.lua) and the title of the settings window
    # (Options/Window.lua). A rule that dropped the whole directory would
    # take a working build down to an untextured button.
    $keep = @('darken-icon-64.tga', 'darken-title-256.tga')
    $shots = Join-Path (Join-Path $stage 'Media') 'shots'
    if (Test-Path $shots) { Remove-Item -Recurse -Force $shots }

    $branding = Join-Path (Join-Path $stage 'Media') 'branding'
    if (Test-Path $branding) {
        Get-ChildItem $branding -File |
            Where-Object { $keep -notcontains $_.Name } |
            Remove-Item -Force
    }
    foreach ($art in $keep) {
        if (-not (Test-Path (Join-Path $branding $art))) {
            throw "Media\branding\$art is missing - the addon draws with it"
        }
    }

    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
    Remove-OldArchives -Dist $dist -AddOn $name -Keep (Split-Path -Leaf $zip)

    Write-Host ''
    Write-Host "Done: $zip"

    # The listing of contents is always printed: a build is checked by what
    # lies in the archive rather than by what the script meant to put there.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = $archive.Entries | ForEach-Object { $_.FullName } | Sort-Object
        Write-Host ("Entries in the archive: {0}" -f $entries.Count)
        Write-Host 'Top level:'
        # The separator inside a zip comes both ways round: it is put there by
        # whichever library created the archive.
        $entries |
            ForEach-Object { (($_ -split '[\\/]') | Select-Object -First 2) -join '/' } |
            Sort-Object -Unique |
            ForEach-Object { '  ' + $_ }
    }
    finally {
        $archive.Dispose()
    }
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
