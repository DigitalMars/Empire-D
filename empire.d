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

module empire;

import std.random;

alias dir_t = int;        // direction
alias loc_t = uint;        // location

enum : loc_t {
	LOC_INVALID,
	LOC_HIDDEN,
	LOC_LASTMAGIC = LOC_HIDDEN
}

// this method is used only in debug to make things predictable
void setran() {
    std.random.rndGen().seed(3749);
    //std.random.rand_seed(37, 49);
}
uint random(uint p) {
    return std.random.uniform(0, p);
    //return std.random.rand() % p;
}
uint ranq() {
    return std.random.uniform!uint;
    //return std.random.rand();
}

const int ERRTERM	= 1;

// Definitions for typ[MAPMAX] array (X=city, J=not unit or city)
enum
{
    J = -1,
    X = -2,
    A = 0,
    F = 1,
    D = 2,
    T = 3,
    S = 4,
    R = 5,
    C = 6,
    B = 7,
}

enum
{
    mA = 0x80,
    mF = 0x40,
    mD = 0x20,
    mT = 0x10,
    mS = 0x08,
    mR = 0x04,
    mC = 0x02,
    mB = 0x01,
}

const int TYPMAX	= 8;	// number of types
const int UNIMAX	= 500;	// max number of units
//const int UNIMAX	= 8;
const int CITMAX	= 70;	// max number of cities
const int MAPMAX	= (4 + PLYMAX * 10);	// number of map elements
const int LOCMAX	= 10;	// size of loci array
const int PLYMAX	= 6;	// number of players
const int VERSION	= 1;	// version number
const int NEW		= 1;	// new computer strategy

debug
{
    const int	PLYMIN	= 1;	// minimum number of players
}
else
{
    const int	PLYMIN	= 2;	// minimum number of players
}


// Some ascii characters
enum
{
    BEL	= 7,
    BS	= 8,
    TAB	= 9,
    LF	= 10,
    FF	= 12,
    CR	= 13,
    ESC	= 27,
    SPC	= 32,
    DEL	= 127,
}

// map row and column limits (0..Mrowmx,0..Mcolmx)
const uint Mrowmx	= 59;
const int Mcolmx	= 99;
const int MAPSIZE	= ((Mrowmx + 1) * (Mcolmx + 1));

int ROW(loc_t loc) { return loc / (Mcolmx + 1); }
int COL(loc_t loc) { return loc % (Mcolmx + 1); }

// Which maptab to use
enum
{
    MTmono	= 0,	// For the monochrome screen.
    MTcgacolor	= 1,	// For the color/graphics adapter with a color monitor.
    MTcgabw	= 2,	// For the color/graphics adapter with a b/w monitor.
    MTterm	= 3,	// For terminals.
}

// Some display attributes (for watch[])
enum
{
    DAnone	= 0,	// not watching this guy
    DAdisp	= 1,	// use disp package (IBM compatible displays)
    DAmsdos	= 2,	// talk thru MS-DOS
    DAcom1	= 3,	// talk to com1:
    DAcom2	= 4,	// talk to com2:
    DAconsole	= 5,	// Win32 console
    DAwindows	= 6,	// Win32 GUI app
}

/////////////////////////////////
// Map values

enum
{
    MAPunknown	= 0, // ' '
    MAPcity     = 1, // '*'
    MAPsea      = 2, // '.'
    MAPland     = 3  // '+'
}

struct City
{
    ubyte own;		// who owns the city, 0 if nobody
    byte phs;		// what the city is producing
    loc_t loc;		// city location, or 0
    uint fnd;		// completion round number

    // Human strategy
    loc_t fipath;	// where to send fighter

    // Computer strategy
    uint round;		// turn it was captured
}

// Ifo functions (same as in hmove.c):

enum
{
    fnAW	= 0,
    fnSE	= 1,
    fnRA	= 2,
    fnMO	= 3,
    fnDI	= 4,
    fnFI	= 5,
}

enum
{
    IFOnone       =  0,	// no function assigned
    IFOgotoT      =  1,	// A: go to troop transport
    IFOdirkam     =  2,	// F: directional, kamikaze
    IFOdir        =  3,	// directional
    IFOtarkam     =  4,	// F: target, kamikaze
    IFOtar        =  5,	// target location
    IFOgotoC      =  6,	// F: goto carrier number
    IFOcity       =  7,	// F,ships: goto city location
    IFOdamaged    =  8,	// ships: damaged and going to port
    IFOstation    =  9,	// C: stationed
    IFOgstation   = 10,	// C: goto station
    IFOcitytar    = 11,	// ships: goto city target
    IFOescort     = 12,	// ships: escort TT number
    IFOshipexplor = 13,	// ships: look at unexplored territory
    IFOloadarmy   = 14,	// T: load up armies
    IFOacitytar   = 15,	// A: city target
    IFOfolshore   = 16,	// A: follow shore
    IFOonboard    = 17,	// A: on board a T
}

struct Unit
{
    loc_t loc;		// location
    ubyte own;		// owner
    ubyte typ;		// type A..B
    ubyte ifo;		// IFOxxxx ifo of unit function
    uint ila;		// ila of unit function
    ubyte hit;		// hits left, fuel left for fighter
    ubyte mov;		// !=0 if unit has moved this turn

    void destroy()	// destroy the unit
    { loc = 0; }

    // Human strategy

    // Computer strategy
    uint abd;		// T,C: number of As (Fs) aboard (0 if not T (C))
    int dir;		// direction (1 or -1)
    int fuel;		// F:range used for strategy selection
}

// Describes unit type
struct Type
{
    ubyte prodtime;  // production times
    ubyte phstart;   // starting production times
    char unichr;     // character representation for city phase purposes
    int hittab;      // hits left (value for F is fuel, for A is 0
                     // for computer strategy)
}

enum
{
    mdNONE	= 0,
    mdMOVE	= 1,
    mdSURV	= 2,
    mdDIR	= 3,
    mdTO	= 4,
    mdPHAS	= 5,
}



// #define DS(x)  ((x)*256+18)
