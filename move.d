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


module move;

import empire;
import eplayer;
import sub2;

const int HYSTERESIS = 10;

/***********************************
 * Do a time slice.
 * Returns:
 *	0	continue
 *	!=0	end program
 */

int slice()
{
    int newnum;
    Player *p;

    switch (numply)
    {
	case 1:
	    Player.get(1).tslice();
	    break;

	case 2:
	    p = Player.get(plynum);

	    p.tslice();
	    newnum = plynum ^ 3;	// 2 -> 1; 1 -> 2
	    plynum = (Player.get(newnum).round > p.round + HYSTERESIS)
		    ? plynum : newnum;
	    break;

	case 3:
	    {   static int e1[4] = [0,2,1,1];	// 0th element is a dummy
		static int e2[4] = [0,3,3,2];

		// Only allow move if we're not HYSTERESIS moves ahead of the others.

		p = Player.get(plynum);
		if (Player.get(e1[plynum]).round + HYSTERESIS > p.round &&
		    Player.get(e2[plynum]).round + HYSTERESIS > p.round)
		    p.tslice();		// move the player

		plynum = (plynum >= 3) ? 1 : plynum + 1;
	    }
	    break;

	default:
	    {	int r;
		int i;

		p = Player.get(plynum);
		r = p.round;
		for (i = 1; 1; i++)
		{
		    if (i > numply)
		    {	p.tslice();
			break;
		    }
		    if (i == plynum)
			continue;

		    // Only allow move if we're not HYSTERESIS moves ahead of the others.
		    if (r >= Player.get(i).round + HYSTERESIS)
			break;			// too far ahead, next player
		}

		plynum = (plynum >= numply) ? 1 : plynum + 1;
	    }
	    break;
    }
    return 0;
}



/*****************************
 * Produce units in the cities and reset for next production.
 */

void hrdprd(Player *p)
{ uint i,wa;
  Unit *u;

  wa = p.watch;
  for (i = CITMAX; i--;)
  {	City *c = &city[i];

	if (c.own != p.num)
	    continue;			/* if we don't own the city	*/
	if (!c.loc)
	    continue;			/* if the city doesn't exist	*/
	//assert(!((c.phs & ~7) && c.phs != '\377'));
	p.sensor(c.loc);		// keep map up to date
	if (c.fnd > p.round)		/* if unit is not produced yet	*/
	    continue;
	if (newuni(&u,c.loc,c.phs,p.num))	// create new unit
	{
	    c.fnd = p.round + typx[c.phs].prodtime;
	    p.display.produce(c);

	    if (overpop)
		p.display.overpop(false);
	    overpop = false;		/* no longer overpopulated	*/
	}
	else				/* else overpop			*/
	{   overpop = true;
	    p.display.overpop(true);
	}
  }
}


/****************************
 * See if anybody won or if computer concedes defeat.
 */

void chkwin()
{ int n[PLYMAX+1];			/* # of cities owned by plyr #	*/
  int i,j;
  Text *t;
  Player *p;

  memset(n,0,n.sizeof);

  for (i = CITMAX; i--;)
	n[city[i].own]++;		// inc number owned

  for (j = 1; j <= numply; j++)		// loop thru the players
  {	p = Player.get(j);
	if (n[j] != 0 ||		// player j hasn't lost yet
	  p.defeat)			// if already defeated
	    continue;

	// If any armies, then player is not defeated
	for (i = unitop; i--;)
	{   if (unit[i].loc && unit[i].own == j && unit[i].typ == A)
		goto L1;
	}

	p.defeat = true;		// player is defeated
	numleft--;			// number of players left
	for (i = 1; i <= numply; i++)
	{
	    Player.get(i).notify_defeated(p);

	}

	if (numleft != 1)
	    for (i = 1; i < numply; i++)
	    {   if (!Player.get(i).defeat && Player.get(i).watch)
		    goto L1;
	    }
	done(0);

    L1:
	;
  }
}


/**************************************
 */

void done(int i)
{
    version (Windows)
    {
    }
    else
    {
	printf("\n");
	win32close();
	exit(i);
    }
}


/**************************************
 */

void updlst(loc_t loc,int type)		// update map value at loc
{ int ty = .typ[.map[loc]];		// what's there

  if ((ty != X) &&			// if not a city
      ((type != A) || (ty != T)) &&	// and not an A leaving a T
      ((type != F) || (ty != C)) )	// and not an F leaving a C
		updmap(loc);		// then update the map
}


/*************************************
 * Change map to land or sea, depending on whether what's on it
 * is over land or sea (i.e. an 'A' would be changed to '+').
 */

int updmap(loc_t loc)
{ return .map[loc] = (land[.map[loc]]) ? MAPland : MAPsea;
}




/************************************
 * Find & return the unit number of the unit at loc.
 */

Unit *fnduni(loc_t loc)
{ int ab,n;
  ab = .map[loc];

  chkloc(loc);
  assert(.typ[ab] >= 0);

  n = unitop;				/* max unit # + 1		*/
  while (n--)
  {	Unit *u = &unit[n];

	if (u.loc == loc && .typ[ab] == u.typ)
	    return u;
  }
  assert(0);
  return null;
}


/***********************
 * Destroy a unit given unit number. If a T or C, destroy any
 * armies or fighters which may be aboard.
 * Watch out for destroying other pieces by mistake!
 */

void kill(Unit *u)
{ int i,loc,ty,ndes;
  Player *p = Player.get(u.own);

  loc = u.loc;				// loc of unit
  ty = tcaf(u);
  p.notify_destroy(u);
  u.destroy();				// destroy unit
  if (ty == -1)				// if not T or C
	return;

  if (.typ[.map[loc]] == X)		// if in a city
	return;				// assume A's & Fs are off ship

  ndes = 0;
  for (i = unitop; i--;)
  {	if (unit[i].loc == loc &&
	    unit[i].typ == ty &&
	    unit[i].own == p.num)
	{
	    p.notify_destroy(&unit[i]);
	    unit[i].destroy();		// destroy it
	    ndes++;			// keep track of # destroyed
	}
  }
}




/**********************************
 * Select and return a random direction,
 * giving priority to moving diagonally.
 */

int randir()
{   int r2;

    r2 = empire.random(24);		// r2 = 0..23
    if (r2 >= 8)			// move diagonally (67%)
    {	r2 &= 7;			// convert to 0..7
	r2 |= 1;			// pick a diagonal move
    }
    return r2;
}



/**********************************
 * Given a pointer to an array of locs, and the number of elements
 * in the array, search for one within range. If found, set ifo,
 * ila and return true.
 */

int fndtar(Unit *u,uint *p,uint n)
{   uint loc;

    loc = u.loc;
    assert(chkloc(loc));
    for (; n--; p++)			// look at n entries
    {	if (!*p) continue;		// 0 location
	assert(chkloc(*p));
	if (dist(loc,*p) > u.fuel)	// if too far
	    continue;
	if (u.fuel == u.hit)		// if kamikaze
	    u.ifo = IFOtarkam;
	else
	    u.ifo = IFOtar;
	u.ila = *p;			// set location of target
	return true;
    }
    return false;
}



/**********************************
 * If unit is an A on a T, and is surrounded by water or friendly
 * stuff, return true.
 */

int sursea(Unit *u)
{ int loc,ac,i;

  loc = u.loc;
  if ((u.typ != A) || (typ[.map[loc]] != T))
	return(false);
  for (i = 8; i--;)
  {	ac = .map[loc + arrow(i)];	/* ltr map value		*/
	if ((land[ac] || typ[ac] == X) && own[ac] != u.own)
	    return(false);		/* found land or unowned city	*/
  }
  return(true);				/* guess it must be so		*/
}



/*************************************
 * Given unit number of a T (C), see if it is full.
 * Unit must not be in a city!
 * Use:
 *	full(uninum)
 * Input:
 *	uninum =	unit # of T or C
 * Returns:
 *	true		if the T (C) is full.
 */

int full(Unit *u)
{ int max;

  max = u.hit;
  if (u.typ == T)
	max <<= 1;			// *2 for transports
  return aboard(u) >= max;		// check # aboard against max
}


/***********************************
 * Return true if there aren't any '+'s around loc.
 * Input:
 *	loc
 */

int Ecrowd(loc_t loc)
{ int i;

  for (i = 8; i--;)
	if (.map[loc + arrow(i)] == 3)		// if '+'
	    return false;
  return true;
}



