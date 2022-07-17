rm *.obj

rm winemp.exe

dmd -g -version=NewDisplay newdisplay empire init maps move path eplayer sub2 printf var mapdata winmain twin Winmm.lib empire.res user32.lib gdi32.lib comdlg32.lib -ofwinemp.exe
