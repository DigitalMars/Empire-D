/*
 * Empire, the Wargame of the Century (tm)
 * Copyright (C) 1978-2004 by Walter Bright
 * All Rights Reserved
 *
 * You may use this source for personal use only. To use it commercially
 * or to distribute source or binaries of Empire, please contact
 * www.digitalmars.com.
 *
 * Written by Walter Bright.
 * Modified by Stewart Gordon.
 * This source is written in the D Programming Language.
 * See www.digitalmars.com/d/ for the D specification and compiler.
 *
 * Use entirely at your own risk. There is no warranty, expressed or implied.
 */


/* This file implements printf for GUI apps that sends the output
 * to logfile rather than stdout.
 * The file is closed after each printf, so that it is complete even
 * if the program subsequently crashes.
 */

// TODO: what's this for?
// TODO: consider converting to D-style

import std.c.stdio;
import std.c.stdlib;
import std.c.string;
import std.string;
import std.file;
import std.stdarg;

const int LOG = 1;				// disable logging by setting this to 0

version (Windows)
{
	char logfile[] = r"\empire.log";
}
version (linux)
{
	char logfile[] = "/var/log/empire.log";
}

/*********************************************
 * Route printf() to a log file rather than stdio.
 */

enum Plog
{
	TOBITBUCKET,
	TOLOGFILE,
	TOSTDOUT,
};

Plog printf_logging = Plog.TOLOGFILE;

void printf_tologfile()
{
	printf_logging = Plog.TOLOGFILE;
}

void printf_tostdout()
{
	printf_logging = Plog.TOSTDOUT;
}

void printf_tobitbucket()
{
	printf_logging = Plog.TOBITBUCKET;
}

void LogfileAppend(char* buffer)
{
	if (printf_logging == Plog.TOLOGFILE)
		std.file.append(logfile, buffer[0 .. strlen(buffer)]);
	else
	{
		fputs(buffer, stdout);
		fflush(stdout);
	}
}

extern (C)
{

	int VPRINTF(char* format, va_list args)
	{
		if (printf_logging != Plog.TOBITBUCKET)
		{
			char buffer[128];
			char* p;
			uint psize;
			int count;

			p = buffer;
			psize = buffer.length;
			for (;;)
			{
				version (linux)
				{
					count = vsnprintf(p,psize,format,args);
					if (count == -1)
						psize *= 2;
					else if (count >= cast(int) psize)
						psize = count + 1;
					else
						break;
				}
				else version (Windows)
				{
					count = _vsnprintf(p,psize,format,args);
					if (count != -1)
						break;
					psize *= 2;
				}
				else
				{
					static assert(0);		// unsupported system
				}
				p = cast(char*) alloca(psize * buffer[0].sizeof);		// buffer too small, try again with larger size
			}

			LogfileAppend(p);
		}
		return 0;
	}

	int PRINTF(char* format, ...)
	{
		int result = 0;

		if (printf_logging != Plog.TOBITBUCKET)
		{
			va_list ap;
			//va_start(ap, format);
			ap = cast(va_list)(cast(void*)format + format.sizeof);
			result = VPRINTF(format,ap);
			//va_end(ap);
		}
		return result;
	}

}

void _printf_assert(char* file, uint line)
{
	PRINTF("assert fail: %s(%d)\n", file, line);
	*cast(char*) 0 = 0;		// seg fault to ensure it isn't overlooked
	exit(0);
}
