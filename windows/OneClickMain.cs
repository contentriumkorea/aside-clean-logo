using System;
using System.IO;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

namespace AsideCleanLogo {
 public static class OneClickMain {
  [STAThread] public static int Main(string[] args) {
   // The apply executable is also the protected helper copied by the existing engine.
   if(args.Length == 1 && args[0] == "--watch") return Program.Main(args);
   bool quiet = args.Length == 1 && args[0] == "--quiet";
   if(args.Length > 0 && !quiet) return 2;
   try {
    bool created;
    using(var action = new Mutex(true, "Local\\AsideCleanLogo-Action-" + WindowsIdentity.GetCurrent().User.Value, out created)) {
     if(!created) return 0;
#if RESTORE_LOGO
    if(Directory.Exists(Program.Home)) Program.Uninstall();
#else
    Program.Install(false);
#endif
    return 0;
    }
   } catch(Exception ex) {
    Console.Error.WriteLine(ex.ToString());
    if(!quiet) MessageBox.Show(ex.Message, "Aside Clean Logo", MessageBoxButtons.OK, MessageBoxIcon.Error);
    return ex is FileNotFoundException ? 2 : 1;
   }
  }
 }
}
