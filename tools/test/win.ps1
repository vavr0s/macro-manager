# Helpers for the test copy (MMTest.exe): move the main window, click, press keys, screen-capture its windows.
#   win.ps1 move X Y [Title]      win.ps1 click X Y [-Double]      win.ps1 key VK      win.ps1 cap OUT.png
param([string]$Cmd, $A, $B, [string]$C = 'ComboCrown', [switch]$Double)
Add-Type -AssemblyName System.Drawing, Microsoft.VisualBasic
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class TW {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static List<RECT> Of(uint[] pids) {
    var res = new List<RECT>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p);
      if (Array.IndexOf(pids, p) >= 0 && IsWindowVisible(h)) { RECT r; DwmGetWindowAttribute(h, 9, out r, 16);
        if (r.R - r.L > 50 && r.B - r.T > 50) res.Add(r); } return true; }, IntPtr.Zero);
    return res;
  }
}
'@
$tp = (Get-CimInstance Win32_Process -Filter "Name='MMTest.exe'" | Select -First 1).ProcessId
function Front { if ($tp) { try { [Microsoft.VisualBasic.Interaction]::AppActivate([int]$tp) } catch {}; Start-Sleep -Milliseconds 300 } }
switch ($Cmd) {
  'move' { $h = [TW]::FindWindow('AutoHotkeyGUI', $C); [void][TW]::SetWindowPos($h, [IntPtr]::Zero, [int]$A, [int]$B, 0, 0, 0x15) }
  'click' {
    Front; [void][TW]::SetCursorPos([int]$A, [int]$B); Start-Sleep -Milliseconds 120
    1..($(if ($Double) { 2 } else { 1 })) | % { [TW]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40; [TW]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60 }
  }
  'key' { [TW]::keybd_event([byte][int]$A, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [TW]::keybd_event([byte][int]$A, 0, 2, [UIntPtr]::Zero) }
  'cap' {
    Front
    $rs = [TW]::Of([uint32[]]@(Get-CimInstance Win32_Process -Filter "Name='MMTest.exe'" | % { [uint32]$_.ProcessId }))
    $minX = ($rs | % { $_.L } | Measure -Minimum).Minimum; $minY = ($rs | % { $_.T } | Measure -Minimum).Minimum
    $maxX = ($rs | % { $_.R } | Measure -Maximum).Maximum; $maxY = ($rs | % { $_.B } | Measure -Maximum).Maximum
    $bmp = [Drawing.Bitmap]::new([int]($maxX - $minX), [int]($maxY - $minY)); $g = [Drawing.Graphics]::FromImage($bmp)
    foreach ($r in $rs) { $g.CopyFromScreen($r.L, $r.T, $r.L - $minX, $r.T - $minY, [Drawing.Size]::new($r.R - $r.L, $r.B - $r.T)); "{0},{1} {2}x{3}" -f $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T) }
    $g.Dispose(); $bmp.Save($A, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  }
}
