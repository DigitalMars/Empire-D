#_ makefile
# Copyright (c) 1982-2004 by Walter Bright
# All Rights Reserved
# Digital Mars www.digitalmars.com
# Build with the D Programming Language from www.digitalmars.com/d/
# www.classicempire.com

DMROOT=e:\dm
DMDROOT=e:\dmd
CC=$(DMDROOT)\bin\dmd
LIBNT=$(DMROOT)\lib
SNN=$(DMROOT)\lib\snn
PHOBOS=$(DMDROOT)\lib\phobos.lib

#DFLAGS=-g
#LFLAGS=/co/map/noi
DFLAGS=-O -g
LFLAGS=/noi

HEADERS=   winemp.h

#DFILES1= display.d empire.d init.d maps.d
#DFILES2= move.d path.d eplayer.d sub2.d text.d
DFILES1= newdisplay.d empire.d init.d maps.d
DFILES2= move.d path.d eplayer.d sub2.d
DFILES3= var.d winmain.d mapdata.d printf.d twin.d winemp.d

DFILES= $(DFILES1) $(DFILES2) $(DFILES3)

#OBJ1=   display.obj empire.obj init.obj
OBJ2=	maps.obj move.obj path.obj eplayer.obj sub2.obj printf.obj
OBJ3=	var.obj mapdata.obj
#WOBJ=	winmain.obj text.obj twin.obj
OBJ1=   empire.obj init.obj
WOBJ=	newdisplay.obj winmain.obj twin.obj

BMP1= city1.bmp a1.bmp f1.bmp fs1.bmp d1.bmp s1.bmp t1.bmp r1.bmp c1.bmp b1.bmp
BMP2= city2.bmp a2.bmp f2.bmp fs2.bmp d2.bmp s2.bmp t2.bmp r2.bmp c2.bmp b2.bmp
BMP3= city3.bmp a3.bmp f3.bmp fs3.bmp d3.bmp s3.bmp t3.bmp r3.bmp c3.bmp b3.bmp
BMP4= city4.bmp a4.bmp f4.bmp fs4.bmp d4.bmp s4.bmp t4.bmp r4.bmp c4.bmp b4.bmp
BMP5= city5.bmp a5.bmp f5.bmp fs5.bmp d5.bmp s5.bmp t5.bmp r5.bmp c5.bmp b5.bmp
BMP6= city6.bmp a6.bmp f6.bmp fs6.bmp d6.bmp s6.bmp t6.bmp r6.bmp c6.bmp b6.bmp

BMP7= blast.bmp blastmask.bmp icon.bmp empire2.bmp unknown.bmp unknown10.bmp \
	land.bmp sea.bmp city.bmp

BMP= $(BMP1) $(BMP2) $(BMP3) $(BMP4) $(BMP5) $(BMP6) $(BMP7)

WAV1=intro.wav click.wav gun_1.wav explosi1.wav error.wav splash.wav bubbles.wav
WAV2=machine1.wav gun_3.wav flyby.wav explode.wav fuel.wav explosion3.wav
WAV3=taps.wav ackack1.wav

WAV= $(WAV1) $(WAV2) $(WAV3)

SOURCE= $(HEADERS) $(DFILES) $(BMP) $(WAV) makefile empire.rc empire.def help.txt

# Makerules:
.d.obj :
	$(CC) $(DFLAGS) -c $*

targets: winemp.exe

winemp.exe : $(OBJ1) $(OBJ2) $(OBJ3) $(WOBJ) empire.res empire.def
	dmd -g newdisplay.obj empire.obj init.obj maps.obj move.obj path.obj eplayer.obj sub2.obj printf.obj var.obj mapdata.obj winmain.obj twin.obj winmm.lib comdlg32.lib gdi32.lib kernel32.lib user32.lib empire.def empire.res -ofwinemp.exe

#winemp.exe : $(OBJ1) $(OBJ2) $(OBJ3) $(WOBJ) winemp.lnk empire.res empire.def
	#link /DEB /DEBUGA /DEBUGB /DEBUGC /DEBUGLI /DEBUGLO /DEBUGP /DEBUGR /DEBUGT @winemp.lnk

winemp.lnk : makefile
	echo $(OBJ1)+				>  $*.lnk
	echo $(OBJ2)+				>> $*.lnk
	echo $(OBJ3)+				>> $*.lnk
	echo $(WOBJ)$(LFLAGS)			>> $*.lnk
	echo $*					>> $*.lnk
	echo $*					>> $*.lnk
	echo $(PHOBOS)+				>> $*.lnk
	echo $(SNN)+				>> $*.lnk
	echo winmm+comdlg32+gdi32+kernel32+user32 >> $*.lnk
	echo empire.def				>> $*.lnk
	echo empire.res				>> $*.lnk

textwin.obj : textwin.d
	$(CC) -c -g textwin

textwin.exe : textwin.obj textwin.def
	$(CC) -g textwin.obj winmm.lib comdlg32.lib gdi32.lib kernel32.lib user32.lib textwin.def

empire.res : empire.rc winemp.h $(BMP)
#	rc /r empire.rc
	rcc -r -32 empire.rc

clean:
	del *.map
	del *.obj
	del empire.res
	del winemp.lnk

display.obj:	 display.d empire.d
mapdata.obj:	 mapdata.d empire.d
empire.obj:	 empire.d
init.obj:	 empire.d init.d
maps.obj:	 empire.d maps.d
move.obj:	 empire.d move.d
path.obj:	 empire.d path.d
eplayer.obj:	 eplayer.d
printf.obj:	 printf.d
sub2.obj:	 empire.d sub2.d
winmain.obj:	 empire.d winemp.h printf.d winmain.d
twin.obj:	 empire.d winemp.h twin.d
text.obj:	 empire.d text.d
var.obj:	 empire.d var.d

zip:
	zip32 empire *.h *.d *.rc *.def makefile

empirebin: winemp.exe help.html $(WAV1) $(WAV2) $(WAV3)
	del empirebin.zip
	zip32 empirebin winemp.exe help.txt
	zip32 empirebin $(WAV1)
	zip32 empirebin $(WAV2)
	zip32 empirebin $(WAV3)

empiresrc: $(SOURCE)
	del empiresrc.zip
	zip32 empiresrc $(HEADERS)
	zip32 empiresrc $(DFILES1)
	zip32 empiresrc $(DFILES2)
	zip32 empiresrc $(DFILES3)
	zip32 empiresrc $(WAV1)
	zip32 empiresrc $(WAV2)
	zip32 empiresrc $(WAV3)
	zip32 empiresrc $(BMP1)
	zip32 empiresrc $(BMP2)
	zip32 empiresrc $(BMP3)
	zip32 empiresrc $(BMP4)
	zip32 empiresrc $(BMP5)
	zip32 empiresrc $(BMP6)
	zip32 empiresrc $(BMP7)
	zip32 empiresrc makefile empire.rc empire.def help.txt

