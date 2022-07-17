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


module sub2;

import std.string;

import empire;
import var;
import maps;

/*********************************
 * Return city number given city location.
 */

City* fndcit(loc_t loc)
in
{
	assert(chkloc(loc));
}
do
{
	int i;

	for (i = CITMAX; i--;)
		if (city[i].loc == loc)
			return &city[i];		// we found the city
	assert(0);
	return null;
}


/*******************************
 * Create a new unit, given its loc and type.
 * Output:
 *	unitop = max(unitop, uninum + 1)
 * Returns:
 *	true	if successful
 *	false	if overpopulation
 */

int newuni(out Unit* pu, loc_t loc, uint ty, uint pn)
in
{
	assert(chkloc(loc));
	assert(ty < TYPMAX);
	assert(pn <= PLYMAX);
}
body
{
	int i;
	Unit* u;

	/+for (i = 0; i < UNIMAX; i++)
	{
		u = &unit[i];

		if (!unit[i].loc)		// if unit doesn't exist
		{
			if (i >= unitop)
				unitop = i + 1;		// set unitop to 1 past max uninum
			//memset(u, 0, Unit.sizeof);
			*u = Unit.init;
			u.loc = loc;
			u.own = pn;
			u.typ = ty;
			u.hit = typx[ty].hittab;
			u.dir = (i & 1) ? 1 : -1;
			*pu = u;			// return unit # created
			return true;		// successful
		}
	}+/

	foreach (int i, inout Unit u; unit) {
		if (!u.loc) {
			if (i >= unitop)
				unitop = i + 1;		// set unitop to 1 past max uninum
			//memset(u, 0, Unit.sizeof);
			u = Unit.init;
			u.loc = loc;
			u.own = pn;
			u.typ = ty;
			u.hit = typx[ty].hittab;
			u.dir = (i & 1) ? 1 : -1;
			pu = &u;			// return unit # created
			return true;		// successful
		}
	}

	return false;				// overpopulation
}
