# [OPIE] Plugin Library setup window.
# Install copies the checked plugins. Uninstall removes only the checked plugins.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    $found = @()
    foreach ($path in (Get-InstalledJarPaths $jarName)) {
        $found += Get-Item -LiteralPath $path
    }
    return @($found)
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
    return $paths
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
    foreach ($card in $cards) {
        $status = $card.Controls['status']
        if ($null -eq $status) { continue }
        if (-not $card.Tag.Available) {
            $status.Text = 'Missing'
            $status.ForeColor = $script:ColorWarning
        } elseif (@(Get-InstalledCopy $card.Tag.JarName).Count -gt 0) {
            $status.Text = 'Installed'
            $status.ForeColor = $script:ColorInstalled
        } else {
            $status.Text = 'Not installed'
            $status.ForeColor = $script:ColorMuted
        }
        $status.Location = New-Object System.Drawing.Point(($card.Width - $status.Width - 18), 32)
    }
    $checked = @(Get-CheckedJarNames $form)
    $form.Tag.InstallButton.Enabled = $checked.Count -gt 0
    $form.Tag.UninstallButton.Enabled = $checked.Count -gt 0
    if (Test-ClientRunning) {
        $form.Tag.Warning.Text = 'The game client is running. Close it before Install or Uninstall.'
    } else {
        $form.Tag.Warning.Text = ''
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
    $subtitle.Text = 'Check the plugins you want. Unchecked plugins stay as they are.'
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

    $installButton = New-SetupButton 'Install selected' 'primary'
    $installButton.Location = New-Object System.Drawing.Point(336, 620)

    $uninstallButton = New-SetupButton 'Uninstall selected' 'danger'
    $uninstallButton.Location = New-Object System.Drawing.Point(492, 620)

    $closeButton = New-SetupButton 'Close' 'quiet'
    $closeButton.Location = New-Object System.Drawing.Point(636, 620)
    $closeButton.Add_Click({ $form.Close() }.GetNewClosure())

    $cards = New-Object System.Collections.Generic.List[object]
    $form.Tag = @{
        Cards = $cards
        List = $list
        InstallButton = $installButton
        UninstallButton = $uninstallButton
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

    $installButton.Add_Click({
        Update-PluginCardStatus $form
        $names = @(Get-CheckedJarNames $form)
        if ($names.Count -eq 0) { return }
        if (Test-ClientRunning) {
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                'Close the game client first so the old plugin files can be deleted.',
                'Client is running',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        try {
            $result = Install-Library $names
            foreach ($path in $result.Removed) { Write-Log $log "Removed old copy: $path" }
            foreach ($path in $result.Installed) { Write-Log $log "Installed: $path" }
            Write-Log $log 'Restart the client, then enable the [OPIE] plugins you want.'
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Installed $($result.Installed.Count) plugin(s).`r`n`r`nRestart the client before using them.",
                'Installed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } catch {
            Write-Log $log $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                $_.Exception.Message,
                'Install failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        Update-PluginCardStatus $form
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
            $present = @($names | Where-Object { @(Get-InstalledCopy $_).Count -gt 0 })
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
        $header, $selectAll, $clearSelection, $list, $warning, $logCaption, $log,
        $installButton, $uninstallButton, $closeButton
    ))

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1500
    $timer.Add_Tick({ Update-PluginCardStatus $form }.GetNewClosure())
    $form.Add_Shown({
        Build-PluginCards $form
        Update-PluginCardStatus $form
        Write-Log $log 'Check the plugins you want, then install. Unchecked plugins are left alone.'
        $timer.Start()
    }.GetNewClosure())
    $null = $form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() }.GetNewClosure())

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
