rm *.obj *.exe
# to build with newdisplay
../d-compiler/ldc2-1.30.0-beta1-osx-arm64/bin/ldc2 -g -mtriple=i686-windows-msvc -d-version=NewDisplay newdisplay empire init maps move path eplayer sub2 printf var mapdata winmain twin Winmm.lib empire.res -ofwinemp.exe
exit
# to build with older display and text
../d-compiler/ldc2-1.30.0-beta1-osx-arm64/bin/ldc2 -d-debug -g -mtriple=i686-windows-msvc display text empire init maps move path eplayer sub2 printf var mapdata winmain twin Winmm.lib empire.res -ofwinemp.exe
exit

etc/ldc2.conf should contain:
"i686-.*-windows-msvc":
{
    switches = [
        "-defaultlib=phobos2-ldc,druntime-ldc",
    ];
    lib-dirs = [
        "%%ldcbinarypath%%/../lib-winx86",
    ];
};

same command as above works on windows as well:
c:\d\bin\ldc2 newdisplay empire init maps move path eplayer sub2 printf var mapdata winmain twin Winmm.lib empire.res -ofwinemp.exe

but NOT on shared drives where ldc2 gives cryptic error:

lld-link: error: cannot open output file winemp.exe: function not supported

so better use dmd on windows:
dmd newdisplay empire init maps move path eplayer sub2 printf var mapdata winmain twin Winmm.lib empire.res user32.lib gdi32.lib comdlg32.lib -ofwinemp.exe