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


import core.stdc.stdlib;
import core.thread; // for sleep()
import std.string;
import core.sys.windows.windows;

import empire;
import eplayer;
import text;
import winmain;
import maps;
import var;

/***
 *	For each display
 *
 *	Deprecated:
 *		Superseded by NewDisplay.  However, non-Windows versions will still
 *		need this until StatusPanel is implemented for the platform.
 */
//deprecated
struct Display
{
	Text text;
	int timeinterval;   // 100ths of a second msg delay time
	uint maptab;        // map values for the players

	int secbas;     // position of upper left corner of sector
	uint Smin;      // text row,col coordinates of upper left sector display
	uint Smax;      // text row,col coordinates of lower right sector display

	/***********************************
	 * Clear the current sector that's showing.
	 */

	void clrsec()
	{
		//Display* d = this;
		//Text* t = &text;

		//t.cmes(d.Smin," ");				// " " because of bug in BIOS
		//t.deleos();						// delete to end of screen

		this.secbas = -1;						// indicate screen is blank
	}


	/***************************
	 * Print out map value at loc.
	 */

	void mapprt(loc_t loc)
	{
		int x;
		//Display* d = this;
		Text* t = &text;

		if (!t.watch) return;
		assert(loc < MAPSIZE);
		if (!insect(loc,0)) return;				// if not in current sector

		invalidateLoc(loc);
	}


	/***************************
	 * Return true if loc is in the current sector showing,
	 * with a border of n spaces. If the sector edge lies on
	 * a map edge, the n spaces do not apply for that edge.
	 * Return false if secbas[] = -1.
	 */

	int insect(loc_t loc,uint n)
	{
		int br,bc,lr,lc;
		int x;
		int sb;
		//Display* d = this;

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
		int row,col,size,rowsize,colsize;
		//Display* d = this;

		row = ROW(loc);
		col = COL(loc);
		if (col == Mcolmx)						// kludge to fix wrap-around
		{
			col = 0;
			row++;
		}
		size = Smax - Smin;						// display size
		rowsize = size >> 8;						// # of rows - 1
		colsize = size & 0xFF;
		if (row < 0) row = 0;
		if (row > Mrowmx - rowsize) row = Mrowmx - rowsize;
		if (col < 0) col = 0;
		if (col > Mcolmx - colsize) col = Mcolmx - colsize;
		return (row * (Mcolmx + 1) + col);		// return adjusted value
	}

	void initialize()
	{
		//memset(&text,0,text.sizeof);
		text = Text.init;
		text.watch = DAnone;
		text.TTtyp = 0;
		text.cursor = 0;
		text.speaker = 1;
		text.Tmax = (23 << 8) + 78;

		text.narrow = 0;
		maptab = 0;
		timeinterval = 0;
		secbas = -1;
		Smin = 0x400;
		Smax = text.Tmax - ((1 << 8) + 2);

		version (Windows)
		{
			Smin = 0;
			Smax = 11 * 256 + 11;		// 12*12 display
		}
	}

	int rusure()
	{
		version (idiotproof) {
			char s;

			text.cmes(text.DS(3),"Are you sure (Y or N)? N\1\b");
			s = toupper(text.TTin());
			text.output(s);								// echo
			return s == 'Y';
		} else {
			return 1;
		}
	}

	void your()
	{
		text.smes(text.narrow ? "Yr " : "Your ");
	}


	void enemy()
	{
		text.smes(text.narrow ? "En " : "Enemy ");
	}

	/**********************
	 */

	void city_attackown()
	{
		Text* t = &text;

		t.cmes(text.DS(2), "Attacked your own city!\1\2");
		t.cmes(text.DS(3), "\1");
		if (t.watch)
			sound_gun();
		t.cmes(text.DS(3),"Your army was executed.\1\2");
		delay(1);
	}

	/*****************
	 */

	void city_repelled(loc_t loc)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.TTcurs(text.DS(2));
			t.vsmes(format("City under attack at %u,%u.",ROW(loc),COL(loc)));
			t.deleol();				// delete to end of line
			sound_subjugate();
			t.cmes(text.DS(3),"Enemy invasion repelled.\1\2");
			delay(1);
		}
	}

	/**********
	 * Your city was conquered.
	 */

	void city_conquered(loc_t loc)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.TTcurs(text.DS(2));
			t.vsmes(format("City is under attack at %u,%u.",ROW(loc),COL(loc)));
			t.deleol();				// delete to end of line
			sound_crushed();
			t.cmes(text.DS(3),"Your city was conquered!\1\2");
			delay(1);
		}
	}

	/**************************
	 */

	void city_subjugated()
	{
		Text* t = &text;

		if (t.watch)
		{
			t.cmes(text.DS(2),"Attacking city!\1");
			t.cmes(text.DS(3),"\1");
			sound_subjugate();
			if (t.narrow > 1)
			{
				t.cmes(text.DS(2),"City subjugated! Army\1");
				t.cmes(text.DS(3),"enforces iron control.\1\2");
			}
			else
			{
				t.cmes(text.DS(2),"The city has been subjugated! The army\1");
				t.cmes(text.DS(3),"was dispersed to enforce iron control.\1\2");
			}
			delay(1);
		}
	}

	/**************************
	 */

	void city_crushed()
	{
		Text* t = &text;

		if (t.watch)
		{
			t.cmes(text.DS(2),"Attacking city!\1");
			t.cmes(text.DS(3),"\1");
			sound_crushed();
			if (t.narrow > 1)
			{
				t.cmes(text.DS(2), "Your assault crushed!\1");
				t.cmes(text.DS(3), "Your army destroyed.\1\2");
			}
			else
			{
				t.cmes(text.DS(2),text.narrow
						? "The city crushed your assault!\1\2"
						: "The city's defenses crushed your assault!\1\2");
				t.cmes(text.DS(3),"Your army destroyed.\1\2");
			}
			delay(1);
		}
	}

	/**********************
	 * Print number of units destroyed
	 */

	void killml(int type,int num)
	{
		Text* t = &text;
		if (t.watch)
		{
			t.curs(text.DS(3));
			t.vsmes(format("%d %s destroyed.",num, nmes_p(type,num)));
			t.deleol();
			delay(3);
		}
	}

	/*************************************
	 * Overloaded T or C.
	 */

	void overloaded(loc_t loc,int typabd,int numdes)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.curs(text.DS(2));
			t.vsmes(format("Your ship is overloaded at %u,%u.",ROW(loc),COL(loc)));
			t.deleol();
			killml(typabd,numdes);		// print message
			sound_aground();
		}
	}

	/************************************
	 * Type out the heading of the unit.
	 */

	void headng(Unit* u)
	{
		int type, abd;
		Text* t = &text;
		//char* y;
		//char buffer[100];
		string y;
		string buffer;

		if (!t.watch)
			return;
		t.curs(text.DS(0));
		if (u.typ == A)
		{
			//sprintf(buffer,"Your army at %u,%u.", ROW(u.loc), COL(u.loc));
			buffer = format("Your army at %d,%d.", ROW(u.loc), COL(u.loc));
		}
		else
		{
			//char buf[10+1];

			y = text.narrow ? "Yr" : "Your";
			//sprintf(buffer,"%s %s at %u,%u.",y,nmes_p(u.typ,1),ROW(u.loc),COL(u.loc));
			buffer = format("%s %s at %d,%d.", y, nmes_p(u.typ, 1),
			  ROW(u.loc), COL(u.loc));

			if ((type = tcaf(u)) >= 0)				// if we have a T or C
			{
				/+char buf[10];

				abd = aboard(u);				// # aboard
				sprintf(buf," %d ",abd);
				strcat(buffer,buf);
				strcat(buffer,nmes_p(type,abd));
				strcat(buffer," aboard.");+/
				abd = aboard(u);
				buffer ~= format(" %d %s aboard.", abd, nmes_p(type,abd));

			}
			if (u.typ == F) {				// if a fighter
				//strcat(buffer," Range: ");
				buffer ~= " Range: ";
			} else {								// else ship
				//strcat(buffer," Hits: ");
				buffer ~= " Hits: ";
			}
			/+sprintf(buf,"%d",u.hit);
			strcat(buffer,buf);+/
			buffer ~= format("%d", u.hit);
		}
		t.smes(buffer);
		t.deleol();
		t.curs(text.DS(1));
		fncprt(u);								// print function
	}


	/*********************
	 * Type out unit message, plural or singular
	 */

	string nmes_p(int type,int num)
	in
	{
		assert(0 <= type && type < TYPMAX);
	}
	do
	{
		static string[2][8] msg =
		[
			[ "army",             "armies"            ],
			[ "fighter",          "fighters"          ],
			[ "destroyer",        "destroyers"        ],
			[ "troop transport",  "troop transports"  ],
			[ "submarine",        "submarines"        ],
			[ "cruiser",          "cruisers"          ],
			[ "aircraft carrier", "aircraft carriers" ],
			[ "battleship",       "battleships"       ]
		];

		// For narrow displays
		static char[3][2][8] msgn =
		[
			[ "A","As" ],
			[ "F","Fs" ],
			[ "D","Ds" ],
			[ "T","Ts" ],
			[ "S","Ss" ],
			[ "R","Rs" ],
			[ "C","Cs" ],
			[ "B","Bs" ]
		];

		if (text.narrow)
			return (num == 1) ? msgn[type][0] : msgn[type][1];
		else
			return (num == 1) ? msg[type][0] : msg[type][1];
	}


	void landing(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.curs(text.DS(1));
			t.vsmes(format("Landing confirmed at %u,%u.",ROW(u.loc),COL(u.loc)));
			t.deleol();
			delay(2);
		}
	}

	void boarding(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.curs(text.DS(1));
			t.vsmes(format("Boarding confirmed at %u,%u.",ROW(u.loc),COL(u.loc)));
			t.deleol();
			delay(2);
		}
	}

	void aground(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			if (t.narrow > 1)
				t.cmes(text.DS(1),"Ship ran aground, sank.\1\2");
			else
				t.cmes(text.DS(1),"Your ship ran aground and sank.\1\2");
			sound_aground();
		}
	}

	void armdes(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
			t.cmes(text.DS(1),"Your army was destroyed.\1\2");
	}

	void drown(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			if (t.narrow > 1)
			{
				t.cmes(text.DS(1),"Army marched into sea!\1");
			}
			else
			{
				t.curs(text.DS(1));
				your();
				t.vsmes(format("%s marched into the sea and drowned!",nmes_p(A,1)));
				t.imes("\1\2");
			}
			sound_splash();
		}
	}

	void shot_down(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.cmes(text.DS(2),"Fighter attacks city!\1");
			sound_flyby();
			sound_ackack();
			sound_ackack();
			t.cmes(text.DS(3),"Fighter shot down!\1");
			sound_fcrash();
		}
	}

	void no_fuel(Unit* u)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.cmes(text.DS(2), "Fighter ran out of fuel...\1\2");
			sound_fuel();
			t.cmes(text.DS(3), "...and crashed!\1\2");
			sound_fcrash();
		}
	}

	void docking(Unit* u, loc_t loc)
	{
		Text* t = &text;

		if (t.watch)
		{
			t.cmes(text.DS(1), "Ship docked at \1");
			t.locdot(loc);
			t.deleol();
		}
	}

	/***************************************
	 * Unit u is under attack.
	 */

	void underattack(Unit* u)
	{
		Text* t = &text;
		if (t.watch)
		{
			//char* p;

			t.curs(text.DS(2));
			/+p = text.narrow ? "Yr" : "Your";
			t.vsmes("%s %.*s is under attack at %u,%u.",
				p,nmes_p(u.typ,1),ROW(u.loc),COL(u.loc));+/
			t.smes(format("%s %s is under attack at %d,%d.",
			  text.narrow ? "Yr" : "Your", nmes_p(u.typ, 1),
			  ROW(u.loc),COL(u.loc)));
			t.deleol();
			delay(2);
		}
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
		string p1;
		string p2;
		Text* t = &text;

		if (t.watch)
		{
			int abd;

			t.curs(text.DS(2));
			//t.vsmes("%s%.*s destroyed.",youene_p(p,ulos.own),nmes_p(ulos.typ,1));
			t.smes(format("%s%s destroyed.", youene_p(p, ulos.own),
			  nmes_p(ulos.typ, 1)));
			t.deleol();
			abd = aboard(ulos);
			if (abd)
				killml(tcaf(ulos),abd);
			t.curs(text.DS(3));
			if (uwin.typ != A && uwin.typ != F)
			{
				p1 = youene_p(p,uwin.own);
				p2 = nmes_p(uwin.typ,1);
				if (uwin.hit == 1)
					//t.vsmes("%s%.*s has 1 hit left",p1,p2);
					t.smes(format("^%s%s has 1 hit left", p1, p2));
				else
					//t.vsmes("%s%.*s has %d hits left",p1,p2,uwin.hit);
					t.smes(format("%s%s has %d hits left", p1, p2, uwin.hit));
			}
			t.deleol();
			t.flush();

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
					break;
			}
			ShowBlast(0, ulos.loc);
		}
	}

	/*************************************
	 */

	string youene_p(Player* p,int num)
	{
		if (p.num == num)
		{
			return text.narrow ? "Yr " : "Your ";
		}
		else
		{
			return text.narrow ? "En " : "Enemy ";
		}
	}

	/******************************
	 * Notify player that pdef has been defeated.
	 */

	void plyrcrushed(Player* pdef)
	{
		Text* t = &text;
		if (t.watch)
		{
			t.cmes(text.DS(2),"Player ");
			t.decprt(pdef.num);
			t.imes(" has been crushed.\1\2");
			t.curs(text.DS(3));
			t.deleol();
			sound_taps();
			delay(4);
		}
	}

	/***********************************
	 * Notify player that he's lost.
	 */

	void lost()
	{
		Text* t = &text;
		if (t.watch)
		{
			t.cmes(text.DS(0),"The enemy has crushed your feeble forces!\1");
			t.cmes(text.DS(1),"Your contemptible dreams of world\1");
			t.cmes(text.DS(2),"Empire are finished!\1");
			t.cmes(text.DS(3),"\1");
			delay(10);
			global.dirty = false;
		}
	}

	/**************************************
	 */

	void produce(City* c)
	{
		Text* t = &text;
		if (t.watch)
		{
			t.curs(text.DS(0));
			string p = (c.phs == A || c.phs == C) ? "n" : "";
			t.vsmes(format("City at %u,%u has completed a%s %s.",
					ROW(c.loc),COL(c.loc),p,nmes_p(c.phs,1)));
			t.imes("\1\2");
		}
	}

	/**************************************
	 */

	void overpop(int flag)
	{
		if (text.watch)
		{
			//text.cmes(text.DS(2),flag ? "Overpop" : "	   ");
		}
	}

	/**********************************
	 * Print function of unit.
	 */

	void fncprt(Unit* u)
	{
		static char[9] dtab = "DEWQAZXC";		// directions
		Player* p = Player.get(u.own);
		Text* t = &text;

		if (!t.watch)						// if not watching this guy
			return;
		if (p.human)						// if human player
		{
			if (u.ifo != fnAW)
				t.smes("Function: ");
			switch (u.ifo)
			{
				case fnAW:
					//t.smes("None");
					break;
				case fnSE:
					t.smes("Sentry");
					break;
				case fnRA:
					t.smes("Random");
					break;
				case fnMO:
					t.smes("Move To ");
					t.locprt(u.ila);
					break;
				case fnDI:
					t.smes("Direction = ");
					t.output(dtab[u.ila]);
					break;
				case fnFI:
					t.smes("Load ");
					if (u.typ == T)
						t.smes("Armies");
					else
						t.smes("Fighters");
					break;
				default:
					assert(0);
			  }
		}
		else		// else computer
		{
			t.smes("IFO: ");
			t.decprt(u.ifo);
			t.smes(" ILA: ");
			t.locdot(u.ila);
		}
		t.deleol();
	}

	/************************************
	 */

	void setdispsize(int rows,int cols)
	{
		//PRINTF("Display::setdispsize(rows=%d, cols=%d)\n",rows,cols);

		version (Windows)
		{
			version (0)
			{
				text.narrow = 0;
				if (global.cxClient < 75 * 10)
					text.narrow = 1;
				if (global.cxClient <= 12 * 10)
					text.narrow = 2;
			}
			else
			{
				text.narrow = (cols < 75);		// use 40 column formatting
				text.narrow = 2;
			}
			text.Tmax = (rows - 1) * 256 + cols - 1;
		}
		else
		{
			text.narrow = (cols < 75);		// use 40 column formatting
			if (text.narrow)
				Smin = (5 * 256) + 0;				// u l edge of map
			else
				Smin = (4 * 256) + 0;

			text.Tmax = (rows - 1) * 256 + cols - 1;

			// Scale back if display is bigger than we can use
			if (cols > Mcolmx + 1 + 3 - 1)
				cols = Mcolmx + 1 + 3 - 1;
			if (rows > 4 + Mrowmx + 1 + 1)
				rows = 4 + Mrowmx + 1 + 1;

			Smax = (rows - 2) * 256 + cols - 3;
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

			if (!text.watch)
				return;
			assert(loc < MAPSIZE);
			if (global.cursor == loc)
				return;

			oldloc = global.cursor;
			global.cursor = loc;
			if (adjSector(global.scalex, global.scaley))
				InvalidateRect(global.hwnd, &global.sector, false);
			else
			{
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
		Text* t = &text;

		if (t.watch)
		{
			t.curs(text.DS(1)); t.deleol();
			t.curs(text.DS(2)); t.deleol();
			t.curs(text.DS(3)); t.deleol();
		}
	}

	/****************************
	 * Print out list of valid commands per mode.
	 */

	void valcmd(int mode)
	{
		static string[] valmsg =
		[
			"valcmd()",                       // just a place holder
			"QWEADZXC,FGHIKLNRSUVY<>,space",  // Move
			"QWEADZXC,FGHIKLNPRSU<>,esc",     // Survey
			"QWEADZXC,esc",                   // Dir
			"QWEADZXC,HKNT<>,esc",            // From To
			"AFDTSRCB"                        // City Prod
		];
		//Text* t = &text;

		text.curs(text.DS(3));
		if (!text.narrow)
			text.smes("Valid commands: ");
		text.smes(valmsg[mode]);
		text.deleol();
		sound_error();
	}

	/************************************
	 */

	void cityProdDemands()
	{
		Text* t = &text;
		t.cmes(t.DS(0),"City production demands: \1");
	}

	void delay(int n)
	{
		//Display* d = this;

		if (text.watch)
		{
			text.flush();
			if (timeinterval)
				//sleep(n * timeinterval);
				Thread.sleep( dur!("msecs")( n * timeinterval ) );
		}
	}

	void wakeup()
	{
		text.cmes(text.DS(2),"Wakeup performed.\1\2");
	}

}

/*******************************
 * Type data on a city.
 */

void typcit(Player* p, City* c)
{
	version (NewDisplay) {}
	else {
		Display* d = p.display;
		Text* text= &(d.text);

		if (text.watch)
		{
			if (c.phs == -1)
				return ;        // invalid city phase
			text.cmes(text.DS(1),text.narrow ? "Prod: " : "Producing: ");
			text.vsmes(format("%s Completion: %d",d.nmes_p(c.phs,2),c.fnd));
			if (p.human && c.fipath)
				text.vsmes(format(" Fipath: %u,%u",ROW(c.fipath),COL(c.fipath)));
			text.deleol();
		}
	}
}

/***********************************
 * Save game.
 */

void savgam()
{
	version (NewDisplay) {}
	else {
		Text* t = &(var.player[plynum].display.text);

		t.cmes(t.DS(3),"Saving game...\1");
		if (var_savgam("empire.dat"))
		{
			t.cmes(t.DS(3),"Error writing EMPIRE.DAT\1");
		}
		else
		{
			t.cmes(t.DS(3),"Game saved.\1");
		}
	}
}

/******************************
 * Type out values of strategy variables.
 */

void lstvar()
{
	version (NewDisplay) {}
	else {
		int i,j,k,ene;
		Player* p = Player.get(2);
		Text* t = &(p.display.text);

		ene = 2;                            // get computer player number
		p.display.clrsec();                 // clear section of screen

		t.cmes(0x500,"TARGET\t");
		for (i = 0; i < CITMAX; i++)        // loop thru cities
		{
			if (p.target[i])                // if it's a target
			{
				t.locprt(city[i].loc);
				t.output('\t');
			}
		}

		t.cmes(0x600,"NUMUNI\t");
		for (i = 0; i < 8; i++)
		{
			t.decprt(p.numuni[i]);
			t.output('\t');
		}

		t.cmes(0x700,"NUMPHS\t");
		for (i = 0; i < 8; i++)
		{
			t.decprt(p.numphs[i]);
			t.output('\t');
		}

		t.curs(0x800);
		t.smes("NUMOWN "); t.decprt(p.numown);
		t.smes(" NUMTAR "); t.decprt(p.numtar);

		t.imes("\n\rTROOPT\n\r");
		for (i = 0; i < 6; i++)
		{
			for (k = 0; k < 5; k++)
			{
				t.locprt(p.troopt[i][k] );
				t.output('\t');
			}
			t.crlf();
		}

		t.imes("LOCI\n\r");
		for (i = 0; i < LOCMAX; i++)
		{
			t.locprt(p.loci[i] );
			t.output('\t');
		}
		t.crlf();
	}
}
