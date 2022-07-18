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

import core.sys.windows.windows;
import core.thread; // for sleep()
import std.string;

import empire;
import eplayer;
import winmain;
import maps;
import var;


private {
	struct UnitName {
		char   abbrev;
		char[] singular;
		char[] plural;
		char[] withArticle;

		char[] sOrP(uint howMany) {
			return howMany == 1 ? singular : plural;
		}
	}

	const UnitName[] unitName = [
		{ 'A', "army",             "armies",            "n army"             },
		{ 'F', "fighter",          "fighters",          " fighter"           },
		{ 'D', "destroyer",        "destroyers",        " destroyer"         },
		{ 'T', "troop transport",  "troop transports",  " troop transport"   },
		{ 'S', "submarine",        "submarines",        " submarine"         },
		{ 'R', "cruiser",          "cruisers",          " cruiser"           },
		{ 'C', "aircraft carrier", "aircraft carriers", "n aircraft carrier" },
		{ 'B', "battleship",       "battleships",       " battleship"        }
	];
}


// For each display

class NewDisplay {
	StatusPanel panel;
	int timeinterval;   // 100ths of a second msg delay time
	//uint maptab;      // map values for the players

	int secbas = -1;    // position of upper left corner of sector
	uint Smin = 0;      // row,col coordinates of upper left sector display
	uint Smax = 11 * 256 + 11; // row,col coordinates of lower right sector display

	//bool cursorHidden = false;

	this()
	{
		panel = new StatusPanel;
	}

	/***************************
	 * Print out map value at loc.
	 */

	void mapprt(loc_t loc)
	{
		if (!panel.isActive) return;
		assert(loc < MAPSIZE);
		if (!insect(loc, 0)) return;  // if not in current sector

		invalidateLoc(loc);
	}

	/***************************
	 * Return true if loc is in the current sector showing,
	 * with a border of n spaces. If the sector edge lies on
	 * a map edge, the n spaces do not apply for that edge.
	 * Return false if secbas[] = -1.
	 */

	int insect(loc_t loc, uint n)
	{
		int br, bc, lr, lc;
		int x;
		int sb;

		assert(loc < MAPSIZE && n < 100);
		sb = secbas;
		if (sb == -1)
			return false;
		br = sb / (Mcolmx + 1);
		bc = sb % (Mcolmx + 1);

		lr = loc / (Mcolmx + 1);
		lc = loc % (Mcolmx + 1);

		x = (br) ? br + n : br;				// min row we can be on
		if (lr < x) return false;

		x = (bc) ? bc + n : bc;				// min col we can be on
		if (lc < x) return false;

		br += (Smax - Smin) >> 8;
		bc += (Smax - Smin) & 0xFF;

		x = (br != Mrowmx) ? br - n : br;		// max row we can be on
		if (lr > x) return false;

		x = (bc != Mcolmx) ? bc - n : bc;		// max col we can be on
		return lc <= x;
	}

	/************************************
	 * Adjust loc so it makes a valid sector base.
	 */

	loc_t adjust(loc_t loc)
	{
		int row, col, size, rowsize, colsize;

		row = ROW(loc);
		col = COL(loc);
		if (col == Mcolmx)                  // kludge to fix wrap-around
		{
			col = 0;
			row++;
		}
		size = Smax - Smin;                 // display size
		rowsize = size >> 8;                // # of rows - 1
		colsize = size & 0xFF;
		if (row < 0) row = 0;
		if (row > Mrowmx - rowsize) row = Mrowmx - rowsize;
		if (col < 0) col = 0;
		if (col > Mcolmx - colsize) col = Mcolmx - colsize;
		return (row * (Mcolmx + 1) + col);  // return adjusted value
	}

	int rusure()
	{
		version (idiotproof) {
			char s;

			panel[3] = "Are you sure (Y or N)?";
			s = getKeystroke();
			panel[3] = null;
			return s == 'Y';
		} else {
			return 1;
		}
	}

	/**********************
	 */

	void city_attackown()
	{
		panel[2] = "Attacked your own city!";
		if (panel.isActive) sound_gun();
		panel[3] = "Your army was executed.";
		delay(1);
	}

	/*****************
	 */

	void city_repelled(loc_t loc)
	{
		panel[2] = format("City under attack at %s.", locToString(loc));
		if (panel.isActive) sound_subjugate();
		panel[3] = "Enemy invasion repelled.";
		delay(1);
	}

	/**********
	 * Your city was conquered.
	 */

	void city_conquered(loc_t loc)
	{
		panel[2] = format("City under attack at %s.", locToString(loc));
		if (panel.isActive) sound_crushed();
		panel[3] = "Your city was conquered!";
		delay(1);
	}

	/**************************
	 */

	void city_subjugated()
	{
		panel[2] = "Attacking city";
		panel[3] = null;
		if (panel.isActive) sound_subjugate();

		panel[2] = "The city has been subjugated! The army";
		panel[3] = "was dispersed to enforce iron control.";
		delay(1);
	}

	/**************************
	 */

	void city_crushed()
	{
		panel[2] = "Attacking city!";
		panel[3] = null;
		if (panel.isActive) sound_crushed();

		panel[2] = "The city's defenses crushed your assault!";
		panel[3] = "Your army destroyed.";
		delay(1);
	}

	/**********************
	 * Print number of units destroyed
	 */

	void killml(int type, int num)
	{
		panel[3] = format("%d %s destroyed.", num, unitName[type].sOrP(num));
		delay(3);
	}

	/*************************************
	 * Overloaded T or C.
	 */

	void overloaded(loc_t loc, int typabd, int numdes)
	{
		panel[2] = format("Your ship is overloaded at %d,%d.",
		  ROW(loc),  COL(loc));
		killml(typabd, numdes);		// print message
		if (panel.isActive) sound_aground();
	}

	/************************************
	 * Type out the heading of the unit.
	 */

	void headng(Unit* u)
	{
		int type, abd;
		char[] buffer;

		if (u.typ == A)
		{
			buffer = format("Your army at %s.", locToString(u.loc));
		}
		else
		{
			buffer = format("Your %s at %s.", unitName[u.typ].singular,
			  locToString(u.loc));

			if ((type = tcaf(u)) >= 0)				// if we have a T or C
			{
				abd = aboard(u);
				buffer ~= format(" %d %s aboard.", abd,
				  unitName[type].sOrP(abd));

			}
			if (u.typ == F) {  // if a fighter
				buffer ~= " Range: ";
			} else {           // else ship
				buffer ~= " Hits: ";
			}
			buffer ~= format("%d", u.hit);
		}
		panel[0] = buffer;
		fncprt(u);								// print function
	}

	void landing(Unit* u)
	{
		panel[1] = format("Landing confirmed at %d,%d.",
		  ROW(u.loc), COL(u.loc));
		delay(2);
	}

	void boarding(Unit* u)
	{
		panel[1] = format("Boarding confirmed at %d,%d.",
		  ROW(u.loc), COL(u.loc));
		delay(2);
	}

	void aground(Unit* u)
	{
		panel[1] = "Your ship ran aground and sank.";
		if (panel.isActive) sound_aground();
	}

	void armdes(Unit* u)
	{
		panel[1] = "Your army was destroyed.";
	}

	void drown(Unit* u)
	{
		panel[1] = "Your army marched into the sea and drowned!";
		if (panel.isActive) sound_splash();
	}

	void shot_down(Unit* u)
	{
		panel[2] = "Fighter attacks city!";
		if (panel.isActive) {
			sound_flyby();
			sound_ackack();
			sound_ackack();
		}
		panel[3] = "Fighter shot down!";
		if (panel.isActive) sound_fcrash();
	}

	void no_fuel(Unit* u)
	{
		panel[2] = "Fighter ran out of fuel...";
		if (panel.isActive) sound_fuel();
		panel[3] = "...and crashed!";
		if (panel.isActive) sound_fcrash();
	}

	void docking(Unit* u, loc_t loc)
	{
		panel[1] = "Ship docked at " ~ locToString(loc) ~ ".";
	}

	/***************************************
	 * Unit u is under attack.
	 */

	void underattack(Unit* u)
	{
		panel[2] = format("Your %s is under attack at %s.",
		  unitName[u.typ].singular, locToString(u.loc));
		delay(2);
	}


	/***************************************
	 * Perform battle.
	 * Input:
	 *	pnum	player number for this display
	 *	uwin	winner
	 *	ulos	loser
	 */

	void battle(Player* p, Unit* uwin, Unit* ulos)
	{
		char[] p1;
		char[] p2;

		int abd;

		panel[2] = format("%s%s destroyed.", youene_p(p, ulos.own),
		  unitName[ulos.typ].singular);
		abd = aboard(ulos);
		if (abd)
			killml(tcaf(ulos), abd);
		if (uwin.typ != A && uwin.typ != F)
		{
			p1 = youene_p(p,uwin.own);
			p2 = unitName[uwin.typ].singular;
			if (uwin.hit == 1) {
				panel[3] = format("%s%s has 1 hit left", p1, p2);
			} else {
				panel[3] = format("%s%s has %d hits left", p1, p2, uwin.hit);
			}
		}

		if (panel.isActive) {
			ShowBlast(1, ulos.loc);
			switch (ulos.typ)
			{
				case A:
					sound_gun();
					break;
				case F:
					sound_ackack();
					break;
				default:
					sound_bang();
			}
			ShowBlast(0, ulos.loc);
		}
	}

	/*************************************
	 */

	char[] youene_p(Player* p,int num)
	{
		return (p.num == num) ? "Your " : "Enemy ";
	}

	/******************************
	 * Notify player that pdef has been defeated.
	 */

	void plyrcrushed(Player* pdef)
	{
		panel[2] = format("Player %d has been crushed.", pdef.num);
		panel[3] = null;
		if (panel.isActive) sound_taps();
		delay(4);
	}

	/***********************************
	 * Notify player that he's lost.
	 */

	void lost()
	{
		panel[0] = "The enemy has crushed your feeble forces!";
		panel[1] = "Your contemptible dreams of world";
		panel[2] = "Empire are finished!";
		panel[3] = null;
		delay(10);
		global.dirty = false;
	}

	/**************************************
	 */

	void produce(City* c)
	{
		panel[0] = format("City at %d,%d has completed a%s.",
		  ROW(c.loc), COL(c.loc), unitName[c.phs].withArticle);
	}

	/**********************************
	 * Print function of unit.
	 */

	void fncprt(Unit* u)
	{
		static char[9] dtab = "DEWQAZXC";		// directions
		Player* p = Player.get(u.own);

		if (p.human)						// if human player
		{
			char[] buffer;
			if (u.ifo != fnAW)
				buffer = "Function: ";
			final switch (u.ifo)
			{
				case fnAW:
					//t.smes("None");
					break;
				case fnSE:
					buffer ~= "Sentry";
					break;
				case fnRA:
					buffer ~= "Random";
					break;
				case fnMO:
					buffer ~= "Move To " ~ locToString(u.ila);
					break;
				case fnDI:
					buffer ~= "Direction = " ~ dtab[u.ila];
					break;
				case fnFI:
					buffer ~= (u.typ == T) ? "Load Armies" : "Load Fighters";
					break;
			}
			panel[1] = buffer;
		}
		else		// else computer
		{
			panel[1] = format("IFO: %d ILA: %s.", u.ifo, locToString(u.ila));
		}
	}

	/********************************
	 * Position cursor where loc is.
	 */

	void pcur(loc_t loc)
	{
		version (Windows)
		{
			loc_t oldloc;

			assert (panel !is null);
			if (!panel.isActive)
				return;
			assert(loc < MAPSIZE);
			if (global.cursor == loc)
				return;

			oldloc = global.cursor;
			global.cursor = loc;
			//cursorHidden = false;
			debug MessageBoxA(global.hwnd, "Entering adjSector", "Debug",
			  MB_OK);
			if (adjSector(global.scalex, global.scaley)) {
				debug MessageBoxA(global.hwnd, "adjSector returned false", "Debug",
				  MB_OK);
				InvalidateRect(global.hwnd, &global.sector, false);
			} else {
				debug MessageBoxA(global.hwnd, "adjSector returned false", "Debug",
				  MB_OK);
				assert (global.player !is null);
				if (global.player.mode == mdTO)
				{
					invalidateLocRect(global.player.frmloc, oldloc);
					invalidateLocRect(global.player.frmloc, loc);
				}
				else if (global.player.mode == mdSURV)
				{
					InvalidateRect(global.hwnd, &global.sector, false);
				}
				else
				{
					invalidateLoc(oldloc);
					invalidateLoc(loc);
				}
			}
		}
		else
		{
			assert(loc < MAPSIZE);
			text.curs(rowcol(loc - secbas) + Smin);
		}
	}

	/*********************************
	 * Remove any sticky messages.
	 */

	void remove_sticky()
	{
		panel[1] = null;
		panel[2] = null;
		panel[3] = null;
	}

	/****************************
	 * Print out list of valid commands per mode.
	 */

	void valcmd(int mode)
	{
		static const char[][] valmsg =
		[
			"valcmd()",                       // just a place holder
			"QWEADZXC,FGHIKLNRSUVY<>,space",  // Move
			"QWEADZXC,FGHIKLNPRSU<>,esc",     // Survey
			"QWEADZXC,esc",                   // Dir
			"QWEADZXC,HKNT<>,esc",            // From To
			"AFDTSRCB"                        // City Prod
		];

		panel[3] = "Valid commands: " ~ valmsg[mode];
		sound_error();
	}

	/************************************
	 */

	void cityProdDemands()
	{
		panel[0] = "City production demands:";
	}

	void delay(int n)
	{
		if (panel.isActive && timeinterval != 0) {
			//sleep(n * timeinterval);
			Thread.sleep( dur!("msecs")( n * timeinterval ) );
		}
	}

	void wakeup()
	{
		panel[2] = "Wakeup performed.";
	}

	static {
		/*******************************
		 * Type data on a city.
		 */

		void typcit(Player* p, City* c)
		{
			NewDisplay d = p.display;

			if (c.phs == -1)
				return;		// invalid city phase

			char[] buffer = format("Producing: %s Completion: %d",
			  unitName[c.phs].plural, c.fnd);
			if (p.human && c.fipath) {
				buffer ~= format(" Fipath: %s", locToString(c.fipath));
			}
			d.panel[1] = buffer;
		}

		/***********************************
		 * Save game.
		 */

		void savgam()
		{
			StatusPanel sp = player[plynum].display.panel;

			sp[3] = "Saving game...";

			if (save(global.hwnd, false))
			{
				sp[3] = "Game saved.";
			}
			else
			{
				sp[3] = null;
			}
		}

		char[] locToString(loc_t loc) {
			return format("%d,%d", ROW(loc), COL(loc));
		}
	}
}


/***
 *	Text status panel.
 *
 *	To do:
 *		Implement the front end for platforms other than Windows.
 */

class StatusPanel {
	public {
		char[] opIndex(uint i) {
			// no need to dup it - Empire never modifies it after retrieval
			return displayLine[i];
		}

		char[] opIndexAssign(char[] line, uint i) {
			// no need to dup it - Empire never modifies it after setting
			displayLine[i] = line;
			if (isActive) refresh();
			return line;
		}

		version (Windows) {
			static void refresh() {
				win_flush();
			}
		} else {
			static assert (false,
			  "StatusPanel implemented only on Windows");
		}

		bool isActive;
	}

	private {
		char[][12] displayLine;
	}
}
