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


import std.string;

import empire;
import mapdata;
import var;

/*****************************
 * Initialize city variables.
 */

void citini()
{
	int loc,i,j,k;

	/+for (i = CITMAX; i--;)
	{
		memset(&city[i],0,City.sizeof);
		city[i].loc = city[i].own = 0;
		city[i].phs = -1;						// no phase
	}+/
	city[] = City.init;
	foreach (City c; city) {
		c.loc = c.own = 0;
		c.phs = -1;        // no phase
	}

	for (i = 0, loc = MAPSIZE; loc--;)
		if (typ[map[loc]] == X)
			city[i++].loc = loc;
	//printf("%d cities\n",i);
	assert(i <= CITMAX);

	// shuffle cities around

	for (i = CITMAX / 2; i--;)
	{
		j = empire.random(CITMAX);
		k = empire.random(CITMAX);
		loc = city[j].loc;
		city[j].loc = city[k].loc;
		city[k].loc = loc;				// swap city locs
	}
}


/*****************************
 * Select a map.
 * Returns:
 *	0	success
 *	!=0	failure
 */

int selmap()
{
	// Use internal maps
	int j;
	ubyte *d;
	int i,a,c,n;

	j = empire.random(5);
	d = cast(ubyte *)(*mapdata.mapdata[j]);
	i = MAPSIZE - 1;
	while ((c = *d) != 0)				// 0 marks end of data
	{
		n = (c >> 2) & 63;				// count of map values - 1
		a = c & 3;						// bottom 2 bits
		if (a == 0 ||						// a must be 1,2,3
			c == -1 ||						// error reading file
			i - n < 0)						// too much data
		{
			assert(0);
		}
		while (n-- >= 0)
			map[i--] = a;
		d++;
	}
	if (ranq() & 4) flip();
	if (ranq() & 4) klip();				// random map rotations
	return 0;
}


/***********************
 * Flip map corner to corner.
 */

void flip()
{
	int i,j,c;

	i = j = MAPSIZE / 2;
	while (i--)
	{
		c = map[j];
		map[j++] = map[i];
		map[i] = c;
	}
}
/************************
 * Flip map end to end.
 */

void klip()
{
	int row,i,j,c;

	row = 0;
	while (row < MAPSIZE)
	{
		i = j = (Mcolmx + 1) / 2;
		while (i--)
		{
			c = map[row + j];
			map[row + j++] = map[row + i];
			map[row + i] = c;
		}
		row += Mcolmx + 1;
	}
}
