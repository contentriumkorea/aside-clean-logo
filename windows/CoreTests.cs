using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Diagnostics;

namespace AsideCleanLogo {
    public static class CoreTests {
        static void Check(bool ok, string name) { if (!ok) throw new Exception("FAIL: " + name); Console.WriteLine("PASS: " + name); }
        public static void Run() {
            Check(Theme.Color(0) == "white" && Theme.Color(1) == "black", "system dark/light mapping");
            Check(Program.TaskXml("AsideCleanLogo-absent-"+Guid.NewGuid().ToString("N"))==null,"real Task Scheduler missing-task lookup");
            Program.DeleteTask("AsideCleanLogo-absent-"+Guid.NewGuid().ToString("N"));
            Check(true,"real Task Scheduler nonexistent deletion is harmless");
            dynamic taskDefinition=Program.TaskDefinition();
            try {
                var taskXml=XDocument.Parse((string)taskDefinition.XmlText);XNamespace ns="http://schemas.microsoft.com/windows/2004/02/mit/task";
                Check(taskXml.Descendants(ns+"RunLevel").Single().Value=="HighestAvailable"&&taskXml.Descendants(ns+"LogonType").Single().Value=="InteractiveToken"&&taskXml.Descendants(ns+"Command").Single().Value==Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"Aside Clean Logo","Aside-Clean-Logo.exe"),"real scheduler definition uses protected interactive highest helper");
            } finally {Marshal.FinalReleaseComObject(taskDefinition);}
            using(var window=new Form()) {
                IntPtr handle=window.Handle;
                WindowProperties.Set(handle,3,"fixture.ico,0");
                Check(WindowProperties.Get(handle,3)=="fixture.ico,0","native window relaunch icon property round trip");
                WindowProperties.Set(handle,3,null);
                Check(WindowProperties.Get(handle,3)==null,"native window relaunch icon property removed on restore");
            }
            string temp = Path.Combine(Path.GetTempPath(), "AsideCleanLogo-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temp);
            try {
                string exe = Path.Combine(temp, "Aside.exe"); File.WriteAllText(exe, "fixture");
                using(var window=new Form()) {
                    IntPtr handle=window.Handle;
                    WindowProperties.Set(handle,5,"AsideFixture");WindowProperties.Set(handle,2,"fixture command");WindowProperties.Set(handle,3,"original-profile.ico,0");
                    var windows=new WindowStore(Path.Combine(temp,"window-state"),Process.GetCurrentProcess().MainModule.FileName);
                    windows.Apply(handle,"white.ico,0");windows.Apply(handle,"black.ico,0");
                    Check(WindowProperties.Get(handle,3)=="black.ico,0","taskbar relaunch property follows selected logo");
                    new WindowStore(Path.Combine(temp,"window-state"),Process.GetCurrentProcess().MainModule.FileName).Restore();
                    Check(WindowProperties.Get(handle,3)=="original-profile.ico,0","persistent window backup preserves original across reinstall");
                    windows.Apply(handle,"white.ico,0");bool stateDenied=false;
                    using(File.Open(Path.Combine(temp,"window-state","windows.json"),FileMode.Open,FileAccess.Read,FileShare.None))try{windows.Apply(handle,"black.ico,0");}catch(IOException){stateDenied=true;}
                    windows.Apply(handle,"black.ico,0");new WindowStore(Path.Combine(temp,"window-state"),Process.GetCurrentProcess().MainModule.FileName).Restore();
                    Check(stateDenied&&WindowProperties.Get(handle,3)=="original-profile.ico,0","retry after denied state write keeps window restoration durable");
                    windows.Apply(handle,"white.ico,0");WindowProperties.Set(handle,3,"owner-change.ico,0");windows.Restore();
                    Check(WindowProperties.Get(handle,3)=="owner-change.ico,0","window restore preserves a later owner change");
                    windows.Apply(handle,"white.ico,0");WindowProperties.Set(handle,2,"new profile command");windows.Restore();
                    Check(WindowProperties.Get(handle,3)==null,"profile change clears product icon before its asset is deleted");
                    windows.Apply(handle,"white.ico,0");WindowProperties.Set(handle,2,"next profile command");windows.Apply(handle,"black.ico,0");
                    new WindowStore(Path.Combine(temp,"window-state"),Process.GetCurrentProcess().MainModule.FileName).Restore();
                    Check(WindowProperties.Get(handle,3)==null,"profile change never captures product icon as an original");
                    windows.Apply(handle,"white.ico,0");WindowProperties.Set(handle,2,"third profile command");WindowProperties.Set(handle,3,"third-party.ico,0");windows.Restore();
                    Check(WindowProperties.Get(handle,3)=="third-party.ico,0","profile change preserves unrelated third-party property");
                    windows.Apply(handle,"white.ico,0");windows.Restore();
                    Check(WindowProperties.Get(handle,3)=="third-party.ico,0","new profile restores its own genuine original");
                    WindowProperties.Set(handle,3,null);WindowProperties.Set(handle,2,null);WindowProperties.Set(handle,5,null);
                }
                string first = Path.Combine(temp,"Aside.lnk"), second = Path.Combine(temp,"Other.lnk");
                Shortcut.Write(first, exe, "original.ico,7");
                Shortcut.Write(second, exe, "second.ico,2");
                byte[] original = File.ReadAllBytes(first), other = File.ReadAllBytes(second);
                var store = new LinkStore(Path.Combine(temp,"state"), new [] {temp}, exe);
                store.Apply(new [] {first}, "white.ico");
                Check(Shortcut.Read(first).Icon == "white.ico,0", "actual Shell link updated");
                store.Apply(new [] {first}, "black.ico");
                store.Restore();
                Check(original.SequenceEqual(File.ReadAllBytes(first)), "reinstall preserves first backup byte for byte");
                bool rollback = false;
                try { store.Transaction(new [] {first,second}, "white.ico", delegate { throw new IOException("registration failed"); }); }
                catch(IOException) { rollback = true; }
                Check(rollback && original.SequenceEqual(File.ReadAllBytes(first)) && other.SequenceEqual(File.ReadAllBytes(second)), "task failure rolls back every shortcut");
                bool denied = false;
                using (File.Open(second,FileMode.Open,FileAccess.Read,FileShare.None)) {
                    try { store.Transaction(new [] {first,second}, "black.ico", delegate {}); } catch(IOException) { denied = true; }
                }
                Check(denied && original.SequenceEqual(File.ReadAllBytes(first)), "locked target fails and restores earlier updates");
                bool missing = false;
                try { store.Apply(new [] {Path.Combine(temp,"missing.lnk")}, "white.ico"); } catch(FileNotFoundException) { missing = true; }
                Check(missing,"missing target is an error");
                string retry=Path.Combine(temp,"Retry.lnk");Shortcut.Write(retry,exe,"retry-original.ico,0");byte[] retryOriginal=File.ReadAllBytes(retry);bool indexDenied=false;
                using(File.Open(Path.Combine(temp,"state","links.xml"),FileMode.Open,FileAccess.Read,FileShare.None))try{store.Apply(new [] {retry},"white.ico");}catch(IOException){indexDenied=true;}
                store.Apply(new [] {retry},"white.ico");new LinkStore(Path.Combine(temp,"state"),new [] {temp},exe).Restore();
                Check(indexDenied&&retryOriginal.SequenceEqual(File.ReadAllBytes(retry)),"retry after denied shortcut index keeps first backup durable");
                string foreign = Path.Combine(temp,"CLI.lnk"); Shortcut.Write(foreign,Path.Combine(temp,"Aside-CLI.exe"),"cli.ico,0");
                bool wrong = false;
                try { store.Apply(new [] {foreign}, "white.ico"); } catch(InvalidOperationException) { wrong = true; }
                Check(wrong && Shortcut.Read(foreign).Icon == "cli.ico,0", "unrelated and CLI shortcut rejected");
                bool outside = false;
                var restricted = new LinkStore(Path.Combine(temp,"restricted"),new [] {Path.Combine(temp,"allowed")},exe);
                try { restricted.Apply(new [] {first},"white.ico"); } catch(InvalidOperationException) {outside = true;}
                Check(outside,"shortcut path constrained to approved roots");
                store.Apply(new [] {first},"black.ico");
                Shortcut.Write(first,Path.Combine(temp,"Replacement.exe"),"replacement.ico,0");
                bool changed = false;
                try {store.Restore();} catch(InvalidOperationException) {changed = true;}
                Check(changed && Shortcut.Read(first).Icon == "replacement.ico,0", "uninstall preserves a shortcut retargeted by its owner");
                Check(!Discovery.IsAsideExecutable(Path.Combine(temp,"Aside CLI","Aside.exe")),"Aside CLI directory excluded");
                Check(Discovery.IsAsideExecutable("C:\\Users\\Alice\\Programs\\Aside\\Aside.exe"),"ordinary username containing cli is accepted");
                Console.WriteLine("All disposable Windows behavior tests passed.");
            } finally {Directory.Delete(temp,true);}
        }
    }
}
