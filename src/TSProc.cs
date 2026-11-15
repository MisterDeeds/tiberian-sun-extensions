// Tiberian Sun Extensions - access to the running game (32-bit): read and write memory with
// "verify, then patch", find the game's windows, take window pictures, send clicks and keys.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

namespace TSExt
{
    public sealed class GameProcess : IDisposable
    {
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr written);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualProtectEx(IntPtr h, IntPtr addr, UIntPtr size, uint prot, out uint old);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool FlushInstructionCache(IntPtr h, IntPtr addr, UIntPtr size);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAllocEx(IntPtr h, IntPtr addr, UIntPtr size, uint type, uint prot);

        const uint PROCESS_ALL = 0x0438 | 0x0010 | 0x0020 | 0x0008 | 0x0400; // VM_READ|VM_WRITE|VM_OPERATION|QUERY
        public readonly Process Proc;
        readonly IntPtr handle;

        public GameProcess(Process p)
        {
            Proc = p;
            handle = OpenProcess(PROCESS_ALL, false, p.Id);
            if (handle == IntPtr.Zero) throw new InvalidOperationException("OpenProcess failed: " + Marshal.GetLastWin32Error());
        }

        public bool HasExited { get { try { return Proc.HasExited; } catch { return true; } } }

        public byte[] Read(uint addr, int len)
        {
            byte[] b = new byte[len];
            IntPtr got;
            if (!ReadProcessMemory(handle, new IntPtr(addr), b, len, out got) || got.ToInt32() != len)
                throw new InvalidOperationException(string.Format("ReadProcessMemory 0x{0:X8} ({1}) failed: {2}", addr, len, Marshal.GetLastWin32Error()));
            return b;
        }

        public bool TryRead(uint addr, int len, out byte[] b)
        {
            b = new byte[len];
            IntPtr got;
            return ReadProcessMemory(handle, new IntPtr(addr), b, len, out got) && got.ToInt32() == len;
        }

        public int ReadInt(uint addr) { return BitConverter.ToInt32(Read(addr, 4), 0); }
        public uint ReadUInt(uint addr) { return BitConverter.ToUInt32(Read(addr, 4), 0); }
        public double ReadDouble(uint addr) { return BitConverter.ToDouble(Read(addr, 8), 0); }
        public byte ReadByte(uint addr) { return Read(addr, 1)[0]; }

        public string ReadString(uint addr, int max)
        {
            byte[] b = Read(addr, max);
            int n = Array.IndexOf(b, (byte)0);
            if (n < 0) n = max;
            return Encoding.GetEncoding(1252).GetString(b, 0, n);
        }

        public void Write(uint addr, byte[] data)
        {
            uint old;
            bool prot = VirtualProtectEx(handle, new IntPtr(addr), new UIntPtr((uint)data.Length), 0x40, out old);
            IntPtr w;
            bool ok = WriteProcessMemory(handle, new IntPtr(addr), data, data.Length, out w);
            int err = Marshal.GetLastWin32Error();
            if (prot) { uint dummy; VirtualProtectEx(handle, new IntPtr(addr), new UIntPtr((uint)data.Length), old, out dummy); }
            FlushInstructionCache(handle, new IntPtr(addr), new UIntPtr((uint)data.Length));
            if (!ok || w.ToInt32() != data.Length) throw new InvalidOperationException(string.Format("WriteProcessMemory 0x{0:X8} failed: {1}", addr, err));
        }

        public void WriteInt(uint addr, int v) { Write(addr, BitConverter.GetBytes(v)); }
        public void WriteDouble(uint addr, double v) { Write(addr, BitConverter.GetBytes(v)); }

        // Writes only if the current bytes are the expected original (or already the new) bytes.
        // Returns "patched", "already" or "mismatch".
        public string VerifyPatch(uint addr, byte[] expected, byte[] patch)
        {
            byte[] cur = Read(addr, expected.Length);
            if (Same(cur, patch)) return "already";
            if (!Same(cur, expected)) return "mismatch";
            Write(addr, patch);
            return "patched";
        }

        // Replaces the instructions at 'at' (exactly 'expected' bytes, at least 5) by a jump to new code
        // ('cave', written to fresh memory), which ends with a jump back behind the replaced bytes.
        // Returns "patched", "already" (a jump is there already) or "mismatch" (unknown bytes - nothing done).
        public string InstallHook(uint at, byte[] expected, byte[] cave)
        {
            byte[] cur = Read(at, expected.Length);
            if (cur[0] == 0xE9 && !Same(cur, expected)) return "already";
            if (!Same(cur, expected)) return "mismatch";
            uint mem = Alloc(cave.Length + 16);
            byte[] code = new byte[cave.Length + 5];
            Array.Copy(cave, code, cave.Length);
            uint back = at + (uint)expected.Length;
            code[cave.Length] = 0xE9;
            BitConverter.GetBytes((int)(back - (mem + (uint)cave.Length + 5))).CopyTo(code, cave.Length + 1);
            Write(mem, code);
            byte[] jmp = new byte[expected.Length];
            for (int i = 0; i < jmp.Length; i++) jmp[i] = 0x90;
            jmp[0] = 0xE9;
            BitConverter.GetBytes((int)(mem - (at + 5))).CopyTo(jmp, 1);
            Write(at, jmp);
            return "patched";
        }

        public uint Alloc(int size)
        {
            IntPtr p = VirtualAllocEx(handle, IntPtr.Zero, new UIntPtr((uint)size), 0x3000, 0x40);
            if (p == IntPtr.Zero) throw new InvalidOperationException("VirtualAllocEx failed: " + Marshal.GetLastWin32Error());
            return (uint)p.ToInt64();
        }

        public static bool Same(byte[] a, byte[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }

        public void Dispose() { CloseHandle(handle); }

        // --- for analysis: where is a thread of the (32-bit) game right now? ---
        [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, int tid);
        [DllImport("kernel32.dll")] static extern uint SuspendThread(IntPtr h);
        [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr h);
        [DllImport("kernel32.dll")] static extern bool Wow64GetThreadContext(IntPtr h, byte[] ctx);

        public int StackBytes = 64;

        // Returns EIP and ESP of each thread (WOW64 context: ContextFlags at 0, Esp at 0xC4, Eip at 0xB8).
        public List<string> SampleThreads()
        {
            List<string> r = new List<string>();
            Proc.Refresh();
            foreach (ProcessThread t in Proc.Threads)
            {
                IntPtr h = OpenThread(0x0002 | 0x0008 | 0x0040, false, t.Id); // SUSPEND_RESUME | GET_CONTEXT | QUERY_INFORMATION
                if (h == IntPtr.Zero) continue;
                try
                {
                    SuspendThread(h);
                    byte[] ctx = new byte[716];
                    BitConverter.GetBytes(0x10001 | 0x10002).CopyTo(ctx, 0); // CONTEXT_i386 | CONTROL | INTEGER
                    if (Wow64GetThreadContext(h, ctx))
                    {
                        uint eip = BitConverter.ToUInt32(ctx, 0xB8), esp = BitConverter.ToUInt32(ctx, 0xC4), ebp = BitConverter.ToUInt32(ctx, 0xB4);
                        string stack = "";
                        byte[] st;
                        if (TryRead(esp, StackBytes, out st)) for (int i = 0; i < StackBytes / 4; i++) { uint v = BitConverter.ToUInt32(st, i * 4); if (v >= 0x401000 && v < 0x6CA000) stack += string.Format(" {0:X}", v); }
                        r.Add(string.Format("tid {0} eip {1:X8} esp {2:X8} ebp {3:X8} cpu {4:0}ms ret:{5}", t.Id, eip, esp, ebp, t.TotalProcessorTime.TotalMilliseconds, stack));
                    }
                    ResumeThread(h);
                }
                finally { CloseHandle(h); }
            }
            return r;
        }
    }

    public static class Win
    {
        public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int pid);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int GetWindowTextA(IntPtr hwnd, StringBuilder sb, int max);
        [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int GetClassNameA(IntPtr hwnd, StringBuilder sb, int max);
        [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dlg, int id);
        [DllImport("user32.dll")] public static extern bool PostMessageA(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern IntPtr SendMessageA(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
        [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hwnd, out RECT r);
        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
        [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();

        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

        public static uint IdleMilliseconds()
        {
            LASTINPUTINFO li = new LASTINPUTINFO();
            li.cbSize = (uint)Marshal.SizeOf(li);
            if (!GetLastInputInfo(ref li)) return 0;
            return (uint)Environment.TickCount - li.dwTime;
        }

        public static List<IntPtr> TopWindows(int pid)
        {
            List<IntPtr> r = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                int p; GetWindowThreadProcessId(h, out p);
                if (p == pid) r.Add(h);
                return true;
            }, IntPtr.Zero);
            return r;
        }

        public static List<IntPtr> Children(IntPtr parent)
        {
            List<IntPtr> r = new List<IntPtr>();
            EnumChildWindows(parent, delegate(IntPtr h, IntPtr l) { r.Add(h); return true; }, IntPtr.Zero);
            return r;
        }

        public static string Text(IntPtr h) { StringBuilder sb = new StringBuilder(512); GetWindowTextA(h, sb, 512); return sb.ToString(); }
        public static string ClassName(IntPtr h) { StringBuilder sb = new StringBuilder(256); GetClassNameA(h, sb, 256); return sb.ToString(); }

        public static string Describe(IntPtr h)
        {
            RECT r; GetWindowRect(h, out r);
            return string.Format("0x{0:X} id={1} class={2} vis={3} rect={4},{5},{6},{7} text={8}", h.ToInt64(), GetDlgCtrlID(h), ClassName(h),
                IsWindowVisible(h), r.Left, r.Top, r.Right, r.Bottom, Text(h));
        }

        public static Bitmap Capture(IntPtr hwnd)
        {
            RECT r; GetWindowRect(hwnd, out r);
            int w = Math.Max(1, r.Right - r.Left), hgt = Math.Max(1, r.Bottom - r.Top);
            Bitmap bmp = new Bitmap(w, hgt, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                IntPtr hdc = g.GetHdc();
                bool ok = PrintWindow(hwnd, hdc, 2);
                g.ReleaseHdc(hdc);
                if (!ok) { g.CopyFromScreen(r.Left, r.Top, 0, 0, new Size(w, hgt)); }
            }
            return bmp;
        }

        public static Bitmap CaptureScreenRect(int x, int y, int w, int h)
        {
            Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp)) g.CopyFromScreen(x, y, 0, 0, new Size(w, h));
            return bmp;
        }

        public static void Click(IntPtr hwnd, int x, int y)
        {
            IntPtr lp = new IntPtr((y << 16) | (x & 0xFFFF));
            PostMessageA(hwnd, 0x0200, IntPtr.Zero, lp);      // WM_MOUSEMOVE
            PostMessageA(hwnd, 0x0201, new IntPtr(1), lp);    // WM_LBUTTONDOWN
            PostMessageA(hwnd, 0x0202, IntPtr.Zero, lp);      // WM_LBUTTONUP
        }

        public static void Key(IntPtr hwnd, int vk)
        {
            PostMessageA(hwnd, 0x0100, new IntPtr(vk), new IntPtr(1));
            PostMessageA(hwnd, 0x0101, new IntPtr(vk), new IntPtr(unchecked((int)0xC0000001)));
        }

        [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);

        // Brings a (possibly minimized) window to the front. Uses the ALT trick so Windows allows the focus change.
        public static void Focus(IntPtr hwnd)
        {
            if (IsIconic(hwnd)) ShowWindow(hwnd, 9);   // SW_RESTORE
            keybd_event(0x12, 0, 0, UIntPtr.Zero);       // ALT down/up unlocks SetForegroundWindow
            keybd_event(0x12, 0, 2, UIntPtr.Zero);
            SetForegroundWindow(hwnd);
        }

        // Real mouse click at a screen position (for tests; the game reads the real mouse, not window messages).
        public static void RealClick(int x, int y, bool right)
        {
            SetCursorPos(x, y);
            System.Threading.Thread.Sleep(120);
            mouse_event(right ? 0x0008u : 0x0002u, 0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(80);
            mouse_event(right ? 0x0010u : 0x0004u, 0, 0, 0, UIntPtr.Zero);
        }

        public static void RealKey(byte vk)
        {
            keybd_event(vk, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(60);
            keybd_event(vk, 0, 2, UIntPtr.Zero);
        }

        // Clicks a dialog button the way the dialog itself would see it (WM_COMMAND, BN_CLICKED).
        public static void Command(IntPtr dlg, int id)
        {
            IntPtr ctl = GetDlgItem(dlg, id);
            PostMessageA(dlg, 0x0111, new IntPtr(id), ctl);
        }
    }
}
