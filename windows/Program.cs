using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using System.Xml.Linq;
using Microsoft.Win32;

namespace AsideCleanLogo {
 public static class Program {
  public static readonly string Home=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Aside Clean Logo");
  static readonly string Self=Assembly.GetExecutingAssembly().Location;
  static readonly string Sid=WindowsIdentity.GetCurrent().User.Value;
  static readonly string TaskName="AsideCleanLogo-"+Sid;
  static readonly string ExeName="Aside-Clean-Logo.exe";
  static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
  static string EventName {get{return "Local\\AsideCleanLogo-Stop-"+Sid;}}
  static string[] Roots {get{return new [] {Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory),Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar")}.Where(p=>!String.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();}}
  [STAThread] public static int Main(string[] args) {
   try {
    if(args.Length==0) {Application.EnableVisualStyles();Application.Run(new InstallForm());return 0;}
    if(args.Length!=1)throw new ArgumentException("Use --install, --uninstall, --status, --self-test, or --watch.");
    switch(args[0]) {
     case "--self-test": CoreTests.Run();CheckAssets();ShellAssetTest();return 0;
     case "--status": if(!File.Exists(Path.Combine(Home,"status.json")))return 2;Console.WriteLine(File.ReadAllText(Path.Combine(Home,"status.json")));return 0;
     case "--install": Install();return 0;
     case "--uninstall": Uninstall();return 0;
     case "--watch": Watch();return 0;
     default:throw new ArgumentException("Unknown option: "+args[0]);
    }
   } catch(Exception ex) {
    Console.Error.WriteLine(ex.ToString());
    try {if(Directory.Exists(Home)){CheckProtected();Atomic(Path.Combine(Home,"last-error.txt"),DateTimeOffset.Now+Environment.NewLine+ex.ToString());}} catch {}
    return ex is FileNotFoundException ? 2 : 1;
   }
  }
  static void Admin() {if(!new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator))throw new UnauthorizedAccessException("Run Setup as administrator.");}
  static void CheckProtected() {
   string full=Path.GetFullPath(Home);
   var trusted=new HashSet<string>{"S-1-5-18","S-1-5-32-544","S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"};
   for(string p=Path.GetDirectoryName(full);p!=null;p=Path.GetDirectoryName(p))if(Directory.Exists(p)) {
    if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new UnauthorizedAccessException("Protected installation path contains a reparse point.");
    var parent=Directory.GetAccessControl(p);
    if(!trusted.Contains(parent.GetOwner(typeof(SecurityIdentifier)).Value))throw new UnauthorizedAccessException("Installation ancestor has an untrusted owner: "+p);
    foreach(FileSystemAccessRule rule in parent.GetAccessRules(true,true,typeof(SecurityIdentifier))) {
     if((rule.PropagationFlags&PropagationFlags.InheritOnly)!=0)continue;
     long replaces=(long)(FileSystemRights.DeleteSubdirectoriesAndFiles|FileSystemRights.Delete|FileSystemRights.ChangePermissions|FileSystemRights.TakeOwnership)|0x10000000L;
     if(rule.AccessControlType==AccessControlType.Allow&&!trusted.Contains(rule.IdentityReference.Value)&&((long)rule.FileSystemRights&replaces)!=0)throw new UnauthorizedAccessException("Installation ancestor can be replaced by an untrusted identity: "+p);
    }
   }
   if(!Directory.Exists(full))return;
   var pending=new Stack<string>();pending.Push(full);
   while(pending.Count>0) {
    string path=pending.Pop();bool directory=Directory.Exists(path);
    if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new UnauthorizedAccessException("Installation contains a reparse point: "+path);
    var security=directory?(FileSystemSecurity)Directory.GetAccessControl(path):File.GetAccessControl(path);
    if(!trusted.Contains(security.GetOwner(typeof(SecurityIdentifier)).Value))throw new UnauthorizedAccessException("Installation is owned by an untrusted identity: "+path);
    foreach(FileSystemAccessRule rule in security.GetAccessRules(true,true,typeof(SecurityIdentifier))) {
     if((rule.PropagationFlags&PropagationFlags.InheritOnly)!=0)continue;
     long rights=(long)rule.FileSystemRights;
     long writes=(long)(FileSystemRights.WriteData|FileSystemRights.AppendData|FileSystemRights.ChangePermissions|FileSystemRights.TakeOwnership|FileSystemRights.Delete|FileSystemRights.DeleteSubdirectoriesAndFiles)|0x50000000L;
     if(rule.AccessControlType==AccessControlType.Allow && !trusted.Contains(rule.IdentityReference.Value) && (rights&writes)!=0)throw new UnauthorizedAccessException("Installation grants write permission to an untrusted identity: "+rule.IdentityReference);
    }
    if(directory)foreach(string child in Directory.GetFileSystemEntries(path))pending.Push(child);
   }
  }
  static void Atomic(string file,string text) {string temp=file+".tmp";File.WriteAllText(temp,text);if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);}
  static void Extract(string name,string target) {using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))using(var output=File.Create(target))input.CopyTo(output);}
  static void CheckAssets() {foreach(string n in new [] {"black.ico","white.ico"})using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream(n)){if(input==null)throw new InvalidDataException("Missing embedded "+n);using(var icon=new Icon(input)){if(icon.Width<16)throw new InvalidDataException("Invalid icon");}}}
  static void ShellAssetTest() {
   string temp=Path.Combine(Path.GetTempPath(),"AsideCleanLogo-icons-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
   try {foreach(string color in new [] {"black","white"}){string file=Path.Combine(temp,color+".ico");Extract(color+".ico",file);Native.ValidateShellIcon(file);Console.WriteLine("PASS: Windows Shell extracts "+color+" icon");}}
   finally{Directory.Delete(temp,true);}
  }
  static Dictionary<string,object> Config() {
   string file=Path.Combine(Home,"install.json");if(!File.Exists(file))throw new FileNotFoundException("Aside Clean Logo is not installed",file);
   var value=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));
   if((string)value["Sid"]!=Sid)throw new UnauthorizedAccessException("Use the Windows account that installed Aside Clean Logo.");
   return value;
  }
  static string[] AllLinks() {
   var links=new List<string>();
   foreach(string root in Roots)if(Directory.Exists(root)) {
    var pending=new Stack<string>();pending.Push(root);
    while(pending.Count>0) {
     string dir=pending.Pop();if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)continue;
     links.AddRange(Directory.GetFiles(dir,"*.lnk"));foreach(string child in Directory.GetDirectories(dir))pending.Push(child);
    }
   }
   return links.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
  }
  static string FindAside(string[] links) {
   var candidates=new List<string>();
   foreach(string link in links) {var data=Shortcut.Read(link);if(Discovery.IsAsideExecutable(data.Target))candidates.Add(data.Target);}
   foreach(var p in Process.GetProcessesByName("Aside"))try {if(Discovery.IsAsideExecutable(p.MainModule.FileName))candidates.Add(p.MainModule.FileName);}catch {}finally {p.Dispose();}
   foreach(string root in new [] {Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs")}) {
    if(String.IsNullOrWhiteSpace(root))continue;candidates.Add(Path.Combine(root,"Aside","Application","Aside.exe"));candidates.Add(Path.Combine(root,"Aside","Aside.exe"));
   }
   foreach(var hive in new [] {Registry.CurrentUser,Registry.LocalMachine})using(var key=hive.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Aside.exe"))if(key!=null)candidates.Add(Convert.ToString(key.GetValue(null)).Trim('"'));
   string exe=candidates.FirstOrDefault(p=>Discovery.IsAsideExecutable(p)&&File.Exists(p));
   if(exe==null)throw new FileNotFoundException("Aside browser was not found. Install the Aside desktop browser first.");return Path.GetFullPath(exe);
  }
  static string[] Matching(string[] links,string exe) {return links.Where(p=>String.Equals(Shortcut.Read(p).Target,exe,StringComparison.OrdinalIgnoreCase)).ToArray();}
  static string Color() {using(var key=Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"))return Theme.Color(key==null?1:Convert.ToInt32(key.GetValue("SystemUsesLightTheme",1)));}
  static dynamic Scheduler() {dynamic service=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));service.Connect();return service;}
  public static string TaskXml(string name) {dynamic service=Scheduler();try {return (string)service.GetFolder("\\").GetTask(name).Xml;}catch(FileNotFoundException) {return null;}catch(COMException ex) {if((uint)ex.ErrorCode==0x80070002)return null;throw;}finally {Marshal.FinalReleaseComObject(service);}}
  public static dynamic TaskDefinition() {
   dynamic service=Scheduler();try {
    dynamic task=service.NewTask(0);task.RegistrationInfo.Description="Switch approved Aside shortcut and window icons with Windows system appearance.";
    task.Principal.UserId=Sid;task.Principal.LogonType=3;task.Principal.RunLevel=1;
    task.Settings.Enabled=true;task.Settings.StartWhenAvailable=true;task.Settings.DisallowStartIfOnBatteries=false;task.Settings.StopIfGoingOnBatteries=false;task.Settings.ExecutionTimeLimit="PT0S";task.Settings.MultipleInstances=2;
    task.Settings.RestartCount=3;task.Settings.RestartInterval="PT1M";
    dynamic trigger=task.Triggers.Create(9);trigger.UserId=Sid;trigger.Enabled=true;
    dynamic action=task.Actions.Create(0);action.Path=Path.Combine(Home,ExeName);action.Arguments="--watch";action.WorkingDirectory=Home;
    return task;
   } finally {Marshal.FinalReleaseComObject(service);}
  }
  static void RegisterTask(string xml) {
   dynamic service=Scheduler();try {
    dynamic folder=service.GetFolder("\\");
    if(xml!=null) {folder.RegisterTask(TaskName,xml,6,null,null,3,null);return;}
    dynamic task=TaskDefinition();
    folder.RegisterTaskDefinition(TaskName,task,6,null,null,3,null);
   } finally {Marshal.FinalReleaseComObject(service);}
  }
  static void RunTask() {dynamic service=Scheduler();try {service.GetFolder("\\").GetTask(TaskName).Run(null);}finally{Marshal.FinalReleaseComObject(service);}}
  public static void DeleteTask(string name) {dynamic service=Scheduler();try {try{service.GetFolder("\\").DeleteTask(name,0);}catch(FileNotFoundException){}catch(COMException ex){if((uint)ex.ErrorCode!=0x80070002)throw;}}finally{Marshal.FinalReleaseComObject(service);}}
  static void StopWatch() {
   try {using(var stop=EventWaitHandle.OpenExisting(EventName))stop.Set();}catch(WaitHandleCannotBeOpenedException) {}
   for(int i=0;i<30;i++){bool live=false;foreach(var p in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(ExeName)))try {if(p.Id!=Process.GetCurrentProcess().Id && String.Equals(p.MainModule.FileName,Path.Combine(Home,ExeName),StringComparison.OrdinalIgnoreCase))live=true;}catch {}finally {p.Dispose();}if(!live)return;Thread.Sleep(200);}
   throw new IOException("Watcher did not stop safely; no files were removed.");
  }
  static void ImportPrototype(LinkStore store,string exe) {
   string prototype=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"AsideIconTheme");
   string index=Path.Combine(prototype,"backup-index.json");if(!File.Exists(index))return;
   object raw=Json.DeserializeObject(File.ReadAllText(index));var array=raw as object[];if(array==null)array=new [] {raw};
   foreach(var item in array) {
    var value=item as Dictionary<string,object>;if(value==null)continue;
    string path=Convert.ToString(value["Path"]),backup=Convert.ToString(value["Backup"]);
    string allowed=Path.GetFullPath(Path.Combine(prototype,"backup"))+"\\";
    if(!Path.GetFullPath(backup).StartsWith(allowed,StringComparison.OrdinalIgnoreCase)||!File.Exists(backup)||!File.Exists(path))continue;
    if(!String.Equals(Shortcut.Read(path).Target,exe,StringComparison.OrdinalIgnoreCase))continue;
    if(Shortcut.Read(backup).Icon.IndexOf("AsideIconTheme",StringComparison.OrdinalIgnoreCase)>=0)throw new InvalidDataException("Prototype backup already contains a modified icon; original backup is required.");
    store.ImportOriginal(path,backup);
   }
  }
  public static void Install() {
   Admin();CheckProtected();CheckAssets();
   string[] all=AllLinks();string exe=FindAside(all);string[] links=Matching(all,exe);
   if(links.Length==0)throw new FileNotFoundException("No Aside shortcuts were found. Create a desktop or Start menu shortcut first.");
   Directory.CreateDirectory(Home);CheckProtected();
   bool existed=File.Exists(Path.Combine(Home,"install.json"));if(existed)Config();
   StopWatch();string oldTask=TaskXml(TaskName);
   var previous=new Dictionary<string,byte[]>();
   foreach(string name in new [] {ExeName,"black.ico","white.ico","install.json","status.json"}) {string file=Path.Combine(Home,name);if(String.Equals(file,Self,StringComparison.OrdinalIgnoreCase))continue;previous[file]=File.Exists(file)?File.ReadAllBytes(file):null;}
   try {
    if(!String.Equals(Self,Path.Combine(Home,ExeName),StringComparison.OrdinalIgnoreCase))File.Copy(Self,Path.Combine(Home,ExeName),true);
    Extract("black.ico",Path.Combine(Home,"black.ico"));Extract("white.ico",Path.Combine(Home,"white.ico"));
    Atomic(Path.Combine(Home,"install.json"),Json.Serialize(new {Version="1.0.0",Sid=Sid,Aside=exe,InstalledAt=DateTimeOffset.Now.ToString("o")}));
    var store=new LinkStore(Home,Roots,exe);ImportPrototype(store,exe);
    store.Transaction(links,Path.Combine(Home,Color()+".ico"),delegate {
     try {
     RegisterTask(null);if(File.Exists(Path.Combine(Home,"status.json")))File.Delete(Path.Combine(Home,"status.json"));RunTask();
     for(int i=0;i<100;i++) {
      Thread.Sleep(200);string status=Path.Combine(Home,"status.json");if(!File.Exists(status))continue;
      var s=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(status));
      if(s.ContainsKey("Errors") && ((System.Collections.IEnumerable)s["Errors"]).Cast<object>().Any())throw new IOException("Watcher reported errors: "+File.ReadAllText(status));
      if(s.ContainsKey("Ready") && (bool)s["Ready"]){RegisterUninstall();return;}
     }
     throw new IOException("Scheduled watcher did not report readiness within 20 seconds.");
     } catch {StopWatch();throw;}
    });
    Native.Notify(links);
   } catch {
    StopWatch();if(oldTask!=null)RegisterTask(oldTask);else DeleteTask(TaskName);
    foreach(var item in previous) {if(item.Value==null){if(File.Exists(item.Key))File.Delete(item.Key);}else File.WriteAllBytes(item.Key,item.Value);}
    if(!existed)Registry.LocalMachine.DeleteSubKeyTree("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\AsideCleanLogo",false);
    if(oldTask!=null)RunTask();throw;
   }
  }
  static void RegisterUninstall() {using(var key=Registry.LocalMachine.CreateSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\AsideCleanLogo")) {key.SetValue("DisplayName","Aside Clean Logo");key.SetValue("DisplayVersion","1.0.0");key.SetValue("Publisher","Contentrium");key.SetValue("InstallLocation",Home);key.SetValue("UninstallString","\""+Path.Combine(Home,ExeName)+"\" --uninstall");key.SetValue("NoModify",1);key.SetValue("NoRepair",1);}}
  public static void Uninstall() {
   Admin();CheckProtected();var config=Config();string exe=(string)config["Aside"];
   StopWatch();var store=new LinkStore(Home,Roots,exe);
   store.Restore();new WindowStore(Home,exe).Restore();Native.RestoreFromExecutable(exe);Native.Notify(Matching(AllLinks(),exe));
   DeleteTask(TaskName);Registry.LocalMachine.DeleteSubKeyTree("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\AsideCleanLogo",false);
   // Remove only known product files. Never recursively delete an installation directory.
   string backup=Path.Combine(Home,"backup");if(Directory.Exists(backup)){foreach(string file in store.BackupFiles)if(File.Exists(file))File.Delete(file);if(!Directory.EnumerateFileSystemEntries(backup).Any())Directory.Delete(backup);}
   foreach(string name in new [] {"black.ico","white.ico","install.json","status.json","links.xml","windows.json","last-error.txt"}) {string file=Path.Combine(Home,name);if(File.Exists(file))File.Delete(file);}
   string helper=Path.Combine(Home,ExeName);if(File.Exists(helper)){try {File.Delete(helper);}catch(IOException){if(!Native.MoveFileEx(helper,null,4))throw new IOException("Uninstall succeeded except removal of its running executable; restart Windows and rerun Setup --uninstall.");}}
   if(!Directory.EnumerateFileSystemEntries(Home).Any())Directory.Delete(Home);
  }
  static void Watch() {
   Admin();CheckProtected();if(!String.Equals(Self,Path.Combine(Home,ExeName),StringComparison.OrdinalIgnoreCase))throw new UnauthorizedAccessException("The elevated watcher must run from its protected installation directory.");
   string exe=(string)Config()["Aside"];bool created;
   using(var mutex=new Mutex(true,"Local\\AsideCleanLogo-Watch-"+Sid,out created)) {
    if(!created)return;
    using(var stop=new EventWaitHandle(false,EventResetMode.ManualReset,EventName)) {
     var handles=new Dictionary<string,IntPtr[]>();foreach(string c in new [] {"white","black"}) {var h=new [] {Native.LoadImage(IntPtr.Zero,Path.Combine(Home,c+".ico"),1,32,32,16),Native.LoadImage(IntPtr.Zero,Path.Combine(Home,c+".ico"),1,256,256,16)};if(h.Any(p=>p==IntPtr.Zero))throw new IOException("Icon could not be loaded");handles[c]=h;}
     var windowStore=new WindowStore(Home,exe);
     try {
      do {
       string color=Color();var errors=new List<string>();int count=0,windows=0,verified=0,relaunch=0;
       try {var store=new LinkStore(Home,Roots,exe);var links=Matching(AllLinks(),exe);count=links.Length;
        foreach(string path in links)try {if(!String.Equals(Shortcut.Read(path).Icon,Path.Combine(Home,color+".ico")+",0",StringComparison.OrdinalIgnoreCase)){store.Apply(new [] {path},Path.Combine(Home,color+".ico"));Native.Notify(new [] {path});}}catch(Exception ex){errors.Add(ex.Message);}
        foreach(var h in Native.Windows(exe)){windows++;if(Native.SetIcon(h,0,handles[color][0])&&Native.SetIcon(h,1,handles[color][1]))verified++;else errors.Add("Window icon update failed: "+h);try{if(windowStore.Apply(h,Path.Combine(Home,color+".ico")+",0"))relaunch++;}catch(Exception ex){errors.Add("Taskbar relaunch icon: "+ex.Message);}}
       } catch(Exception ex){errors.Add(ex.Message);}
       Atomic(Path.Combine(Home,"status.json"),Json.Serialize(new {Ready=errors.Count==0,Color=color,Icon=Path.Combine(Home,color+".ico"),Shortcuts=count,Windows=windows,VerifiedWindows=verified,VerifiedRelaunchIcons=relaunch,Errors=errors,ProcessId=Process.GetCurrentProcess().Id,UpdatedAt=DateTimeOffset.Now.ToString("o")}));
      } while(!stop.WaitOne(1500));
     } finally {windowStore.Restore();Native.RestoreFromExecutable(exe);foreach(var h in handles.Values)foreach(var icon in h)Native.DestroyIcon(icon);}
    }
   }
  }
 }
 public class InstallForm:Form {
  readonly Label info=new Label();readonly Button install=new Button();
  bool finished;
  public InstallForm() {
   Text="Aside Clean Logo";ClientSize=new Size(440,230);FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
   info.Text="Aside Clean Logo\n\nWindows dark appearance uses the white logo.\nLight appearance uses the black logo.\n\nOriginal shortcuts are backed up for removal.";info.SetBounds(24,20,395,145);Controls.Add(info);
   install.Text="Install";install.SetBounds(286,176,128,34);Controls.Add(install);
   install.Click+=delegate {if(finished){Close();return;}install.Enabled=false;info.Text="Installing and verifying...";Application.DoEvents();try {Program.Install();info.Text="Installed. The logo follows your Windows system appearance.\n\nRemove with Settings > Apps > Aside Clean Logo.";install.Text="Close";finished=true;install.Enabled=true;}catch(Exception ex){info.Text="Installation failed:\n"+ex.Message;install.Enabled=true;}};
  }
 }
}
