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

module winemp;

enum
{

    BMP_CURSOR		= 140,
    BMP_SPLASH		= 141,
    BMP_UNKNOWN10	= 142,
    BMP_BLAST		= 143,
    BMP_BLASTMASK	= 144,

    IDD_ARMIES		= 150,
    IDD_FIGHTERS	= 151,
    IDD_DESTROYERS	= 152,
    IDD_TRANSPORTS	= 153,
    IDD_SUBMARINES	= 154,
    IDD_CRUISERS	= 155,
    IDD_CARRIERS	= 156,
    IDD_BATTLESHIPS	= 157,

    IDD_SENSOR		= 158,
    IDD_TILE		= 159,

    IDD_ONE			= 161,
    IDD_TWO			= 162,
    IDD_THREE		= 163,
    IDD_FOUR		= 164,
    IDD_FIVE		= 165,
    IDD_SIX			= 166,

    IDD_DEMO		= 167,

    IDM_NEW			= 170,
    IDM_OPEN		= 171,
    IDM_SAVE		= 172,
    IDM_SAVE_AS		= 200,
    IDM_ABOUT		= 173,
    IDM_CLOSE		= 174,
    IDM_SOUND		= 175,
    IDM_F			= 176,
    IDM_G			= 177,
    IDM_H			= 178,
    IDM_I			= 179,
    IDM_K			= 180,
    IDM_L			= 181,
    IDM_N			= 182,
    IDM_P			= 183,
    IDM_R			= 184,
    IDM_S			= 185,
    IDM_U			= 186,
    IDM_Y			= 187,
    IDM_ESC			= 188,
    IDM_FASTER		= 189,
    IDM_SLOWER		= 190,
    IDM_HELP		= 191,
    IDM_ZOOMIN		= 192,
    IDM_ZOOMOUT		= 193,
    IDM_POV			= 194,

}
