using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace AsideCleanLogo {
 public static class Native {
  delegate bool EnumProc(IntPtr h,IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback,IntPtr p);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
  public static uint WindowProcessId(IntPtr window) {uint pid;GetWindowThreadProcessId(window,out pid);return pid;}
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int count);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr instance,string file,uint type,int cx,int cy,uint flags);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
  [DllImport("user32.dll")] static extern IntPtr CopyIcon(IntPtr icon);
  [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern uint ExtractIconEx(string file,int index,IntPtr[] large,IntPtr[] small,uint count);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h,uint msg,IntPtr w,IntPtr l,uint flags,uint timeout,out IntPtr result);
  [DllImport("shell32.dll",CharSet=CharSet.Unicode)] public static extern void SHChangeNotify(uint ev,uint flags,string item1,string item2);
  [DllImport("user32.dll")] static extern IntPtr GetClassLongPtr(IntPtr h,int index);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool MoveFileEx(string oldPath,string newPath,uint flags);
  public static IntPtr GetIcon(IntPtr h,int type) {IntPtr result;SendMessageTimeout(h,0x7F,(IntPtr)type,IntPtr.Zero,2,500,out result);return result;}
  public static bool SetIcon(IntPtr h,int type,IntPtr icon) {IntPtr result;if(SendMessageTimeout(h,0x7F,(IntPtr)type,IntPtr.Zero,2,500,out result)!=IntPtr.Zero&&result==icon)return true;return SendMessageTimeout(h,0x80,(IntPtr)type,icon,2,500,out result)!=IntPtr.Zero && GetIcon(h,type)==icon;}
  public static List<IntPtr> Windows(string exe) {
   var pids=new HashSet<uint>();
   foreach(var p in Process.GetProcessesByName("Aside"))try {if(String.Equals(p.MainModule.FileName,exe,StringComparison.OrdinalIgnoreCase))pids.Add((uint)p.Id);}catch {}finally {p.Dispose();}
   var result=new List<IntPtr>();
   EnumWindows(delegate(IntPtr h,IntPtr unused) {uint pid;GetWindowThreadProcessId(h,out pid);if(pids.Contains(pid)){var text=new StringBuilder(256);GetClassName(h,text,256);if(text.ToString().StartsWith("Chrome_WidgetWin",StringComparison.Ordinal))result.Add(h);}return true;},IntPtr.Zero);
   return result;
  }
  public static void Notify(string[] paths) {
   var directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(string path in paths){SHChangeNotify(0x2000,0x1005,path,null);directories.Add(Path.GetDirectoryName(path));}
   foreach(string dir in directories)SHChangeNotify(0x1000,0x1005,dir,null);
   SHChangeNotify(0x8000000,0,null,null);
  }
  public static void ValidateShellIcon(string icon) {
   IntPtr[] large=new IntPtr[1],small=new IntPtr[1];
   uint result=ExtractIconEx(icon,0,large,small,1);
   try {if(result!=1||large[0]==IntPtr.Zero||small[0]==IntPtr.Zero)throw new InvalidOperationException("Windows Shell cannot extract icon: "+icon);}
   finally {if(large[0]!=IntPtr.Zero)DestroyIcon(large[0]);if(small[0]!=IntPtr.Zero)DestroyIcon(small[0]);}
  }
  public static void RestoreFromExecutable(string exe) {
   // Class icons belong to Aside, so their handles remain valid after the uninstaller exits.
   var failed=new List<IntPtr>();
   foreach(var h in Windows(exe)) {if(!SetIcon(h,0,GetClassLongPtr(h,-34))||!SetIcon(h,1,GetClassLongPtr(h,-14)))failed.Add(h);}
   if(failed.Count>0)throw new InvalidOperationException("Unable to restore running Aside window icons: "+String.Join(",",failed));
  }
 }
}
