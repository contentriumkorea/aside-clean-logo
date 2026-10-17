using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.Web.Script.Serialization;
namespace AsideCleanLogo {
 public class WindowStore {
  public class Backup {public long Window;public int Pid;public long Start;public string AppId;public string Command;public string Original;public string Applied;public List<string> AppliedIcons=new List<string>();}
  readonly string file,exe;readonly List<Backup> entries;readonly JavaScriptSerializer json=new JavaScriptSerializer();
  public WindowStore(string state,string exe){this.exe=exe;file=Path.Combine(state,"windows.json");entries=File.Exists(file)?json.Deserialize<List<Backup>>(File.ReadAllText(file)):new List<Backup>();}
  bool ProcessIdentity(Backup b) {
   IntPtr h=(IntPtr)b.Window;if(Native.WindowProcessId(h)!=(uint)b.Pid)return false;
   try {using(var p=Process.GetProcessById(b.Pid))return p.StartTime.ToUniversalTime().Ticks==b.Start&&String.Equals(p.MainModule.FileName,exe,StringComparison.OrdinalIgnoreCase);}
   catch(ArgumentException){return false;}
  }
  bool Identity(Backup b) {return ProcessIdentity(b)&&WindowProperties.Get((IntPtr)b.Window,5)==b.AppId&&WindowProperties.Get((IntPtr)b.Window,2)==b.Command;}
  static bool Owned(Backup b,string icon) {return !String.IsNullOrEmpty(icon)&&(icon==b.Applied||b.AppliedIcons.Contains(icon));}
  void Save() {entries.RemoveAll(b=>!Identity(b));Directory.CreateDirectory(Path.GetDirectoryName(file));string temp=file+".tmp";File.WriteAllText(temp,json.Serialize(entries));if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);}
  public bool Apply(IntPtr window,string icon) {
   string appId=WindowProperties.Get(window,5);if(String.IsNullOrWhiteSpace(appId))return false;
   int pid=(int)Native.WindowProcessId(window);long start;
   using(var p=Process.GetProcessById(pid)){if(!String.Equals(p.MainModule.FileName,exe,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Window is not owned by the selected browser");start=p.StartTime.ToUniversalTime().Ticks;}
   string command=WindowProperties.Get(window,2);
   var record=entries.FirstOrDefault(b=>b.Window==window.ToInt64()&&b.Pid==pid&&b.Start==start&&b.AppId==appId&&b.Command==command);
   bool dirty=record==null;
   if(record==null){
    string original=WindowProperties.Get(window,3);
    if(entries.Any(b=>b.Window==window.ToInt64()&&b.Pid==pid&&b.Start==start&&Owned(b,original)))original=null;
    record=new Backup{Window=window.ToInt64(),Pid=pid,Start=start,AppId=appId,Command=command,Original=original};entries.Add(record);
   }
   if(!record.AppliedIcons.Contains(icon)){record.Applied=icon;record.AppliedIcons.Add(icon);dirty=true;}
   bool change=WindowProperties.Get(window,3)!=icon;
   // A failed save must be retried before a later tick can modify the real window.
   if(dirty||change)Save();
   if(change)WindowProperties.Set(window,3,icon);
   return true;
  }
  public void Restore() {
   var errors=new List<string>();
   foreach(var group in entries.GroupBy(b=>new {b.Window,b.Pid,b.Start}))try {
    var record=group.First();if(!ProcessIdentity(record))continue;
    string current=WindowProperties.Get((IntPtr)record.Window,3);if(!group.Any(b=>Owned(b,current)))continue;
    var matching=group.LastOrDefault(b=>Identity(b));string original=matching==null?null:matching.Original;
    if(group.Any(b=>Owned(b,original)))original=null;
    // A changed profile gets native fallback, never a deleted product resource or another profile's icon.
    WindowProperties.Set((IntPtr)record.Window,3,original);
   }catch(Exception ex){errors.Add(ex.Message);}
   if(errors.Count>0)throw new InvalidOperationException("Window property restoration failed: "+String.Join("; ",errors));
  }
 }
}
