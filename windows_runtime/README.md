Microsoft Visual C++ 2015-2022 runtime (x64, v14.44), copied from Visual Studio
Build Tools' redistributable folder (VC\Redist\MSVC\...\x64\Microsoft.VC143.CRT).

windows_installer.iss installs these next to school_management_app.exe so the
PC app starts on computers that never had the VC++ Redistributable installed
(fresh or stripped-down Windows). Microsoft allows app-local redistribution of
these files.
