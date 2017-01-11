#
# Makefile for the fileinfo program
#

ifeq (${OS},android)
	ANDNDK    = /opt/android-ndk
	PLATFORM  = 8
	#ANDBIN  := $(ANDNDK)/toolchains/arm-eabi-4.4.0/prebuilt/linux-x86/bin
	ANDBIN   := $(ANDNDK)/toolchains/arm-linux-androideabi-4.4.3/prebuilt/linux-x86/bin
	ANDUSR   := $(ANDNDK)/platforms/android-${PLATFORM}/arch-arm/usr
	ANDINC   := $(ANDUSR)/include
	ANDLIB   := $(ANDUSR)/lib
	#ANDARM  := $(ANDBIN)/arm-eabi
	ANDARM   := $(ANDBIN)/arm-linux-androideabi
	ANDLINKER = /system/bin/linker

	CC       := $(ANDARM)-g++
	CPP      := $(ANDARM)-cpp
	CFLAGS   := -O -fpic -rdynamic -DANDROID -I$(ANDINC)
	CLIBS    := -L$(ANDLIB) -Wl,-rpath-link=$(ANDLIB),-dynamic-linker=$(ANDLINKER) -nostdlib -lc -ldl -lm
else
	CC      = g++
	CP      = cp
	CFLAGS  = -g -O -Wall
	CLIBS   =
	DESTDIR = /usr/local/bin
	LIBDIR  = /usr/local/lib/brexx
endif

.cc.o:
	$(CC) -c $(CFLAGS) $<

all: fileinfo rmfiles

fileinfo:	fileinfo.o
	$(CC) -o $@ $< $(CLIBS)

rmfiles:	rmfiles.o
	$(CC) -o $@ $< $(CLIBS)

dirtest:	dirtest.o
	$(CC) -o $@ $< $(CLIBS)

install:
	$(CP) fileinfo rmfiles $(DESTDIR)
	$(CP) sync.r syncdiff.r $(DESTDIR)
	$(CP) synclib.r $(LIBDIR)

.PHONY: tags
tags:
	ctags *.c *.r

clean:
	rm -f fileinfo *.o core.*
