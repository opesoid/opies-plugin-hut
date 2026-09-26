# [OPIE] Plugin Library setup window.
# Install copies the checked plugins. Uninstall removes only the checked plugins.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = 'Stop'

try {
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
} catch {
}
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not ([System.Management.Automation.PSTypeName]'OpieSetupWindow').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OpieSetupWindow {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$DistDir = Join-Path $RepoRoot 'dist'
$LibraryFile = Join-Path $DistDir 'library.txt'

$script:PluginDirs = @(
    (Join-Path $env:USERPROFILE '.runelite\microbot-plugins'),
    (Join-Path $env:USERPROFILE '.runelite\sideloaded-plugins')
)
$script:InstallDir = $script:PluginDirs[0]
$script:SkipClientCheck = $false

$script:ColorBg = [System.Drawing.Color]::FromArgb(18, 18, 20)
$script:ColorCard = [System.Drawing.Color]::FromArgb(32, 33, 38)
$script:ColorCardEdge = [System.Drawing.Color]::FromArgb(58, 60, 68)
$script:ColorText = [System.Drawing.Color]::FromArgb(245, 245, 247)
$script:ColorMuted = [System.Drawing.Color]::FromArgb(161, 161, 170)
$script:ColorAccent = [System.Drawing.Color]::FromArgb(255, 59, 48)
$script:ColorAccentDark = [System.Drawing.Color]::FromArgb(214, 40, 32)
$script:ColorInstalled = [System.Drawing.Color]::FromArgb(52, 211, 153)
$script:ColorWarning = [System.Drawing.Color]::FromArgb(251, 191, 36)
$script:ColorLog = [System.Drawing.Color]::FromArgb(14, 14, 16)

$script:HashCache = @{}
$script:SourceMetaCache = @{}
$script:JarVersionCache = @{}
$script:ShortcutFileName = '[OPIE] Plugin Library.lnk'
$script:LauncherDir = Join-Path $env:LOCALAPPDATA 'OpiesPluginLibrary'
$script:RunScriptUri = 'https://raw.githubusercontent.com/opesoid/opies-plugin-hut/dev/installer/run.ps1'

$script:PluginBlurbs = @{
    'OpiesBankSorterPlugin.jar' = 'Sorts the bank into an iron 8-tab layout.'
    'OpiesSandBuyerPlugin.jar' = 'Buys sand and soda ash in Catherby, then hops.'
    'OpiesEclipseRedPlugin.jar' = 'Collects Eclipse red at the Hunter Guild.'
    'OpiesMoltenGlassPlugin.jar' = 'Smelts molten glass at the Edgeville furnace.'
}

function Get-LibraryJarNames {
    if (-not (Test-Path -LiteralPath $LibraryFile)) {
        return @()
    }
    $names = @()
    foreach ($line in (Get-Content -LiteralPath $LibraryFile)) {
        $name = $line.Trim()
        if (-not $name -or $name.StartsWith('#')) { continue }
        if ($name -match '[\\/]' -or $name.Contains('..')) {
            throw "library.txt has an unsafe jar name: $name"
        }
        $names += $name
    }
    return @($names | Select-Object -Unique)
}

function Get-PluginLabel([string] $jarName) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($jarName)
    if ($name.StartsWith('Opies')) { $name = $name.Substring(5) }
    if ($name.EndsWith('Plugin')) { $name = $name.Substring(0, $name.Length - 6) }
    $spaced = [regex]::Replace($name, '(?<!^)([A-Z])', ' $1')
    return $spaced.Trim()
}

function Format-Stamp([System.IO.FileInfo] $file) {
    return '{0}  {1:N0} KB' -f $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), ($file.Length / 1KB)
}

function Test-ClientRunning {
    if ($script:SkipClientCheck) { return $false }
    $names = @('RuneLite', 'Microbot')
    return $null -ne (Get-Process -Name $names -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-InstalledCopy([string] $jarName) {
    $found = New-Object System.Collections.Generic.List[object]
    foreach ($path in (Get-InstalledJarPaths $jarName)) {
        [void] $found.Add((Get-Item -LiteralPath $path))
    }
    Write-Output -NoEnumerate $found
}

function Get-InstalledJarPaths([string] $jarName) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($jarName)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $script:PluginDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -File -Filter ($stem + '*.jar') -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq $jarName -or $file.Name.StartsWith($stem + '-')) {
                [void] $paths.Add($file.FullName)
            }
        }
    }
    Write-Output -NoEnumerate $paths
}

function Get-CachedFileHash([string] $path) {
    $item = Get-Item -LiteralPath $path
    $key = '{0}|{1}|{2}' -f $item.FullName, $item.Length, $item.LastWriteTimeUtc.Ticks
    if ($script:HashCache.ContainsKey($key)) {
        return $script:HashCache[$key]
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $script:HashCache[$key] = $hash
    return $hash
}

function Get-PluginSourceMeta([string] $jarName) {
    if ($script:SourceMetaCache.ContainsKey($jarName)) {
        return $script:SourceMetaCache[$jarName]
    }
    $meta = @{
        Version = $null
        MinClient = $null
    }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($jarName)
    $srcRoot = Join-Path $RepoRoot 'src'
    if (Test-Path -LiteralPath $srcRoot) {
        $file = Get-ChildItem -LiteralPath $srcRoot -Filter ($stem + '.java') -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $file) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ($text -match 'public static final String version = "([^"]+)"') {
                $meta.Version = $Matches[1]
            }
            if ($text -match 'minClientVersion = "([^"]+)"') {
                $meta.MinClient = $Matches[1]
            }
        }
    }
    $script:SourceMetaCache[$jarName] = $meta
    return $meta
}

function Get-AvailablePluginVersion([string] $jarName) {
    return (Get-PluginSourceMeta $jarName).Version
}

function Get-JarVersionStrings([string] $jarPath) {
    $item = Get-Item -LiteralPath $jarPath
    $key = '{0}|{1}|{2}' -f $item.FullName, $item.Length, $item.LastWriteTimeUtc.Ticks
    if ($script:JarVersionCache.ContainsKey($key)) {
        Write-Output -NoEnumerate @($script:JarVersionCache[$key])
        return
    }
    $found = New-Object System.Collections.Generic.List[string]
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($jarPath)
        try {
            $encoding = [System.Text.Encoding]::GetEncoding(28591)
            foreach ($entry in $zip.Entries) {
                if (-not $entry.FullName.EndsWith('Plugin.class')) { continue }
                if ($entry.FullName.Contains('$')) { continue }
                $stream = $entry.Open()
                try {
                    $memory = New-Object System.IO.MemoryStream
                    $stream.CopyTo($memory)
                    $bytes = $memory.ToArray()
                    $memory.Dispose()
                } finally {
                    $stream.Dispose()
                }
                $text = $encoding.GetString($bytes)
                foreach ($match in [regex]::Matches($text, '\d+\.\d+\.\d+')) {
                    $value = $match.Value
                    if (-not $found.Contains($value)) {
                        [void] $found.Add($value)
                    }
                }
            }
        } finally {
            $zip.Dispose()
        }
    } catch {
        $script:JarVersionCache[$key] = @()
        Write-Output -NoEnumerate $found
        return
    }
    $script:JarVersionCache[$key] = $found.ToArray()
    Write-Output -NoEnumerate $found
}

function Get-InstalledPluginVersion([string] $jarName, [string] $availableVersion) {
    $minClient = (Get-PluginSourceMeta $jarName).MinClient
    foreach ($file in (Get-InstalledCopy $jarName)) {
        $versions = Get-JarVersionStrings $file.FullName
        if ($versions.Count -eq 0) { continue }
        if ($availableVersion -and ($versions -contains $availableVersion)) {
            return $availableVersion
        }
        foreach ($value in $versions) {
            if ($value -eq $availableVersion) { continue }
            if ($minClient -and ($value -eq $minClient)) { continue }
            return $value
        }
    }
    return $null
}

function Test-PluginNeedsUpdate([string] $jarName) {
    $source = Join-Path $DistDir $jarName
    if (-not (Test-Path -LiteralPath $source)) { return $false }
    $installed = Get-InstalledCopy $jarName
    if ($installed.Count -eq 0) { return $false }
    try {
        $sourceHash = Get-CachedFileHash $source
        foreach ($file in $installed) {
            if ((Get-CachedFileHash $file.FullName) -ne $sourceHash) {
                return $true
            }
        }
    } catch {
        return $true
    }
    return $installed.Count -gt 1
}

function Get-DesktopShortcutPath {
    return (Join-Path ([Environment]::GetFolderPath('Desktop')) $script:ShortcutFileName)
}

function Test-DesktopShortcut {
    return (Test-Path -LiteralPath (Get-DesktopShortcutPath))
}

function Get-InstallerIconSource {
    return (Join-Path $ScriptDir 'opes-plugin-hut.ico')
}

function Install-ShortcutIcon {
    $source = Get-InstallerIconSource
    if (-not (Test-Path -LiteralPath $source)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $script:LauncherDir)) {
        New-Item -ItemType Directory -Path $script:LauncherDir | Out-Null
    }
    $dest = Join-Path $script:LauncherDir 'opes-plugin-hut.ico'
    Copy-Item -LiteralPath $source -Destination $dest -Force
    return $dest
}

function Add-DesktopShortcut {
    if (-not (Test-Path -LiteralPath $script:LauncherDir)) {
        New-Item -ItemType Directory -Path $script:LauncherDir | Out-Null
    }
    $vbs = Join-Path $script:LauncherDir 'Open-Installer.vbs'
    $launcher = @(
        "' Opens the latest [OPIE] Plugin Library installer.",
        'Set shell = CreateObject("Wscript.Shell")',
        ('command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""irm {0} | iex"""' -f $script:RunScriptUri),
        'shell.Run command, 0, False'
    ) -join "`r`n"
    Set-Content -LiteralPath $vbs -Value $launcher -Encoding ASCII
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut((Get-DesktopShortcutPath))
    $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $shortcut.Arguments = "//nologo `"$vbs`""
    $shortcut.WorkingDirectory = $script:LauncherDir
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Open the [OPIE] Plugin Library installer'
    $icon = Install-ShortcutIcon
    if ($icon) {
        $shortcut.IconLocation = "$icon,0"
    } else {
        $shortcut.IconLocation = ((Join-Path $env:SystemRoot 'System32\imageres.dll') + ',109')
    }
    $shortcut.Save()
}

function Update-ExistingShortcutIcon {
    if (-not (Test-DesktopShortcut)) {
        return
    }
    $icon = Install-ShortcutIcon
    if (-not $icon) {
        return
    }
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut((Get-DesktopShortcutPath))
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Save()
}

function Remove-DesktopShortcut {
    $path = Get-DesktopShortcutPath
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Update-ShortcutLink($link) {
    if ($null -eq $link) { return }
    if (Test-DesktopShortcut) {
        $link.Text = 'Remove desktop shortcut'
        $link.ForeColor = $script:ColorMuted
    } else {
        $link.Text = 'Add desktop shortcut'
        $link.ForeColor = $script:ColorAccent
    }
}

function Remove-LibraryJars([string[]] $jarNames) {
    $removed = @()
    foreach ($jarName in $jarNames) {
        foreach ($path in (Get-InstalledJarPaths $jarName)) {
            [System.IO.File]::Delete($path)
            if (Test-Path -LiteralPath $path) {
                throw "Could not delete $path. Close the client and try again."
            }
            $removed += $path
        }
    }
    return @($removed)
}

function Install-Library([string[]] $jarNames) {
    if (Test-ClientRunning) {
        throw 'Close the game client first so the old plugin files can be deleted.'
    }
    if ($jarNames.Count -eq 0) {
        throw 'Select at least one plugin.'
    }
    $missing = @()
    foreach ($jarName in $jarNames) {
        $source = Join-Path $DistDir $jarName
        if (-not (Test-Path -LiteralPath $source)) { $missing += $jarName }
    }
    if ($missing.Count -gt 0) {
        throw ("Missing jar(s) in dist: " + ($missing -join ', '))
    }

    $removed = @(Remove-LibraryJars $jarNames)
    if (-not (Test-Path -LiteralPath $script:InstallDir)) {
        New-Item -ItemType Directory -Path $script:InstallDir | Out-Null
    }
    $installed = @()
    foreach ($jarName in $jarNames) {
        $source = Join-Path $DistDir $jarName
        $dest = Join-Path $script:InstallDir $jarName
        [System.IO.File]::Copy($source, $dest, $true)
        $installed += $dest
    }
    return @{
        Removed = $removed
        Installed = $installed
    }
}

function Uninstall-Library([string[]] $jarNames) {
    if (Test-ClientRunning) {
        throw 'Close the game client first so the plugin files can be deleted.'
    }
    if ($jarNames.Count -eq 0) {
        throw 'Select at least one plugin.'
    }
    return @(Remove-LibraryJars $jarNames)
}

function Get-CheckedJarNames($form) {
    $names = New-Object System.Collections.Generic.List[string]
    $cards = $form.Tag['Cards']
    if ($null -eq $cards) { return @() }
    foreach ($card in $cards) {
        if ($card.Tag.Checked -and $card.Tag.Available) {
            [void] $names.Add($card.Tag.JarName)
        }
    }
    return $names.ToArray()
}

function Write-Log($box, [string] $message) {
    if ($null -eq $box) { return }
    $box.AppendText(("[{0}]  {1}{2}" -f (Get-Date -Format 'HH:mm:ss'), $message, [Environment]::NewLine))
}

function Set-ControlBuffered($control) {
    [void] $control.GetType().InvokeMember(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]'NonPublic, Instance, SetProperty',
        $null,
        $control,
        @($true))
}

function New-RoundedPath([System.Drawing.Rectangle] $bounds, [int] $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    $path.AddArc($bounds.X, $bounds.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($bounds.Right - $diameter), $bounds.Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($bounds.Right - $diameter), ($bounds.Bottom - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($bounds.X, ($bounds.Bottom - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-SetupButton([string] $text, [string] $kind) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Size = New-Object System.Drawing.Size(148, 40)
    $button.FlatStyle = 'Flat'
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $button.FlatAppearance.BorderSize = 0
    if ($kind -eq 'primary') {
        $button.BackColor = $script:ColorAccent
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(255, 84, 74)
        $button.FlatAppearance.MouseDownBackColor = $script:ColorAccentDark
    } elseif ($kind -eq 'danger') {
        $button.BackColor = $script:ColorCard
        $button.ForeColor = $script:ColorText
        $button.FlatAppearance.BorderSize = 1
        $button.FlatAppearance.BorderColor = $script:ColorCardEdge
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(44, 46, 54)
        $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(28, 29, 34)
    } else {
        $button.Size = New-Object System.Drawing.Size(96, 40)
        $button.BackColor = $script:ColorBg
        $button.ForeColor = $script:ColorMuted
        $button.FlatAppearance.MouseOverBackColor = $script:ColorCard
        $button.FlatAppearance.MouseDownBackColor = $script:ColorCard
    }
    return $button
}

function Add-CardToggle($control, $card) {
    $control.Cursor = [System.Windows.Forms.Cursors]::Hand
    $control.Add_Click({
        if (-not $card.Tag.Available) { return }
        $card.Tag.Checked = -not $card.Tag.Checked
        $card.Invalidate()
        $owner = $card.FindForm()
        if ($null -ne $owner) {
            Update-PluginCardStatus $owner
        }
    }.GetNewClosure())
}

function Build-PluginCards($form) {
    $list = $form.Tag.List
    $cards = $form.Tag.Cards
    $list.Controls.Clear()
    $cards.Clear()
    $names = @(Get-LibraryJarNames)
    $y = 4
    $cardWidth = 688
    foreach ($jarName in $names) {
        $source = Join-Path $DistDir $jarName
        $available = Test-Path -LiteralPath $source
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(8, $y)
        $card.Size = New-Object System.Drawing.Size($cardWidth, 84)
        $card.BackColor = $script:ColorCard
        $card.Cursor = [System.Windows.Forms.Cursors]::Hand
        $card.Tag = @{
            JarName = $jarName
            Checked = [bool] $available
            Available = [bool] $available
            AvailableVersion = (Get-AvailablePluginVersion $jarName)
            HasUpdate = $false
        }
        Set-ControlBuffered $card
        $card.Add_Paint({
            param($sender, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $bounds = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
            $path = New-RoundedPath $bounds 10
            $fill = New-Object System.Drawing.SolidBrush $script:ColorCard
            $g.FillPath($fill, $path)
            $edgeColor = $script:ColorCardEdge
            if ($sender.Tag.Checked) { $edgeColor = $script:ColorAccent }
            $pen = New-Object System.Drawing.Pen $edgeColor
            $g.DrawPath($pen, $path)
            $box = New-Object System.Drawing.Rectangle(18, 30, 22, 22)
            $boxPath = New-RoundedPath $box 5
            if ($sender.Tag.Checked) {
                $checkBrush = New-Object System.Drawing.SolidBrush $script:ColorAccent
                $g.FillPath($checkBrush, $boxPath)
                $checkBrush.Dispose()
                $mark = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
                $g.DrawLine($mark, 23, 41, 28, 46)
                $g.DrawLine($mark, 28, 46, 36, 35)
                $mark.Dispose()
            } else {
                $empty = New-Object System.Drawing.Pen $script:ColorMuted
                $g.DrawPath($empty, $boxPath)
                $empty.Dispose()
            }
            $path.Dispose()
            $fill.Dispose()
            $pen.Dispose()
            $boxPath.Dispose()
        })
        $card.Add_Click({
            param($sender, $e)
            if (-not $sender.Tag.Available) { return }
            $sender.Tag.Checked = -not $sender.Tag.Checked
            $sender.Invalidate()
            $owner = $sender.FindForm()
            if ($null -ne $owner) {
                Update-PluginCardStatus $owner
            }
        })

        $name = New-Object System.Windows.Forms.Label
        $name.Text = Get-PluginLabel $jarName
        $name.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
        $name.ForeColor = $script:ColorText
        $name.BackColor = $script:ColorCard
        $name.AutoSize = $true
        $name.Location = New-Object System.Drawing.Point(56, 16)
        Add-CardToggle $name $card

        $detail = New-Object System.Windows.Forms.Label
        $detail.Name = 'detail'
        $blurb = $script:PluginBlurbs[$jarName]
        if (-not $blurb) { $blurb = 'Library plugin' }
        if ($available) {
            $file = Get-Item -LiteralPath $source
            $detail.Text = "$blurb   $(Format-Stamp $file)"
        } else {
            $detail.Text = "$blurb   Missing from dist"
            $name.ForeColor = $script:ColorMuted
        }
        $detail.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $detail.ForeColor = $script:ColorMuted
        $detail.BackColor = $script:ColorCard
        $detail.AutoSize = $false
        $detail.Size = New-Object System.Drawing.Size(460, 22)
        $detail.Location = New-Object System.Drawing.Point(56, 44)
        Add-CardToggle $detail $card

        $status = New-Object System.Windows.Forms.Label
        $status.Name = 'status'
        $status.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $status.BackColor = $script:ColorCard
        $status.AutoSize = $true
        $status.TextAlign = 'MiddleRight'
        Add-CardToggle $status $card

        $card.Controls.AddRange(@($name, $detail, $status))
        $list.Controls.Add($card)
        [void] $cards.Add($card)
        $y += 94
    }
    if ($names.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = "No plugins listed.`r`n$LibraryFile"
        $empty.ForeColor = $script:ColorMuted
        $empty.BackColor = $script:ColorBg
        $empty.AutoSize = $false
        $empty.Size = New-Object System.Drawing.Size(640, 48)
        $empty.Location = New-Object System.Drawing.Point(12, 12)
        $list.Controls.Add($empty)
    }
}

function Update-PluginCardStatus($form) {
    $cards = $form.Tag['Cards']
    if ($null -eq $cards) { return }
    $updateCount = 0
    $updateLabels = New-Object System.Collections.Generic.List[string]
    foreach ($card in $cards) {
        $status = $card.Controls['status']
        $detail = $card.Controls['detail']
        if ($null -eq $status) { continue }
        $jarName = $card.Tag.JarName
        $blurb = $script:PluginBlurbs[$jarName]
        if (-not $blurb) { $blurb = 'Library plugin' }
        $availableVersion = $card.Tag.AvailableVersion
        $needsUpdate = $false
        if (-not $card.Tag.Available) {
            $status.Text = 'Missing'
            $status.ForeColor = $script:ColorWarning
            if ($null -ne $detail) { $detail.Text = "$blurb   Missing from dist" }
        } elseif (Test-PluginNeedsUpdate $jarName) {
            $needsUpdate = $true
            $updateCount += 1
            [void] $updateLabels.Add((Get-PluginLabel $jarName))
            $status.Text = 'Update available'
            $status.ForeColor = $script:ColorWarning
            $installedVersion = Get-InstalledPluginVersion $jarName $availableVersion
            if ($installedVersion -and $availableVersion -and ($installedVersion -ne $availableVersion)) {
                if ($null -ne $detail) { $detail.Text = "$blurb   $installedVersion  ->  $availableVersion" }
            } elseif ($availableVersion) {
                if ($null -ne $detail) { $detail.Text = "$blurb   Newer copy available (latest $availableVersion)" }
            } else {
                if ($null -ne $detail) { $detail.Text = "$blurb   Newer copy available" }
            }
        } elseif ((Get-InstalledCopy $jarName).Count -gt 0) {
            $status.Text = 'Installed'
            $status.ForeColor = $script:ColorInstalled
            if ($null -ne $detail) {
                if ($availableVersion) {
                    $detail.Text = "$blurb   v$availableVersion"
                } else {
                    $source = Join-Path $DistDir $jarName
                    $file = Get-Item -LiteralPath $source
                    $detail.Text = "$blurb   $(Format-Stamp $file)"
                }
            }
        } else {
            $status.Text = 'Not installed'
            $status.ForeColor = $script:ColorMuted
            if ($null -ne $detail) {
                $source = Join-Path $DistDir $jarName
                $file = Get-Item -LiteralPath $source
                if ($availableVersion) {
                    $detail.Text = "$blurb   v$availableVersion   $(Format-Stamp $file)"
                } else {
                    $detail.Text = "$blurb   $(Format-Stamp $file)"
                }
            }
        }
        $card.Tag.HasUpdate = $needsUpdate
        $status.Location = New-Object System.Drawing.Point(($card.Width - $status.Width - 18), 32)
    }
    $checked = @(Get-CheckedJarNames $form)
    $form.Tag.InstallButton.Enabled = $checked.Count -gt 0
    $form.Tag.UninstallButton.Enabled = $checked.Count -gt 0
    if ($null -ne $form.Tag.UpdateLink) {
        if ($updateCount -gt 0) {
            $form.Tag.UpdateLink.ForeColor = $script:ColorAccent
            $form.Tag.UpdateLink.Cursor = [System.Windows.Forms.Cursors]::Hand
        } else {
            $form.Tag.UpdateLink.ForeColor = $script:ColorMuted
            $form.Tag.UpdateLink.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    }
    if (Test-ClientRunning) {
        $form.Tag.Warning.Text = 'The game client is running. Close it before Install or Uninstall.'
    } elseif ($updateCount -eq 1) {
        $form.Tag.Warning.Text = "$($updateLabels[0]) has an update."
    } elseif ($updateCount -gt 1) {
        $names = $updateLabels.ToArray() -join ', '
        $form.Tag.Warning.Text = "$updateCount plugins have updates: $names."
    } else {
        $form.Tag.Warning.Text = ''
    }
}

function Invoke-InstallPlugins($form, $log, [string[]] $names) {
    if ($names.Count -eq 0) { return $false }
    if (Test-ClientRunning) {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            'Close the game client first so the old plugin files can be deleted.',
            'Client is running',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    try {
        $hadUpdates = @($names | Where-Object { Test-PluginNeedsUpdate $_ }).Count -gt 0
        $result = Install-Library $names
        foreach ($path in $result.Removed) { Write-Log $log "Removed old copy: $path" }
        foreach ($path in $result.Installed) { Write-Log $log "Installed: $path" }
        Write-Log $log 'Restart the client, then enable the [OPIE] plugins you want.'
        $title = if ($hadUpdates) { 'Installed / updated' } else { 'Installed' }
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Installed or updated $($result.Installed.Count) plugin(s).`r`n`r`nRestart the client before using them.",
            $title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $true
    } catch {
        Write-Log $log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            $_.Exception.Message,
            'Install failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    } finally {
        Update-PluginCardStatus $form
    }
}

function New-LibraryForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '[OPIE] Plugin Library'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(760, 680)
    $form.BackColor = $script:ColorBg
    $form.ForeColor = $script:ColorText
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.ShowInTaskbar = $true
    $iconPath = Get-InstallerIconSource
    if (Test-Path -LiteralPath $iconPath) {
        $form.Icon = New-Object System.Drawing.Icon $iconPath
    }
    Set-ControlBuffered $form

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(760, 112)
    $header.BackColor = $script:ColorBg
    $header.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $badge = New-Object System.Drawing.Rectangle(28, 28, 58, 26)
        $path = New-RoundedPath $badge 6
        $brush = New-Object System.Drawing.SolidBrush $script:ColorAccent
        $e.Graphics.FillPath($brush, $path)
        $path.Dispose()
        $brush.Dispose()
        $font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
        $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $e.Graphics.DrawString('OPIE', $font, $textBrush, 40, 32)
        $font.Dispose()
        $textBrush.Dispose()
        $line = New-Object System.Drawing.Pen $script:ColorCardEdge
        $e.Graphics.DrawLine($line, 0, 111, 760, 111)
        $line.Dispose()
    })

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Plugin Library'
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 20)
    $title.ForeColor = $script:ColorText
    $title.BackColor = $script:ColorBg
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(100, 22)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = 'Check the plugins you want. Outdated installs are marked so you can update them here.'
    $subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $subtitle.ForeColor = $script:ColorMuted
    $subtitle.BackColor = $script:ColorBg
    $subtitle.AutoSize = $false
    $subtitle.Size = New-Object System.Drawing.Size(620, 24)
    $subtitle.Location = New-Object System.Drawing.Point(102, 62)

    $selectAll = New-Object System.Windows.Forms.Label
    $selectAll.Text = 'Select all'
    $selectAll.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $selectAll.ForeColor = $script:ColorAccent
    $selectAll.BackColor = $script:ColorBg
    $selectAll.AutoSize = $true
    $selectAll.Cursor = [System.Windows.Forms.Cursors]::Hand
    $selectAll.Location = New-Object System.Drawing.Point(28, 128)

    $clearSelection = New-Object System.Windows.Forms.Label
    $clearSelection.Text = 'Clear'
    $clearSelection.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $clearSelection.ForeColor = $script:ColorMuted
    $clearSelection.BackColor = $script:ColorBg
    $clearSelection.AutoSize = $true
    $clearSelection.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clearSelection.Location = New-Object System.Drawing.Point(108, 128)

    $updateOutdated = New-Object System.Windows.Forms.Label
    $updateOutdated.Text = 'Update outdated'
    $updateOutdated.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $updateOutdated.ForeColor = $script:ColorMuted
    $updateOutdated.BackColor = $script:ColorBg
    $updateOutdated.AutoSize = $true
    $updateOutdated.Cursor = [System.Windows.Forms.Cursors]::Default
    $updateOutdated.Location = New-Object System.Drawing.Point(160, 128)

    $list = New-Object System.Windows.Forms.Panel
    $list.Location = New-Object System.Drawing.Point(20, 160)
    $list.Size = New-Object System.Drawing.Size(720, 292)
    $list.BackColor = $script:ColorBg
    $list.AutoScroll = $true
    Set-ControlBuffered $list

    $warning = New-Object System.Windows.Forms.Label
    $warning.AutoSize = $false
    $warning.Size = New-Object System.Drawing.Size(704, 22)
    $warning.Location = New-Object System.Drawing.Point(28, 460)
    $warning.ForeColor = $script:ColorWarning
    $warning.BackColor = $script:ColorBg
    $warning.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $logCaption = New-Object System.Windows.Forms.Label
    $logCaption.Text = 'Activity'
    $logCaption.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $logCaption.ForeColor = $script:ColorMuted
    $logCaption.BackColor = $script:ColorBg
    $logCaption.AutoSize = $true
    $logCaption.Location = New-Object System.Drawing.Point(28, 486)

    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $log.BorderStyle = 'None'
    $log.BackColor = $script:ColorLog
    $log.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 216)
    $log.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $log.Location = New-Object System.Drawing.Point(28, 510)
    $log.Size = New-Object System.Drawing.Size(704, 92)

    $shortcutLink = New-Object System.Windows.Forms.Label
    $shortcutLink.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $shortcutLink.BackColor = $script:ColorBg
    $shortcutLink.AutoSize = $true
    $shortcutLink.Cursor = [System.Windows.Forms.Cursors]::Hand
    $shortcutLink.Location = New-Object System.Drawing.Point(28, 630)
    Update-ShortcutLink $shortcutLink

    $installButton = New-SetupButton 'Install / Update' 'primary'
    $installButton.Size = New-Object System.Drawing.Size(158, 40)
    $installButton.Location = New-Object System.Drawing.Point(320, 620)

    $uninstallButton = New-SetupButton 'Uninstall selected' 'danger'
    $uninstallButton.Location = New-Object System.Drawing.Point(486, 620)

    $closeButton = New-SetupButton 'Close' 'quiet'
    $closeButton.Location = New-Object System.Drawing.Point(642, 620)
    $closeButton.Add_Click({ $form.Close() }.GetNewClosure())

    $cards = New-Object System.Collections.Generic.List[object]
    $form.Tag = @{
        Cards = $cards
        List = $list
        InstallButton = $installButton
        UninstallButton = $uninstallButton
        UpdateLink = $updateOutdated
        ShortcutLink = $shortcutLink
        Warning = $warning
    }

    $selectAll.Add_Click({
        foreach ($card in $form.Tag['Cards']) {
            if ($card.Tag.Available) { $card.Tag.Checked = $true }
            $card.Invalidate()
        }
        Update-PluginCardStatus $form
    }.GetNewClosure())

    $clearSelection.Add_Click({
        foreach ($card in $form.Tag['Cards']) {
            $card.Tag.Checked = $false
            $card.Invalidate()
        }
        Update-PluginCardStatus $form
    }.GetNewClosure())

    $updateOutdated.Add_Click({
        Update-PluginCardStatus $form
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($card in $form.Tag['Cards']) {
            $hasUpdate = [bool] $card.Tag.HasUpdate
            $card.Tag.Checked = $hasUpdate
            $card.Invalidate()
            if ($hasUpdate) { [void] $names.Add($card.Tag.JarName) }
        }
        Update-PluginCardStatus $form
        if ($names.Count -eq 0) {
            Write-Log $log 'No installed plugins have updates.'
            return
        }
        [void] (Invoke-InstallPlugins $form $log $names.ToArray())
    }.GetNewClosure())

    $shortcutLink.Add_Click({
        try {
            if (Test-DesktopShortcut) {
                Remove-DesktopShortcut
                Write-Log $log 'Removed the desktop shortcut.'
            } else {
                Add-DesktopShortcut
                Write-Log $log 'Added a desktop shortcut. It opens the latest installer.'
            }
        } catch {
            Write-Log $log $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                $_.Exception.Message,
                'Desktop shortcut failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        Update-ShortcutLink $shortcutLink
    }.GetNewClosure())

    $installButton.Add_Click({
        Update-PluginCardStatus $form
        $names = @(Get-CheckedJarNames $form)
        if ($names.Count -eq 0) { return }
        [void] (Invoke-InstallPlugins $form $log $names)
    }.GetNewClosure())

    $uninstallButton.Add_Click({
        Update-PluginCardStatus $form
        if (Test-ClientRunning) {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                'Close the game client first so the plugin files can be deleted.',
                'Client is running',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        try {
            $names = @(Get-CheckedJarNames $form)
            $present = @($names | Where-Object { (Get-InstalledCopy $_).Count -gt 0 })
            if ($present.Count -eq 0) {
                Write-Log $log 'None of the selected plugins are installed.'
                [System.Windows.Forms.MessageBox]::Show(
                    $form,
                    'None of the selected plugins are installed.',
                    'Already uninstalled',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                return
            }
            $removed = @(Uninstall-Library $names)
            foreach ($path in $removed) { Write-Log $log "Uninstalled: $path" }
            Write-Log $log 'Other plugins were left in place.'
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Uninstalled $($removed.Count) file(s). Other plugins were left in place.",
                'Uninstalled',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            Write-Log $log $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                $_.Exception.Message,
                'Uninstall failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        Update-PluginCardStatus $form
    }.GetNewClosure())

    $header.Controls.AddRange(@($title, $subtitle))
    $form.Controls.AddRange(@(
        $header, $selectAll, $clearSelection, $updateOutdated, $list, $warning, $logCaption, $log,
        $shortcutLink, $installButton, $uninstallButton, $closeButton
    ))

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1500
    $timer.Add_Tick({ Update-PluginCardStatus $form }.GetNewClosure())
    $form.Add_Shown({
        Build-PluginCards $form
        Update-PluginCardStatus $form
        if (Test-DesktopShortcut) {
            Update-ExistingShortcutIcon
        }
        Update-ShortcutLink $shortcutLink
        Write-Log $log 'Check the plugins you want, then install or update. Unchecked plugins are left alone.'
        if (Test-DesktopShortcut) {
            Write-Log $log 'Desktop shortcut is present. Click Remove desktop shortcut to delete it.'
        } else {
            Write-Log $log 'Add a desktop shortcut if you want to open this installer later.'
        }
        $updateNames = @()
        foreach ($card in $form.Tag['Cards']) {
            if ($card.Tag.HasUpdate) { $updateNames += (Get-PluginLabel $card.Tag.JarName) }
        }
        if ($updateNames.Count -eq 1) {
            Write-Log $log "$($updateNames[0]) has an update. Use Update outdated or Install / Update."
        } elseif ($updateNames.Count -gt 1) {
            Write-Log $log (("$($updateNames.Count) plugins have updates: " + ($updateNames -join ', ')) + '.')
        }
        $timer.Start()
    }.GetNewClosure())
    $null = $form.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
        if ($null -ne $form.Icon) { $form.Icon.Dispose() }
    }.GetNewClosure())

    return $form
}

function Hide-SetupConsole {
    $hwnd = [OpieSetupWindow]::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        [void] [OpieSetupWindow]::ShowWindow($hwnd, 0)
    }
}

function Show-LibrarySetup {
    Hide-SetupConsole
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        [System.Windows.Forms.MessageBox]::Show(
            $e.Exception.Message,
            'Plugin Library setup failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    })
    try {
        $form = New-LibraryForm
        [void] $form.ShowDialog()
        $form.Dispose()
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Plugin Library setup failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Show-LibrarySetup
}
