<#
.SYNOPSIS
    Background hotkey listener for Win + Shift + K with Tray Icon and Status Balloon.
    Launches start-all.bat when pressed.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class HotKeyForm : Form {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int HOTKEY_ID = 8821;
    private const uint MOD_SHIFT = 0x0004;
    private const uint MOD_WIN = 0x0008;
    private const uint VK_K = 0x4B;

    private string scriptPath;
    private NotifyIcon trayIcon;

    public HotKeyForm(string script) {
        this.scriptPath = script;
        this.WindowState = FormWindowState.Minimized;
        this.ShowInTaskbar = false;

        this.trayIcon = new NotifyIcon();
        this.trayIcon.Icon = SystemIcons.Application;
        this.trayIcon.Text = "ChatAPP Hotkey (Win+Shift+K)";
        this.trayIcon.Visible = true;

        bool success = RegisterHotKey(this.Handle, HOTKEY_ID, MOD_WIN | MOD_SHIFT, VK_K);
        if (!success) {
            int err = Marshal.GetLastWin32Error();
            Console.WriteLine("[ERROR] Could not register Win+Shift+K. Win32 error: " + err);
        } else {
            Console.WriteLine("[READY] Win+Shift+K hotkey registered successfully.");
        }
    }

    protected override void WndProc(ref Message m) {
        const int WM_HOTKEY = 0x0312;
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID) {
            try {
                this.trayIcon.ShowBalloonTip(3000, "ChatAPP Starting", "Win + Shift + K pressed! Starting backend, socket, and devices...", ToolTipIcon.Info);

                ProcessStartInfo psi = new ProcessStartInfo {
                    FileName = "cmd.exe",
                    Arguments = "/c start \"\" \"" + scriptPath + "\"",
                    UseShellExecute = true,
                    CreateNoWindow = true
                };
                Process.Start(psi);
            } catch (Exception ex) {
                Console.WriteLine("[ERROR] Failed to run: " + ex.Message);
            }
        }
        base.WndProc(ref m);
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        if (this.trayIcon != null) {
            this.trayIcon.Visible = false;
            this.trayIcon.Dispose();
        }
        base.OnFormClosing(e);
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms, System.Drawing
$target = Join-Path $PSScriptRoot "start-all.bat"
$form = New-Object HotKeyForm($target)

# Run message loop
[System.Windows.Forms.Application]::Run($form)
