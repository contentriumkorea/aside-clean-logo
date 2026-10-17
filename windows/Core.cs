using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using System.Diagnostics;
namespace AsideCleanLogo {
 public class LinkDiscoveryCache {
  readonly Func<string[]> discover;
  List<string> paths=new List<string>();DateTime refreshAt=DateTime.MinValue;
  public int Scans {get;private set;}
  public long ScanMilliseconds {get;private set;}
  public DateTime LastScanUtc {get;private set;}
  public LinkDiscoveryCache(Func<string[]> discover){this.discover=discover;}
  public string[] Current(DateTime utcNow){
   if(utcNow>=refreshAt){var watch=Stopwatch.StartNew();var found=discover();paths=found.Distinct(StringComparer.OrdinalIgnoreCase).ToList();Scans++;ScanMilliseconds=watch.ElapsedMilliseconds;LastScanUtc=utcNow;refreshAt=utcNow.AddSeconds(60);}
   return paths.ToArray();
  }
  public void Forget(string path){paths.RemoveAll(p=>String.Equals(p,path,StringComparison.OrdinalIgnoreCase));}
 }
 public static class Theme {public static string Color(int light) { return light == 0 ? "white" : "black"; }}
 public class LinkData {public string Target;public string Icon;}
 public static class Shortcut {
  public static LinkData Read(string path) {
   if(!File.Exists(path))throw new FileNotFoundException("Shortcut is missing",path);
   using(File.Open(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)) {}
   dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
   dynamic link = shell.CreateShortcut(path);
   try {return new LinkData {Target=(string)link.TargetPath,Icon=(string)link.IconLocation};}
   finally {Marshal.FinalReleaseComObject(link);Marshal.FinalReleaseComObject(shell);}
  }
  public static void Write(string path,string target,string icon) {
   dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
   dynamic link=shell.CreateShortcut(path);
   try {link.TargetPath=target;link.IconLocation=icon;link.Save();}
   finally {Marshal.FinalReleaseComObject(link);Marshal.FinalReleaseComObject(shell);}
  }
  public static void SetIcon(string path,string icon) {
   // Probe first: Shell COM can silently leave a read-only link unchanged.
   using(File.Open(path,FileMode.Open,FileAccess.Write,FileShare.Read)) {}
   dynamic shell=Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
   dynamic link=shell.CreateShortcut(path);
   try {link.IconLocation=icon+",0";link.Save();}
   finally {Marshal.FinalReleaseComObject(link);Marshal.FinalReleaseComObject(shell);}
   if(!String.Equals(Read(path).Icon,icon+",0",StringComparison.OrdinalIgnoreCase))throw new IOException("Shortcut icon did not persist: "+path);
  }
 }
 public class LinkStore {
  readonly string state,exe;readonly string[] roots;
  readonly Dictionary<string,string> entries=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  public IEnumerable<string> BackupFiles {get{return entries.Values;}}
  public LinkStore(string state,string[] roots,string exe) {
   this.state=state;this.roots=roots;this.exe=exe;
   string index=Path.Combine(state,"links.xml");
   if(File.Exists(index)) foreach(var e in XDocument.Load(index).Root.Elements("link")) {
    string path=(string)e.Attribute("path"),file=(string)e.Attribute("backup");
    if(file != Path.GetFileName(file) || !file.EndsWith(".lnk",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Unsafe backup name");
    ValidatePath(path);entries.Add(path,Path.Combine(state,"backup",file));
   }
  }
  void ValidatePath(string path) {
   string full=Path.GetFullPath(path);
   if(!full.EndsWith(".lnk",StringComparison.OrdinalIgnoreCase) || !roots.Any(r=>full.StartsWith(Path.GetFullPath(r).TrimEnd('\\')+"\\",StringComparison.OrdinalIgnoreCase)))throw new InvalidOperationException("Shortcut outside allowed folders: "+path);
   for(string p=Path.GetDirectoryName(full);p!=null;p=Path.GetDirectoryName(p))if(Directory.Exists(p) && (File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("Reparse-point shortcut directory: "+p);
   if(File.Exists(full) && (File.GetAttributes(full)&FileAttributes.ReparsePoint)!=0)throw new InvalidOperationException("Reparse-point shortcut: "+path);
  }
  void ValidateTarget(string path) {
   ValidatePath(path);
   if(!String.Equals(Shortcut.Read(path).Target,exe,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Shortcut target changed or is not Aside: "+path);
  }
  void Save() {
   Directory.CreateDirectory(state);
   var doc=new XDocument(new XElement("links",entries.Select(e=>new XElement("link",new XAttribute("path",e.Key),new XAttribute("backup",Path.GetFileName(e.Value))))));
   string file=Path.Combine(state,"links.xml"),temp=file+".tmp";
   doc.Save(temp);if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);
  }
  public void ImportOriginal(string path,string backup) {
   ValidateTarget(path);
   if(entries.ContainsKey(path))return;
   if(!String.Equals(Shortcut.Read(backup).Target,exe,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Prototype backup has a different target");
   Backup(path,backup);
  }
  void Backup(string path,string source) {
   if(entries.ContainsKey(path))return;
   Directory.CreateDirectory(Path.Combine(state,"backup"));
   string key;using(var hash=SHA256.Create())key=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(path.ToUpperInvariant()))).Replace("-","");
   string backup=Path.Combine(state,"backup",key+".lnk");
   if(!File.Exists(backup))File.Copy(source,backup);
   entries.Add(path,backup);
   try {Save();}catch {entries.Remove(path);throw;}
  }
  public void Apply(string[] paths,string icon) {
   foreach(string path in paths) {ValidateTarget(path);Backup(path,path);Shortcut.SetIcon(path,icon);}
  }
  public void Restore() {
   var errors=new List<string>();
   foreach(var e in entries) {
    try {if(!File.Exists(e.Key))continue;ValidateTarget(e.Key);if(!File.Exists(e.Value))throw new FileNotFoundException("Original backup missing",e.Value);File.Copy(e.Value,e.Key,true);}
    catch(Exception ex) {errors.Add(ex.Message);}
   }
   if(errors.Count>0)throw new InvalidOperationException(String.Join(Environment.NewLine,errors));
  }
  public void Transaction(string[] paths,string icon,Action complete) {
   var before=new Dictionary<string,byte[]>();
   try {foreach(string path in paths) {ValidateTarget(path);before.Add(path,File.ReadAllBytes(path));Apply(new [] {path},icon);}complete();}
   catch(Exception original) {
    var errors=new List<string>();foreach(var e in before)try {File.WriteAllBytes(e.Key,e.Value);}catch(Exception ex){errors.Add(ex.Message);}
    if(errors.Count>0)throw new IOException("Install failed: "+original.Message+"; rollback errors: "+String.Join("; ",errors),original);
    throw;
   }
  }
 }
 public static class Discovery {
  public static bool IsAsideExecutable(string path) {
   if(String.IsNullOrWhiteSpace(path)||!String.Equals(Path.GetFileName(path),"Aside.exe",StringComparison.OrdinalIgnoreCase))return false;
   return !path.Split('\\','/').Any(part=>{
    string compact=part.Replace("-","").Replace("_","").Replace(" ","");
    return String.Equals(compact,"cli",StringComparison.OrdinalIgnoreCase)||compact.StartsWith("AsideCLI",StringComparison.OrdinalIgnoreCase);
   });
  }
 }
}
