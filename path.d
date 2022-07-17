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


module path;

import empire;
import eplayer;
import maps;
import var;

/****************************************
 * Find path from beg to end over
 *	a) land including blanks (BLK)
 *	b) if on same continent (CNT)
 *	c) path over land excluding blanks (LND)
 *	d) path over sea including blanks (SEA)
 * Returns:
 *	true if path found
 */

static char tblinit;

/*                 ,*,.,+,O,A,F,F,D,T,S,R,C,B,
 *                        o,a,f,f,d,t,s,r,c,b,
 *                        X,1,2,2,3,4,5,6,7,8
 */
bool[MAPMAX]
 okblk = [1,0,0,1,0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0];
bool[MAPMAX]
 okcnt = [0,0,0,1,1,1,1,0,0,0,0,0,0,0,
                          1,1,1,0,0,0,0,0,0,0,
                          1,1,1,0,0,0,0,0,0,0,
                          1,1,1,0,0,0,0,0,0,0,
                          1,1,1,0,0,0,0,0,0,0];
bool[MAPMAX]
 oklnd = [0,0,0,1,0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0,
                          0,1,1,0,0,0,0,0,0,0];
bool[MAPMAX]
 oksea = [1,0,1,0,0,0,0,1,0,0,0,0,0,0,
                          0,0,0,1,0,0,0,0,0,0,
                          0,0,0,1,0,0,0,0,0,0,
                          0,0,0,1,0,0,0,0,0,0,
                          0,0,0,1,0,0,0,0,0,0];

void dotblinit()
{
	/+int i;
	int j;
	int k;

	for (i = 4; i < (4 + 10); i++)
	{
		for (j = 1; j < PLYMAX; j++)
		{
			k = 4 + j * 10;
			assert(k < MAPMAX);
			okblk[k] = okblk[i];
			okcnt[k] = okcnt[i];
			oklnd[k] = oklnd[i];
			oksea[k] = oksea[i];
		}
	}+/

	for (int iPly = 1; iPly < PLYMAX; iPly++) {
		okblk[iPly*10 + 4 .. iPly*10 + 14] = okblk[4..14];
		okcnt[iPly*10 + 4 .. iPly*10 + 14] = okcnt[4..14];
		oklnd[iPly*10 + 4 .. iPly*10 + 14] = oklnd[4..14];
		oksea[iPly*10 + 4 .. iPly*10 + 14] = oksea[4..14];
	}

	tblinit++;
}

/*****************************************
 * Find path from beg to end.
 * Two entry points:
 *	patho():	optimize path
 *	pathn():	don't optimize path
 * Input:
 *	beg   beginning location
 *	end   ending location
 *	dir   1 or -1, direction to turn in case of obstacle
 *	ok[]  array of map vals with yea or nay
 *	*pr2  where we write the final move to (garbage if fail)
 * Output:
 *	*pr2
 * Returns:
 *	true	if a path is found
 */

bool path(
	Player* p,
	loc_t beg,   // beginning
	loc_t end,   // end
	int dir,     // direction to turn in obstacle
	bool* ok,    // array of ok map values
	dir_t* pr2,  // pointer to initial move
	bool opt)    // if true then optimize
in
{
	assert(dir == 1 || dir == -1);
	//assert(opt == 0 || opt == 1);
	assert(chkloc(beg));
	assert(chkloc(end));

	for (int i = 0; i < MAPMAX; i++)
	{
		//if (!(ok[i] == 0 || ok[i] == 1))
		//printf("\nok[%d]=%d  \n", i, ok[i]);
		assert(ok[i] == 0 || ok[i] == 1);
	}
}
do
{
	int i;
	int movsav;
	int t;
	int curloc;   // current location
	int loc;      // trial move location
	bool bakadr;  // ret from okmove
	int dir3;     // 3 * dir
	ubyte* mapb;  // base of map array
	int movnum;   // # of moves tried
	int movmax;   // max # of tries
	int trymov;   // trial move direction
	int begdir;   // dir that we started out with

	const int TRACKMAX = 100;

	/*	list of locs where we stopped following the shore and went straight.
	 *	This is necessary so we don't go around in circles
	 */
	int[TRACKMAX] track;

    // Given loc, return true if we can move there.
    bool mapinm() { return ok[*(mapb+loc)] || loc==end; }

    // Same as armain(), but trymov is given.
    bool armap() { return (loc=curloc+arrow(trymov)), mapinm(); }

    // See if we can move from curloc to end. Set trymov and loc
    bool armain() { return (trymov=movdir(curloc, end)), armap(); }

	// initialize

	if (!tblinit)
		dotblinit();

	*pr2 = -1;                                  // in case beg == end
	curloc = beg;
	dir3 = dir * 3;
	begdir = dir;
	t = 0;
	movmax = movnum = 50 + 2 * dist(beg, end);  // max # of tries
	mapb = p.map;                               // base addr of map

  // move straight towards end

strght:
	if (curloc == end) return true;             // if already there
	if (!armain())                              // if we can't move there
		goto folshr;                            // try following shore

okstr:
	bakadr = true;                              // return to strght

	// The move trymov is legit and we will use it.

okmove:
	if (curloc == beg)                          // if at beginning
	    *pr2 = trymov;                          // set initial move
	curloc = loc;                               // set current loc
	if (curloc == end) return true;
	if (!--movnum)                              // if run out of moves
	    goto trydir;                            // try another direction
	if (bakadr) {                               // goto strght or chknxt
	    goto strght;
	} else {
		if (opt)                                // attempt to optimize path
	    {
			int move1 = movdir(beg, curloc);    // initial move

			loc = beg;
			while (loc != curloc)               // while we haven't arrived
			{
				loc += arrow(movdir(loc, curloc));
				if (!mapinm())                  // if we can't move there
				goto chknxt;
			}
			*pr2 = move1;                       // set initial move
		}
		goto chknxt;
	}

trydir:
	dir3 = -dir3;                               // try the other direction
	dir = -dir;
	if (dir == begdir)                          // if already tried
	    return false;                           // then failed
	movnum = movmax;
	curloc = beg;
	t = 0;                                      // reset variables
	goto strght;                                // and try again

	// We've run into an obstacle. Follow the shore.

folshr:
	trymov = (trymov - dir3) & 7;               // go back 3
	if (armap())                                // if we can move there
		trymov = (trymov + dir3) & 7;           // then don't go back 3
	for (i = 8; i; i--, trymov = (trymov + dir) & 7)
	{
		loc = curloc + arrow(trymov);
		if (!border(loc) &&                   // if location isn't on edge
		  mapinm())                           // and we can move there
		{
			bakadr = false;                   // return from okmove to chknxt
			goto okmove;                      // the move is ok
		}
	}
	return false;                             // can't do anything

	/* See if we can break away from following the shore and go
	 * straight.
	 */
chknxt:
	movsav = movdir(curloc, end);	// move straight to end
	loc = curloc + arrow(movsav);
	if (!mapinm())                  // if we can't
		goto folshr;                // resume following the shore
	for (i = t; i--;)               // loop backwards thru track
		if (track[i] == loc)        // if we already tried this
			goto folshr;            // resume following shore
	track[t++] = loc;               // enter this try into track
	if (t == TRACKMAX)              // overflow array
		goto trydir;                // try other direction
	trymov = movsav;                // go straight
	goto okstr;                     // all clear for going straight
}
