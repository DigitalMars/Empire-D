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

module maps;

import empire;
import var;

/***********************************
 * Count how many As (Fs) are aboard a T (C).
 * Returns:
 *	Number of As (Fs) are aboard. Returns 0 if unit is not a T (C).
 *	Returns 0 if unit is in a city.
 */

int aboard(Unit *u)
{ int loc,type,i,total;

  loc = u.loc;
  if ((type = tcaf(u)) < 0) return 0;	// if not a T or C
  if (typ[map[loc]] == X) return 0;	// if in a city
  total = 0;				// number aboard
  for (i = unitop; i--;)		// loop thru units
	if (unit[i].loc == loc &&	// locations match
	    unit[i].typ == type &&	// if it's the right type
	    unit[i].own == u.own)
	    total++;
  return total;
}

/**************************************
 * Look for troop transports or carriers.
 * Returns:
 *	A	if unit is a T
 *	F	if unit is a C
 *	-1	else
 */

int tcaf(Unit *u)
{			//    A  F  D  T  S  R  C  B
    static int tcaftab[8] = [-1,-1,-1, A,-1,-1, F,-1];

    return tcaftab[u.typ];
}


/*******************************
 * Find and return distance between loc1 and loc2.
 */

int dist(loc_t loc1,loc_t loc2)
{ int r1,c1,r2,c2;

  assert(chkloc(loc1));
  assert(chkloc(loc2));

  r1 = ROW(loc1);
  c1 = COL(loc1);
  r2 = ROW(loc2);
  c2 = COL(loc2);

  return max(abs(r1-r2),abs(c1-c2));
}

/******************************
 * Find direction to go in to go from loc1
 * to loc2.
 */

int movdir(loc_t loc1,loc_t loc2)
{ static int mov[] = [3,4,5,2,-1,6,1,0,7];
  int i = 0;
  int r1,c1,r2,c2;

  assert(chkloc(loc1));
  assert(chkloc(loc2));

  r1 = ROW(loc1);
  c1 = COL(loc1);
  r2 = ROW(loc2);
  c2 = COL(loc2);

  if (c2 >  c1) i++;
  if (c2 >= c1) i++;
  i *= 3;			/* i=0,3,6 for (3,4,5),(2,-1,6),(1,0,7) */

  if (r2 >  r1) i++;
  if (r2 >= r1) i++;

  return mov[i];		/* correct direction to move		*/
}

/****************************
 * Return true if we're on the edge.
 */

int border(loc_t loc)
{ int r1,c1;

  r1 = ROW(loc);
  c1 = COL(loc);
  return ((r1 == 0) || (r1 == Mrowmx) || (c1 == 0) || (c1 == Mcolmx));
}

/**********************************
 * Convert location to row*256+col
 */

int rowcol(loc_t loc)
{
  return (ROW(loc)<<8) + COL(loc);
}

/**************************
 * Total up amount of sea around loc and return it.
 */

int edger(loc_t loc)
{ int sum = 0;				/* running total		*/
  int i = 8;				/* # of directions		*/

  assert(chkloc(loc));

  while (i--)				/* continue till i = -1		*/
    if (sea[map[loc + arrow(i)]]) sum++;
  return sum;
}

/*********************
 * Check routines
 */

/**************************
 * Return true if loc is a valid location.
 */

int chkloc(loc_t loc)
{
    return loc < MAPSIZE && !border(loc);
}

void chkmov(dir_t r2,int errnum)
{
  assert(r2 >= -1 && r2 <= 7);
}


/* Miscellaneous
 */

int max(int a, int b)
{
  return (a > b) ? a : b;
}

int abs(int a)
{
  return (a < 0) ? -a : a;
}


