using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ChatAppLauncher
{
    static class Program
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public POINT pt;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll")]
        private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage([In] ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage([In] ref MSG lpmsg);

        [DllImport("user32.dll")]
        private static extern void PostQuitMessage(int nExitCode);

        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_ALT = 0x0001;
        private const uint MOD_CONTROL = 0x0002;
        private const uint MOD_SHIFT = 0x0004;
        private const uint MOD_WIN = 0x0008;
        private const uint VK_K = 0x4B;

        private static NotifyIcon trayIcon;
        private static string scriptPath;
        private static string logPath;

        private static void Log(string message)
        {
            try
            {
                string line = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message + Environment.NewLine;
                File.AppendAllText(logPath, line);
            }
            catch { }
        }

        private static void TriggerLauncher()
        {
            try
            {
                if (trayIcon != null)
                {
                    trayIcon.ShowBalloonTip(2000, "ChatAPP Starting", "Launching backend, socket, and devices...", ToolTipIcon.Info);
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "cmd.exe";
                psi.Arguments = "/c start \"\" \"" + scriptPath + "\"";
                psi.WorkingDirectory = Path.GetDirectoryName(scriptPath);
                psi.UseShellExecute = true;
                psi.CreateNoWindow = true;
                Process.Start(psi);
                Log("Launched start-all.bat successfully.");
            }
            catch (Exception ex)
            {
                Log("Launch error: " + ex.Message);
            }
        }

        [STAThread]
        static void Main()
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            scriptPath = Path.Combine(appDir, "start-all.bat");
            logPath = Path.Combine(appDir, "hotkey.log");

            AppDomain.CurrentDomain.UnhandledException += delegate(object sender, UnhandledExceptionEventArgs e) {
                Log("FATAL UNHANDLED: " + (e.ExceptionObject != null ? e.ExceptionObject.ToString() : "null"));
            };

            try
            {
                Log("Starting ChatAPP HotKey Service (Win32 Thread Loop)...");

                bool regWinShiftK = RegisterHotKey(IntPtr.Zero, 1, MOD_WIN | MOD_SHIFT, VK_K);
                bool regCtrlShiftK = RegisterHotKey(IntPtr.Zero, 2, MOD_CONTROL | MOD_SHIFT, VK_K);
                bool regCtrlAltK = RegisterHotKey(IntPtr.Zero, 3, MOD_CONTROL | MOD_ALT, VK_K);

                Log("Register Win+Shift+K: " + regWinShiftK);
                Log("Register Ctrl+Shift+K: " + regCtrlShiftK);
                Log("Register Ctrl+Alt+K: " + regCtrlAltK);

                ContextMenu menu = new ContextMenu();
                menu.MenuItems.Add("▶ Run ChatAPP Now", delegate { TriggerLauncher(); });
                menu.MenuItems.Add("-");
                menu.MenuItems.Add("Exit Hotkey Service", delegate {
                    Log("Exiting service by user request.");
                    UnregisterHotKey(IntPtr.Zero, 1);
                    UnregisterHotKey(IntPtr.Zero, 2);
                    UnregisterHotKey(IntPtr.Zero, 3);
                    if (trayIcon != null) { trayIcon.Visible = false; trayIcon.Dispose(); }
                    PostQuitMessage(0);
                });

                trayIcon = new NotifyIcon();
                trayIcon.Icon = SystemIcons.Application;
                trayIcon.Text = "ChatAPP HotKey (Win+Shift+K)";
                trayIcon.ContextMenu = menu;
                trayIcon.Visible = true;
                trayIcon.DoubleClick += delegate { TriggerLauncher(); };

                trayIcon.ShowBalloonTip(3000, "ChatAPP Ready", "Press Win+Shift+K (or Ctrl+Shift+K) to launch ChatAPP.", ToolTipIcon.Info);
                Log("Entering GetMessage loop...");

                MSG msg;
                int ret;
                while ((ret = GetMessage(out msg, IntPtr.Zero, 0, 0)) != 0)
                {
                    if (ret == -1)
                    {
                        Log("GetMessage error: " + Marshal.GetLastWin32Error());
                        break;
                    }
                    if (msg.message == WM_HOTKEY)
                    {
                        Log("WM_HOTKEY received! (ID: " + msg.wParam.ToString() + ")");
                        TriggerLauncher();
                    }
                    TranslateMessage(ref msg);
                    DispatchMessage(ref msg);
                }

                Log("Loop exited normally. Ret: " + ret);
            }
            catch (Exception ex)
            {
                Log("CATCH ERROR in Main: " + ex.ToString());
            }
            finally
            {
                Log("Process reached end of Main.");
            }
        }
    }
}
