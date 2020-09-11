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
 * This source is written in the D Programming Language.
 * See www.digitalmars.com/d/ for the D specification and compiler.
 *
 * Use entirely at your own risk. There is no warranty, expressed or implied.
 */


module text;

import std.c.stdio;
import std.ctype;

import empire;
import printf;

extern (C) void win_flush();
extern (C) void sound_click();

const int VBUFROWS	= 5;
const int VBUFCOLS	= 80;

char vbuffer[5][80 + 1];

// For each text mode display, which can be either a tty or the
// PC screen in text mode.

struct Text
{
    ubyte watch;		// display attribute DAxxxx if non-zero
    int TTtyp;			// terminal type
    uint cursor;		// current cursor position
    uint Tmax;			// terminal max display size
    ubyte speaker;		// speaker on?
    ubyte narrow;		// true if narrow screen
    int nrows;			// total number of rows in display
    int ncols;			// total number of columns in display
    int inbuf;			// -1 if empty, otherwise next character to be read
    int anychanges;		// !=0 if any changes since last flush()

    void deleol()		// erase to end of line
    {
	if (watch)
	{
	    int r, c;

	    r = cursor >> 8;
	    c = cursor & 0xFF;			// get row & column in r,c
	    for (; c < VBUFCOLS; c++)
	    {   if (vbuffer[r][c] != ' ')
		{   anychanges = 1;
		    vbuffer[r][c] = ' ';
		}
	    }
	}
    }


    void deleos()		// erase to end of screen
    {
	if (watch)
	{
	    int r, c;

	    r = cursor >> 8;
	    c = cursor & 0xFF;			// get row & column in r,c
	    for (; r < VBUFROWS; r++)
	    {
		for (; c < VBUFCOLS; c++)
		    vbuffer[r][c] = ' ';
		c = 0;
	    }
	    anychanges = 1;
	}
    }

    void block_cursor()		// set block cursor
    {
    }

    void clear()		// clear screen
    {
	if (watch)
	{
	    int r, c;

	    for (r = 0; r < VBUFROWS; r++)
	    {	for (c = 0; c < VBUFCOLS; c++)
		    vbuffer[r][c] = ' ';
		vbuffer[r][VBUFCOLS] = 0;
	    }
	    anychanges = 1;
	}
    }



    /*********************************
     * Send char to output device.
     */

    void TTout(char c)
    {
	if (watch)
	{   int row, col;

	    row = cursor >> 8;
	    col = cursor & 0xFF;
	    if (row < VBUFROWS && col < VBUFCOLS)
	    {
		if (vbuffer[row][col] != c)
		{   anychanges = 1;
		    vbuffer[row][col] = c;
		}
	    }
	}
    }


    /*****************************
     * Get char from device. Wait until one is available.
     */

    int TTin()
    {   int c;

	c = TTinr();
	return c;
    }


    /***************************
     * Get char from device and return it. Return -1
     * if no char is available. Convert all chars to uc.
     * Do not echo character.
     */

    int TTinr()
    {
	int c;

	if (watch == DAnone)
	    return -1;

	c = inbuf;
	inbuf = -1;

	return std.ctype.toupper(cast(dchar)c);
    }

    void TTunget(int c)		// put character c in input
    {
	inbuf = c;
    }

    /**************************************
     * Position cursor at r,c.
     */

    void TTcurs(uint rc)
    {
	cursor = rc;
    }


    /******************************
     * Position cursor at r,c. Use cursor[] to minimize chars sent out.
     * Cases considered:
     *	1. Use cursor addressing if we are to move backwards or up.
     *	2. Use cursor addressing if we are to move to 25th line.
     *	3. Use a CRLF if we start a new line.
     *	4. Do nothing if cursor is already there.
     *	5. Else use cursor addressing.
     */

    void curs(int rc)
    {
	//PRINTF("Text::curs(%x)\n", rc);
	uint r,c,rp,cp;

	if (!watch) return;

	if (rc == cursor) return;		// case 4
	r = rc >> 8;
	c = rc & 0xFF;			// get row & column in r,c
	if (!(r <= (Tmax >> 8) && c <= (Tmax & 0xFF)))
	    PRINTF("r = %d, c = %d, Tmax = %d,%d\n", r, c, Tmax >> 8, Tmax & 0xFF);
	assert(r <= (Tmax >> 8) && c <= (Tmax & 0xFF));
	TTcurs(rc);
    }


    /*************************************
     * Ring the bell.
     */

    void bell()
    {
	//MessageBeep(0);
    }


    /**************************
     * Output chars to display. Keep track of cursor
     * position.
     * Cases considered:
     *	1.	CR
     *	2.	LF
     *	3.	0
     *	4.	printable char
     *	5.	BS
     *	6.	1 (do a delete to end of line)
     *	7.	2 (do a delay(2))
     */

    void output(char chr)
    {
	int r,c;

	if (!watch) return;
	r = cursor >> 8;
	c = cursor & 0xFF;

	switch (chr)
	{   case '\r':
		    c = 0;
		    break;
	    case '\n':
		    r++;
		    r = (r > (Tmax >> 8)) ? r - 1 : r;
		    break;
	    case '\0':
		    return;
	    case 1:
		    deleol();
		    return;
	    case 2:
		    //delay(2);
		    flush();
		    return;
	    case '\b':
		    c = (c) ? c - 1 : c;
		    break;
	    default:			/* printable char		*/
		    c++;
		    c = (c > (Tmax & 0xFF)) ? c - 1 : c;
		    break;
	}
	TTout(chr);				// and send out the char
	cursor = (r << 8) + c;		// save new cursor position
    }


    /***************************
     * Take number in decimal and send it to output().
     */

    void decprt(int i)
    {
	if (watch)
	{
	    if (i < 0)
	    {   output('-');
		i = -i;				// absolute value
	    }
	    if (i/10)
		decprt(i/10);
	    output(i % 10 + '0');
	}
    }


    /***************************
     * Send string to output.
     */

    void imes(char *p)
    {
      //printf("imes('%s')\n",p);
      if (watch)
      {
	    while (*p)
		output(*p++);
	    flush();
      }
    }

    /***************************
     * Send string to output.
     */

    void smes(char *p)
    {
      //printf("smes('%s')\n",p);
      if (watch)
      {
	imes(p);
      }
    }


    /****************************
     * Formatted print.
     */

    void vsmes(char* format,...)
    {   char buffer[100];
	int count;

	count = _vsnprintf(buffer,buffer.sizeof,format,cast(va_list)(&format + 1));
	smes(buffer);
    }

    /****************************
     * Position cursor and type message.
     */

    void cmes(int rc,char *p)
    {
      if (!watch) return;
      TTcurs(rc);
      imes(p);
    }


    /*************************
     * Initialize operating system
     * to have:
     *	single character input
     *	turn off echo
     */

    void TTinit()
    {
	inbuf = -1;		// no character in input
	//nrows = 160 / 10;
	//ncols = 120 / 10;
	nrows = VBUFROWS;
	ncols = VBUFCOLS;
    }


    /**************************
     * Restore operating system
     */

    void TTdone()
    {
    }

    /***************************************
     * Print out location in row,col format
     */

    void locprt(loc_t loc)
    {
	vsmes("%u,%u",ROW(loc),COL(loc));
    }

    void locdot(loc_t loc)
    {
	vsmes("%u,%u.",ROW(loc),COL(loc));
	deleol();
    }

    void space()
    {
	output(' ');
    }

    void crlf()
    {
	imes("\r\n");
    }

    void put(uint rc,uint value)
    {
	if (watch)
	{
	    curs(rc);
	    output(value);
	}
    }

    void flush()
    {
	if (watch && anychanges)
	{
	    win_flush();
	    anychanges = 0;
	}
    }


    /***************************************
     * Put messages in different spots for 40 col or 80 col display
     * Returns:
     *	cursor address of start of message
     */

    int DS(int row)
    {
      if (narrow)			// if 40 column display
	    return (row << 8) + 0;
      else
	    return (row << 8) + 20;
    }


    void speaker_click()	// click speaker
    {
	if (watch && speaker)
	{
	    sound_click();
	}
    }
}



