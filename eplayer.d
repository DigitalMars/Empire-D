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

module eplayer;

import empire;
import display;
import path;
import move;

// For each player

struct Player
{
    uint num;		// player number (1..numply)
    uint round;		// round number
    ubyte *map;
    int human;		// !=0 if human player
    ubyte watch;	// display attribute DAxxxx if non-zero
    int movedone;	// !=0 if we moved the piece this turn

    int uninum;		// what unit number we're on
    int secflg;		// if next unit has to be in current sector
    ubyte defeat;	// true if player is defeated
    Display *display;
    int turns;		// number of turns completed

    static Player *get(int num) { return &player[num]; }

    // Human player
    Unit *usv;		// current unit pointer
    int mode;		// mdXXXX: input modes
    loc_t curloc;	// current location of cursor
    int frmloc;		// use when in TO mode
    int maxrng;
    int citnum;
    int savmod;
    int nrdy;		// true if we're not ready
    int modsave;

    // Computer strategy
    ubyte target[CITMAX];	// There is a TARGET byte for each city.
				// If the computer knows about the city
				// but doesn't own it, it is true.

    uint troopt[6][5];		// The 6 rows correspond to the ships
				// DTSRCB in that order. The 5 columns
				// correspond to locations of enemy ships
				// discovered, in order from newest to
				// oldest sighting.

    uint loci[LOCMAX];		// Locations of enemy armies sighted,
				// from most to least recent.

    uint numuni[TYPMAX];	// # of units of each type
    uint numown;		// # of our owned cities
    uint numtar;		// # of cities listed as targets
    uint numphs[TYPMAX];	// # of cities producing each type of unit

    /*************************************
     * Give time slice to a player.
     */

    void tslice()
    {   int i;
	Unit *u;
	Player *p = this;

	if (!p.human)
	{   int x;

	    x = p.display.text.TTinr();
	    switch (x)
	    {   case 3:
		    done(1);
		    break;
		case 'S':
		    cwatch();
		    break;
		case 'O':
		    do
			p = p.nextp();
		    while (p.human);
		    exchange_display(p);
		    return;
		default:
		    break;
	    }
	}
	if (numleft == 1)
	    return;

	// Loop through all the units making sure that each unit moves
	// once per round.
	for (; p.uninum < unitop; p.uninum++)
	{
	    i = p.uninum;			// get unit number
	    u = &unit[i];
	    if (u.mov ||			// if unit has already moved
		!u.loc ||			// if unit doesn't exist
		u.own != p.num)		// if the unit isn't ours
		continue;
	    if (p.secflg &&		// if move by sector and
		!p.display.insect(u.loc,2) &&	// not in current sector and
		p.movedone)		// previous move was completed
		    continue;
	    if (p.watch)
		p.secflg = true;		// back to moving by sector
	    p.movedone = p.Mmove(u);	// move the unit
	    if (p.movedone)
		u.mov = true;		// indicate that it's moved
	    return;
	}

	// We've moved all the units for this round that are in this sector.
	p.uninum = 0;			// reset
	if (p.secflg)			// if only in sector showing
	{   p.secflg = false;		// try anybody
	    return;
	}

	// We've moved all the units for this round.
	if (p.watch)			// only by sector if we're watching
	    p.secflg = true;		// back to moving by sector

	
	for (i = unitop; i--;)
	{   u = &unit[i];
	    if (u.own == p.num)
		u.mov = false;		// reset all the unimov entries
	}
	finrnd();				// finish up round
    }

    /*******************
     * Finish up the round for this player.
     */

    void finrnd()
    {
	if (!human)			// if computer player
	    cityph();			// adjust city phases as req'd
	display.remove_sticky();	// remove any 'sticky' messages
	hrdprd(this);			// hardware production
	chkwin();			// see if anybody won
	round++;			// next round
	for (int i = 1; i <= numply; i++)
	    Player.get(i).notify_round(this,round);	// type out the round #
	display.text.flush();
    }


    static int locold;		// previous loc of unit
    static int snsflg;		// set if do sensor for enemy

    /***************************
     * Perform a move for a unit. Return true if
     * move was successfully completed.
     */

    int Mmove(Unit *u)
    {   dir_t r2;
        int e;
        Player *p = this;

        do
        {   p.sensor(u.loc);		// get up to date before move
	    if (p.human)		// if human player
	    {   if (!p.hmove(u,&r2))	// do human move
		    return 0;		// not ready
	    }
	    else	// computer move
	    {   if (!p.cmove(u,&r2))
		    return 0;		// not ready
	    }

	    /*
	     * see if unit was destroyed while in cmove or hmove
	     */

	    if (!u.loc || u.own != p.num)	// unit was destroyed
		break;

	    debug chkmov(r2);		// check for legit move
	    assert(chkloc(u.loc));		// check for valid location

	    e = p.evalu8(u,r2);
      } while (e);

      p.turns = 0;				// reset
      return 1;				// done with this piece
    }

    /*********************************
     * Evaluate the move.
     * Input:
     *	uninum =	unit number
     *	r2 =		move
     * Returns:
     *	true		if we get another move
     */

    int evalu8(Unit *u,dir_t r2)
    {
	loc_t loc = u.loc;		// location of unit
	int type = u.typ;		// what type of unit we have
	int ab = .map[loc];		// what's there
	int ac;
	Player *p = this;
	Display *d = p.display;
	Text *t = &d.text;

      /*
       * perform the move
       */

      locold = loc;			// remember for drag
      snsflg = 0;			// don't do sensor for enemy
      updlst(loc,type);			// fixup map location left
      loc += arrow(r2);			// move to new loc
      ac = .map[loc];			// map value of where we are
      u.loc = loc;			// update unit location

      /*
       * Watch out for an A on a T attempting to attack a ship
       */

      if (type == A && sea[ac] &&
	    .typ[ab] == T && r2 != -1)
      {   d.drown(u);			// can't do this!
	    killit(u);
	    return false;
      }

      /*
       * perform battles as req'd, watch for A on T or F on C
       */

      if (.typ[ac] >= A)				// if ac is a unit
      {   if (.own[ac] == p.num)		// if we own the piece
	    {   if (type == A && .typ[ac] == T)
		{   if (.typ[ab] != T)
		    {   d.boarding(u);		// if A boarding a transport
			eomove(u.loc);
		    }
		    return false;
		}
		if (type == F && .typ[ac] == C)
		{   if (.typ[ab] != C)
		    {
			// if F landing on a carrier
			u.hit = typx[F].hittab;		// reset range of F
			d.landing(u);
			eomove(u.loc);
		    }
		    return false;
		}
	    }
	    else
		snsflg = .own[ac];		// do sensor for enemy
	    if (fight(u,loc))		// if we fight & lose
	    {   killit(u);			// remove the carcass
		return false;		// all done
	    }
	    ac = updmap(loc);		// fix up map
      }

     /*
      * take care of special stuff for armies
      */

      if (type == A)			// if army
      {   if (ac == MAPsea)		// if moving onto sea
	    {   d.drown(u);		// drown him
		killit(u);
	    }
	    else if (ac == MAPland)		// if moving onto land
	    {   change(type,loc,ac);	// update map loc
		eomove(loc);		// do end of move processing
	    }
	    else
	    {
		assert(.typ[ac] == X);
		attcit(loc);		// then must be attacking a city
		killit(u);			// always destroyed
	    }
	    return false;			// all done
      }

      /*
       * take care of special stuff for fighters
       */

      if (type == F)			// if fighter
      {   if (.typ[ac] == X)		// if moving onto a city
	    {   if (.own[ac] == p.num)	// if the city is ours
		{
		    // land the plane
		    u.hit = typx[F].hittab;	// reset range of F
		    d.landing(u);
		    eomove(u.loc);
		}
		else			// unowned city
		{
		    d.shot_down(u);
		    killit(u);		// a fatal error
		}
		return false;
	    }
	    else				// moving onto sea or land
	    {   if (--u.hit)		// if not run out of fuel yet
		    change(type,loc,ac);	// good move
		else			// ran out of fuel
		{
		    d.no_fuel(u);
		    killit(u);
		    return false;
		}
	    }
      }

    /*
     * take care of ships
     */

      if (type >= D)			// take care of ships
      {   if (ac == MAPsea)		// if moving onto sea
		change(type,loc,ac);	// then fix map & we're done
	    else				// ran aground or docked
	    {   if (.own[ac] != p.num)	// if not owned
		{   d.aground(u);		// ran aground
		    killit(u);
		    return false;
		}
		if (u.hit < typx[type].hittab)
		    u.hit++;		// ship in port, repair it
		d.docking(u, loc);
	    }
      }

      eomove(loc);				// do ending sensor probes

      switch (type)
      {
	    case F:
		if (u.hit % 4 == 0)
		    return false;		// if fighter has moved 4
		break;

	    case T:
	    case C:
		p.drag(u);			// drag along As and Fs
	    case D:
	    case S:
	    case R:
	    case B:
		if (p.turns ||			// if already got extra move
		    u.hit <= typx[type].hittab/2)	// or half damaged
		    return false;
		break;

	    default:
		assert(0);
      }

      if (.typ[ac] == X)			// if in city
	    return false;			// then no extra moves
      p.turns++;				// # of turns completed
      return true;				// get another move
    }


    /****************************************
     * Attack city at loc and determine outcome.
     */

    void attcit(loc_t loc)
    {   int ab = .map[loc];
        Player *patt = this;
        Player *pdef = Player.get(own[ab]);
        City *c;

        assert(loc < MAPSIZE);
        c = fndcit(loc);
        if (patt == pdef)
	    patt.display.city_attackown();
        else if (ranq() & 1)			// 50% chance of takeover
        {
	    int mapval;				// city map value
	    int i;

	    pdef.display.city_conquered(loc);
	    patt.display.city_subjugated();

	    pdef.notify_city_lost(c);

	    assert(c.own == pdef.num);
	    mapval = 4 + 10 * (patt.num - 1);	// map val of conquered city
	    assert(.own[mapval] == patt.num);
	    .map[loc] = mapval;			// set reference map
	    snsflg = c.own;			// !=0 if do sensor for enemy
	    c.own = patt.num;			// set new owner

	    /* Destroy any enemy pieces in the city.
	     */

	    for (i = 0; i < unitop; i++)
	    {   Unit *u = &unit[i];

		if (u.loc == loc && u.own != patt.num)
		{
		    assert(u.own == pdef.num);
		    pdef.notify_destroy(u);
		    u.destroy();
		}
	    }

	    c.phs = -1;			// select new phase
	    patt.notify_city_won(c);
        }
        else
        {
	    pdef.notify_city_repelled(c);

	    pdef.display.city_repelled(loc);	// invasion was repelled
	    patt.display.city_crushed();		// assault was crushed
        }
    }

    /*********************************
     * Type out sector indicated by upper left corner loc.
     */

    void sector(loc_t loc)
    {
	Player *p = this;
	Display *d = p.display;
	Text *t = &p.display.text;

	if (!t.watch)
	    return;			// not watching this player

	//if (loc >= MAPSIZE) PRINTF("sector(loc = %d)\n", loc);
	assert(loc < MAPSIZE);

	if (loc == d.secbas)
	    return;			// this sector is already showing
	global.player = p;
	global.ulcorner = loc;
	global.map = map;
	global.offsetx = 0;
	global.offsety = 0;
	d.secbas = loc;			// set new sector base

	invalidateSector();
    }


    /*****************************
     * Do sensor probe around loc. Update player maps, screen and
     * computer player variables. If an enemy is detected, call sensor
     * for him also.
     */

    static int dirtab[9] = [3,2,1,4,-1,0,5,6,7];	// to minimize chars
							// sent to screen
    void sensor(loc_t loc)
    {
      int i,r2,o;
      uint z6;
      ubyte pab,rab;
      Player *p = this;

      debug assert(chkloc(loc));

      for (i = 9; i--;)				// look at 9 directions
      {     r2 = dirtab[i];			// get direction
	    z6 = loc + arrow(r2);		// get new location
	    pab = map[z6];			// get player map value
	    rab = .map[z6];			// and reference map value

	    if (pab != rab)			// if there is a change
	    {   map[z6] = rab;			// update player map
		if (p.watch)
		    p.display.mapprt(z6);	// print map value on screen
		if (!p.human)
		    p.updcmp(z6);		// update computer strat variables
	    }

	    /* Check to see if it's an enemy piece or city. If so, do a sensor
	     * probe about this loc for the enemy.
	     */

	    o = own[rab];
	    if (o && o != p.num)
	    {
		Player *pe = Player.get(o);
		pab = pe.map[loc];
		rab = .map[loc];
		if (pab != rab)			// if there is a change
		{   pe.map[loc] = rab;		// update player map
		    if (pe.watch)
			pe.display.mapprt(loc);	// print map value on screen
		    if (!pe.human)
			pe.updcmp(loc);		// update computer strat variables
		}
	    }

      }
    }


    /*******************************
     * Center the sector about loc.
     */

    void center(loc_t loc)
    {   int row,col,rowsize,colsize,size;
        Player *p = this;
        Display *d = p.display;

      row = ROW(loc);
      col = COL(loc);
      size = d.Smax - d.Smin;		// display size
      rowsize = size >> 8;			// # of rows - 1
      colsize = size & 0xFF;
      row -= rowsize / 2;
      col -= colsize / 2;
      if (row < 0)			row = 0;
      if (row > Mrowmx - rowsize)	row = Mrowmx - rowsize;
      if (col < 0)			col = 0;
      if (col > Mcolmx - colsize)	col = Mcolmx - colsize;
      p.sector(row * (Mcolmx + 1) + col);	// type new sector
    }

    /*******************************
     * Select initial city for player.
     */

    void citsel()
    {   int n;
        loc_t loc;
        City *c;
        Player *p = this;

        do
        {   n = empire.random(CITMAX);	// select a city at random
	    c = &city[n];
	    loc = c.loc;
        }
        while (!loc ||			// if city doesn't exist or
	    edger(loc) == 8 ||		// island city or
	    c.own);			// already owned
        c.own = p.num;			// claim the city
        .map[loc] = 4 + (p.num - 1) * 10;	// set map value
        p.sensor(loc);			// do a sensor probe
        if (p.human)			// if human player
	    p.phasin(c);		// get city phase
        else				// else computer player
	    p.cphasin(c);
    }


/* ===================== Human strategy ===================================== */


    /**********************************
     * Get move from player.
     * Watch out for unit being destroyed while in tty input wait for a move.
     * Input:
     *	u	unit number
     *	pr2	-> where output move is to go
     * Output:
     *	*pr2	move selected (valid only if false is returned)
     * Returns:
     *	0	move not completed
     *	!=0	move successfully completed
     */

    int hmove(Unit *u,dir_t *pr2)
    {   loc_t oldloc;
      int cmd;
      Player *p = this;
      Display *d = p.display;
      Text *t = &d.text;

      assert(u.loc);
      assert(u.own == p.num);

      if (u != p.usv)
	    p.nrdy = 0;			// it's a different unit!
      if (p.nrdy == 1) goto cmdin;		// get command
      if (p.nrdy == 2) goto dirin;		// get direction in cmdI

    bhmove:
      p.usv = u;				// remember unit number
      *pr2 = -1;				// default no move
      if (sursea(u)) return 1;		// if A on T at sea
      if (p.mycode(u,pr2))			// if automatic move
      {
	    t.flush();
    done:	p.setmode(mdNONE);
	    p.chksleep(u,*pr2);		// see if we put it to sleep
	    t.speaker_click();
	    return 1;
      }

      /* Enter movement mode.
       */

    movmod:
      p.curloc = u.loc;			// set current location
      d.headng(u);				// print heading
      if (!d.insect(p.curloc,2))		// if not in current sector
	    center(p.curloc);		// then print out the sector
      p.setmode(mdMOVE);			// put in move mode
      goto cmdscn;

     /* Bad command
      */

    cmderr:
      cmderror();

      /* Command scanner
       */

    cmdscn:
      p.sensor(u.loc);			// bring map up to date
    cmdin:
      d.pcur(p.curloc);			// position cursor
      if ((cmd = t.TTinr()) == -1)		// if no input from tty
      {   p.nrdy = 1;
	    return 0;			// not ready
      }
      p.nrdy = 0;				// reset flag

      /* Evaluate result if it's a direction command.
       */

      oldloc = p.curloc;			// remember
      if (cmdcur(&p.curloc,cmd,pr2))	// if direction command
      {   if (p.curloc == oldloc)	// if bad direction command
		goto cmderr;		// then error
	    if (p.mode == mdMOVE)		// if in move mode
	    {   if (!p.seeifok(u,*pr2) &&	// if move is destructive
		    !p.rusure())		// and he backs out
		{   p.curloc = u.loc;
		    goto cmdscn;		// give him another chance
		}
		goto done;			// we're done
	    }
	    if (p.mode == mdTO)		// if in TO mode
	    {   if (dist(p.curloc,p.frmloc) > p.maxrng)
		{   p.curloc = oldloc;
		    goto cmderr;		// too far away
		}
	    }
	    p.typhdg();			// update heading
	    goto cmdscn;
      }

      /* Check for command in our table.
       */

      switch (cmd)
	{   default:
		    goto cmderr;		// no defaults!
	    case 3:
		    done(1);
	    case ' ':			// stay put
		    *pr2 = -1;
		    if (p.mode == mdMOVE)
		    {   if (!p.seeifok(u,*pr2) &&	// if move is destructive
			    !p.rusure())		// and he backs out
			    goto cmdscn;	// give him another chance
			goto done;		// only allowed in move mode
		    }
		    cmderror();
		    break;
	    case 'F':			// from
		    p.cmdF(u); break;
	    case 'G':			// goto nearest city/carrier
		    if (p.cmdG(u))
			goto bhmove;	// if ifo and ila were changed
		    break;
	    case 'H':			// 20 free moves to enemy
		    if (!p.rusure())
			    goto cmdin;	// give him a chance to back out
		    p.setmode(mdNONE);
		    p.round += 20;		// use this as our mechanism
		    return 0;		// not ready
	    case 'I':			// direction
		    if (!p.valid(u) || p.mode == mdTO)
		    {   cmderror();
			break;
		    }
		    p.modsave = p.mode;
		    p.setmode(mdDIR);		// new mode
	    dirinp:	d.pcur(p.curloc);		// position cursor
	    dirin:	if ((cmd = t.TTinr()) == -1)
		    {   p.nrdy = 2;
			return 0;		// player is not ready
		    }
		    p.nrdy = 0;	// reset flag
		    if (cmd == ESC)		// if abort
		    {   p.setmode(p.modsave);
			break;
		    }
		    oldloc = p.curloc;
		    if (!cmdcur(&oldloc,cmd,pr2) || oldloc == p.curloc)
		    {   cmderror();
			goto dirinp;	// try again
		    }
		    p.setmode(p.modsave); // back to old mode
		    if (p.mycmod(u,fnDI,*pr2))
			goto bhmove;	// back to beginning
		    break;

	    case 'J':			// toggle sound on/off
		    t.speaker ^= true; break;
	    case 'K':			// wake up
		    p.cmdK(u); break;
	    case 'L':			// load armies
		    if (p.cmdL(u))
			goto bhmove;	// if ifo and ila were changed
		    break;
	    case 'N':			// new screen
		    center(p.curloc);
		    break;
	    case 'P':			// production phase
		    p.cmdP(); break;
	    case 'R':			// random
		    if (p.mycmod(u,fnRA,0))
			goto bhmove;	// back to beginning
		    break;
	    case 'S':			// sentry
		    if (.typ[map[p.curloc]] == X)
			goto cmderr;	// can't put in sentry in a city
		    if (p.mycmod(u,fnSE,0))
			goto bhmove;
		    break;
	    case 'T':			// to
		    if (p.cmdT(u))
			goto bhmove;	// if ifo and ila were changed
		    break;
	    case 'U':			// wake up units aboard
		    p.cmdU(u); break;
	    case 'V':			// save game
		    if (p.mode != mdMOVE)
			goto cmderr;	// only in move mode
		    savgam();		// save game next time around
		    return 0;		// move not completed
	    case 'Y':			// enter survey mode
		    if (p.mode == mdSURV)
			goto cmderr;	// allready in survey mode
		    p.setmode(mdSURV);	// enter survey mode
		    p.typhdg();
		    break;
	    case ESC:
		    if (p.mode == mdMOVE)
			goto cmderr;	// already in move mode
		    goto movmod;		// return to move mode
	    case '<':			// decrease time delay
		    d.timeinterval = (d.timeinterval < 1)
			    ? 0 : d.timeinterval - 1;
		    break;
	    case '>':			// increase time delay
		    d.timeinterval++;
		    break;
	} // switch (cmd)
      goto cmdscn;
    } // hmove

    /********************************
     * Process the 'F' command.
     */

    void cmdF(Unit *u)
    {   int ab,md;
      Player *p = this;

      md = p.mode;			// shorthand
      if (md == mdTO) goto err;

      ab = .map[p.curloc];
      p.maxrng = 100;			// default unless fighter
      p.citnum = -1;			// default unless from city

      if (!p.valid(u) ||			// if not a unit
	  (md == mdSURV && typ[ab] == X))	// or we're sitting on a city
      {   if (!p.cittst())		// if not an owned city
		goto err;
	    p.maxrng = typx[F].hittab;	// set to max fighter range
	    p.citnum = fndcit(p.curloc) - &city[0]; // find city #
      }
      else if (p.curloc != u.loc ||
	       (md == mdSURV && u.typ == F && typ[ab] == C))
      {   Unit *ui;

	    ui = fnduni(p.curloc);		// get unit number
	    if (ui.typ == F)		// if it's a fighter
		p.maxrng = ui.hit;	// set max range
      }
      else
      {   if (u.typ == F)		// if it's a fighter
		p.maxrng = u.hit;
      }

      p.savmod = p.mode;			// save current mode
      p.setmode(mdTO);			// switch to TO mode
      p.frmloc = p.curloc;		// set from location
      return;

    err:
      cmderror();
    }

    /***********************************
     * Command 'G'.
     * Find the nearest city or carrier we can fly to. Works
     * for setting fipath[]s also.
     * Returns:
     *	true	if we modified the ifo and ila of the unum unit.
     */

    int cmdG(Unit *u)
    {   int md,cloc,i,mindist,minloc;
      Player *p = this;

      md = p.mode;
      if (md == mdTO) goto err;
      cloc = p.curloc;

      /* First find nearest city.
       */

      mindist = typx[F].hittab + 1;		// we want one within range
      for (i = CITMAX; i--;)
      {   if (city[i].own == p.num &&	// if we own the city and
	    cloc != city[i].loc &&		// we're not already there and
	    city[i].loc &&			// the city exists and
	    dist(cloc,city[i].loc) < mindist)
	    {   minloc = city[i].loc;
		mindist = dist(cloc,minloc);
	    }
      }

      /* Look for a closer carrier.
       */

      for (i = unitop; i--;)
      {   if (unit[i].typ == C &&		// if it's a carrier and
	    unit[i].own == p.num &&	// we own it and
	    unit[i].loc &&			// it exists and
	    cloc != unit[i].loc &&		// we're not already there and
	    dist(cloc,unit[i].loc) < mindist)
	    {   minloc = unit[i].loc;
		mindist = dist(cloc,minloc);
	    }
      }
      if (mindist == typx[F].hittab + 1) goto err;	// if we failed

      if (md == mdMOVE)
      {   if (u.typ != F) goto err;
	    if (u.hit < mindist) goto err;	// if out of range
	    return p.mycmod(u,fnMO,minloc);
      }
      if (p.cittst())			// if we set fipath[]
      {   fndcit(cloc).fipath = minloc;
	    p.typhdg();
	    return false;
      }
      if (p.valid(u))			// if valid unit
      {   Unit *ui = fnduni(cloc);	// find the unit number
	    if (ui.typ != F ||
		ui.hit < mindist)
		goto err;
	    return p.mycmod(u,fnMO,minloc);
      }

    err:
      cmderror();
      return false;
    }

    /***********************************
     * Wake up unit if on a unit, clear fipath[]
     * if on a city.
     */

    void cmdK(Unit *u)
    {
      Player *p = this;

      if (p.mode == mdMOVE)
      {   p.mycmod(u,fnAW,0);
	    return;
      }
      if (p.cittst())			// if we're on a valid city
      {   fndcit(p.curloc).fipath = 0;	// zero out fipath
	    p.typhdg();
	    return;
      }
      if (p.valid(u))			// if a valid unit
	    p.mycmod(u,fnAW,0);		// wake up unit
      else
	    cmderror();
    }


    /***********************************
     * Process 'L' command.
     * Load armies/fighters on transports/carriers.
     * Don't allow it if he's in a city.
     * Returns:
     *	true	if we modified the ifo and ila of the unum unit.
     */

    int cmdL(Unit *u)
    {   int type,ab;
      Player *p = this;

      ab = .map[p.curloc];
      if (own[ab] == p.num &&		// if we own the unit and
	    (typ[ab] == T || typ[ab] == C))	// it's a transport or carrier
	    return p.mycmod(u,fnFI,0);	// put in fill mode

      cmderror();
      return false;
    }


    /***********************************
     * Enter new city production phase.
     */

    void cmdP()
    {
      Player *p = this;

      if (p.mode != mdSURV)		// only allowed in survey mode
	    goto err;
      if (!p.cittst()) goto err;		// not a valid city
      p.setmode(mdPHAS);
      p.phasin(fndcit(p.curloc));		// get new phase for city
      p.setmode(mdSURV);			// back to survey mode
      return;

    err:
      cmderror();
    }


    /***********************************
     * Process 'T' command.
     * Returns:
     *	true	if we modified the ifo and ila of the unum unit.
     */

    int cmdT(Unit *u)
    {   int ila;
      Player *p = this;

      if (p.mode != mdTO)		// if not in TO mode
	{   cmderror();
	    return false;
	}
      p.setmode(p.savmod);		// back to previous mode
      ila = p.curloc;
      p.curloc = p.frmloc;	// set cursor back
      if (p.citnum == -1)		// if it wasn't a city
	    return p.mycmod(u,fnMO,ila);	// set new function for device
	else				// else it was a city
	{   city[p.citnum].fipath = ila;
	    p.typhdg();
	    return false;
	}
    }


    /***********************************
     * Wake up units aboard.
     */

    void cmdU(Unit *u)
    {   int i,type;
      Player *p = this;

      if (p.cittst())				// if we're sitting on a city
	    for (i = unitop; i--;)
	    {   if (unit[i].loc == p.curloc &&
		    unit[i].own == p.num)
		    unit[i].ifo = 0;		// wake up the unit
	    }
      else
      {   if (!p.valid(u)) goto err;		// if not valid unit
	    type = typ[.map[p.curloc]];
	    if (type != T && type != C)
		goto err;
	    type = (type == T) ? A : F;		// type we want to wake up
	    for (i = unitop; i--;)
	    {   if (unit[i].loc == p.curloc &&
		    unit[i].typ == type &&
		    unit[i].own == p.num)
		    unit[i].ifo = 0;		// wake up the unit
	    }
      }
      p.display.wakeup();
      return;

    err:
      cmderror();
    }


    /***********************************
     * Modify ifo and ila of the unit the cursor is on.
     * Input:
     *	ifo	fnXX
     *	ila	appropriate ila for the ifo
     * Returns:
     *	true	if we modified the ifo and ila of the unum unit.
     */

    int mycmod(Unit *u,int ifo,int ila)
    {   int i;
      Player *p = this;

      if (!p.valid(u))			// if not a valid unit
      {   cmderror();
	    return false;
      }
      if (p.mode != mdMOVE)		// then look at visible piece
      {   Unit *ui = fnduni(p.curloc);
	    ui.ifo = ifo;
	    ui.ila = ila;
	    p.display.headng(ui);
	    return false;
      }
      else					// else in mdMOVE
      {   u.ifo = ifo;
	    u.ila = ila;
	    p.display.headng(u);		// type out new heading
	    return true;
      }
    }


    /***********************************
     * Return true if (curloc = loc) or (we're sitting on an owned unit).
     */

    int valid(Unit *u)
    {   int ab;
      Player *p = this;

      if (p.mode == mdMOVE && p.curloc == u.loc) return true;
      ab = .map[p.curloc];
      return (typ[ab] >= A && own[ab] == p.num);
    }


    /***********************************
     * Return true if we're sitting on an owned city.
     */

    int cittst()
    {   int ab;
      Player *p = this;

      ab = .map[p.curloc];
      return (typ[ab] == X && own[ab] == p.num);
    }


    /***********************************
     * Print current mode if necessary.
     */

    void setmode(int newmod)
    {   static char *modmsg[] =
	[	"         \1",
	    "Move     \1",
	    "Survey   \1",
	    "Direction\1",
	    "From To  \1",
	    "City Prod\1"
	];

	if (mode != newmod)			// if it is a new mode
	{
	    display.text.cmes(display.text.DS(2), modmsg[newmod]);
	    display.text.flush();
	    if (newmod == mdSURV || newmod == mdDIR ||
		mode == mdSURV || mode == mdTO || mode == mdDIR)
		invalidateSector();
	    mode = newmod;			// set new mode
	}
    }


    /*****************************
     * There was a command error.
     */

    void cmderror()
    {
	display.text.bell();
	display.valcmd(mode);
    }


    /*******************************
     * Type out information on what we're sitting on.
     * Input:
     *	curloc[]
     */

    void typhdg()
    {   int ab;
      loc_t loc;
      Player *p = this;

      loc = p.curloc;			// current location
      ab = .map[loc];			// get map val of where we are
      if (own[ab] == p.num)		// only if it's ours
      {   if (typ[ab] == X)		// if it's a city
		typcit(p,fndcit(loc));
	    else				// else it's a unit
		p.display.headng(fnduni(loc));
      }
    }


    /*********************************
     * If it's an army moving onto a troop transport in
     * fnFI mode, put the army to sleep.
     */

    void chksleep(Unit *u,int r2)
    {   uint loc,ab;
      Player *p = this;

      if (u.typ != A) return;		// if not an army
      loc = u.loc + arrow(r2);
      ab = .map[loc];
      if (typ[ab] != T || own[ab] != p.num)
	    return;
      if (fnduni(loc).ifo != fnFI)		// if not in fill mode
	    return;
      u.ifo = fnSE;			// put army in sentry mode
    }


    /**************************
     * Ask him if he's sure he wants to do this.
     * Returns:
     *	true if he's sure
     */

    int rusure()
    {
      return display.rusure();
    }

    /**********************************
     * Given a unit number and a trial move, see if it's ok.
     * Note it's ok to attack enemy pieces (even ships against armies!).
     * Watch out for case with r2 == -1 (stay in place)!
     * Use:
     *	seeifok(uninum,r2)
     * Input:
     *	uninum =	unit number
     *	r2 =		the trial move
     * Returns:
     *	true		if the move is ok
     */


    int seeifok(Unit *u,dir_t r2)
    {   loc_t z6;
      int ac,ab,type;
      Player *p = this;

      z6 = u.loc + arrow(r2);		// see where we're going
      ab = .map[u.loc];			// see where we are
      ac = .map[z6];			// see where we are going
      type = u.typ;			// what's our unit type?
      if (type == A)			// if dealing with an A
      {   if (ac == MAPland)		// if '+'
		return true;
	    if (typ[ac] == X)		// if attacking a city
		return own[ac] != p.num;	// ok if not our own city
	    if (r2 == -1)			// if staying put
		return true;
	    if (typ[ab] == T && sea[ac])	// can't move from T onto sea
		    return false;
	    if ((typ[ac] >= A) && (own[ac] != p.num))
		return true;		// ok if enemy
	    return typ[ac] == T && !full(fnduni(z6));	// not full T
      }
      if (ac == MAPsea)			// if '.'
	    return true;
      if ((typ[ac] >= A) && (own[ac] != p.num))
	    return true;			// it's enemy
      if (typ[ac] == X && own[ac] == p.num) // if owned city
	    return !aboard(u);	// false if T (C) with As (Fs) aboard
      if (type == F &&
	    (ac == MAPland || (typ[ac] == C && !full(fnduni(z6)) )) )
	    return true;
      return r2 == -1;			// ok only if stay in place
    }


    /***********************************
     * Handle human function moves
     * Input:
     *	uninum
     *	*pr2 =	pointer to move variable
     * Output:
     *	r2 =	selected move if true
     * Return:
     *	true	a move has been selected
     *	false	caller must pick a move
     */

    int mycode(Unit *u,dir_t *pr2)
    {   int loc,type,ab,ifo,ila;
      Player *p = this;

      loc = u.loc;
      type = u.typ;
      ab = .map[loc];
      ifo = u.ifo;
      ila = u.ila;

      if (eneltr(loc))			// if enemies in ltr
      {   u.ifo = 0;			// wake up
	    return(false);			// caller must pick move
      }

      /*
       * take care of fipaths
       */

      if ((type == F) && (typ[ab] == X))	// if fighter in a city
      {   City *c = fndcit(loc);		// find the city

	    if (c.fipath)			// if there is one
	    {   ila = u.ila = c.fipath;
		ifo = u.ifo = fnMO;
	    }
      }

	if (type == A &&			// if army and
	  citltr(loc,pr2))			// unowned city in ltr
		return(false);		// caller must pick move

	switch (ifo)
	{   case fnAW:
		return(false);		// caller picks move

	    case fnSE:
		*pr2 = -1;			// stay put
		return(true);

	    case fnRA:
		if (type == A)		// if army
		    if (tltr(loc,pr2))	// if a T to get on
		    {   u.ifo = 0;		// wake up
			return(true);
		    }
		*pr2 = empire.random(8);		// pick a move at random
		if (around(u,pr2))		// if we got a move
		    goto di2;
		return false;		// temporarilly unable to move

	    case fnMO:
		*pr2 = movdir(loc,ila);	// move from loc to ila
		if (*pr2 == -1)		// if arrived at ila
		{   u.ifo = 0;		// wake up
		    return(false);
		}
		return p.okmove(u,*pr2);	// if move is allright

	    case fnDI:
		*pr2 = ila;			// set initial move
	    di2:
		assert(*pr2 >= -1 && *pr2 <= 7);
		if (border(loc + arrow(*pr2)))	// if trial move is bad
		    return(false);
		if (type == F)				// if fighter
		    if (u.hit == typx[F].hittab/2)	// at 1/2 range
			return false;	// temporarilly wake up
		return p.okmove(u,*pr2);	// check status of move

	    case fnFI:
		if (full(u))		// if T or C is full
		{   u.ifo = 0;		// wake up
		    return(false);
		}
		*pr2 = -1;			// stay put
		return true;

	    default:
		assert(0);			// bad ifo
		return false;
	}
    }

    /**********************************
     * Given a unit number and a trial move, see if it's ok.
     * Input:
     *	uninum =	unit number
     *	r2 =		the trial move
     * Returns:
     *	true		if the move is ok
     */


    int okmove(Unit *u,dir_t r2)
    {   int z6,ac,ab,type;
      Player *p = this;

      assert(!(r2 & ~7));
      z6 = u.loc + arrow(r2);		// see where we're going
      if (border(z6))			// if on edge
	    return(false);
      ac = .map[z6];			// see where we are going
      if ((typ[ac] >= A) && (own[ac] != p.num))
	    return(false);			// it's enemy
      ab = .map[u.loc];			// see where we are
      type = u.typ;			// what's our unit type?
      if (type == A)			// if dealing with an A
      {   Unit *ut;

	    if (ac == MAPland)		// if '+'
		return(true);
	    if ((typ[ab] == T) && sea[ac])	// can't move from T onto sea
		return(false);
	    if (typ[ac] != T)		// if it's not an owned T
		return(false);
	    ut = fnduni(z6);
	    if (!p.human &&
		u.hit < typx[T].hittab &&
		u.ifo == IFOdamaged)
		return false;		// don't get on damaged T

	    return !full(ut);		// can't get on it it's full
      }
      if (ac == MAPsea)			// if '.'
	    return(true);
      if (typ[ac] == X && own[ac] == p.num) // if owned city
      {   if (u.ifo == IFOloadarmy)	// if computer strategy
		return(false);
	    if (aboard(u))			// if T (C) with As (Fs) aboard
		return(false);
	    return(true);			// can move into city
      }
      if (type == F &&
	    (ac == MAPland || (typ[ac] == C && !full(fnduni(z6)) )) )
	    return true;
      return false;
    }


    /**************************************
     * For a human player, get a production phase for a city.
     * Input:
     *	citnum
     * Output:
     *	city[citnum].phs
     */

    void phasin(City *c)
    {   loc_t loc;
	int ab,i;
	Player *p = this;
	Display *d = p.display;
	Text *t = &d.text;

	loc = c.loc;				// city location
	if (!d.insect(loc,2))		// if not in current sector
	    center(loc);			// center sector about city
	typcit(p,c);				// type out data on city
	version (Windows)
	{
	    d.pcur(loc);				// position cursor
	    t.flush();
	    i = dialogCitySelect(c.phs);
	    ab = typx[i].unichr;
	}
	else
	{
	    d.cityProdDemands();
	    d.pcur(loc);				// position cursor
	    while (true)
	    {   int c = t.TTin();
		ab = toupper(c);		// get char from tty
		for (i = 7; i >= 0; i--)
		    if (ab == typx[i].unichr)
			break;
		if (i >= 0)
		    break;			// got a good one
		t.bell();
	    }
	    t.curs(t.DS(0) + 25);		// where we want the prod to beg
	    t.output(ab);			// echo
	}
	c.phs = i;				// set city phase
	c.fnd = p.round + typx[i].phstart;
	typcit(p,c);
	d.delay(1);
    }


    /************************************
     * Look for unloaded Ts in LTR.
     * Use:
     *	tltr(loc,&r2)
     * Input:
     *	*pr2 =		place to store direction
     *	loc =		location
     * Output:
     *	*pr2 =		if (true) then direction of unloaded T
     * Returns:
     *	true		if there is an unloaded T in LTR
     */

    int tltr(loc_t loc,dir_t *pr2)
    {   int d,z6;
        Unit *u;

        assert(chkloc(loc));
        for (d = 8; d--;)		// loop thru directions
        {   z6 = loc + arrow(d);	// trial location
	    if (typ[.map[z6]] != T)	// if nay troop transport
		continue;		// try next direction
	    u = fnduni(z6);		// find unit number of T
	    if (u.own == num &&		// if we own it and
	       !full(u))		// the T isn't full
	    {   *pr2 = d;		// we found one
		return true;
	    }
        }
        return false;			// didn't find one
    }


    /*********************************
     * Return true if there is an enemy unit in LTR.
     * Use:
     *	eneltr(loc)
     * Input:
     *	loc
     */

    int eneltr(loc_t loc)
    {   int r2,ab;

	assert(chkloc(loc));
	for (r2 = 8; r2--;)
	{   ab = .map[loc + arrow(r2)];
	    if (typ[ab] >= A && own[ab] != num)
		return(true);
	}
	return false;
    }


    /*********************************
     * Search for unowned cities in LTR.
     * Use:
     *	citltr(loc,&r2)
     * Input:
     *	&r2,loc
     * Output:
     *	if true then r2 = direction of unowned city
     *	else r2 preserved.
     * Returns:
     *	true	if unowned city in LTR
     */

    int citltr(loc_t loc,dir_t *pr2)
    {   int i,ab;

	assert(chkloc(loc));
	for (i = 8; i--;)
	{   ab = .map[loc + arrow(i)];
	    if (typ[ab] == X && own[ab] != num)
	    {   *pr2 = i;				// return direction of city
		return(true);
	    }
	}
	return false;
    }


/* ===================== Computer strategy ================================== */

    /*************************************
     * Calculate move for computer piece.
     * Designed to run concurrently with hmove(), but is not itself
     * reentrant! i.e. cmove() cannot call idle().
     * Use:
     *	cmove(uninum,&r2);
     * Input:
     * Output:
     *	*pr2 = direction to move
     * Returns:
     *	0	move not completed
     *	!=0	move successfully completed
     */

    int cmove(Unit *u,dir_t *pr2)
    {   static int c = ' ';
      Player *p = this;
      Display *d = p.display;

      u.abd = aboard(u);			// count how many are aboard
      assert(chkloc(u.loc));
      arrloc(u.loc);			// update loci & troopt
      if (p.watch)
      {   if (!d.insect(u.loc,2))
		center(u.loc);
	    p.curloc = u.loc;
	    d.headng(u);			// type out the heading
	    d.pcur(p.curloc);
      }
    version (none)
    {
      if (ifoeva(u))			// see if we need a new ifo
      {   imes(" newifo ");
	    newifo(u);			// select a new ifo
	    curs(0x100 + 47);
	    p.display.fncprt(u);
      }
      else
	    imes(" movsel ");
      *pr2 = movsel();			// select a trial move
      cmes(DS(2),"movsel: "); decprt(*pr2);
      movcor(u,pr2);				// return corrected move
      imes(" movcor: "); decprt(*pr2); d.text.deleol();
      if (!p.watch) return 1;
      if (c == ' ' || (c == 'F' && u.typ == F)
		   || (c == 'A' && u.typ == A)
		   || (c == 'D' && u.typ == D)
		   || (c == 'T' && u.typ == T))
      {   if (!p.display.insect(u.loc,2))
		center(u.loc);
	    d.pcur(u.loc);
	    //c = toupper(TTin());
      }
    }
    else
    {
      if (ifoeva(u))			// see if we need a new ifo
	    newifo(u);			// select a new ifo

      *pr2 = movsel(u);			// select a trial move
    {   dir_t oldr2 = *pr2;
      movcor(u,pr2);			// return corrected move
    //if (p.watch && u.typ == A && u.ifo == IFOfolshore)
    //printf("\nu=%p, ifo=%d, ila=%3d, r2=%2d, oldr2=%d, dir=%2d\n",u,u.ifo,u.ila,*pr2,oldr2,u.dir),sleep(1);
    }
    }
      return 1;				// move is done
    }

    /***************************
     * Evaluate IFO to see if we should change it.
     * Output:
     *	unit[uninum].ila may change
     * Returns:
     *	true	if a new IFO needs to be selected
     */

    int ifoeva(Unit *u)
    {
      /*
       * If it's a damaged ship, look for a port to go to.
       */

      if (u.typ >= D &&			// if it's a ship and
	  u.hit <= (typx[u.typ].hittab >> 1) &&	// half damaged and
	  u.ifo != IFOdamaged &&			// not already heading for port
	  (u.typ != T || !u.abd))		// not a T with As aboard
		port(u);			// search for a port

      /*
       * If it's a T with u.ifo != IFOloadarmy and no armies aboard, clear u.ifo.
       */

      if (u.typ == T && u.ifo != IFOloadarmy &&
	  u.abd == 0 && u.ifo != IFOdamaged)
	    u.ifo = IFOnone;

      switch(u.ifo)
      {   case IFOnone:
	    case IFOescort:
	    case IFOfolshore:
	    case IFOonboard:	return true;	// select a new ifo
	    case IFOgotoT:		return ifo_gotoT(u);
	    case IFOdirkam:		return ifo2(u);
	    case IFOdir:		return ifo3(u);
	    case IFOtarkam:
	    case IFOtar:
	    case IFOcity:		return ifo_city(u);
	    case IFOgotoC:		return ifo6(u);
	    case IFOdamaged:	return ifo8(u);
	    case IFOstation:	return ifo9(u);
	    case IFOgstation:	return ifo10(u);
	    case IFOcitytar:	return ifo11(u);
	    case IFOshipexplor:	return ifo13(u);
	    case IFOloadarmy:	return ifo14(u);
	    case IFOacitytar:	return ifo15(u);
	    default:	assert(0);
			    return 0;
      }
    }

    /***************************
     * Go to TT# (armies only)
     * Input:
     *	u.ila =	TT unit number
     */

    int ifo_gotoT(Unit *u)
    {   Unit *ua = &unit[u.ila];

      assert(u.typ == A);
      assert(u.ila < unitop);
      if (ua.typ != T ||
	  ua.ifo != IFOloadarmy ||		// not a T looking for As
	  ua.own != num ||			// if we don't own it
	  !ua.loc)				// if T doesn't exist
	    return true;			// select new ifo
      if (typ[.map[u.loc]] == T)		// if aboard a T
	    return true;
      if ((ranq() & 8) && armtar(u))
	    return true;
      ua.ila = u.loc;			// set ila of T
      return false;
    }


    /*******************************
     * Directional, kamikaze (Fs only)
     * u.ila = direction
     */

    int ifo2(Unit *u)
    {
      assert(u.typ == F);
      if (!(ranq() & 15))			// change direction 1/16 times
	    u.ila = (u.ila + u.dir) & 7;
      return false;				// never change ifo
    }


    /************************
     * Directional
     * u.ila = direction
     */

    int ifo3(Unit *u)
    {
      if (u.typ == F && u.hit == 10)	// if fighter at half range
	    return true;			// pick a new ifo
      if (!(ranq() & 15))			// change direction 1/16 times
	    u.ila = (u.ila + u.dir) & 7;
      return false;				// never change ifo
    }


    /************************
     * Go to carrier # (Fs only)
     * u.ila = carrier #
     */

    int ifo6(Unit *u)
    {   int dloc;
      Unit *ua = &unit[u.ila];

      assert(u.typ == F);
      assert(u.ila < unitop);
      dloc = ua.loc;			// location of carrier
      if (!dloc) return true;		// if carrier doesn't exist
      if (ua.own != num) return true;	// if we don't own it
      if (u.loc == dloc) return true;	// we've arrived
      if (ua.typ != C) return true;
      return dist(u.loc,dloc) > u.hit;	// true if out of range
    }

    /********************
     * Go to target location (Fs, ships)
     * Used for ifo4, ifo5, ifo_city.
     */

    int ifo_city(Unit *u)
    {   int r0;

      assert(chkloc(u.ila));
      if (u.loc == u.ila)			// if we have arrived
	    return true;
      if (u.typ == A)
      {   if (map[u.ila] == MAPsea)
		return true;
	    return !patblk(u.loc,u.ila);	// true if army can't get there
      }
      if (u.typ == F)
      {   int d;

	    d = dist(u.loc,u.ila);		// distance to target
	    if (d > u.hit)				// if out of range
		return true;
	    if (u.ifo == IFOtar && d == 1 && typ[.map[u.ila]] == X)
		return true;
	    return false;
      }
      return !patsea(u.loc,u.ila);		// true if ship can't get there
    }


    /*********************
     * Go to port (ship is damaged)
     * u.ila = loc of city
     */

    int ifo8(Unit *u)
    {
      assert(chkloc(u.ila));
      if (u.hit == typx[u.typ].hittab)	// if ship is repaired
	    return true;
      if (own[.map[u.ila]] != num)	// if we don't own the city
	    return !port(u);		// search for new port
      return false;
    }


    /*********************
     * Stationed (for carriers)
     * u.ila = stationed location
     * Returns:
     *	true	if no target cities are within fighter range
     */

    int ifo9(Unit *u)
    {   int i;

      assert(chkloc(u.ila));
      for (i = CITMAX; i--;)
      {   if (!target[i])			// if city is not a target
		continue;
	    if (dist(u.ila,city[i].loc) <= 10)	// if within range
		return false;
      }
      return true;
    }


    /***********************
     * Heading towards station (carriers)
     * u.ila = station
     */

    int ifo10(Unit *u)
    {   char ab;

      assert(chkloc(u.ila));
      if (u.loc == u.ila)			// if we arrived at station
      {   u.ifo = 9;			// station the C at u.ila
	    return false;
      }
      ab = map[u.ila];			// see what's at the station
      return ab != MAPunknown && ab != MAPsea;	// true if not blank or sea
    }


    /**************************
     * City target (ships)
     * u.ila = city loc
     */

    int ifo11(Unit *u)
    {   int r0;

      assert(chkloc(u.ila));
      if (!patsea(u.loc,u.ila))
	    return true;
      if (own[.map[u.ila]] != num)	// if we don't own the city
	    return false;
      r0 = dist(u.loc,u.ila);		// r0 = distance to our city
      return (r0 <= 1) || (r0 > 10);	// if nearby, continue on
    }


    /***************************
     * Look at unexplored territory (ships)
     * u.ila = loc of unexplored territory
     */

    int ifo13(Unit *u)
    {
      assert(chkloc(u.ila));
      if (map[u.ila])			// if territory is explored
	    return true;			// pick a new ifo
      return !patsea(u.loc,u.ila);	// pick new ifo if no path
    }


    /******************************
     * Load up armies (troop transports)
     * Ila can be either the loc of an army-producing city or the loc
     * of an army which wants to get aboard.
     * Ila can be:
     *	1) loc of an army-producing city.
     *	2) within 1 space of an army that wants to get aboard
     *	3) a direction
     */

    int ifo14(Unit *u)
    {   int i,ab;

      if (typ[.map[u.ila]] == X)		// if location of city
      {   if (own[.map[u.ila]] != num ||	// if we don't own it any more
	       fndcit(u.ila).phs != A)	// if not producing armies
		return true;
      }
      else if (u.ila > 7)			// if it's not a direction
      {   for (i = 8; i-- >= 0;)		// thru 9 directions
	    {   ab = .map[u.ila + arrow(i)];
		if (typ[ab] == A && own[ab] == num)
		    goto ok;
	    }
	    return true;			// select new ifo
      }
      else if ((ranq() & 7) == 1)
	    return true;
    ok:
      return (round <= 150)			// if in early part of game
	     ? u.abd >= u.hit		// don't fill up the T so much
	     : u.abd >= (u.hit << 1);	// fill up T completely
    }


    /****************************
     * City target (armies)
     * u.ila = city location
     * Use of patblk() must match up with usage in armtar() in ARMYMV!
     */

    int ifo15(Unit *u)
    {
      assert(chkloc(u.ila));
      assert(.typ[.map[u.ila]] == X);
      if (own[.map[u.ila]] == num)	// if we own the city
	    return true;			// select a new ifo
      return !patblk(u.loc,u.ila);	// new ifo if we can't get there
    }

    /*****************************
     * Select a new ifo and u.ila for the unit.
     * Input:
     *	local variables
     * Output:
     *	u.ifo,u.ila,uniifo,uniila
     */

    void newifo(Unit *u)
    {
      switch (u.typ)
      {   case A:	ARMYif(u);
		    break;
	    case F:	FIGHif(u);
		    break;
	    case T:	TROOif(u);
		    break;
	    case C:	CARRif(u);
		    break;
	    case D:
	    case S:
	    case R:
	    case B:	SHIPif(u);
		    break;
	    default:
		    assert(0);
      }
      assert(u.ifo);
    }

    /***************************
     * Select a move given ifo and u.ila.
     * Input:
     *	local variables
     * Returns:
     *	move
     */

    dir_t movsel(Unit *u)
    {   dir_t r;

      switch (u.ifo)
      {   case IFOgotoT:
	    case IFOgotoC:
	    case IFOescort:
		    r = seluni(u);
		    break;
	    case IFOdirkam:
	    case IFOdir:
		    r = seldir(u);
		    break;
	    case IFOtarkam:
	    case IFOtar:
	    case IFOcity:
	    case IFOdamaged:
	    case IFOstation:
	    case IFOgstation:
	    case IFOcitytar:
	    case IFOshipexplor:
	    case IFOloadarmy:
	    case IFOacitytar:
		    r = selloc(u);
		    break;
	    case IFOfolshore:
		    r = selfol(u);
		    break;
	    case IFOonboard:
		    r = -1;		// don't move
		    break;
	    default:
		    display.text.cmes(display.text.DS(2),"ifo:");
		    display.text.decprt(u.ifo);
		    assert(0);
      }
      return r;
    }


    /**********************************
     * Directional, but follow the shore.
     * Input:
     *	u.ila =	direction
     */

    dir_t selfol(Unit *u)
    {   dir_t r2;

      assert(u.ila >= 0 && u.ila < 8);
      r2 = (u.ila - u.dir * 3) & 7;	// go back 3 & normalize
      if (okmove(u,r2))			// if move is ok
	    r2 = u.ila;			// don't go back 3
      if (around(u,&r2))			// if found a good move
	    u.ila = r2;			// set new direction
      return r2;
    }


    /***************************
     * Directional
     * Input:
     *	u.ila =	direction (0..7, not -1!)
     */

    int seldir(Unit *u)
    {   int r2;

      assert(!(u.ila & ~7));
      r2 = u.ila;
      if (around(u,&r2))			// if found a good move
	    u.ila = r2;			// set new direction
      return r2;
    }


    /***************************
     * Move towards a unit number.
     * u.ila = unit number
     */

    int seluni(Unit *u)
    {
      assert(u.ila < unitop);
      assert(chkloc(unit[u.ila].loc));
      return locs(u,unit[u.ila].loc);		// move towards unit location
    }


    /**********************
     * Move towards a location.
     * u.ila = number
     */

    int selloc(Unit *u)
    {
      if (u.ila <= 7)			// if it's a direction
	    return seldir(u);		// directional
      return locs(u,u.ila);		// get move
    }


    /*********************
     * Move from u.loc to toloc.
     * Returns:
     *	move
     */

    int locs(Unit *u,loc_t toloc)
    {   int r2,flag;

	static byte lp[PLYMAX][MAPMAX];	// move on land for armies
	static byte ap[PLYMAX][MAPMAX];	// move on sea for fighters
	static byte sp[PLYMAX][MAPMAX];	// move on sea for ships
	static int inited;

	if (u.loc == toloc)		// if at destination
	    return -1;			// no move
	if (!inited)
	{   // Initialize arrays
	    uint p,m;

	    inited++;
	    for (p = 0; p < PLYMAX; p++)
	    {
		sp[p][0] = 1; ap[p][0] = 1; lp[p][0] = 1;	// ' '
		sp[p][1] = 0; ap[p][1] = 0; lp[p][1] = 1;	// *
		sp[p][2] = 1; ap[p][2] = 1; lp[p][2] = 0;	// .
		sp[p][3] = 0; ap[p][3] = 1; lp[p][3] = 1;	// +
		for (m = 4; m < MAPMAX; m++)
		{
		    sp[p][m] = sea[m];
		    if (((m - 4) / 10) == p)
		    {   // It's our city or unit
			ap[p][m] = (typ[m] == X || typ[m] == C);
			lp[p][m] = land[m];
		    }
		    else
		    {   // It's an enemy city or unit
			ap[p][m] = typ[m] != X;
			lp[p][m] = (typ[m] == X || land[m]);
		    }
		}
	    }
	}
	switch (u.typ)
	{   case A:	flag = patho(u.loc,toloc,u.dir,lp[num - 1],&r2);
		    break;
	    case F: flag = patho(u.loc,toloc,u.dir,ap[num - 1],&r2);
		    break;
	    default:			// ships
		    flag = patho(u.loc,toloc,u.dir,sp[num - 1],&r2);
	}
	version (none)
	{
	    if (!flag && u.typ == T && watch && u.ifo == IFOcitytar)
	    {
		display.text.TTcurs(0x410);
		printf("flag=%d r2=%d floc=%d,tloc=%d ",flag,r2,u.loc,toloc);
		display.text.TTin();
	    }
	}
	if (!flag)				// if didn't find a move
	    r2 = movdir(u.loc,toloc);		// default move
	return r2;
    }

    /******************************
     * Given a move, r2, correct it.
     */

    void movcor(Unit *u,dir_t *pr2)
    {
      switch (u.typ)
      {   case A:	ARMYco(u,pr2);
		    break;
	    case F:	FIGHco(u,pr2);
		    break;
	    case D:
	    case T:
	    case S:
	    case R:
	    case C:
	    case B:	SHIPco(u,pr2);
		    break;
	    default:
		    assert(0);
      }
    }


    /******************************
     * Given a unit number and direction, look around
     * for territory to explore, giving priority to
     * moving diagonally.
     * Input:
     *	*r2	where to put direction (watch out for -1!)
     * Returns:
     *	true	*r2 = direction to go
     *	false	*r2 preserved
     */

    int explor(Unit *u,dir_t *pr2)
    {   int r,ab,i;
      loc_t loc,loc2;
      dir_t r2 = -1;
      Player *p = this;

      loc = u.loc;
      r = *pr2 | 1;				// diagonal
      for (i = 8; i--;)			// loop thru 8 dirs
      {   r &= 7;				// normalize
	    if (p.okmove(u,r))		// if good move
	    {
		loc2 = loc + (arrow(r) * 2);	// move twice in r direction
		ab = map[loc2];
		if (ab == MAPunknown)	// if unexplored
		{   *pr2 = r;		// set direction
		    return true;
		}
		// Look another step in r direction
		if (NEW && !border(loc2) && (u.typ == A && ab == MAPland ||
		    u.typ >= D && ab == MAPsea || u.typ == F))
		{   loc2 += arrow(r);
		    ab = map[loc2];
		    if (ab == MAPunknown)
			r2 = r;
		}
	    }
	    r += 2;				// next direction
	    if (i == 4)			// if halfway thru
		r++;			// leave diagonals
      }
      if (r2 != -1)
      {   *pr2 = r2;
	    return true;
      }
      return false;				// nothing to explore
    }

    /*********************************
     * Look for unexplored territory.
     * Input:
     * Returns:
     *	0	no unexplored territory found
     *	else	loc of unexplored territory
     */

    int expshp()
    {   int i;
      loc_t loc;
      ubyte* map;

      map = this.map;
      for (i = 20; i--;)			// do 10 tries
      {   loc = (Mcolmx+2) + empire.random((Mrowmx-1)*(Mcolmx+1) - 2);	// pick loc from 101..5898
	    if (map[loc] == MAPunknown &&	// if location is blank	and
		!border(loc))		// it isn't on the border
		    return loc;		// then we got one
      }
      return 0;				// didn't find one
    }

    /******************************
     * Remove targets from loci and troopt if loc is on them.
     * Input:
     *	loc
     */

    void arrloc(loc_t loc)
    {   uint i;
	uint *pl;
	Player *p = this;

	pl = &p.troopt[0][0];
	for (i = 6 * 5; i--; pl++)
	    if (loc == *pl)
		*pl = 0;
	pl = &p.loci[0];
	for (i = LOCMAX; i--; pl++)
	    if (loc == *pl)
		*pl = 0;
    }

    /********************************
     * Look around loc to see if there is anything to attack.
     * If so, set direction. As will not attack Fs over sea,
     * and ships will not attack Fs over land.
     * Input:
     *	uninum
     *	&r2
     *	mask		mask with things to attack
     * Output:
     *	r2		move to attack in
     * Returns:
     *	true		if r2 was modified
     */

    int eneatt(Unit *u,dir_t *pr2,int mask)
    {   int i,ab,type;
      loc_t loc;

      loc = u.loc;
      type = u.typ;
      for (i = 8; i--;)
      {   ab = .map[loc + arrow(i)];
	    if (own[ab] == num ||		// if we own it, it's not enemy
	       typ[ab] < A ||		// if not a unit
	       !(mask & msk[typ[ab]]))	// if type is not in mask
		continue;
	    if (typ[ab] == F)		// if attacking a fighter
	    {   if ((type == A && sea[ab]) ||
		    (type >= D && land[ab]))
		    continue;
	    }
	    *pr2 = i;			// set move
	    return true;
      }
      return false;
    }

    /************************************
     * Given a move, look around till one that satisfies okmove()
     * is found, and return it in *pr2.
     * Input:
     *	u
     *	pr2
     * Returns:
     *	true	if we found a good move.
     *	false	we didn't find one (*pr2 = -1)
     */

    int around(Unit *u,dir_t *pr2)
    {   int i;
      dir_t r2;
      Player *p = this;

      assert(u.dir == 1 || u.dir == -1);
      r2 = *pr2 & 7;			// in case *pr2 = -1
      for (i = 8; i--;)			// 8 directions
      {   if (p.okmove(u,r2))		// if move is ok
	    {   *pr2 = r2;
		return true;
	    }
	    r2 = 7 & (r2 + u.dir);		// new direction
      }
      *pr2 = -1;				// stay put
      return false;
    }

    /**********************************
     * Select a new ifo and ila for an army.
     */

    void ARMYif(Unit *u)
    {   uint loc,ab;
      dir_t r2;

      loc = u.loc;
      assert(chkloc(loc));
      ab = .map[loc];

      //cmes(0x100,"a1            ");
      if (typ[ab] == T)			// if we're aboard a T
      {   u.ifo = IFOonboard;		// set to indicate we're aboard
	    //cmes(0x102,"b2");
	    if (sursea(u)) return;		// if surrounded by sea
	    //cmes(0x104,"b3");
	    if (armtar(u)) return;		// if cities to attack
	    r2 = 0;				// for explor()
	    //cmes(0x106,"b4");
	    if (!explor(u,&r2)) return;	// if no territory to explore
	    goto set16;			// follow shore
      }

      if (((u.dir >> 1) ^ round) & 1)	// get arbitrary but predictable #
      {   //cmes(0x102,"a2");
	    if (armtar(u))		// don't call armtar() every time
		return;
      }
      if (armloc(u)) return;	// if loci to attack
      if (armtt(u)) return;		// if TTs to get aboard
      if (u.ifo == IFOfolshore)	// if already following shore
	    return;

    set16:
      u.ifo = IFOfolshore;		// follow shore
      u.ila = randir();		// set direction
    //printf("\nfolshore: %p, ila=%d, dir=%2d\n",u,u.ila,u.dir);
    }

    /****************************************
     * Given a trial move r2, correct that move.
     * Input:
     *	pr2 .		r2
     *	uninum =	unit number
     * Output:
     *	r2 =		corrected move
     */

    void ARMYco(Unit *u,dir_t *pr2)
    {   int at;
      Player *p = this;

      if (citltr(u.loc,pr2)) return;	// if unowned cities
      if (explor(u,pr2)) return;		// if territory to explore
      if (typ[.map[u.loc]] == T)		// if aboard a transport
	    at = mA|mF;			// attack only As or Fs
      else if (NEW && u.ifo == IFOacitytar)
	    at = mA|mT;
      else
	    at = mA|mF|mD|mT|mS;		// else attack AFDTSs
      if (eneatt(u,pr2,at))			// if anything to attack
	    return;
      if (NEW && u.ifo == IFOfolshore)
      {   // Look around for TT to get on
	    int i;
	    loc_t loc;

	    for (i = 8; i--;)
	    {
		loc = u.loc + arrow(i);
		if (typ[.map[loc]] == T && p.okmove(u,i))
		{   *pr2 = i;
		    return;
		}
	    }
      }
      if (*pr2 == -1) return;		// if stay put
      around(u,pr2);			// look around for okmove
    }


    /************************************
     * Search for a target city for the army to attack. If found,
     * set ifo and ila and return true.
     */

    int armtar(Unit *u)
    {   loc_t loc,loccit;
      int i,end;
      Player *p = this;
      int distance;

      if (NEW)
	    distance = 20;
      else
	    distance = 12;
      loc = u.loc;
      assert(chkloc(loc));
      i = end = empire.random(CITMAX);		// select random city number
      do
      {   if (p.target[i])		// if the city is on our hit list
	    {   loccit = city[i].loc;	// get city location
		if (loccit &&		// if city exists
		  dist(loc,loccit) <= distance &&	// near to city
		  patblk(loc,loccit))	// path to city
		{   u.ifo = IFOacitytar;	// attack city
		    u.ila = loccit;	// location of city to attack
		    return true;
		}
	    }
	    i++;
	    if (i >= CITMAX) i = 0;
      }
      while (i != end);
      return false;				// failed
    }


    /****************************
     * Find a target in loci[]. If found, set ifo and ila
     * and return true.
     */

    int armloc(Unit *u)
    {   uint loc;
        uint* pl;
        uint i;
        Player *p = this;

        loc = u.loc;
        assert(chkloc(loc));
        pl = &p.loci[0];			// get pointer to loci
        for (i = 0; i < LOCMAX; i++,pl++)	// loop thru loci
        {   if (!*pl) continue;			// if unit doesn't exist
	    assert(chkloc(*pl));
	    if (dist(loc,*pl) > 12) continue;	// if loci is too far away
	    if (patblk(loc,*pl))		// if it's reachable
	    {   u.ifo = IFOtar;
		u.ila = *pl;			// target location
		return true;			// found one
	    }
        }
        return false;
    }


    /******************************************
     * Search for a T for the army to get on.
     * Input:
     *	uninum
     * If found:
     *	Set ifo, ila of army.
     *	Set ila of T such that the T will head towards the army.
     *	Return true
     * Else:
     *	Return false
     */

    int armtt(Unit *u)
    {   uint i, end;
      loc_t loc;
      Unit *ui;

      loc = u.loc;
      assert(chkloc(loc));
      i = end = empire.random(unitop);		// end at random unit #
      do
      {   ui = &unit[i];
	    if (ui.ifo == IFOloadarmy &&	// must be looking for armies
	      ui.typ == T &&		// look for a transports
	      ui.loc &&			// if unit exists
	      ui.own == num &&		// if we own the unit
	      dist(loc,ui.loc) <= 10)	// if T is near
	    {   ui.ila = loc;		// set ila of T to unit loc
		u.ifo = IFOgotoT;
		u.ila = i;			// set ila to transport #
		return true;
	    }
	    i++;
	    if (i >= unitop) i = 0;		// wrap around
      }
      while (i != end);
      return false;
    }

    /************************************
     * Select an ifo and ila for a fighter.
     */

    void FIGHif(Unit *u)
    {
      Player *p = this;

      u.fuel = cast(int) u.hit;		// get amount of fuel left
      if (u.fuel < typx[F].hittab)		// if F is airborne
      {
	if (gocit(u)) return;		// look for city
	if (gocar(u)) return;		// then a carrier
      }
      else
	  u.fuel >>= 1;			// only let him go halfway out

	// Look for enemy troop transports, then submarines.
	if (fndtar(u,&p.troopt[T-2][0],10))
	    return;				// look for Ts, then Ss

	if (figtar(u))			// attack enemy city
	    return;

	switch (empire.random(3))
	{
	    case 0:
		// Move towards an enemy army location within range.
		if (fndtar(u,&p.loci[0],LOCMAX))
		    return;			// if found a loci[] target
		if (gocit(u)) return;	// look for city
		if (gocar(u)) return;	// then a carrier
		break;

	    case 1:				// to city or carrier
		if (gocar(u)) return;	// then a carrier
		if (gocit(u)) return;	// look for city
		// Move towards an enemy army location within range.
		if (fndtar(u,&p.loci[0],LOCMAX))
		    return;			// if found a loci[] target
		break;

	    case 2:
		break;

	    default:
		assert(0);
	}
	// Move in random direction
	u.ila = randir();
	u.ifo = IFOdir;
    }

    /*******************************
     * Look for a city in range. If found, set ifo, ila, and
     * return true.
     */

    int gocit(Unit *u)
    {
      loc_t loc = u.loc;
      int i,end,inc;
      City *cmax;
      Player *p = this;

      assert(chkloc(loc));
      i = end = empire.random(CITMAX);		// set random end
      inc = (ranq() & 1) ? 1 : -1;		// pick 1 or -1
      cmax = null;
      do 					// loop thru all cities
      {   City *c = &city[i];

	    if (c.own == p.num &&		// if owned
	       c.loc &&			// city exists
	       c.loc != loc &&		// not already there
	       dist(loc,c.loc) <= u.fuel)	// within range
	    {   if (!cmax || c.round > cmax.round)
		    cmax = c;		// newer city
	    }
	    i += inc;
	    if (i >= CITMAX) i = 0;
	    if (i < 0) i = CITMAX - 1;
      }
      while (i != end);
      if (cmax)
      {
	    u.ifo = IFOcity;
	    u.ila = cmax.loc;
	    if (cmax.round)
		cmax.round--;		// age it
	    return true;
      }
      return false;
    }

    /********************************
     * Same as gocit(), but find a carrier.
     */

    int gocar(Unit *u)
    {   uint end,i;
      loc_t loc,cloc;
      Unit *uc;

      loc = u.loc;
      assert(chkloc(loc));
      i = end = empire.random(unitop);
      do
      {   if (i >= unitop) i = 0;		// wrap around
	    uc = &unit[i];
	    if (uc.typ == C &&		// if a carrier
		uc.loc &&
		uc.own == num &&		// if we own it
	      (u.fuel == u.hit ||		// if looking for place to land
		uc.ifo == IFOstation) &&	// or C is stationed
	      (cloc = uc.loc) != 0 &&	// C exists
	      loc != cloc &&		// not already there
	      dist(loc,cloc) <= u.fuel)	// if near enough
	    {   u.ifo = IFOtar;
		u.ila = cloc;
		return true;
	    }
	    i++;
	    if (i >= unitop) i = 0;
      }
      while (i != end);
      return false;
    }


    /************************************
     * Search for a target city for the army to attack. If found,
     * set ifo and ila and return true.
     */

    int figtar(Unit *u)
    {   uint loc,loccit;
      int i,end;
      Player *p = this;

      loc = u.loc;
      assert(chkloc(loc));
      i = end = empire.random(CITMAX);		// select random city number
      do
      {   if (p.target[i] &&		// if the city is on our hit list
		city[i].own)		// and it's an enemy city
	    {   loccit = city[i].loc;	// get city location
		if (loccit &&		// if city exists
		  dist(loc,loccit) <= u.fuel)	// near to city
		{   u.ifo = IFOtar;	// attack city
		    u.ila = loccit;	// location of city to attack
		    return true;
		}
	    }
	    i++;
	    if (i >= CITMAX) i = 0;
      }
      while (i != end);
      return false;				// failed
    }


    /*******************************
     * Correct the move that pr2 points to.
     */

    void FIGHco(Unit *u,dir_t *pr2)
    {
      if (eneatt(u,pr2,mA|mF|mD|mT|mS|mR|mC|mB))	// attack anything
	    return;
      if (u.ifo == IFOdirkam ||		// if kamikaze
	    u.hit > 10)			// and plenty of fuel
      {   if (explor(u,pr2))		// and territory to explore
		return;
      }
      if (*pr2 == -1) return;		// if stay put
      around(u,pr2);			// look for okmove
    }

    /********************************
     * Find new ifo and ila for a T.
     */

    void TROOif(Unit *u)
    {   uint abd;
      loc_t z6;
      int flag;

      abd = aboard(u);			// see how many are aboard
      assert(abd <= 8);
      if (!abd)				// if none aboard
      {   if (armcit(u))			// look for army producing city
		return;
	    u.ifo = IFOloadarmy;
	    u.ila = randir();		// select random direction
	    return;
      }
      flag = ranq();
      if (flag & 1)				// 50% chance
      {   if (trotar(u,flag & 2))		// if target city found
		return;
	    z6 = expshp();			// places to explore
	    if (z6)
	    {   u.ifo = IFOshipexplor;
		u.ila = z6;
		return;
	    }
      }
      else
      {   z6 = expshp();
	    if (z6)				// if places to explore
	    {   u.ifo = IFOshipexplor;
		u.ila = z6;
		return;
	    }
	    if (trotar(u,flag & 6))		// if target city found
		return;
      }
      if (u.ifo == IFOdir) return;		// if random direction already
      u.ifo = IFOdir;
      u.ila = randir();			// set random direction
    }

    /*********************************
     * Select ifo, ila for D,S,R,B.
     */

    void SHIPif(Unit *u)
    {   loc_t z6;

      if (shiptr(u)) return;		// look for enemy ships to attack
      if (ranq() & 1)			// 50% chance
      {   if (shipta(u)) return;		// look for target city
      }
      else
      {   if (shiptt(u)) return;		// look for TT to escort
      }
      z6 = expshp();
      if (z6)				// if places to explore
      {   u.ifo = IFOshipexplor;
	    u.ila = z6;
	    return;
      }
      if (u.ifo == IFOdir) return;		// if it's already 3
      u.ifo = IFOdir;
      u.ila = randir();
    }


    /***********************************
     * Select ifo and ila for carriers.
     */

    void CARRif(Unit *u)
    {   loc_t z6;

      if (shiptr(u))			// look for enemy ships
      {   u.ifo = IFOgstation;		// station at enemy ship loc
	    return;
      }
      if (shipta(u)) return;		// look for target city
      z6 = expshp();
      if (z6)				// if places to explore
      {   u.ifo = IFOshipexplor;
	    u.ila = z6;
	    return;
      }
      if (u.ifo == IFOdir)
	    return;				// if it's already 3
      u.ifo = IFOdir;
      u.ila = randir();
    }

    /**********************************
     * Correct the move that pr2 points to.
     */

    void SHIPco(Unit *u,dir_t *pr2)
    {   int msknum;
      static int attmsk[6] =
      [	mF|mD|mT|mS,			// D:.FDT S...
	    0,				// T:.... ....
	    mD|mT|mS|mR|mC|mB,		// S:..DT SRCB
	    mF|mD|mT|mS|mR|mC|mB,		// R:.FDT SRCB
	    mD|mT|mC,			// C:..DT ..C.
	    mF|mD|mT|mS|mR|mC|mB		// B:.FDT SRCB
      ];
      static int escmsk[6] =
      [	mA|mR|mC|mB,			// D:A... .RCB
	    mA|mF|mD|mS|mR|mC|mB,		// T:AFD. SRCB
	    mA|mF,				// S:AF.. ....
	    0,				// R:.... ....
	    mA|mS|mR|mB,			// C:A... SR.B
	    0				// B:.... ....
      ];
      int m;

      if (lodarm(u,pr2)) return;		// loading armies, stay put
      if (u.ifo != IFOloadarmy)		// if not looking for armies
      {   if (*pr2 == -1) return;		// if stay put, then stay put
	    if (u.ifo != 8 &&		// if ship isn't damaged and
		explor(u,pr2))		// territory to explore
		return;
      }
      msknum = u.typ - D;			// get index into masks
      m = attmsk[msknum];
      if (overpop && u.typ != T)
	    m = mA|mF|mD|mT|mS|mR|mC|mB;	// attack anything
      if (eneatt(u,pr2,m))
	    return;				// if enemies to attack
      if (eneatt(u,pr2,escmsk[msknum]))	// if anything to escape from
	    *pr2 = (*pr2 + 3 + empire.random(3)) & 7; // move in opposite direction
      around(u,pr2);
    }

    /**************************
     * Look for port to go to.
     * Input:
     *	uninum
     * Output:
     *	uniifo[],uniila[]
     * Returns:
     *	true	if a port is found.
     */

    int port(Unit *u)
    {   loc_t loc,cloc;
      uint min,dtry,i,end;
      Player *p = this;

      loc = u.loc;
      assert(chkloc(loc));
      min = 10000;				// arbitrary # larger than any dist
      for (i = CITMAX; i--;)
      {   if (city[i].own == p.num &&	// if own the city and
	      (cloc = city[i].loc) != 0 &&	// city exists
	      (dtry = dist(loc,cloc)) < min &&
	      edger(cloc) &&		// it's a port city
	      patsea(loc,cloc))		// a path by sea
	    {   u.ifo = IFOdamaged;
		u.ila = cloc;
		min = dtry;			// set new minimum
	    }
      }
      return min != 10000;			// true if we found one
    }


    /**************************
     * Look for an army producing city.
     * Input:
     *	uninum
     * Output:
     *	uniifo[],uniila[]
     * Returns:
     *	true	if one is found.
     */

    int armcit(Unit *u)
    {   uint loc,cloc,min,dtry,i,end;
      Player *p = this;

      loc = u.loc;
      assert(chkloc(loc));
      min = 10000;				// arbitrary # larger than any dist
      for (i = CITMAX; i--;)
      {   if (city[i].own != p.num)
		continue;			// don't own it
	    if (city[i].phs != A) continue;	// if not army producing city
	    cloc = city[i].loc;		// loc of city
	    if (!cloc) continue;		// city doesn't exist
	    assert(chkloc(cloc));
	    dtry = dist(loc,cloc);		// distance to city
	    if (dtry >= min) continue;	// not minimum
	    if (!edger(cloc)) continue;	// if not a port city
	    if (patsea(loc,cloc))		// if a path by sea
	    {   u.ifo = IFOloadarmy;
		u.ila = cloc;
		min = dtry;			// set new minimum
	    }
      }
      return min != 10000;			// true if we found one
    }


    /**************************
     * Look for city target for a troop transport.
     * Input:
     *	uninum
     *	flag	0	look at all cities
     *		!=0	look at only unowned cities
     * Output:
     *	uniifo[],uniila[]
     * Returns:
     *	true	if one is found.
     */

    int trotar(Unit *u,int flag)
    {   loc_t loc,cloc;
      uint min,dtry,i;
      Player *p = this;

      if (!NEW)
	    flag = 0;
      loc = u.loc;
      assert(chkloc(loc));
      min = 10000;				// arbitrary # larger than any dist
    L1:
      for (i = CITMAX; i--;)		// loop thru cities
      {   if (!p.target[i])		// if city is not a target
		continue;
	    cloc = city[i].loc;		// loc of city
	    if (!cloc) continue;		// city doesn't exist
	    assert(chkloc(cloc));
	    if (flag && own[.map[cloc]])	// if an owned city
		continue;
	    dtry = dist(loc,cloc);		// distance to city
	    if (dtry >= min) continue;	// not minimum
	    if (!edger(cloc)) continue;	// if not a port city
	    if (patsea(loc,cloc))		// if a path by sea
	    {   u.ifo = IFOcitytar;
		u.ila = cloc;
		min = dtry;			// set new minimum
	    }
      }
      if (flag && min == 10000)
      {   flag = 0;
	    goto L1;
      }
      return min != 10000;			// true if we found one
    }


    /**************************
     * Look for city target for a ship.
     * Input:
     *	uninum
     * Output:
     *	uniifo[],uniila[]
     * Returns:
     *	true	if one is found.
     */

    int shipta(Unit *u)
    {   loc_t loc,cloc;
      uint min,dtry,i,end;
      Player *p = this;

      loc = u.loc;
      assert(chkloc(loc));
      min = 10000;				// arbitrary # larger than any dist
      for (i = CITMAX; i--;)		// loop thru cities
      {   if (!p.target[i])		// if city is not a target
		continue;
	    if (!city[i].own) continue;	// it's not an enemy city
	    cloc = city[i].loc;		// loc of city
	    if (!cloc) continue;		// city doesn't exist
	    assert(chkloc(cloc));
	    dtry = dist(loc,cloc);		// distance to city
	    if (dtry >= min) continue;	// not minimum
	    if (!edger(cloc)) continue;	// if not a port city
	    if (!patsea(loc,cloc))		// if not a path by sea
		continue;
	    u.ifo = IFOcitytar;
	    u.ila = cloc;
	    min = dtry;			// set new minimum
      }
      return min != 10000;			// true if we found one
    }


    /*******************************
     * Search for a TT to escort. If one is found,
     * set ifo and ila accordingly and return.
     */

    int shiptt(Unit *u)
    {   loc_t loc,uloc;
      uint end,i;
      Player *p = this;

      loc = u.loc;
      assert(chkloc(loc));
      i = end = empire.random(unitop);
      do
      {   if (unit[i].typ == T &&		// looking for troop transports
	    (uloc = unit[i].loc) != 0 &&	// it exists
	    unit[i].own == p.num &&	// we own it
	    patsea(loc,uloc))		// path by sea
	    {   u.ifo = IFOescort;
		u.ila = i;			// ila = TT number
		return true;		// found one
	    }
	    i++;
	    if (i >= unitop) i = 0;
      } while (i != end);
      return false;
    }

    /***************************
     * For ships, look thru troopt[] for the closest one to attack.
     * If one is found, set ifo, ila and return true.
     */

    int shiptr(Unit *u)
    {   uint loc,tloc,min,dt,i,j,mask;
	Player *p = this;
	static uint nshprf[6] =		// which rows to look at
	[   mD|mT|mS,			// D: DT S...
	    mT,				// T: .T ....
	    mD|mT|mS,			// S: DT S...
	    mD|mT|mS|mR|mC,		// R: DT SRC.
	    mD|mT|mS|mC,		// C: DT S.C.
	    mD|mT|mS|mR|mC|mB		// B: DT SRCB
	];

      loc = u.loc;
      assert(chkloc(loc));
      min = 10000;				// # larger than max distance
      mask = nshprf[u.typ - 2];		// select mask from nshprf
      for (i = D; i <= B; i++)		// loop thru 6 rows
      {   if (!(mask & msk[i]))		// if bit is not set in nshprf[]
		continue;
	    for (j = 5; j--;)		// loop thru columns
	    {   tloc = p.troopt[i-2][j];	// location of enemy ship
		if (!tloc) continue;
		assert(chkloc(tloc));
		dt = dist(loc,tloc);	// distance to ship
		if (dt < min &&		// select closest one
		   patsea(loc,tloc))	// that we can get to
		{   min = dt;		// new minimum
		    u.ifo = IFOtar;
		    u.ila = tloc;
		}
	    }
      }
      return min != 10000;			// true if we found one
    }


    /*********************************
     * If ship is a T with ifo=IFOloadarmy (loading armies), and there is an
     * army in LTR, stay put so the army can get aboard.
     * Returns:
     *	false:	*pr2 preserved
     *	true:	*pr2 = -1
     */

    int lodarm(Unit *u,dir_t *pr2)
    {   uint loc,uloc,ab,i;
	Player *p = this;

	if (u.ifo != IFOloadarmy) return false;	// only Ts can have this
	loc = u.loc;
	assert(chkloc(loc));
	if (typ[.map[loc]] == X) return false;	// if in city, don't stay put
	for (i = 8; i--;)			// loop thru 8 directions
	{   uloc = loc + arrow(i);		// location
	    ab = .map[uloc];			// what's there
	    if (typ[ab] == A &&		// if an army and
	      own[ab] == p.num &&		// own it and
	      fnduni(uloc).ifo == IFOgotoT)	// if army is trying to board
	    {   *pr2 = -1;			// stay put
		return true;		// found one
	    }
	}
	return false;
    }

    /*******************************************
     * Watch computer strategy.
     */

    void cwatch()
    {   Display *d = display;
	Text *t = &d.text;

	if (!watch)
	    return;
	if (!curloc)
	{
	    // Use first owned city
	    for (int i = 0; 1; i++)
	    {
		if (i == CITMAX)
		    return;
		if (city[i].own == num)
		{   curloc = city[i].loc;
		    break;
		}
	    }
	}
	while (1)
	{   int cmd;
	    dir_t r2;
	    Unit *u;
	    City *c;

	    u = null;
	    if (.typ[.map[curloc]] >= 0)
	    {   u = fnduni(curloc);
		if (u.own != num)
		    u = null;
	    }
	    c = null;
	    if (.typ[.map[curloc]] == X)
	    {   c = fndcit(curloc);
		if (c.own != num)
		    c = null;
	    }
	    if (!d.insect(curloc,2))
		center(curloc);
	    if (u)
		d.headng(u);
	    else if (c)
		typcit(this,c);
	    d.pcur(curloc);
	    cmd = t.TTin();
	    switch (cmd)
	    {
		case 3:
		case ESC:
		    return;
		case ' ':
		    if (!c && u)
		    {
			Mmove(u);
			if (u.loc)
			    curloc = u.loc;
		    }
		    break;
		default:
		    if (cmdcur(&curloc,cmd,&r2))
			break;
		    t.bell();
		    break;
	    }
	}
    }

/* ================================================================== */

    /*********************************
     * Update numown, numtar, numphs for computer strategy.
     */

    void cityct()
    {   int i;
        Player *p = this;

        for (i = TYPMAX; i--;)		// clear arrays
	    p.numuni[i] = p.numphs[i] = 0;
        p.numown = p.numtar = 0;

        for (i = unitop; i--;)		// loop thru units
        {   Unit *u = &unit[i];

	    if (!u.loc) continue;	// unit doesn't exist
	    if (u.own != p.num)
		continue;		// it isn't ours
	    p.numuni[u.typ]++;		// count up how many
        }

        for (i = CITMAX; i--;)		// loop thru cities
        {   if (p.target[i])		// if city is a target
		p.numtar++;		// number of targets
	    if (city[i].own == p.num)	// if we own the city
	    {   p.numown++;		// number owned
		if (!(city[i].phs & ~7))	// if valid phase
		    p.numphs[city[i].phs]++;	// # of cities w each phase
	    }
        }
    }

    /*************************************
     * Select initial phase for computer.
     */

    void cphasin(City *c)
    {
	c.phs = F;				// produce fighters
	c.fnd = typx[F].phstart;		// set completion date

    }

    /**********************************
     * Select city phases for enemy.
      */

    void cityph()
    {
      City *c;
      int iniphs;				// initial city phase
      int crowd;				// true if unit is crowded
      int i;				// city number
      loc_t loc;
      int edge;				// # of seas around city
      Player *p = this;

      p.cityct();				// bring city vars up to date
      for (i = CITMAX; i--;)		// loop thru cities
      {   c = &city[i];
	    if (p.num != c.own)
		continue;			// it's not ours
	    loc = c.loc;
	    edge = edger(loc);		// # of seas around city
	    iniphs = c.phs;		// remember initial phase
	    crowd = Ecrowd(loc);		// evaluate crowding conditions

	    if (iniphs & ~7)		// if illegal phase
		goto nophs;

	    if (c.fnd != p.round + typx[iniphs].prodtime - 1)
		continue;			// if not just produced something

	    /* Evaluate phase and select a new one if necessary.
	     */

	    if (edge == 8)			// if island city
	    {   island(c);			// evaluate phase for island city
		goto L401;
	    }

	    if (c.phs == F)		// if making fighters
	    {   if (p.numuni[F] && p.numown == 1)
		    goto nophs;
	    }
	    if (c.phs) continue;	// if not making armies
	    if (nearct(loc) <= 5) continue;	// if not many As nearby
	    if (crowd) goto nophs;		// the armies are crowded
	    if (p.numphs[A] <= 1)		// if only 1 city making armies
		continue;

    nophs:	c.phs = A;			// default to making armies

	    if (edge == 8)			// if island
		island(c);
	    else
	    {
		if (!ckloci(c) &&		// if no enemy armies nearby
		    !makfs(c,crowd,edge))	// if we don't make As or Fs
		    selshp(c);		// select a ship

		if (edge &&			// if not land-locked
		    !p.numphs[T] &&	// and we're not making Ts
		    p.numown > 1)		// and we've got more than 1 city
		    c.phs = T;		// then make Ts
	    }
    L401:	if (c.phs == iniphs)		// if phase didn't change
		continue;
	    c.fnd = p.round + typx[c.phs].phstart;
	    p.cityct();			// update variables

	    debug
	    {
		Display *d = p.display;
		Text *t = &d.text;
		t.curs(0x400);
		t.vsmes("City at %u,%u from %d to %s",
			ROW(loc),COL(loc),iniphs,d.nmes_p(c.phs,2));
	    }

      } // for
    }


    /********************************
     * Count up & return the number of our armies within 6 spaces of loc
     * and on the same continent.
     * Input:
     *	loc	of city
     */

    int nearct(loc_t loc)
    {   int n,j,uloc;

	n = 0;				// count
	for (j = unitop; j--;)		// loop thru units
	{   if (unit[j].typ) continue;	// if not an army
	    if (unit[j].own != num) continue;	// we don't own it
	    if ((uloc = unit[j].loc) == 0) continue;	// unit doesn't exist
	    if (dist(loc,uloc) > 6) continue;	// too far away
	    if (typ[map[uloc]] == T) continue;	// if A is on a T
	    if (patlnd(uloc,loc))		// if on same continent
		n++;			// count
	}
	return n;
    }


    /*************************************
     * Evaluate city phase for an island city.
     * Input:
     *	i	city number
     */

    void island(City *c)
    {   Player *p = this;

	if (p.numown > 1)			// if own more than 1 city
	{   if (!c.phs)			// if making armies
		selshp(c);			// select a ship
	}
	else if (!p.numuni[T])		// if we don't have any Ts
	    c.phs = T;			// then make some
	else
	    c.phs = A;			// make armies
    }


    /***********************************
     * Select a ship to be produced, giving priority to 2 T and 1 C
     * producing cities.
     * Input:
     *	i	city #
     */

    void selshp(City *c)
    {   Player *p = this;
	int j;

	c.phs = B;			// try battleships
	j = B - 1;
	while (j >= D)
	{   if (p.numphs[j] <= p.numphs[j + 1])
		c.phs = j;		// priority to cheaper ships
	    j--;
	}
	if (!p.numphs[C])		// if nobody making Cs
	    c.phs = C;
	if (p.numphs[T] < 2)	// if not 2 making Ts
	    c.phs = T;
    }


    /************************************
     * If any enemy armies on the continent, make As and return true.
     * Input:
     *	i	city #
     *	loc	city location
     */

    int ckloci(City *c)
    {   Player *p = this;
	int j;
	uint *pl;

	pl = p.loci;			// pl . start of loci array
	for (j = LOCMAX; j--; pl++)
	{   if (!*pl) continue;		// no loci
	    if (patlnd(c.loc,*pl))		// if on same continent
	      {   c.phs = A;			// make armies
		return true;
	      }
	}
      return false;
    }


    /**********************************
     * Determine whether As or Fs should be made. If so,
     * set citphs[] and return true.
     * Input:
     *	i	city #
     *	loc
     *	edge
     */

    int makfs(City *c,int crowd,int edge)
    {   Player *p = this;

	if (!edge)				// if land-locked city
	{   if (p.numuni[A] <= 3 * p.numuni[F] && !crowd)
		c.phs = A;
	    else
		c.phs = F;
	    return true;
	}
	if (nearct(c.loc) <= 2 && !crowd)	// if few armies nearby
	{   c.phs = A;
	    return true;
	}
	c.phs = F;
	return p.numuni[F] < p.numown / 2;
    }


/* ================================================================== */

    /**************************************
     * Update computer strategy variables.
     * Input:
     *	loc =	location to update
     */

    void updcmp(loc_t loc)
    {	ubyte ab;
	Player *p = this;

      ab = .map[loc];			// get map value
      if (own[ab] == p.num)
	    return;			// return if we own it

      if (typ[ab] == X)			// if unowned or enemy city
      {   p.target[fndcit(loc) - &city[0]] = 1;	// indicate target
	    return;
      }

      if (!own[ab]) return;		// if not enemy unit

      if (typ[ab] == A)			// if enemy army
      {   threat(loc);			// check for threatened cities
	    updloc(loc);		// update LOCI array
	    return;
      }

      if (typ[ab] >= D)			// if enemy ship
	    updtro(loc,typ[ab]);	// update troopt array
    }


    /******************************
     * If any cities on the same continent as loc are threatened
     * by the enemy army at loc, reset their phases to -1 so cityph()
     * will set them to creating armies.
     */

    void threat(loc_t loc)
    {   int i;
        Player *p = this;

        for (i = CITMAX; i--;)
	{   if (city[i].own == p.num &&	// if we own the city
	    city[i].phs != A &&		// if not already producing As
	    city[i].phs != -1 &&	// if not unassigned
	    city[i].loc &&			// if city exists
	    city[i].fnd >= p.round + typx[city[i].phs].prodtime - 5 &&
	    p.patlnd(city[i].loc,loc))	// route to enemy army
	    {
		debug cmes(0x400,"THREAT");
		city[i].phs = -1;		// select new phase
	    }
	}
    }


    /*********************************
     * Update loci array with enemy army discovered at loc.
     */

    void updloc(loc_t loc)
    {   uint i;
	uint* pl;
	Player *p = this;

        pl = &p.loci[0];
        for (i = LOCMAX; i--;)
	    if (pl[i] == loc)
		return;
        for (i = LOCMAX; i--;)
        {   if (!pl[i])			// if slot available
	    {   pl[i] = loc;
		return;
	    }
        }
        for (i = LOCMAX - 1; i--;)
	    pl[i+1] = pl[i];			// ripple down data
        pl[0] = loc;				// insert new data
    }

    /***************************************
     * Update troopt array with the loc of the enemy
     * ship that was discovered.
     * Input:
     *	loc =	location of enemy ship
     *	ty =	type of enemy ship
     * Output:
     *	troopt array updated
     */

    void updtro(loc_t loc,uint ty)
    {   uint* pl;
      uint i;
      Player *p = this;

      pl = &(p.troopt[ty-D][0]);		// point to row
      for (i = 5; i--;)
	    if (pl[i] == loc) return;
      for (i = 5; i--;)
      {   if (!pl[i])			// if slot available
	    {   pl[i] = loc;
		return;
	    }
      }
      for (i = 5 - 1; i--;)
	    pl[i+1] = pl[i];			// ripple down data
      pl[0] = loc;				// insert new data
    }

    int patblk(loc_t beg,loc_t end)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{   int dummy;

	    return pathn(beg,end,1,okblk,&dummy);
	}

    int patcnt(loc_t beg,loc_t end)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{   int dummy;

	    return pathn(beg,end,1,okcnt,&dummy);
	}

    int patlnd(loc_t beg,loc_t end)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{   int dummy;

	    return pathn(beg,end,1,oklnd,&dummy);
	}

    int patsea(loc_t beg,loc_t end)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{   int dummy;

	    return pathn(beg,end,1,oksea,&dummy);
	}

    int patho(loc_t beg,loc_t end,int dir,byte *ok,dir_t *pr2)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{
	    return path.path(this,beg,end,dir,ok,pr2,true);
	}

    int pathn(loc_t beg,loc_t end,int dir,byte *ok,dir_t *pr2)
	in
	{
	    assert(chkloc(beg));
	    assert(chkloc(end));
	}
	body
	{
	    return path.path(this,beg,end,dir,ok,pr2,false);
	}

    // Notify player that things have happened

    void notify_destroy(Unit *u) { }	// your unit u was destroyed

    /*******************************
     * Notify current player that player p is now on round r.
     */

    void notify_round(Player *p,int r)
    {   int plysave;
	int i;
	int co40;
	char *s;
	char buf[r.sizeof * 3 + 1];
	Text *t = &display.text;

	if (!watch)
	    return;
	if (t.narrow == 2)
	    return;
	co40 = t.narrow;
	i = p.num;
	if (i >= 6)
	    return;

	if (p.defeat)
	    s = "lost";
	else
	{
	    sprintf(buf,"%d",r);
	    s = buf;
	}

	if (r <= 1 || co40 || watch == DAwindows)
	{
	    if (co40)
		t.curs(0x400 + i * 10);
	    else
		t.curs((i - 1) << 8);

	    if (p == this)		// if it's this player
	    {   if (co40)
		    t.vsmes("Yr: %s",s);
		else
		    t.vsmes("Your  : %s",s);
	    }
	    else
	    {   if (co40)
		    t.vsmes("P%d: %s",i,s);
		else
		    t.vsmes("Plyr %d: %s",i,s);
	    }
	}
	else
	{
	    t.curs(((i - 1) << 8) + 8);
	    t.vsmes(s);
	}
    }

    /**************************************
     * Notify that p has been defeated.
     * p might be you.
     */

    void notify_defeated(Player *p)
    {
	if (p == this)			// if this means you
	    display.lost();		// then you lost
	else
	    display.plyrcrushed(p);	// someone else lost
    }


    /****************************************
     * Your city has been captured by the enemy.
     * Update strategy variables.
     */

    void notify_city_lost(City *c)
    {
	if (!human)
	    target[c - &city[0]] = 1;			// it's now a target
    }

    /**************************************
     * You have conquered a new city.
     * Update strategy variables.
     */

    void notify_city_won(City *c)
    {
	if (human)
	{
	    display.delay(1);
	    sensor(c.loc);
	    c.fipath = 0;
	    phasin(c);
	}
	else
	{
	    c.round = 50;
	    target[c - &city[0]] = 0;		// it's no longer a target
	}
    }

    /************************************************
     * We've been attacked, but repelled the invasion.
     */

    void notify_city_repelled(City *c)
    {
	if (!human)
	    c.round = 50;			// send some fighters here
    }


//private:

    /**************************************
     * For Ts and Cs, drag along any As and Fs that are aboard, and destroy
     * any extra.
     */

    void drag(Unit *u)
    {   int type = u.typ,		// T or C
	    typabd = F,			// assume F (type == C)
	    numabd = 0,			// number aboard
	    numdes = 0,			// number destroyed
	    nummax = u.hit;		// max # allowed
        int i;
        Player *p = this;
        Display *d = p.display;

        if (type == T)			// if troop transport
        {   typabd = A;			// looking for armies
	    nummax *= 2;			// allow 6 on board
        }

      for (i = unitop; i--;)		// loop thru all units
      {   Unit *ua = &unit[i];

	    if (ua.loc != locold ||	// if not on old location
		ua.typ != typabd)		// wrong type
		continue;
	    numabd++;			// it's an A or F aboard
	    ua.loc = u.loc;		// drag unit to new location
	    if (numabd > nummax)		// too many aboard
	    {
		p.notify_destroy(ua);
		ua.destroy();		// destroy the unit
		numdes++;			// remember how many trashed
	    }
      }

      if (numdes)				// if we trashed anything
	    d.overloaded(u.loc,typabd,numdes);
    }


    void eomove(loc_t loc)			// end of move processing
    {
	assert(loc < MAPSIZE);
	sensor(loc);			// do sensor probe for new loc
	if (snsflg)				// if do sensor for enemy
	    get(snsflg).sensor(loc);	// do sensor for enemy
	if (watch && !human)
	    display.pcur(loc);
    }

    /*********************************
     * Input:
     *	type =	unit type
     *	loc =	location
     *	ac =	sea or land (MAPsea or MAPland)
     * Output:
     *	change ref map to correct map value
     */

    void change(uint type,loc_t loc,uint ac)
    {
	assert(loc < MAPSIZE && (ac == MAPsea || ac == MAPland) && type <= B);
	type += 5 + 10 * (num - 1);		// offset to army
	if (ac == MAPsea)			// if moving onto sea
	    type++;				// offset for two Fs
	.map[loc] = type;			// update reference map
    }

    void killit(Unit *u)		// kill the unit
    {
	eomove(u.loc);			// do any sensor probes
	u.loc = locold;			// put back in old loc
	kill(u);			// messages, etc.
    }


    /*************************************
     * Perform a battle between attacker and defender.
     * Input:
     *	attnum =	unit # of attacker
     *	loc =		loc of defender
     * Output:
     *	unihit[]	updated for winner
     *	uniloc[]	set to 0 for loser, loc for winner
     * Return:
     *	true		if attacker loses
     */

    int fight(Unit *uatt,loc_t loc)
    {   int Hatt,Satt,Hdef,Sdef;		// hits & strike capability
        int Hwin;
        Unit *udef;				// defending unit
        Unit *uwin;				// winning unit
        Unit *ulos;				// losing unit
        Player *pdef;
        Player *pwin;
        Player *plos;

        Hatt = Satt = Hdef = Sdef = 1;		// all to 1 initially

        if (uatt.typ >= D)			// if ship
	    Hatt = uatt.hit;			// set hits of attacker
        if (uatt.typ == S)			// if submarine
	    Satt = 3;				// for torpedos

      uatt.loc = ~0u;				// so fnduni won't find attacker
      udef = fnduni(loc);			// get defender
      uatt.loc = loc;				// restore
      pdef = get(udef.own);

      if (udef.typ >= D)
	    Hdef = udef.hit;
      if (udef.typ == S)
	    Sdef = 3;			// do same for defender

      /*
       * hit attacker and defender until one is destroyed
       */

      while (true)
      {   if (ranq() & 1)			// hit attacker
	    {   if ((Hatt -= Sdef) <= 0)	// if attacker is destroyed
		{
		    uwin = udef;
		    ulos = uatt;
		    Hwin = Hdef;

		    pwin = pdef;
		    plos = this;
		    break;
		}
	    }
	    else				// hit defender
	    {   if ((Hdef -= Satt) <= 0)	// if defender is destroyed
		{   // attacker wins
		    uwin = uatt;
		    ulos = udef;
		    Hwin = Hatt;

		    pwin = this;
		    plos = pdef;
		    break;
		}
	    }
      }
      if (uwin.typ >= D)
	    uwin.hit = Hwin;

	pdef.display.underattack(udef);

	if (pwin != plos)
	    pwin.display.battle(pwin,uwin,ulos);
	plos.display.battle(plos,uwin,ulos);

	if (ulos == udef)
	    kill(ulos);			// kill the loser's unit
	return uwin != uatt;		// true if attacker loses
    }


    /******************************
     * Given a location and a command, find out if the command
     * is a direction command. If it is, try to move the cursor
     * in that direction. If that fails, change sectors so you
     * can. If that fails, return with location and cursor unchanged.
     * Input:
     *	ploc .		location of cursor
     *	cmd		the command
     *	pr2 .		where to put the direction
     * Output:
     *	if (cmd is valid direction command)
     *		if (good command)
     *			*ploc =	new location
     *			*pr2 = direction
     *		else
     *			*ploc,*pr2 preserved
     *		return true
     *	else
     *		*ploc,*pr2 preserved
     *		return false
     * Returns:
     *	true		if valid direction command
     */

    int cmdcur(loc_t *ploc,uint cmd,dir_t *pr2)
    {   static int dirtab[] = ['D','E','W','Q','A','Z','X','C'];
        static int dirtab2[] = [77*256,73*256,72*256,71*256,	// scan codes
			      75*256,79*256,80*256,81*256];
      Player *p = this;
      Display *d = p.display;

      loc_t newloc;
      int i;

      for (i = 0; 1; i++)
      {
	    if (i == 8)
		return false;		// bad direction command
	    if (cmd == dirtab[i] || cmd == dirtab2[i])
		break;
      }

      newloc = *ploc + arrow(i);		// try new location
      if (mapgen)				// if in map editor
      {   if (newloc < 0 || newloc >= MAPSIZE)
		return false;
	    if (border(*ploc) && border(newloc) && COL(*ploc) != COL(newloc))
		return false;
      }
      else					// else in game
      {   assert(newloc < MAPSIZE);
	    if (border(newloc)) return false;	// can't move on border
      }
      *pr2 = i;
      *ploc = newloc;			// set return parameters
      if (!d.insect(newloc,2))		// if not in current sector
	    p.sector(d.adjust(d.secbas + arrow(i)));	// print new sector
      return true;
    }


    /*************************************
     * Find next computer player.
     */

    Player* nextp()
    {   int i;

	for (i = num + 1; 1; i++)
	{
	    if (i > numply)
		i = 1;
	    break;
	}
	return get(i);
    }


    /**********************************
     * Exchange display with that of another player.
     */

    void exchange_display(Player *p)
    {   Display *d;
	int w;

	if (p != this)
	{
	    d = display;
	    display = p.display;
	    p.display = d;

	    w = watch;
	    watch = p.watch;
	    p.watch = w;

	    w = secflg;
	    secflg = p.secflg;
	    p.secflg = w;

	    repaint();
	    p.repaint();
	}
    }


    /*************************************
     * Repaint display.
     */

    void repaint()
    {
	if (watch)
	{
	    Display *d = display;

	    d.secbas = -1;
	    d.text.clear();
	    if (defeat || numleft == 1)
		sector(0);
	}
    }

}

