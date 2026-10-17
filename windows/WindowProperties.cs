using System;
using System.Runtime.InteropServices;
namespace AsideCleanLogo {
 public static class WindowProperties {
  [StructLayout(LayoutKind.Sequential)] struct PropertyKey {public Guid Format;public uint Id;}
  [StructLayout(LayoutKind.Explicit,Size=24)] struct Variant {[FieldOffset(0)] public ushort Type;[FieldOffset(8)] public IntPtr Pointer;}
  [ComImport,Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
   [PreserveSig] int GetCount(out uint count);
   [PreserveSig] int GetAt(uint index,out PropertyKey key);
   [PreserveSig] int GetValue(ref PropertyKey key,out Variant value);
   [PreserveSig] int SetValue(ref PropertyKey key,ref Variant value);
   [PreserveSig] int Commit();
  }
  [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr window,ref Guid iid,[MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
  [DllImport("ole32.dll")] static extern int PropVariantClear(ref Variant value);
  static PropertyKey Key(uint property) {return new PropertyKey{Format=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),Id=property};}
  static IPropertyStore Open(IntPtr window) {Guid iid=typeof(IPropertyStore).GUID;IPropertyStore store;Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window,ref iid,out store));return store;}
  public static string Get(IntPtr window,uint property) {
   var store=Open(window);var key=Key(property);Variant value=new Variant();
   try {Marshal.ThrowExceptionForHR(store.GetValue(ref key,out value));if(value.Type==0)return null;if(value.Type==31)return Marshal.PtrToStringUni(value.Pointer);if(value.Type==8)return Marshal.PtrToStringBSTR(value.Pointer);throw new InvalidOperationException("Unexpected window property value type: "+value.Type);}
   finally {PropVariantClear(ref value);Marshal.FinalReleaseComObject(store);}
  }
  public static void Set(IntPtr window,uint property,string text) {
   var store=Open(window);var key=Key(property);var value=new Variant();
   if(text!=null){value.Type=31;value.Pointer=Marshal.StringToCoTaskMemUni(text);}
   try {Marshal.ThrowExceptionForHR(store.SetValue(ref key,ref value));}
   finally {PropVariantClear(ref value);Marshal.FinalReleaseComObject(store);}
   if(Get(window,property)!=text)throw new InvalidOperationException("Window property did not persist.");
  }
 }
}
