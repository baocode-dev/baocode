param(
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
  [switch]$NoForce,
  [switch]$ListOnly,
  [string[]]$Resources = @()
)

$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $ProcessId
if ($process.Path -ne [IO.Path]::GetFullPath($ExpectedExecutable)) {
  throw 'Process executable does not match the explicitly selected test app'
}

# Register only this process, never the executable as a shared file resource.
Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

public static class BaoRestartManagerSmoke {
  [StructLayout(LayoutKind.Sequential)]
  public struct UniqueProcess {
    public uint Pid;
    public FILETIME Started;
  }

  public delegate void Progress(uint percent);

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct ProcessInfo {
    public UniqueProcess Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string Service;
    public uint Type;
    public uint Status;
    public uint Session;
    [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
  }

  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool GetProcessTimes(IntPtr process, out FILETIME creation,
    out FILETIME exit, out FILETIME kernel, out FILETIME user);

  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  static extern uint RmStartSession(out uint session, uint flags,
    StringBuilder key);

  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  static extern uint RmRegisterResources(uint session, uint fileCount,
    string[] files, uint processCount, UniqueProcess[] processes,
    uint serviceCount, string[] services);

  [DllImport("rstrtmgr.dll")]
  static extern uint RmShutdown(uint session, uint flags, Progress progress);

  [DllImport("rstrtmgr.dll")]
  static extern uint RmGetList(uint session, out uint needed,
    ref uint count, [In, Out] ProcessInfo[] processes, ref uint rebootReasons);

  [DllImport("rstrtmgr.dll")]
  static extern uint RmEndSession(uint session);

  public static void Run(int pid, bool force, bool listOnly, string[] files) {
    if (files.Length != 0 && !listOnly)
      throw new Exception("File-resource tests are read-only to protect other apps");
    using (var process = Process.GetProcessById(pid)) {
      FILETIME started, exit, kernel, user;
      if (!GetProcessTimes(process.Handle, out started, out exit,
        out kernel, out user)) throw new Exception("GetProcessTimes failed");
      uint session;
      uint result = RmStartSession(out session, 0, new StringBuilder(33));
      if (result != 0) throw new Exception("RmStartSession: " + result);
      try {
        var selected = new UniqueProcess { Pid = (uint)pid, Started = started };
        result = files.Length == 0
          ? RmRegisterResources(session, 0, null, 1, new[] { selected }, 0, null)
          : RmRegisterResources(session, (uint)files.Length, files, 0, null, 0, null);
        if (result != 0) throw new Exception("RmRegisterResources: " + result);
        uint needed, count = 0, reasons = 0;
        result = RmGetList(session, out needed, ref count, null, ref reasons);
        if (result == 234) {
          count = needed;
          var apps = new ProcessInfo[count];
          result = RmGetList(session, out needed, ref count, apps, ref reasons);
          if (result != 0) throw new Exception("RmGetList: " + result);
          for (int i = 0; i < count; i++)
            Console.WriteLine("RM_APP pid=" + apps[i].Process.Pid +
              " name=" + apps[i].Name + " type=" + apps[i].Type);
        } else if (result != 0) throw new Exception("RmGetList: " + result);
        if (listOnly) return;
        var watch = Stopwatch.StartNew();
        result = RmShutdown(session, force ? 1U : 0U,
          percent => Console.WriteLine("RM_PROGRESS=" + percent));
        Console.WriteLine("RM_RESULT=" + result);
        Console.WriteLine("RM_SHUTDOWN_MS=" + watch.ElapsedMilliseconds);
        bool ended = process.WaitForExit(5000);
        Console.WriteLine("PROCESS_EXITED=" + ended);
        if (ended) Console.WriteLine("PROCESS_EXIT_CODE=" + process.ExitCode);
        if (result != 0 || !ended) throw new Exception("Restart Manager shutdown failed");
      } finally {
        RmEndSession(session);
      }
    }
  }
}
"@

[BaoRestartManagerSmoke]::Run($ProcessId, -not $NoForce, $ListOnly, $Resources)
