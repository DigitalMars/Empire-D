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


module var;

import std.c.stdio;

import empire;
import eplayer;

/**************************************
 * Variables not saved across game saves.
 */

uint noflush = 0;						// if non-zero then don't flush

Type typx[TYPMAX] =
[
	{  5, 6,'A', 0 },
	{ 10,12,'F',20 },
	{ 20,24,'D', 3 },
	{ 30,36,'T', 3 },
	{ 25,30,'S', 2 },
	{ 50,60,'R', 8 },
	{ 60,72,'C', 8 },
	{ 75,90,'B',12 },
];


// These are fleshed out in init_var()
//					 ,*,.,+,O,A,F,F,D,T,S,R,C,B
int[MAPMAX] own   = [0,0,0,0,1,1,1,1,1,1,1,1,1,1,  // etc.
                             2,2,2,2,2,2,2,2,2,2];
int[MAPMAX] typ   = [J,X,J,J,X,A,F,F,D,T,S,R,C,B,  // etc.
                             X,A,F,F,D,T,S,R,C,B];
bool[MAPMAX] sea  = [0,0,1,0,0,0,0,1,1,1,1,1,1,1,  // etc.
                             0,0,0,1,1,1,1,1,1,1];
bool[MAPMAX] land = [0,0,0,1,0,1,1,0,0,0,0,0,0,0,  // etc.
                             0,1,1,0,0,0,0,0,0,0];

// Mask table. Index is type (A..B).
ubyte[8] msk      = [mA,mF,mD,mT,mS,mR,mC,mB];

/* direction table, index is -1..7
 *
 *		qwe		3  2  1
 *		a d		4 -1  0
 *		zxc		5  6  7
 */

int arrow(dir_t dir)
	in
	{
		assert(-1 <= dir && dir <= 7);
	}
	body
	{
		static int arrow[9] =
			[0,1,-Mcolmx,-Mcolmx-1,-Mcolmx-2,-1,Mcolmx,Mcolmx+1,Mcolmx+2];

		return arrow[dir + 1];
	}

int mapgen = false;             // true if we're running MAPGEN.EXE
int savegame = false;           // set to true if we're to save the game

/*************************************
 * Variables saved across game saves.
 * All variables must be initialized, so they are in the same segment.
 */

ubyte savbeg = 0;				// start of variable save area

/*
 * Map variables
 */

ubyte[MAPSIZE] map = [0,]; // reference map
int empver = VERSION;      // version number
//static int mapbas = 0;   // not used

uint seedhi=0,seedlo=0; // seeds for random()
int overpop = false;    // true means unit arrays are full
int tamper = false;     // true means prog has been tampered with

/*
 * City variables.
 */

uint cittop = 0;				// actual number of cities
City[CITMAX] city;

/*
 * Unit variables.
 */

uint unitop = 0;				// unitop >= topmost unit number
Unit[UNIMAX] unit;

/*
 * Player variables.
 */

int	numply = 0,	  // default number of players playing
	plynum = 0,	  // which player is playing, 1..numply
	concede = false, // set to true if computer concedes game
	numleft = 0;	 // number of players left in the game

Player[PLYMAX + 1] player;

ubyte savend = 0;	// so we can find end of variable space

/*************************************
 * Initialize variables.
 */

void init_var()
{
	int i,j;

	for (i = 0; i < PLYMAX; i++)
	{
		if (i && player[i].map)
			player[i].map = null;

		if (player[i].display) {
			delete player[i].display;
			player[i].display = null;
		}
	}

	(&savbeg)[0 .. &savend - &savbeg] = 0;
	city[] = City.init;
	unit[] = Unit.init;
	player[] = Player.init;

	own [4..14] = 1;
	for (i = 2; i <= PLYMAX; i++)
	{
		/+for (j = 0; j < 10; j++)
		{   // Fill in the etc. parts

			own [4 + (i - 1) * 10 + j] = i;
			typ [4 + (i - 1) * 10 + j] = typ [4 + j];
			sea [4 + (i - 1) * 10 + j] = sea [4 + j];
			land[4 + (i - 1) * 10 + j] = land[4 + j];
		}+/
		own [i*10 - 6 .. i*10 + 4] = i;
		typ [i*10 - 6 .. i*10 + 4] = typ [4..14];
		sea [i*10 - 6 .. i*10 + 4] = sea [4..14];
		land[i*10 - 6 .. i*10 + 4] = land[4..14];
	}
}

/*********************************
 * Save the game in filename.
 * Returns:
 *		0		success
 *		!=0		error
 */

int var_savgam(char* filename)
{
	FILE* fp;
	char r;
	size_t n;
	int i;

	fp = fopen(filename,"wb");
	if (fp == null) goto err;
	n = &savend - &savbeg;
	if (fwrite(&savbeg, 1, n, fp) != n)
		goto err2;
	n = CITMAX;
	if (fwrite(city, City.sizeof, n, fp) != n)
		goto err2;
	n = UNIMAX;
	if (fwrite(unit, Unit.sizeof, n, fp) != n)
		goto err2;
	n = PLYMAX + 1;
	if (fwrite(player, Player.sizeof, n, fp) != n)
		goto err2;

	player[0].map = .map;
	for (i = 1; i <= numply; i++)
	{
		n = MAPSIZE;
		if (fwrite(player[i].map, map[0].sizeof, n, fp) != n)
		goto err2;
	}

	if (fclose(fp) == -1) goto err;
	return 0;

	err2:
		fclose(fp);
	err:
		return 1;
}


/******************************
 * Restore game from fp.
 * Returns:
 *		false  success
 *		true   error
 */

bool resgam(FILE* fp)
{
	size_t n;
	int i;

	n = &savend - &savbeg;
	if (fread(&savbeg, 1, n, fp) != n)
	goto err2;
	n = CITMAX;
	if (fread(city, City.sizeof, n, fp) != n)
	goto err2;
	n = UNIMAX;
	if (fread(unit, Unit.sizeof, n, fp) != n)
	goto err2;
	n = PLYMAX + 1;
	if (fread(player, Player.sizeof, n, fp) != n)
	goto err2;

	player[0].map = .map;
	for (i = 1; i <= numply; i++)
	{
		n = MAPSIZE;
		player[i].map = new ubyte[MAPSIZE];
		if (fread(player[i].map, map[0].sizeof, n, fp) != n)
		goto err2;
		player[i].usv = null;
	}

	if (fclose(fp) == -1) goto err;

	return false;

err2:
	fclose(fp);
err:
	return true;	// false here apparently was a typo in Stewart code.
}
