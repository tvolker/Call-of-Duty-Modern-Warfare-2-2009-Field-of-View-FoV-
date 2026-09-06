$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ExpectedHash = "3F307EA47940F63936FA41F01ED4A6DEB93493CFD4BF98FBC896A017083B69FA"

# Exact RVAs for the user's verified x64 iw4mp.exe.
$FovPointerRva     = [Int64]0x6BAFF8
$FovCurrentOffset  = [Int64]0x10

$ChannelCountRva   = [Int64]0x651A680
$ChannelTableRva   = [Int64]0x6519178
$StateBaseRva      = [Int64]0x65183E4
$ActiveStatePtrRva = [Int64]0x6518FF8

$ChannelRecordSize = [Int64]0x50
$StateBlockSize    = [Int64]0x304
$StateEntrySize    = [Int64]0x0C
$BlockCount        = 4

$MusicTargets = @(
    @{ Index = 13; Name = "menu" },
    @{ Index = 32; Name = "music" },
    @{ Index = 33; Name = "musicnopause" }
)

Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class MW2UtilityMemory
{
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ReadProcessMemory(
        IntPtr h, IntPtr address, [Out] byte[] buffer,
        UIntPtr size, out UIntPtr read);

    [DllImport("kernel32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool WriteProcessMemory(
        IntPtr h, IntPtr address, byte[] buffer,
        UIntPtr size, out UIntPtr written);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr h);

    public static IntPtr Open(int pid)
    {
        const uint VM_OPERATION = 0x0008;
        const uint VM_READ      = 0x0010;
        const uint VM_WRITE     = 0x0020;
        const uint QUERY        = 0x0400;

        IntPtr h = OpenProcess(VM_OPERATION | VM_READ | VM_WRITE | QUERY, false, pid);

        if (h == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess failed");

        return h;
    }

    public static byte[] ReadBytes(IntPtr h, long address, int count)
    {
        byte[] buffer = new byte[count];
        UIntPtr got;

        bool ok = ReadProcessMemory(
            h,
            new IntPtr(address),
            buffer,
            new UIntPtr((uint)count),
            out got);

        if (!ok || got.ToUInt64() != (ulong)count)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "ReadProcessMemory failed at 0x" + address.ToString("X"));

        return buffer;
    }

    public static long ReadInt64(IntPtr h, long address)
    {
        return BitConverter.ToInt64(ReadBytes(h, address, 8), 0);
    }

    public static int ReadInt32(IntPtr h, long address)
    {
        return BitConverter.ToInt32(ReadBytes(h, address, 4), 0);
    }

    public static float ReadFloat(IntPtr h, long address)
    {
        return BitConverter.ToSingle(ReadBytes(h, address, 4), 0);
    }

    public static string ReadAscii(IntPtr h, long address, int max)
    {
        byte[] b = ReadBytes(h, address, max);
        int n = Array.IndexOf<byte>(b, 0);
        if (n < 0) n = b.Length;
        return Encoding.ASCII.GetString(b, 0, n);
    }

    public static void WriteFloat(IntPtr h, long address, float value)
    {
        WriteBytes(h, address, BitConverter.GetBytes(value));
    }

    public static void WriteBytes(IntPtr h, long address, byte[] buffer)
    {
        UIntPtr wrote;

        bool ok = WriteProcessMemory(
            h,
            new IntPtr(address),
            buffer,
            new UIntPtr((uint)buffer.Length),
            out wrote);

        if (!ok || wrote.ToUInt64() != (ulong)buffer.Length)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "WriteProcessMemory failed at 0x" + address.ToString("X"));
    }

    public static void Close(IntPtr h)
    {
        if (h != IntPtr.Zero)
            CloseHandle(h);
    }
}
"@

# -------------------------
# Runtime state
# -------------------------
$script:GameProcess = $null
$script:GameHandle = [IntPtr]::Zero
$script:ModuleBase = [Int64]0
$script:ConnectedPid = 0
$script:LastDiscovery = [DateTime]::MinValue
$script:UserStopped = $false

$script:FovOriginal = $null
$script:FovLastWritten = $null
$script:FovPtr = [Int64]0
$script:FovWrote = $false

$script:MusicSaved = @{}
$script:MusicCaptured = $false
$script:MusicWrote = $false

$script:Zero12 = New-Object byte[] 12

# -------------------------
# UI
# -------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "MW2 Utility"
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size(470, 300)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Modern Warfare 2 (2009) Utility"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(18, 16)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "FoV + menu/in-game music control for your verified x64 iw4mp.exe"
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(20, 46)
$form.Controls.Add($subtitle)

$groupFov = New-Object System.Windows.Forms.GroupBox
$groupFov.Text = "Field of View"
$groupFov.Location = New-Object System.Drawing.Point(18, 78)
$groupFov.Size = New-Object System.Drawing.Size(210, 105)
$form.Controls.Add($groupFov)

$chkFov = New-Object System.Windows.Forms.CheckBox
$chkFov.Text = "Maintain FoV"
$chkFov.Checked = $true
$chkFov.AutoSize = $true
$chkFov.Location = New-Object System.Drawing.Point(15, 25)
$groupFov.Controls.Add($chkFov)

$numFov = New-Object System.Windows.Forms.NumericUpDown
$numFov.Minimum = 65
$numFov.Maximum = 90
$numFov.Value = 90
$numFov.DecimalPlaces = 0
$numFov.Location = New-Object System.Drawing.Point(15, 57)
$numFov.Size = New-Object System.Drawing.Size(70, 25)
$groupFov.Controls.Add($numFov)

$lblFovRange = New-Object System.Windows.Forms.Label
$lblFovRange.Text = "65 - 90"
$lblFovRange.AutoSize = $true
$lblFovRange.Location = New-Object System.Drawing.Point(95, 60)
$groupFov.Controls.Add($lblFovRange)

$groupAudio = New-Object System.Windows.Forms.GroupBox
$groupAudio.Text = "Audio"
$groupAudio.Location = New-Object System.Drawing.Point(242, 78)
$groupAudio.Size = New-Object System.Drawing.Size(210, 105)
$form.Controls.Add($groupAudio)

$chkMusic = New-Object System.Windows.Forms.CheckBox
$chkMusic.Text = "Disable all music"
$chkMusic.Checked = $true
$chkMusic.AutoSize = $true
$chkMusic.Location = New-Object System.Drawing.Point(15, 25)
$groupAudio.Controls.Add($chkMusic)

$lblMusic = New-Object System.Windows.Forms.Label
$lblMusic.Text = "Menu + in-game music`r`nOther game audio remains enabled."
$lblMusic.AutoSize = $true
$lblMusic.Location = New-Object System.Drawing.Point(15, 51)
$groupAudio.Controls.Add($lblMusic)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Connect / Apply"
$btnApply.Location = New-Object System.Drawing.Point(18, 198)
$btnApply.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($btnApply)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore && Stop"
$btnRestore.Location = New-Object System.Drawing.Point(158, 198)
$btnRestore.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($btnRestore)

$btnReconnect = New-Object System.Windows.Forms.Button
$btnReconnect.Text = "Resume Auto-Connect"
$btnReconnect.Location = New-Object System.Drawing.Point(298, 198)
$btnReconnect.Size = New-Object System.Drawing.Size(154, 32)
$btnReconnect.Enabled = $false
$form.Controls.Add($btnReconnect)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Starting..."
$status.BorderStyle = "Fixed3D"
$status.Location = New-Object System.Drawing.Point(18, 244)
$status.Size = New-Object System.Drawing.Size(434, 38)
$status.TextAlign = "MiddleLeft"
$form.Controls.Add($status)

$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($chkMusic, "Mutes verified channels 13 (menu), 32 (music), and 33 (musicnopause).")
$tip.SetToolTip($chkFov, "Maintains the selected cg_fov value while MW2 is running.")

function Set-Status([string]$text)
{
    if ($status.Text -ne $text)
    {
        $status.Text = $text
    }
}

function Clear-ConnectionState
{
    if ($script:GameHandle -ne [IntPtr]::Zero)
    {
        try { [MW2UtilityMemory]::Close($script:GameHandle) } catch {}
    }

    $script:GameHandle = [IntPtr]::Zero
    $script:GameProcess = $null
    $script:ModuleBase = [Int64]0
    $script:ConnectedPid = 0

    $script:FovOriginal = $null
    $script:FovLastWritten = $null
    $script:FovPtr = [Int64]0
    $script:FovWrote = $false

    $script:MusicSaved = @{}
    $script:MusicCaptured = $false
    $script:MusicWrote = $false
}

function Game-IsAlive
{
    if ($null -eq $script:GameProcess -or $script:GameHandle -eq [IntPtr]::Zero)
    {
        return $false
    }

    try
    {
        $script:GameProcess.Refresh()
        return (-not $script:GameProcess.HasExited)
    }
    catch
    {
        return $false
    }
}

function Validate-MusicChannels
{
    $count = [MW2UtilityMemory]::ReadInt32(
        $script:GameHandle,
        $script:ModuleBase + $ChannelCountRva)

    if ($count -le 33)
    {
        throw "Sound channel table is not initialized yet."
    }

    foreach ($target in $MusicTargets)
    {
        $idx = [int]$target.Index
        $expected = [string]$target.Name

        $record =
            $script:ModuleBase +
            $ChannelTableRva +
            ([Int64]$idx * $ChannelRecordSize)

        $actual = [MW2UtilityMemory]::ReadAscii(
            $script:GameHandle,
            $record,
            64)

        if ($actual -ne $expected)
        {
            throw "Sound-channel validation failed at index $idx."
        }
    }
}

function Validate-Fov
{
    $ptr = [MW2UtilityMemory]::ReadInt64(
        $script:GameHandle,
        $script:ModuleBase + $FovPointerRva)

    if ($ptr -eq 0)
    {
        throw "cg_fov is not initialized yet."
    }

    $namePtr = [MW2UtilityMemory]::ReadInt64($script:GameHandle, $ptr)

    if ($namePtr -eq 0)
    {
        throw "cg_fov name pointer is not initialized."
    }

    $name = [MW2UtilityMemory]::ReadAscii(
        $script:GameHandle,
        $namePtr,
        16)

    if ($name -ne "cg_fov")
    {
        throw "FoV runtime validation failed."
    }

    $value = [MW2UtilityMemory]::ReadFloat(
        $script:GameHandle,
        $ptr + $FovCurrentOffset)

    if ([Single]::IsNaN($value) -or [Single]::IsInfinity($value) -or
        $value -lt 40.0 -or $value -gt 140.0)
    {
        throw "Unexpected cg_fov value."
    }

    return @($ptr, $value)
}

function Try-Connect
{
    if ($script:UserStopped)
    {
        return $false
    }

    $procs = @(Get-Process -Name "iw4mp" -ErrorAction SilentlyContinue)

    if ($procs.Count -eq 0)
    {
        Set-Status "Waiting for MW2 Multiplayer..."
        return $false
    }

    if ($procs.Count -ne 1)
    {
        Set-Status "Multiple iw4mp.exe processes found. Close the extras."
        return $false
    }

    $p = $procs[0]

    try
    {
        $exePath = $p.MainModule.FileName
        $base = [Int64]$p.MainModule.BaseAddress.ToInt64()
        $hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    catch
    {
        Set-Status "Cannot inspect MW2. Run both programs under the same Windows user."
        return $false
    }

    if ($hash -ne $ExpectedHash)
    {
        Set-Status "Unsupported iw4mp.exe build. No memory changes made."
        return $false
    }

    try
    {
        $h = [MW2UtilityMemory]::Open($p.Id)

        $script:GameProcess = $p
        $script:GameHandle = $h
        $script:ModuleBase = $base
        $script:ConnectedPid = $p.Id

        Validate-MusicChannels
        [void](Validate-Fov)

        Set-Status "MW2 connected. Applying selected settings..."
        return $true
    }
    catch
    {
        Clear-ConnectionState
        Set-Status ("MW2 found; waiting for game initialization...")
        return $false
    }
}

function Capture-MusicValues
{
    if ($script:MusicCaptured)
    {
        return
    }

    $script:MusicSaved = @{}
    $stateBase = $script:ModuleBase + $StateBaseRva

    foreach ($target in $MusicTargets)
    {
        $idx = [int]$target.Index
        $rows = @()

        for ($b = 0; $b -lt $BlockCount; $b++)
        {
            $entry =
                $stateBase +
                ([Int64]$b * $StateBlockSize) +
                ([Int64]$idx * $StateEntrySize)

            $rows += ,([MW2UtilityMemory]::ReadBytes(
                $script:GameHandle,
                $entry,
                12))
        }

        $script:MusicSaved[$idx] = $rows
    }

    $script:MusicCaptured = $true
}

function Apply-MusicMute
{
    if (-not $chkMusic.Checked)
    {
        return
    }

    Capture-MusicValues

    $stateBase = $script:ModuleBase + $StateBaseRva

    foreach ($target in $MusicTargets)
    {
        $idx = [int]$target.Index

        for ($b = 0; $b -lt $BlockCount; $b++)
        {
            $entry =
                $stateBase +
                ([Int64]$b * $StateBlockSize) +
                ([Int64]$idx * $StateEntrySize)

            [MW2UtilityMemory]::WriteBytes(
                $script:GameHandle,
                $entry,
                $script:Zero12)
        }
    }

    $script:MusicWrote = $true
}

function Restore-Music
{
    if (-not $script:MusicCaptured -or -not (Game-IsAlive))
    {
        $script:MusicSaved = @{}
        $script:MusicCaptured = $false
        $script:MusicWrote = $false
        return
    }

    $stateBase = $script:ModuleBase + $StateBaseRva

    try
    {
        foreach ($target in $MusicTargets)
        {
            $idx = [int]$target.Index

            if ($script:MusicSaved.ContainsKey($idx))
            {
                $rows = $script:MusicSaved[$idx]

                for ($b = 0; $b -lt $BlockCount; $b++)
                {
                    $entry =
                        $stateBase +
                        ([Int64]$b * $StateBlockSize) +
                        ([Int64]$idx * $StateEntrySize)

                    [MW2UtilityMemory]::WriteBytes(
                        $script:GameHandle,
                        $entry,
                        [byte[]]$rows[$b])
                }
            }
        }
    }
    catch {}

    $script:MusicSaved = @{}
    $script:MusicCaptured = $false
    $script:MusicWrote = $false
}

function Apply-Fov
{
    if (-not $chkFov.Checked)
    {
        return
    }

    $result = Validate-Fov
    $ptr = [Int64]$result[0]
    $current = [single]$result[1]
    $desired = [single]$numFov.Value

    if ($null -eq $script:FovOriginal -or $script:FovPtr -ne $ptr)
    {
        $script:FovOriginal = $current
        $script:FovPtr = $ptr
        $script:FovWrote = $false
    }

    if ([Math]::Abs($current - $desired) -gt 0.001)
    {
        [MW2UtilityMemory]::WriteFloat(
            $script:GameHandle,
            $ptr + $FovCurrentOffset,
            $desired)

        $check = [MW2UtilityMemory]::ReadFloat(
            $script:GameHandle,
            $ptr + $FovCurrentOffset)

        if ([Math]::Abs($check - $desired) -gt 0.001)
        {
            throw "FoV write did not validate."
        }

        $script:FovLastWritten = $desired
        $script:FovWrote = $true
    }
}

function Restore-Fov
{
    if ($null -eq $script:FovOriginal -or
        $script:FovPtr -eq 0 -or
        -not $script:FovWrote -or
        -not (Game-IsAlive))
    {
        $script:FovOriginal = $null
        $script:FovPtr = [Int64]0
        $script:FovWrote = $false
        return
    }

    try
    {
        $current = [MW2UtilityMemory]::ReadFloat(
            $script:GameHandle,
            $script:FovPtr + $FovCurrentOffset)

        # Same safety behavior as the working FoV tool:
        # only restore if the value is still the one this utility wrote.
        if ($null -ne $script:FovLastWritten -and
            [Math]::Abs($current - [single]$script:FovLastWritten) -lt 0.001)
        {
            [MW2UtilityMemory]::WriteFloat(
                $script:GameHandle,
                $script:FovPtr + $FovCurrentOffset,
                [single]$script:FovOriginal)
        }
    }
    catch {}

    $script:FovOriginal = $null
    $script:FovLastWritten = $null
    $script:FovPtr = [Int64]0
    $script:FovWrote = $false
}

function Restore-All
{
    if (Game-IsAlive)
    {
        Restore-Music
        Restore-Fov
    }

    Clear-ConnectionState
}

function Update-ConnectedStatus
{
    $fovText = if ($chkFov.Checked) { "FoV $([int]$numFov.Value)" } else { "FoV off" }
    $musicText = if ($chkMusic.Checked) { "Music muted" } else { "Music on" }

    Set-Status ("Connected  |  " + $fovText + "  |  " + $musicText)
}

$btnApply.Add_Click({
    $script:UserStopped = $false
    $btnReconnect.Enabled = $false

    if (-not (Game-IsAlive))
    {
        Clear-ConnectionState
        [void](Try-Connect)
    }

    if (Game-IsAlive)
    {
        try
        {
            if ($chkMusic.Checked) { Apply-MusicMute }
            if ($chkFov.Checked) { Apply-Fov }
            Update-ConnectedStatus
        }
        catch
        {
            Set-Status ("Apply failed: " + $_.Exception.Message)
        }
    }
})

$btnRestore.Add_Click({
    Restore-All
    $script:UserStopped = $true
    $btnReconnect.Enabled = $true
    Set-Status "Stopped. Original values restored where safely possible."
})

$btnReconnect.Add_Click({
    $script:UserStopped = $false
    $btnReconnect.Enabled = $false
    Set-Status "Auto-connect resumed. Waiting for MW2..."
})

$chkMusic.Add_CheckedChanged({
    if (Game-IsAlive)
    {
        if ($chkMusic.Checked)
        {
            try
            {
                Capture-MusicValues
                Apply-MusicMute
                Update-ConnectedStatus
            }
            catch
            {
                Set-Status ("Music control failed: " + $_.Exception.Message)
            }
        }
        else
        {
            Restore-Music
            Update-ConnectedStatus
        }
    }
})

$chkFov.Add_CheckedChanged({
    if (Game-IsAlive)
    {
        if ($chkFov.Checked)
        {
            try
            {
                Apply-Fov
                Update-ConnectedStatus
            }
            catch
            {
                Set-Status ("FoV control failed: " + $_.Exception.Message)
            }
        }
        else
        {
            Restore-Fov
            Update-ConnectedStatus
        }
    }
})

$numFov.Add_ValueChanged({
    if (Game-IsAlive -and $chkFov.Checked)
    {
        try
        {
            Apply-Fov
            Update-ConnectedStatus
        }
        catch
        {
            Set-Status ("FoV control failed: " + $_.Exception.Message)
        }
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50

$timer.Add_Tick({
    try
    {
        if (Game-IsAlive)
        {
            if ($chkFov.Checked)
            {
                Apply-Fov
            }

            if ($chkMusic.Checked)
            {
                Apply-MusicMute
            }

            Update-ConnectedStatus
            return
        }

        if ($script:ConnectedPid -ne 0)
        {
            Clear-ConnectionState
            Set-Status "MW2 closed. Waiting to reconnect automatically..."
        }

        if ($script:UserStopped)
        {
            return
        }

        $now = Get-Date

        if (($now - $script:LastDiscovery).TotalMilliseconds -ge 900)
        {
            $script:LastDiscovery = $now
            [void](Try-Connect)
        }
    }
    catch
    {
        # Stop touching this process on any runtime validation/memory error,
        # then allow a clean reconnect.
        Clear-ConnectionState

        if (-not $script:UserStopped)
        {
            Set-Status ("Connection reset: " + $_.Exception.Message)
        }
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    try { Restore-All } catch {}
})

$timer.Start()
Set-Status "Waiting for MW2 Multiplayer... Auto-connect is enabled."

[void]$form.ShowDialog()
