; Rally-X (MSX, Namcot, third release, 1984)
; Disassembled by Ricardo Bittencourt (bluepenguin@gmail.com)
; Last update at 2026-06-27
;
	output "rallyx_v3.rom"
	org 04000h

SAT_MIRROR                       equ     0E000h    ; RAM copy of sprite attribute table; uploaded to VRAM 0700h each frame
SAT_SLOT0_PATTERN_COLOR          equ     0E002h    ; SAT slot 0 pattern+color (16-bit write); set to 844h at game-over
SAT_SLOT1_Y                      equ     0E004h    ; Y-coord of SAT slot 1; written to D0h to terminate sprite list at game-over
SPRITE_PATTERN_WORK_BUF          equ     0E060h    ; 96-byte work area inside TEMP_SPACE; bit-transposed before VRAM upload
GAME_ACTIVE                      equ     0E080h    ; Non-zero ⇒ gameplay running (gates UPDATE_SOUND output and pause input)
HIGH_SCORE_BCD                   equ     0E081h    ; 3-byte BCD high score; displayed via UNPACK_BCD_DIGITS (default 200h)
HIGH_SCORE_BCD_HIGH              equ     0E083h    ; Top byte of HIGH_SCORE_BCD (+2); cleared in INITIAL_STATE_HANDLER
STATE_HANDLER_VECTOR             equ     0E085h    ; 16-bit pointer to current state handler; VBLANK_HANDLER tail-jumps via jp (hl)
FRAME_TICK                       equ     0E087h    ; Free-running per-frame counter; many handlers read this for animation timing
WORLD_X_POS                      equ     0E088h    ; 16-bit world X coordinate; SBC by player movement drives WORLD_SCROLL_DX
PLAYER_VELOCITY_X                equ     0E089h    ; Signed 8-bit X velocity (mirror of PLAYER_VELOCITY_Y); picks TILE_SLICE_N
WORLD_Y_POS                      equ     0E08Ah    ; 16-bit world Y coordinate
PLAYER_VELOCITY_Y                equ     0E08Bh    ; Player Y velocity; bit 7 = direction, lower bits = magnitude
STEP_COUNTER_HIGH                equ     0E08Ch    ; Companion byte to STEP_COUNTER; inc'd 3x by MOVE_PLAYER_DIRECTION_0/2
STEP_COUNTER                     equ     0E08Dh    ; Inc'd by 3 each player step; possibly drives distance bonus
NAME_BANK_FLAG                   equ     0E08Eh    ; Selects VDP R2 between name=0400h (0) and name=1400h (non-zero)
PLAYER_WORLD_POSITION_X          equ     0E08Fh    ; Signed 8-bit X-axis world position; +X velocity -> PLAYER_SCREEN_X
PLAYER_WORLD_POSITION_Y          equ     0E090h    ; Signed 8-bit Y-axis world position; mirror of PLAYER_WORLD_POSITION_X
PLAYER_DIRECTION                 equ     0E091h    ; Lower 2 bits select 1 of 4 facings (target for DRAW_PLAYER_CAR rotation)
PLAYFIELD_SCROLL_OFFSET          equ     0E092h    ; 16-bit world scroll/position offset; clamped to (0, C000h)
SAT_MIRROR_CURSOR                equ     0E094h    ; Write cursor into SAT_MIRROR; reset every frame by VBLANK_GAME_FRAME
WORLD_SCROLL_DX                  equ     0E096h    ; Per-frame world X delta added to object positions by SCROLL_OBJECTS_*
WORLD_SCROLL_DY                  equ     0E097h    ; Per-frame world Y delta added to object positions by SCROLL_OBJECTS_*
RNG_LCG                          equ     0E098h    ; 1-byte LCG state advanced by NEXT_RANDOM (x' = 5x + 1)
RNG_LFSR                         equ     0E099h    ; 2-byte LFSR state (xor-shift) advanced by NEXT_RANDOM
ROCK_SPAWN_COUNT                 equ     0E09Ch    ; Loaded from STAGE_PARAM_TABLE; loop count for SCROLL_ROCKS seeding
ENEMY_CAR_ITER_TIMER             equ     0E09Dh    ; Start-of-stage grace timer; while non-zero, enemy contact isn't lethal (5A7Eh)
PLAYER_SCREEN_X                  equ     0E0A3h    ; Per-frame: PLAYER_WORLD_POSITION_X + PLAYER_VELOCITY_X (offset)
PLAYER_SCREEN_Y                  equ     0E0A4h    ; Per-frame: PLAYER_WORLD_POSITION_Y + PLAYER_VELOCITY_Y (offset)
RADAR_LAST_DOT_PTR               equ     0E0A5h    ; 16-bit ptr to the radar cell most recently written by UPDATE_RADAR_DOT_*
SMOKE_COOLDOWN                   equ     0E0A7h    ; Counts down after a smoke drop; gates subsequent DEPLOY_SMOKE_IF_INPUT
SMOKE_TRAIL_WRITE_PTR            equ     0E0A8h    ; Write cursor into SMOKE_TRAIL_TABLE (advances by 10h per spawn)
SMOKE_TRAIL_WRITE_INDEX          equ     0E0AAh    ; 0..8 ring index; wraps to 0 after 9 entries
PLAYER_ROTATION_PHASE            equ     0E0ABh    ; Current animation phase (0..2Fh); slewed toward target by DRAW_PLAYER_CAR
FRAME_TICK_SUB                   equ     0E0ACh    ; Sub-counter cleared at GAMEPLAY_INIT; advances within FRAME_TICK
MOVEMENT_SUB_PHASE               equ     0E0ADh    ; Cleared at GAMEPLAY_INIT; tracked alongside PLAYER_ROTATION_PHASE
STAGE_DIFFICULTY                 equ     0E0AEh    ; Branch key in LOAD_STAGE_PARAMS (thresholds at 6 and 3 select one of 3 rows)
STAGE_CLEAR_FLAG                 equ     0E0AFh    ; Non-zero ⇒ trigger STAGE_CLEAR_BONUS at next frame check
STAGE_PALETTE_INDEX              equ     0E0B0h    ; Drives palette selection in INIT_PLAYFIELD_PATTERNS via (val>>2)&3
SCORE_BCD                        equ     0E0B1h    ; 3-byte BCD score (6 digits); unpacked by UPDATE_SCORE_HUD via UNPACK_BCD_DIGITS
SCORE_BCD_MID                    equ     0E0B2h    ; SCORE_BCD+1; tested by CHECK_SCORE_MILESTONE for 2/8 extra-life thresholds
SCORE_BCD_HIGH                   equ     0E0B3h    ; Top byte of SCORE_BCD (+2); cleared in INITIAL_STATE_HANDLER
BONUS_BCD                        equ     0E0B4h    ; 4-byte BCD bonus counter from STAGE_CLEAR_BONUS via BCD_ADD_TO_BONUS overlap
LIVES                            equ     0E0B5h    ; Lives remaining; decremented on death, gates jump back to title
VBLANK_PARITY                    equ     0E0B6h    ; Inc'd at top of VBLANK_GAME_FRAME; low bit gates alternating refresh path
STAGE_TIMER_INNER                equ     0E0B7h    ; Inner tick counter for TICK_STAGE_TIMER; resets to E0BA on rollover
STAGE_TIMER_OUTER                equ     0E0B8h    ; Outer countdown decremented by TICK_STAGE_TIMER and TICK_FUEL_REFRESH
FUEL_LEVEL                       equ     0E0B9h    ; Depletes by 3 per smoke; UPDATE_FUEL_GAUGE renders it as a tile bar
STAGE_TIMER_RELOAD               equ     0E0BAh    ; Reload value for STAGE_TIMER_INNER when it hits zero
PLAYER_DEAD_FLAG                 equ     0E0BBh    ; Non-zero ⇒ trigger death sequence (jp DEATH_SEQUENCE from frame check)
SAVED_TIMER_FOR_DEATH            equ     0E0BCh    ; Backup of (E0B8, E0B9) preserved across DEATH_SEQUENCE
EXTRA_LIFE_AWARDED               equ     0E0BEh    ; Flag: set by CHECK_SCORE_MILESTONE to avoid awarding the same extra life twice
STAGE_DIFFICULTY_INDEX           equ     0E0BFh    ; Per-stage sub-index; offsets into STAGE_DIFFICULTY_TABLE in LOAD_STAGE_PARAMS
STAGE_ENEMY_SEED_LEN             equ     0E0C0h    ; INIT_ENEMY_CARS seed-copy length in bytes (cars*16)
ENEMY_STEP_SPEED                 equ     0E0C1h    ; Per-stage enemy step velocity (8.8); added to position accumulator each tick
ENEMY_STEP_SPEED_HI              equ     0E0C2h    ; High byte of ENEMY_STEP_SPEED 16-bit pair; only ever read as part of (E0C1)
SCROLL_LIMIT_LO                  equ     0E0C3h    ; Low byte of forward-scroll cap; PLAYFIELD_SCROLL_OFFSET stops advancing at this
SCROLL_LIMIT_HI                  equ     0E0C4h    ; High byte of forward-scroll cap (paired with SCROLL_LIMIT_LO at E0C3)
PLAYER_MOVE_GATE                 equ     0E0C5h    ; Set during death/init transitions; gates player position updates and movement
VRAM_BANK_FLAG                   equ     0E0C6h    ; Drives VDP R4 toggle between pattern bank 0800h and 1800h (double-buffer)
PAUSE_KEY_HISTORY                equ     0E0C7h    ; Shift register; CHECK_PAUSE_KEY rotates key bits into here to debounce chord
PAUSE_FLAG                       equ     0E0C8h    ; Non-zero ⇒ game frozen in VBLANK_HANDLER (PSG silenced, no game work)
GAME_OVER_FLAG                   equ     0E0C9h    ; Non-zero ⇒ play SFX_BANG and freeze music; tail of game-over sequence
FLAG_TABLE                       equ     0E100h    ; Table iterated by SCROLL_FLAGS (10 entries)
FUEL_GAUGE_BUFFER                equ     0E1E0h    ; 8-byte tile buffer rendered by UPDATE_FUEL_GAUGE then LDIRVM'd to VRAM 04D7h
FUEL_GAUGE_BUFFER_TAIL           equ     0E1E1h    ; FUEL_GAUGE_BUFFER+1 — used as LDIR destination when filling the buffer
DIGIT_TILE_BUFFER                equ     0E1F0h    ; 8-byte scratch where UNPACK_BCD_DIGITS writes tile indices for the HUD score
DIGIT_TILE_BUFFER_END            equ     0E1F8h    ; DIGIT_TILE_BUFFER+8 — end pointer used by UNPACK_BCD_DIGITS to walk backward
ROCK_TABLE                       equ     0E200h    ; Table iterated by SCROLL_ROCKS / UPDATE_ROCKS_COLLISION
ROCK_TABLE_TAIL                  equ     0E201h    ; ROCK_TABLE+1 — used as LDIR destination when clearing ROCK_TABLE
ENEMY_CAR_TABLE                  equ     0E300h    ; 6-7 entries x 16 bytes; iterated by ITERATE_ENEMY_CARS
ENEMY_CAR_TABLE_TAIL             equ     0E301h    ; ENEMY_CAR_TABLE+1 — used as LDIR destination when clearing ENEMY_CAR_TABLE
SMOKE_TRAIL_TABLE                equ     0E400h    ; 9 entries x 16 bytes; iterated by SCROLL_SMOKE_TRAILS
SMOKE_TRAIL_TABLE_TAIL           equ     0E401h    ; SMOKE_TRAIL_TABLE+1 — used as LDIR destination when clearing
PSG_MIRROR                       equ     0E500h    ; 14-byte PSG-register shadow uploaded by UPDATE_SOUND
PSG_MIRROR_PITCH_B               equ     0E502h    ; PSG R2/R3 (channel B 12-bit pitch); MUSIC_OPENING / SFX_BONUS
PSG_MIRROR_PITCH_C               equ     0E504h    ; PSG R4/R5 ch C pitch; MUSIC_STAGE_CLEAR/SFX_SMOKE/SFX_C_STAGE
PSG_MIRROR_VOL_A                 equ     0E508h    ; Mirror of PSG R8 (Channel A volume) written by SOUND_TICK_MUSIC_THEME
PSG_MIRROR_VOL_B                 equ     0E509h    ; Mirror of PSG R9 (Channel B volume) written by SOUND_TICK_SFX_*
PSG_MIRROR_VOL_C                 equ     0E50Ah    ; Mirror of PSG R10 (Channel C volume) written by SOUND_TICK_MUSIC_STAGE_CLEAR
SOUND_STATE_THEME                equ     0E510h    ; Music channel A control byte; non-zero ⇒ track active
SOUND_STATE_OPENING              equ     0E520h    ; Music channel B control byte (start jingle trigger at boot)
SOUND_STATE_STAGE_CLEAR          equ     0E530h    ; Music channel C control byte
SOUND_STATE_FLAG                 equ     0E540h    ; SFX subsystem 1 control byte
SOUND_STATE_FLAG_ALT             equ     0E541h    ; Alternate trigger byte for SFX_FLAG (second variant)
SOUND_STATE_SMOKE                equ     0E542h    ; SFX subsystem 2 control byte
SOUND_STATE_SMOKE_STREAM_PTR     equ     0E543h    ; 16-bit stream pointer for SFX_SMOKE channel
SOUND_STATE_SMOKE_COUNTER        equ     0E545h    ; Duration counter for SFX_SMOKE stream
SOUND_STATE_SMOKE_VOL_PTR        equ     0E547h    ; Pointer into volume envelope table for SFX_SMOKE
SFX_TRIGGER_SMOKE                equ     0E550h    ; Set to 1 by SPAWN_SMOKE; drives the smoke-deploy SFX
SOUND_STATE_BONUS                equ     0E551h    ; SFX subsystem 3 control byte
SOUND_STATE_BONUS_STREAM_PTR     equ     0E552h    ; 16-bit stream pointer for SFX_BONUS channel
SFX_TRIGGER_EXTRA_LIFE           equ     0E560h    ; Set to 1 by CHECK_SCORE_MILESTONE; drives the extra-life jingle
SOUND_STATE_BANG_TRIGGER         equ     0E561h    ; Alternate trigger byte adjacent to SOUND_STATE_BANG
SOUND_STATE_BANG                 equ     0E562h    ; SFX subsystem 4 control byte
SOUND_STATE_BANG_STREAM_PTR      equ     0E563h    ; 16-bit stream pointer for SFX_BANG channel
SOUND_STATE_C_STAGE              equ     0E565h    ; SFX subsystem 5 control byte
SOUND_STATE_C_STAGE_STREAM_PTR   equ     0E566h    ; 16-bit stream pointer for SFX_C_STAGE channel
SOUND_STATE_C_STAGE_COUNTER      equ     0E568h    ; Duration counter for SFX_C_STAGE stream
SOUND_STATE_C_STAGE_VOL_PTR      equ     0E569h    ; Pointer into volume envelope table for SFX_C_STAGE
PLAYFIELD_LOOKUP_TABLE           equ     0E600h    ; ~1800-byte precomputed table built by INIT_PLAYFIELD_LOOKUP
PLAYFIELD_LOOKUP_OUT_OF_BOUNDS   equ     0ED20h    ; Secondary tier of PLAYFIELD_LOOKUP_TABLE (H>=20h path)
RADAR_GRID                       equ     0EE00h    ; 112-byte radar/minimap cell grid; INIT_STAGE fills with 90h (empty)
RADAR_GRID_TAIL                  equ     0EE01h    ; RADAR_GRID+1 — used as LDIR destination when clearing RADAR_GRID to 90h
OBSTACLE_GRID                    equ     0EE80h    ; Per-cell obstacle/state layout adjacent to RADAR_GRID
TRACK_DATA_RING                  equ     0EF00h    ; 10 entries x 0x5A bytes filled by INIT_STAGE_TRACK_DATA
TRACK_DATA_RING_END              equ     0F283h    ; Last byte of TRACK_DATA_RING; LDDR top anchor when scrolling on player move

NOTE_REST                        equ     00000h    ; period table offset, rest
NOTE_O1_E                        equ     00002h    ; period table offset, 41.5 Hz  O1 E
NOTE_O1_F                        equ     00004h    ; period table offset, 44.0 Hz  O1 F
NOTE_O1_F_SHARP                  equ     00006h    ; period table offset, 46.6 Hz  O1 F#
NOTE_O1_G                        equ     00008h    ; period table offset, 49.3 Hz  O1 G
NOTE_O1_G_SHARP                  equ     0000Ah    ; period table offset, 52.3 Hz  O1 G#
NOTE_O1_A                        equ     0000Ch    ; period table offset, 55.4 Hz  O1 A
NOTE_O1_A_SHARP                  equ     0000Eh    ; period table offset, 58.8 Hz  O1 A#
NOTE_O1_B                        equ     00010h    ; period table offset, 62.1 Hz  O1 B
NOTE_O2_C                        equ     00012h    ; period table offset, 66.0 Hz  O2 C
NOTE_O2_C_SHARP                  equ     00014h    ; period table offset, 69.7 Hz  O2 C#
NOTE_O2_D                        equ     00016h    ; period table offset, 74.0 Hz  O2 D
NOTE_O2_D_SHARP                  equ     00018h    ; period table offset, 78.3 Hz  O2 D#
NOTE_O2_E                        equ     0001Ah    ; period table offset, 83.0 Hz  O2 E
NOTE_O2_F                        equ     0001Ch    ; period table offset, 87.9 Hz  O2 F
NOTE_O2_F_SHARP                  equ     0001Eh    ; period table offset, 93.2 Hz  O2 F#
NOTE_O2_G                        equ     00020h    ; period table offset, 98.6 Hz  O2 G
NOTE_O2_G_SHARP                  equ     00022h    ; period table offset, 104.5 Hz  O2 G#
NOTE_O2_A                        equ     00024h    ; period table offset, 110.8 Hz  O2 A
NOTE_O2_A_SHARP                  equ     00026h    ; period table offset, 117.5 Hz  O2 A#
NOTE_O2_B                        equ     00028h    ; period table offset, 124.3 Hz  O2 B
NOTE_O3_C                        equ     0002Ah    ; period table offset, 131.9 Hz  O3 C
NOTE_O3_C_SHARP                  equ     0002Ch    ; period table offset, 139.5 Hz  O3 C#
NOTE_O3_D                        equ     0002Eh    ; period table offset, 148.0 Hz  O3 D
NOTE_O3_D_SHARP                  equ     00030h    ; period table offset, 156.7 Hz  O3 D#
NOTE_O3_E                        equ     00032h    ; period table offset, 166.0 Hz  O3 E
NOTE_O3_F                        equ     00034h    ; period table offset, 175.9 Hz  O3 F
NOTE_O3_F_SHARP                  equ     00036h    ; period table offset, 186.4 Hz  O3 F#
NOTE_O3_G                        equ     00038h    ; period table offset, 197.3 Hz  O3 G
NOTE_O3_G_SHARP                  equ     0003Ah    ; period table offset, 209.1 Hz  O3 G#
NOTE_O3_A                        equ     0003Ch    ; period table offset, 221.5 Hz  O3 A
NOTE_O3_A_SHARP                  equ     0003Eh    ; period table offset, 235.0 Hz  O3 A#
NOTE_O3_B                        equ     00040h    ; period table offset, 248.6 Hz  O3 B
NOTE_O4_C                        equ     00042h    ; period table offset, 263.8 Hz  O4 C
NOTE_O4_C_SHARP                  equ     00044h    ; period table offset, 279.0 Hz  O4 C#
NOTE_O4_D                        equ     00046h    ; period table offset, 295.9 Hz  O4 D
NOTE_O4_D_SHARP                  equ     00048h    ; period table offset, 313.3 Hz  O4 D#
NOTE_O4_E                        equ     0004Ah    ; period table offset, 331.9 Hz  O4 E
NOTE_O4_F                        equ     0004Ch    ; period table offset, 351.8 Hz  O4 F
NOTE_O4_F_SHARP                  equ     0004Eh    ; period table offset, 372.9 Hz  O4 F#
NOTE_O4_G                        equ     00050h    ; period table offset, 395.3 Hz  O4 G
NOTE_O4_G_SHARP                  equ     00052h    ; period table offset, 419.0 Hz  O4 G#
NOTE_O4_A                        equ     00054h    ; period table offset, 443.9 Hz  O4 A
NOTE_O4_A_SHARP                  equ     00056h    ; period table offset, 470.0 Hz  O4 A#
NOTE_O4_B                        equ     00058h    ; period table offset, 497.2 Hz  O4 B
NOTE_O5_C                        equ     0005Ah    ; period table offset, 527.6 Hz  O5 C
NOTE_O5_C_SHARP                  equ     0005Ch    ; period table offset, 559.3 Hz  O5 C#
NOTE_O5_D                        equ     0005Eh    ; period table offset, 591.9 Hz  O5 D
NOTE_O5_D_SHARP                  equ     00060h    ; period table offset, 628.4 Hz  O5 D#
NOTE_O5_E                        equ     00062h    ; period table offset, 665.8 Hz  O5 E
NOTE_O5_F                        equ     00064h    ; period table offset, 703.5 Hz  O5 F
NOTE_O5_F_SHARP                  equ     00066h    ; period table offset, 745.7 Hz  O5 F#
NOTE_O5_G                        equ     00068h    ; period table offset, 793.3 Hz  O5 G
NOTE_O5_G_SHARP                  equ     0006Ah    ; period table offset, 841.1 Hz  O5 G#
NOTE_O5_A                        equ     0006Ch    ; period table offset, 887.8 Hz  O5 A
NOTE_O5_A_SHARP                  equ     0006Eh    ; period table offset, 940.0 Hz  O5 A#
NOTE_O5_B                        equ     00070h    ; period table offset, 998.8 Hz  O5 B
NOTE_O6_C                        equ     00072h    ; period table offset, 1055.3 Hz  O6 C
NOTE_O6_C_SHARP                  equ     00074h    ; period table offset, 1118.6 Hz  O6 C#
NOTE_O6_D                        equ     00076h    ; period table offset, 1190.0 Hz  O6 D
NOTE_O6_D_SHARP                  equ     00078h    ; period table offset, 1256.9 Hz  O6 D#
NOTE_O6_E                        equ     0007Ah    ; period table offset, 1331.7 Hz  O6 E
NOTE_O6_F                        equ     0007Ch    ; period table offset, 1416.0 Hz  O6 F
NOTE_O6_F_SHARP                  equ     0007Eh    ; period table offset, 1491.5 Hz  O6 F#
NOTE_O6_G                        equ     00080h    ; period table offset, 1598.0 Hz  O6 G
NOTE_O6_G_SHARP                  equ     00082h    ; period table offset, 1694.9 Hz  O6 G#
NOTE_O6_A                        equ     00084h    ; period table offset, 1775.6 Hz  O6 A
NOTE_O6_A_SHARP                  equ     00086h    ; period table offset, 1895.9 Hz  O6 A#
NOTE_O6_B                        equ     00088h    ; period table offset, 1997.5 Hz  O6 B
NOTE_O7_C                        equ     0008Ah    ; period table offset, 2110.6 Hz  O7 C
NOTE_O7_C_SHARP                  equ     0008Ch    ; period table offset, 2237.2 Hz  O7 C#
NOTE_O7_D                        equ     0008Eh    ; period table offset, 2380.0 Hz  O7 D
NOTE_O7_D_SHARP                  equ     00090h    ; period table offset, 2542.3 Hz  O7 D#
Z80_JP                           equ     000C3h    ; Z80 opcode byte for "JP nnnn" (used to inject hooks)
SPRITE_Y_TERMINATOR              equ     000D0h    ; VDP sprite Y = D0h means "end of sprite list"
TILE_BLANK                       equ     00040h    ; Tile index of the all-blank (space) character
TILE_DIGIT_0                     equ     00030h    ; Tile index for character '0' (digits are 30..39)
BIOS_WRTVDP                      equ     00047h    ; Write byte B to VDP register C
BIOS_WRTVRM                      equ     0004Dh    ; Write byte A to VRAM address HL
BIOS_SETRD                       equ     00050h    ; Point VDP read pointer at HL (VRAM read setup)
BIOS_FILVRM                      equ     00056h    ; Fill VRAM at HL with byte A, length BC
BIOS_LDIRVM                      equ     0005Ch    ; Block copy RAM(HL) -> VRAM(DE), length BC
BIOS_WRTPSG                      equ     00093h    ; Write byte E to PSG register A
BIOS_RDPSG                       equ     00096h    ; Read PSG register A; returns value in A
BIOS_RDVDP                       equ     0013Eh    ; Read VDP status S#0; acknowledges VBLANK IRQ
BIOS_SNSMAT                      equ     00141h    ; Scan keyboard matrix row A; returns inverted bits in A
BIOS_H_TIMI                      equ     0FD9Ah    ; Timer-interrupt hook (5-byte JP slot called every VBLANK)
STACK                            equ     0F380h    ; Stack top — GAME_BOOT and VBLANK_HANDLER set SP here (F380h)
COLOR_TRANSPARENT                equ     00000h    ; MSX color 0 (transparent)
COLOR_BLACK                      equ     00001h    ; MSX color 1 (black)
COLOR_GREEN_DARK                 equ     00002h    ; MSX color 2 (medium green)
COLOR_GREEN_LIGHT                equ     00003h    ; MSX color 3 (light green)
COLOR_BLUE_DARK                  equ     00004h    ; MSX color 4 (dark blue)
COLOR_BLUE_LIGHT                 equ     00005h    ; MSX color 5 (light blue)
COLOR_RED_DARK                   equ     00006h    ; MSX color 6 (dark red)
COLOR_CYAN                       equ     00007h    ; MSX color 7 (cyan)
COLOR_RED                        equ     00008h    ; MSX color 8 (medium red)
COLOR_RED_LIGHT                  equ     00009h    ; MSX color 9 (light red)
COLOR_YELLOW_DARK                equ     0000Ah    ; MSX color A (dark yellow)
COLOR_YELLOW_LIGHT               equ     0000Bh    ; MSX color B (light yellow)
COLOR_GREEN_MED                  equ     0000Ch    ; MSX color C (medium dark green)
COLOR_MAGENTA                    equ     0000Dh    ; MSX color D (magenta)
COLOR_GRAY                       equ     0000Eh    ; MSX color E (gray)
COLOR_WHITE                      equ     0000Fh    ; MSX color F (white)
ENEMY_OFFSET_TYPE                equ     00000h    ; ENEMY_CAR_TABLE entry: 0=dead, 1=normal, 2=hit-player
ENEMY_OFFSET_TIMER               equ     00001h    ; bounce / hit-state countdown
ENEMY_OFFSET_STATE               equ     00002h    ; small state counter (AI sub-phase)
ENEMY_OFFSET_X_ACCUM_LO          equ     00003h    ; X-axis subpixel accumulator low byte
ENEMY_OFFSET_X_ACCUM_HI          equ     00004h    ; X-axis accumulator high (phase wraps at 18h -> cell step)
ENEMY_OFFSET_CELL_X              equ     00005h    ; X cell coord (maze column)
ENEMY_OFFSET_Y_ACCUM_LO          equ     00006h    ; Y-axis subpixel accumulator low byte
ENEMY_OFFSET_Y_ACCUM_HI          equ     00007h    ; Y-axis accumulator high (phase wraps at 18h)
ENEMY_OFFSET_CELL_Y              equ     00008h    ; Y cell coord (maze row)
ENEMY_OFFSET_X                   equ     00009h    ; screen X position low byte
ENEMY_OFFSET_X_HI                equ     0000Ah    ; screen X high byte (must be 0 to be visible)
ENEMY_OFFSET_Y                   equ     0000Bh    ; screen Y position low byte
ENEMY_OFFSET_Y_HI                equ     0000Ch    ; screen Y high byte (must be 0 to be visible)
ENEMY_OFFSET_PATTERN             equ     0000Dh    ; sprite tile pattern
ENEMY_OFFSET_COLOR               equ     0000Eh    ; sprite color
ENEMY_OFFSET_DIR                 equ     0000Fh    ; movement direction (lower 2 bits)
SMOKE_OFFSET_ACTIVE              equ     00000h    ; SMOKE_TRAIL_TABLE entry: 0=free, 1=active
SMOKE_OFFSET_X                   equ     00003h    ; 16-bit screen X position low byte
SMOKE_OFFSET_X_HI                equ     00004h    ; X position high byte (must be 0 to be visible)
SMOKE_OFFSET_Y                   equ     00005h    ; 16-bit screen Y position low byte
SMOKE_OFFSET_Y_HI                equ     00006h    ; Y position high byte
ROCK_OFFSET_X                    equ     00003h    ; 16-bit screen X position low byte
ROCK_OFFSET_X_HI                 equ     00004h    ; X position high byte
ROCK_OFFSET_Y                    equ     00005h    ; 16-bit screen Y position low byte
ROCK_OFFSET_Y_HI                 equ     00006h    ; Y position high byte
TEMP_SPACE                       equ     0E000h    ; Boot scratch at E000 (SAT_MIRROR base): RAM-zero + pattern-assembly buffer

; Hardware: screen 1 (Graphic 1) with double-buffered VRAM banks.
;
; Memory layout (VRAM):
;   0400h name table A (32x24)
;   0700h SAT
;   0780h color (32 grps),
;   0800h pattern table A
;   1400h name table B (alt)
;   1800h pattern B
;   3000h sprite patterns.
; R4 toggles between A/B via VRAM_BANK_FLAG.
;
; Memory layout (RAM):
;   E000-E07F SAT_MIRROR, E080-E0FF game state flags/counters,
;   E100-E4FF four object tables (E100/E200/E300/E400),
;   E500-E5FF PSG mirror + sound subsystem state,
;   EE00-EEFF RADAR_GRID + OBSTACLE_GRID,
;   EF00-F3xx misc + stack (top at F380h).
;
; Frame model: VBLANK_HANDLER is hooked into BIOS_H_TIMI
; and dispatches to a state handler via STATE_HANDLER_VECTOR.
; State handlers yield via WAIT_VBLANK / WAIT_VBLANK_FINISH_SPRITES
; — both pop their caller's PC into STATE_HANDLER_VECTOR so the
; next vblank fire resumes mid-routine (coroutine-style).
;

        ; Single-instruction documentation macro: load a VRAM address into
        ; reg before a BIOS_LDIRVM / BIOS_FILVRM / BIOS_WRTVRM call. Expands
        ; to one 'ld reg, addr' (3 bytes).
        macro LOAD_VRAM_ADDRESS reg, addr
                ld      reg, addr
        endm

        ; One (note,duration) record in a music/SFX note stream. note is a
        ; NOTE_PERIOD_TABLE index (0 = rest); duration is a tick count. The
        ; player (via SOUND_ADVANCE_NOTE_DURATION) walks the stream two
        ; bytes at a time. Expands to two data bytes.
        macro NOTE note, duration
                db      note, duration
        endm

        ; One note in a flat SFX note-index stream (SFX_FLAG_STREAM_*): note is a
        ; NOTE_PERIOD_TABLE index, held a fixed time by the SFX player (no
        ; per-note duration byte). FFh ends the stream. Expands to one byte.
        macro SINGLE_NOTE note
                db      note
        endm

        ; One (X,Y) rock-spawn candidate cell in a ROCK_POSITIONS_N table.
        ; x is the maze column, y the maze row. Two bytes. Named params keep
        ; the call sites self-documenting (ROCK_POSITION x=0Bh, y=05h).
        macro ROCK_POSITION x, y
                db      x, y
        endm

        ; One per-stage record in STAGE_PARAM_TABLE (4 bytes), read by
        ; LOAD_STAGE_PARAMS. rocks = ROCK_SPAWN_COUNT; enemies = number
        ; of enemy cars, emitted as enemies*16 — the STAGE_ENEMY_SEED_LEN byte
        ; count, since each ENEMY_CAR_TABLE seed record is 16 bytes; reload =
        ; STAGE_TIMER_RELOAD; difficulty = STAGE_DIFFICULTY_TABLE record
        ; index, emitted as difficulty*0Ch (its 12-byte record stride).
        macro STAGE_PARAMS rocks, enemies, reload, difficulty
                db      rocks, enemies*16, reload, difficulty*0Ch
        endm

        ; One maze cell's 3x3 tile block in PLAYFIELD_CELL_TILES: three rows of
        ; three character codes, each passed as a "XXXXXX" hex string and
        ; emitted with dh. QUERY_PLAYFIELD_EMIT copies the 9 bytes into
        ; three successive playfield tile-buffer rows.
        macro PLAYFIELD_TILES r0, r1, r2
                dh      r0
                dh      r1
                dh      r2
        endm

        ; INITIAL_ENEMY_CARS_DATA seed record, split into four macros so the
        ; named-parameter call sites stay well within the column cap. Together
        ; they emit one 16-byte ENEMY_CAR_TABLE seed (ENEMY_OFFSET_* order); the
        ; dw fields (accumulators, screen X/Y) are little-endian words.
        ; _1: identity + AI state (offsets 0..2).
        macro ENEMY_SEED_1 type, timer, state
                db      type,timer,state
        endm

        ; _2: X/Y subpixel accumulators + maze column (offsets 3..7).
        macro ENEMY_SEED_2 x_accum, cell_x, y_accum
                dw      x_accum                 ; X subpixel accumulator (hi wraps at 18h)
                db      cell_x                  ; CELL_X (maze column)
                dw      y_accum                 ; Y subpixel accumulator (hi wraps at 18h)
        endm

        ; _3: maze row + screen position (offsets 8..0Ch).
        macro ENEMY_SEED_3 cell_y, screen_x, screen_y
                db      cell_y                  ; CELL_Y (maze row)
                dw      screen_x                ; screen X (signed; <0 = off left edge)
                dw      screen_y                ; screen Y (signed; <0 = off top edge)
        endm

        ; _4: sprite attributes (offsets 0Dh..0Fh).
        macro ENEMY_SEED_4 pattern, color, dir
                db      pattern,color,dir       ; sprite PATTERN COLOR DIR
        endm

ROM_HEADER:
        ; Cartridge header
        ; magic
        db      "AB"                                           ;#4000: 41 42
        ; init address
        dw      GAME_BOOT                                      ;#4002: 24 40
        ; CALL statement handler
        dw      0                                              ;#4004: 00 00
        ; device handler
        dw      0                                              ;#4006: 00 00
        ; BASIC program
        dw      0                                              ;#4008: 00 00
        ; reserved
        dw      0                                              ;#400A: 00 00
        ; reserved
        dw      0                                              ;#400C: 00 00
        ; reserved
        dw      0                                              ;#400E: 00 00

ROM_TITLE:
        ; ROM identifier string "newRALLYXfor MSX II" (20 bytes, ASCII)
        db      9, "newRALLYXfor MSX II"                       ;#4010: 09 6E 65 77 52 41 4C 4C 59 58 66 6F 72 20 4D 53 58 20 49 49

GAME_BOOT:
        ; Entry point for ROM startup (init vector from header)
        ; place stack just below the RDPRIM BIOS routine
        ld      sp,STACK                                       ;#4024: 31 80 F3
        di                                                     ;#4027: F3
        call    INIT_VDP_AND_LOAD_GFX                          ;#4028: CD 0E 4D
        ld      hl,VBLANK_HANDLER                              ;#402B: 21 5B 40
        ; opcode for JP nnnn, written into BIOS_H_TIMI
        ld      a,Z80_JP                                       ;#402E: 3E C3
        ld      (BIOS_H_TIMI),a                                ;#4030: 32 9A FD
        ld      (BIOS_H_TIMI+1),hl                             ;#4033: 22 9B FD
        ld      hl,TEMP_SPACE                                  ;#4036: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#4039: 11 01 E0
        ld      bc,6FFh                                        ;#403C: 01 FF 06
        ld      (hl),0                                         ;#403F: 36 00
        ldir                                                   ;#4041: ED B0
        ld      hl,INITIAL_STATE_HANDLER                       ;#4043: 21 73 43
        ld      (STATE_HANDLER_VECTOR),hl                      ;#4046: 22 85 E0
        call    LOAD_PLAYFIELD_GFX                             ;#4049: CD 5A 65
REFRESH_RNG_AND_SOUND:
        ; Tail of GAME_BOOT: stir RNG, then fall into FINISH_FRAME_AND_WAIT
        call    NEXT_RANDOM                                    ;#404C: CD EF 54
FINISH_FRAME_AND_WAIT:
        ; Tail used by GAME_BOOT and WAIT_VBLANK: call UPDATE_SOUND, ei, R1=E2h, halt
        call    UPDATE_SOUND                                   ;#404F: CD DC 68
        ei                                                     ;#4052: FB
        ; enable screen + IRQs + 16x16 sprites
        ld      bc,ROCK_TABLE_TAIL                             ;#4053: 01 01 E2
        call    BIOS_WRTVDP                                    ;#4056: CD 47 00
WAIT_FIRST_VBLANK:
        ; Tight `jr $` loop waiting for first VBLANK after boot
        jr      WAIT_FIRST_VBLANK                              ;#4059: 18 FE

VBLANK_HANDLER:
        ; Per-frame main loop, hooked into H.TIMI by GAME_BOOT
        ; VBLANK_HANDLER is reached via the BIOS_H_TIMI hook installed at GAME_BOOT. The
        ; SP is reset on every entry so the previous frame's stack is discarded —
        ; combined with the WAIT_VBLANK_* coroutine yield, this means state handlers can
        ; "block" by simply jumping into FINISH_FRAME_AND_ WAIT after saving their
        ; resume point in STATE_HANDLER_VECTOR.
        ld      sp,STACK                                       ;#405B: 31 80 F3
        call    BIOS_RDVDP                                     ;#405E: CD 3E 01
        call    CHECK_PAUSE_KEY                                ;#4061: CD E0 40
        ld      a,(PAUSE_FLAG)                                 ;#4064: 3A C8 E0
        and     a                                              ;#4067: A7
        jr      z,VBLANK_GAME_FRAME                            ;#4068: 28 06
        call    SILENCE_PSG                                    ;#406A: CD CB 40
        ei                                                     ;#406D: FB
PAUSE_HALT_LOOP:
        ; Tight `jr $` loop while PAUSE_FLAG is set (PSG already silenced)
        jr      PAUSE_HALT_LOOP                                ;#406E: 18 FE

VBLANK_GAME_FRAME:
        ; Non-paused branch of VBLANK_HANDLER; runs per-frame game work
        ; VBLANK_GAME_FRAME runs the non-paused per-frame work: increments
        ; VBLANK_PARITY, gates VDP-bank swap (R4 between 01/03 via VRAM_BANK_FLAG and R2
        ; between 01/05 via NAME_BANK_FLAG), updates FRAME_TICK, refreshes the SAT
        ; mirror to VRAM 0700h, then jumps to STATE_HANDLER_VECTOR.
        ld      hl,VBLANK_PARITY                               ;#4070: 21 B6 E0
        inc     (hl)                                           ;#4073: 34
        ld      a,(hl)                                         ;#4074: 7E
        rra                                                    ;#4075: 1F
        jr      nc,REFRESH_RNG_AND_SOUND                       ;#4076: 30 D4
        ld      a,(VRAM_BANK_FLAG)                             ;#4078: 3A C6 E0
        rra                                                    ;#407B: 1F
        jr      c,VBLANK_GAME_FRAME_R4_BANK_A                  ;#407C: 38 08
        ; R4=3 → pattern table bank B (1800h)
        ld      bc,304h                                        ;#407E: 01 04 03
        call    BIOS_WRTVDP                                    ;#4081: CD 47 00
        jr      VBLANK_GAME_FRAME_R1_WRITE                     ;#4084: 18 06

VBLANK_GAME_FRAME_R4_BANK_A:
        ; Bank-A path: VDP R4 = 01 (patterns at 0800h)
        ; R4=1 → pattern table bank A (0800h)
        ld      bc,104h                                        ;#4086: 01 04 01
        call    BIOS_WRTVDP                                    ;#4089: CD 47 00
VBLANK_GAME_FRAME_R1_WRITE:
        ; After R4 select, write R1 = C2h (display enable + VBLANK IRQ)
        ; R1=C2h → screen on, IRQ off (mid-frame state)
        ld      bc,0C201h                                      ;#408C: 01 01 C2
        call    BIOS_WRTVDP                                    ;#408F: CD 47 00
        ld      bc,102h                                        ;#4092: 01 02 01
        ld      a,(NAME_BANK_FLAG)                             ;#4095: 3A 8E E0
        and     a                                              ;#4098: A7
        jr      z,VBLANK_GAME_FRAME_R2_WRITE                   ;#4099: 28 03
        ; R2=5 → name table bank B (1400h)
        ld      bc,502h                                        ;#409B: 01 02 05
VBLANK_GAME_FRAME_R2_WRITE:
        ; Apply chosen R2 value (01h or 05h) to switch name-table bank
        call    BIOS_WRTVDP                                    ;#409E: CD 47 00
        ld      hl,FRAME_TICK                                  ;#40A1: 21 87 E0
        inc     (hl)                                           ;#40A4: 34
        ld      hl,SAT_MIRROR                                  ;#40A5: 21 00 E0
        ld      (SAT_MIRROR_CURSOR),hl                         ;#40A8: 22 94 E0
        LOAD_VRAM_ADDRESS de, 700h                             ;#40AB: 11 00 07
        ld      bc,80h                                         ;#40AE: 01 80 00
        call    BIOS_LDIRVM                                    ;#40B1: CD 5C 00
        ld      hl,(STATE_HANDLER_VECTOR)                      ;#40B4: 2A 85 E0
        jp      (hl)                                           ;#40B7: E9

WAIT_VBLANK_FINISH_SPRITES:
        ; Yield: save PC into STATE_HANDLER_VECTOR, terminate SAT, wait for VBLANK
        ; WAIT_VBLANK_FINISH_SPRITES and WAIT_VBLANK implement the coroutine yield
        ; idiom: `pop hl` grabs the caller's return address, stores it in
        ; STATE_HANDLER_VECTOR, then `jp FINISH_FRAME_AND_WAIT` (=FINISH_FRAME_AND_
        ; WAIT) which ticks sound, ei, and halts. Next vblank, VBLANK_HANDLER fires,
        ; dispatches via `jp (STATE_HANDLER_VECTOR)`, and execution resumes at the
        ; return point. The "FINISH_SPRITES" variant also writes the sprite-list
        ; terminator (D0h) before yielding.
        pop     hl                                             ;#40B8: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40B9: 22 85 E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#40BC: 2A 94 E0
        ; mark next sprite slot as end-of-list
        ld      (hl),SPRITE_Y_TERMINATOR                       ;#40BF: 36 D0
        jp      FINISH_FRAME_AND_WAIT                          ;#40C1: C3 4F 40

WAIT_VBLANK:
        ; Yield: save caller PC into STATE_HANDLER_VECTOR, wait for next VBLANK
        pop     hl                                             ;#40C4: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40C5: 22 85 E0
        jp      FINISH_FRAME_AND_WAIT                          ;#40C8: C3 4F 40

SILENCE_PSG:
        ; Zero PSG channel-volume registers (R8/R9/R10)
        ; SILENCE_PSG writes 0 to PSG R8/R9/R10 (channel A/B/C amplitude registers). All
        ; 3 channels go silent. Called when entering PAUSE state from VBLANK_HANDLER so
        ; the music doesn't keep playing while paused.
        ld      a,8                                            ;#40CB: 3E 08
        ld      e,0                                            ;#40CD: 1E 00
        call    BIOS_WRTPSG                                    ;#40CF: CD 93 00
        ; silence PSG channel B volume
        ld      a,9                                            ;#40D2: 3E 09
        ld      e,0                                            ;#40D4: 1E 00
        call    BIOS_WRTPSG                                    ;#40D6: CD 93 00
        ld      a,0Ah                                          ;#40D9: 3E 0A
        ld      e,0                                            ;#40DB: 1E 00
        ; tail call for R10 silence (covered manually)
        jp      BIOS_WRTPSG                                    ;#40DD: C3 93 00

CHECK_PAUSE_KEY:
        ; Poll SNSMAT row 7 and toggle PAUSE_FLAG on a sustained key chord
        ; CHECK_PAUSE_KEY runs once per frame. Reads SNSMAT row 7 (function keys),
        ; rotates the input bits into PAUSE_KEY_HISTORY as a 4-bit shift register, and
        ; tests for a stable held-down pattern (history & 0Fh == 0Ch). On match, toggles
        ; PAUSE_FLAG via cpl. The shift register debounces the keypress so single frames
        ; don't accidentally pause.
        ld      a,(GAME_ACTIVE)                                ;#40E0: 3A 80 E0
        and     a                                              ;#40E3: A7
        jr      z,CHECK_PAUSE_KEY_TOGGLE_PAUSE                 ;#40E4: 28 18
        ld      a,7                                            ;#40E6: 3E 07
        call    BIOS_SNSMAT                                    ;#40E8: CD 41 01
        ld      hl,PAUSE_KEY_HISTORY                           ;#40EB: 21 C7 E0
        rla                                                    ;#40EE: 17
        rla                                                    ;#40EF: 17
        rla                                                    ;#40F0: 17
        rla                                                    ;#40F1: 17
        rl      (hl)                                           ;#40F2: CB 16
        ld      a,(hl)                                         ;#40F4: 7E
        and     0Fh                                            ;#40F5: E6 0F
        cp      0Ch                                            ;#40F7: FE 0C
        ret     nz                                             ;#40F9: C0
        ld      a,(PAUSE_FLAG)                                 ;#40FA: 3A C8 E0
        cpl                                                    ;#40FD: 2F
CHECK_PAUSE_KEY_TOGGLE_PAUSE:
        ; CHECK_PAUSE_KEY tail: toggle PAUSE_FLAG and return
        ld      (PAUSE_FLAG),a                                 ;#40FE: 32 C8 E0
        ret                                                    ;#4101: C9

FILL_NAMETABLE_BLANK:
        ; Fill a 23x24 tile area at HL with tile 40h (clear playfield region)
        ; FILL_NAMETABLE_BLANK clears a 23-wide × 24-tall area at the name table base in
        ; HL. Per-row: BIOS_FILVRM fills 23 cells with TILE_BLANK (40h), then HL += 32
        ; (next row). Used by both INIT_PLAYFIELD_PATTERNS and CLEAR_PLAYFIELD to wipe
        ; the screen.
        ld      b,18h                                          ;#4102: 06 18
FILL_NAMETABLE_ROW_TOP:
        ; Outer djnz of FILL_NAMETABLE_BLANK (per-row body)
        push    bc                                             ;#4104: C5
        push    hl                                             ;#4105: E5
        ld      bc,17h                                         ;#4106: 01 17 00
        ld      a,40h                                          ;#4109: 3E 40
        call    BIOS_FILVRM                                    ;#410B: CD 56 00
        pop     hl                                             ;#410E: E1
        ld      bc,20h                                         ;#410F: 01 20 00
        add     hl,bc                                          ;#4112: 09
        pop     bc                                             ;#4113: C1
        djnz    FILL_NAMETABLE_ROW_TOP                         ;#4114: 10 EE
        ret                                                    ;#4116: C9

INIT_PLAYFIELD_PATTERNS:
        ; Clear name tables, upload tile patterns 80h..FFh, select stage palette
        ; INIT_PLAYFIELD_PATTERNS sets up the per-stage tile patterns: (1) clears both
        ; name table banks via FILL_NAMETABLE_BLANK, (2) zeros 256 bytes at VRAM
        ; 0C00h/1C00h (chars 80h-9Fh), (3) LDIRVMs BG_PATTERN_FILL 8 times to fill chars
        ; A0h-EFh in both banks, (4) LDIRVMs BG_PATTERN_DATA twice for chars F0h-FFh,
        ; (5) selects a color row from STAGE_PALETTES based on STAGE_PALETTE_INDEX.
        ld      hl,400h                                        ;#4117: 21 00 04
        call    FILL_NAMETABLE_BLANK                           ;#411A: CD 02 41
        ld      hl,1400h                                       ;#411D: 21 00 14
        call    FILL_NAMETABLE_BLANK                           ;#4120: CD 02 41
        LOAD_VRAM_ADDRESS hl, 0C00h                            ;#4123: 21 00 0C
        ld      bc,100h                                        ;#4126: 01 00 01
        xor     a                                              ;#4129: AF
        call    BIOS_FILVRM                                    ;#412A: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1C00h                            ;#412D: 21 00 1C
        ld      bc,100h                                        ;#4130: 01 00 01
        xor     a                                              ;#4133: AF
        call    BIOS_FILVRM                                    ;#4134: CD 56 00
        ld      hl,BG_PATTERN_FILL                             ;#4137: 21 B3 42
        LOAD_VRAM_ADDRESS de, 0D00h                            ;#413A: 11 00 0D
        ld      bc,80h                                         ;#413D: 01 80 00
        call    BIOS_LDIRVM                                    ;#4140: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4143: 21 B3 42
        LOAD_VRAM_ADDRESS de, 1D00h                            ;#4146: 11 00 1D
        ld      bc,80h                                         ;#4149: 01 80 00
        call    BIOS_LDIRVM                                    ;#414C: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#414F: 21 B3 42
        LOAD_VRAM_ADDRESS de, 0D80h                            ;#4152: 11 80 0D
        ld      bc,80h                                         ;#4155: 01 80 00
        call    BIOS_LDIRVM                                    ;#4158: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#415B: 21 B3 42
        LOAD_VRAM_ADDRESS de, 1D80h                            ;#415E: 11 80 1D
        ld      bc,80h                                         ;#4161: 01 80 00
        call    BIOS_LDIRVM                                    ;#4164: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4167: 21 B3 42
        LOAD_VRAM_ADDRESS de, 0E00h                            ;#416A: 11 00 0E
        ld      bc,80h                                         ;#416D: 01 80 00
        call    BIOS_LDIRVM                                    ;#4170: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4173: 21 B3 42
        LOAD_VRAM_ADDRESS de, 1E00h                            ;#4176: 11 00 1E
        ld      bc,80h                                         ;#4179: 01 80 00
        call    BIOS_LDIRVM                                    ;#417C: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#417F: 21 B3 42
        LOAD_VRAM_ADDRESS de, 0E80h                            ;#4182: 11 80 0E
        ld      bc,80h                                         ;#4185: 01 80 00
        call    BIOS_LDIRVM                                    ;#4188: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#418B: 21 B3 42
        LOAD_VRAM_ADDRESS de, 1E80h                            ;#418E: 11 80 1E
        ld      bc,80h                                         ;#4191: 01 80 00
        call    BIOS_LDIRVM                                    ;#4194: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#4197: 21 D3 41
        LOAD_VRAM_ADDRESS de, 0F00h                            ;#419A: 11 00 0F
        ld      bc,100h                                        ;#419D: 01 00 01
        call    BIOS_LDIRVM                                    ;#41A0: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#41A3: 21 D3 41
        LOAD_VRAM_ADDRESS de, 1F00h                            ;#41A6: 11 00 1F
        ld      bc,100h                                        ;#41A9: 01 00 01
        call    BIOS_LDIRVM                                    ;#41AC: CD 5C 00
        ld      hl,STAGE_PALETTES                              ;#41AF: 21 33 43
        ld      a,(STAGE_PALETTE_INDEX)                        ;#41B2: 3A B0 E0
        rra                                                    ;#41B5: 1F
        rra                                                    ;#41B6: 1F
        and     3                                              ;#41B7: E6 03
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41B9: 28 0F
        ld      hl,STAGE_PALETTE_1                             ;#41BB: 21 43 43
        dec     a                                              ;#41BE: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41BF: 28 09
        ld      hl,STAGE_PALETTE_2                             ;#41C1: 21 53 43
        dec     a                                              ;#41C4: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41C5: 28 03
        ; palette 4 → color row
        ld      hl,STAGE_PALETTE_3                             ;#41C7: 21 63 43
INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD:
        ; Tail: LDIRVM the chosen palette row to VRAM 0790h
        LOAD_VRAM_ADDRESS de, 790h                             ;#41CA: 11 90 07
        ld      bc,10h                                         ;#41CD: 01 10 00
        jp      BIOS_LDIRVM                                    ;#41D0: C3 5C 00

BG_PATTERN_DATA:
        ; 8-pixel-wide stripe patterns; loaded into tile patterns F0h..FFh
        dh      "00010101010101000003030303030300"             ;#41D3: 00 01 01 01 01 01 01 00 00 03 03 03 03 03 03 00
        dh      "0007070707070700000F0F0F0F0F0F00"             ;#41E3: 00 07 07 07 07 07 07 00 00 0F 0F 0F 0F 0F 0F 00
        dh      "001F1F1F1F1F1F00003F3F3F3F3F3F00"             ;#41F3: 00 1F 1F 1F 1F 1F 1F 00 00 3F 3F 3F 3F 3F 3F 00
        dh      "007F7F7F7F7F7F0000FFFFFFFFFFFF00"             ;#4203: 00 7F 7F 7F 7F 7F 7F 00 00 FF FF FF FF FF FF 00
        dh      "00000000000000000004040404040400"             ;#4213: 00 00 00 00 00 00 00 00 00 04 04 04 04 04 04 00
        dh      "000C0C0C0C0C0C00001C1C1C1C1C1C00"             ;#4223: 00 0C 0C 0C 0C 0C 0C 00 00 1C 1C 1C 1C 1C 1C 00
        dh      "003C3C3C3C3C3C00007C7C7C7C7C7C00"             ;#4233: 00 3C 3C 3C 3C 3C 3C 00 00 7C 7C 7C 7C 7C 7C 00
        dh      "00FCFCFCFCFCFC0000FCFCFCFCFCFC00"             ;#4243: 00 FC FC FC FC FC FC 00 00 FC FC FC FC FC FC 00
        dh      "00000000000030300000000000000082"             ;#4253: 00 00 00 00 00 00 30 30 00 00 00 00 00 00 00 82
        dh      "007E607C6060000800666666663C0020"             ;#4263: 00 7E 60 7C 60 60 00 08 00 66 66 66 66 3C 00 20
        dh      "007E607C607E808200606060607E0008"             ;#4273: 00 7E 60 7C 60 7E 80 82 00 60 60 60 60 7E 00 08
        dh      "00000000000000200000000000000686"             ;#4283: 00 00 00 00 00 00 00 20 00 00 00 00 00 00 06 86
        dh      "00010B0F0B0101031B1F190000000000"             ;#4293: 00 01 0B 0F 0B 01 01 03 1B 1F 19 00 00 00 00 00
        dh      "0080D0F0D08080C0D8F8980000000000"             ;#42A3: 00 80 D0 F0 D0 80 80 C0 D8 F8 98 00 00 00 00 00

BG_PATTERN_FILL:
        ; 128-byte filler pattern, LDIRVM'd 8 times to populate tile patterns 80h..EFh
        dh      "C0C00000000000003030000000000000"             ;#42B3: C0 C0 00 00 00 00 00 00 30 30 00 00 00 00 00 00
        dh      "0C0C0000000000000303000000000000"             ;#42C3: 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00 00 00
        dh      "0000C0C0000000000000303000000000"             ;#42D3: 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00 00 00
        dh      "00000C0C000000000000030300000000"             ;#42E3: 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00
        dh      "00000000C0C000000000000030300000"             ;#42F3: 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00
        dh      "000000000C0C00000000000003030000"             ;#4303: 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00
        dh      "000000000000C0C00000000000003030"             ;#4313: 00 00 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30
        dh      "0000000000000C0C0000000000000303"             ;#4323: 00 00 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03

STAGE_PALETTES:
        ; Base of 4 x 16-byte color-table rows (palette 0)
        ; STAGE_PALETTES — 4 rows of 16 bytes each (= 64 bytes total). Used by
        ; INIT_PLAYFIELD_PATTERNS to pick a color row based on STAGE_PALETTE_INDEX (see
        ; (val >> 2) & 3 logic at 41B2h). All 4 rows differ only in their first 2 bytes
        ; — those are the visible per-stage color differentiation (rest is the shared
        ; HUD palette).
        dh      "DEEDF5F5A5A5F5F515156565A1A1F1A1"             ;#4333: DE ED F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_1:
        ; 16-byte color-table row for palette 1
        dh      "4EE4F5F5A5A5F5F515156565A1A1F1A1"             ;#4343: 4E E4 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_2:
        ; 16-byte color-table row for palette 2
        dh      "6EE6F5F5A5A5F5F515156565A1A1F1A1"             ;#4353: 6E E6 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_3:
        ; 16-byte color-table row for palette 3
        dh      "2EE2F5F5A5A5F5F515156565A1A1F1A1"             ;#4363: 2E E2 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

INITIAL_STATE_HANDLER:
        ; First state handler installed by GAME_BOOT into STATE_HANDLER_VECTOR
        ; INITIAL_STATE_HANDLER is the first state-handler installed at boot. It walks
        ; the boot flow: reset counters, blank screen, LOAD_PLAYFIELD_GFX,
        ; TITLE_WAIT_INPUT (poll until any input), then GAMEPLAY_INIT which arms the
        ; start jingle. WAIT_START_MUSIC spins on SOUND_STATE_OPENING to drain, then
        ; CLEAR_PLAYFIELD wipes both name tables. After that: INIT_PLAYFIELD_PATTERNS,
        ; LOAD_STAGE_PARAMS, INIT_STAGE, the 4 INIT_OBJECT_TABLE_* helpers, and finally
        ; falls through to GAME_LOOP.
        ld      hl,200h                                        ;#4373: 21 00 02
        ld      (HIGH_SCORE_BCD),hl                            ;#4376: 22 81 E0
        ld      h,0                                            ;#4379: 26 00
        ld      (HIGH_SCORE_BCD_HIGH),hl                       ;#437B: 22 83 E0
        ld      (SCORE_BCD),hl                                 ;#437E: 22 B1 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#4381: 22 B3 E0
INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART:
        ; Stage-restart entry: clear GAME_ACTIVE, blank screen, reload tile patterns
        xor     a                                              ;#4384: AF
        ld      (GAME_ACTIVE),a                                ;#4385: 32 80 E0
        ; blank screen (R1=82h) during stage setup
        ld      bc,8201h                                       ;#4388: 01 01 82
        call    BIOS_WRTVDP                                    ;#438B: CD 47 00
        call    LOAD_PLAYFIELD_GFX                             ;#438E: CD 5A 65
TITLE_WAIT_INPUT:
        ; Title-screen loop; polls POLL_INPUT until any key/joystick pressed
        ; TITLE_WAIT_INPUT spins waiting for any input. Calls WAIT_VBLANK_FINISH_SPRITES
        ; (yield), then POLL_INPUT. If no input bit is set in C (mask 0F0h after cpl),
        ; loops back to TITLE_WAIT_INPUT. Used during the title/attract sequence before
        ; the player can start.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#4391: CD B8 40
        call    POLL_INPUT                                     ;#4394: CD CA 4C
        ld      a,c                                            ;#4397: 79
        cpl                                                    ;#4398: 2F
        and     0F0h                                           ;#4399: E6 F0
        jr      z,TITLE_WAIT_INPUT                             ;#439B: 28 F4
        xor     a                                              ;#439D: AF
        ld      (STAGE_PALETTE_INDEX),a                        ;#439E: 32 B0 E0
        ld      (EXTRA_LIFE_AWARDED),a                         ;#43A1: 32 BE E0
        ld      hl,0                                           ;#43A4: 21 00 00
        ld      (SCORE_BCD),hl                                 ;#43A7: 22 B1 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#43AA: 22 B3 E0
        inc     a                                              ;#43AD: 3C
        ld      (GAME_ACTIVE),a                                ;#43AE: 32 80 E0
        ld      a,2                                            ;#43B1: 3E 02
        ld      (LIVES),a                                      ;#43B3: 32 B5 E0
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43B6: CD B8 40
        ld      a,1                                            ;#43B9: 3E 01
        ld      (SOUND_STATE_OPENING),a                        ;#43BB: 32 20 E5
WAIT_START_MUSIC:
        ; Spin on SOUND_STATE_OPENING until the opening jingle finishes
        ; WAIT_START_MUSIC spins until SOUND_STATE_OPENING reaches 0 — the start-jingle
        ; ends. Uses WAIT_VBLANK_FINISH_SPRITES as yield. After drain, proceeds to
        ; CLEAR_PLAYFIELD.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43BE: CD B8 40
        ld      a,(SOUND_STATE_OPENING)                        ;#43C1: 3A 20 E5
        and     a                                              ;#43C4: A7
        jr      nz,WAIT_START_MUSIC                            ;#43C5: 20 F7
        LOAD_VRAM_ADDRESS hl, 400h                             ;#43C7: 21 00 04
        ld      bc,300h                                        ;#43CA: 01 00 03
        ld      a,40h                                          ;#43CD: 3E 40
        call    BIOS_FILVRM                                    ;#43CF: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#43D2: 21 00 14
        ld      bc,300h                                        ;#43D5: 01 00 03
        ld      a,40h                                          ;#43D8: 3E 40
        call    BIOS_FILVRM                                    ;#43DA: CD 56 00
INITIAL_STATE_HANDLER_PALETTE_REFRESH:
        ; Wait one VBLANK, inc STAGE_PALETTE_INDEX, jump back to pattern init
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43DD: CD B8 40
        ld      hl,STAGE_PALETTE_INDEX                         ;#43E0: 21 B0 E0
        inc     (hl)                                           ;#43E3: 34
        jr      nz,INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT    ;#43E4: 20 02
        ld      (hl),0F0h                                      ;#43E6: 36 F0
INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT:
        ; After tile-pattern setup: reset SMOKE_TRAIL_WRITE_INDEX and continue stage init
        call    INIT_PLAYFIELD_PATTERNS                        ;#43E8: CD 17 41
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43EB: CD B8 40
        ld      a,8                                            ;#43EE: 3E 08
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#43F0: 32 AA E0
        call    LOAD_STAGE_PARAMS                              ;#43F3: CD AF 71
        call    SCROLL_ROCKS                                   ;#43F6: CD 23 56
        call    INIT_STAGE                                     ;#43F9: CD D2 53
        ld      a,1                                            ;#43FC: 3E 01
        ld      (STAGE_TIMER_INNER),a                          ;#43FE: 32 B7 E0
        xor     a                                              ;#4401: AF
        ld      (STAGE_CLEAR_FLAG),a                           ;#4402: 32 AF E0
STAGE_RESUME:
        ; Re-seed enemy cars / flags / rocks / track data after death or stage clear
        call    INIT_ENEMY_CARS                                ;#4405: CD 39 4C
        call    INIT_FLAGS                                     ;#4408: CD 8D 54
        call    INIT_ROCKS                                     ;#440B: CD 6D 56
        call    INIT_STAGE_TRACK_DATA                          ;#440E: CD 07 4C
        xor     a                                              ;#4411: AF
        ld      (NAME_BANK_FLAG),a                             ;#4412: 32 8E E0
        ld      (MOVEMENT_SUB_PHASE),a                         ;#4415: 32 AD E0
        ld      (GAME_OVER_FLAG),a                             ;#4418: 32 C9 E0
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#441B: 32 61 E5
        ld      (FRAME_TICK_SUB),a                             ;#441E: 32 AC E0
        ld      (PLAYER_MOVE_GATE),a                           ;#4421: 32 C5 E0
        ld      hl,3C01h                                       ;#4424: 21 01 3C
        ld      (STAGE_TIMER_OUTER),hl                         ;#4427: 22 B8 E0
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#442A: 21 9C 07
        ld      a,0A1h                                         ;#442D: 3E A1
        call    BIOS_WRTVRM                                    ;#442F: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#4432: 21 9D 07
        ld      a,0A1h                                         ;#4435: 3E A1
        call    BIOS_WRTVRM                                    ;#4437: CD 4D 00
        ld      hl,TEXT_ROUND                                  ;#443A: 21 33 46
        ld      de,FUEL_GAUGE_BUFFER                           ;#443D: 11 E0 E1
        ld      bc,6                                           ;#4440: 01 06 00
        ldir                                                   ;#4443: ED B0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4445: 3A B0 E0
        cp      63h                                            ;#4448: FE 63
        jr      c,SHOW_ROUND_NUM_CAP                           ;#444A: 38 02
        ld      a,63h                                          ;#444C: 3E 63
SHOW_ROUND_NUM_CAP:
        ; Clamp STAGE_PALETTE_INDEX to 63h before round-number divmod
        ld      c,40h                                          ;#444E: 0E 40
SHOW_ROUND_NUM_DIVMOD:
        ; Divmod-10 loop body: subtract 10 from A, inc tens digit in C
        cp      0Ah                                            ;#4450: FE 0A
        jr      c,SHOW_ROUND_NUM_STORE                         ;#4452: 38 07
        sub     0Ah                                            ;#4454: D6 0A
        res     6,c                                            ;#4456: CB B1
        inc     c                                              ;#4458: 0C
        jr      SHOW_ROUND_NUM_DIVMOD                          ;#4459: 18 F5

SHOW_ROUND_NUM_STORE:
        ; Store ones digit at HL, tens at HL+1 in the round-number SAT cells
        ex      de,hl                                          ;#445B: EB
        ld      (hl),c                                         ;#445C: 71
        inc     hl                                             ;#445D: 23
        ld      (hl),a                                         ;#445E: 77
        ld      hl,DIGIT_TEMPLATE_F0                           ;#445F: 21 39 46
        LOAD_VRAM_ADDRESS de, 4B7h                             ;#4462: 11 B7 04
        ld      bc,8                                           ;#4465: 01 08 00
        call    BIOS_LDIRVM                                    ;#4468: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_F0                           ;#446B: 21 39 46
        LOAD_VRAM_ADDRESS de, 14B7h                            ;#446E: 11 B7 14
        ld      bc,8                                           ;#4471: 01 08 00
        call    BIOS_LDIRVM                                    ;#4474: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#4477: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 6F7h                             ;#447A: 11 F7 06
        ld      bc,8                                           ;#447D: 01 08 00
        call    BIOS_LDIRVM                                    ;#4480: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#4483: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 16F7h                            ;#4486: 11 F7 16
        ld      bc,8                                           ;#4489: 01 08 00
        call    BIOS_LDIRVM                                    ;#448C: CD 5C 00
        ld      hl,SMOKE_TRAIL_TABLE                           ;#448F: 21 00 E4
        ld      de,SMOKE_TRAIL_TABLE_TAIL                      ;#4492: 11 01 E4
        ld      bc,8Fh                                         ;#4495: 01 8F 00
        xor     a                                              ;#4498: AF
        ld      (PLAYER_DIRECTION),a                           ;#4499: 32 91 E0
        ld      (PLAYER_ROTATION_PHASE),a                      ;#449C: 32 AB E0
        ld      (SMOKE_COOLDOWN),a                             ;#449F: 32 A7 E0
        ld      (hl),a                                         ;#44A2: 77
        ldir                                                   ;#44A3: ED B0
        call    UPDATE_LIVES_DISPLAY                           ;#44A5: CD 6F 68
        call    UPDATE_RADAR                                   ;#44A8: CD EA 52
        ld      a,(STAGE_PALETTE_INDEX)                        ;#44AB: 3A B0 E0
        rra                                                    ;#44AE: 1F
        jr      nc,GAME_LOOP                                   ;#44AF: 30 14
        rra                                                    ;#44B1: 1F
        jr      nc,GAME_LOOP                                   ;#44B2: 30 11
        call    DRAW_CHALLENGING_STAGE_SCREEN                  ;#44B4: CD EA 46
        ld      a,1                                            ;#44B7: 3E 01
        ld      (SOUND_STATE_C_STAGE),a                        ;#44B9: 32 65 E5
GAMELOOP_PRE_YIELD:
        ; Spin until SOUND_STATE_C_STAGE = 0 (jingle done)
        call    WAIT_VBLANK                                    ;#44BC: CD C4 40
        ld      a,(SOUND_STATE_C_STAGE)                        ;#44BF: 3A 65 E5
        and     a                                              ;#44C2: A7
        jr      nz,GAMELOOP_PRE_YIELD                          ;#44C3: 20 F7
GAME_LOOP:
        ; Per-frame gameplay loop: yield, music+sound, sprite updates, end-of-round checks
        ; GAME_LOOP is the per-frame heart of gameplay. Each iteration: yield via
        ; WAIT_VBLANK_FINISH_SPRITES, copy FRAME_TICK->VRAM_BANK_FLAG for the double-
        ; buffer swap, drive sound + sprites + scrolling, then check the three end-of-
        ; round flags (STAGE_CLEAR_FLAG / PLAYER_DEAD_FLAG / GAME_OVER_FLAG) and either
        ; continue looping or branch to STAGE_CLEAR_ BONUS / DEATH_SEQUENCE /
        ; GAME_OVER_SEQUENCE.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#44C5: CD B8 40
        ld      a,(FRAME_TICK)                                 ;#44C8: 3A 87 E0
        ld      (VRAM_BANK_FLAG),a                             ;#44CB: 32 C6 E0
        ld      a,1                                            ;#44CE: 3E 01
        ld      (SOUND_STATE_THEME),a                          ;#44D0: 32 10 E5
        call    FLASH_AND_UPDATE_SCORE_HUD                     ;#44D3: CD 2A 67
        call    DRAW_PLAYER_CAR                                ;#44D6: CD 99 47
        call    UPLOAD_PATTERN_SLICE                           ;#44D9: CD 0C 4E
        call    ITERATE_ENEMY_CARS                             ;#44DC: CD 89 57
        call    UPDATE_ROCKS_COLLISION                         ;#44DF: CD C4 56
        call    SCROLL_FLAGS                                   ;#44E2: CD 13 55
        call    SCROLL_SMOKE_TRAILS                            ;#44E5: CD 87 5C
        call    UPDATE_SMOKE_STATE                             ;#44E8: CD 06 5C
        call    TICK_STAGE_TIMER                               ;#44EB: CD 25 71
        ld      a,(STAGE_CLEAR_FLAG)                           ;#44EE: 3A AF E0
        and     a                                              ;#44F1: A7
        jp      nz,STAGE_CLEAR_BONUS                           ;#44F2: C2 66 45
        ld      a,(PLAYER_DEAD_FLAG)                           ;#44F5: 3A BB E0
        and     a                                              ;#44F8: A7
        jp      nz,DEATH_SEQUENCE                              ;#44F9: C2 41 46
        ld      a,(GAME_OVER_FLAG)                             ;#44FC: 3A C9 E0
        and     a                                              ;#44FF: A7
        jr      z,GAME_LOOP                                    ;#4500: 28 C3
        xor     a                                              ;#4502: AF
        ld      (SOUND_STATE_THEME),a                          ;#4503: 32 10 E5
        ld      (FRAME_TICK),a                                 ;#4506: 32 87 E0
        inc     a                                              ;#4509: 3C
        ld      (SOUND_STATE_BANG),a                           ;#450A: 32 62 E5
        ld      hl,844h                                        ;#450D: 21 44 08
        ld      (SAT_SLOT0_PATTERN_COLOR),hl                   ;#4510: 22 02 E0
GAMEOVER_WAIT_PHASE1:
        ; Wait until FRAME_TICK reaches 14h before placing sprite-list terminator
        call    WAIT_VBLANK                                    ;#4513: CD C4 40
        ld      a,(FRAME_TICK)                                 ;#4516: 3A 87 E0
        cp      14h                                            ;#4519: FE 14
        jr      c,GAMEOVER_WAIT_PHASE1                         ;#451B: 38 F6
        ; end sprite list at game over
        ld      a,SPRITE_Y_TERMINATOR                          ;#451D: 3E D0
        ld      (SAT_SLOT1_Y),a                                ;#451F: 32 04 E0
GAMEOVER_WAIT_PHASE2:
        ; Wait until FRAME_TICK reaches 28h before drawing GAME_OVER text
        call    WAIT_VBLANK                                    ;#4522: CD C4 40
        ld      a,(FRAME_TICK)                                 ;#4525: 3A 87 E0
        cp      28h                                            ;#4528: FE 28
        jr      c,GAMEOVER_WAIT_PHASE2                         ;#452A: 38 F6
        ld      a,(LIVES)                                      ;#452C: 3A B5 E0
        and     a                                              ;#452F: A7
        jr      z,GAMEOVER_SHOW_EXTRA_LIFE                     ;#4530: 28 10
        dec     a                                              ;#4532: 3D
        ld      (LIVES),a                                      ;#4533: 32 B5 E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4536: 3A B0 E0
        cpl                                                    ;#4539: 2F
        and     3                                              ;#453A: E6 03
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#453C: CA DD 43
        jp      STAGE_RESUME                                   ;#453F: C3 05 44

GAMEOVER_SHOW_EXTRA_LIFE:
        ; LIVES==0 branch: paint SAT_EXTRA_LIFE entry then fall into wait phase 3
        ld      hl,SAT_EXTRA_LIFE                              ;#4542: 21 5D 45
        ld      de,SAT_MIRROR                                  ;#4545: 11 00 E0
        ld      bc,9                                           ;#4548: 01 09 00
        ldir                                                   ;#454B: ED B0
GAMEOVER_WAIT_PHASE3:
        ; Wait until FRAME_TICK >= 50h, then loop back to next-stage restart
        call    WAIT_VBLANK                                    ;#454D: CD C4 40
        ld      a,(FRAME_TICK)                                 ;#4550: 3A 87 E0
        cp      50h                                            ;#4553: FE 50
        jr      c,GAMEOVER_WAIT_PHASE3                         ;#4555: 38 F6
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#4557: CD B8 40
        jp      INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART       ;#455A: C3 84 43

SAT_EXTRA_LIFE:
        ; 9-byte SAT data: copied to SAT_MIRROR when an extra life is awarded
        ; SAT_EXTRA_LIFE is 9-byte SAT data copied into SAT_MIRROR when the player earns
        ; an extra life. Shows a brief sprite overlay (likely a "1UP" or "EXTRA"
        ; indicator) on the HUD.
        dh      "5750D00F5760D40FD0"                           ;#455D: 57 50 D0 0F 57 60 D4 0F D0

STAGE_CLEAR_BONUS:
        ; Kill MUSIC_THEME, start MUSIC_STAGE_CLEAR, drain FUEL_LEVEL into score
        ; STAGE_CLEAR_BONUS plays the stage-clear sequence: kill MUSIC_THEME, trigger
        ; MUSIC_STAGE_CLEAR (victory jingle), wait for it to drain, then convert
        ; remaining FUEL_LEVEL into bonus score using one of 4 DRAIN_FUEL_* variants
        ; (slower drain at higher stages = longer display = more "satisfying" bonus
        ; animation).
        xor     a                                              ;#4566: AF
        ld      (SOUND_STATE_THEME),a                          ;#4567: 32 10 E5
        ld      (PLAYER_DEAD_FLAG),a                           ;#456A: 32 BB E0
        inc     a                                              ;#456D: 3C
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#456E: 32 30 E5
        call    UPDATE_SCORE_HUD                               ;#4571: CD 59 67
STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR:
        ; Spin until SOUND_STATE_STAGE_CLEAR reaches 0 (victory jingle drained)
        call    WAIT_VBLANK                                    ;#4574: CD C4 40
        ld      a,(SOUND_STATE_STAGE_CLEAR)                    ;#4577: 3A 30 E5
        and     a                                              ;#457A: A7
        jr      nz,STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR    ;#457B: 20 F7
        ld      a,(STAGE_PALETTE_INDEX)                        ;#457D: 3A B0 E0
        cp      0Ch                                            ;#4580: FE 0C
        jp      nc,STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH        ;#4582: D2 0E 46
        cp      8                                              ;#4585: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP         ;#4587: 30 5D
        cp      4                                              ;#4589: FE 04
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP         ;#458B: 30 2E
STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP:
        ; Drain-fuel loop (stages 0-3): 4x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#458D: CD C4 40
        xor     a                                              ;#4590: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4591: 32 51 E5
        ld      b,2                                            ;#4594: 06 02
STAGE_CLEAR_BONUS_QUAD_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#4596: 3A B9 E0
        and     a                                              ;#4599: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#459A: CA DD 43
        call    DRAIN_FUEL_QUAD_TICK                           ;#459D: CD A9 45
        djnz    STAGE_CLEAR_BONUS_QUAD_TICK_TOP                ;#45A0: 10 F4
        ld      a,1                                            ;#45A2: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45A4: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP              ;#45A7: 18 E4

DRAIN_FUEL_QUAD_TICK:
        ; 4x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — fastest drain variant (stage 0-3)
        push    bc                                             ;#45A9: C5
        call    TICK_FUEL_REFRESH                              ;#45AA: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#45AD: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#45B0: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#45B3: CD 2E 71
        call    BCD_ADD_TO_BONUS                               ;#45B6: CD 17 68
        pop     bc                                             ;#45B9: C1
        ret                                                    ;#45BA: C9

STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP:
        ; Drain-fuel loop (stages 4-7): 3x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45BB: CD C4 40
        xor     a                                              ;#45BE: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45BF: 32 51 E5
        ld      b,3                                            ;#45C2: 06 03
STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45C4: 3A B9 E0
        and     a                                              ;#45C7: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45C8: CA DD 43
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#45CB: CD D7 45
        djnz    STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP              ;#45CE: 10 F4
        ld      a,1                                            ;#45D0: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45D2: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP            ;#45D5: 18 E4

DRAIN_FUEL_TRIPLE_TICK:
        ; 3x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — drain variant (stage 4-7)
        push    bc                                             ;#45D7: C5
        call    TICK_FUEL_REFRESH                              ;#45D8: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#45DB: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#45DE: CD 2E 71
        call    BCD_ADD_TO_BONUS                               ;#45E1: CD 17 68
        pop     bc                                             ;#45E4: C1
        ret                                                    ;#45E5: C9

STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP:
        ; Drain-fuel loop (stages 8-Bh): 2x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45E6: CD C4 40
        xor     a                                              ;#45E9: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45EA: 32 51 E5
        ld      b,4                                            ;#45ED: 06 04
STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45EF: 3A B9 E0
        and     a                                              ;#45F2: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45F3: CA DD 43
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#45F6: CD 02 46
        djnz    STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP              ;#45F9: 10 F4
        ld      a,1                                            ;#45FB: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45FD: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP            ;#4600: 18 E4

DRAIN_FUEL_DOUBLE_TICK:
        ; Two TICK_FUEL_REFRESH calls + BCD_ADD_TO_BONUS overlap — 2x drain rate variant
        push    bc                                             ;#4602: C5
        call    TICK_FUEL_REFRESH                              ;#4603: CD 2E 71
        call    TICK_FUEL_REFRESH                              ;#4606: CD 2E 71
        call    BCD_ADD_TO_BONUS                               ;#4609: CD 17 68
        pop     bc                                             ;#460C: C1
        ret                                                    ;#460D: C9

STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH:
        ; Drain-fuel loop (stage >=Ch): 1x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#460E: CD C4 40
        xor     a                                              ;#4611: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4612: 32 51 E5
        ld      b,8                                            ;#4615: 06 08
STAGE_CLEAR_BONUS_SINGLE_TICK_TOP:
        ; Inner djnz loop body (stage-8plus drain rate)
        ld      a,(FUEL_LEVEL)                                 ;#4617: 3A B9 E0
        and     a                                              ;#461A: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#461B: CA DD 43
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#461E: CD 2A 46
        djnz    STAGE_CLEAR_BONUS_SINGLE_TICK_TOP              ;#4621: 10 F4
        ld      a,1                                            ;#4623: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4625: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH           ;#4628: 18 E4

DRAIN_FUEL_TICK_TO_BONUS:
        ; Wrap TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS to drain one fuel into bonus
        ; DRAIN_FUEL_TICK_TO_BONUS — 1× wrap. Calls TICK_FUEL_REFRESH then
        ; BCD_ADD_TO_BONUS (overlap entry adding 10h to BONUS_BCD). Used by
        ; STAGE_CLEAR_BONUS at the slowest drain rate (stage 12+).
        push    bc                                             ;#462A: C5
        call    TICK_FUEL_REFRESH                              ;#462B: CD 2E 71
        call    BCD_ADD_TO_BONUS                               ;#462E: CD 17 68
        pop     bc                                             ;#4631: C1
        ret                                                    ;#4632: C9

TEXT_ROUND:
        ; "ROUND " label (6 bytes, ASCII + trailing space tile 40h)
        db      "ROUND@"                                       ;#4633: 52 4F 55 4E 44 40

DIGIT_TEMPLATE_F0:
        ; 8-byte tile run F0..F7 used as 8 score-style digit slot positions
        dh      "F0F1F2F3F4F5F6F7"                             ;#4639: F0 F1 F2 F3 F4 F5 F6 F7

DEATH_SEQUENCE:
        ; Player-death animation entry; pp E0B8 to E0BC, etc., before respawn
        ; DEATH_SEQUENCE handles a player-rock or player-enemy collision. Saves
        ; STAGE_TIMER pair (E0B8, E0B9 → E0BC) so it can resume after the death
        ; animation. Plays death SFX, animates player car explosion, then either: LIVES
        ; > 0 → respawn at start position; LIVES = 0 → set GAME_OVER_FLAG to trigger
        ; GAME_OVER_SEQUENCE next frame.
        ld      hl,(STAGE_TIMER_OUTER)                         ;#4641: 2A B8 E0
        ld      (SAVED_TIMER_FOR_DEATH),hl                     ;#4644: 22 BC E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4647: 3A B0 E0
        cp      0Ch                                            ;#464A: FE 0C
        jr      nc,STAGE_CLEAR_BONUS_RESTORE_AND_RETURN        ;#464C: 30 59
        cp      8                                              ;#464E: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK          ;#4650: 30 3A
        cp      4                                              ;#4652: FE 04
        jr      nc,STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH        ;#4654: 30 1B
STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER:
        ; Single-tick branch: zero SFX_BONUS each iteration to retrigger drain sound
        call    WAIT_VBLANK                                    ;#4656: CD C4 40
        xor     a                                              ;#4659: AF
        ld      (SOUND_STATE_BONUS),a                          ;#465A: 32 51 E5
        ld      b,2                                            ;#465D: 06 02
DEATH_RESET_LOOP_HEAD:
        ; Inner djnz loop within DEATH_SEQUENCE phase 1
        ld      a,(FUEL_LEVEL)                                 ;#465F: 3A B9 E0
        and     a                                              ;#4662: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4663: 28 5D
        call    DRAIN_FUEL_QUAD_TICK                           ;#4665: CD A9 45
        djnz    DEATH_RESET_LOOP_HEAD                          ;#4668: 10 F5
        ld      a,1                                            ;#466A: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#466C: 32 51 E5
        jr      STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER             ;#466F: 18 E5

STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH:
        ; Mirror of LOOP_SFX_TRIGGER for the stage-4plus drain path
        call    WAIT_VBLANK                                    ;#4671: CD C4 40
        xor     a                                              ;#4674: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4675: 32 51 E5
        ld      b,3                                            ;#4678: 06 03
DEATH_RESET_LOOP_HEAD_2:
        ; Inner djnz loop within DEATH_SEQUENCE phase 2
        ld      a,(FUEL_LEVEL)                                 ;#467A: 3A B9 E0
        and     a                                              ;#467D: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#467E: 28 42
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#4680: CD D7 45
        djnz    DEATH_RESET_LOOP_HEAD_2                        ;#4683: 10 F5
        ld      a,1                                            ;#4685: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4687: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH           ;#468A: 18 E5

STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK:
        ; Check FUEL_LEVEL = 0: when drained, jump to ISH_PALETTE_REFRESH
        call    WAIT_VBLANK                                    ;#468C: CD C4 40
        xor     a                                              ;#468F: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4690: 32 51 E5
        ld      b,4                                            ;#4693: 06 04
DEATH_RESET_LOOP_HEAD_3:
        ; Inner djnz loop within DEATH_SEQUENCE phase 3
        ld      a,(FUEL_LEVEL)                                 ;#4695: 3A B9 E0
        and     a                                              ;#4698: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4699: 28 27
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#469B: CD 02 46
        djnz    DEATH_RESET_LOOP_HEAD_3                        ;#469E: 10 F5
        ld      a,1                                            ;#46A0: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#46A2: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK             ;#46A5: 18 E5

STAGE_CLEAR_BONUS_RESTORE_AND_RETURN:
        ; Drain finished: restore SFX_BONUS trigger then return to gameplay flow
        call    WAIT_VBLANK                                    ;#46A7: CD C4 40
        xor     a                                              ;#46AA: AF
        ld      (SOUND_STATE_BONUS),a                          ;#46AB: 32 51 E5
        ld      b,8                                            ;#46AE: 06 08
DEATH_RESET_LOOP_HEAD_4:
        ; Inner djnz loop within DEATH_SEQUENCE phase 4
        ld      a,(FUEL_LEVEL)                                 ;#46B0: 3A B9 E0
        and     a                                              ;#46B3: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#46B4: 28 0C
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#46B6: CD 2A 46
        djnz    DEATH_RESET_LOOP_HEAD_4                        ;#46B9: 10 F5
        ld      a,1                                            ;#46BB: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#46BD: 32 51 E5
        jr      STAGE_CLEAR_BONUS_RESTORE_AND_RETURN           ;#46C0: 18 E5

DEATH_RESTORE_TIMER:
        ; Restore (STAGE_TIMER_OUTER, FUEL_LEVEL) from SAVED_TIMER_FOR_DEATH and reset
        ld      hl,(SAVED_TIMER_FOR_DEATH)                     ;#46C2: 2A BC E0
        ld      (STAGE_TIMER_OUTER),hl                         ;#46C5: 22 B8 E0
        xor     a                                              ;#46C8: AF
        ld      (PLAYER_DEAD_FLAG),a                           ;#46C9: 32 BB E0
        ld      (PLAYER_MOVE_GATE),a                           ;#46CC: 32 C5 E0
        ld      a,h                                            ;#46CF: 7C
        cp      0Ah                                            ;#46D0: FE 0A
        jr      c,DEATH_PAINT_DIGITS                           ;#46D2: 38 10
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#46D4: 21 9C 07
        ld      a,0A1h                                         ;#46D7: 3E A1
        call    BIOS_WRTVRM                                    ;#46D9: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#46DC: 21 9D 07
        ld      a,0A1h                                         ;#46DF: 3E A1
        call    BIOS_WRTVRM                                    ;#46E1: CD 4D 00
DEATH_PAINT_DIGITS:
        ; After digits painted: refresh fuel gauge and resume GAME_LOOP
        call    UPDATE_FUEL_GAUGE                              ;#46E4: CD 6F 71
        jp      GAME_LOOP                                      ;#46E7: C3 C5 44

DRAW_CHALLENGING_STAGE_SCREEN:
        ; Render "CHALLENGING STAGE NO <N>" text + stage-number sprites
        ; DRAW_CHALLENGING_STAGE_SCREEN composes the "CHALLENGING STAGE NO X" screen
        ; between stages. Decodes the stage number into 2 digits via an inline decimal-
        ; conversion loop, writes both digits to the name table via BIOS_WRTVRM, then
        ; LDIRVMs TEXT_CHALLENGING_STAGE and TEXT_NO to fixed positions in the name
        ; table. SAT_STAGE_INDICATOR sprites overlay the digits at sprite-sized
        ; positions.
        and     3Fh                                            ;#46EA: E6 3F
        inc     a                                              ;#46EC: 3C
        ld      c,0                                            ;#46ED: 0E 00
DEATH_DIGIT_DIVMOD:
        ; Divmod-10 loop for death-screen score digit
        cp      0Ah                                            ;#46EF: FE 0A
        jr      c,DEATH_DIGIT_LOOP_TAIL                        ;#46F1: 38 05
        inc     c                                              ;#46F3: 0C
        sub     0Ah                                            ;#46F4: D6 0A
        jr      DEATH_DIGIT_DIVMOD                             ;#46F6: 18 F7

DEATH_DIGIT_LOOP_TAIL:
        ; Digit-loop tail: store B in VRAM at the computed position
        ld      b,a                                            ;#46F8: 47
        ld      hl,400h                                        ;#46F9: 21 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#46FC: 3A 8E E0
        and     a                                              ;#46FF: A7
        jr      z,CHALLENGE_RIGHT_BANK                         ;#4700: 28 03
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#4702: 21 00 14
CHALLENGE_RIGHT_BANK:
        ; CHALLENGING STAGE bank-B path: emit text to VRAM 14Eh + bank offset
        push    hl                                             ;#4705: E5
        ld      de,14Eh                                        ;#4706: 11 4E 01
        add     hl,de                                          ;#4709: 19
        ld      a,c                                            ;#470A: 79
        and     a                                              ;#470B: A7
        jr      z,CHALLENGE_FALLTHROUGH                        ;#470C: 28 08
        push    bc                                             ;#470E: C5
        push    hl                                             ;#470F: E5
        call    BIOS_WRTVRM                                    ;#4710: CD 4D 00
        pop     hl                                             ;#4713: E1
        pop     bc                                             ;#4714: C1
        inc     hl                                             ;#4715: 23
CHALLENGE_FALLTHROUGH:
        ; Common tail after bank-A/B selection: write ones digit via BIOS_WRTVRM
        ld      a,b                                            ;#4716: 78
        call    BIOS_WRTVRM                                    ;#4717: CD 4D 00
        pop     hl                                             ;#471A: E1
        push    hl                                             ;#471B: E5
        LOAD_VRAM_ADDRESS de, 104h                             ;#471C: 11 04 01
        add     hl,de                                          ;#471F: 19
        ex      de,hl                                          ;#4720: EB
        ld      hl,TEXT_CHALLENGING_STAGE                      ;#4721: 21 7C 47
        ld      bc,11h                                         ;#4724: 01 11 00
        call    BIOS_LDIRVM                                    ;#4727: CD 5C 00
        pop     hl                                             ;#472A: E1
        push    hl                                             ;#472B: E5
        LOAD_VRAM_ADDRESS de, 14Bh                             ;#472C: 11 4B 01
        add     hl,de                                          ;#472F: 19
        ex      de,hl                                          ;#4730: EB
        ld      hl,TEXT_NO                                     ;#4731: 21 8D 47
        ld      bc,3                                           ;#4734: 01 03 00
        call    BIOS_LDIRVM                                    ;#4737: CD 5C 00
        pop     hl                                             ;#473A: E1
        push    hl                                             ;#473B: E5
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#473C: 3A C0 E0
        rra                                                    ;#473F: 1F
        rra                                                    ;#4740: 1F
        rra                                                    ;#4741: 1F
        rra                                                    ;#4742: 1F
        and     0Fh                                            ;#4743: E6 0F
        ld      de,1AEh                                        ;#4745: 11 AE 01
        add     hl,de                                          ;#4748: 19
        call    BIOS_WRTVRM                                    ;#4749: CD 4D 00
        ld      a,(ROCK_SPAWN_COUNT)                           ;#474C: 3A 9C E0
        ld      c,0                                            ;#474F: 0E 00
        cp      0Ah                                            ;#4751: FE 0A
        jr      c,CHALLENGE_ROCK_NO_DIVMOD                     ;#4753: 38 03
        inc     c                                              ;#4755: 0C
        sub     0Ah                                            ;#4756: D6 0A
CHALLENGE_ROCK_NO_DIVMOD:
        ; No-divmod path: ROCK_SPAWN_COUNT < 10, draw ones digit only
        pop     hl                                             ;#4758: E1
        ld      de,20Eh                                        ;#4759: 11 0E 02
        add     hl,de                                          ;#475C: 19
        ld      b,a                                            ;#475D: 47
        ld      a,c                                            ;#475E: 79
        and     a                                              ;#475F: A7
        jr      z,CHALLENGE_WRITE_ONES_DIGIT                   ;#4760: 28 08
        push    hl                                             ;#4762: E5
        push    bc                                             ;#4763: C5
        call    BIOS_WRTVRM                                    ;#4764: CD 4D 00
        pop     bc                                             ;#4767: C1
        pop     hl                                             ;#4768: E1
        inc     hl                                             ;#4769: 23
CHALLENGE_WRITE_ONES_DIGIT:
        ; Write the ones digit of ROCK_SPAWN_COUNT, then LDIRVM the SAT indicator
        ld      a,b                                            ;#476A: 78
        call    BIOS_WRTVRM                                    ;#476B: CD 4D 00
        ld      hl,SAT_STAGE_INDICATOR                         ;#476E: 21 90 47
        ld      de,SAT_MIRROR                                  ;#4771: 11 00 E0
        ld      bc,9                                           ;#4774: 01 09 00
        ldir                                                   ;#4777: ED B0
        jp      UPDATE_SCORE_HUD                               ;#4779: C3 59 67

TEXT_CHALLENGING_STAGE:
        ; "CHALLENGING STAGE" string (17 bytes, ASCII)
        db      "CHALLENGING STAGE"                            ;#477C: 43 48 41 4C 4C 45 4E 47 49 4E 47 20 53 54 41 47 45

TEXT_NO:
        ; "NO]" suffix text (3 bytes)
        db      "NO]"                                          ;#478D: 4E 4F 5D

SAT_STAGE_INDICATOR:
        ; 9-byte SAT data for stage-number sprite display (2 sprites + terminator)
        ; SAT_STAGE_INDICATOR is 9 bytes of SAT data uploaded to SAT_MIRROR to show the
        ; stage-number sprites on the "CHALLENGING STAGE" screen. Contains 2 sprite
        ; entries (4 bytes each) + terminator (Y=D0h).
        dh      "635800087B583C09D0"                           ;#4790: 63 58 00 08 7B 58 3C 09 D0

DRAW_PLAYER_CAR:
        ; Rotate animation phase toward PLAYER_DIRECTION; emit car sprite at screen centre
        ; DRAW_PLAYER_CAR runs every other frame (gated by FRAME_TICK low bit). Reads
        ; PLAYER_DIRECTION (lower 2 bits), computes a target rotation angle, and slews
        ; PLAYER_ROTATION_PHASE by +/-4 toward it (modulo 30h). Then emits the player
        ; car sprite at fixed screen-center (Y=57h, X=58h) with the rotation phase as
        ; the tile index and color 5 (cyan).
        ld      a,(FRAME_TICK)                                 ;#4799: 3A 87 E0
        rra                                                    ;#479C: 1F
        jr      nc,PLAYER_EMIT_SPRITE                          ;#479D: 30 2E
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#479F: 3A AB E0
        ld      c,a                                            ;#47A2: 4F
        ld      a,(PLAYER_DIRECTION)                           ;#47A3: 3A 91 E0
        and     3                                              ;#47A6: E6 03
        ld      b,a                                            ;#47A8: 47
        add     a,a                                            ;#47A9: 87
        add     a,b                                            ;#47AA: 80
        add     a,a                                            ;#47AB: 87
        add     a,a                                            ;#47AC: 87
        sub     c                                              ;#47AD: 91
        jr      z,PLAYER_EMIT_SPRITE                           ;#47AE: 28 1D
        jr      nc,PLAYER_DELTA_NORMALIZED                     ;#47B0: 30 02
        add     a,30h                                          ;#47B2: C6 30
PLAYER_DELTA_NORMALIZED:
        ; Direction delta normalized to [0..2Fh]; pick rotate-minus or rotate-plus
        cp      18h                                            ;#47B4: FE 18
        jr      c,PLAYER_ROTATE_PLUS                           ;#47B6: 38 0A
        ld      a,c                                            ;#47B8: 79
        sub     4                                              ;#47B9: D6 04
        jr      nc,PLAYER_STORE_ROTATION                       ;#47BB: 30 0D
        ld      a,2Ch                                          ;#47BD: 3E 2C
        jp      PLAYER_STORE_ROTATION                          ;#47BF: C3 CA 47

PLAYER_ROTATE_PLUS:
        ; Rotate phase by +4 (mod 30h) toward target direction
        ld      a,c                                            ;#47C2: 79
        add     a,4                                            ;#47C3: C6 04
        cp      30h                                            ;#47C5: FE 30
        jr      c,PLAYER_STORE_ROTATION                        ;#47C7: 38 01
        xor     a                                              ;#47C9: AF
PLAYER_STORE_ROTATION:
        ; Store updated PLAYER_ROTATION_PHASE
        ld      (PLAYER_ROTATION_PHASE),a                      ;#47CA: 32 AB E0
PLAYER_EMIT_SPRITE:
        ; Skip-update branch (gated by FRAME_TICK low bit): emit player sprite
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#47CD: 3A AB E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#47D0: 2A 94 E0
        ; emit player sprite
        ld      (hl),57h                                       ;#47D3: 36 57
        inc     hl                                             ;#47D5: 23
        ld      (hl),58h                                       ;#47D6: 36 58
        inc     hl                                             ;#47D8: 23
        ld      (hl),a                                         ;#47D9: 77
        inc     hl                                             ;#47DA: 23
        ld      (hl),5                                         ;#47DB: 36 05
        inc     hl                                             ;#47DD: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#47DE: 22 94 E0
        ld      bc,101h                                        ;#47E1: 01 01 01
        ld      a,(PLAYER_VELOCITY_X)                          ;#47E4: 3A 89 E0
        bit     7,a                                            ;#47E7: CB 7F
        jr      z,PLAYER_APPLY_X_VEL                           ;#47E9: 28 03
        neg                                                    ;#47EB: ED 44
        dec     b                                              ;#47ED: 05
PLAYER_APPLY_X_VEL:
        ; Velocity-Y not negative: store positive velocity and update WORLD_X_POS
        sub     0Ah                                            ;#47EE: D6 0A
        ld      e,a                                            ;#47F0: 5F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#47F1: 3A 8B E0
        bit     7,a                                            ;#47F4: CB 7F
        jr      z,PLAYER_APPLY_Y_VEL                           ;#47F6: 28 03
        neg                                                    ;#47F8: ED 44
        dec     c                                              ;#47FA: 0D
PLAYER_APPLY_Y_VEL:
        ; Velocity-Y negative: store inverted velocity and update WORLD_Y_POS
        sub     0Ah                                            ;#47FB: D6 0A
        ld      d,a                                            ;#47FD: 57
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#47FE: 21 8F E0
        ld      a,(hl)                                         ;#4801: 7E
        add     a,b                                            ;#4802: 80
        ld      (PLAYER_SCREEN_X),a                            ;#4803: 32 A3 E0
        ld      b,a                                            ;#4806: 47
        inc     hl                                             ;#4807: 23
        ld      a,(hl)                                         ;#4808: 7E
        add     a,c                                            ;#4809: 81
        ld      (PLAYER_SCREEN_Y),a                            ;#480A: 32 A4 E0
        ld      l,a                                            ;#480D: 6F
        ld      h,b                                            ;#480E: 60
        call    DEPLOY_SMOKE_IF_INPUT                          ;#480F: CD BD 49
        ld      a,(PLAYER_DIRECTION)                           ;#4812: 3A 91 E0
        call    AI_PICK_VALID_DIRECTION                        ;#4815: CD 35 4A
        ld      hl,(PLAYFIELD_SCROLL_OFFSET)                   ;#4818: 2A 92 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#481B: 3A C5 E0
        and     a                                              ;#481E: A7
        jr      nz,SCROLL_CHECK_BACKWARD                       ;#481F: 20 17
        ld      a,(SCROLL_LIMIT_HI)                            ;#4821: 3A C4 E0
        cp      h                                              ;#4824: BC
        jr      nz,SCROLL_ADVANCE_FORWARD                      ;#4825: 20 08
        ld      a,(SCROLL_LIMIT_LO)                            ;#4827: 3A C3 E0
        cp      l                                              ;#482A: BD
        jr      z,DISPATCH_PLAYER_DIRECTION                    ;#482B: 28 1B
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#482D: 38 19
SCROLL_ADVANCE_FORWARD:
        ; Scroll bounds advance: increment PLAYFIELD_SCROLL_OFFSET by 10h
        ld      de,10h                                         ;#482F: 11 10 00
        add     hl,de                                          ;#4832: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4833: 22 92 E0
        jr      DISPATCH_PLAYER_DIRECTION                      ;#4836: 18 10

SCROLL_CHECK_BACKWARD:
        ; Move-gate active: check whether scroll should retreat
        ld      a,h                                            ;#4838: 7C
        and     a                                              ;#4839: A7
        jr      nz,SCROLL_RETREAT                              ;#483A: 20 05
        ld      a,l                                            ;#483C: 7D
        cp      0C0h                                           ;#483D: FE C0
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#483F: 38 07
SCROLL_RETREAT:
        ; Scroll bounds retreat: subtract 8 from PLAYFIELD_SCROLL_OFFSET
        ld      de,-8                                          ;#4841: 11 F8 FF
        add     hl,de                                          ;#4844: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4845: 22 92 E0
DISPATCH_PLAYER_DIRECTION:
        ; 4-way switch on PLAYER_DIRECTION&3 into per-direction movement handlers
        ; DISPATCH_PLAYER_DIRECTION reads PLAYER_DIRECTION lower 2 bits (0/1/2/3 =
        ; up/right/down/left), then jumps to MOVE_PLAYER_DIRECTION_0..3. Each handler
        ; updates WORLD_X_POS or WORLD_Y_POS, derives WORLD_SCROLL_DX/DY for the per-
        ; frame world scroll, and verifies movement via LOOKUP_ PLAYFIELD_CELL to detect
        ; wall collisions.
        ex      de,hl                                          ;#4848: EB
        ld      a,(PLAYER_DIRECTION)                           ;#4849: 3A 91 E0
        and     3                                              ;#484C: E6 03
        jp      z,MOVE_PLAYER_DIRECTION_0                      ;#484E: CA B3 48
        dec     a                                              ;#4851: 3D
        jp      z,MOVE_PLAYER_DIRECTION_1                      ;#4852: CA 65 49
        dec     a                                              ;#4855: 3D
        jp      z,MOVE_PLAYER_DIRECTION_2                      ;#4856: CA 0D 49
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4859: 3A 8B E0
        ld      c,a                                            ;#485C: 4F
        and     a                                              ;#485D: A7
        ld      a,0Ch                                          ;#485E: 3E 0C
        jp      p,MOVE_DIR3_STORE_VEL                          ;#4860: F2 65 48
        ld      a,0F4h                                         ;#4863: 3E F4
MOVE_DIR3_STORE_VEL:
        ; Direction-3 (left) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#4865: 32 8B E0
        sub     c                                              ;#4868: 91
        neg                                                    ;#4869: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#486B: 32 97 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#486E: CD 63 57
        ld      hl,(WORLD_X_POS)                               ;#4871: 2A 88 E0
        and     a                                              ;#4874: A7
        ld      a,h                                            ;#4875: 7C
        sbc     hl,de                                          ;#4876: ED 52
        ld      (WORLD_X_POS),hl                               ;#4878: 22 88 E0
        sub     h                                              ;#487B: 94
        ld      (WORLD_SCROLL_DX),a                            ;#487C: 32 96 E0
        call    ADD_DE_TO_ENEMY_X                              ;#487F: CD 3D 57
        ld      a,h                                            ;#4882: 7C
        add     a,14h                                          ;#4883: C6 14
        ret     p                                              ;#4885: F0
        add     a,4                                            ;#4886: C6 04
        ld      (PLAYER_VELOCITY_X),a                          ;#4888: 32 89 E0
        ld      hl,STEP_COUNTER                                ;#488B: 21 8D E0
        inc     (hl)                                           ;#488E: 34
        inc     (hl)                                           ;#488F: 34
        inc     (hl)                                           ;#4890: 34
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4891: 21 8F E0
        dec     (hl)                                           ;#4894: 35
        ld      hl,TRACK_DATA_RING_END-3                       ;#4895: 21 80 F2
        ld      de,TRACK_DATA_RING_END                         ;#4898: 11 83 F2
        ld      bc,381h                                        ;#489B: 01 81 03
        lddr                                                   ;#489E: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#48A0: 21 8F E0
        ld      a,(hl)                                         ;#48A3: 7E
        sub     4                                              ;#48A4: D6 04
        ld      c,a                                            ;#48A6: 4F
        inc     hl                                             ;#48A7: 23
        ld      a,(hl)                                         ;#48A8: 7E
        sub     4                                              ;#48A9: D6 04
        ld      l,a                                            ;#48AB: 6F
        ld      h,c                                            ;#48AC: 61
        ld      de,TRACK_DATA_RING                             ;#48AD: 11 00 EF
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#48B0: C3 85 4A

MOVE_PLAYER_DIRECTION_0:
        ; Direction-0 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#48B3: 3A 89 E0
        ld      c,a                                            ;#48B6: 4F
        and     a                                              ;#48B7: A7
        ld      a,0Ch                                          ;#48B8: 3E 0C
        jp      p,MOVE_DIR0_STORE_VEL                          ;#48BA: F2 BF 48
        ld      a,0F4h                                         ;#48BD: 3E F4
MOVE_DIR0_STORE_VEL:
        ; Direction-0 (up) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#48BF: 32 89 E0
        sub     c                                              ;#48C2: 91
        neg                                                    ;#48C3: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#48C5: 32 96 E0
        call    ADD_DE_TO_ENEMY_X                              ;#48C8: CD 3D 57
        ld      hl,(WORLD_Y_POS)                               ;#48CB: 2A 8A E0
        and     a                                              ;#48CE: A7
        ld      a,h                                            ;#48CF: 7C
        sbc     hl,de                                          ;#48D0: ED 52
        ld      (WORLD_Y_POS),hl                               ;#48D2: 22 8A E0
        sub     h                                              ;#48D5: 94
        ld      (WORLD_SCROLL_DY),a                            ;#48D6: 32 97 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#48D9: CD 63 57
        ld      a,h                                            ;#48DC: 7C
        add     a,14h                                          ;#48DD: C6 14
        ret     p                                              ;#48DF: F0
        add     a,4                                            ;#48E0: C6 04
        ld      (PLAYER_VELOCITY_Y),a                          ;#48E2: 32 8B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#48E5: 21 8C E0
        inc     (hl)                                           ;#48E8: 34
        inc     (hl)                                           ;#48E9: 34
        inc     (hl)                                           ;#48EA: 34
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#48EB: 21 90 E0
        dec     (hl)                                           ;#48EE: 35
        ld      hl,TRACK_DATA_RING_END-5Ah                     ;#48EF: 21 29 F2
        ld      de,TRACK_DATA_RING_END                         ;#48F2: 11 83 F2
        ld      bc,32Ah                                        ;#48F5: 01 2A 03
        lddr                                                   ;#48F8: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#48FA: 21 8F E0
        ld      a,(hl)                                         ;#48FD: 7E
        sub     4                                              ;#48FE: D6 04
        ld      c,a                                            ;#4900: 4F
        inc     hl                                             ;#4901: 23
        ld      a,(hl)                                         ;#4902: 7E
        sub     4                                              ;#4903: D6 04
        ld      l,a                                            ;#4905: 6F
        ld      h,c                                            ;#4906: 61
        ld      de,TRACK_DATA_RING                             ;#4907: 11 00 EF
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#490A: C3 75 4A

MOVE_PLAYER_DIRECTION_2:
        ; Direction-2 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#490D: 3A 89 E0
        ld      c,a                                            ;#4910: 4F
        and     a                                              ;#4911: A7
        ld      a,0Ch                                          ;#4912: 3E 0C
        jp      p,MOVE_DIR2_STORE_VEL                          ;#4914: F2 19 49
        ld      a,0F4h                                         ;#4917: 3E F4
MOVE_DIR2_STORE_VEL:
        ; Direction-2 (right) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#4919: 32 89 E0
        sub     c                                              ;#491C: 91
        neg                                                    ;#491D: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#491F: 32 96 E0
        call    ADD_DE_TO_ENEMY_X                              ;#4922: CD 3D 57
        ld      hl,(WORLD_Y_POS)                               ;#4925: 2A 8A E0
        ld      a,h                                            ;#4928: 7C
        add     hl,de                                          ;#4929: 19
        ld      (WORLD_Y_POS),hl                               ;#492A: 22 8A E0
        sub     h                                              ;#492D: 94
        ld      (WORLD_SCROLL_DY),a                            ;#492E: 32 97 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4931: CD 63 57
        ld      a,h                                            ;#4934: 7C
        sub     15h                                            ;#4935: D6 15
        ret     m                                              ;#4937: F8
        sub     3                                              ;#4938: D6 03
        ld      (PLAYER_VELOCITY_Y),a                          ;#493A: 32 8B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#493D: 21 8C E0
        dec     (hl)                                           ;#4940: 35
        dec     (hl)                                           ;#4941: 35
        dec     (hl)                                           ;#4942: 35
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#4943: 21 90 E0
        inc     (hl)                                           ;#4946: 34
        ld      hl,TRACK_DATA_RING+5Ah    ; 2nd enemy-path record ;#4947: 21 5A EF
        ld      de,TRACK_DATA_RING                             ;#494A: 11 00 EF
        ld      bc,32Ah                                        ;#494D: 01 2A 03
        ldir                                                   ;#4950: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4952: 21 8F E0
        ld      a,(hl)                                         ;#4955: 7E
        sub     4                                              ;#4956: D6 04
        ld      c,a                                            ;#4958: 4F
        inc     hl                                             ;#4959: 23
        ld      a,(hl)                                         ;#495A: 7E
        add     a,5                                            ;#495B: C6 05
        ld      l,a                                            ;#495D: 6F
        ld      h,c                                            ;#495E: 61
        ld      de,TRACK_DATA_RING_END-59h                     ;#495F: 11 2A F2
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#4962: C3 75 4A

MOVE_PLAYER_DIRECTION_1:
        ; Direction-1 movement handler
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4965: 3A 8B E0
        ld      c,a                                            ;#4968: 4F
        and     a                                              ;#4969: A7
        ld      a,0Ch                                          ;#496A: 3E 0C
        jp      p,MOVE_DIR1_STORE_VEL                          ;#496C: F2 71 49
        ld      a,0F4h                                         ;#496F: 3E F4
MOVE_DIR1_STORE_VEL:
        ; Direction-1 (down) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#4971: 32 8B E0
        sub     c                                              ;#4974: 91
        neg                                                    ;#4975: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#4977: 32 97 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#497A: CD 63 57
        ld      hl,(WORLD_X_POS)                               ;#497D: 2A 88 E0
        ld      a,h                                            ;#4980: 7C
        add     hl,de                                          ;#4981: 19
        ld      (WORLD_X_POS),hl                               ;#4982: 22 88 E0
        sub     h                                              ;#4985: 94
        ld      (WORLD_SCROLL_DX),a                            ;#4986: 32 96 E0
        call    ADD_DE_TO_ENEMY_X                              ;#4989: CD 3D 57
        ld      a,h                                            ;#498C: 7C
        sub     15h                                            ;#498D: D6 15
        ret     m                                              ;#498F: F8
        sub     3                                              ;#4990: D6 03
        ld      (PLAYER_VELOCITY_X),a                          ;#4992: 32 89 E0
        ld      hl,STEP_COUNTER                                ;#4995: 21 8D E0
        dec     (hl)                                           ;#4998: 35
        dec     (hl)                                           ;#4999: 35
        dec     (hl)                                           ;#499A: 35
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#499B: 21 8F E0
        inc     (hl)                                           ;#499E: 34
        ld      hl,TRACK_DATA_RING+3                           ;#499F: 21 03 EF
        ld      de,TRACK_DATA_RING                             ;#49A2: 11 00 EF
        ld      bc,381h                                        ;#49A5: 01 81 03
        ldir                                                   ;#49A8: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#49AA: 21 8F E0
        ld      a,(hl)                                         ;#49AD: 7E
        add     a,5                                            ;#49AE: C6 05
        ld      c,a                                            ;#49B0: 4F
        inc     hl                                             ;#49B1: 23
        ld      a,(hl)                                         ;#49B2: 7E
        sub     4                                              ;#49B3: D6 04
        ld      l,a                                            ;#49B5: 6F
        ld      h,c                                            ;#49B6: 61
        ld      de,TRACK_DATA_RING+1Bh                         ;#49B7: 11 1B EF
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#49BA: C3 85 4A

DEPLOY_SMOKE_IF_INPUT:
        ; Check input + fuel via POLL_INPUT; if available, drop fuel and refresh gauge
        ; DEPLOY_SMOKE_IF_INPUT. Polls input via POLL_INPUT; if a smoke-deploy key is
        ; held AND SMOKE_COOLDOWN is 0 AND FUEL_LEVEL > 3, deducts 3 from fuel,
        ; refreshes UPDATE_FUEL_GAUGE, sets SMOKE_COOLDOWN=3 frames. The actual smoke
        ; entity spawn happens elsewhere in the smoke subsystem.
        push    hl                                             ;#49BD: E5
        push    de                                             ;#49BE: D5
        call    POLL_INPUT                                     ;#49BF: CD CA 4C
        ld      a,(STAGE_PALETTE_INDEX)                        ;#49C2: 3A B0 E0
        cpl                                                    ;#49C5: 2F
        and     3                                              ;#49C6: E6 03
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49C8: 28 22
        ld      a,c                                            ;#49CA: 79
        cpl                                                    ;#49CB: 2F
        and     0F0h                                           ;#49CC: E6 F0
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49CE: 28 1C
        ld      a,(SMOKE_COOLDOWN)                             ;#49D0: 3A A7 E0
        and     a                                              ;#49D3: A7
        jr      nz,PROCESS_DIRECTION_INPUT                     ;#49D4: 20 16
        ld      a,(FUEL_LEVEL)                                 ;#49D6: 3A B9 E0
        sub     3                                              ;#49D9: D6 03
        jr      c,PROCESS_DIRECTION_INPUT                      ;#49DB: 38 0F
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49DD: 28 0D
        ld      (FUEL_LEVEL),a                                 ;#49DF: 32 B9 E0
        push    bc                                             ;#49E2: C5
        call    UPDATE_FUEL_GAUGE                              ;#49E3: CD 6F 71
        pop     bc                                             ;#49E6: C1
        ld      a,3                                            ;#49E7: 3E 03
        ld      (SMOKE_COOLDOWN),a                             ;#49E9: 32 A7 E0
PROCESS_DIRECTION_INPUT:
        ; Map 4 input bits (up/right/down/left) into TRY_SET_DIRECTION calls
        ; PROCESS_DIRECTION_INPUT takes the input mask in B (one bit per direction) and
        ; tests each bit, calling TRY_SET_DIRECTION with the appropriate direction code
        ; (0=up, 1=left, 2=right, 3=down). Earlier direction bits dominate — diagonal
        ; inputs resolve to vertical.
        ld      b,c                                            ;#49EC: 41
        ld      c,0                                            ;#49ED: 0E 00
        bit     0,b                                            ;#49EF: CB 40
        call    z,TRY_SET_DIRECTION                            ;#49F1: CC 0C 4A
        ld      c,2                                            ;#49F4: 0E 02
        bit     1,b                                            ;#49F6: CB 48
        call    z,TRY_SET_DIRECTION                            ;#49F8: CC 0C 4A
        ld      c,3                                            ;#49FB: 0E 03
        bit     2,b                                            ;#49FD: CB 50
        call    z,TRY_SET_DIRECTION                            ;#49FF: CC 0C 4A
        ld      c,1                                            ;#4A02: 0E 01
        bit     3,b                                            ;#4A04: CB 58
        call    z,TRY_SET_DIRECTION                            ;#4A06: CC 0C 4A
        pop     de                                             ;#4A09: D1
        pop     hl                                             ;#4A0A: E1
        ret                                                    ;#4A0B: C9

TRY_SET_DIRECTION:
        ; Inner: if dir C differs from PLAYER_DIRECTION, validate path then update
        ; TRY_SET_DIRECTION is the inner direction-update helper. The `inc sp; inc sp`
        ; at entry and `dec sp; dec sp` later discard the caller's return address
        ; temporarily — a stack-pointer trick that lets it return TWO frames up to
        ; PROCESS_DIRECTION_INPUT's caller when direction acceptance succeeds. Verifies
        ; the proposed direction via CHECK_DIRECTION_BLOCKED before updating
        ; PLAYER_DIRECTION.
        inc     sp                                             ;#4A0C: 33
        inc     sp                                             ;#4A0D: 33
        ld      a,(PLAYER_DIRECTION)                           ;#4A0E: 3A 91 E0
        cp      c                                              ;#4A11: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A12: 28 18
        xor     2                                              ;#4A14: EE 02
        cp      c                                              ;#4A16: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A17: 28 13
        pop     de                                             ;#4A19: D1
        push    de                                             ;#4A1A: D5
        dec     sp                                             ;#4A1B: 3B
        dec     sp                                             ;#4A1C: 3B
        ld      a,d                                            ;#4A1D: 7A
        cp      5                                              ;#4A1E: FE 05
        ret     nc                                             ;#4A20: D0
        ld      a,e                                            ;#4A21: 7B
        cp      5                                              ;#4A22: FE 05
        ret     nc                                             ;#4A24: D0
        push    bc                                             ;#4A25: C5
        call    CHECK_DIRECTION_BLOCKED                        ;#4A26: CD 5A 4A
        pop     bc                                             ;#4A29: C1
        ret     c                                              ;#4A2A: D8
        pop     hl                                             ;#4A2B: E1
TRY_SET_DIRECTION_END:
        ; Tail of TRY_SET_DIRECTION: restore sp adjustment, ret to outer caller
        pop     de                                             ;#4A2C: D1
        pop     hl                                             ;#4A2D: E1
AI_DIR_FOUND:
        ; Found unblocked direction: mask to 2 bits, store as PLAYER_DIRECTION
        ld      a,c                                            ;#4A2E: 79
        and     3                                              ;#4A2F: E6 03
        ld      (PLAYER_DIRECTION),a                           ;#4A31: 32 91 E0
        ret                                                    ;#4A34: C9

AI_PICK_VALID_DIRECTION:
        ; Try alternate directions via CHECK_DIRECTION_BLOCKED, set PLAYER_DIRECTION
        ; AI_PICK_VALID_DIRECTION tries up to 4 directions and picks the first non-
        ; blocked one. Calls CHECK_DIRECTION_BLOCKED for each candidate (which returns
        ; carry=1 when blocked). The picked direction is stored in PLAYER_DIRECTION.
        ; Used by both player movement and enemy AI to navigate around obstacles.
        ld      c,a                                            ;#4A35: 4F
        ld      a,e                                            ;#4A36: 7B
        cp      5                                              ;#4A37: FE 05
        ret     nc                                             ;#4A39: D0
        ld      a,d                                            ;#4A3A: 7A
        cp      5                                              ;#4A3B: FE 05
        ret     nc                                             ;#4A3D: D0
        ld      d,h                                            ;#4A3E: 54
        ld      e,l                                            ;#4A3F: 5D
        call    CHECK_DIRECTION_BLOCKED                        ;#4A40: CD 5A 4A
        jr      nc,AI_DIR_FOUND                                ;#4A43: 30 E9
        ld      h,d                                            ;#4A45: 62
        ld      l,e                                            ;#4A46: 6B
        inc     c                                              ;#4A47: 0C
        call    CHECK_DIRECTION_BLOCKED                        ;#4A48: CD 5A 4A
        jr      nc,AI_DIR_FOUND                                ;#4A4B: 30 E1
        inc     c                                              ;#4A4D: 0C
        inc     c                                              ;#4A4E: 0C
        ld      h,d                                            ;#4A4F: 62
        ld      l,e                                            ;#4A50: 6B
        call    CHECK_DIRECTION_BLOCKED                        ;#4A51: CD 5A 4A
        jr      nc,AI_DIR_FOUND                                ;#4A54: 30 D8
        dec     c                                              ;#4A56: 0D
        jp      AI_DIR_FOUND                                   ;#4A57: C3 2E 4A

CHECK_DIRECTION_BLOCKED:
        ; Test if direction C is blocked; returns carry-set when blocked
        ; CHECK_DIRECTION_BLOCKED tests if direction C is blocked. Looks up the
        ; playfield cell adjacent to the current position in that direction via
        ; QUERY_PLAYFIELD_AT; returns carry=1 (blocked) if the cell is a rock/wall,
        ; carry=0 (free) otherwise. Called many times per frame by
        ; AI_PICK_VALID_DIRECTION and player movement.
        ld      a,c                                            ;#4A5A: 79
        and     3                                              ;#4A5B: E6 03
        jr      z,DIR_BLOCKED_LEFT                             ;#4A5D: 28 0A
        dec     a                                              ;#4A5F: 3D
        jr      z,DIR_BLOCKED_DOWN                             ;#4A60: 28 0B
        dec     a                                              ;#4A62: 3D
        jr      z,DIR_BLOCKED_RIGHT                            ;#4A63: 28 0C
        dec     h                                              ;#4A65: 25
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A66: C3 86 4B

DIR_BLOCKED_LEFT:
        ; Direction LEFT blocked path: dec L then jump to LOOKUP_PLAYFIELD_CELL
        dec     l                                              ;#4A69: 2D
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A6A: C3 86 4B

DIR_BLOCKED_DOWN:
        ; Direction DOWN blocked path: inc H then jump to LOOKUP_PLAYFIELD_CELL
        inc     h                                              ;#4A6D: 24
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A6E: C3 86 4B

DIR_BLOCKED_RIGHT:
        ; Direction RIGHT blocked path: inc L then jump to LOOKUP_PLAYFIELD_CELL
        inc     l                                              ;#4A71: 2C
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A72: C3 86 4B

SCAN_PLAYFIELD_H_STRIP:
        ; Loop 10 cells along H axis (stride 3), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_H_STRIP scans 10 cells horizontally (along H axis, E += 3 per
        ; cell), invoking QUERY_PLAYFIELD_AT for each. Used by AI routines to find the
        ; closest rock/flag in a row.
        ld      b,0Ah                                          ;#4A75: 06 0A
SCAN_H_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_H_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A77: CD 95 4A
        inc     h                                              ;#4A7A: 24
        ld      a,e                                            ;#4A7B: 7B
        add     a,3                                            ;#4A7C: C6 03
        ld      e,a                                            ;#4A7E: 5F
        jr      nc,SCAN_H_STRIP_NEXT                           ;#4A7F: 30 01
        inc     d                                              ;#4A81: 14
SCAN_H_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_H_STRIP (H += 1, E += 3)
        djnz    SCAN_H_STRIP_TOP                               ;#4A82: 10 F3
        ret                                                    ;#4A84: C9

SCAN_PLAYFIELD_L_STRIP:
        ; Loop 10 cells along L axis (stride 5Ah), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_L_STRIP is the L-axis equivalent (L += 0Ah per cell, E += 5Ah
        ; per cell — wider stride). Both share QUERY_PLAYFIELD_AT.
        ld      b,0Ah                                          ;#4A85: 06 0A
SCAN_L_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_L_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A87: CD 95 4A
        inc     l                                              ;#4A8A: 2C
        ld      a,e                                            ;#4A8B: 7B
        add     a,5Ah                                          ;#4A8C: C6 5A
        ld      e,a                                            ;#4A8E: 5F
        jr      nc,SCAN_L_STRIP_NEXT                           ;#4A8F: 30 01
        inc     d                                              ;#4A91: 14
SCAN_L_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_L_STRIP (L += 1, E += 5Ah)
        djnz    SCAN_L_STRIP_TOP                               ;#4A92: 10 F3
        ret                                                    ;#4A94: C9

QUERY_PLAYFIELD_AT:
        ; Lookup playfield cell at (H, L) via PLAYFIELD_LOOKUP_TABLE
        ; QUERY_PLAYFIELD_AT looks up (H, L) coord in PLAYFIELD_LOOKUP_TABLE
        ; (PLAYFIELD_LOOKUP_TABLE). H>=20h uses one branch (returns from a higher tier
        ; of the table at PLAYFIELD_LOOKUP_OUT_OF_BOUNDS); H<20h takes the in-bounds
        ; path indexing PLAYFIELD_ LOOKUP_TABLE. Returns the cell value in A — used to
        ; detect rocks, walls, flag positions for AI and movement.
        push    bc                                             ;#4A95: C5
        push    de                                             ;#4A96: D5
        push    hl                                             ;#4A97: E5
        ld      a,h                                            ;#4A98: 7C
        cp      20h                                            ;#4A99: FE 20
        jr      c,QUERY_IN_BOUNDS                              ;#4A9B: 38 15
        inc     a                                              ;#4A9D: 3C
        jr      nz,QUERY_OUT_OF_BOUNDS                         ;#4A9E: 20 2A
        ld      a,l                                            ;#4AA0: 7D
        cp      39h                                            ;#4AA1: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4AA3: 30 25
        ld      hl,PLAYFIELD_LOOKUP_OUT_OF_BOUNDS              ;#4AA5: 21 20 ED
        add     a,l                                            ;#4AA8: 85
        ld      l,a                                            ;#4AA9: 6F
        ld      a,0                                            ;#4AAA: 3E 00
        adc     a,h                                            ;#4AAC: 8C
        ld      h,a                                            ;#4AAD: 67
        ld      a,(hl)                                         ;#4AAE: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4AAF: C3 CC 4A

QUERY_IN_BOUNDS:
        ; In-bounds path: compute PLAYFIELD_LOOKUP_TABLE row index
        ld      c,a                                            ;#4AB2: 4F
        ld      a,l                                            ;#4AB3: 7D
        cp      39h                                            ;#4AB4: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4AB6: 30 12
        ld      h,0                                            ;#4AB8: 26 00
        add     hl,hl                                          ;#4ABA: 29
        add     hl,hl                                          ;#4ABB: 29
        add     hl,hl                                          ;#4ABC: 29
        add     hl,hl                                          ;#4ABD: 29
        add     hl,hl                                          ;#4ABE: 29
        ld      a,c                                            ;#4ABF: 79
        add     a,l                                            ;#4AC0: 85
        ld      l,a                                            ;#4AC1: 6F
        ld      bc,PLAYFIELD_LOOKUP_TABLE                      ;#4AC2: 01 00 E6
        add     hl,bc                                          ;#4AC5: 09
        ld      a,(hl)                                         ;#4AC6: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4AC7: C3 CC 4A

QUERY_OUT_OF_BOUNDS:
        ; Out-of-bounds path: substitute cell value 87h (no playfield)
        ld      a,87h                                          ;#4ACA: 3E 87
QUERY_PLAYFIELD_EMIT:
        ; Copy a cell's 3x3 block (9 bytes) to 3 tile-buffer rows at DE +0/+1Eh/+3Ch
        ld      hl,PLAYFIELD_CELL_TILES                        ;#4ACC: 21 F6 4A
        add     a,l                                            ;#4ACF: 85
        ld      l,a                                            ;#4AD0: 6F
        ld      a,0                                            ;#4AD1: 3E 00
        adc     a,h                                            ;#4AD3: 8C
        ld      h,a                                            ;#4AD4: 67
        ld      bc,3                                           ;#4AD5: 01 03 00
        ldir                                                   ;#4AD8: ED B0
        ld      a,e                                            ;#4ADA: 7B
        add     a,1Bh                                          ;#4ADB: C6 1B
        ld      e,a                                            ;#4ADD: 5F
        ld      a,0                                            ;#4ADE: 3E 00
        adc     a,d                                            ;#4AE0: 8A
        ld      d,a                                            ;#4AE1: 57
        ld      c,3                                            ;#4AE2: 0E 03
        ldir                                                   ;#4AE4: ED B0
        ld      a,e                                            ;#4AE6: 7B
        add     a,1Bh                                          ;#4AE7: C6 1B
        ld      e,a                                            ;#4AE9: 5F
        ld      a,0                                            ;#4AEA: 3E 00
        adc     a,d                                            ;#4AEC: 8A
        ld      d,a                                            ;#4AED: 57
        ld      c,3                                            ;#4AEE: 0E 03
        ldir                                                   ;#4AF0: ED B0
        pop     hl                                             ;#4AF2: E1
        pop     de                                             ;#4AF3: D1
        pop     bc                                             ;#4AF4: C1
        ret                                                    ;#4AF5: C9

PLAYFIELD_CELL_TILES:
        ; Maze cell -> 3x3 tile block (16 cells, chars 80h+); paints the tile buffer
        PLAYFIELD_TILES "8C8C8C", "8C8C8C", "8C8C8C"           ;#4AF6: 8C 8C 8C 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C80", "8C8C81", "8C8C81"           ;#4AFF: 8C 8C 80 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8C8C82", "8C8C8C", "8C8C8C"           ;#4B08: 8C 8C 82 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C81", "8C8C81", "8C8C81"           ;#4B11: 8C 8C 81 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858587", "8C8C8C", "8C8C8C"           ;#4B1A: 85 85 87 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B23: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858585", "8C8C8C", "8C8C8C"           ;#4B2C: 85 85 85 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B35: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B3E: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8D", "848484", "848484"           ;#4B47: 8D 8D 8D 84 84 84 84 84 84
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B50: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8F", "848484", "848484"           ;#4B59: 8D 8D 8F 84 84 84 84 84 84
        PLAYFIELD_TILES "848489", "848489", "848489"           ;#4B62: 84 84 89 84 84 89 84 84 89
        PLAYFIELD_TILES "84848A", "848484", "848484"           ;#4B6B: 84 84 8A 84 84 84 84 84 84
        PLAYFIELD_TILES "848488", "848489", "848489"           ;#4B74: 84 84 88 84 84 89 84 84 89
        PLAYFIELD_TILES "848484", "848484", "848484"           ;#4B7D: 84 84 84 84 84 84 84 84 84

LOOKUP_PLAYFIELD_CELL:
        ; Given (H, L) map coord, index MAZE_BITMAP_N per STAGE_PALETTE_INDEX
        ; LOOKUP_PLAYFIELD_CELL takes (H, L) as a map coordinate and returns the
        ; playfield cell value in BC. Indexes MAZE_BITMAP_N at 7C00..7F00 at offset
        ; based on STAGE_PALETTE_INDEX (top bits) + coord. Returns cell type so callers
        ; can distinguish rock vs flag vs road.
        push    bc                                             ;#4B86: C5
        ld      bc,MAZE_BITMAP_0                               ;#4B87: 01 00 7C
        ld      a,l                                            ;#4B8A: 7D
        cp      38h                                            ;#4B8B: FE 38
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B8D: 30 25
        add     a,a                                            ;#4B8F: 87
        add     a,a                                            ;#4B90: 87
        ld      c,a                                            ;#4B91: 4F
        ld      a,h                                            ;#4B92: 7C
        cp      20h                                            ;#4B93: FE 20
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B95: 30 1D
        rra                                                    ;#4B97: 1F
        rra                                                    ;#4B98: 1F
        rra                                                    ;#4B99: 1F
        and     3                                              ;#4B9A: E6 03
        or      c                                              ;#4B9C: B1
        ld      c,a                                            ;#4B9D: 4F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4B9E: 3A B0 E0
        rra                                                    ;#4BA1: 1F
        rra                                                    ;#4BA2: 1F
        and     3                                              ;#4BA3: E6 03
        or      b                                              ;#4BA5: B0
        ld      b,a                                            ;#4BA6: 47
        ld      a,(bc)                                         ;#4BA7: 0A
        push    af                                             ;#4BA8: F5
        ld      a,h                                            ;#4BA9: 7C
        and     7                                              ;#4BAA: E6 07
        inc     a                                              ;#4BAC: 3C
        ld      b,a                                            ;#4BAD: 47
        pop     af                                             ;#4BAE: F1
LOOKUP_SHIFT_LOOP:
        ; Inner djnz of LOOKUP_PLAYFIELD_CELL (bit-extract per row)
        add     a,a                                            ;#4BAF: 87
        djnz    LOOKUP_SHIFT_LOOP                              ;#4BB0: 10 FD
        pop     bc                                             ;#4BB2: C1
        ret                                                    ;#4BB3: C9

LOOKUP_OUT_OF_BOUNDS:
        ; Coord out of range: set carry and return (signal blocked cell)
        scf                                                    ;#4BB4: 37
        pop     bc                                             ;#4BB5: C1
        ret                                                    ;#4BB6: C9

PLAYFIELD_TILE_LOOKUP:
        ; Helper called by INIT_PLAYFIELD_LOOKUP to compute one cell's value
        ld      c,0                                            ;#4BB7: 0E 00
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BB9: CD 86 4B
        rl      c                                              ;#4BBC: CB 11
        dec     l                                              ;#4BBE: 2D
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BBF: CD 86 4B
        rl      c                                              ;#4BC2: CB 11
        inc     h                                              ;#4BC4: 24
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BC5: CD 86 4B
        rl      c                                              ;#4BC8: CB 11
        inc     l                                              ;#4BCA: 2C
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BCB: CD 86 4B
        rl      c                                              ;#4BCE: CB 11
        ret                                                    ;#4BD0: C9

INIT_PLAYFIELD_LOOKUP:
        ; Build PLAYFIELD_LOOKUP_TABLE over coords 0..38h x 0..1Fh
        ; INIT_PLAYFIELD_LOOKUP builds a precomputed lookup table at
        ; PLAYFIELD_LOOKUP_TABLE (~1800 bytes). Iterates a 32x57 grid (l=0..38h,
        ; h=0..1Fh), calling PLAYFIELD_TILE_LOOKUP per cell to compute one 9-byte sub-
        ; record. The table speeds up per-frame queries via QUERY_PLAYFIELD_AT (replaces
        ; an arithmetic recompute with an indexed read).
        ld      de,PLAYFIELD_LOOKUP_TABLE                      ;#4BD1: 11 00 E6
        ld      hl,0                                           ;#4BD4: 21 00 00
INIT_LOOKUP_LOOP:
        ; INIT_PLAYFIELD_LOOKUP main grid loop: H over 0..1Fh, L stays
        push    hl                                             ;#4BD7: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BD8: CD B7 4B
        pop     hl                                             ;#4BDB: E1
        ld      a,c                                            ;#4BDC: 79
        add     a,a                                            ;#4BDD: 87
        add     a,a                                            ;#4BDE: 87
        add     a,a                                            ;#4BDF: 87
        add     a,c                                            ;#4BE0: 81
        ld      (de),a                                         ;#4BE1: 12
        inc     de                                             ;#4BE2: 13
        inc     h                                              ;#4BE3: 24
        ld      a,h                                            ;#4BE4: 7C
        cp      20h                                            ;#4BE5: FE 20
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BE7: 20 EE
        ld      h,0                                            ;#4BE9: 26 00
        inc     l                                              ;#4BEB: 2C
        ld      a,l                                            ;#4BEC: 7D
        cp      39h                                            ;#4BED: FE 39
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BEF: 20 E6
        ld      hl,0FF00h                                      ;#4BF1: 21 00 FF
INIT_LOOKUP_TAIL_LOOP:
        ; INIT_PLAYFIELD_LOOKUP tail loop with H=FF (wrap-around row at top)
        push    hl                                             ;#4BF4: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BF5: CD B7 4B
        pop     hl                                             ;#4BF8: E1
        ld      a,c                                            ;#4BF9: 79
        add     a,a                                            ;#4BFA: 87
        add     a,a                                            ;#4BFB: 87
        add     a,a                                            ;#4BFC: 87
        add     a,c                                            ;#4BFD: 81
        ld      (de),a                                         ;#4BFE: 12
        inc     de                                             ;#4BFF: 13
        inc     l                                              ;#4C00: 2C
        ld      a,l                                            ;#4C01: 7D
        cp      39h                                            ;#4C02: FE 39
        jr      nz,INIT_LOOKUP_TAIL_LOOP                       ;#4C04: 20 EE
        ret                                                    ;#4C06: C9

INIT_STAGE_TRACK_DATA:
        ; Initialize TRACK_DATA_RING region (10 x 0x5A blocks) with stage path/track state
        ; INIT_STAGE_TRACK_DATA initializes TRACK_DATA_RING. Sets up two 16-bit pointers
        ; (E088 = E08A = F400h, E08F = 320Fh, E092 = 0). Then loops 10 times, calling
        ; SCAN_PLAYFIELD_H_STRIP with HL=0B2Eh and DE walking by 0x5A per iter —
        ; populates the 10 enemy-car path/track records.
        ld      hl,0F400h                                      ;#4C07: 21 00 F4
        ld      (WORLD_X_POS),hl                               ;#4C0A: 22 88 E0
        ld      (WORLD_Y_POS),hl                               ;#4C0D: 22 8A E0
        ld      hl,320Fh                                       ;#4C10: 21 0F 32
        ld      (PLAYER_WORLD_POSITION_X),hl                   ;#4C13: 22 8F E0
        ld      hl,0                                           ;#4C16: 21 00 00
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4C19: 22 92 E0
        call    INIT_PLAYFIELD_LOOKUP                          ;#4C1C: CD D1 4B
        ld      b,0Ah                                          ;#4C1F: 06 0A
        ld      de,TRACK_DATA_RING                             ;#4C21: 11 00 EF
        ld      hl,0B2Eh                                       ;#4C24: 21 2E 0B
INIT_TRACK_DATA_LOOP:
        ; Inner djnz of INIT_STAGE_TRACK_DATA (10 enemy paths)
        push    hl                                             ;#4C27: E5
        push    de                                             ;#4C28: D5
        push    bc                                             ;#4C29: C5
        call    SCAN_PLAYFIELD_H_STRIP                         ;#4C2A: CD 75 4A
        pop     bc                                             ;#4C2D: C1
        pop     de                                             ;#4C2E: D1
        ld      hl,5Ah                                         ;#4C2F: 21 5A 00
        add     hl,de                                          ;#4C32: 19
        ex      de,hl                                          ;#4C33: EB
        pop     hl                                             ;#4C34: E1
        inc     l                                              ;#4C35: 2C
        djnz    INIT_TRACK_DATA_LOOP                           ;#4C36: 10 EF
        ret                                                    ;#4C38: C9

INIT_ENEMY_CARS:
        ; Clear 0x6F bytes at E300 and reset its iterator timer (E09D = 70h)
        ; INIT_ENEMY_CARS clears 6Fh bytes of ENEMY_CAR_TABLE to 0 and resets
        ; ENEMY_CAR_ITER_TIMER to 70h. Then loads stage-specific seed data from
        ; INITIAL_ENEMY_CARS_DATA using STAGE_ENEMY_SEED_LEN bytes worth.
        ld      a,70h                                          ;#4C39: 3E 70
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#4C3B: 32 9D E0
        ld      hl,ENEMY_CAR_TABLE                             ;#4C3E: 21 00 E3
        ld      de,ENEMY_CAR_TABLE_TAIL                        ;#4C41: 11 01 E3
        ld      bc,6Fh                                         ;#4C44: 01 6F 00
        ld      (hl),0                                         ;#4C47: 36 00
        ldir                                                   ;#4C49: ED B0
        ld      hl,INITIAL_ENEMY_CARS_DATA                     ;#4C4B: 21 5A 4C
        ld      de,ENEMY_CAR_TABLE                             ;#4C4E: 11 00 E3
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#4C51: 3A C0 E0
        ld      c,a                                            ;#4C54: 4F
        ld      b,0                                            ;#4C55: 06 00
        ldir                                                   ;#4C57: ED B0
        ret                                                    ;#4C59: C9

INITIAL_ENEMY_CARS_DATA:
        ; Stage-specific initial state for ENEMY_CAR_TABLE (E0C0 bytes copied)
        ; INITIAL_ENEMY_CARS_DATA holds the stage-specific seed for ENEMY_CAR_TABLE.
        ; STAGE_ENEMY_SEED_LEN bytes (=enemies*16) get copied in by INIT_ENEMY_CARS.
        ; Each 16-byte enemy record encodes type, initial position, direction, and AI
        ; state, rendered as the four ENEMY_SEED_1/_2/_3/_4 macro calls. Enemy car 1
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C5A: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4C5D: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=58h, screen_y=9Fh    ;#4C62: 34 58 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C67: 00 06 00
        ; Enemy car 2
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C6A: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4C6D: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=88h, screen_y=9Fh    ;#4C72: 34 88 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C77: 00 06 00
        ; Enemy car 3
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C7A: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Dh, y_accum=0C00h  ;#4C7D: 00 0C 0D 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=28h, screen_y=9Fh    ;#4C82: 34 28 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C87: 00 06 00
        ; Enemy car 4
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C8A: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=13h, y_accum=0C00h  ;#4C8D: 00 0C 13 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0B8h, screen_y=9Fh   ;#4C92: 34 B8 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C97: 00 06 00
        ; Enemy car 5
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C9A: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Bh, y_accum=0C00h  ;#4C9D: 00 0C 0B 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0FFF8h, screen_y=9Fh ;#4CA2: 34 F8 FF 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4CA7: 00 06 00
        ; Enemy car 6
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CAA: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4CAD: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=58h, screen_y=0FBEFh   ;#4CB2: 02 58 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CB7: 24 06 02
        ; Enemy car 7
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CBA: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4CBD: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=88h, screen_y=0FBEFh   ;#4CC2: 02 88 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CC7: 24 06 02
POLL_INPUT:
        ; Read PSG R14 joystick + SNSMAT row 8 keys; return combined input bits in C
        ; POLL_INPUT reads both joystick (via PSG R14 after configuring R15 as output
        ; via SET_PSG_REG) AND keyboard (SNSMAT row 8) and OR-combines them into C. Each
        ; direction/button has a unique bit in C. The combined state then feeds
        ; PROCESS_DIRECTION_INPUT and DEPLOY_SMOKE_IF_INPUT.
        ld      a,0Fh                                          ;#4CCA: 3E 0F
        ld      e,8Fh                                          ;#4CCC: 1E 8F
        call    BIOS_WRTPSG                                    ;#4CCE: CD 93 00
        ld      a,0Eh                                          ;#4CD1: 3E 0E
        call    BIOS_RDPSG                                     ;#4CD3: CD 96 00
        or      0C0h                                           ;#4CD6: F6 C0
        ld      c,a                                            ;#4CD8: 4F
        ld      a,8                                            ;#4CD9: 3E 08
        call    SNSMAT_PRESERVE_BC                             ;#4CDB: CD 08 4D
        rla                                                    ;#4CDE: 17
        jr      c,POLL_KEY_LEFT_DONE                           ;#4CDF: 38 02
        res     3,c                                            ;#4CE1: CB 99
POLL_KEY_LEFT_DONE:
        ; After clearing LEFT bit, fall through to DOWN probe
        rla                                                    ;#4CE3: 17
        jr      c,POLL_KEY_DOWN_DONE                           ;#4CE4: 38 02
        res     1,c                                            ;#4CE6: CB 89
POLL_KEY_DOWN_DONE:
        ; After clearing DOWN bit, fall through to UP probe
        rla                                                    ;#4CE8: 17
        jr      c,POLL_KEY_UP_DONE                             ;#4CE9: 38 02
        res     0,c                                            ;#4CEB: CB 81
POLL_KEY_UP_DONE:
        ; After clearing UP bit, fall through to RIGHT probe
        rla                                                    ;#4CED: 17
        jr      c,POLL_KEY_RIGHT_DONE                          ;#4CEE: 38 02
        res     2,c                                            ;#4CF0: CB 91
POLL_KEY_RIGHT_DONE:
        ; After clearing RIGHT bit, fall through to TRIGGER probe
        and     10h                                            ;#4CF2: E6 10
        jr      nz,POLL_KEY_TRIGGER_DONE                       ;#4CF4: 20 02
        res     7,c                                            ;#4CF6: CB B9
POLL_KEY_TRIGGER_DONE:
        ; Read SNSMAT row 5: check joystick trigger 1 bit
        ld      a,5                                            ;#4CF8: 3E 05
        call    SNSMAT_PRESERVE_BC                             ;#4CFA: CD 08 4D
        rla                                                    ;#4CFD: 17
        jr      c,POLL_KEY_GTRIG_DONE                          ;#4CFE: 38 02
        res     5,c                                            ;#4D00: CB A9
POLL_KEY_GTRIG_DONE:
        ; Read SNSMAT row 5: check joystick trigger 2 bit (general trigger)
        rla                                                    ;#4D02: 17
        rla                                                    ;#4D03: 17
        ret     c                                              ;#4D04: D8
        res     4,c                                            ;#4D05: CB A1
        ret                                                    ;#4D07: C9

SNSMAT_PRESERVE_BC:
        ; Tiny stub: call BIOS_SNSMAT preserving BC across the call
        push    bc                                             ;#4D08: C5
        call    BIOS_SNSMAT                                    ;#4D09: CD 41 01
        pop     bc                                             ;#4D0C: C1
        ret                                                    ;#4D0D: C9

INIT_VDP_AND_LOAD_GFX:
        ; Set VDP R0..R7 to screen-1 layout and upload initial pattern/sprite/color tables
        ; INIT_VDP_AND_LOAD_GFX is the boot's "all the graphics" routine. It: (1) writes
        ; VDP R0..R7 from INITIAL_VDP_REGISTERS to configure screen 1 layout, (2)
        ; uploads INITIAL_COLOR_TABLE to the color table at 0780h, (3) zeros 2KB of RAM
        ; at TEMP_SPACE, (4) copies TILE_PATTERN_HEX_DIGITS / TILE_PATTERN_NAMCOT_LOGO
        ; and three repetitions of TILE_PATTERN_CHAR_FONT into that RAM, (5) bit-
        ; transposes 9 sprite patterns via TRANSPOSE_TILE_BLOCKS, (6) LDIRVMs the
        ; prepared data into both pattern-table banks (0800h and 1800h), and finally (7)
        ; uploads the SPRITE_FLAG.. and SPRITE_BONUS_100.. patterns. Step (3)'s RAM zero
        ; matters: the 2KB at TEMP_SPACE is the LDIRVM source for both pattern banks, so
        ; any leftover stack/state bytes would leak into the pattern table.
        ld      hl,INITIAL_VDP_REGISTERS                       ;#4D0E: 21 A7 4D
        ld      bc,800h                                        ;#4D11: 01 00 08
VDP_REG_INIT_LOOP:
        ; Inner djnz of INIT_VDP_AND_LOAD_GFX (8 registers)
        push    bc                                             ;#4D14: C5
        ld      b,(hl)                                         ;#4D15: 46
        call    BIOS_WRTVDP                                    ;#4D16: CD 47 00
        pop     bc                                             ;#4D19: C1
        inc     hl                                             ;#4D1A: 23
        inc     c                                              ;#4D1B: 0C
        djnz    VDP_REG_INIT_LOOP                              ;#4D1C: 10 F6
        ld      hl,INITIAL_COLOR_TABLE                         ;#4D1E: 21 AF 4D
        LOAD_VRAM_ADDRESS de, 780h                             ;#4D21: 11 80 07
        ld      bc,20h                                         ;#4D24: 01 20 00
        call    BIOS_LDIRVM                                    ;#4D27: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D2A: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#4D2D: 11 01 E0
        ld      (hl),0                                         ;#4D30: 36 00
        ld      bc,7FFh                                        ;#4D32: 01 FF 07
        ldir                                                   ;#4D35: ED B0
        ld      hl,TILE_PATTERN_HEX_DIGITS                     ;#4D37: 21 DA 60
        ld      de,TEMP_SPACE                                  ;#4D3A: 11 00 E0
        ld      bc,100h                                        ;#4D3D: 01 00 01
        ldir                                                   ;#4D40: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D42: 21 9A 61
        ld      b,1                                            ;#4D45: 06 01
        ldir                                                   ;#4D47: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D49: 21 9A 61
        ld      b,1                                            ;#4D4C: 06 01
        ldir                                                   ;#4D4E: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D50: 21 9A 61
        ld      b,1                                            ;#4D53: 06 01
        ldir                                                   ;#4D55: ED B0
        ld      hl,TEMP_SPACE                                  ;#4D57: 21 00 E0
        LOAD_VRAM_ADDRESS de, 800h                             ;#4D5A: 11 00 08
        ld      bc,800h                                        ;#4D5D: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D60: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D63: 21 00 E0
        LOAD_VRAM_ADDRESS de, 1800h                            ;#4D66: 11 00 18
        ld      bc,800h                                        ;#4D69: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D6C: CD 5C 00
        ld      hl,SPRITE_CAR                                  ;#4D6F: 21 FA 5C
        ld      de,TEMP_SPACE                                  ;#4D72: 11 00 E0
        ld      bc,60h                                         ;#4D75: 01 60 00
        ldir                                                   ;#4D78: ED B0
        ld      hl,SPRITE_PATTERN_WORK_BUF                     ;#4D7A: 21 60 E0
        ld      de,TEMP_SPACE                                  ;#4D7D: 11 00 E0
        call    TRANSPOSE_TILE_BLOCKS                          ;#4D80: CD CF 4D
        ld      hl,TEMP_SPACE                                  ;#4D83: 21 00 E0
        LOAD_VRAM_ADDRESS de, 3000h                            ;#4D86: 11 00 30
        ld      bc,180h                                        ;#4D89: 01 80 01
        call    BIOS_LDIRVM                                    ;#4D8C: CD 5C 00
        ld      hl,SPRITE_FLAG                                 ;#4D8F: 21 5A 5D
        LOAD_VRAM_ADDRESS de, 3180h                            ;#4D92: 11 80 31
        ld      bc,100h                                        ;#4D95: 01 00 01
        call    BIOS_LDIRVM                                    ;#4D98: CD 5C 00
        ld      hl,SPRITE_BONUS_100                            ;#4D9B: 21 1A 5E
        LOAD_VRAM_ADDRESS de, 3400h                            ;#4D9E: 11 00 34
        ld      bc,2C0h                                        ;#4DA1: 01 C0 02
        jp      BIOS_LDIRVM                                    ;#4DA4: C3 5C 00

INITIAL_VDP_REGISTERS:
        ; Screen-1 R0..R7 init block: name=0400h, SAT=0700h, patterns=0800h
        ; INITIAL_VDP_REGISTERS — 8 bytes loaded into VDP R0..R7 by boot. R0=00 (M3=0,
        ; no horiz IRQ), R1=82h (screen blank, IRQs off, 16x16 sprites — screen 1 mode),
        ; R2=01 (name table 0400h), R3=1E (color 0780h), R4=01 (patterns 0800h), R5=0E
        ; (SAT 0700h), R6=06 (sprite patterns 3000h), R7=F0 (FG=white BG=transparent).
        db      0, 82h, 1, 1Eh, 1, 0Eh, 6, 0F0h ; VDP registers R0..R7  ;#4DA7: 00 82 01 1E 01 0E 06 F0

INITIAL_COLOR_TABLE:
        ; 32-byte screen-1 colour table uploaded to VRAM 0780h (not SAT)
        dh      "F0F080F070707070F0F0F0F080808080"             ;#4DAF: F0 F0 80 F0 70 70 70 70 F0 F0 F0 F0 80 80 80 80
        dh      "2992F0F0A0A0F0F010106060F0F0F0F0"             ;#4DBF: 29 92 F0 F0 A0 A0 F0 F0 10 10 60 60 F0 F0 F0 F0

TRANSPOSE_TILE_BLOCKS:
        ; Process 9 32-byte blocks via 4 sub-quadrant TRANSPOSE_TILE_BITS calls each
        ; TRANSPOSE_TILE_BLOCKS processes 9 tile-pattern blocks of 32 bytes each by
        ; calling TRANSPOSE_TILE_BITS 4 times per iteration (one per 8-byte quadrant).
        ; The 4 quadrant offsets within a 32-byte tile are +16, +0, +24, +8 (i.e.
        ; quadrant order is bottom-left, top-left, bottom-right, top-right). This
        ; rearranges packed source data into VRAM-pattern-table format before LDIRVM.
        ld      b,9                                            ;#4DCF: 06 09
TRANSPOSE_BLOCKS_LOOP:
        ; Outer djnz of TRANSPOSE_TILE_BLOCKS (9 tile blocks)
        push    bc                                             ;#4DD1: C5
        push    hl                                             ;#4DD2: E5
        ld      bc,10h                                         ;#4DD3: 01 10 00
        add     hl,bc                                          ;#4DD6: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DD7: CD FA 4D
        pop     hl                                             ;#4DDA: E1
        push    hl                                             ;#4DDB: E5
        call    TRANSPOSE_TILE_BITS                            ;#4DDC: CD FA 4D
        pop     hl                                             ;#4DDF: E1
        push    hl                                             ;#4DE0: E5
        ld      bc,18h                                         ;#4DE1: 01 18 00
        add     hl,bc                                          ;#4DE4: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DE5: CD FA 4D
        pop     hl                                             ;#4DE8: E1
        push    hl                                             ;#4DE9: E5
        ld      bc,8                                           ;#4DEA: 01 08 00
        add     hl,bc                                          ;#4DED: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DEE: CD FA 4D
        pop     hl                                             ;#4DF1: E1
        ld      bc,20h                                         ;#4DF2: 01 20 00
        add     hl,bc                                          ;#4DF5: 09
        pop     bc                                             ;#4DF6: C1
        djnz    TRANSPOSE_BLOCKS_LOOP                          ;#4DF7: 10 D8
        ret                                                    ;#4DF9: C9

TRANSPOSE_TILE_BITS:
        ; 8x8 bit-matrix transpose: 8 input bytes -> 8 output bytes (bit-column-first)
        ; TRANSPOSE_TILE_BITS is the classic 8×8 bit-matrix transpose: 8 input bytes
        ; interpreted as an 8×8 bit grid become 8 output bytes with rows and columns
        ; swapped. Implemented as 2 nested loops: inner 8x `add a,a; rr (hl); inc hl`
        ; (shifts bits column-wise), outer 8x to consume each input byte.
        ld      c,8                                            ;#4DFA: 0E 08
TRANSPOSE_OUTER_LOOP:
        ; Outer 8-byte loop of TRANSPOSE_TILE_BITS (one column per iter)
        ld      a,(de)                                         ;#4DFC: 1A
        inc     de                                             ;#4DFD: 13
        push    hl                                             ;#4DFE: E5
        ld      b,8                                            ;#4DFF: 06 08
TRANSPOSE_INNER_BIT:
        ; Inner djnz of TRANSPOSE_TILE_BITS (bit-by-bit shift)
        add     a,a                                            ;#4E01: 87
        rr      (hl)                                           ;#4E02: CB 1E
        inc     hl                                             ;#4E04: 23
        djnz    TRANSPOSE_INNER_BIT                            ;#4E05: 10 FA
        pop     hl                                             ;#4E07: E1
        dec     c                                              ;#4E08: 0D
        jr      nz,TRANSPOSE_OUTER_LOOP                        ;#4E09: 20 F1
        ret                                                    ;#4E0B: C9

UPLOAD_PATTERN_SLICE:
        ; Pick a slice via TILE_PATTERN_SLICE_TABLE then LDIRVM to VRAM 0C00h
        ; UPLOAD_PATTERN_SLICE selects a 128-byte tile-pattern slice from
        ; TILE_PATTERN_SLICE_TABLE based on PLAYER_VELOCITY_X, then LDIRVMs it to VRAM
        ; 0C00h (pattern table). Used to switch dynamic patterns per game state.
        ld      a,(PLAYER_VELOCITY_X)                          ;#4E0C: 3A 89 E0
        add     a,18h                                          ;#4E0F: C6 18
        and     7                                              ;#4E11: E6 07
        add     a,a                                            ;#4E13: 87
        ld      hl,TILE_PATTERN_SLICE_TABLE                    ;#4E14: 21 D2 4E
        add     a,l                                            ;#4E17: 85
        ld      l,a                                            ;#4E18: 6F
        ld      a,0                                            ;#4E19: 3E 00
        adc     a,h                                            ;#4E1B: 8C
        ld      h,a                                            ;#4E1C: 67
        ld      a,(hl)                                         ;#4E1D: 7E
        inc     hl                                             ;#4E1E: 23
        ld      h,(hl)                                         ;#4E1F: 66
        ld      l,a                                            ;#4E20: 6F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4E21: 3A 8B E0
        add     a,18h                                          ;#4E24: C6 18
        neg                                                    ;#4E26: ED 44
        and     7                                              ;#4E28: E6 07
        inc     a                                              ;#4E2A: 3C
        ld      b,a                                            ;#4E2B: 47
UPLOAD_PATTERN_SLICE_DEC_HL:
        ; Inner djnz of UPLOAD_PATTERN_SLICE (rewind HL)
        dec     hl                                             ;#4E2C: 2B
        djnz    UPLOAD_PATTERN_SLICE_DEC_HL                    ;#4E2D: 10 FD
        ld      a,(FRAME_TICK)                                 ;#4E2F: 3A 87 E0
        rra                                                    ;#4E32: 1F
        jr      nc,UPLOAD_PATTERN_SLICE_BANK_B                 ;#4E33: 30 0C
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#4E35: 11 00 0C
        ld      bc,80h                                         ;#4E38: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E3B: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E3E: C3 4D 4E

UPLOAD_PATTERN_SLICE_BANK_B:
        ; Bank-B path: LDIRVM the slice to VRAM 1C00h instead of 0C00h
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#4E41: 11 00 1C
        ld      bc,80h                                         ;#4E44: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E47: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E4A: C3 4D 4E

UPLOAD_PATTERN_SLICE_AFTER_LDIRVM:
        ; After both bank LDIRVM paths: prepare to update VRAM cursor for next slice
        ld      de,PLAYER_VELOCITY_Y                           ;#4E4D: 11 8B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#4E50: 21 8C E0
        ld      a,(de)                                         ;#4E53: 1A
        add     a,1Fh                                          ;#4E54: C6 1F
        rra                                                    ;#4E56: 1F
        rra                                                    ;#4E57: 1F
        rra                                                    ;#4E58: 1F
        and     7                                              ;#4E59: E6 07
        cp      (hl)                                           ;#4E5B: BE
        jr      nz,UPLOAD_PATTERN_SLICE_FIRST_ROW              ;#4E5C: 20 21
        ld      b,a                                            ;#4E5E: 47
        dec     de                                             ;#4E5F: 1B
        dec     de                                             ;#4E60: 1B
        inc     hl                                             ;#4E61: 23
        ld      a,(de)                                         ;#4E62: 1A
        add     a,18h                                          ;#4E63: C6 18
        rra                                                    ;#4E65: 1F
        rra                                                    ;#4E66: 1F
        rra                                                    ;#4E67: 1F
        and     7                                              ;#4E68: E6 07
        cp      (hl)                                           ;#4E6A: BE
        jp      z,UPDATE_RADAR                                 ;#4E6B: CA EA 52
        ld      (hl),a                                         ;#4E6E: 77
        ld      hl,TRACK_DATA_RING                             ;#4E6F: 21 00 EF
        add     a,l                                            ;#4E72: 85
        ld      l,a                                            ;#4E73: 6F
        ld      a,0                                            ;#4E74: 3E 00
        adc     a,h                                            ;#4E76: 8C
        ld      h,a                                            ;#4E77: 67
        ld      de,1Eh                                         ;#4E78: 11 1E 00
        inc     b                                              ;#4E7B: 04
        jp      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E7C: C3 9A 4E

UPLOAD_PATTERN_SLICE_FIRST_ROW:
        ; First-row branch: update the playfield-position byte, then advance the loop
        ld      (hl),a                                         ;#4E7F: 77
        ld      b,a                                            ;#4E80: 47
        dec     de                                             ;#4E81: 1B
        dec     de                                             ;#4E82: 1B
        inc     hl                                             ;#4E83: 23
        ld      a,(de)                                         ;#4E84: 1A
        add     a,18h                                          ;#4E85: C6 18
        rra                                                    ;#4E87: 1F
        rra                                                    ;#4E88: 1F
        rra                                                    ;#4E89: 1F
        and     7                                              ;#4E8A: E6 07
        ld      (hl),a                                         ;#4E8C: 77
        ld      hl,TRACK_DATA_RING                             ;#4E8D: 21 00 EF
        add     a,l                                            ;#4E90: 85
        ld      l,a                                            ;#4E91: 6F
        ld      a,0                                            ;#4E92: 3E 00
        adc     a,h                                            ;#4E94: 8C
        ld      h,a                                            ;#4E95: 67
        ld      de,1Eh                                         ;#4E96: 11 1E 00
        inc     b                                              ;#4E99: 04
UPLOAD_PATTERN_SLICE_ADVANCE_LOOP:
        ; Inner djnz: HL += 1Eh per iteration (skip 30 chars between visible rows)
        dec     b                                              ;#4E9A: 05
        jr      z,UPLOAD_PATTERN_SLICE_BANK_SWAP               ;#4E9B: 28 03
        add     hl,de                                          ;#4E9D: 19
        jr      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E9E: 18 FA

UPLOAD_PATTERN_SLICE_BANK_SWAP:
        ; Frame-parity gate: choose bank-A (NAME_BANK_FLAG=0) or bank-B path
        ld      b,18h                                          ;#4EA0: 06 18
        ld      de,400h                                        ;#4EA2: 11 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#4EA5: 3A 8E E0
        and     a                                              ;#4EA8: A7
        jp      nz,UPLOAD_PATTERN_SLICE_BANK_CLEAR             ;#4EA9: C2 B7 4E
        ld      a,1                                            ;#4EAC: 3E 01
        ld      (NAME_BANK_FLAG),a                             ;#4EAE: 32 8E E0
        LOAD_VRAM_ADDRESS de, 1400h                            ;#4EB1: 11 00 14
        jp      UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4EB4: C3 BB 4E

UPLOAD_PATTERN_SLICE_BANK_CLEAR:
        ; Bank-A path: clear NAME_BANK_FLAG so the next frame uses bank-B
        xor     a                                              ;#4EB7: AF
        ld      (NAME_BANK_FLAG),a                             ;#4EB8: 32 8E E0
UPLOAD_PATTERN_SLICE_LDIRVM_SLICE:
        ; LDIRVM the 23-tile row to the name table at chosen bank
        push    bc                                             ;#4EBB: C5
        push    hl                                             ;#4EBC: E5
        push    de                                             ;#4EBD: D5
        ld      bc,17h                                         ;#4EBE: 01 17 00
        call    BIOS_LDIRVM                                    ;#4EC1: CD 5C 00
        pop     hl                                             ;#4EC4: E1
        ld      bc,20h                                         ;#4EC5: 01 20 00
        add     hl,bc                                          ;#4EC8: 09
        ex      de,hl                                          ;#4EC9: EB
        pop     hl                                             ;#4ECA: E1
        ld      c,1Eh                                          ;#4ECB: 0E 1E
        add     hl,bc                                          ;#4ECD: 09
        pop     bc                                             ;#4ECE: C1
        djnz    UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4ECF: 10 EA
        ret                                                    ;#4ED1: C9

TILE_PATTERN_SLICE_TABLE:
        ; 8 endpoint pointers into the per-substate tile-pattern data block
        dw TILE_SLICE_0 + 9                                    ;#4ED2: EB 4E
        dw TILE_SLICE_1 + 9                                    ;#4ED4: 6B 4F
        dw TILE_SLICE_2 + 9                                    ;#4ED6: EB 4F
        dw TILE_SLICE_3 + 9                                    ;#4ED8: 6B 50
        dw TILE_SLICE_4 + 9                                    ;#4EDA: EB 50
        dw TILE_SLICE_5 + 9                                    ;#4EDC: 6B 51
        dw TILE_SLICE_6 + 9                                    ;#4EDE: EB 51
        dw TILE_SLICE_7 + 9                                    ;#4EE0: 6B 52

TILE_SLICE_0:
        ; 128-byte tile-pattern slice 0 (table points to TILE_SLICE_0 + 9)
        dh      "00000000000000000000000000000000"             ;#4EE2: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4EF2: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F02: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F12: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF
        dh      "00000000000000000000000000000000"             ;#4F22: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4F32: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F42: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F52: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF

TILE_SLICE_1:
        ; 128-byte tile-pattern slice 1
        dh      "00000000000000000101010101010101"             ;#4F62: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4F72: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F82: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4F92: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE
        dh      "00000000000000000101010101010101"             ;#4FA2: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4FB2: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4FC2: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4FD2: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE

TILE_SLICE_2:
        ; 128-byte tile-pattern slice 2
        dh      "00000000000000000303030303030303"             ;#4FE2: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#4FF2: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5002: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#5012: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC
        dh      "00000000000000000303030303030303"             ;#5022: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#5032: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5042: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#5052: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC

TILE_SLICE_3:
        ; 128-byte tile-pattern slice 3
        dh      "00000000000000000707070707070707"             ;#5062: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#5072: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5082: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#5092: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8
        dh      "00000000000000000707070707070707"             ;#50A2: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#50B2: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#50C2: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#50D2: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8

TILE_SLICE_4:
        ; 128-byte tile-pattern slice 4
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#50E2: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#50F2: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5102: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#5112: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#5122: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#5132: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5142: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#5152: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0

TILE_SLICE_5:
        ; 128-byte tile-pattern slice 5
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#5162: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#5172: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5182: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#5192: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#51A2: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#51B2: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#51C2: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#51D2: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0

TILE_SLICE_6:
        ; 128-byte tile-pattern slice 6
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#51E2: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#51F2: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5202: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#5212: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#5222: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#5232: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5242: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#5252: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0

TILE_SLICE_7:
        ; 136-byte tile-pattern slice 7 (extended tail)
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#5262: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#5272: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5282: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#5292: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#52A2: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#52B2: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#52C2: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#52D2: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "0000000000000000"                             ;#52E2: 00 00 00 00 00 00 00 00

UPDATE_RADAR:
        ; Snapshot RADAR_GRID into OBSTACLE_GRID, then refresh entity dots
        ; UPDATE_RADAR refreshes the on-screen radar. (1) Snapshots RADAR_GRID (112)
        ; into OBSTACLE_GRID. (2) When FRAME_TICK & 8 fires, clears the previous frame's
        ; player dot via RADAR_LAST_DOT_PTR. (3) Calls UPDATE_RADAR_DOT_A/B 7 times —
        ; one per entry in ENEMY_CAR_TABLE (10h stride). (4) Plots the player explicitly
        ; at PLAYER_SCREEN_X/Y via PROBE_OBSTACLE_CELL. The 7-call pattern A,B,B,A,A,B,A
        ; is deliberate, not arbitrary: the two variants are identical EXCEPT in which
        ; FRAME_TICK parity they yield priority on (A skips overwriting occupied cells
        ; on odd frames; B skips on even). Because later calls overwrite earlier, when
        ; several enemies' dots collide on the same radar cell the last permitted writer
        ; wins. The sequence is engineered so entries 5 (B) and 6 (A) — the two trailing
        ; enemy slots — alternate as overlap-winner each frame, producing a deliberate
        ; blink that surfaces high-priority chasers through pile-ups instead of silently
        ; obscuring them.
        ld      hl,RADAR_GRID                                  ;#52EA: 21 00 EE
        ld      de,OBSTACLE_GRID                               ;#52ED: 11 80 EE
        ld      bc,70h                                         ;#52F0: 01 70 00
        ldir                                                   ;#52F3: ED B0
        ld      a,(FRAME_TICK)                                 ;#52F5: 3A 87 E0
        and     8                                              ;#52F8: E6 08
        jr      z,RADAR_AFTER_CLEAR                            ;#52FA: 28 05
        ld      hl,(RADAR_LAST_DOT_PTR)                        ;#52FC: 2A A5 E0
        ld      (hl),90h                                       ;#52FF: 36 90
RADAR_AFTER_CLEAR:
        ; After optional player-dot clear: set up IX = ENEMY_CAR_TABLE for plot
        ld      ix,ENEMY_CAR_TABLE                             ;#5301: DD 21 00 E3
        call    UPDATE_RADAR_DOT_A                             ;#5305: CD 5A 53
        call    UPDATE_RADAR_DOT_B                             ;#5308: CD 96 53
        call    UPDATE_RADAR_DOT_B                             ;#530B: CD 96 53
        call    UPDATE_RADAR_DOT_A                             ;#530E: CD 5A 53
        call    UPDATE_RADAR_DOT_A                             ;#5311: CD 5A 53
        call    UPDATE_RADAR_DOT_B                             ;#5314: CD 96 53
        call    UPDATE_RADAR_DOT_A                             ;#5317: CD 5A 53
        ld      a,(PLAYER_SCREEN_X)                            ;#531A: 3A A3 E0
        ld      d,a                                            ;#531D: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#531E: 3A A4 E0
        ld      e,a                                            ;#5321: 5F
        ld      c,0B0h                                         ;#5322: 0E B0
        ld      a,(FRAME_TICK)                                 ;#5324: 3A 87 E0
        and     10h                                            ;#5327: E6 10
        jr      z,RADAR_PROBE_PLAYER                           ;#5329: 28 02
        ld      c,0C0h                                         ;#532B: 0E C0
RADAR_PROBE_PLAYER:
        ; Plot the player dot at PLAYER_SCREEN_X/Y with blinking color B0h/C0h
        call    PROBE_OBSTACLE_CELL                            ;#532D: CD 6C 53
        ld      hl,OBSTACLE_GRID                               ;#5330: 21 80 EE
        ld      b,0Eh                                          ;#5333: 06 0E
        ld      de,4F7h                                        ;#5335: 11 F7 04
        ld      a,(NAME_BANK_FLAG)                             ;#5338: 3A 8E E0
        and     a                                              ;#533B: A7
        jr      z,RADAR_UPLOAD_ROW_LOOP                        ;#533C: 28 03
        LOAD_VRAM_ADDRESS de, 14F7h                            ;#533E: 11 F7 14
RADAR_UPLOAD_ROW_LOOP:
        ; Inner djnz: LDIRVM 8 radar bytes per row, then HL+=8, DE+=20h
        push    bc                                             ;#5341: C5
        push    de                                             ;#5342: D5
        push    hl                                             ;#5343: E5
        ld      bc,8                                           ;#5344: 01 08 00
        ; BIOS_LDIRVM call inside the radar-clear loop. Used by UPDATE_RADAR to bulk-
        ; clear the radar grid before redrawing entity dots. Just a standard LDIRVM call
        ; site (no enclosing macro because the source is computed register, not
        ; literal).
        call    BIOS_LDIRVM                                    ;#5347: CD 5C 00
        pop     hl                                             ;#534A: E1
        ld      bc,8                                           ;#534B: 01 08 00
        add     hl,bc                                          ;#534E: 09
        pop     de                                             ;#534F: D1
        ex      de,hl                                          ;#5350: EB
        ld      bc,20h                                         ;#5351: 01 20 00
        add     hl,bc                                          ;#5354: 09
        ex      de,hl                                          ;#5355: EB
        pop     bc                                             ;#5356: C1
        djnz    RADAR_UPLOAD_ROW_LOOP                          ;#5357: 10 E8
        ret                                                    ;#5359: C9

UPDATE_RADAR_DOT_A:
        ; Per-entity radar update helper (variant A, reads ix+5/+8)
        ; UPDATE_RADAR_DOT_A reads the current ENEMY_CAR_TABLE entry's (ix+5, ix+8)
        ; screen position, advances IX by 10h (next entry), then falls into
        ; PROBE_OBSTACLE_CELL with c=0D0h (radar dot color). PROBE_OBSTACLE_CELL maps
        ; (D, E) to an OBSTACLE_GRID byte and: - if cell empty (90h) → always write c -
        ; if occupied → `rra` on FRAME_TICK, `ret c` (skip on ODD frames). Variant B
        ; (UPDATE_RADAR_DOT_B) is byte-identical except the final test is `ret nc` (skip
        ; on EVEN frames). The A/B split lets the caller pick which frame-parity each
        ; enemy yields overlap priority on — see UPDATE_RADAR for the sequencing
        ; rationale.
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#535A: DD 7E 00
        and     a                                              ;#535D: A7
        ret     z                                              ;#535E: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#535F: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5362: DD 5E 08
        ld      bc,10h                                         ;#5365: 01 10 00
        add     ix,bc                                          ;#5368: DD 09
        ld      c,0D0h                                         ;#536A: 0E D0
PROBE_OBSTACLE_CELL:
        ; Compute OBSTACLE_GRID index from (D, E) coord and read cell; compare to 90h
        ; PROBE_OBSTACLE_CELL takes (D, E) as a map coordinate, computes a bit index
        ; into OBSTACLE_GRID (128 bytes covering 32x32 cells), reads the cell value, and
        ; compares to 90h (empty marker). Returns z-flag set if cell is empty, clear if
        ; occupied. Used by AI for collision/path checks.
        ld      a,d                                            ;#536C: 7A
        and     3                                              ;#536D: E6 03
        or      c                                              ;#536F: B1
        ld      c,a                                            ;#5370: 4F
        ld      a,e                                            ;#5371: 7B
        add     a,a                                            ;#5372: 87
        add     a,a                                            ;#5373: 87
        and     0Ch                                            ;#5374: E6 0C
        or      c                                              ;#5376: B1
        ld      c,a                                            ;#5377: 4F
        ld      a,d                                            ;#5378: 7A
        rra                                                    ;#5379: 1F
        rra                                                    ;#537A: 1F
        and     7                                              ;#537B: E6 07
        ld      l,a                                            ;#537D: 6F
        ld      a,e                                            ;#537E: 7B
        add     a,a                                            ;#537F: 87
        and     78h                                            ;#5380: E6 78
        or      l                                              ;#5382: B5
        ld      l,a                                            ;#5383: 6F
        ld      h,0                                            ;#5384: 26 00
        ld      de,OBSTACLE_GRID                               ;#5386: 11 80 EE
        add     hl,de                                          ;#5389: 19
        ld      a,(hl)                                         ;#538A: 7E
        cp      90h                                            ;#538B: FE 90
        jr      z,RADAR_A_WRITE_CELL                           ;#538D: 28 05
        ld      a,(FRAME_TICK)                                 ;#538F: 3A 87 E0
        rra                                                    ;#5392: 1F
        ret     c                                              ;#5393: D8
RADAR_A_WRITE_CELL:
        ; Variant A write: store color C into the radar cell (occupied or empty)
        ld      (hl),c                                         ;#5394: 71
        ret                                                    ;#5395: C9

UPDATE_RADAR_DOT_B:
        ; Per-entity radar update helper (variant B)
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5396: DD 7E 00
        and     a                                              ;#5399: A7
        ret     z                                              ;#539A: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#539B: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#539E: DD 5E 08
        ld      bc,10h                                         ;#53A1: 01 10 00
        add     ix,bc                                          ;#53A4: DD 09
        ld      c,0D0h                                         ;#53A6: 0E D0
        ld      a,d                                            ;#53A8: 7A
        and     3                                              ;#53A9: E6 03
        or      c                                              ;#53AB: B1
        ld      c,a                                            ;#53AC: 4F
        ld      a,e                                            ;#53AD: 7B
        add     a,a                                            ;#53AE: 87
        add     a,a                                            ;#53AF: 87
        and     0Ch                                            ;#53B0: E6 0C
        or      c                                              ;#53B2: B1
        ld      c,a                                            ;#53B3: 4F
        ld      a,d                                            ;#53B4: 7A
        rra                                                    ;#53B5: 1F
        rra                                                    ;#53B6: 1F
        and     7                                              ;#53B7: E6 07
        ld      l,a                                            ;#53B9: 6F
        ld      a,e                                            ;#53BA: 7B
        add     a,a                                            ;#53BB: 87
        and     78h                                            ;#53BC: E6 78
        or      l                                              ;#53BE: B5
        ld      l,a                                            ;#53BF: 6F
        ld      h,0                                            ;#53C0: 26 00
        ld      de,OBSTACLE_GRID                               ;#53C2: 11 80 EE
        add     hl,de                                          ;#53C5: 19
        ld      a,(hl)                                         ;#53C6: 7E
        cp      90h                                            ;#53C7: FE 90
        jr      z,RADAR_B_WRITE_CELL                           ;#53C9: 28 05
        ld      a,(FRAME_TICK)                                 ;#53CB: 3A 87 E0
        rra                                                    ;#53CE: 1F
        ret     nc                                             ;#53CF: D0
RADAR_B_WRITE_CELL:
        ; Variant B write: store color C into the radar cell (opposite frame parity)
        ld      (hl),c                                         ;#53D0: 71
        ret                                                    ;#53D1: C9

INIT_STAGE:
        ; Fill RADAR_GRID with 90h and seed FLAG_TABLE with 10 random entries
        ; INIT_STAGE first fills RADAR_GRID (112 bytes) with 90h (empty-cell marker).
        ; Then loops 10 times: write 1 to flag's active byte, call NEXT_RANDOM twice for
        ; X/Y, place flag at random position. The 10 flags = 8 yellow + 2 red special,
        ; matching tile pattern in INIT_FLAGS at stage start.
        ld      hl,RADAR_GRID                                  ;#53D2: 21 00 EE
        ld      de,RADAR_GRID_TAIL                             ;#53D5: 11 01 EE
        ld      bc,6Fh                                         ;#53D8: 01 6F 00
        ld      (hl),90h                                       ;#53DB: 36 90
        ldir                                                   ;#53DD: ED B0
        ld      hl,FLAG_TABLE                                  ;#53DF: 21 00 E1
        ld      a,0Ah                                          ;#53E2: 3E 0A
        ld      (STAGE_DIFFICULTY),a                           ;#53E4: 32 AE E0
        ld      b,a                                            ;#53E7: 47
INIT_STAGE_FLAG_LOOP:
        ; Outer loop body: write 1 to active byte, push pointer, pick new random pos
        ld      (hl),1                                         ;#53E8: 36 01
        inc     hl                                             ;#53EA: 23
        push    hl                                             ;#53EB: E5
INIT_STAGE_RANDOM_X:
        ; Pick a random X (in [0..1Fh])
        call    NEXT_RANDOM                                    ;#53EC: CD EF 54
        and     1Fh                                            ;#53EF: E6 1F
        ld      h,a                                            ;#53F1: 67
INIT_STAGE_RANDOM_Y:
        ; Pick a random Y (must be < 38h; retry if larger)
        call    NEXT_RANDOM                                    ;#53F2: CD EF 54
        and     3Fh                                            ;#53F5: E6 3F
        cp      38h                                            ;#53F7: FE 38
        jr      nc,INIT_STAGE_RANDOM_Y                         ;#53F9: 30 F7
        ld      l,a                                            ;#53FB: 6F
        cp      4                                              ;#53FC: FE 04
        jr      c,INIT_STAGE_CHECK_Y_BOUNDS                    ;#53FE: 38 04
        cp      32h                                            ;#5400: FE 32
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#5402: 38 09
INIT_STAGE_CHECK_Y_BOUNDS:
        ; Y in range: check that X is not in PLAYER_SPAWN_ZONE (0..9 or 10h..14h)
        ld      a,h                                            ;#5404: 7C
        cp      0Ah                                            ;#5405: FE 0A
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#5407: 38 04
        cp      15h                                            ;#5409: FE 15
        jr      c,INIT_STAGE_RANDOM_X                          ;#540B: 38 DF
INIT_STAGE_CHECK_PLAYFIELD:
        ; Coord passed; verify cell is not a wall via LOOKUP_PLAYFIELD_CELL
        call    LOOKUP_PLAYFIELD_CELL                          ;#540D: CD 86 4B
        jr      c,INIT_STAGE_RANDOM_X                          ;#5410: 38 DA
        ex      de,hl                                          ;#5412: EB
        ld      hl,ROCK_TABLE                                  ;#5413: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5416: 3A 9C E0
        and     a                                              ;#5419: A7
        jr      z,INIT_STAGE_AFTER_ROCKS                       ;#541A: 28 1A
        ld      c,a                                            ;#541C: 4F
INIT_STAGE_ROCK_DIST_LOOP:
        ; Check distance from each existing ROCK_TABLE entry (>=7 cells away)
        inc     hl                                             ;#541D: 23
        ld      a,(hl)                                         ;#541E: 7E
        inc     hl                                             ;#541F: 23
        sub     d                                              ;#5420: 92
        add     a,3                                            ;#5421: C6 03
        cp      7                                              ;#5423: FE 07
        jr      nc,INIT_STAGE_ROCK_NEXT                        ;#5425: 30 08
        ld      a,(hl)                                         ;#5427: 7E
        sub     e                                              ;#5428: 93
        add     a,3                                            ;#5429: C6 03
        cp      7                                              ;#542B: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#542D: 38 BD
INIT_STAGE_ROCK_NEXT:
        ; ROCK distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#542F: 7D
        add     a,0Eh                                          ;#5430: C6 0E
        ld      l,a                                            ;#5432: 6F
        dec     c                                              ;#5433: 0D
        jr      nz,INIT_STAGE_ROCK_DIST_LOOP                   ;#5434: 20 E7
INIT_STAGE_AFTER_ROCKS:
        ; After rock-dedup: check distance from existing FLAG_TABLE entries too
        ld      hl,FLAG_TABLE                                  ;#5436: 21 00 E1
        ld      a,0Ah                                          ;#5439: 3E 0A
        sub     b                                              ;#543B: 90
        jr      z,INIT_STAGE_PLACE_FLAG                        ;#543C: 28 1A
        ld      c,a                                            ;#543E: 4F
INIT_STAGE_FLAG_DIST_LOOP:
        ; Inner loop: compare candidate vs each placed flag in FLAG_TABLE
        inc     hl                                             ;#543F: 23
        ld      a,(hl)                                         ;#5440: 7E
        inc     hl                                             ;#5441: 23
        sub     d                                              ;#5442: 92
        add     a,3                                            ;#5443: C6 03
        cp      7                                              ;#5445: FE 07
        jr      nc,INIT_STAGE_FLAG_NEXT                        ;#5447: 30 08
        ld      a,(hl)                                         ;#5449: 7E
        sub     e                                              ;#544A: 93
        add     a,3                                            ;#544B: C6 03
        cp      7                                              ;#544D: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#544F: 38 9B
INIT_STAGE_FLAG_NEXT:
        ; FLAG distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#5451: 7D
        add     a,0Eh                                          ;#5452: C6 0E
        ld      l,a                                            ;#5454: 6F
        dec     c                                              ;#5455: 0D
        jr      nz,INIT_STAGE_FLAG_DIST_LOOP                   ;#5456: 20 E7
INIT_STAGE_PLACE_FLAG:
        ; All distance checks passed: write (X, Y) to flag entry and seed RADAR_GRID
        pop     hl                                             ;#5458: E1
        ld      (hl),d                                         ;#5459: 72
        inc     hl                                             ;#545A: 23
        ld      (hl),e                                         ;#545B: 73
        inc     hl                                             ;#545C: 23
        push    hl                                             ;#545D: E5
        ld      a,d                                            ;#545E: 7A
        and     3                                              ;#545F: E6 03
        ld      c,a                                            ;#5461: 4F
        ld      a,e                                            ;#5462: 7B
        add     a,a                                            ;#5463: 87
        add     a,a                                            ;#5464: 87
        or      c                                              ;#5465: B1
        and     0Fh                                            ;#5466: E6 0F
        or      0A0h                                           ;#5468: F6 A0
        ld      c,a                                            ;#546A: 4F
        ld      hl,RADAR_GRID                                  ;#546B: 21 00 EE
        ld      a,d                                            ;#546E: 7A
        rra                                                    ;#546F: 1F
        rra                                                    ;#5470: 1F
        and     7                                              ;#5471: E6 07
        add     a,l                                            ;#5473: 85
        ld      l,a                                            ;#5474: 6F
        ld      a,e                                            ;#5475: 7B
        add     a,a                                            ;#5476: 87
        and     78h                                            ;#5477: E6 78
        add     a,l                                            ;#5479: 85
        ld      l,a                                            ;#547A: 6F
        ld      (hl),c                                         ;#547B: 71
        set     7,l                                            ;#547C: CB FD
        ld      (RADAR_LAST_DOT_PTR),hl                        ;#547E: 22 A5 E0
        pop     hl                                             ;#5481: E1
        ld      a,l                                            ;#5482: 7D
        and     0F0h                                           ;#5483: E6 F0
        add     a,10h                                          ;#5485: C6 10
        ld      l,a                                            ;#5487: 6F
        dec     b                                              ;#5488: 05
        jp      nz,INIT_STAGE_FLAG_LOOP                        ;#5489: C2 E8 53
        ret                                                    ;#548C: C9

INIT_FLAGS:
        ; Initialize FLAG_TABLE: 10 flags (8 regular + 2 special) at stage start
        ; INIT_FLAGS places the 10 stage flags. Walks FLAG_TABLE (10 entries x 8 bytes),
        ; for each: writes the active flag (1), uses NEXT_RANDOM to pick X/Y inside the
        ; playfield bounds, sets sprite parameters. The last 2 entries (index 9, 8 — set
        ; first in the iteration since B counts down) get tile 38h/34h color 8 (red
        ; SPECIAL flags); the rest get tile 30h color 2 (regular yellow flags). 10 = 8
        ; yellow + 2 red.
        ld      hl,FLAG_TABLE                                  ;#548D: 21 00 E1
        ld      b,0Ah                                          ;#5490: 06 0A
INIT_FLAGS_LOOP_TOP:
        ; Outer djnz of INIT_FLAGS (10 flag entries)
        ld      a,(hl)                                         ;#5492: 7E
        and     a                                              ;#5493: A7
        jp      z,INIT_FLAGS_NEXT_ENTRY                        ;#5494: CA E6 54
        inc     hl                                             ;#5497: 23
        ld      d,(hl)                                         ;#5498: 56
        inc     hl                                             ;#5499: 23
        ld      e,(hl)                                         ;#549A: 5E
        inc     hl                                             ;#549B: 23
        push    hl                                             ;#549C: E5
        ld      h,0                                            ;#549D: 26 00
        ld      a,d                                            ;#549F: 7A
        sub     0Fh                                            ;#54A0: D6 0F
        jp      p,INIT_FLAGS_X_POS                             ;#54A2: F2 A6 54
        dec     h                                              ;#54A5: 25
INIT_FLAGS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended for negative side of screen
        ld      c,a                                            ;#54A6: 4F
        add     a,a                                            ;#54A7: 87
        add     a,c                                            ;#54A8: 81
        ld      l,a                                            ;#54A9: 6F
        add     hl,hl                                          ;#54AA: 29
        add     hl,hl                                          ;#54AB: 29
        add     hl,hl                                          ;#54AC: 29
        ld      a,e                                            ;#54AD: 7B
        ld      de,58h                                         ;#54AE: 11 58 00
        add     hl,de                                          ;#54B1: 19
        ex      de,hl                                          ;#54B2: EB
        pop     hl                                             ;#54B3: E1
        ld      (hl),e                                         ;#54B4: 73
        inc     hl                                             ;#54B5: 23
        ld      (hl),d                                         ;#54B6: 72
        inc     hl                                             ;#54B7: 23
        push    hl                                             ;#54B8: E5
        ld      h,0                                            ;#54B9: 26 00
        sub     32h                                            ;#54BB: D6 32
        jp      p,INIT_FLAGS_Y_POS                             ;#54BD: F2 C1 54
        dec     h                                              ;#54C0: 25
INIT_FLAGS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended for top half of screen
        ld      l,a                                            ;#54C1: 6F
        add     a,a                                            ;#54C2: 87
        add     a,l                                            ;#54C3: 85
        ld      l,a                                            ;#54C4: 6F
        add     hl,hl                                          ;#54C5: 29
        add     hl,hl                                          ;#54C6: 29
        add     hl,hl                                          ;#54C7: 29
        ld      de,6Fh                                         ;#54C8: 11 6F 00
        add     hl,de                                          ;#54CB: 19
        ex      de,hl                                          ;#54CC: EB
        pop     hl                                             ;#54CD: E1
        ld      (hl),e                                         ;#54CE: 73
        inc     hl                                             ;#54CF: 23
        ld      (hl),d                                         ;#54D0: 72
        inc     hl                                             ;#54D1: 23
        ld      a,38h                                          ;#54D2: 3E 38
        ld      e,8                                            ;#54D4: 1E 08
        ld      c,b                                            ;#54D6: 48
        dec     c                                              ;#54D7: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54D8: 28 09
        ld      a,34h                                          ;#54DA: 3E 34
        dec     c                                              ;#54DC: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54DD: 28 04
        ld      a,30h                                          ;#54DF: 3E 30
        ld      e,2                                            ;#54E1: 1E 02
INIT_FLAGS_STORE_TILE:
        ; Choose tile/color: last-2 entries get the 34h/38h red SPECIAL flags
        ld      (hl),a                                         ;#54E3: 77
        inc     hl                                             ;#54E4: 23
        ld      (hl),e                                         ;#54E5: 73
INIT_FLAGS_NEXT_ENTRY:
        ; Advance HL by 10h to next FLAG_TABLE entry, djnz back to top
        ld      a,l                                            ;#54E6: 7D
        and     0F0h                                           ;#54E7: E6 F0
        add     a,10h                                          ;#54E9: C6 10
        ld      l,a                                            ;#54EB: 6F
        djnz    INIT_FLAGS_LOOP_TOP                            ;#54EC: 10 A4
        ret                                                    ;#54EE: C9

NEXT_RANDOM:
        ; LCG+LFSR random byte generator; advances RNG_LCG and RNG_LFSR, returns byte in A
        ; NEXT_RANDOM is a hybrid: an 8-bit LCG (RNG_LCG: x' = 5x + 1) combined with a
        ; 16-bit xor-shift LFSR (RNG_LFSR, seeded to 55AAh if it ever hits 0). Returns
        ; RNG_LCG + (RNG_LFSR low byte) in A. Used by INIT_STAGE for flag placement,
        ; SCROLL_ROCKS for rock positions, and ITERATE_ENEMY_CARS for AI decisions.
        ld      a,(RNG_LCG)                                    ;#54EF: 3A 98 E0
        ld      c,a                                            ;#54F2: 4F
        add     a,a                                            ;#54F3: 87
        add     a,a                                            ;#54F4: 87
        add     a,c                                            ;#54F5: 81
        inc     a                                              ;#54F6: 3C
        ld      (RNG_LCG),a                                    ;#54F7: 32 98 E0
        ld      c,a                                            ;#54FA: 4F
        push    hl                                             ;#54FB: E5
        ld      hl,(RNG_LFSR)                                  ;#54FC: 2A 99 E0
        ld      a,h                                            ;#54FF: 7C
        or      l                                              ;#5500: B5
        jr      nz,RNG_LFSR_TICK                               ;#5501: 20 03
        ld      hl,55AAh                                       ;#5503: 21 AA 55
RNG_LFSR_TICK:
        ; LFSR step: A = H XOR L, shift, then xor bit 6 of XOR back into bit 0
        ld      a,h                                            ;#5506: 7C
        xor     l                                              ;#5507: AD
        add     a,a                                            ;#5508: 87
        add     a,a                                            ;#5509: 87
        adc     hl,hl                                          ;#550A: ED 6A
        ld      (RNG_LFSR),hl                                  ;#550C: 22 99 E0
        ld      a,l                                            ;#550F: 7D
        pop     hl                                             ;#5510: E1
        add     a,c                                            ;#5511: 81
        ret                                                    ;#5512: C9

SCROLL_FLAGS:
        ; Iterate FLAG_TABLE: apply world scroll, draw each flag sprite, detect collect
        ; SCROLL_FLAGS iterates the 10-entry FLAG_TABLE. For each active flag, it: (1)
        ; world-scrolls the entry's screen position, (2) checks player proximity, (3) on
        ; collect — calls ADD_SCORE, clears the flag's RADAR_GRID dot, decrements
        ; STAGE_DIFFICULTY (the remaining-flags counter); when that reaches 0, sets
        ; STAGE_CLEAR_FLAG. Draws non-collected flags as sprites at their screen
        ; position.
        ld      hl,FLAG_TABLE                                  ;#5513: 21 00 E1
        ld      b,0Ah                                          ;#5516: 06 0A
SCROLL_FLAGS_LOOP_TOP:
        ; Outer djnz of SCROLL_FLAGS (10 entries)
        ld      a,(hl)                                         ;#5518: 7E
        and     a                                              ;#5519: A7
        jp      z,SCROLL_FLAG_NEXT                             ;#551A: CA 80 55
        inc     hl                                             ;#551D: 23
        inc     hl                                             ;#551E: 23
        inc     hl                                             ;#551F: 23
        ld      e,(hl)                                         ;#5520: 5E
        inc     hl                                             ;#5521: 23
        ld      d,(hl)                                         ;#5522: 56
        push    hl                                             ;#5523: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#5524: 3A 96 E0
        ld      l,a                                            ;#5527: 6F
        ld      h,0                                            ;#5528: 26 00
        rla                                                    ;#552A: 17
        jr      nc,SCROLL_FLAG_APPLY_DX                        ;#552B: 30 01
        dec     h                                              ;#552D: 25
SCROLL_FLAG_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to flag X position
        add     hl,de                                          ;#552E: 19
        ex      de,hl                                          ;#552F: EB
        pop     hl                                             ;#5530: E1
        ld      (hl),d                                         ;#5531: 72
        dec     hl                                             ;#5532: 2B
        ld      (hl),e                                         ;#5533: 73
        inc     hl                                             ;#5534: 23
        inc     hl                                             ;#5535: 23
        push    bc                                             ;#5536: C5
        ld      c,(hl)                                         ;#5537: 4E
        inc     hl                                             ;#5538: 23
        ld      b,(hl)                                         ;#5539: 46
        push    hl                                             ;#553A: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#553B: 3A 97 E0
        ld      l,a                                            ;#553E: 6F
        ld      h,0                                            ;#553F: 26 00
        rla                                                    ;#5541: 17
        jr      nc,SCROLL_FLAG_APPLY_DY                        ;#5542: 30 01
        dec     h                                              ;#5544: 25
SCROLL_FLAG_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to flag Y position
        add     hl,bc                                          ;#5545: 09
        ld      b,h                                            ;#5546: 44
        ld      c,l                                            ;#5547: 4D
        pop     hl                                             ;#5548: E1
        ld      (hl),b                                         ;#5549: 70
        dec     hl                                             ;#554A: 2B
        ld      (hl),c                                         ;#554B: 71
        ld      a,b                                            ;#554C: 78
        or      d                                              ;#554D: B2
        jr      nz,SCROLL_FLAG_OFFSCREEN                       ;#554E: 20 39
        ld      a,e                                            ;#5550: 7B
        cp      0A9h                                           ;#5551: FE A9
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#5553: 30 34
        ld      a,c                                            ;#5555: 79
        cp      0E0h                                           ;#5556: FE E0
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#5558: 30 2F
        sub     18h                                            ;#555A: D6 18
        inc     hl                                             ;#555C: 23
        inc     hl                                             ;#555D: 23
        ld      d,(hl)                                         ;#555E: 56
        inc     hl                                             ;#555F: 23
        ld      c,(hl)                                         ;#5560: 4E
        push    hl                                             ;#5561: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5562: 2A 94 E0
        ld      (hl),a                                         ;#5565: 77
        inc     hl                                             ;#5566: 23
        ld      (hl),e                                         ;#5567: 73
        inc     hl                                             ;#5568: 23
        ld      (hl),d                                         ;#5569: 72
        inc     hl                                             ;#556A: 23
        ld      (hl),c                                         ;#556B: 71
        inc     hl                                             ;#556C: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#556D: 22 94 E0
        pop     hl                                             ;#5570: E1
        sub     4Bh                                            ;#5571: D6 4B
        cp      19h                                            ;#5573: FE 19
        jr      nc,SCROLL_FLAG_POPBC                           ;#5575: 30 08
        ld      a,e                                            ;#5577: 7B
        sub     4Ch                                            ;#5578: D6 4C
        cp      19h                                            ;#557A: FE 19
        jp      c,SCROLL_FLAG_COLLECT                          ;#557C: DA 96 55
SCROLL_FLAG_POPBC:
        ; After collect check: restore BC saved during the inner body
        pop     bc                                             ;#557F: C1
SCROLL_FLAG_NEXT:
        ; Skip-this-flag path: advance HL by 10h, djnz back to next entry
        ld      a,l                                            ;#5580: 7D
        and     0F0h                                           ;#5581: E6 F0
SCROLL_FLAG_ADV_PTR:
        ; Tail of the per-frame loop: shared HL advance code
        add     a,10h                                          ;#5583: C6 10
        ld      l,a                                            ;#5585: 6F
        djnz    SCROLL_FLAGS_LOOP_TOP                          ;#5586: 10 90
        ret                                                    ;#5588: C9

SCROLL_FLAG_OFFSCREEN:
        ; Off-screen path: deactivate the flag entry and continue
        pop     bc                                             ;#5589: C1
        ld      a,l                                            ;#558A: 7D
        and     0F0h                                           ;#558B: E6 F0
        ld      l,a                                            ;#558D: 6F
        ld      c,(hl)                                         ;#558E: 4E
        dec     c                                              ;#558F: 0D
        jr      z,SCROLL_FLAG_ADV_PTR                          ;#5590: 28 F1
        ld      (hl),0                                         ;#5592: 36 00
        jr      SCROLL_FLAG_ADV_PTR                            ;#5594: 18 ED

SCROLL_FLAG_COLLECT:
        ; Collect: trigger SFX_FLAG, dec STAGE_DIFFICULTY, set STAGE_CLEAR if last
        ld      a,1                                            ;#5596: 3E 01
        ld      (hl),a                                         ;#5598: 77
        dec     hl                                             ;#5599: 2B
        push    hl                                             ;#559A: E5
        ld      a,l                                            ;#559B: 7D
        and     0F0h                                           ;#559C: E6 F0
        ld      l,a                                            ;#559E: 6F
        ld      a,(hl)                                         ;#559F: 7E
        pop     hl                                             ;#55A0: E1
        dec     a                                              ;#55A1: 3D
        jp      nz,SCROLL_FLAG_POPBC                           ;#55A2: C2 7F 55
        inc     a                                              ;#55A5: 3C
        ld      (SOUND_STATE_FLAG),a                           ;#55A6: 32 40 E5
        ld      a,d                                            ;#55A9: 7A
        cp      34h                                            ;#55AA: FE 34
        jr      nz,SCROLL_FLAG_CHECK_SPECIAL                   ;#55AC: 20 07
        ld      a,1                                            ;#55AE: 3E 01
        ld      (PLAYER_DEAD_FLAG),a                           ;#55B0: 32 BB E0
        jr      SCROLL_FLAG_SCORE_TICK                         ;#55B3: 18 11

SCROLL_FLAG_CHECK_SPECIAL:
        ; Check whether this is a SPECIAL (red) flag for bonus scoring
        cp      38h                                            ;#55B5: FE 38
        jr      nz,SCROLL_FLAG_SCORE_TICK                      ;#55B7: 20 0D
        xor     a                                              ;#55B9: AF
        ld      (SOUND_STATE_FLAG),a                           ;#55BA: 32 40 E5
        inc     a                                              ;#55BD: 3C
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#55BE: 32 41 E5
        ld      a,1                                            ;#55C1: 3E 01
        ld      (MOVEMENT_SUB_PHASE),a                         ;#55C3: 32 AD E0
SCROLL_FLAG_SCORE_TICK:
        ; Award score chunk per-tick during the collect animation
        ld      a,(FRAME_TICK_SUB)                             ;#55C6: 3A AC E0
        inc     a                                              ;#55C9: 3C
        ld      (FRAME_TICK_SUB),a                             ;#55CA: 32 AC E0
        add     a,a                                            ;#55CD: 87
        add     a,a                                            ;#55CE: 87
        add     a,a                                            ;#55CF: 87
        add     a,78h                                          ;#55D0: C6 78
        ld      c,a                                            ;#55D2: 4F
        ld      a,(MOVEMENT_SUB_PHASE)                         ;#55D3: 3A AD E0
        and     a                                              ;#55D6: A7
        jr      z,SCROLL_FLAG_PHASE_SET                        ;#55D7: 28 04
        ld      a,c                                            ;#55D9: 79
        add     a,4                                            ;#55DA: C6 04
        ld      c,a                                            ;#55DC: 4F
SCROLL_FLAG_PHASE_SET:
        ; Phase-set: write target SAT cell color/tile for the score bubble
        ld      (hl),c                                         ;#55DD: 71
        push    hl                                             ;#55DE: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#55DF: 2A 94 E0
        dec     hl                                             ;#55E2: 2B
        ld      (hl),1                                         ;#55E3: 36 01
        dec     hl                                             ;#55E5: 2B
        ld      (hl),c                                         ;#55E6: 71
        pop     hl                                             ;#55E7: E1
        ld      a,l                                            ;#55E8: 7D
        and     0F0h                                           ;#55E9: E6 F0
        ld      l,a                                            ;#55EB: 6F
        ld      (hl),2                                         ;#55EC: 36 02
        ld      a,c                                            ;#55EE: 79
        rra                                                    ;#55EF: 1F
        rra                                                    ;#55F0: 1F
        and     1Fh                                            ;#55F1: E6 1F
        call    ADD_SCORE                                      ;#55F3: CD E6 67
        push    hl                                             ;#55F6: E5
        inc     hl                                             ;#55F7: 23
        ld      d,(hl)                                         ;#55F8: 56
        inc     hl                                             ;#55F9: 23
        ld      e,(hl)                                         ;#55FA: 5E
        ld      hl,RADAR_GRID                                  ;#55FB: 21 00 EE
        ld      a,d                                            ;#55FE: 7A
        rra                                                    ;#55FF: 1F
        rra                                                    ;#5600: 1F
        and     7                                              ;#5601: E6 07
        add     a,l                                            ;#5603: 85
        ld      l,a                                            ;#5604: 6F
        ld      a,e                                            ;#5605: 7B
        add     a,a                                            ;#5606: 87
        and     78h                                            ;#5607: E6 78
        add     a,l                                            ;#5609: 85
        ld      l,a                                            ;#560A: 6F
        ld      (hl),90h                                       ;#560B: 36 90
        pop     hl                                             ;#560D: E1
        ld      a,(STAGE_DIFFICULTY)                           ;#560E: 3A AE E0
        dec     a                                              ;#5611: 3D
        ld      (STAGE_DIFFICULTY),a                           ;#5612: 32 AE E0
        jp      nz,SCROLL_FLAG_NOT_LAST                        ;#5615: C2 1D 56
        ld      a,1                                            ;#5618: 3E 01
        ld      (STAGE_CLEAR_FLAG),a                           ;#561A: 32 AF E0
SCROLL_FLAG_NOT_LAST:
        ; Not the last flag: fall through to LBL_71D7 (update HUD count)
        call    LOAD_STAGE_DIFFICULTY_TIER                     ;#561D: CD D7 71
        jp      SCROLL_FLAG_POPBC                              ;#5620: C3 7F 55

SCROLL_ROCKS:
        ; Iterate ROCK_TABLE: world-scroll + sprite draw
        ; SCROLL_ROCKS uses ROCK_SPAWN_COUNT as the iteration count. Each entry is
        ; seeded with a random position from ROCK_POSITIONS_N (using NEXT_RANDOM as the
        ; index byte), then drawn as a rock sprite at its world-scrolled screen
        ; position. Rocks are static obstacles — no AI.
        ld      hl,ROCK_TABLE                                  ;#5623: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5626: 3A 9C E0
        and     a                                              ;#5629: A7
        ret     z                                              ;#562A: C8
        ld      b,a                                            ;#562B: 47
SCROLL_ROCKS_LOOP_TOP:
        ; Outer djnz of SCROLL_ROCKS
        ld      (hl),1                                         ;#562C: 36 01
        inc     hl                                             ;#562E: 23
        push    hl                                             ;#562F: E5
SCROLL_ROCKS_PICK_POSITION:
        ; Pick a random ROCK_POSITIONS_N index, jump out if dup vs other rocks
        call    NEXT_RANDOM                                    ;#5630: CD EF 54
        ld      hl,MAZE_BITMAP_0                               ;#5633: 21 00 7C
        add     a,a                                            ;#5636: 87
        or      0E0h                                           ;#5637: F6 E0
        ld      l,a                                            ;#5639: 6F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#563A: 3A B0 E0
        rra                                                    ;#563D: 1F
        rra                                                    ;#563E: 1F
        and     3                                              ;#563F: E6 03
        or      h                                              ;#5641: B4
        ld      h,a                                            ;#5642: 67
        ld      d,(hl)                                         ;#5643: 56
        inc     hl                                             ;#5644: 23
        ld      e,(hl)                                         ;#5645: 5E
        ld      hl,ROCK_TABLE                                  ;#5646: 21 00 E2
        ld      a,0Ch                                          ;#5649: 3E 0C
        sub     b                                              ;#564B: 90
        jr      z,SCROLL_ROCKS_STORE                           ;#564C: 28 12
        ld      c,a                                            ;#564E: 4F
SCROLL_ROCKS_DEDUP_LOOP:
        ; Dedup loop: check candidate vs each placed rock entry
        inc     hl                                             ;#564F: 23
        ld      a,(hl)                                         ;#5650: 7E
        inc     hl                                             ;#5651: 23
        cp      d                                              ;#5652: BA
        jr      nz,SCROLL_ROCKS_DEDUP_NEXT                     ;#5653: 20 04
        ld      a,(hl)                                         ;#5655: 7E
        cp      e                                              ;#5656: BB
        jr      z,SCROLL_ROCKS_PICK_POSITION                   ;#5657: 28 D7
SCROLL_ROCKS_DEDUP_NEXT:
        ; Dedup OK for this entry: advance pointer to next rock
        ld      a,l                                            ;#5659: 7D
        add     a,0Eh                                          ;#565A: C6 0E
        ld      l,a                                            ;#565C: 6F
        dec     c                                              ;#565D: 0D
        jr      nz,SCROLL_ROCKS_DEDUP_LOOP                     ;#565E: 20 EF
SCROLL_ROCKS_STORE:
        ; All checks passed: write rock (X, Y) into ROCK_TABLE
        pop     hl                                             ;#5660: E1
        ld      (hl),d                                         ;#5661: 72
        inc     hl                                             ;#5662: 23
        ld      (hl),e                                         ;#5663: 73
        ld      a,l                                            ;#5664: 7D
        and     0F0h                                           ;#5665: E6 F0
        add     a,10h                                          ;#5667: C6 10
        ld      l,a                                            ;#5669: 6F
        djnz    SCROLL_ROCKS_LOOP_TOP                          ;#566A: 10 C0
        ret                                                    ;#566C: C9

INIT_ROCKS:
        ; Initialize ROCK_TABLE at stage start
        ; INIT_ROCKS clears ROCK_TABLE and seeds it from MAZE_BITMAP_N at 7C00..7F00
        ; using random positions. ROCK_SPAWN_COUNT (ROCK_SPAWN_COUNT) controls the
        ; count. Called once per stage from INITIAL_STATE_HANDLER's tail.
        ld      hl,ROCK_TABLE                                  ;#566D: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5670: 3A 9C E0
        and     a                                              ;#5673: A7
        ret     z                                              ;#5674: C8
        ld      b,a                                            ;#5675: 47
INIT_ROCKS_LOOP_TOP:
        ; Outer djnz of INIT_ROCKS
        ld      a,(hl)                                         ;#5676: 7E
        and     a                                              ;#5677: A7
        jp      z,INIT_ROCKS_NEXT_ENTRY                        ;#5678: CA BB 56
        inc     hl                                             ;#567B: 23
        ld      d,(hl)                                         ;#567C: 56
        inc     hl                                             ;#567D: 23
        ld      e,(hl)                                         ;#567E: 5E
        inc     hl                                             ;#567F: 23
        push    hl                                             ;#5680: E5
        ld      h,0                                            ;#5681: 26 00
        ld      a,d                                            ;#5683: 7A
        sub     0Fh                                            ;#5684: D6 0F
        jp      p,INIT_ROCKS_X_POS                             ;#5686: F2 8A 56
        dec     h                                              ;#5689: 25
INIT_ROCKS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended
        ld      c,a                                            ;#568A: 4F
        add     a,a                                            ;#568B: 87
        add     a,c                                            ;#568C: 81
        ld      l,a                                            ;#568D: 6F
        add     hl,hl                                          ;#568E: 29
        add     hl,hl                                          ;#568F: 29
        add     hl,hl                                          ;#5690: 29
        ld      a,e                                            ;#5691: 7B
        ld      de,58h                                         ;#5692: 11 58 00
        add     hl,de                                          ;#5695: 19
        ex      de,hl                                          ;#5696: EB
        pop     hl                                             ;#5697: E1
        ld      (hl),e                                         ;#5698: 73
        inc     hl                                             ;#5699: 23
        ld      (hl),d                                         ;#569A: 72
        inc     hl                                             ;#569B: 23
        push    hl                                             ;#569C: E5
        ld      h,0                                            ;#569D: 26 00
        sub     32h                                            ;#569F: D6 32
        jp      p,INIT_ROCKS_Y_POS                             ;#56A1: F2 A5 56
        dec     h                                              ;#56A4: 25
INIT_ROCKS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended
        ld      l,a                                            ;#56A5: 6F
        add     a,a                                            ;#56A6: 87
        add     a,l                                            ;#56A7: 85
        ld      l,a                                            ;#56A8: 6F
        add     hl,hl                                          ;#56A9: 29
        add     hl,hl                                          ;#56AA: 29
        add     hl,hl                                          ;#56AB: 29
        ld      de,6Fh                                         ;#56AC: 11 6F 00
        add     hl,de                                          ;#56AF: 19
        ex      de,hl                                          ;#56B0: EB
        pop     hl                                             ;#56B1: E1
        ld      (hl),e                                         ;#56B2: 73
        inc     hl                                             ;#56B3: 23
        ld      (hl),d                                         ;#56B4: 72
        inc     hl                                             ;#56B5: 23
        ld      (hl),3Ch                                       ;#56B6: 36 3C
        inc     hl                                             ;#56B8: 23
        ld      (hl),6                                         ;#56B9: 36 06
INIT_ROCKS_NEXT_ENTRY:
        ; Advance HL by 10h to next ROCK_TABLE entry, djnz back to top
        ld      a,l                                            ;#56BB: 7D
        and     0F0h                                           ;#56BC: E6 F0
        add     a,10h                                          ;#56BE: C6 10
        ld      l,a                                            ;#56C0: 6F
        djnz    INIT_ROCKS_LOOP_TOP                            ;#56C1: 10 B3
        ret                                                    ;#56C3: C9

UPDATE_ROCKS_COLLISION:
        ; Second pass over ROCK_TABLE (different update phase)
        ; UPDATE_ROCKS_COLLISION is the second iteration over ROCK_TABLE per frame,
        ; performing the "did the player hit a rock" detection. Different from
        ; SCROLL_ROCKS which renders sprites — PASS2 is collision logic.
        ld      hl,ROCK_TABLE                                  ;#56C4: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#56C7: 3A 9C E0
        and     a                                              ;#56CA: A7
        ret     z                                              ;#56CB: C8
        ld      b,a                                            ;#56CC: 47
UPDATE_ROCKS_COLLISION_LOOP_TOP:
        ; Outer djnz of UPDATE_ROCKS_COLLISION
        inc     hl                                             ;#56CD: 23
        inc     hl                                             ;#56CE: 23
        inc     hl                                             ;#56CF: 23
        ld      e,(hl)                                         ;#56D0: 5E
        inc     hl                                             ;#56D1: 23
        ld      d,(hl)                                         ;#56D2: 56
        push    hl                                             ;#56D3: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#56D4: 3A 96 E0
        ld      l,a                                            ;#56D7: 6F
        ld      h,0                                            ;#56D8: 26 00
        rla                                                    ;#56DA: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DX             ;#56DB: 30 01
        dec     h                                              ;#56DD: 25
UPDATE_ROCKS_COLLISION_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to rock X position
        add     hl,de                                          ;#56DE: 19
        ex      de,hl                                          ;#56DF: EB
        pop     hl                                             ;#56E0: E1
        ld      (hl),d                                         ;#56E1: 72
        dec     hl                                             ;#56E2: 2B
        ld      (hl),e                                         ;#56E3: 73
        inc     hl                                             ;#56E4: 23
        inc     hl                                             ;#56E5: 23
        push    bc                                             ;#56E6: C5
        ld      c,(hl)                                         ;#56E7: 4E
        inc     hl                                             ;#56E8: 23
        ld      b,(hl)                                         ;#56E9: 46
        push    hl                                             ;#56EA: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#56EB: 3A 97 E0
        ld      l,a                                            ;#56EE: 6F
        ld      h,0                                            ;#56EF: 26 00
        rla                                                    ;#56F1: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DY             ;#56F2: 30 01
        dec     h                                              ;#56F4: 25
UPDATE_ROCKS_COLLISION_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to rock Y position
        add     hl,bc                                          ;#56F5: 09
        ld      b,h                                            ;#56F6: 44
        ld      c,l                                            ;#56F7: 4D
        pop     hl                                             ;#56F8: E1
        ld      (hl),b                                         ;#56F9: 70
        dec     hl                                             ;#56FA: 2B
        ld      (hl),c                                         ;#56FB: 71
        ld      a,b                                            ;#56FC: 78
        or      d                                              ;#56FD: B2
        jr      nz,UPDATE_ROCKS_COLLISION_NEXT                 ;#56FE: 20 33
        ld      a,e                                            ;#5700: 7B
        cp      0A9h                                           ;#5701: FE A9
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#5703: 30 2E
        ld      a,c                                            ;#5705: 79
        cp      0E0h                                           ;#5706: FE E0
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#5708: 30 29
        sub     18h                                            ;#570A: D6 18
        inc     hl                                             ;#570C: 23
        inc     hl                                             ;#570D: 23
        ld      d,(hl)                                         ;#570E: 56
        inc     hl                                             ;#570F: 23
        ld      c,(hl)                                         ;#5710: 4E
        push    hl                                             ;#5711: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5712: 2A 94 E0
        ld      (hl),a                                         ;#5715: 77
        inc     hl                                             ;#5716: 23
        ld      (hl),e                                         ;#5717: 73
        inc     hl                                             ;#5718: 23
        ld      (hl),d                                         ;#5719: 72
        inc     hl                                             ;#571A: 23
        ld      (hl),c                                         ;#571B: 71
        inc     hl                                             ;#571C: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#571D: 22 94 E0
        sub     4Fh                                            ;#5720: D6 4F
        cp      11h                                            ;#5722: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#5724: 30 0C
        ld      a,e                                            ;#5726: 7B
        sub     50h                                            ;#5727: D6 50
        cp      11h                                            ;#5729: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#572B: 30 05
        ld      a,1                                            ;#572D: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#572F: 32 C9 E0
UPDATE_ROCKS_COLLISION_DEATH:
        ; Player-on-rock collision: set GAME_OVER_FLAG=1
        pop     hl                                             ;#5732: E1
UPDATE_ROCKS_COLLISION_NEXT:
        ; Skip-this-rock: advance HL by 10h, djnz back
        pop     bc                                             ;#5733: C1
        ld      a,l                                            ;#5734: 7D
        and     0F0h                                           ;#5735: E6 F0
        add     a,10h                                          ;#5737: C6 10
        ld      l,a                                            ;#5739: 6F
        djnz    UPDATE_ROCKS_COLLISION_LOOP_TOP                ;#573A: 10 91
        ret                                                    ;#573C: C9

ADD_DE_TO_ENEMY_X:
        ; Add DE (sign-extended) to ENEMY_OFFSET_X (9..0Ah) of all 7 enemies
        ; ADD_DE_TO_ENEMY_X iterates 7 ENEMY_CAR_TABLE entries (skipping E300+0=type).
        ; For each entry, adds DE (sign-extended via rla) to ENEMY_OFFSET_X (screen X,
        ; 9..0Ah). Applies the world-scroll delta to every enemy's screen X when the
        ; player moves.
        exx                                                    ;#573D: D9
        ld      e,a                                            ;#573E: 5F
        ld      d,0                                            ;#573F: 16 00
        rla                                                    ;#5741: 17
        jr      nc,ADD_DE_ENEMY_X_INIT                         ;#5742: 30 01
        dec     d                                              ;#5744: 15
ADD_DE_ENEMY_X_INIT:
        ; ADD_DE_TO_ENEMY_X init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#5745: DD 21 00 E3
        ld      bc,10h                                         ;#5749: 01 10 00
        ld      a,7                                            ;#574C: 3E 07
ADD_DE_ENEMY_X_LOOP:
        ; Per-enemy djnz body: load (ix+9..0Ah), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#574E: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5751: DD 6E 09
        add     hl,de                                          ;#5754: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5755: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#5758: DD 75 09
        add     ix,bc                                          ;#575B: DD 09
        dec     a                                              ;#575D: 3D
        jr      nz,ADD_DE_ENEMY_X_LOOP                         ;#575E: 20 EE
        ld      a,e                                            ;#5760: 7B
        exx                                                    ;#5761: D9
        ret                                                    ;#5762: C9

ADD_DE_TO_ENEMY_Y:
        ; Add DE (sign-extended) to ENEMY_OFFSET_Y (0Bh..0Ch) of all 7 enemies
        ; ADD_DE_TO_ENEMY_Y is the same shape for ENEMY_OFFSET_Y (screen Y, 0Bh..0Ch).
        ; Together they scroll all enemies' screen X/Y with the world.
        exx                                                    ;#5763: D9
        ld      e,a                                            ;#5764: 5F
        ld      d,0                                            ;#5765: 16 00
        rla                                                    ;#5767: 17
        jr      nc,ADD_DE_ENEMY_Y_INIT                         ;#5768: 30 01
        dec     d                                              ;#576A: 15
ADD_DE_ENEMY_Y_INIT:
        ; ADD_DE_TO_ENEMY_Y init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#576B: DD 21 00 E3
        ld      bc,10h                                         ;#576F: 01 10 00
        ld      a,7                                            ;#5772: 3E 07
ADD_DE_ENEMY_Y_LOOP:
        ; Per-enemy djnz body: load (ix+0Bh..0Ch), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5774: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5777: DD 6E 0B
        add     hl,de                                          ;#577A: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#577B: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#577E: DD 75 0B
        add     ix,bc                                          ;#5781: DD 09
        dec     a                                              ;#5783: 3D
        jr      nz,ADD_DE_ENEMY_Y_LOOP                         ;#5784: 20 EE
        ld      a,e                                            ;#5786: 7B
        exx                                                    ;#5787: D9
        ret                                                    ;#5788: C9

ITERATE_ENEMY_CARS:
        ; Dec ENEMY_CAR_ITER_TIMER, then call UPDATE_ENEMY_CAR_ENTRY 6x (AI every frame)
        ; ITERATE_ENEMY_CARS decrements ENEMY_CAR_ITER_TIMER toward 0 each frame, then
        ; unconditionally calls UPDATE_ENEMY_CAR_ENTRY 6 times — the AI runs every frame
        ; regardless of the timer. The timer is a start-of-stage grace period: while it
        ; is non-zero an enemy touching the player does not set GAME_OVER_FLAG (checked
        ; at 5A7Eh).
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#5789: 3A 9D E0
        and     a                                              ;#578C: A7
        jr      z,ITER_ENEMY_KICK_AI                           ;#578D: 28 04
        dec     a                                              ;#578F: 3D
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#5790: 32 9D E0
ITER_ENEMY_KICK_AI:
        ; After timer dec: call UPDATE_ENEMY_CAR_ENTRY 6 times in a row
        ld      ix,ENEMY_CAR_TABLE                             ;#5793: DD 21 00 E3
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5797: CD A9 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#579A: CD A9 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#579D: CD A9 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#57A0: CD A9 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#57A3: CD A9 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#57A6: CD A9 57
UPDATE_ENEMY_CAR_ENTRY:
        ; Update ENEMY_CAR_TABLE entry; branch on (ix+0) type, reads PLAYER_MOVE_GATE
        ; UPDATE_ENEMY_CAR_ENTRY runs each enemy car's AI per tick. Reads (ix+0) type;
        ; if 2 (special "hit player" state), branches to DRAW_ENEMY_CAR_SPRITE.
        ; Otherwise (PLAYER_MOVE_GATE clear and ENEMY_STEP_SPEED non-zero) chases the
        ; player: rock/smoke bounce via CHECK_ENEMY_HITS_ROCK, then a direction pick
        ; toward PLAYER_SCREEN_X/Y using APPLY_DIRECTION_TO_POS and the SCAN_PLAYFIELD_*
        ; helpers, moving at ENEMY_STEP_SPEED. See ENEMY_AI.md.
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#57A9: DD 7E 00
        and     a                                              ;#57AC: A7
        ret     z                                              ;#57AD: C8
        cp      2                                              ;#57AE: FE 02
        jp      z,ENEMY_HIT_PHASE                              ;#57B0: CA 1B 5A
        ld      a,(PLAYER_MOVE_GATE)                           ;#57B3: 3A C5 E0
        and     a                                              ;#57B6: A7
        jr      nz,ENEMY_AI_RUN_TICK                           ;#57B7: 20 08
        ld      hl,(ENEMY_STEP_SPEED)                          ;#57B9: 2A C1 E0
        ld      a,h                                            ;#57BC: 7C
        or      l                                              ;#57BD: B5
        jp      z,DRAW_ENEMY_CAR_SPRITE                        ;#57BE: CA 3C 5A
ENEMY_AI_RUN_TICK:
        ; Run AI for this enemy: rock collision, AI tick countdown, target chase
        call    CHECK_ENEMY_HITS_ROCK                          ;#57C1: CD 84 5B
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#57C4: DD 7E 01
        dec     (ix+ENEMY_OFFSET_TIMER)                        ;#57C7: DD 35 01
        cp      6                                              ;#57CA: FE 06
        jp      nc,DRAW_ENEMY_CAR_SPRITE                       ;#57CC: D2 3C 5A
        and     a                                              ;#57CF: A7
        jr      nz,ENEMY_BOUNCE_DELAY                          ;#57D0: 20 03
        inc     (ix+ENEMY_OFFSET_TIMER)                        ;#57D2: DD 34 01
ENEMY_BOUNCE_DELAY:
        ; Bounce-delay over: re-evaluate target direction
        ld      a,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#57D5: DD 7E 04
        sub     0Ah                                            ;#57D8: D6 0A
        cp      5                                              ;#57DA: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57DC: D2 8A 58
        ld      a,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#57DF: DD 7E 07
        sub     0Ah                                            ;#57E2: D6 0A
        cp      5                                              ;#57E4: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57E6: D2 8A 58
        dec     (ix+ENEMY_OFFSET_STATE)                        ;#57E9: DD 35 02
        jp      nz,ENEMY_RETRY_DIRS                            ;#57EC: C2 5E 58
        ld      (ix+ENEMY_OFFSET_STATE),2                      ;#57EF: DD 36 02 02
        ld      a,(PLAYER_SCREEN_Y)                            ;#57F3: 3A A4 E0
        sub     (ix+ENEMY_OFFSET_CELL_Y)                       ;#57F6: DD 96 08
        ld      h,a                                            ;#57F9: 67
        jr      nc,ENEMY_ABS_DY                                ;#57FA: 30 02
        neg                                                    ;#57FC: ED 44
ENEMY_ABS_DY:
        ; |target_y - my_y| - jr nc skips neg, branch falls into ABS_DY
        ld      l,a                                            ;#57FE: 6F
        ld      a,(PLAYER_SCREEN_X)                            ;#57FF: 3A A3 E0
        sub     (ix+ENEMY_OFFSET_CELL_X)                       ;#5802: DD 96 05
        ld      d,a                                            ;#5805: 57
        jr      nc,ENEMY_ABS_DX                                ;#5806: 30 02
        neg                                                    ;#5808: ED 44
ENEMY_ABS_DX:
        ; |target_x - my_x| - jr nc skips neg, branch falls into ABS_DX
        cp      l                                              ;#580A: BD
        jp      nc,ENEMY_PREFER_HORIZ                          ;#580B: D2 37 58
        xor     a                                              ;#580E: AF
        bit     7,h                                            ;#580F: CB 7C
        jr      nz,ENEMY_STORE_DIR_VERT                        ;#5811: 20 02
        ld      a,2                                            ;#5813: 3E 02
ENEMY_STORE_DIR_VERT:
        ; Vertical preferred: store dir 0 or 2 based on sign(dy) into c
        ld      c,a                                            ;#5815: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#5816: DD 96 0F
        and     3                                              ;#5819: E6 03
        cp      2                                              ;#581B: FE 02
        ld      a,c                                            ;#581D: 79
        jr      z,ENEMY_ROTATE_HORIZ                           ;#581E: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#5820: CD E4 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5823: D2 7C 58
ENEMY_ROTATE_HORIZ:
        ; Rotate to horizontal: fall back to horiz when vertical fails APPLY_DIR
        ld      a,1                                            ;#5826: 3E 01
        bit     7,d                                            ;#5828: CB 7A
        jr      z,ENEMY_FALLBACK_HORIZ                         ;#582A: 28 02
        ld      a,3                                            ;#582C: 3E 03
ENEMY_FALLBACK_HORIZ:
        ; Horizontal fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#582E: CD E4 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5831: D2 7C 58
        jp      ENEMY_RETRY_DIRS                               ;#5834: C3 5E 58

ENEMY_PREFER_HORIZ:
        ; Horizontal preferred: store dir 1 or 3 based on sign(dx) into c
        ld      a,1                                            ;#5837: 3E 01
        ld      e,h                                            ;#5839: 5C
        bit     7,d                                            ;#583A: CB 7A
        jr      z,ENEMY_STORE_DIR_HORIZ                        ;#583C: 28 02
        ld      a,3                                            ;#583E: 3E 03
ENEMY_STORE_DIR_HORIZ:
        ; Horizontal store: keep direction in c, try APPLY_DIRECTION_TO_POS
        ld      c,a                                            ;#5840: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#5841: DD 96 0F
        and     3                                              ;#5844: E6 03
        cp      2                                              ;#5846: FE 02
        ld      a,c                                            ;#5848: 79
        jr      z,ENEMY_ROTATE_VERT                            ;#5849: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#584B: CD E4 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#584E: D2 7C 58
ENEMY_ROTATE_VERT:
        ; Rotate to vertical: fall back to vertical when horiz fails APPLY_DIR
        xor     a                                              ;#5851: AF
        bit     7,e                                            ;#5852: CB 7B
        jr      nz,ENEMY_FALLBACK_VERT                         ;#5854: 20 02
        ld      a,2                                            ;#5856: 3E 02
ENEMY_FALLBACK_VERT:
        ; Vertical fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#5858: CD E4 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#585B: D2 7C 58
ENEMY_RETRY_DIRS:
        ; Retry directions: cycle through 4 directions looking for an unblocked one
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#585E: DD 7E 0F
        call    APPLY_DIRECTION_TO_POS                         ;#5861: CD E4 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#5864: 30 0E
        inc     a                                              ;#5866: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#5867: CD E4 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#586A: 30 08
        inc     a                                              ;#586C: 3C
        inc     a                                              ;#586D: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#586E: CD E4 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#5871: 30 01
        dec     a                                              ;#5873: 3D
ENEMY_PICK_DIR_OK:
        ; Direction picked: mask to 2 bits and store as (ix+0Fh)
        and     3                                              ;#5874: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5876: DD 77 0F
        jp      ENEMY_DISPATCH_DIR                             ;#5879: C3 8D 58

ENEMY_REVERSE_GUARD:
        ; Reverse-guard: don't flip 180 degrees on consecutive ticks
        and     3                                              ;#587C: E6 03
        ld      c,a                                            ;#587E: 4F
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#587F: DD 7E 0F
        xor     2                                              ;#5882: EE 02
        cp      c                                              ;#5884: B9
        jr      z,ENEMY_RETRY_DIRS                             ;#5885: 28 D7
        ld      (ix+ENEMY_OFFSET_DIR),c                        ;#5887: DD 71 0F
ENEMY_READ_DIR:
        ; Read (ix+0Fh) as current AI direction byte
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#588A: DD 7E 0F
ENEMY_DISPATCH_DIR:
        ; Dispatch on direction bits: 0/1/2/3 -> DIR0/DIR1/DIR2/DIR3 paths
        rra                                                    ;#588D: 1F
        jp      nc,ENEMY_DIR2_RUN                              ;#588E: D2 56 59
        rra                                                    ;#5891: 1F
        jr      nc,ENEMY_DIR1_RUN                              ;#5892: 30 62
        ld      a,0Ch                                          ;#5894: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#5896: DD 96 07
        jr      z,ENEMY_DIR2_DONE                              ;#5899: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#589B: DD 36 07 0C
        ld      e,a                                            ;#589F: 5F
        ld      d,0                                            ;#58A0: 16 00
        jr      nc,ENEMY_DIR2_ADD                              ;#58A2: 30 01
        dec     d                                              ;#58A4: 15
ENEMY_DIR2_ADD:
        ; DIR2 (right) inner: add velocity to (ix+0Bh..0Ch) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#58A5: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#58A8: DD 6E 0B
        add     hl,de                                          ;#58AB: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#58AC: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#58AF: DD 75 0B
ENEMY_DIR2_DONE:
        ; DIR2 done: update target_pos and shape change
        ld      de,(ENEMY_STEP_SPEED)                          ;#58B2: ED 5B C1 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#58B6: 3A C5 E0
        and     a                                              ;#58B9: A7
        jr      z,ENEMY_DIR0_RUN                               ;#58BA: 28 03
        ld      de,300h                                        ;#58BC: 11 00 03
ENEMY_DIR0_RUN:
        ; DIR0 (up) main: write velocity to (ix+4) and propagate
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#58BF: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#58C2: DD 6E 03
        and     a                                              ;#58C5: A7
        ld      a,h                                            ;#58C6: 7C
        sbc     hl,de                                          ;#58C7: ED 52
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#58C9: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#58CC: DD 75 03
        sub     h                                              ;#58CF: 94
        neg                                                    ;#58D0: ED 44
        ld      e,a                                            ;#58D2: 5F
        ld      d,0                                            ;#58D3: 16 00
        rla                                                    ;#58D5: 17
        jr      nc,ENEMY_DIR0_BORROW_CHECK                     ;#58D6: 30 01
        dec     d                                              ;#58D8: 15
ENEMY_DIR0_BORROW_CHECK:
        ; DIR0 borrow check: if (ix+4) overflowed negative, fix +18h and dec (ix+5)
        bit     7,h                                            ;#58D9: CB 7C
        jr      z,ENEMY_DIR0_STORE_POS                         ;#58DB: 28 09
        ld      a,h                                            ;#58DD: 7C
        add     a,18h                                          ;#58DE: C6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#58E0: DD 77 04
        dec     (ix+ENEMY_OFFSET_CELL_X)                       ;#58E3: DD 35 05
ENEMY_DIR0_STORE_POS:
        ; DIR0 store: write updated world X (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#58E6: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#58E9: DD 6E 09
        add     hl,de                                          ;#58EC: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#58ED: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#58F0: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#58F3: C3 3C 5A

ENEMY_DIR1_RUN:
        ; DIR1 (right) main: write velocity to (ix+7) and propagate to world Y
        ld      a,0Ch                                          ;#58F6: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#58F8: DD 96 07
        jr      z,ENEMY_DIR1_PHASE2                            ;#58FB: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#58FD: DD 36 07 0C
        ld      e,a                                            ;#5901: 5F
        ld      d,0                                            ;#5902: 16 00
        jr      nc,ENEMY_DIR1_ADD                              ;#5904: 30 01
        dec     d                                              ;#5906: 15
ENEMY_DIR1_ADD:
        ; DIR1 add: adjust position by delta and store new (ix+0Bh..0Ch)
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5907: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#590A: DD 6E 0B
        add     hl,de                                          ;#590D: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#590E: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5911: DD 75 0B
ENEMY_DIR1_PHASE2:
        ; DIR1 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#5914: ED 5B C1 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#5918: 3A C5 E0
        and     a                                              ;#591B: A7
        jr      z,ENEMY_DIR1_APPLY                             ;#591C: 28 03
        ld      de,300h                                        ;#591E: 11 00 03
ENEMY_DIR1_APPLY:
        ; DIR1 apply: add target step into (ix+3..+4) world X
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#5921: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#5924: DD 6E 03
        ld      a,h                                            ;#5927: 7C
        add     hl,de                                          ;#5928: 19
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#5929: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#592C: DD 75 03
        sub     h                                              ;#592F: 94
        neg                                                    ;#5930: ED 44
        ld      e,a                                            ;#5932: 5F
        ld      d,0                                            ;#5933: 16 00
        rla                                                    ;#5935: 17
        jr      nc,ENEMY_DIR1_CARRY_CHECK                      ;#5936: 30 01
        dec     d                                              ;#5938: 15
ENEMY_DIR1_CARRY_CHECK:
        ; DIR1 carry check: if (ix+4) >= 18h, fix -18h and inc (ix+5)
        ld      a,h                                            ;#5939: 7C
        cp      18h                                            ;#593A: FE 18
        jr      c,ENEMY_DIR1_STORE_POS                         ;#593C: 38 08
        sub     18h                                            ;#593E: D6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#5940: DD 77 04
        inc     (ix+ENEMY_OFFSET_CELL_X)                       ;#5943: DD 34 05
ENEMY_DIR1_STORE_POS:
        ; DIR1 store: write updated world Y (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5946: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5949: DD 6E 09
        add     hl,de                                          ;#594C: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#594D: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5950: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5953: C3 3C 5A

ENEMY_DIR2_RUN:
        ; DIR2 (down) main: shift back from DIR0/1 paths into common
        rra                                                    ;#5956: 1F
        jr      c,ENEMY_DIR3_RUN                               ;#5957: 38 62
        ld      a,0Ch                                          ;#5959: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#595B: DD 96 04
        jr      z,ENEMY_DIR2_PHASE2                            ;#595E: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#5960: DD 36 04 0C
        ld      e,a                                            ;#5964: 5F
        ld      d,0                                            ;#5965: 16 00
        jr      nc,ENEMY_DIR2_ADD2                             ;#5967: 30 01
        dec     d                                              ;#5969: 15
ENEMY_DIR2_ADD2:
        ; DIR2 add 2: secondary add to (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#596A: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#596D: DD 6E 09
        add     hl,de                                          ;#5970: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5971: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#5974: DD 75 09
ENEMY_DIR2_PHASE2:
        ; DIR2 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#5977: ED 5B C1 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#597B: 3A C5 E0
        and     a                                              ;#597E: A7
        jr      z,ENEMY_DIR2_APPLY                             ;#597F: 28 03
        ld      de,300h                                        ;#5981: 11 00 03
ENEMY_DIR2_APPLY:
        ; DIR2 apply: subtract step from (ix+6..7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#5984: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#5987: DD 6E 06
        and     a                                              ;#598A: A7
        ld      a,h                                            ;#598B: 7C
        sbc     hl,de                                          ;#598C: ED 52
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#598E: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#5991: DD 75 06
        sub     h                                              ;#5994: 94
        neg                                                    ;#5995: ED 44
        ld      e,a                                            ;#5997: 5F
        ld      d,0                                            ;#5998: 16 00
        rla                                                    ;#599A: 17
        jr      nc,ENEMY_DIR2_BORROW_CHECK                     ;#599B: 30 01
        dec     d                                              ;#599D: 15
ENEMY_DIR2_BORROW_CHECK:
        ; DIR2 borrow check: if (ix+7) underflowed, fix +18h and dec (ix+8)
        bit     7,h                                            ;#599E: CB 7C
        jr      z,ENEMY_DIR2_STORE_POS                         ;#59A0: 28 09
        ld      a,h                                            ;#59A2: 7C
        add     a,18h                                          ;#59A3: C6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#59A5: DD 77 07
        dec     (ix+ENEMY_OFFSET_CELL_Y)                       ;#59A8: DD 35 08
ENEMY_DIR2_STORE_POS:
        ; DIR2 store: write updated world (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#59AB: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#59AE: DD 6E 0B
        add     hl,de                                          ;#59B1: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#59B2: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#59B5: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#59B8: C3 3C 5A

ENEMY_DIR3_RUN:
        ; DIR3 (left) main: write velocity to (ix+4) and propagate
        ld      a,0Ch                                          ;#59BB: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#59BD: DD 96 04
        jr      z,ENEMY_DIR3_PHASE2                            ;#59C0: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#59C2: DD 36 04 0C
        ld      e,a                                            ;#59C6: 5F
        ld      d,0                                            ;#59C7: 16 00
        jr      nc,ENEMY_DIR3_ADD                              ;#59C9: 30 01
        dec     d                                              ;#59CB: 15
ENEMY_DIR3_ADD:
        ; DIR3 add: adjust position and store (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#59CC: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#59CF: DD 6E 09
        add     hl,de                                          ;#59D2: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#59D3: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#59D6: DD 75 09
ENEMY_DIR3_PHASE2:
        ; DIR3 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#59D9: ED 5B C1 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#59DD: 3A C5 E0
        and     a                                              ;#59E0: A7
        jr      z,ENEMY_DIR3_APPLY                             ;#59E1: 28 03
        ld      de,300h                                        ;#59E3: 11 00 03
ENEMY_DIR3_APPLY:
        ; DIR3 apply: add target step into (ix+6..+7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#59E6: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#59E9: DD 6E 06
        ld      a,h                                            ;#59EC: 7C
        add     hl,de                                          ;#59ED: 19
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#59EE: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#59F1: DD 75 06
        sub     h                                              ;#59F4: 94
        neg                                                    ;#59F5: ED 44
        ld      e,a                                            ;#59F7: 5F
        ld      d,0                                            ;#59F8: 16 00
        rla                                                    ;#59FA: 17
        jr      nc,ENEMY_DIR3_CARRY_CHECK                      ;#59FB: 30 01
        dec     d                                              ;#59FD: 15
ENEMY_DIR3_CARRY_CHECK:
        ; DIR3 carry check: if (ix+7) >= 18h, fix -18h and inc (ix+8)
        ld      a,h                                            ;#59FE: 7C
        cp      18h                                            ;#59FF: FE 18
        jr      c,ENEMY_DIR3_STORE_POS                         ;#5A01: 38 08
        sub     18h                                            ;#5A03: D6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#5A05: DD 77 07
        inc     (ix+ENEMY_OFFSET_CELL_Y)                       ;#5A08: DD 34 08
ENEMY_DIR3_STORE_POS:
        ; DIR3 store: write updated (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5A0B: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5A0E: DD 6E 0B
        add     hl,de                                          ;#5A11: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5A12: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5A15: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A18: C3 3C 5A

ENEMY_HIT_PHASE:
        ; Enemy hit state (type=2): tick the bounce-away animation phase
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5A1B: DD 7E 01
        dec     a                                              ;#5A1E: 3D
        jr      z,ENEMY_HIT_RESET                              ;#5A1F: 28 17
        ld      (ix+ENEMY_OFFSET_TIMER),a                      ;#5A21: DD 77 01
        and     1                                              ;#5A24: E6 01
        jr      nz,DRAW_ENEMY_CAR_SPRITE                       ;#5A26: 20 14
        ld      a,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A28: DD 7E 0D
        add     a,4                                            ;#5A2B: C6 04
        cp      30h                                            ;#5A2D: FE 30
        jr      c,ENEMY_HIT_STORE_ROT                          ;#5A2F: 38 01
        xor     a                                              ;#5A31: AF
ENEMY_HIT_STORE_ROT:
        ; Store updated bounce rotation back to (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5A32: DD 77 0D
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A35: C3 3C 5A

ENEMY_HIT_RESET:
        ; Bounce finished: re-activate enemy with type=1
        ld      (ix+ENEMY_OFFSET_TYPE),1                       ;#5A38: DD 36 00 01
DRAW_ENEMY_CAR_SPRITE:
        ; Bounds-check (ix+9..0Ch) entry position, write sprite to SAT_MIRROR
        ; DRAW_ENEMY_CAR_SPRITE validates enemy-car position then writes one sprite to
        ; SAT_MIRROR. Bounds: (ix+0Ah) and (ix+0Ch) must be 0 (high bytes of 16-bit
        ; X/Y), (ix+9) < 0A9h, (ix+0Bh) < 0E0h. Sprite Y = pos-Y - 18h (height offset).
        ld      a,(ix+ENEMY_OFFSET_X_HI)                       ;#5A3C: DD 7E 0A
        or      (ix+ENEMY_OFFSET_Y_HI)                         ;#5A3F: DD B6 0C
        jp      nz,ENEMY_AI_ADVANCE_IX                         ;#5A42: C2 09 5B
        ld      a,(ix+ENEMY_OFFSET_X)                          ;#5A45: DD 7E 09
        cp      0A9h                                           ;#5A48: FE A9
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A4A: D2 09 5B
        ld      d,a                                            ;#5A4D: 57
        ld      a,(ix+ENEMY_OFFSET_Y)                          ;#5A4E: DD 7E 0B
        ld      e,a                                            ;#5A51: 5F
        cp      0E0h                                           ;#5A52: FE E0
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A54: D2 09 5B
        ld      (ix+ENEMY_OFFSET_STATE),1                      ;#5A57: DD 36 02 01
        sub     18h                                            ;#5A5B: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5A5D: 2A 94 E0
        ld      (hl),a                                         ;#5A60: 77
        inc     hl                                             ;#5A61: 23
        ld      (hl),d                                         ;#5A62: 72
        inc     hl                                             ;#5A63: 23
        ld      c,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A64: DD 4E 0D
        ld      (hl),c                                         ;#5A67: 71
        inc     hl                                             ;#5A68: 23
        ld      b,(ix+ENEMY_OFFSET_COLOR)                      ;#5A69: DD 46 0E
        ld      (hl),b                                         ;#5A6C: 70
        inc     hl                                             ;#5A6D: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5A6E: 22 94 E0
        sub     4Fh                                            ;#5A71: D6 4F
        cp      11h                                            ;#5A73: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A75: 30 12
        ld      a,d                                            ;#5A77: 7A
        sub     50h                                            ;#5A78: D6 50
        cp      11h                                            ;#5A7A: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A7C: 30 0B
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#5A7E: 3A 9D E0
        and     a                                              ;#5A81: A7
        jr      nz,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A82: 20 05
        ld      a,1                                            ;#5A84: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#5A86: 32 C9 E0
DRAW_ENEMY_VS_SMOKE_LOOP:
        ; For each smoke trail entry: check overlap with this enemy car
        ex      de,hl                                          ;#5A89: EB
        ld      iy,SMOKE_TRAIL_TABLE                           ;#5A8A: FD 21 00 E4
        ld      b,9                                            ;#5A8E: 06 09
DRAW_ENEMY_SMOKE_INNER:
        ; Inner djnz of DRAW_ENEMY_VS_SMOKE_LOOP
        ld      a,(iy+SMOKE_OFFSET_ACTIVE)                     ;#5A90: FD 7E 00
        and     a                                              ;#5A93: A7
        jr      z,DRAW_ENEMY_SMOKE_NEXT                        ;#5A94: 28 31
        ld      a,(iy+SMOKE_OFFSET_X)                          ;#5A96: FD 7E 03
        sub     h                                              ;#5A99: 94
        add     a,4                                            ;#5A9A: C6 04
        cp      9                                              ;#5A9C: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5A9E: 30 27
        ld      a,(iy+SMOKE_OFFSET_Y)                          ;#5AA0: FD 7E 05
        sub     l                                              ;#5AA3: 95
        add     a,4                                            ;#5AA4: C6 04
        cp      9                                              ;#5AA6: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5AA8: 30 1D
        ld      (iy+SMOKE_OFFSET_ACTIVE),0                     ;#5AAA: FD 36 00 00
        ld      (ix+ENEMY_OFFSET_TYPE),2                       ;#5AAE: DD 36 00 02
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5AB2: DD 7E 0F
        add     a,2                                            ;#5AB5: C6 02
        and     3                                              ;#5AB7: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5AB9: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5ABC: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5AC0: DD 36 02 03
        jp      ENEMY_AI_TAIL_ADV                              ;#5AC4: C3 1E 5B

DRAW_ENEMY_SMOKE_NEXT:
        ; Advance IY to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5AC7: 11 10 00
        add     iy,de                                          ;#5ACA: FD 19
        djnz    DRAW_ENEMY_SMOKE_INNER                         ;#5ACC: 10 C2
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5ACE: DD 7E 00
        cp      2                                              ;#5AD1: FE 02
        jp      z,ENEMY_AI_TAIL_ADV                            ;#5AD3: CA 1E 5B
        ld      a,(FRAME_TICK)                                 ;#5AD6: 3A 87 E0
        rra                                                    ;#5AD9: 1F
        jr      nc,ENEMY_AI_ADVANCE_IX                         ;#5ADA: 30 2D
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5ADC: DD 7E 0F
        and     3                                              ;#5ADF: E6 03
        ld      b,a                                            ;#5AE1: 47
        add     a,a                                            ;#5AE2: 87
        add     a,b                                            ;#5AE3: 80
        add     a,a                                            ;#5AE4: 87
        add     a,a                                            ;#5AE5: 87
        sub     c                                              ;#5AE6: 91
        jr      z,ENEMY_AI_ADVANCE_IX                          ;#5AE7: 28 20
        jr      nc,ENEMY_SMOKE_ROT_TOP                         ;#5AE9: 30 02
        add     a,30h                                          ;#5AEB: C6 30
ENEMY_SMOKE_ROT_TOP:
        ; Compute rotation delta < 18h: pick MINUS or PLUS step
        cp      18h                                            ;#5AED: FE 18
        jr      c,ENEMY_SMOKE_ROT_PLUS                         ;#5AEF: 38 0D
        ld      a,c                                            ;#5AF1: 79
        sub     4                                              ;#5AF2: D6 04
        jr      nc,ENEMY_SMOKE_ROT_MINUS_STORE                 ;#5AF4: 30 02
        ld      a,2Ch                                          ;#5AF6: 3E 2C
ENEMY_SMOKE_ROT_MINUS_STORE:
        ; Rotate enemy sprite by -4 (mod 30h), clamp at 2Ch
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5AF8: DD 77 0D
        jp      ENEMY_AI_ADVANCE_IX                            ;#5AFB: C3 09 5B

ENEMY_SMOKE_ROT_PLUS:
        ; Rotate enemy sprite by +4 (mod 30h), wrap to 0
        ld      a,c                                            ;#5AFE: 79
        add     a,4                                            ;#5AFF: C6 04
        cp      30h                                            ;#5B01: FE 30
        jr      c,ENEMY_SMOKE_ROT_STORE                        ;#5B03: 38 01
        xor     a                                              ;#5B05: AF
ENEMY_SMOKE_ROT_STORE:
        ; Store new rotation phase at (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5B06: DD 77 0D
ENEMY_AI_ADVANCE_IX:
        ; Advance IX by 10h to next ENEMY_CAR_TABLE entry, return to caller
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5B09: DD 7E 01
        and     a                                              ;#5B0C: A7
        jr      nz,ENEMY_AI_TAIL_ADV                           ;#5B0D: 20 0F
        push    ix                                             ;#5B0F: DD E5
        pop     iy                                             ;#5B11: FD E1
ENEMY_COLLIDE_LOOP:
        ; Enemy-vs-enemy collision loop: walk subsequent entries via IY
        ld      de,10h                                         ;#5B13: 11 10 00
        add     iy,de                                          ;#5B16: FD 19
        ld      a,(iy+ENEMY_OFFSET_TYPE)                       ;#5B18: FD 7E 00
        and     a                                              ;#5B1B: A7
        jr      nz,ENEMY_COLLIDE_TEST_Y                        ;#5B1C: 20 06
ENEMY_AI_TAIL_ADV:
        ; Common tail: advance IX by 10h and return
        ld      de,10h                                         ;#5B1E: 11 10 00
        add     ix,de                                          ;#5B21: DD 19
        ret                                                    ;#5B23: C9

ENEMY_COLLIDE_TEST_Y:
        ; Test Y delta < 0Ch: rejected -> jump back to loop; accepted -> check X
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B24: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B27: DD 6E 09
        ld      d,(iy+ENEMY_OFFSET_X_HI)                       ;#5B2A: FD 56 0A
        ld      e,(iy+ENEMY_OFFSET_X)                          ;#5B2D: FD 5E 09
        and     a                                              ;#5B30: A7
        sbc     hl,de                                          ;#5B31: ED 52
        ld      de,0Ch                                         ;#5B33: 11 0C 00
        add     hl,de                                          ;#5B36: 19
        ld      a,h                                            ;#5B37: 7C
        and     a                                              ;#5B38: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B39: 20 D8
        ld      a,l                                            ;#5B3B: 7D
        cp      19h                                            ;#5B3C: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B3E: 30 D3
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5B40: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5B43: DD 6E 0B
        ld      d,(iy+ENEMY_OFFSET_Y_HI)                       ;#5B46: FD 56 0C
        ld      e,(iy+ENEMY_OFFSET_Y)                          ;#5B49: FD 5E 0B
        and     a                                              ;#5B4C: A7
        sbc     hl,de                                          ;#5B4D: ED 52
        ld      de,0Ch                                         ;#5B4F: 11 0C 00
        add     hl,de                                          ;#5B52: 19
        ld      a,h                                            ;#5B53: 7C
        and     a                                              ;#5B54: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B55: 20 BC
        ld      a,l                                            ;#5B57: 7D
        cp      19h                                            ;#5B58: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B5A: 30 B7
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5B5C: DD 7E 0F
        xor     2                                              ;#5B5F: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5B61: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5B64: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5B68: DD 36 02 03
        ld      a,(iy+ENEMY_OFFSET_DIR)                        ;#5B6C: FD 7E 0F
        xor     2                                              ;#5B6F: EE 02
        cp      (ix+ENEMY_OFFSET_DIR)                          ;#5B71: DD BE 0F
        jr      z,ENEMY_COLLIDE_STORE_OTHER                    ;#5B74: 28 03
        ld      (iy+ENEMY_OFFSET_DIR),a                        ;#5B76: FD 77 0F
ENEMY_COLLIDE_STORE_OTHER:
        ; Both cars collided: also set bounce-away flags on the other car
        ld      (iy+ENEMY_OFFSET_TIMER),78h                    ;#5B79: FD 36 01 78
        ld      (iy+ENEMY_OFFSET_STATE),3                      ;#5B7D: FD 36 02 03
        jp      ENEMY_COLLIDE_LOOP                             ;#5B81: C3 13 5B

CHECK_ENEMY_HITS_ROCK:
        ; AABB-style check (|dx|<0Ch & |dy|<0Ch) between IX (E300) and IY (E200)
        ; CHECK_ENEMY_HITS_ROCK does an AABB check between the current enemy car (IX =
        ; ENEMY_CAR_TABLE entry) and every ROCK_TABLE entry (IY). |dx| < 0Ch AND |dy| <
        ; 0Ch ⇒ hit; on hit, XOR bit 1 of (ix+0Fh) — a flag the enemy uses to reverse
        ; direction on its next AI tick.
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5B84: DD 7E 01
        and     a                                              ;#5B87: A7
        ret     nz                                             ;#5B88: C0
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5B89: 3A 9C E0
        and     a                                              ;#5B8C: A7
        ret     z                                              ;#5B8D: C8
        ld      b,a                                            ;#5B8E: 47
        ld      iy,ROCK_TABLE                                  ;#5B8F: FD 21 00 E2
CHECK_ROCK_LOOP_TOP:
        ; Outer djnz of CHECK_ENEMY_HITS_ROCK
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B93: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B96: DD 6E 09
        ld      d,(iy+ROCK_OFFSET_X_HI)                        ;#5B99: FD 56 04
        ld      e,(iy+ROCK_OFFSET_X)                           ;#5B9C: FD 5E 03
        and     a                                              ;#5B9F: A7
        sbc     hl,de                                          ;#5BA0: ED 52
        ld      de,0Ch                                         ;#5BA2: 11 0C 00
        add     hl,de                                          ;#5BA5: 19
        ld      a,h                                            ;#5BA6: 7C
        and     a                                              ;#5BA7: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5BA8: 20 32
        ld      a,l                                            ;#5BAA: 7D
        cp      19h                                            ;#5BAB: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BAD: 30 2D
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5BAF: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5BB2: DD 6E 0B
        ld      d,(iy+ROCK_OFFSET_Y_HI)                        ;#5BB5: FD 56 06
        ld      e,(iy+ROCK_OFFSET_Y)                           ;#5BB8: FD 5E 05
        and     a                                              ;#5BBB: A7
        sbc     hl,de                                          ;#5BBC: ED 52
        ld      de,0Ch                                         ;#5BBE: 11 0C 00
        add     hl,de                                          ;#5BC1: 19
        ld      a,h                                            ;#5BC2: 7C
        and     a                                              ;#5BC3: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5BC4: 20 16
        ld      a,l                                            ;#5BC6: 7D
        cp      19h                                            ;#5BC7: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BC9: 30 11
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5BCB: DD 7E 0F
        xor     2                                              ;#5BCE: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5BD0: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5BD3: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5BD7: DD 36 02 03
        ret                                                    ;#5BDB: C9

CHECK_ROCK_NEXT:
        ; Skip-this-rock: advance IY by 10h, djnz back to outer loop
        ld      de,10h                                         ;#5BDC: 11 10 00
        add     iy,de                                          ;#5BDF: FD 19
        djnz    CHECK_ROCK_LOOP_TOP                            ;#5BE1: 10 B0
        ret                                                    ;#5BE3: C9

APPLY_DIRECTION_TO_POS:
        ; Adjust H/L by direction A then call LOOKUP_PLAYFIELD_CELL
        ; APPLY_DIRECTION_TO_POS reads (ix+5, ix+8) as a 16-bit (H, L) position, adjusts
        ; by direction code in A: 0 = H-1 (up), 1 = H+1 (down), 2 = L-1 (left), 3 = L+1
        ; (right). Then calls LOOKUP_PLAYFIELD_CELL to fetch the cell at the new coord.
        ; Used by enemy and player movement code to "look ahead" before committing a
        ; move.
        ld      c,a                                            ;#5BE4: 4F
        ld      h,(ix+ENEMY_OFFSET_CELL_X)                     ;#5BE5: DD 66 05
        ld      l,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5BE8: DD 6E 08
        rra                                                    ;#5BEB: 1F
        jr      nc,APPLY_DIR_HORIZ                             ;#5BEC: 30 0B
        rra                                                    ;#5BEE: 1F
        jr      nc,APPLY_DIR_INC_H                             ;#5BEF: 30 04
        dec     h                                              ;#5BF1: 25
        jp      APPLY_DIR_LOOKUP                               ;#5BF2: C3 01 5C

APPLY_DIR_INC_H:
        ; APPLY_DIR direction 1 (down): inc H, then lookup
        inc     h                                              ;#5BF5: 24
        jp      APPLY_DIR_LOOKUP                               ;#5BF6: C3 01 5C

APPLY_DIR_HORIZ:
        ; APPLY_DIR horizontal (dir 2/3): switch on dir bit
        rra                                                    ;#5BF9: 1F
        jr      c,APPLY_DIR_INC_L                              ;#5BFA: 38 04
        dec     l                                              ;#5BFC: 2D
        jp      APPLY_DIR_LOOKUP                               ;#5BFD: C3 01 5C

APPLY_DIR_INC_L:
        ; APPLY_DIR direction 3 (right): inc L, then lookup
        inc     l                                              ;#5C00: 2C
APPLY_DIR_LOOKUP:
        ; Common lookup: call LOOKUP_PLAYFIELD_CELL with adjusted (H, L)
        call    LOOKUP_PLAYFIELD_CELL                          ;#5C01: CD 86 4B
        ld      a,c                                            ;#5C04: 79
        ret                                                    ;#5C05: C9

UPDATE_SMOKE_STATE:
        ; Per-frame smoke-state update; gated by SMOKE_COOLDOWN and PLAYER_VELOCITY_X
        ; UPDATE_SMOKE_STATE runs once per frame. No-op if SMOKE_COOLDOWN is zero.
        ; Otherwise reads PLAYER_VELOCITY_X for direction bits, then iterates
        ; SMOKE_TRAIL_TABLE; for each entry not too close to the player
        ; (PLAYER_VELOCITY_Y in safe range), updates state. Tail-falls into SPAWN_SMOKE
        ; which allocates the next smoke trail puff.
        ld      a,(SMOKE_COOLDOWN)                             ;#5C06: 3A A7 E0
        and     a                                              ;#5C09: A7
        ret     z                                              ;#5C0A: C8
        ld      a,(PLAYER_VELOCITY_X)                          ;#5C0B: 3A 89 E0
        and     a                                              ;#5C0E: A7
        jp      p,SMOKE_DIR_ABS                                ;#5C0F: F2 14 5C
        neg                                                    ;#5C12: ED 44
SMOKE_DIR_ABS:
        ; Take |PLAYER_VELOCITY_X| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C14: D6 0A
        cp      5                                              ;#5C16: FE 05
        ret     nc                                             ;#5C18: D0
        ld      a,(PLAYER_VELOCITY_Y)                          ;#5C19: 3A 8B E0
        and     a                                              ;#5C1C: A7
        jp      p,SMOKE_VEL_ABS                                ;#5C1D: F2 22 5C
        neg                                                    ;#5C20: ED 44
SMOKE_VEL_ABS:
        ; Take |PLAYER_VELOCITY_Y| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C22: D6 0A
        cp      5                                              ;#5C24: FE 05
        ret     nc                                             ;#5C26: D0
        ld      a,(PLAYER_SCREEN_X)                            ;#5C27: 3A A3 E0
        ld      d,a                                            ;#5C2A: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#5C2B: 3A A4 E0
        ld      e,a                                            ;#5C2E: 5F
        ; SPAWN_SMOKE (inside UPDATE_SMOKE_STATE's tail). Allocates the next
        ; SMOKE_TRAIL_TABLE entry: advance SMOKE_TRAIL_WRITE_PTR by 0x10, wrap
        ; SMOKE_TRAIL_WRITE_INDEX modulo 9. Initialize: active=1, pos=(D,E), tile=58h,
        ; attr=0, life=6Fh, etc. Decrement SMOKE_COOLDOWN and trigger SFX_TRIGGER_SMOKE
        ; (=1) for the deploy sound.
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C2F: 21 00 E4
        ld      b,9                                            ;#5C32: 06 09
SMOKE_SCAN_LOOP_TOP:
        ; Inner djnz of SPAWN_SMOKE (scan SMOKE_TRAIL_TABLE)
        ld      a,(hl)                                         ;#5C34: 7E
        and     a                                              ;#5C35: A7
        jr      z,SMOKE_SPAWN_NEXT                             ;#5C36: 28 12
        inc     hl                                             ;#5C38: 23
        inc     hl                                             ;#5C39: 23
        inc     hl                                             ;#5C3A: 23
        ld      a,(hl)                                         ;#5C3B: 7E
        sub     50h                                            ;#5C3C: D6 50
        cp      10h                                            ;#5C3E: FE 10
        jr      nc,SMOKE_SPAWN_NEXT                            ;#5C40: 30 08
        inc     hl                                             ;#5C42: 23
        inc     hl                                             ;#5C43: 23
        ld      a,(hl)                                         ;#5C44: 7E
        sub     67h                                            ;#5C45: D6 67
        cp      10h                                            ;#5C47: FE 10
        ret     c                                              ;#5C49: D8
SMOKE_SPAWN_NEXT:
        ; Try next smoke slot if current entry too close to player
        ld      a,l                                            ;#5C4A: 7D
        and     0F0h                                           ;#5C4B: E6 F0
        add     a,10h                                          ;#5C4D: C6 10
        ld      l,a                                            ;#5C4F: 6F
        djnz    SMOKE_SCAN_LOOP_TOP                            ;#5C50: 10 E2
        ld      hl,(SMOKE_TRAIL_WRITE_PTR)                     ;#5C52: 2A A8 E0
        ld      bc,10h                                         ;#5C55: 01 10 00
        add     hl,bc                                          ;#5C58: 09
        ld      a,(SMOKE_TRAIL_WRITE_INDEX)                    ;#5C59: 3A AA E0
        inc     a                                              ;#5C5C: 3C
        cp      9                                              ;#5C5D: FE 09
        jr      nz,SMOKE_ALLOC_ENTRY                           ;#5C5F: 20 04
        xor     a                                              ;#5C61: AF
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C62: 21 00 E4
SMOKE_ALLOC_ENTRY:
        ; Init new smoke entry: active=1, pos=(D,E), tile=58h, life=6Fh
        ld      (SMOKE_TRAIL_WRITE_PTR),hl                     ;#5C65: 22 A8 E0
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#5C68: 32 AA E0
        ld      (hl),1                                         ;#5C6B: 36 01
        inc     hl                                             ;#5C6D: 23
        ld      (hl),d                                         ;#5C6E: 72
        inc     hl                                             ;#5C6F: 23
        ld      (hl),e                                         ;#5C70: 73
        inc     hl                                             ;#5C71: 23
        ld      (hl),58h                                       ;#5C72: 36 58
        inc     hl                                             ;#5C74: 23
        ld      (hl),0                                         ;#5C75: 36 00
        inc     hl                                             ;#5C77: 23
        ld      (hl),6Fh                                       ;#5C78: 36 6F
        inc     hl                                             ;#5C7A: 23
        ld      (hl),0                                         ;#5C7B: 36 00
        ld      hl,SMOKE_COOLDOWN                              ;#5C7D: 21 A7 E0
        dec     (hl)                                           ;#5C80: 35
        ld      a,1                                            ;#5C81: 3E 01
        ld      (SFX_TRIGGER_SMOKE),a                          ;#5C83: 32 50 E5
        ret                                                    ;#5C86: C9

SCROLL_SMOKE_TRAILS:
        ; Iterate SMOKE_TRAIL_TABLE (9 entries x 16 bytes): world-scroll + draw
        ; SCROLL_SMOKE_TRAILS iterates the 9-entry SMOKE_TRAIL_TABLE. Active entries
        ; have their X/Y advanced by WORLD_SCROLL_DX/DY. When the position goes off-
        ; screen (X >= 0A9h or Y >= 0E0h), the entry is deactivated. In-bounds entries
        ; are drawn as smoke sprites at the SAT_MIRROR cursor (tile 40h, color 0Fh =
        ; white smoke).
        ld      ix,SMOKE_TRAIL_TABLE                           ;#5C87: DD 21 00 E4
        ld      b,9                                            ;#5C8B: 06 09
SCROLL_SMOKE_LOOP_TOP:
        ; Outer djnz of SCROLL_SMOKE_TRAILS
        ld      a,(ix+SMOKE_OFFSET_ACTIVE)                     ;#5C8D: DD 7E 00
        and     a                                              ;#5C90: A7
        jr      z,SMOKE_ADVANCE_IX                             ;#5C91: 28 53
        ld      a,(WORLD_SCROLL_DX)                            ;#5C93: 3A 96 E0
        ld      e,a                                            ;#5C96: 5F
        ld      d,0                                            ;#5C97: 16 00
        rla                                                    ;#5C99: 17
        jr      nc,SMOKE_APPLY_DX                              ;#5C9A: 30 01
        dec     d                                              ;#5C9C: 15
SMOKE_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to smoke entry X
        ld      l,(ix+SMOKE_OFFSET_X)                          ;#5C9D: DD 6E 03
        ld      h,(ix+SMOKE_OFFSET_X_HI)                       ;#5CA0: DD 66 04
        add     hl,de                                          ;#5CA3: 19
        ld      (ix+SMOKE_OFFSET_X_HI),h                       ;#5CA4: DD 74 04
        ld      (ix+SMOKE_OFFSET_X),l                          ;#5CA7: DD 75 03
        ld      a,h                                            ;#5CAA: 7C
        and     a                                              ;#5CAB: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CAC: 20 40
        ld      a,l                                            ;#5CAE: 7D
        cp      0A9h                                           ;#5CAF: FE A9
        jr      nc,SMOKE_DEACTIVATE                            ;#5CB1: 30 3B
        ld      c,l                                            ;#5CB3: 4D
        ld      a,(WORLD_SCROLL_DY)                            ;#5CB4: 3A 97 E0
        ld      e,a                                            ;#5CB7: 5F
        ld      d,0                                            ;#5CB8: 16 00
        rla                                                    ;#5CBA: 17
        jr      nc,SMOKE_APPLY_DY                              ;#5CBB: 30 01
        dec     d                                              ;#5CBD: 15
SMOKE_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to smoke entry Y
        ld      l,(ix+SMOKE_OFFSET_Y)                          ;#5CBE: DD 6E 05
        ld      h,(ix+SMOKE_OFFSET_Y_HI)                       ;#5CC1: DD 66 06
        add     hl,de                                          ;#5CC4: 19
        ld      (ix+SMOKE_OFFSET_Y),l                          ;#5CC5: DD 75 05
        ld      (ix+SMOKE_OFFSET_Y_HI),h                       ;#5CC8: DD 74 06
        ld      a,h                                            ;#5CCB: 7C
        and     a                                              ;#5CCC: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CCD: 20 1F
        ld      a,l                                            ;#5CCF: 7D
        cp      0E0h                                           ;#5CD0: FE E0
        jr      nc,SMOKE_DEACTIVATE                            ;#5CD2: 30 1A
        sub     18h                                            ;#5CD4: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5CD6: 2A 94 E0
        ; emit one E400 object sprite
        ld      (hl),a                                         ;#5CD9: 77
        inc     hl                                             ;#5CDA: 23
        ld      (hl),c                                         ;#5CDB: 71
        inc     hl                                             ;#5CDC: 23
        ld      (hl),40h                                       ;#5CDD: 36 40
        inc     hl                                             ;#5CDF: 23
        ld      (hl),0Fh                                       ;#5CE0: 36 0F
        inc     hl                                             ;#5CE2: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5CE3: 22 94 E0
SMOKE_ADVANCE_IX:
        ; Advance IX by 10h to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5CE6: 11 10 00
        add     ix,de                                          ;#5CE9: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CEB: 10 A0
        ret                                                    ;#5CED: C9

SMOKE_DEACTIVATE:
        ; Off-screen / hit smoke: zero entry, advance IX, djnz back
        ld      (ix+SMOKE_OFFSET_ACTIVE),0                     ;#5CEE: DD 36 00 00
        ld      de,10h                                         ;#5CF2: 11 10 00
        add     ix,de                                          ;#5CF5: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CF7: 10 94
        ret                                                    ;#5CF9: C9

SPRITE_CAR:
        ; Player car sprite (16x16); stored pre-transpose, see TRANSPOSE_TILE_BLOCKS
        dh      "0103777F7703030206EEEEFEEFE70202"             ;#5CFA: 01 03 77 7F 77 03 03 02 06 EE EE FE EF E7 02 02
        dh      "80C0EEFEEEC0C0406077777FF7E74040"             ;#5D0A: 80 C0 EE FE EE C0 C0 40 60 77 77 7F F7 E7 40 40

SPRITE_CAR_ROTATED_30:
        ; Player car rotated 30 degrees (pre-transpose)
        dh      "060E0F0C007173F2FEFC181C1F171404"             ;#5D1A: 06 0E 0F 0C 00 71 73 F2 FE FC 18 1C 1F 17 14 04
        dh      "0070F8F8FFFFFF662060C0F8F8F87070"             ;#5D2A: 00 70 F8 F8 FF FF FF 66 20 60 C0 F8 F8 F8 70 70

SPRITE_CAR_ROTATED_45:
        ; Player car rotated 45 degrees (pre-transpose)
        dh      "00000038F8FBFE3C3031FB1F7F030303"             ;#5D3A: 00 00 00 38 F8 FB FE 3C 30 31 FB 1F 7F 03 03 03
        dh      "70F0F07C7EFEFE7C64C70F0EE0E0E080"             ;#5D4A: 70 F0 F0 7C 7E FE FE 7C 64 C7 0F 0E E0 E0 E0 80

SPRITE_FLAG:
        ; Checkpoint flag sprite (16x16); base of the 3180h sprite upload
        dh      "00000000000000000000010100000000"             ;#5D5A: 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5D6A: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_L_FLAG:
        ; 'L' flag sprite
        dh      "006060606060607E0000010100000000"             ;#5D7A: 00 60 60 60 60 60 60 7E 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5D8A: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_S_FLAG:
        ; Special 'S' flag sprite (doubles bonus values)
        dh      "003C66603C06663C0000010100000000"             ;#5D9A: 00 3C 66 60 3C 06 66 3C 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5DAA: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_ROCK:
        ; Rock obstacle sprite
        dh      "00104161033337071F3F3F7F7F7F3F0F"             ;#5DBA: 00 10 41 61 03 33 37 07 1F 3F 3F 7F 7F 7F 3F 0F
        dh      "00E0F0F8FCFCFCFCFEFEFEFFFFFFFFC6"             ;#5DCA: 00 E0 F0 F8 FC FC FC FC FE FE FE FF FF FF FF C6

SPRITE_SMOKE:
        ; Smoke-screen sprite
        dh      "00193F3F7F7F7F7F3F7F7F3F3F1F0E00"             ;#5DDA: 00 19 3F 3F 7F 7F 7F 7F 3F 7F 7F 3F 3F 1F 0E 00
        dh      "0014BEFFFEFEFCFCFEFFFFFFFEBC1800"             ;#5DEA: 00 14 BE FF FE FE FC FC FE FF FF FF FE BC 18 00

SPRITE_BANG:
        ; Crash 'BANG' explosion sprite
        dh      "9945B310C6A9A9CFA9A9C900B7654D99"             ;#5DFA: 99 45 B3 10 C6 A9 A9 CF A9 A9 C9 00 B7 65 4D 99
        dh      "275C91005354747575555700B5565249"             ;#5E0A: 27 5C 91 00 53 54 74 75 75 55 57 00 B5 56 52 49

SPRITE_BONUS_100:
        ; Bonus 100 score popup sprite
        dh      "00113212121212390000000000000000"             ;#5E1A: 00 11 32 12 12 12 12 39 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5E2A: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_100X2:
        ; Bonus 100 doubled (special-flag) popup sprite
        dh      "00113212121212390000110A040A1100"             ;#5E3A: 00 11 32 12 12 12 12 39 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5E4A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_200:
        ; Bonus 200 score popup sprite
        dh      "00718A8A122242F90000000000000000"             ;#5E5A: 00 71 8A 8A 12 22 42 F9 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5E6A: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_200X2:
        ; Bonus 200 doubled (special-flag) popup sprite
        dh      "00718A8A122242F90000110A040A1100"             ;#5E7A: 00 71 8A 8A 12 22 42 F9 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5E8A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_300:
        ; Bonus 300 score popup sprite
        dh      "00718A0A320A8A710000000000000000"             ;#5E9A: 00 71 8A 0A 32 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5EAA: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_300X2:
        ; Bonus 300 doubled (special-flag) popup sprite
        dh      "00718A0A320A8A710000110A040A1100"             ;#5EBA: 00 71 8A 0A 32 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5ECA: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_400:
        ; Bonus 400 score popup sprite
        dh      "0011325292FA12110000000000000000"             ;#5EDA: 00 11 32 52 92 FA 12 11 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5EEA: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_400X2:
        ; Bonus 400 doubled (special-flag) popup sprite
        dh      "0011325292FA12110000110A040A1100"             ;#5EFA: 00 11 32 52 92 FA 12 11 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F0A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_500:
        ; Bonus 500 score popup sprite
        dh      "00F982F20A0A8A710000000000000000"             ;#5F1A: 00 F9 82 F2 0A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5F2A: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_500X2:
        ; Bonus 500 doubled (special-flag) popup sprite
        dh      "00F982F20A0A8A710000110A040A1100"             ;#5F3A: 00 F9 82 F2 0A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F4A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_600:
        ; Bonus 600 score popup sprite
        dh      "00718A82F28A8A710000000000000000"             ;#5F5A: 00 71 8A 82 F2 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5F6A: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_600X2:
        ; Bonus 600 doubled (special-flag) popup sprite
        dh      "00718A82F28A8A710000110A040A1100"             ;#5F7A: 00 71 8A 82 F2 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F8A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_700:
        ; Bonus 700 score popup sprite
        dh      "00F90A0A122222210000000000000000"             ;#5F9A: 00 F9 0A 0A 12 22 22 21 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5FAA: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_700X2:
        ; Bonus 700 doubled (special-flag) popup sprite
        dh      "00F90A0A122222210000110A040A1100"             ;#5FBA: 00 F9 0A 0A 12 22 22 21 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5FCA: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_800:
        ; Bonus 800 score popup sprite
        dh      "00718A8A728A8A710000000000000000"             ;#5FDA: 00 71 8A 8A 72 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5FEA: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_800X2:
        ; Bonus 800 doubled (special-flag) popup sprite
        dh      "00718A8A728A8A710000110A040A1100"             ;#5FFA: 00 71 8A 8A 72 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#600A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_900:
        ; Bonus 900 score popup sprite
        dh      "00718A8A7A0A8A710000000000000000"             ;#601A: 00 71 8A 8A 7A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#602A: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_900X2:
        ; Bonus 900 doubled (special-flag) popup sprite
        dh      "00718A8A7A0A8A710000110A040A1100"             ;#603A: 00 71 8A 8A 7A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#604A: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_1000:
        ; Bonus 1000 score popup sprite
        dh      "0098A5A5A5A5A5980000000000000000"             ;#605A: 00 98 A5 A5 A5 A5 A5 98 00 00 00 00 00 00 00 00
        dh      "00C62929292929C60000000000000000"             ;#606A: 00 C6 29 29 29 29 29 C6 00 00 00 00 00 00 00 00

SPRITE_BONUS_1000X2:
        ; Bonus 1000 doubled (special-flag) popup sprite
        dh      "0098A5A5A5A5A5980000110A040A1100"             ;#607A: 00 98 A5 A5 A5 A5 A5 98 00 00 11 0A 04 0A 11 00
        dh      "00C62929292929C6003844440810207C"             ;#608A: 00 C6 29 29 29 29 29 C6 00 38 44 44 08 10 20 7C

SPRITE_GAMEOVER_LEFT:
        ; GAME OVER text, left half
        dh      "1F30606763331F003E63636363633E00"             ;#609A: 1F 30 60 67 63 33 1F 00 3E 63 63 63 63 63 3E 00
        dh      "1C3663637F636300636363773E1C0800"             ;#60AA: 1C 36 63 63 7F 63 63 00 63 63 63 77 3E 1C 08 00

SPRITE_GAMEOVER_RIGHT:
        ; GAME OVER text, right half
        dh      "63777F7F6B6363003F30303E30303F00"             ;#60BA: 63 77 7F 7F 6B 63 63 00 3F 30 30 3E 30 30 3F 00
        dh      "3F30303E30303F007E6363677C6E6700"             ;#60CA: 3F 30 30 3E 30 30 3F 00 7E 63 63 67 7C 6E 67 00

TILE_PATTERN_HEX_DIGITS:
        ; Hex digit font 0-F (16x 8x8); base of the boot pattern-table upload
        dh      "1C26636363321C000C1C0C0C0C0C3F00"             ;#60DA: 1C 26 63 63 63 32 1C 00 0C 1C 0C 0C 0C 0C 3F 00
        dh      "3E63071E3C707F003F060C1703633E00"             ;#60EA: 3E 63 07 1E 3C 70 7F 00 3F 06 0C 17 03 63 3E 00
        dh      "0E1E36667F0606007E607E0303633E00"             ;#60FA: 0E 1E 36 66 7F 06 06 00 7E 60 7E 03 03 63 3E 00
        dh      "1E30607E63633E007F62060C18181800"             ;#610A: 1E 30 60 7E 63 63 3E 00 7F 62 06 0C 18 18 18 00
        dh      "3C62723C4F433E003E63633F03063C00"             ;#611A: 3C 62 72 3C 4F 43 3E 00 3E 63 63 3F 03 06 3C 00
        dh      "1C3663637F6363007E63637E63637E00"             ;#612A: 1C 36 63 63 7F 63 63 00 7E 63 63 7E 63 63 7E 00
        dh      "1E33606060331E007C66636363667C00"             ;#613A: 1E 33 60 60 60 33 1E 00 7C 66 63 63 63 66 7C 00
        dh      "3F30303E30303F007F60607E60606000"             ;#614A: 3F 30 30 3E 30 30 3F 00 7F 60 60 7E 60 60 60 00

TILE_PATTERN_NAMCOT_LOGO:
        ; Namcot publisher logo, 8x 8x8 tiles
        dh      "7F7F60606060606087C7C0C7CFCCCFC7"             ;#615A: 7F 7F 60 60 60 60 60 60 87 C7 C0 C7 CF CC CF C7
        dh      "F1F939F9F939F9F9FFFF999999999999"             ;#616A: F1 F9 39 F9 F9 39 F9 F9 FF FF 99 99 99 99 99 99
        dh      "0F9F989898989F8FE3E706060606E7E3"             ;#617A: 0F 9F 98 98 98 98 9F 8F E3 E7 06 06 06 06 E7 E3
        dh      "F8FC0C0C0C0CFCF8FFFF181818181818"             ;#618A: F8 FC 0C 0C 0C 0C FC F8 FF FF 18 18 18 18 18 18

TILE_PATTERN_CHAR_FONT:
        ; Uppercase font tiles: A-Z © . − (32x 8x8); LDIR'd 3x to E100-E3FF
        dh      "00000000000000001C3663637F636300"             ;#619A: 00 00 00 00 00 00 00 00 1C 36 63 63 7F 63 63 00
        dh      "7E63637E63637E001E33606060331E00"             ;#61AA: 7E 63 63 7E 63 63 7E 00 1E 33 60 60 60 33 1E 00
        dh      "7C66636363667C003F30303E30303F00"             ;#61BA: 7C 66 63 63 63 66 7C 00 3F 30 30 3E 30 30 3F 00
        dh      "7F60607E606060001F30606763331F00"             ;#61CA: 7F 60 60 7E 60 60 60 00 1F 30 60 67 63 33 1F 00
        dh      "6363637F636363003F0C0C0C0C0C3F00"             ;#61DA: 63 63 63 7F 63 63 63 00 3F 0C 0C 0C 0C 0C 3F 00
        dh      "0303030303633E0063666C787C6E6700"             ;#61EA: 03 03 03 03 03 63 3E 00 63 66 6C 78 7C 6E 67 00
        dh      "3030303030303F0063777F7F6B636300"             ;#61FA: 30 30 30 30 30 30 3F 00 63 77 7F 7F 6B 63 63 00
        dh      "63737B7F6F6763003E63636363633E00"             ;#620A: 63 73 7B 7F 6F 67 63 00 3E 63 63 63 63 63 3E 00
        dh      "7E6363637E6060003E6363636F663D00"             ;#621A: 7E 63 63 63 7E 60 60 00 3E 63 63 63 6F 66 3D 00
        dh      "7E6363677C6E67003C66603E03633E00"             ;#622A: 7E 63 63 67 7C 6E 67 00 3C 66 60 3E 03 63 3E 00
        dh      "3F0C0C0C0C0C0C006363636363633E00"             ;#623A: 3F 0C 0C 0C 0C 0C 0C 00 63 63 63 63 63 63 3E 00
        dh      "636363773E1C080063636B7F7F776300"             ;#624A: 63 63 63 77 3E 1C 08 00 63 63 6B 7F 7F 77 63 00
        dh      "63773E1C3E7763003333331E0C0C0C00"             ;#625A: 63 77 3E 1C 3E 77 63 00 33 33 33 1E 0C 0C 0C 00
        dh      "7F070E1C38707F003C4299A1A199423C"             ;#626A: 7F 07 0E 1C 38 70 7F 00 3C 42 99 A1 A1 99 42 3C
        dh      "00000000000000000000000000181800"             ;#627A: 00 00 00 00 00 00 00 00 00 00 00 00 00 18 18 00
        dh      "00000000000000000000007E00000000"             ;#628A: 00 00 00 00 00 00 00 00 00 00 00 7E 00 00 00 00

PATTERN_RALLYX_LOGO:
        ; Rally-X logo char patterns (88x 8x8, chars 80h+); LDIRVM'd to VRAM 0C00h/1C00h
        dh      "3F6040C080808080FF00000000000000"             ;#629A: 3F 60 40 C0 80 80 80 80 FF 00 00 00 00 00 00 00
        dh      "FF0100000000000000C0406020301018"             ;#62AA: FF 01 00 00 00 00 00 00 00 C0 40 60 20 30 10 18
        dh      "00000000000000000F1830206040C080"             ;#62BA: 00 00 00 00 00 00 00 00 0F 18 30 20 60 40 C0 80
        dh      "C0701018080C04060001010302020202"             ;#62CA: C0 70 10 18 08 0C 04 06 00 01 01 03 02 02 02 02
        dh      "80808080808080801E1F1E0000000000"             ;#62DA: 80 80 80 80 80 80 80 80 1E 1F 1E 00 00 00 00 00
        dh      "1C1C1E1F1F1F3F7F01010302028684C4"             ;#62EA: 1C 1C 1E 1F 1F 1F 3F 7F 01 01 03 02 02 86 84 C4
        dh      "820707070F0F1F000303030181818000"             ;#62FA: 82 07 07 07 0F 0F 1F 00 03 03 03 01 81 81 80 00
        dh      "020282C2C2E2F2F2000000081C1C1C1C"             ;#630A: 02 02 82 C2 C2 E2 F2 F2 00 00 00 08 1C 1C 1C 1C
        dh      "0301000000000000FFFF7F3F3F3F3F3F"             ;#631A: 03 01 00 00 00 00 00 00 FF FF 7F 3F 3F 3F 3F 3F
        dh      "CCE8F8F0F0E0E0C0FA7A7E7E7E7E3E3E"             ;#632A: CC E8 F8 F0 F0 E0 E0 C0 FA 7A 7E 7E 7E 7E 3E 3E
        dh      "1C1C1C1C1C1C1C1C3F3F3F3F3F3E3E3E"             ;#633A: 1C 1C 1C 1C 1C 1C 1C 1C 3F 3F 3F 3F 3F 3E 3E 3E
        dh      "C0808000000000003E3E1E1E1E1E0E0E"             ;#634A: C0 80 80 00 00 00 00 00 3E 3E 1E 1E 1E 1E 0E 0E
        dh      "8080808080C040601C1C1C1C1C1C1C3E"             ;#635A: 80 80 80 80 80 C0 40 60 1C 1C 1C 1C 1C 1C 1C 3E
        dh      "3C3C38383838387C0E0E0E0707070F1F"             ;#636A: 3C 3C 38 38 38 38 38 7C 0E 0E 0E 07 07 07 0F 1F
        dh      "3F3F1F1F0F070301FFFFFFFFFFFFFFFF"             ;#637A: 3F 3F 1F 1F 0F 07 03 01 FF FF FF FF FF FF FF FF
        dh      "FFFF7F3F1F000000FFFFFFFFFF000000"             ;#638A: FF FF 7F 3F 1F 00 00 00 FF FF FF FF FF 00 00 00
        dh      "FF80000000000000C06030180C0C0E0F"             ;#639A: FF 80 00 00 00 00 00 00 C0 60 30 18 0C 0C 0E 0F
        dh      "F018080C060203031F30303038181C0C"             ;#63AA: F0 18 08 0C 06 02 03 03 1F 30 30 30 38 18 1C 0C
        dh      "F80C0603010000000000000080C04161"             ;#63BA: F8 0C 06 03 01 00 00 00 00 00 00 00 80 C0 41 61
        dh      "0F0F0F0F0F0703000080C0C0E0E0F010"             ;#63CA: 0F 0F 0F 0F 0F 07 03 00 00 80 C0 C0 E0 E0 F0 10
        dh      "03030303030100008E87C7C3E1F1F808"             ;#63DA: 03 03 03 03 03 01 00 00 8E 87 C7 C3 E1 F1 F8 08
        dh      "00000080C0C0E0F033121E0C00000000"             ;#63EA: 00 00 00 80 C0 C0 E0 F0 33 12 1E 0C 00 00 00 00
        dh      "180C0E0E0F0F0F0F0C06070707070707"             ;#63FA: 18 0C 0E 0E 0F 0F 0F 0F 0C 06 07 07 07 07 07 07
        dh      "783C1C0C84C4E4F40F0F0F0F0F0F0F0F"             ;#640A: 78 3C 1C 0C 84 C4 E4 F4 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0707070707070707F4FCFCFCFCFCFCFC"             ;#641A: 07 07 07 07 07 07 07 07 F4 FC FC FC FC FC FC FC
        dh      "00000000000080C00F0F0F0F0F0F0F1F"             ;#642A: 00 00 00 00 00 00 80 C0 0F 0F 0F 0F 0F 0F 0F 1F
        dh      "808080C0C0C0E0F0070707070707070F"             ;#643A: 80 80 80 C0 C0 C0 E0 F0 07 07 07 07 07 07 07 0F
        dh      "FCFCFCFCFCFCFCFE0000000000000001"             ;#644A: FC FC FC FC FC FC FC FE 00 00 00 00 00 00 00 01
        dh      "FFFFF7F7F7F3F3F1F1F0F0F0F0000000"             ;#645A: FF FF F7 F7 F7 F3 F3 F1 F1 F0 F0 F0 F0 00 00 00
        dh      "FFFFFF7F7F0000000F19103061C18307"             ;#646A: FF FF FF 7F 7F 00 00 00 0F 19 10 30 61 C1 83 07
        dh      "008080E0E0F0F0F80306060202020301"             ;#647A: 00 80 80 E0 E0 F0 F0 F8 03 06 06 02 02 02 03 01
        dh      "F80C06020301010000010306040C98F0"             ;#648A: F8 0C 06 02 03 01 01 00 00 01 03 06 04 0C 98 F0
        dh      "F8880C0C0C1C3C3C070F1F1F3F7F7EFE"             ;#649A: F8 88 0C 0C 0C 1C 3C 3C 07 0F 1F 1F 3F 7F 7E FE
        dh      "F8FCFCFF80000000010101E03018080C"             ;#64AA: F8 FC FC FF 80 00 00 00 01 01 01 E0 30 18 08 0C
        dh      "8080C0E0E0E0F0786000000101030307"             ;#64BA: 80 80 C0 E0 E0 E0 F0 78 60 00 00 01 01 03 03 07
        dh      "7C7CFCF8F8F0F0E0FEFEFFFFFFFFFFFE"             ;#64CA: 7C 7C FC F8 F8 F0 F0 E0 FE FE FF FF FF FF FF FE
        dh      "000000FFFF7F3F1F0C0E1EFEFEFEFCF8"             ;#64DA: 00 00 00 FF FF 7F 3F 1F 0C 0E 1E FE FE FE FC F8
        dh      "78707030202060400303010101000000"             ;#64EA: 78 70 70 30 20 20 60 40 03 03 01 01 01 00 00 00
        dh      "E0C0C080808080C0FEFEFEFEFEFEFEFE"             ;#64FA: E0 C0 C0 80 80 80 80 C0 FE FE FE FE FE FE FE FE
        dh      "0000010103020604C080800000000000"             ;#650A: 00 00 01 01 03 02 06 04 C0 80 80 00 00 00 00 00
        dh      "4060203018080C060C18103060602030"             ;#651A: 40 60 20 30 18 08 0C 06 0C 18 10 30 60 60 20 30
        dh      "0000000001010307000040E0E0F0F8FC"             ;#652A: 00 00 00 00 01 01 03 07 00 00 40 E0 E0 F0 F8 FC
        dh      "02030101010101011F1F1F0F0F070707"             ;#653A: 02 03 01 01 01 01 01 01 1F 1F 1F 0F 0F 07 07 07
        dh      "FEFEFEFEFE0000000303010100000000"             ;#654A: FE FE FE FE FE 00 00 00 03 03 01 01 00 00 00 00

LOAD_PLAYFIELD_GFX:
        ; Fill name table, upload status/digit patterns, init both VRAM banks
        ; LOAD_PLAYFIELD_GFX uploads the HUD-and-text static graphics: tile patterns for
        ; chars 80h-FFh (PATTERN_RALLYX_LOGO → VRAM 0C00h + bank-B 1C00h), the HUD row
        ; tile-mapping (TILES_RALLYX_LOGO → 04A0h), the SCORE/HI_SCORE labels, digit-row
        ; templates, and the NAMCO copyright text. Also unpacks the initial scores
        ; (HIGH_SCORE_BCD via UNPACK_BCD_DIGITS).
        LOAD_VRAM_ADDRESS hl, 400h                             ;#655A: 21 00 04
        ld      bc,300h                                        ;#655D: 01 00 03
        ld      a,40h                                          ;#6560: 3E 40
        call    BIOS_FILVRM                                    ;#6562: CD 56 00
        xor     a                                              ;#6565: AF
        ld      (NAME_BANK_FLAG),a                             ;#6566: 32 8E E0
        LOAD_VRAM_ADDRESS hl, 790h                             ;#6569: 21 90 07
        ld      bc,10h                                         ;#656C: 01 10 00
        ld      a,50h                                          ;#656F: 3E 50
        call    BIOS_FILVRM                                    ;#6571: CD 56 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#6574: 21 9A 62
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#6577: 11 00 0C
        ld      bc,400h                                        ;#657A: 01 00 04
        call    BIOS_LDIRVM                                    ;#657D: CD 5C 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#6580: 21 9A 62
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#6583: 11 00 1C
        ld      bc,400h                                        ;#6586: 01 00 04
        call    BIOS_LDIRVM                                    ;#6589: CD 5C 00
        ld      hl,TILES_RALLYX_LOGO                           ;#658C: 21 4A 66
        LOAD_VRAM_ADDRESS de, 4A0h                             ;#658F: 11 A0 04
        ld      bc,0E0h                                        ;#6592: 01 E0 00
        call    BIOS_LDIRVM                                    ;#6595: CD 5C 00
        ld      hl,PLAYFIELD_NAMETABLE_DATA                    ;#6598: 21 F8 65
        LOAD_VRAM_ADDRESS de, 406h                             ;#659B: 11 06 04
        ld      bc,13h                                         ;#659E: 01 13 00
        call    BIOS_LDIRVM                                    ;#65A1: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#65A4: 21 B1 E0
        call    UNPACK_BCD_DIGITS                              ;#65A7: CD AA 67
        ld      hl,DIGIT_TILE_BUFFER                           ;#65AA: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 423h                             ;#65AD: 11 23 04
        ld      bc,8                                           ;#65B0: 01 08 00
        call    BIOS_LDIRVM                                    ;#65B3: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#65B6: 21 81 E0
        call    UNPACK_BCD_DIGITS                              ;#65B9: CD AA 67
        ld      hl,DIGIT_TILE_BUFFER                           ;#65BC: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 430h                             ;#65BF: 11 30 04
        ld      bc,8                                           ;#65C2: 01 08 00
        call    BIOS_LDIRVM                                    ;#65C5: CD 5C 00
        ld      hl,DEFAULT_SCORE_VALUES                        ;#65C8: 21 0B 66
        LOAD_VRAM_ADDRESS de, 5C8h                             ;#65CB: 11 C8 05
        ld      bc,0Eh                                         ;#65CE: 01 0E 00
        call    BIOS_LDIRVM                                    ;#65D1: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_10_17                        ;#65D4: 21 19 66
        LOAD_VRAM_ADDRESS de, 62Bh                             ;#65D7: 11 2B 06
        ld      bc,8                                           ;#65DA: 01 08 00
        call    BIOS_LDIRVM                                    ;#65DD: CD 5C 00
        ld      hl,TEXT_NAMCO_LTD                              ;#65E0: 21 21 66
        LOAD_VRAM_ADDRESS de, 685h                             ;#65E3: 11 85 06
        ld      bc,16h                                         ;#65E6: 01 16 00
        call    BIOS_LDIRVM                                    ;#65E9: CD 5C 00
        ld      hl,TEXT_RIGHTS_RESERVED                        ;#65EC: 21 37 66
        LOAD_VRAM_ADDRESS de, 6C6h                             ;#65EF: 11 C6 06
        ld      bc,13h                                         ;#65F2: 01 13 00
        jp      BIOS_LDIRVM                                    ;#65F5: C3 5C 00

PLAYFIELD_NAMETABLE_DATA:
SCORE_HI_SCORE_LABELS:
        ; 19-byte "score      hi" + "score" label row LDIRVM'd to VRAM 0406h
        db      "score      hi", 7Fh, "score"                  ;#65F8: 73 63 6F 72 65 20 20 20 20 20 20 68 69 7F 73 63 6F 72 65

DEFAULT_SCORE_VALUES:
        ; 14-byte initial-displayed score digits LDIRVM'd to VRAM 05C8h
        dh      "30353328203330212325202B2539"                 ;#660B: 30 35 33 28 20 33 30 21 23 25 20 2B 25 39

DIGIT_TEMPLATE_10_17:
        ; 8 tile codes (10h..17h) LDIRVM'd to VRAM 062Bh as digit slot template
        dh      "1011121314151617"                             ;#6619: 10 11 12 13 14 15 16 17

TEXT_NAMCO_LTD:
        ; 22-byte "[ ... NAMCO LTD]" decoration + text LDIRVM'd to VRAM 0685h
        db      "[ ", 1, 9, 8, 0, " ", 1, 9, 8, 4, " NAMCO LTD]"  ;#6621: 5B 20 01 09 08 00 20 01 09 08 04 20 4E 41 4D 43 4F 20 4C 54 44 5D

TEXT_RIGHTS_RESERVED:
        ; 19-byte "ALL RIGHTS RESERVED" string LDIRVM'd to VRAM 06C6h
        db      "ALL RIGHTS RESERVED"                          ;#6637: 41 4C 4C 20 52 49 47 48 54 53 20 52 45 53 45 52 56 45 44

TILES_RALLYX_LOGO:
        ; Rally-X logo name-table layout (32x7 tile codes 80h-D7h); LDIRVM'd to VRAM 04A0h
        dh      "20202020208081828384858687A0A184"             ;#664A: 20 20 20 20 20 80 81 82 83 84 85 86 87 A0 A1 84
        dh      "80A2A3A4A5BBBCBDBEBFC02020202020"             ;#665A: 80 A2 A3 A4 A5 BB BC BD BE BF C0 20 20 20 20 20
        dh      "20202020208889848A8B8C8D8E84A6A7"             ;#666A: 20 20 20 20 20 88 89 84 8A 8B 8C 8D 8E 84 A6 A7
        dh      "88A8A9AAABC1C2C3C4C5C62020202020"             ;#667A: 88 A8 A9 AA AB C1 C2 C3 C4 C5 C6 20 20 20 20 20
        dh      "2020202020888F9091928484938484AC"             ;#668A: 20 20 20 20 20 88 8F 90 91 92 84 84 93 84 84 AC
        dh      "8884ADAE84C7C8C9CACBCC2020202020"             ;#669A: 88 84 AD AE 84 C7 C8 C9 CA CB CC 20 20 20 20 20
        dh      "202020202088948495968484978484AF"             ;#66AA: 20 20 20 20 20 88 94 84 95 96 84 84 97 84 84 AF
        dh      "8884B0B184CD84CECF84D02020202020"             ;#66BA: 88 84 B0 B1 84 CD 84 CE CF 84 D0 20 20 20 20 20
        dh      "20202020209899849A8484849BB284B3"             ;#66CA: 20 20 20 20 20 98 99 84 9A 84 84 84 9B B2 84 B3
        dh      "B484B5B6B7CD84D1D2D3D42020202020"             ;#66DA: B4 84 B5 B6 B7 CD 84 D1 D2 D3 D4 20 20 20 20 20
        dh      "20202020209C9D9D9D9D9D9D9D9D9D9D"             ;#66EA: 20 20 20 20 20 9C 9D 9D 9D 9D 9D 9D 9D 9D 9D 9D
        dh      "9D9D9DB89DCD84D59D9D9D2020202020"             ;#66FA: 9D 9D 9D B8 9D CD 84 D5 9D 9D 9D 20 20 20 20 20
        dh      "2020202020849E9F9F9F9F9F9F9F9F9F"             ;#670A: 20 20 20 20 20 84 9E 9F 9F 9F 9F 9F 9F 9F 9F 9F
        dh      "9F9F9FB9BAD684D79F9F9F2020202020"             ;#671A: 9F 9F 9F B9 BA D6 84 D7 9F 9F 9F 20 20 20 20 20

FLASH_AND_UPDATE_SCORE_HUD:
        ; Blink the SCORE label every 8 frames + redraw score digits each frame
        ; FLASH_AND_UPDATE_SCORE_HUD. Like UPDATE_SCORE_HUD but adds a visibility flash:
        ; when FRAME_TICK & 8, the SCORE label is replaced with spaces (FILVRM with
        ; value 20h) to make it blink. Otherwise it redraws normally. Used during
        ; attract mode or "1UP/2UP" highlighting.
        ld      hl,SCORE_LABEL                                 ;#672A: 21 4C 67
        ld      de,457h                                        ;#672D: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#6730: 3A 8E E0
        and     a                                              ;#6733: A7
        jr      z,FLASH_SCORE_LDIRVM_OR_FILL                   ;#6734: 28 03
        ld      de,1457h                                       ;#6736: 11 57 14
FLASH_SCORE_LDIRVM_OR_FILL:
        ; Branch: if FRAME_TICK & 8 then FILVRM blanks, else LDIRVM the label
        push    de                                             ;#6739: D5
        ld      bc,5                                           ;#673A: 01 05 00
        ld      a,(FRAME_TICK)                                 ;#673D: 3A 87 E0
        and     8                                              ;#6740: E6 08
        jr      z,UPDATE_SCORE_HUD_LDIRVM_LABEL                ;#6742: 28 28
        ex      de,hl                                          ;#6744: EB
        ld      a,20h                                          ;#6745: 3E 20
        call    BIOS_FILVRM                                    ;#6747: CD 56 00
        jr      UPDATE_SCORE_HUD_AFTER_LABEL                   ;#674A: 18 23

SCORE_LABEL:
        ; "SCORE" HUD label (5 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "SCORE"                                        ;#674C: 53 43 4F 52 45

HI_SCORE_LABEL:
        ; "HI_SCORE" HUD label (8 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "HI_SCORE"                                     ;#6751: 48 49 5F 53 43 4F 52 45

UPDATE_SCORE_HUD:
        ; Draw SCORE label and BCD-unpacked SCORE_BCD digits into the HUD name-table row
        ; UPDATE_SCORE_HUD redraws the score row each frame. LDIRVM the "SCORE" /
        ; "HI_SCORE" labels (SCORE_LABEL/HI_SCORE_LABEL), then UNPACK_BCD_DIGITS on
        ; SCORE_BCD (3 bytes BCD = 6 digits, leading-zero suppressed) and LDIRVM the
        ; digit row to the score VRAM position. Does the same for HIGH_SCORE_BCD.
        ld      hl,SCORE_LABEL                                 ;#6759: 21 4C 67
        ld      de,457h                                        ;#675C: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#675F: 3A 8E E0
        and     a                                              ;#6762: A7
        jr      z,UPDATE_SCORE_HUD_PUSH_DE                     ;#6763: 28 03
        LOAD_VRAM_ADDRESS de, 1457h                            ;#6765: 11 57 14
UPDATE_SCORE_HUD_PUSH_DE:
        ; Save DE (VRAM dest of SCORE row) for re-use across LDIRVM calls
        push    de                                             ;#6768: D5
        ld      bc,5                                           ;#6769: 01 05 00
UPDATE_SCORE_HUD_LDIRVM_LABEL:
        ; LDIRVM the SCORE label string
        call    BIOS_LDIRVM                                    ;#676C: CD 5C 00
UPDATE_SCORE_HUD_AFTER_LABEL:
        ; After SCORE label: restore DE, set up HI_SCORE position via DE - 40h
        pop     de                                             ;#676F: D1
        push    de                                             ;#6770: D5
        ld      hl,-40h                                        ;#6771: 21 C0 FF
        add     hl,de                                          ;#6774: 19
        ex      de,hl                                          ;#6775: EB
        ld      hl,HI_SCORE_LABEL                              ;#6776: 21 51 67
        ld      bc,8                                           ;#6779: 01 08 00
        call    BIOS_LDIRVM                                    ;#677C: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#677F: 21 B1 E0
        call    UNPACK_BCD_DIGITS                              ;#6782: CD AA 67
        pop     de                                             ;#6785: D1
        push    de                                             ;#6786: D5
        ld      hl,20h                                         ;#6787: 21 20 00
        add     hl,de                                          ;#678A: 19
        ex      de,hl                                          ;#678B: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#678C: 21 F0 E1
        ld      bc,8                                           ;#678F: 01 08 00
        call    BIOS_LDIRVM                                    ;#6792: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#6795: 21 81 E0
        call    UNPACK_BCD_DIGITS                              ;#6798: CD AA 67
        pop     de                                             ;#679B: D1
        ld      hl,-20h                                        ;#679C: 21 E0 FF
        add     hl,de                                          ;#679F: 19
        ex      de,hl                                          ;#67A0: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#67A1: 21 F0 E1
        ld      bc,8                                           ;#67A4: 01 08 00
        jp      BIOS_LDIRVM                                    ;#67A7: C3 5C 00

UNPACK_BCD_DIGITS:
        ; Decode BCD bytes at HL into 8 tile indices at DIGIT_TILE_BUFFER
        ; UNPACK_BCD_DIGITS reads BCD bytes at HL and writes 8 tile indices at
        ; DIGIT_TILE_BUFFER. Each BCD nibble becomes a tile in the range 0..9. Leading
        ; zeros are suppressed (tile 40h = blank). The output is then LDIRVM'd to a
        ; digit row in VRAM by callers.
        ld      de,DIGIT_TILE_BUFFER_END                       ;#67AA: 11 F8 E1
        ld      b,8                                            ;#67AD: 06 08
        ld      a,40h                                          ;#67AF: 3E 40
UNPACK_BCD_CLEAR_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (init blanks)
        dec     de                                             ;#67B1: 1B
        ld      (de),a                                         ;#67B2: 12
        djnz    UNPACK_BCD_CLEAR_LOOP                          ;#67B3: 10 FC
        ld      b,3                                            ;#67B5: 06 03
UNPACK_BCD_SKIP_LZ_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (skip leading zero bytes)
        ld      a,(hl)                                         ;#67B7: 7E
        and     a                                              ;#67B8: A7
        jr      nz,UNPACK_BCD_NONZERO                          ;#67B9: 20 09
        inc     de                                             ;#67BB: 13
        inc     de                                             ;#67BC: 13
        inc     hl                                             ;#67BD: 23
        djnz    UNPACK_BCD_SKIP_LZ_LOOP                        ;#67BE: 10 F7
        ld      b,1                                            ;#67C0: 06 01
        jr      UNPACK_BCD_LOOP                                ;#67C2: 18 10

UNPACK_BCD_NONZERO:
        ; BCD byte non-zero: unpack high nibble (skip if leading zero), then low
        rra                                                    ;#67C4: 1F
        rra                                                    ;#67C5: 1F
        rra                                                    ;#67C6: 1F
        rra                                                    ;#67C7: 1F
        and     0Fh                                            ;#67C8: E6 0F
        jr      z,UNPACK_BCD_AFTER_HIGH                        ;#67CA: 28 01
        ld      (de),a                                         ;#67CC: 12
UNPACK_BCD_AFTER_HIGH:
        ; Common path after high nibble: store low nibble
        inc     de                                             ;#67CD: 13
        ld      a,(hl)                                         ;#67CE: 7E
        and     0Fh                                            ;#67CF: E6 0F
        ld      (de),a                                         ;#67D1: 12
        inc     de                                             ;#67D2: 13
        inc     hl                                             ;#67D3: 23
UNPACK_BCD_LOOP:
        ; Loop body: unpack high+low nibbles from one BCD byte, advance DE
        ld      a,(hl)                                         ;#67D4: 7E
        rra                                                    ;#67D5: 1F
        rra                                                    ;#67D6: 1F
        rra                                                    ;#67D7: 1F
        rra                                                    ;#67D8: 1F
        and     0Fh                                            ;#67D9: E6 0F
        ld      (de),a                                         ;#67DB: 12
        inc     de                                             ;#67DC: 13
        ld      a,(hl)                                         ;#67DD: 7E
        and     0Fh                                            ;#67DE: E6 0F
        ld      (de),a                                         ;#67E0: 12
        inc     de                                             ;#67E1: 13
        inc     hl                                             ;#67E2: 23
        djnz    UNPACK_BCD_LOOP                                ;#67E3: 10 EF
        ret                                                    ;#67E5: C9

ADD_SCORE:
        ; Look up SCORE_BONUS_TABLE[A] and BCD-add it into SCORE_BCD
        ; ADD_SCORE indexes SCORE_BONUS_TABLE by A, reads the BCD value, and adds it
        ; into SCORE_BCD with daa carry propagation. Then calls CHECK_SCORE_MILESTONE
        ; which awards an extra life on milestone scores.
        push    hl                                             ;#67E6: E5
        ld      hl,SCORE_BONUS_TABLE                           ;#67E7: 21 03 68
        add     a,l                                            ;#67EA: 85
        ld      l,a                                            ;#67EB: 6F
        jr      nc,ADD_SCORE_NO_CARRY                          ;#67EC: 30 01
        inc     h                                              ;#67EE: 24
ADD_SCORE_NO_CARRY:
        ; No carry from index offset: continue with high byte unchanged
        ld      a,(hl)                                         ;#67EF: 7E
        ld      hl,SCORE_BCD_HIGH                              ;#67F0: 21 B3 E0
        ld      b,3                                            ;#67F3: 06 03
        and     a                                              ;#67F5: A7
ADD_SCORE_BCD_LOOP:
        ; Inner djnz of ADD_SCORE (3-byte BCD add)
        adc     a,(hl)                                         ;#67F6: 8E
        daa                                                    ;#67F7: 27
        ld      (hl),a                                         ;#67F8: 77
        ld      a,0                                            ;#67F9: 3E 00
        dec     hl                                             ;#67FB: 2B
        djnz    ADD_SCORE_BCD_LOOP                             ;#67FC: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#67FE: CD 2D 68
        pop     hl                                             ;#6801: E1
        ret                                                    ;#6802: C9

SCORE_BONUS_TABLE:
        ; Points table indexed by event id; consumed by ADD_SCORE
        dh      "01020204030604080510061207140816"             ;#6803: 01 02 02 04 03 06 04 08 05 10 06 12 07 14 08 16
        dh      "09181020"                                     ;#6813: 09 18 10 20

BCD_ADD_TO_BONUS:
        ; Opcode-overlap entry adding 10h to BONUS_BCD (see CONVENTIONS § OVERLAP_LD_A)
        ld      a,10h                                          ;#6817: 3E 10
        ld      hl,BONUS_BCD                                   ;#6819: 21 B4 E0
        ld      b,4                                            ;#681C: 06 04
        and     a                                              ;#681E: A7
SCORE_BONUS_BCD_LOOP:
        ; Inner djnz inside SCORE_BONUS_TABLE area (alt entry)
        adc     a,(hl)                                         ;#681F: 8E
        daa                                                    ;#6820: 27
        ld      (hl),a                                         ;#6821: 77
        ld      a,0                                            ;#6822: 3E 00
        dec     hl                                             ;#6824: 2B
        djnz    SCORE_BONUS_BCD_LOOP                           ;#6825: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#6827: CD 2D 68
        jp      UPDATE_SCORE_HUD                               ;#682A: C3 59 67

CHECK_SCORE_MILESTONE:
        ; Inspect SCORE_BCD mid-byte for extra-life thresholds (2, 8); triggers SFX_60
        ; CHECK_SCORE_MILESTONE tests SCORE_BCD mid-byte (SCORE_BCD_MID) against 2 and 8
        ; (extra-life thresholds at every 200/800-thousand). When hit, increments LIVES,
        ; sets EXTRA_LIFE_AWARDED to prevent re-award, and triggers
        ; SFX_TRIGGER_EXTRA_LIFE for the celebratory jingle.
        ld      a,(SCORE_BCD_MID)                              ;#682D: 3A B2 E0
        cp      2                                              ;#6830: FE 02
        jr      nz,MILESTONE_CHECK_8                           ;#6832: 20 09
        ld      hl,EXTRA_LIFE_AWARDED                          ;#6834: 21 BE E0
        ld      a,(hl)                                         ;#6837: 7E
        and     a                                              ;#6838: A7
        jr      nz,UPDATE_HIGH_SCORE                           ;#6839: 20 1A
        jr      MILESTONE_AWARD_LIFE                           ;#683B: 18 0B

MILESTONE_CHECK_8:
        ; Check second milestone (8 -> 800k pts) for extra life
        cp      8                                              ;#683D: FE 08
        jr      nz,UPDATE_HIGH_SCORE                           ;#683F: 20 14
        ld      hl,EXTRA_LIFE_AWARDED                          ;#6841: 21 BE E0
        ld      a,(hl)                                         ;#6844: 7E
        dec     a                                              ;#6845: 3D
        jr      nz,UPDATE_HIGH_SCORE                           ;#6846: 20 0D
MILESTONE_AWARD_LIFE:
        ; Award extra life: set EXTRA_LIFE_AWARDED, trigger SFX, inc LIVES
        inc     (hl)                                           ;#6848: 34
        ld      a,1                                            ;#6849: 3E 01
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#684B: 32 60 E5
        ld      hl,LIVES                                       ;#684E: 21 B5 E0
        inc     (hl)                                           ;#6851: 34
        call    UPDATE_LIVES_DISPLAY                           ;#6852: CD 6F 68
UPDATE_HIGH_SCORE:
        ; Compare SCORE_BCD vs HIGH_SCORE_BCD; if greater, copy SCORE into HIGH_SCORE
        ; UPDATE_HIGH_SCORE compares SCORE_BCD byte-by-byte (high to low) against
        ; HIGH_SCORE_BCD. If SCORE > HIGH_SCORE at any byte position (early-exit on
        ; lower byte), copies the entire SCORE_BCD into HIGH_SCORE_BCD. Otherwise leaves
        ; HIGH_SCORE unchanged.
        ld      hl,HIGH_SCORE_BCD                              ;#6855: 21 81 E0
        ld      de,SCORE_BCD                                   ;#6858: 11 B1 E0
        ld      b,4                                            ;#685B: 06 04
HIGH_SCORE_COMPARE_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (compare path)
        ld      a,(de)                                         ;#685D: 1A
        cp      (hl)                                           ;#685E: BE
        ret     c                                              ;#685F: D8
        ld      (hl),a                                         ;#6860: 77
        inc     hl                                             ;#6861: 23
        inc     de                                             ;#6862: 13
        jr      nz,HIGH_SCORE_TAIL_LOOP                        ;#6863: 20 07
        djnz    HIGH_SCORE_COMPARE_LOOP                        ;#6865: 10 F6
        ret                                                    ;#6867: C9

HIGH_SCORE_COPY_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (copy path)
        ld      a,(de)                                         ;#6868: 1A
        ld      (hl),a                                         ;#6869: 77
        inc     hl                                             ;#686A: 23
        inc     de                                             ;#686B: 13
HIGH_SCORE_TAIL_LOOP:
        ; Inner copy loop: SCORE_BCD bytes 2..4 over to HIGH_SCORE_BCD
        djnz    HIGH_SCORE_COPY_LOOP                           ;#686C: 10 FA
        ret                                                    ;#686E: C9

UPDATE_LIVES_DISPLAY:
        ; Draw LIVES as mini-car tiles in the HUD name-table row; indexes LIVES_ICON_TILES
        ; UPDATE_LIVES_DISPLAY reads LIVES, indexes LIVES_ICON_TILES - 2*LIVES (so
        ; LIVES_ICON_TILES_TOP extends backward to prepend N car-top tiles), and LDIRVMs
        ; the two tile rows into the HUD name-table row (06B7h/06D7h) in both banks.
        ; LIVES=0 -> blank; LIVES=1 -> 1 mini-car icon; etc. These are name-table
        ; tiles, not sprites.
        ld      a,(LIVES)                                      ;#686F: 3A B5 E0
        ld      hl,LIVES_ICON_TILES                            ;#6872: 21 B6 68
        add     a,a                                            ;#6875: 87
        jr      z,LIVES_DRAW_LOOP                              ;#6876: 28 08
        neg                                                    ;#6878: ED 44
        add     a,l                                            ;#687A: 85
        ld      l,a                                            ;#687B: 6F
        ld      a,0FFh                                         ;#687C: 3E FF
        adc     a,h                                            ;#687E: 8C
        ld      h,a                                            ;#687F: 67
LIVES_DRAW_LOOP:
        ; Per-row LDIRVM loop: two 8-byte tile rows to two name-table bank mirrors
        push    hl                                             ;#6880: E5
        LOAD_VRAM_ADDRESS de, 6B7h                             ;#6881: 11 B7 06
        ld      bc,8                                           ;#6884: 01 08 00
        call    BIOS_LDIRVM                                    ;#6887: CD 5C 00
        pop     hl                                             ;#688A: E1
        push    hl                                             ;#688B: E5
        LOAD_VRAM_ADDRESS de, 16B7h                            ;#688C: 11 B7 16
        ld      bc,8                                           ;#688F: 01 08 00
        call    BIOS_LDIRVM                                    ;#6892: CD 5C 00
        pop     hl                                             ;#6895: E1
        ld      bc,10h                                         ;#6896: 01 10 00
        add     hl,bc                                          ;#6899: 09
        push    hl                                             ;#689A: E5
        LOAD_VRAM_ADDRESS de, 6D7h                             ;#689B: 11 D7 06
        ld      bc,8                                           ;#689E: 01 08 00
        call    BIOS_LDIRVM                                    ;#68A1: CD 5C 00
        pop     hl                                             ;#68A4: E1
        LOAD_VRAM_ADDRESS de, 16D7h                            ;#68A5: 11 D7 16
        ld      bc,8                                           ;#68A8: 01 08 00
        jp      BIOS_LDIRVM                                    ;#68AB: C3 5C 00

LIVES_ICON_TILES_TOP:
        ; Top-row tiles (F8/FA) of the lives mini-car icons; prepended via negative offset
        dh      "F8FAF8FAF8FAF8FA"                             ;#68AE: F8 FA F8 FA F8 FA F8 FA

LIVES_ICON_TILES:
        ; Name-table tiles for the lives indicator (car-bottom F9/FB + blank 40h padding)
        dh      "4040404040404040F9FBF9FBF9FBF9FB"             ;#68B6: 40 40 40 40 40 40 40 40 F9 FB F9 FB F9 FB F9 FB
        dh      "4040404040404040"                             ;#68C6: 40 40 40 40 40 40 40 40

PSG_SILENCE_DEFAULTS:
        ; 14 bytes copied to PSG_MIRROR each frame before sound subsystems mix in
        dh      "00000000000000B8000000000000"                 ;#68CE: 00 00 00 00 00 00 00 B8 00 00 00 00 00 00

UPDATE_SOUND:
        ; Render PSG output from PSG_MIRROR; runs 8 sound subsystems when GAME_ACTIVE
        ; UPDATE_SOUND copies the 14-byte PSG_SILENCE_DEFAULTS into PSG_MIRROR each
        ; frame as the "silent" baseline. Then, gated by GAME_ACTIVE, runs the 8 sound-
        ; tick subroutines (3 music + 5 SFX). Each subsystem reads a "control byte"
        ; (zero = no sound on this channel, non-zero = play the addressed stream). After
        ; ticking, writes PSG_MIRROR to PSG R0..R11 sequentially, plus R12 if
        ; PSG_MIRROR[0Dh] is non-zero (envelope-shape trigger). The 8 logical voices
        ; share the 3 PSG channels via priority.
        ld      hl,PSG_SILENCE_DEFAULTS                        ;#68DC: 21 CE 68
        ld      de,PSG_MIRROR                                  ;#68DF: 11 00 E5
        ld      bc,0Eh                                         ;#68E2: 01 0E 00
        ldir                                                   ;#68E5: ED B0
        ld      a,(GAME_ACTIVE)                                ;#68E7: 3A 80 E0
        and     a                                              ;#68EA: A7
        jr      z,SOUND_WRITE_PSG                              ;#68EB: 28 18
        call    SOUND_TICK_MUSIC_THEME                         ;#68ED: CD 75 6C
        call    SOUND_TICK_SFX_FLAG                            ;#68F0: CD 71 6A
        call    SOUND_TICK_MUSIC_OPENING                       ;#68F3: CD F4 6A
        call    SOUND_TICK_MUSIC_STAGE_CLEAR                   ;#68F6: CD 28 6B
        call    SOUND_TICK_SFX_C_STAGE                         ;#68F9: CD 38 69
        call    SOUND_TICK_SFX_SMOKE                           ;#68FC: CD 2B 6A
        call    SOUND_TICK_SFX_BONUS                           ;#68FF: CD EF 69
        call    SOUND_TICK_SFX_BANG                            ;#6902: CD 76 69
SOUND_WRITE_PSG:
        ; Walk PSG_MIRROR[0..0Bh] and write each register via BIOS_WRTPSG
        ld      hl,PSG_MIRROR                                  ;#6905: 21 00 E5
        xor     a                                              ;#6908: AF
        ld      b,0Ch                                          ;#6909: 06 0C
SOUND_PSG_WRITE_LOOP:
        ; Inner djnz of SOUND_WRITE_PSG (12 PSG registers)
        ld      e,(hl)                                         ;#690B: 5E
        inc     hl                                             ;#690C: 23
        call    BIOS_WRTPSG                                    ;#690D: CD 93 00
        inc     a                                              ;#6910: 3C
        djnz    SOUND_PSG_WRITE_LOOP                           ;#6911: 10 F8
        ld      a,(hl)                                         ;#6913: 7E
        and     a                                              ;#6914: A7
        ret     z                                              ;#6915: C8
        ld      e,a                                            ;#6916: 5F
        ld      a,0Ch                                          ;#6917: 3E 0C
        call    BIOS_WRTPSG                                    ;#6919: CD 93 00
        inc     hl                                             ;#691C: 23
        ld      e,(hl)                                         ;#691D: 5E
        inc     a                                              ;#691E: 3C
        jp      BIOS_WRTPSG                                    ;#691F: C3 93 00

SFX_C_STAGE_RESET:
        ; Done: clear SOUND_STATE_C_STAGE then fall into init
        xor     a                                              ;#6922: AF
        ld      (SOUND_STATE_C_STAGE),a                        ;#6923: 32 65 E5
SFX_C_STAGE_INIT_STREAM:
        ; Init SFX_C_STAGE stream pointers, counter, and volume cursor
        ld      hl,SFX_C_STAGE_STREAM                          ;#6926: 21 D0 6E
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),hl            ;#6929: 22 66 E5
        inc     hl                                             ;#692C: 23
        ld      a,(hl)                                         ;#692D: 7E
        ld      (SOUND_STATE_C_STAGE_COUNTER),a                ;#692E: 32 68 E5
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#6931: 21 5F 6D
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#6934: 22 69 E5
        ret                                                    ;#6937: C9

SOUND_TICK_SFX_C_STAGE:
        ; Sound subsystem driven by state at SOUND_STATE_C_STAGE
        ld      a,(SOUND_STATE_C_STAGE)                        ;#6938: 3A 65 E5
        and     a                                              ;#693B: A7
        jr      z,SFX_C_STAGE_INIT_STREAM                      ;#693C: 28 E8
        ld      de,(SOUND_STATE_C_STAGE_STREAM_PTR)            ;#693E: ED 5B 66 E5
        ld      a,(de)                                         ;#6942: 1A
        ld      c,a                                            ;#6943: 4F
        inc     a                                              ;#6944: 3C
        jr      z,SFX_C_STAGE_RESET                            ;#6945: 28 DB
        ld      hl,(SOUND_STATE_C_STAGE_VOL_PTR)               ;#6947: 2A 69 E5
        ld      a,(hl)                                         ;#694A: 7E
        inc     hl                                             ;#694B: 23
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#694C: 22 69 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#694F: 32 0A E5
        ld      hl,SOUND_STATE_C_STAGE_COUNTER                 ;#6952: 21 68 E5
        dec     (hl)                                           ;#6955: 35
        jr      nz,SFX_C_STAGE_LOAD_PITCH                      ;#6956: 20 10
        inc     de                                             ;#6958: 13
        inc     de                                             ;#6959: 13
        inc     de                                             ;#695A: 13
        ld      a,(de)                                         ;#695B: 1A
        dec     de                                             ;#695C: 1B
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),de            ;#695D: ED 53 66 E5
        ld      (hl),a                                         ;#6961: 77
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#6962: 21 5F 6D
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#6965: 22 69 E5
SFX_C_STAGE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_C_STAGE channel C
        ld      b,0                                            ;#6968: 06 00
        ld      hl,NOTE_PERIOD_TABLE                           ;#696A: 21 93 70
        add     hl,bc                                          ;#696D: 09
        ld      e,(hl)                                         ;#696E: 5E
        inc     hl                                             ;#696F: 23
        ld      d,(hl)                                         ;#6970: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#6971: ED 53 04 E5
        ret                                                    ;#6975: C9

SOUND_TICK_SFX_BANG:
        ; Sound subsystem driven by state at SOUND_STATE_BANG
        ld      a,(SOUND_STATE_BANG)                           ;#6976: 3A 62 E5
        dec     a                                              ;#6979: 3D
        jr      nz,SFX_BANG_TICK_BRANCH                        ;#697A: 20 36
        xor     a                                              ;#697C: AF
        ld      (SOUND_STATE_THEME),a                          ;#697D: 32 10 E5
        ld      (SOUND_STATE_OPENING),a                        ;#6980: 32 20 E5
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#6983: 32 30 E5
        ld      (SOUND_STATE_FLAG),a                           ;#6986: 32 40 E5
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#6989: 32 41 E5
        ld      (SOUND_STATE_SMOKE),a                          ;#698C: 32 42 E5
        ld      (SFX_TRIGGER_SMOKE),a                          ;#698F: 32 50 E5
        ld      (SOUND_STATE_BONUS),a                          ;#6992: 32 51 E5
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#6995: 32 60 E5
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#6998: 32 61 E5
        ld      a,2                                            ;#699B: 3E 02
        ld      (SOUND_STATE_BANG),a                           ;#699D: 32 62 E5
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#69A0: 21 D6 69
        ld      de,PSG_MIRROR                                  ;#69A3: 11 00 E5
        ld      bc,0Bh                                         ;#69A6: 01 0B 00
        ldir                                                   ;#69A9: ED B0
        ld      hl,SFX_BANG_VOLUME_ENVELOPE                    ;#69AB: 21 7F 6D
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#69AE: 22 63 E5
        ret                                                    ;#69B1: C9

SFX_BANG_TICK_BRANCH:
        ; SFX_BANG tick branch: ldir 8 bytes from precomputed envelope into PSG_MIRROR
        inc     a                                              ;#69B2: 3C
        ret     z                                              ;#69B3: C8
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#69B4: 21 D6 69
        ld      de,PSG_MIRROR                                  ;#69B7: 11 00 E5
        ld      bc,8                                           ;#69BA: 01 08 00
        ldir                                                   ;#69BD: ED B0
        ld      hl,(SOUND_STATE_BANG_STREAM_PTR)               ;#69BF: 2A 63 E5
        ld      a,(hl)                                         ;#69C2: 7E
        inc     hl                                             ;#69C3: 23
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#69C4: 22 63 E5
        inc     a                                              ;#69C7: 3C
        jr      nz,SFX_BANG_WRITE_VOL                          ;#69C8: 20 03
        ld      (SOUND_STATE_BANG),a                           ;#69CA: 32 62 E5
SFX_BANG_WRITE_VOL:
        ; Write the current envelope volume to PSG_MIRROR_VOL_A/B/C
        ld      hl,PSG_MIRROR_VOL_A                            ;#69CD: 21 08 E5
        ld      (hl),a                                         ;#69D0: 77
        inc     hl                                             ;#69D1: 23
        ld      (hl),a                                         ;#69D2: 77
        inc     hl                                             ;#69D3: 23
        ld      (hl),a                                         ;#69D4: 77
        ret                                                    ;#69D5: C9

SFX_BANG_INIT_PSG_BLOCK:
        ; 11-byte PSG silence/init block; LDIR-copied to PSG_MIRROR when SFX_BANG fires
        dh      "FF0FF205FF0F1F820F0F0F"                       ;#69D6: FF 0F F2 05 FF 0F 1F 82 0F 0F 0F

SFX_BONUS_INIT_STREAM:
        ; Init SFX_BONUS stream pointer at SFX_BONUS_STREAM
        ld      de,SFX_BONUS_STREAM                            ;#69E1: 11 BF 6E
        ld      hl,SOUND_STATE_BONUS_STREAM_PTR                ;#69E4: 21 52 E5
        ld      (hl),e                                         ;#69E7: 73
        inc     hl                                             ;#69E8: 23
        ld      (hl),d                                         ;#69E9: 72
        inc     hl                                             ;#69EA: 23
        inc     de                                             ;#69EB: 13
        ld      a,(de)                                         ;#69EC: 1A
        ld      (hl),a                                         ;#69ED: 77
        ret                                                    ;#69EE: C9

SOUND_TICK_SFX_BONUS:
        ; Sound subsystem driven by state at SOUND_STATE_BONUS
        ld      hl,SOUND_STATE_BONUS                           ;#69EF: 21 51 E5
        ld      a,(hl)                                         ;#69F2: 7E
        and     a                                              ;#69F3: A7
        jr      z,SFX_BONUS_INIT_STREAM                        ;#69F4: 28 EB
        inc     hl                                             ;#69F6: 23
        ld      e,(hl)                                         ;#69F7: 5E
        inc     hl                                             ;#69F8: 23
        ld      d,(hl)                                         ;#69F9: 56
        inc     hl                                             ;#69FA: 23
        ld      a,(de)                                         ;#69FB: 1A
        ld      c,a                                            ;#69FC: 4F
        inc     a                                              ;#69FD: 3C
        jr      z,SFX_BONUS_INIT_STREAM                        ;#69FE: 28 E1
        dec     (hl)                                           ;#6A00: 35
        jr      nz,SFX_BONUS_LOAD_PITCH                        ;#6A01: 20 0A
        inc     de                                             ;#6A03: 13
        inc     de                                             ;#6A04: 13
        inc     de                                             ;#6A05: 13
        ld      a,(de)                                         ;#6A06: 1A
        ld      (hl),a                                         ;#6A07: 77
        dec     de                                             ;#6A08: 1B
        dec     hl                                             ;#6A09: 2B
        ld      (hl),d                                         ;#6A0A: 72
        dec     hl                                             ;#6A0B: 2B
        ld      (hl),e                                         ;#6A0C: 73
SFX_BONUS_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_BONUS channel B
        ld      hl,NOTE_PERIOD_TABLE                           ;#6A0D: 21 93 70
        ld      b,0                                            ;#6A10: 06 00
        add     hl,bc                                          ;#6A12: 09
        ld      e,(hl)                                         ;#6A13: 5E
        inc     hl                                             ;#6A14: 23
        ld      d,(hl)                                         ;#6A15: 56
        ld      (PSG_MIRROR_PITCH_B),de                        ;#6A16: ED 53 02 E5
        ld      a,0Ch                                          ;#6A1A: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#6A1C: 32 09 E5
        ret                                                    ;#6A1F: C9

SFX_SMOKE_RESET:
        ; Done: reset volume pointer to SFX_SMOKE_VOLUME_ENVELOPE and clear state
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#6A20: 21 4F 6D
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A23: 22 47 E5
        xor     a                                              ;#6A26: AF
        ld      (SOUND_STATE_SMOKE_VOL_PTR),a                  ;#6A27: 32 47 E5
        ret                                                    ;#6A2A: C9

SOUND_TICK_SFX_SMOKE:
        ; Sound subsystem driven by state at SOUND_STATE_SMOKE
        ld      a,(SOUND_STATE_SMOKE)                          ;#6A2B: 3A 42 E5
        and     a                                              ;#6A2E: A7
        jr      z,SFX_SMOKE_RESET                              ;#6A2F: 28 EF
        ld      de,(SOUND_STATE_SMOKE_STREAM_PTR)              ;#6A31: ED 5B 43 E5
        ld      a,(de)                                         ;#6A35: 1A
        cp      0FFh                                           ;#6A36: FE FF
        jr      z,SFX_SMOKE_RESET                              ;#6A38: 28 E6
        ld      hl,SOUND_STATE_SMOKE_COUNTER                   ;#6A3A: 21 45 E5
        dec     (hl)                                           ;#6A3D: 35
        jr      nz,SFX_SMOKE_LOAD_PITCH                        ;#6A3E: 20 0F
        inc     hl                                             ;#6A40: 23
        ld      c,(hl)                                         ;#6A41: 4E
        dec     hl                                             ;#6A42: 2B
        ld      (hl),c                                         ;#6A43: 71
        dec     hl                                             ;#6A44: 2B
        inc     de                                             ;#6A45: 13
        ld      (hl),d                                         ;#6A46: 72
        dec     hl                                             ;#6A47: 2B
        ld      (hl),e                                         ;#6A48: 73
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#6A49: 21 4F 6D
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A4C: 22 47 E5
SFX_SMOKE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_SMOKE channel C
        ld      hl,NOTE_PERIOD_TABLE                           ;#6A4F: 21 93 70
        add     a,l                                            ;#6A52: 85
        ld      l,a                                            ;#6A53: 6F
        ld      a,0                                            ;#6A54: 3E 00
        adc     a,h                                            ;#6A56: 8C
        ld      h,a                                            ;#6A57: 67
        ld      e,(hl)                                         ;#6A58: 5E
        inc     hl                                             ;#6A59: 23
        ld      d,(hl)                                         ;#6A5A: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#6A5B: ED 53 04 E5
        ld      hl,(SOUND_STATE_SMOKE_VOL_PTR)                 ;#6A5F: 2A 47 E5
        ld      a,(hl)                                         ;#6A62: 7E
        inc     hl                                             ;#6A63: 23
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A64: 22 47 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#6A67: 32 0A E5
        ld      hl,0                                           ;#6A6A: 21 00 00
        ld      (PSG_MIRROR_VOL_A),hl                          ;#6A6D: 22 08 E5
        ret                                                    ;#6A70: C9

SOUND_TICK_SFX_FLAG:
        ; Sound subsystem driven by state at SOUND_STATE_FLAG
        ld      a,(SOUND_STATE_FLAG)                           ;#6A71: 3A 40 E5
        and     a                                              ;#6A74: A7
        jr      z,SFX_FLAG_CHECK_VARIANT                       ;#6A75: 28 17
        xor     a                                              ;#6A77: AF
        ld      (SOUND_STATE_FLAG),a                           ;#6A78: 32 40 E5
        ld      de,SFX_FLAG_STREAM_BASE                        ;#6A7B: 11 87 6E
SFX_FLAG_INIT_SFX_SMOKE:
        ; SFX_FLAG fires variant A: seed SOUND_STATE_SMOKE with stream and durations
        ld      hl,SOUND_STATE_SMOKE                           ;#6A7E: 21 42 E5
        ld      (hl),1                                         ;#6A81: 36 01
        inc     hl                                             ;#6A83: 23
        ld      (hl),e                                         ;#6A84: 73
        inc     hl                                             ;#6A85: 23
        ld      (hl),d                                         ;#6A86: 72
        inc     hl                                             ;#6A87: 23
        ld      (hl),2                                         ;#6A88: 36 02
        inc     hl                                             ;#6A8A: 23
        ld      (hl),2                                         ;#6A8B: 36 02
        ret                                                    ;#6A8D: C9

SFX_FLAG_CHECK_VARIANT:
        ; Check second SFX_FLAG variant flag (SOUND_STATE_FLAG_ALT)
        ld      a,(SOUND_STATE_FLAG_ALT)                       ;#6A8E: 3A 41 E5
        and     a                                              ;#6A91: A7
        jr      z,SFX_FLAG_CHECK_EXTRA_LIFE                    ;#6A92: 28 0A
        xor     a                                              ;#6A94: AF
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#6A95: 32 41 E5
        ld      de,SFX_FLAG_STREAM_FLAG_GET                    ;#6A98: 11 79 6E
        jp      SFX_FLAG_INIT_SFX_SMOKE                        ;#6A9B: C3 7E 6A

SFX_FLAG_CHECK_EXTRA_LIFE:
        ; Check SFX_TRIGGER_EXTRA_LIFE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_EXTRA_LIFE)                     ;#6A9E: 3A 60 E5
        and     a                                              ;#6AA1: A7
        jr      z,SFX_FLAG_CHECK_SMOKE                         ;#6AA2: 28 17
        xor     a                                              ;#6AA4: AF
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#6AA5: 32 60 E5
        ld      de,SFX_FLAG_STREAM_EXTRA_LIFE                  ;#6AA8: 11 9B 6E
        ld      hl,SOUND_STATE_SMOKE                           ;#6AAB: 21 42 E5
        ld      (hl),1                                         ;#6AAE: 36 01
        inc     hl                                             ;#6AB0: 23
        ld      (hl),e                                         ;#6AB1: 73
        inc     hl                                             ;#6AB2: 23
        ld      (hl),d                                         ;#6AB3: 72
        inc     hl                                             ;#6AB4: 23
        ld      (hl),4                                         ;#6AB5: 36 04
        inc     hl                                             ;#6AB7: 23
        ld      (hl),4                                         ;#6AB8: 36 04
        ret                                                    ;#6ABA: C9

SFX_FLAG_CHECK_SMOKE:
        ; Check SFX_TRIGGER_SMOKE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_SMOKE)                          ;#6ABB: 3A 50 E5
        and     a                                              ;#6ABE: A7
        jr      z,SFX_FLAG_CHECK_E561                          ;#6ABF: 28 17
        xor     a                                              ;#6AC1: AF
        ld      (SFX_TRIGGER_SMOKE),a                          ;#6AC2: 32 50 E5
        ld      de,SFX_SMOKE_STREAM                            ;#6AC5: 11 8F 6E
        ld      hl,SOUND_STATE_SMOKE                           ;#6AC8: 21 42 E5
        ld      (hl),1                                         ;#6ACB: 36 01
        inc     hl                                             ;#6ACD: 23
        ld      (hl),e                                         ;#6ACE: 73
        inc     hl                                             ;#6ACF: 23
        ld      (hl),d                                         ;#6AD0: 72
        inc     hl                                             ;#6AD1: 23
        ld      (hl),2                                         ;#6AD2: 36 02
        inc     hl                                             ;#6AD4: 23
        ld      (hl),2                                         ;#6AD5: 36 02
        ret                                                    ;#6AD7: C9

SFX_FLAG_CHECK_E561:
        ; Check SOUND_STATE_BANG_TRIGGER (fuel-low tick): kick SFX_SMOKE if just fired
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#6AD8: 3A 61 E5
        dec     a                                              ;#6ADB: 3D
        ret     nz                                             ;#6ADC: C0
        ld      a,2                                            ;#6ADD: 3E 02
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#6ADF: 32 61 E5
        ld      hl,SFX_FLAG_STREAM_FUEL_LOW                    ;#6AE2: 21 94 6E
        ld      (SOUND_STATE_SMOKE_STREAM_PTR),hl              ;#6AE5: 22 43 E5
        ld      hl,0F0Fh                                       ;#6AE8: 21 0F 0F
        ld      (SOUND_STATE_SMOKE_COUNTER),hl                 ;#6AEB: 22 45 E5
        ld      a,1                                            ;#6AEE: 3E 01
        ld      (SOUND_STATE_SMOKE),a                          ;#6AF0: 32 42 E5
        ret                                                    ;#6AF3: C9

SOUND_TICK_MUSIC_OPENING:
        ; Music channel B tick; state at SOUND_STATE_OPENING
        ld      hl,SOUND_STATE_OPENING                         ;#6AF4: 21 20 E5
        ld      a,(hl)                                         ;#6AF7: 7E
        and     a                                              ;#6AF8: A7
        jr      z,SOUND_TICK_MUSIC_OPENING_INIT                ;#6AF9: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#6AFB: CD 5C 6B
        and     a                                              ;#6AFE: A7
        ret     nz                                             ;#6AFF: C0
SOUND_TICK_MUSIC_OPENING_INIT:
        ; MUSIC_OPENING init: clear state and seed pointers for three streams
        ld      hl,SOUND_STATE_OPENING                         ;#6B00: 21 20 E5
        xor     a                                              ;#6B03: AF
        ld      (hl),a                                         ;#6B04: 77
        inc     hl                                             ;#6B05: 23
        ld      de,MUSIC_OPENING_VOICE_0                       ;#6B06: 11 6E 70
        ld      (hl),e                                         ;#6B09: 73
        inc     hl                                             ;#6B0A: 23
        ld      (hl),d                                         ;#6B0B: 72
        inc     hl                                             ;#6B0C: 23
        inc     de                                             ;#6B0D: 13
        ld      a,(de)                                         ;#6B0E: 1A
        ld      (hl),a                                         ;#6B0F: 77
        inc     hl                                             ;#6B10: 23
        ld      de,MUSIC_OPENING_VOICE_1                       ;#6B11: 11 4E 70
        ld      (hl),e                                         ;#6B14: 73
        inc     hl                                             ;#6B15: 23
        ld      (hl),d                                         ;#6B16: 72
        inc     hl                                             ;#6B17: 23
        inc     de                                             ;#6B18: 13
        ld      a,(de)                                         ;#6B19: 1A
        ld      (hl),a                                         ;#6B1A: 77
        inc     hl                                             ;#6B1B: 23
        ld      de,MUSIC_OPENING_VOICE_2                       ;#6B1C: 11 1C 70
        ld      (hl),e                                         ;#6B1F: 73
        inc     hl                                             ;#6B20: 23
        ld      (hl),d                                         ;#6B21: 72
        inc     hl                                             ;#6B22: 23
        inc     de                                             ;#6B23: 13
        ld      a,(de)                                         ;#6B24: 1A
        ld      (hl),a                                         ;#6B25: 77
        inc     hl                                             ;#6B26: 23
        ret                                                    ;#6B27: C9

SOUND_TICK_MUSIC_STAGE_CLEAR:
        ; Music channel C tick; state at SOUND_STATE_STAGE_CLEAR
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#6B28: 21 30 E5
        ld      a,(hl)                                         ;#6B2B: 7E
        and     a                                              ;#6B2C: A7
        jr      z,SOUND_TICK_MUSIC_STAGE_CLEAR_INIT            ;#6B2D: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#6B2F: CD 5C 6B
        and     a                                              ;#6B32: A7
        ret     nz                                             ;#6B33: C0
SOUND_TICK_MUSIC_STAGE_CLEAR_INIT:
        ; MUSIC_STAGE_CLEAR init: clear state and seed pointers for three voices
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#6B34: 21 30 E5
        xor     a                                              ;#6B37: AF
        ld      (hl),a                                         ;#6B38: 77
        inc     hl                                             ;#6B39: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_2            ;#6B3A: 11 AC 6E
        ld      (hl),e                                         ;#6B3D: 73
        inc     hl                                             ;#6B3E: 23
        ld      (hl),d                                         ;#6B3F: 72
        inc     hl                                             ;#6B40: 23
        inc     de                                             ;#6B41: 13
        ld      a,(de)                                         ;#6B42: 1A
        ld      (hl),a                                         ;#6B43: 77
        inc     hl                                             ;#6B44: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_1            ;#6B45: 11 AA 6E
        ld      (hl),e                                         ;#6B48: 73
        inc     hl                                             ;#6B49: 23
        ld      (hl),d                                         ;#6B4A: 72
        inc     hl                                             ;#6B4B: 23
        inc     de                                             ;#6B4C: 13
        ld      a,(de)                                         ;#6B4D: 1A
        ld      (hl),a                                         ;#6B4E: 77
        inc     hl                                             ;#6B4F: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_0            ;#6B50: 11 A8 6E
        ld      (hl),e                                         ;#6B53: 73
        inc     hl                                             ;#6B54: 23
        ld      (hl),d                                         ;#6B55: 72
        inc     hl                                             ;#6B56: 23
        inc     de                                             ;#6B57: 13
        ld      a,(de)                                         ;#6B58: 1A
        ld      (hl),a                                         ;#6B59: 77
        inc     hl                                             ;#6B5A: 23
        ret                                                    ;#6B5B: C9

SOUND_ADVANCE_NOTE_DURATION:
        ; Decrement note-duration counter; on rollover, advance to next note byte
        inc     hl                                             ;#6B5C: 23
        ld      e,(hl)                                         ;#6B5D: 5E
        inc     hl                                             ;#6B5E: 23
        ld      d,(hl)                                         ;#6B5F: 56
        inc     hl                                             ;#6B60: 23
        dec     (hl)                                           ;#6B61: 35
        jr      nz,SOUND_ADVANCE_TAIL                          ;#6B62: 20 0C
        inc     de                                             ;#6B64: 13
        inc     de                                             ;#6B65: 13
        inc     de                                             ;#6B66: 13
        ld      a,(de)                                         ;#6B67: 1A
        dec     de                                             ;#6B68: 1B
        ld      (hl),a                                         ;#6B69: 77
        dec     hl                                             ;#6B6A: 2B
        ld      (hl),d                                         ;#6B6B: 72
        dec     hl                                             ;#6B6C: 2B
        ld      (hl),e                                         ;#6B6D: 73
        inc     hl                                             ;#6B6E: 23
        inc     hl                                             ;#6B6F: 23
SOUND_ADVANCE_TAIL:
        ; Common tail of SOUND_ADVANCE_NOTE_DURATION: ret nz
        ld      a,(de)                                         ;#6B70: 1A
        inc     a                                              ;#6B71: 3C
        ret     z                                              ;#6B72: C8
        dec     a                                              ;#6B73: 3D
        ld      de,NOTE_PERIOD_TABLE                           ;#6B74: 11 93 70
        add     a,e                                            ;#6B77: 83
        ld      e,a                                            ;#6B78: 5F
        ld      a,0                                            ;#6B79: 3E 00
        adc     a,d                                            ;#6B7B: 8A
        ld      d,a                                            ;#6B7C: 57
        ld      a,(de)                                         ;#6B7D: 1A
        ld      c,a                                            ;#6B7E: 4F
        inc     de                                             ;#6B7F: 13
        ld      a,(de)                                         ;#6B80: 1A
        ld      b,a                                            ;#6B81: 47
        ld      (PSG_MIRROR),bc                                ;#6B82: ED 43 00 E5
        ld      a,0Ch                                          ;#6B86: 3E 0C
        ld      (PSG_MIRROR_VOL_A),a                           ;#6B88: 32 08 E5
        inc     hl                                             ;#6B8B: 23
        ld      e,(hl)                                         ;#6B8C: 5E
        inc     hl                                             ;#6B8D: 23
        ld      d,(hl)                                         ;#6B8E: 56
        inc     hl                                             ;#6B8F: 23
        dec     (hl)                                           ;#6B90: 35
        jr      nz,SOUND_B_LOAD_PITCH                          ;#6B91: 20 0C
        inc     de                                             ;#6B93: 13
        inc     de                                             ;#6B94: 13
        inc     de                                             ;#6B95: 13
        ld      a,(de)                                         ;#6B96: 1A
        dec     de                                             ;#6B97: 1B
        ld      (hl),a                                         ;#6B98: 77
        dec     hl                                             ;#6B99: 2B
        ld      (hl),d                                         ;#6B9A: 72
        dec     hl                                             ;#6B9B: 2B
        ld      (hl),e                                         ;#6B9C: 73
        inc     hl                                             ;#6B9D: 23
        inc     hl                                             ;#6B9E: 23
SOUND_B_LOAD_PITCH:
        ; After advance: look up channel-B note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#6B9F: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6BA0: 11 93 70
        add     a,e                                            ;#6BA3: 83
        ld      e,a                                            ;#6BA4: 5F
        ld      a,0                                            ;#6BA5: 3E 00
        adc     a,d                                            ;#6BA7: 8A
        ld      d,a                                            ;#6BA8: 57
        ld      a,(de)                                         ;#6BA9: 1A
        ld      c,a                                            ;#6BAA: 4F
        inc     de                                             ;#6BAB: 13
        ld      a,(de)                                         ;#6BAC: 1A
        ld      b,a                                            ;#6BAD: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#6BAE: ED 43 02 E5
        ld      a,0Ch                                          ;#6BB2: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#6BB4: 32 09 E5
        inc     hl                                             ;#6BB7: 23
        ld      e,(hl)                                         ;#6BB8: 5E
        inc     hl                                             ;#6BB9: 23
        ld      d,(hl)                                         ;#6BBA: 56
        inc     hl                                             ;#6BBB: 23
        dec     (hl)                                           ;#6BBC: 35
        jr      nz,SOUND_C_LOAD_PITCH                          ;#6BBD: 20 0C
        inc     de                                             ;#6BBF: 13
        inc     de                                             ;#6BC0: 13
        inc     de                                             ;#6BC1: 13
        ld      a,(de)                                         ;#6BC2: 1A
        dec     de                                             ;#6BC3: 1B
        ld      (hl),a                                         ;#6BC4: 77
        dec     hl                                             ;#6BC5: 2B
        ld      (hl),d                                         ;#6BC6: 72
        dec     hl                                             ;#6BC7: 2B
        ld      (hl),e                                         ;#6BC8: 73
        inc     hl                                             ;#6BC9: 23
        inc     hl                                             ;#6BCA: 23
SOUND_C_LOAD_PITCH:
        ; After advance: look up channel-C note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#6BCB: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6BCC: 11 93 70
        add     a,e                                            ;#6BCF: 83
        ld      e,a                                            ;#6BD0: 5F
        ld      a,0                                            ;#6BD1: 3E 00
        adc     a,d                                            ;#6BD3: 8A
        ld      d,a                                            ;#6BD4: 57
        ld      a,(de)                                         ;#6BD5: 1A
        ld      c,a                                            ;#6BD6: 4F
        inc     de                                             ;#6BD7: 13
        ld      a,(de)                                         ;#6BD8: 1A
        ld      b,a                                            ;#6BD9: 47
        ld      (PSG_MIRROR_PITCH_C),bc                        ;#6BDA: ED 43 04 E5
        ld      a,0Ch                                          ;#6BDE: 3E 0C
        ld      (PSG_MIRROR_VOL_C),a                           ;#6BE0: 32 0A E5
        ret                                                    ;#6BE3: C9

MUSIC_THEME_RESTART:
        ; Stream end: bump SOUND_STATE_THEME index; restart substream 0/1/2
        ld      hl,SOUND_STATE_THEME                           ;#6BE4: 21 10 E5
        inc     hl                                             ;#6BE7: 23
        inc     (hl)                                           ;#6BE8: 34
        ld      a,(hl)                                         ;#6BE9: 7E
        cp      3                                              ;#6BEA: FE 03
        jr      z,MUSIC_THEME_REPICK                           ;#6BEC: 28 2B
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#6BEE: 11 CF 6D
        inc     hl                                             ;#6BF1: 23
        ld      (hl),e                                         ;#6BF2: 73
        inc     hl                                             ;#6BF3: 23
        ld      (hl),d                                         ;#6BF4: 72
        inc     de                                             ;#6BF5: 13
        ld      a,(de)                                         ;#6BF6: 1A
        inc     hl                                             ;#6BF7: 23
        ld      (hl),a                                         ;#6BF8: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6BF9: 11 3F 6D
        inc     hl                                             ;#6BFC: 23
        ld      (hl),e                                         ;#6BFD: 73
        inc     hl                                             ;#6BFE: 23
        ld      (hl),d                                         ;#6BFF: 72
        inc     hl                                             ;#6C00: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE0_2                ;#6C01: 11 10 6E
        ld      (hl),e                                         ;#6C04: 73
        inc     hl                                             ;#6C05: 23
        ld      (hl),d                                         ;#6C06: 72
        inc     hl                                             ;#6C07: 23
        inc     de                                             ;#6C08: 13
        ld      a,(de)                                         ;#6C09: 1A
        ld      (hl),a                                         ;#6C0A: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C0B: 11 FF 6C
        inc     hl                                             ;#6C0E: 23
        ld      (hl),e                                         ;#6C0F: 73
        inc     hl                                             ;#6C10: 23
        ld      (hl),d                                         ;#6C11: 72
        inc     de                                             ;#6C12: 13
        inc     hl                                             ;#6C13: 23
        ld      a,(de)                                         ;#6C14: 1A
        ld      (hl),a                                         ;#6C15: 77
        jp      SOUND_TICK_MUSIC_THEME                         ;#6C16: C3 75 6C

MUSIC_THEME_REPICK:
        ; After substream 3: call PICK_MUSIC_STREAM then re-enter SOUND_TICK_MUSIC_THEME
        call    PICK_MUSIC_STREAM                              ;#6C19: CD 20 6C
        jp      SOUND_TICK_MUSIC_THEME                         ;#6C1C: C3 75 6C

MUSIC_THEME_REFRESH_HEAD:
        ; Substream 0 head refresh: clear state and re-seed (used after silence/start)
        inc     hl                                             ;#6C1F: 23
PICK_MUSIC_STREAM:
        ; Select music data stream for SOUND_TICK_MUSIC_THEME based on STAGE_PALETTE_INDEX
        xor     a                                              ;#6C20: AF
        ld      (hl),a                                         ;#6C21: 77
        ld      a,(STAGE_PALETTE_INDEX)                        ;#6C22: 3A B0 E0
        cpl                                                    ;#6C25: 2F
        and     3                                              ;#6C26: E6 03
        jp      z,MUSIC_THEME_PICK_VARIANT                     ;#6C28: CA 50 6C
        ld      de,MUSIC_THEME_VOICE0_BASELINE                 ;#6C2B: 11 05 6F
        inc     hl                                             ;#6C2E: 23
        ld      (hl),e                                         ;#6C2F: 73
        inc     hl                                             ;#6C30: 23
        ld      (hl),d                                         ;#6C31: 72
        inc     de                                             ;#6C32: 13
        ld      a,(de)                                         ;#6C33: 1A
        inc     hl                                             ;#6C34: 23
        ld      (hl),a                                         ;#6C35: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C36: 11 3F 6D
        inc     hl                                             ;#6C39: 23
        ld      (hl),e                                         ;#6C3A: 73
        inc     hl                                             ;#6C3B: 23
        ld      (hl),d                                         ;#6C3C: 72
        inc     hl                                             ;#6C3D: 23
        ld      de,MUSIC_THEME_VOICE1_BASELINE                 ;#6C3E: 11 8A 6F
        ld      (hl),e                                         ;#6C41: 73
        inc     hl                                             ;#6C42: 23
        ld      (hl),d                                         ;#6C43: 72
        inc     hl                                             ;#6C44: 23
        inc     de                                             ;#6C45: 13
        ld      a,(de)                                         ;#6C46: 1A
        ld      (hl),a                                         ;#6C47: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C48: 11 FF 6C
        inc     hl                                             ;#6C4B: 23
        ld      (hl),e                                         ;#6C4C: 73
        inc     hl                                             ;#6C4D: 23
        ld      (hl),d                                         ;#6C4E: 72
        ret                                                    ;#6C4F: C9

MUSIC_THEME_PICK_VARIANT:
        ; Pick the substream variant based on STAGE_PALETTE_INDEX bits
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#6C50: 11 CF 6D
        inc     hl                                             ;#6C53: 23
        ld      (hl),e                                         ;#6C54: 73
        inc     hl                                             ;#6C55: 23
        ld      (hl),d                                         ;#6C56: 72
        inc     de                                             ;#6C57: 13
        ld      a,(de)                                         ;#6C58: 1A
        inc     hl                                             ;#6C59: 23
        ld      (hl),a                                         ;#6C5A: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C5B: 11 3F 6D
        inc     hl                                             ;#6C5E: 23
        ld      (hl),e                                         ;#6C5F: 73
        inc     hl                                             ;#6C60: 23
        ld      (hl),d                                         ;#6C61: 72
        inc     hl                                             ;#6C62: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE1                  ;#6C63: 11 40 6E
        ld      (hl),e                                         ;#6C66: 73
        inc     hl                                             ;#6C67: 23
        ld      (hl),d                                         ;#6C68: 72
        inc     hl                                             ;#6C69: 23
        inc     de                                             ;#6C6A: 13
        ld      a,(de)                                         ;#6C6B: 1A
        ld      (hl),a                                         ;#6C6C: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C6D: 11 FF 6C
        inc     hl                                             ;#6C70: 23
        ld      (hl),e                                         ;#6C71: 73
        inc     hl                                             ;#6C72: 23
        ld      (hl),d                                         ;#6C73: 72
        ret                                                    ;#6C74: C9

SOUND_TICK_MUSIC_THEME:
        ; Music channel A tick; state at SOUND_STATE_THEME, writes PSG R0/R1
        ld      hl,SOUND_STATE_THEME                           ;#6C75: 21 10 E5
        ld      a,(hl)                                         ;#6C78: 7E
        and     a                                              ;#6C79: A7
        jp      z,MUSIC_THEME_REFRESH_HEAD                     ;#6C7A: CA 1F 6C
        inc     hl                                             ;#6C7D: 23
        inc     hl                                             ;#6C7E: 23
        ld      e,(hl)                                         ;#6C7F: 5E
        inc     hl                                             ;#6C80: 23
        ld      d,(hl)                                         ;#6C81: 56
        inc     hl                                             ;#6C82: 23
        ld      a,(hl)                                         ;#6C83: 7E
        dec     (hl)                                           ;#6C84: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH                      ;#6C85: 20 15
        inc     de                                             ;#6C87: 13
        inc     de                                             ;#6C88: 13
        inc     de                                             ;#6C89: 13
        ld      a,(de)                                         ;#6C8A: 1A
        ld      (hl),a                                         ;#6C8B: 77
        dec     de                                             ;#6C8C: 1B
        dec     hl                                             ;#6C8D: 2B
        ld      (hl),d                                         ;#6C8E: 72
        dec     hl                                             ;#6C8F: 2B
        ld      (hl),e                                         ;#6C90: 73
        inc     hl                                             ;#6C91: 23
        inc     hl                                             ;#6C92: 23
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C93: 11 3F 6D
        inc     hl                                             ;#6C96: 23
        ld      (hl),e                                         ;#6C97: 73
        inc     hl                                             ;#6C98: 23
        ld      (hl),d                                         ;#6C99: 72
        dec     hl                                             ;#6C9A: 2B
        dec     hl                                             ;#6C9B: 2B
MUSIC_THEME_LOAD_PITCH:
        ; MUSIC_THEME tick: look up pitch byte from current stream
        ld      a,(de)                                         ;#6C9C: 1A
        cp      0FFh                                           ;#6C9D: FE FF
        jp      z,MUSIC_THEME_RESTART                          ;#6C9F: CA E4 6B
        ld      de,NOTE_PERIOD_TABLE                           ;#6CA2: 11 93 70
        add     a,e                                            ;#6CA5: 83
        ld      e,a                                            ;#6CA6: 5F
        ld      a,0                                            ;#6CA7: 3E 00
        adc     a,d                                            ;#6CA9: 8A
        ld      d,a                                            ;#6CAA: 57
        ld      a,(de)                                         ;#6CAB: 1A
        ld      c,a                                            ;#6CAC: 4F
        inc     de                                             ;#6CAD: 13
        ld      a,(de)                                         ;#6CAE: 1A
        ld      b,a                                            ;#6CAF: 47
        ld      (PSG_MIRROR),bc                                ;#6CB0: ED 43 00 E5
        inc     hl                                             ;#6CB4: 23
        ld      e,(hl)                                         ;#6CB5: 5E
        inc     hl                                             ;#6CB6: 23
        ld      d,(hl)                                         ;#6CB7: 56
        ld      a,(de)                                         ;#6CB8: 1A
        inc     de                                             ;#6CB9: 13
        ld      (hl),d                                         ;#6CBA: 72
        dec     hl                                             ;#6CBB: 2B
        ld      (hl),e                                         ;#6CBC: 73
        ld      (PSG_MIRROR_VOL_A),a                           ;#6CBD: 32 08 E5
        inc     hl                                             ;#6CC0: 23
        inc     hl                                             ;#6CC1: 23
        ld      e,(hl)                                         ;#6CC2: 5E
        inc     hl                                             ;#6CC3: 23
        ld      d,(hl)                                         ;#6CC4: 56
        inc     hl                                             ;#6CC5: 23
        ld      a,(hl)                                         ;#6CC6: 7E
        dec     (hl)                                           ;#6CC7: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH_B                    ;#6CC8: 20 15
        inc     de                                             ;#6CCA: 13
        inc     de                                             ;#6CCB: 13
        inc     de                                             ;#6CCC: 13
        ld      a,(de)                                         ;#6CCD: 1A
        ld      (hl),a                                         ;#6CCE: 77
        dec     de                                             ;#6CCF: 1B
        dec     hl                                             ;#6CD0: 2B
        ld      (hl),d                                         ;#6CD1: 72
        dec     hl                                             ;#6CD2: 2B
        ld      (hl),e                                         ;#6CD3: 73
        inc     hl                                             ;#6CD4: 23
        inc     hl                                             ;#6CD5: 23
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6CD6: 11 FF 6C
        inc     hl                                             ;#6CD9: 23
        ld      (hl),e                                         ;#6CDA: 73
        inc     hl                                             ;#6CDB: 23
        ld      (hl),d                                         ;#6CDC: 72
        dec     hl                                             ;#6CDD: 2B
        dec     hl                                             ;#6CDE: 2B
MUSIC_THEME_LOAD_PITCH_B:
        ; MUSIC_THEME second-voice: look up pitch byte from second stream
        ld      a,(de)                                         ;#6CDF: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6CE0: 11 93 70
        add     a,e                                            ;#6CE3: 83
        ld      e,a                                            ;#6CE4: 5F
        ld      a,0                                            ;#6CE5: 3E 00
        adc     a,d                                            ;#6CE7: 8A
        ld      d,a                                            ;#6CE8: 57
        ld      a,(de)                                         ;#6CE9: 1A
        ld      c,a                                            ;#6CEA: 4F
        inc     de                                             ;#6CEB: 13
        ld      a,(de)                                         ;#6CEC: 1A
        ld      b,a                                            ;#6CED: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#6CEE: ED 43 02 E5
        inc     hl                                             ;#6CF2: 23
        ld      e,(hl)                                         ;#6CF3: 5E
        inc     hl                                             ;#6CF4: 23
        ld      d,(hl)                                         ;#6CF5: 56
        ld      a,(de)                                         ;#6CF6: 1A
        inc     de                                             ;#6CF7: 13
        ld      (hl),d                                         ;#6CF8: 72
        dec     hl                                             ;#6CF9: 2B
        ld      (hl),e                                         ;#6CFA: 73
        ld      (PSG_MIRROR_VOL_B),a                           ;#6CFB: 32 09 E5
        ret                                                    ;#6CFE: C9

SOUND_ENVELOPE_TABLE:
        ; Initial sound envelope/volume curve
        dh      "0B0B0B0B0B0B0A0A0909080807070707"             ;#6CFF: 0B 0B 0B 0B 0B 0B 0A 0A 09 09 08 08 07 07 07 07
        dh      "07070707060605050504040404030303"             ;#6D0F: 07 07 07 07 06 06 05 05 05 04 04 04 04 03 03 03
        dh      "03030202020202020101010101010101"             ;#6D1F: 03 03 02 02 02 02 02 02 01 01 01 01 01 01 01 01
        dh      "01010101010101000000000000000000"             ;#6D2F: 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00 00

MUSIC_THEME_DURATIONS:
        ; Sound sub-table (referenced from music tick advance)
        dh      "0A0A0909070705050000000000000000"             ;#6D3F: 0A 0A 09 09 07 07 05 05 00 00 00 00 00 00 00 00

SFX_SMOKE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_SMOKE)
        dh      "0C0C0C0C0C0C0C0C0C0C0C0C00000000"             ;#6D4F: 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 00 00 00 00

SFX_C_STAGE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BANG/5)
        dh      "0F0D0B0A0A0A0A0A0A09080706050403"             ;#6D5F: 0F 0D 0B 0A 0A 0A 0A 0A 0A 09 08 07 06 05 04 03
        dh      "02010000000000000000000000000000"             ;#6D6F: 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00

SFX_BANG_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BONUS)
        dh      "080E0D0C0B0B0B0B0B0B0B0B0B0B0B0B"             ;#6D7F: 08 0E 0D 0C 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B
        dh      "0A0A0A0A0A0A0A0A0A0A090909090909"             ;#6D8F: 0A 0A 0A 0A 0A 0A 0A 0A 0A 0A 09 09 09 09 09 09
        dh      "09090909080808080808080808080707"             ;#6D9F: 09 09 09 09 08 08 08 08 08 08 08 08 08 08 07 07
        dh      "07070707070707070606060606060606"             ;#6DAF: 07 07 07 07 07 07 07 07 06 06 06 06 06 06 06 06
        dh      "060605050505050505050505040302FF"             ;#6DBF: 06 06 05 05 05 05 05 05 05 05 05 05 04 03 02 FF

MUSIC_THEME_VARIANT_VOICE0:
        ; Sound sub-table (referenced from music note advance)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#6DCF: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DD1: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DD3: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DD5: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DD7: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DD9: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DDB: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DDD: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DDF: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DE1: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DE3: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DE5: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DE7: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DE9: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DEB: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DED: 38 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DEF: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DF1: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DF3: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DF5: 2A 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DF7: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DF9: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DFB: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DFD: 2A 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DFF: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6E01: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E03: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E05: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6E07: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6E09: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E0B: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E0D: 38 0C
        db      0FFh    ; substream end                        ;#6E0F: FF

MUSIC_THEME_VARIANT_VOICE0_2:
        ; Voice-0 2nd substream (after FF 6E0Fh); MUSIC_THEME_RESTART ptr
        NOTE    note=NOTE_O5_D, duration=19h                   ;#6E10: 5E 19
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E12: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6E14: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#6E16: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E18: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6E1A: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#6E1C: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E1E: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E20: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E22: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E24: 4A 0C
        NOTE    note=NOTE_O4_G, duration=30h                   ;#6E26: 50 30
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E28: 4A 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E2A: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E2C: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E2E: 50 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E30: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E32: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E34: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E36: 54 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E38: 58 0C
        NOTE    note=NOTE_O4_G, duration=18h                   ;#6E3A: 50 18
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E3C: 4A 0C
        NOTE    note=NOTE_O4_D, duration=30h                   ;#6E3E: 46 30

MUSIC_THEME_VARIANT_VOICE1:
        ; Sound sub-table
        NOTE    note=NOTE_O4_G, duration=0Dh                   ;#6E40: 50 0D
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#6E42: 4C 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E44: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E46: 50 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#6E48: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E4A: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E4C: 42 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E4E: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E50: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E52: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E54: 38 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E56: 42 0C
        NOTE    note=NOTE_O3_B, duration=0Ch                   ;#6E58: 40 0C
        NOTE    note=NOTE_O3_G, duration=24h                   ;#6E5A: 38 24
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E5C: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E5E: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E60: 38 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#6E62: 34 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E64: 38 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E66: 3E 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E68: 42 0C
        NOTE    note=NOTE_O4_C_SHARP, duration=0Ch             ;#6E6A: 44 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E6C: 46 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#6E6E: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E70: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E72: 42 0C
        NOTE    note=NOTE_O3_B, duration=30h                   ;#6E74: 40 30
        db      4,4,0Eh    ; last note pair + orphan byte (song ends via voice-0 FF) ;#6E76: 04 04 0E

SFX_FLAG_STREAM_FLAG_GET:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_C                             ;#6E79: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E7A: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E7B: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E7C: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E7D: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E7E: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E7F: 78
        SINGLE_NOTE note=NOTE_O5_C                             ;#6E80: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E81: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E82: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E83: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E84: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E85: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E86: 78

SFX_FLAG_STREAM_BASE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E87: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E88: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E89: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E8A: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E8B: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E8C: 78
        SINGLE_NOTE note=NOTE_O6_F                             ;#6E8D: 7C
        db      0FFh    ; end of stream                        ;#6E8E: FF

SFX_SMOKE_STREAM:
        ; Smoke SFX note stream (SFX_SMOKE); loaded by SFX_FLAG_CHECK_SMOKE at 6AC5h
        SINGLE_NOTE note=NOTE_O2_A_SHARP                       ;#6E8F: 26
        SINGLE_NOTE note=NOTE_O2_B                             ;#6E90: 28
        SINGLE_NOTE note=NOTE_O3_C                             ;#6E91: 2A
        SINGLE_NOTE note=NOTE_O3_C_SHARP                       ;#6E92: 2C
        db      0FFh    ; end of stream                        ;#6E93: FF

SFX_FLAG_STREAM_FUEL_LOW:
        ; SFX sub-stream (fuel-low warning beep)
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E94: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E95: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E96: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E97: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E98: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E99: 44
        db      0FFh    ; end of stream                        ;#6E9A: FF

SFX_FLAG_STREAM_EXTRA_LIFE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E9B: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E9C: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E9D: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E9E: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E9F: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6EA0: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6EA1: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6EA2: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6EA3: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6EA4: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6EA5: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6EA6: 76
        db      0FFh    ; end of stream                        ;#6EA7: FF

MUSIC_STAGE_CLEAR_STREAM_VOICE_0:
        ; Music channel C voice 0 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#6EA8: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_1:
        ; Music channel C voice 1 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#6EAA: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_2:
        ; Music channel C voice 2 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=9                     ;#6EAC: 00 09
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#6EAE: 56 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6EB0: 5E 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#6EB2: 64 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#6EB4: 5A 0C
        NOTE    note=NOTE_O5_D_SHARP, duration=0Ch             ;#6EB6: 60 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6EB8: 5E 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=0Ch             ;#6EBA: 6E 0C
        NOTE    note=NOTE_REST, duration=10h                   ;#6EBC: 00 10
        db      0FFh    ; substream end                        ;#6EBE: FF

SFX_BONUS_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_BONUS)
        NOTE    note=NOTE_O5_G, duration=1                     ;#6EBF: 68 01
        NOTE    note=NOTE_O5_A, duration=5                     ;#6EC1: 6C 05
        NOTE    note=NOTE_O5_B, duration=5                     ;#6EC3: 70 05
        NOTE    note=NOTE_O6_C, duration=5                     ;#6EC5: 72 05
        NOTE    note=NOTE_O6_D, duration=5                     ;#6EC7: 76 05
        NOTE    note=NOTE_O6_E, duration=5                     ;#6EC9: 7A 05
        NOTE    note=NOTE_O6_F_SHARP, duration=5               ;#6ECB: 7E 05
        NOTE    note=NOTE_O6_G, duration=5                     ;#6ECD: 80 05
        db      0FFh    ; substream end                        ;#6ECF: FF

SFX_C_STAGE_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_C_STAGE)
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6ED0: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#6ED2: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#6ED4: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#6ED6: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#6ED8: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6EDA: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6EDC: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EDE: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6EE0: 34 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EE2: 38 06
        NOTE    note=NOTE_REST, duration=6                     ;#6EE4: 00 06
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6EE6: 3E 0C
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EE8: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6EEA: 34 06
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6EEC: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#6EEE: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#6EF0: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#6EF2: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#6EF4: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6EF6: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6EF8: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EFA: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6EFC: 34 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6EFE: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6F00: 2E 06
        NOTE    note=NOTE_O2_A_SHARP, duration=0Ch             ;#6F02: 26 0C
        db      0FFh    ; substream end                        ;#6F04: FF

MUSIC_THEME_VOICE0_BASELINE:
        ; Music data stream (channel A track)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#6F05: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F07: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F09: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F0B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F0D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F0F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F11: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F13: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F15: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F17: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F19: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F1B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F1D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F1F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F21: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F23: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F25: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F27: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F29: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F2B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F2D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F2F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F31: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F33: 38 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F35: 16 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F37: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F39: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F3B: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F3D: 2E 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F3F: 16 0C
        NOTE    note=NOTE_O2_E, duration=0Ch                   ;#6F41: 1A 0C
        NOTE    note=NOTE_O2_F_SHARP, duration=0Ch             ;#6F43: 1E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F45: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F47: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F49: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F4B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F4D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F4F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F51: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F53: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F55: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F57: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F59: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F5B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F5D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F5F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F61: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F63: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F65: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F67: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F69: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F6B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F6D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F6F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F71: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F73: 38 0C
        NOTE    note=NOTE_O2_C, duration=1                     ;#6F75: 12 01
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6F77: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6F79: 2A 0C
        NOTE    note=NOTE_O2_D, duration=1                     ;#6F7B: 16 01
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F7D: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F7F: 2E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F81: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F83: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F85: 38 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6F87: 00 0C
        db      0FFh    ; substream end                        ;#6F89: FF

MUSIC_THEME_VOICE1_BASELINE:
        ; Music data stream (channel A alt)
        NOTE    note=NOTE_O4_G, duration=0Bh                   ;#6F8A: 50 0B
        NOTE    note=NOTE_REST, duration=2                     ;#6F8C: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F8E: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6F90: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6F92: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F94: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6F96: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#6F98: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6F9A: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6F9C: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F9E: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FA0: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FA2: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FA4: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6FA6: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#6FA8: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FAA: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FAC: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FAE: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FB0: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FB2: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FB4: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#6FB6: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#6FB8: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#6FBA: 5C 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6FBC: 5E 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FBE: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FC0: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FC2: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FC4: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FC6: 5C 06
        NOTE    note=NOTE_O5_D, duration=4                     ;#6FC8: 5E 04
        NOTE    note=NOTE_REST, duration=2                     ;#6FCA: 00 02
        NOTE    note=NOTE_O5_D, duration=14h                   ;#6FCC: 5E 14
        NOTE    note=NOTE_REST, duration=4                     ;#6FCE: 00 04
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FD0: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#6FD2: 5A 06
        NOTE    note=NOTE_O4_B, duration=6                     ;#6FD4: 58 06
        NOTE    note=NOTE_O4_A, duration=6                     ;#6FD6: 54 06
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FD8: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FDA: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FDC: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FDE: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FE0: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FE2: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6FE4: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#6FE6: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FE8: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FEA: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FEC: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FEE: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FF0: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FF2: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6FF4: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#6FF6: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FF8: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FFA: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FFC: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FFE: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#7000: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#7002: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#7004: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#7006: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#7008: 5C 0C
        NOTE    note=NOTE_O5_G, duration=0Ch                   ;#700A: 68 0C
        NOTE    note=NOTE_O5_D, duration=6                     ;#700C: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#700E: 5A 06
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#7010: 56 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#7012: 50 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#7014: 4C 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#7016: 4E 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#7018: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#701A: 00 0C

MUSIC_OPENING_VOICE_2:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=0Dh                   ;#701C: 5A 0D
        NOTE    note=NOTE_O5_D, duration=4                     ;#701E: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#7020: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#7022: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#7024: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#7026: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#7028: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#702A: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#702C: 64 0C
        NOTE    note=NOTE_O5_G_SHARP, duration=10h             ;#702E: 6A 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#7030: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#7032: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#7034: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#7036: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#7038: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#703A: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#703C: 64 04
        NOTE    note=NOTE_O5_A, duration=0Ch                   ;#703E: 6C 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#7040: 6E 04
        NOTE    note=NOTE_O6_C, duration=0Ch                   ;#7042: 72 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#7044: 6E 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#7046: 6A 0C
        NOTE    note=NOTE_O5_F, duration=4                     ;#7048: 64 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#704A: 6A 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#704C: 64 0C

MUSIC_OPENING_VOICE_1:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=1Dh                   ;#704E: 5A 1D
        NOTE    note=NOTE_O4_A, duration=10h                   ;#7050: 54 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#7052: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#7054: 5A 1C
        NOTE    note=NOTE_O4_G_SHARP, duration=10h             ;#7056: 52 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#7058: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#705A: 5A 1C
        NOTE    note=NOTE_O4_A, duration=10h                   ;#705C: 54 10
        NOTE    note=NOTE_O4_F, duration=10h                   ;#705E: 4C 10
        NOTE    note=NOTE_O5_C, duration=4                     ;#7060: 5A 04
        NOTE    note=NOTE_O4_G_SHARP, duration=0Ch             ;#7062: 52 0C
        NOTE    note=NOTE_O4_F, duration=4                     ;#7064: 4C 04
        NOTE    note=NOTE_O4_D_SHARP, duration=0Ch             ;#7066: 48 0C
        NOTE    note=NOTE_O4_C, duration=4                     ;#7068: 42 04
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#706A: 4A 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#706C: 4C 0C

MUSIC_OPENING_VOICE_0:
        ; Music data stream (channel B/C)
        NOTE    note=NOTE_O2_F, duration=11h                   ;#706E: 1C 11
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7070: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7072: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7074: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7076: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7078: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#707A: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#707C: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#707E: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7080: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7082: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7084: 34 10
        NOTE    note=NOTE_O1_A_SHARP, duration=0Ch             ;#7086: 0E 0C
        NOTE    note=NOTE_O2_A_SHARP, duration=4               ;#7088: 26 04
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#708A: 12 0C
        NOTE    note=NOTE_O3_C, duration=4                     ;#708C: 2A 04
        NOTE    note=NOTE_O2_F, duration=0Ch                   ;#708E: 1C 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#7090: 34 0C
        db      0FFh    ; substream end                        ;#7092: FF

NOTE_PERIOD_TABLE:
        ; PSG tone-period entries (73 x 2 bytes) indexed by note byte
        ; NOTE_PERIOD_TABLE — 73 entries x 2 bytes (146 bytes total). Indexed by note
        ; byte from music data streams. Each 16-bit entry is a PSG tone-period value
        ; (12-bit; high 4 bits ignored by PSG). Covers ~6 octaves of musical pitch
        ; range.
        dw      0     ; rest                                   ;#7093: 00 00
        dw      0A88h  ;    41.5 Hz  O1 E                      ;#7095: 88 0A
        dw      9F0h   ;    44.0 Hz  O1 F                      ;#7097: F0 09
        dw      960h   ;    46.6 Hz  O1 F#                     ;#7099: 60 09
        dw      8DCh   ;    49.3 Hz  O1 G                      ;#709B: DC 08
        dw      85Ch   ;    52.3 Hz  O1 G#                     ;#709D: 5C 08
        dw      7E4h   ;    55.4 Hz  O1 A                      ;#709F: E4 07
        dw      770h   ;    58.8 Hz  O1 A#                     ;#70A1: 70 07
        dw      708h   ;    62.1 Hz  O1 B                      ;#70A3: 08 07
        dw      6A0h   ;    66.0 Hz  O2 C                      ;#70A5: A0 06
        dw      644h   ;    69.7 Hz  O2 C#                     ;#70A7: 44 06
        dw      5E8h   ;    74.0 Hz  O2 D                      ;#70A9: E8 05
        dw      594h   ;    78.3 Hz  O2 D#                     ;#70AB: 94 05
        dw      544h   ;    83.0 Hz  O2 E                      ;#70AD: 44 05
        dw      4F8h   ;    87.9 Hz  O2 F                      ;#70AF: F8 04
        dw      4B0h   ;    93.2 Hz  O2 F#                     ;#70B1: B0 04
        dw      46Eh   ;    98.6 Hz  O2 G                      ;#70B3: 6E 04
        dw      42Eh   ;   104.5 Hz  O2 G#                     ;#70B5: 2E 04
        dw      3F2h   ;   110.8 Hz  O2 A                      ;#70B7: F2 03
        dw      3B8h   ;   117.5 Hz  O2 A#                     ;#70B9: B8 03
        dw      384h   ;   124.3 Hz  O2 B                      ;#70BB: 84 03
        dw      350h   ;   131.9 Hz  O3 C                      ;#70BD: 50 03
        dw      322h   ;   139.5 Hz  O3 C#                     ;#70BF: 22 03
        dw      2F4h   ;   148.0 Hz  O3 D                      ;#70C1: F4 02
        dw      2CAh   ;   156.7 Hz  O3 D#                     ;#70C3: CA 02
        dw      2A2h   ;   166.0 Hz  O3 E                      ;#70C5: A2 02
        dw      27Ch   ;   175.9 Hz  O3 F                      ;#70C7: 7C 02
        dw      258h   ;   186.4 Hz  O3 F#                     ;#70C9: 58 02
        dw      237h   ;   197.3 Hz  O3 G                      ;#70CB: 37 02
        dw      217h   ;   209.1 Hz  O3 G#                     ;#70CD: 17 02
        dw      1F9h   ;   221.5 Hz  O3 A                      ;#70CF: F9 01
        dw      1DCh   ;   235.0 Hz  O3 A#                     ;#70D1: DC 01
        dw      1C2h   ;   248.6 Hz  O3 B                      ;#70D3: C2 01
        dw      1A8h   ;   263.8 Hz  O4 C                      ;#70D5: A8 01
        dw      191h   ;   279.0 Hz  O4 C#                     ;#70D7: 91 01
        dw      17Ah   ;   295.9 Hz  O4 D                      ;#70D9: 7A 01
        dw      165h   ;   313.3 Hz  O4 D#                     ;#70DB: 65 01
        dw      151h   ;   331.9 Hz  O4 E                      ;#70DD: 51 01
        dw      13Eh   ;   351.8 Hz  O4 F                      ;#70DF: 3E 01
        dw      12Ch   ;   372.9 Hz  O4 F#                     ;#70E1: 2C 01
        dw      11Bh   ;   395.3 Hz  O4 G                      ;#70E3: 1B 01
        dw      10Bh   ;   419.0 Hz  O4 G#                     ;#70E5: 0B 01
        dw      0FCh   ;   443.9 Hz  O4 A                      ;#70E7: FC 00
        dw      0EEh   ;   470.0 Hz  O4 A#                     ;#70E9: EE 00
        dw      0E1h   ;   497.2 Hz  O4 B                      ;#70EB: E1 00
        dw      0D4h   ;   527.6 Hz  O5 C                      ;#70ED: D4 00
        dw      0C8h   ;   559.3 Hz  O5 C#                     ;#70EF: C8 00
        dw      0BDh   ;   591.9 Hz  O5 D                      ;#70F1: BD 00
        dw      0B2h   ;   628.4 Hz  O5 D#                     ;#70F3: B2 00
        dw      0A8h   ;   665.8 Hz  O5 E                      ;#70F5: A8 00
        dw      9Fh    ;   703.5 Hz  O5 F                      ;#70F7: 9F 00
        dw      96h    ;   745.7 Hz  O5 F#                     ;#70F9: 96 00
        dw      8Dh    ;   793.3 Hz  O5 G                      ;#70FB: 8D 00
        dw      85h    ;   841.1 Hz  O5 G#                     ;#70FD: 85 00
        dw      7Eh    ;   887.8 Hz  O5 A                      ;#70FF: 7E 00
        dw      77h    ;   940.0 Hz  O5 A#                     ;#7101: 77 00
        dw      70h    ;   998.8 Hz  O5 B                      ;#7103: 70 00
        dw      6Ah    ;  1055.3 Hz  O6 C                      ;#7105: 6A 00
        dw      64h    ;  1118.6 Hz  O6 C#                     ;#7107: 64 00
        dw      5Eh    ;  1190.0 Hz  O6 D                      ;#7109: 5E 00
        dw      59h    ;  1256.9 Hz  O6 D#                     ;#710B: 59 00
        dw      54h    ;  1331.7 Hz  O6 E                      ;#710D: 54 00
        dw      4Fh    ;  1416.0 Hz  O6 F                      ;#710F: 4F 00
        dw      4Bh    ;  1491.5 Hz  O6 F#                     ;#7111: 4B 00
        dw      46h    ;  1598.0 Hz  O6 G                      ;#7113: 46 00
        dw      42h    ;  1694.9 Hz  O6 G#                     ;#7115: 42 00
        dw      3Fh    ;  1775.6 Hz  O6 A                      ;#7117: 3F 00
        dw      3Bh    ;  1895.9 Hz  O6 A#                     ;#7119: 3B 00
        dw      38h    ;  1997.5 Hz  O6 B                      ;#711B: 38 00
        dw      35h    ;  2110.6 Hz  O7 C                      ;#711D: 35 00
        dw      32h    ;  2237.2 Hz  O7 C#                     ;#711F: 32 00
        dw      2Fh    ;  2380.0 Hz  O7 D                      ;#7121: 2F 00
        dw      2Ch    ;  2542.3 Hz  O7 D#                     ;#7123: 2C 00

TICK_STAGE_TIMER:
        ; Two-stage countdown: dec E0B7, on zero reload from E0BA and dec E0B8
        ; TICK_STAGE_TIMER is the two-stage countdown: dec STAGE_TIMER_INNER
        ; (STAGE_TIMER_INNER). If non-zero, return. Else reload from STAGE_TIMER_RELOAD
        ; (STAGE_TIMER_RELOAD) and dec STAGE_TIMER_OUTER. Used as a sub-frame pacing
        ; tick by various game-flow states.
        ld      hl,STAGE_TIMER_INNER                           ;#7125: 21 B7 E0
        dec     (hl)                                           ;#7128: 35
        ret     nz                                             ;#7129: C0
        ld      a,(STAGE_TIMER_RELOAD)                         ;#712A: 3A BA E0
        ld      (hl),a                                         ;#712D: 77
TICK_FUEL_REFRESH:
        ; Dec E0B8 (reload 0Ah); on rollover, refresh fuel gauge cells
        ; TICK_FUEL_REFRESH dec STAGE_TIMER_OUTER (the outer timer) with auto-reload to
        ; 0Ah. On rollover, refreshes the fuel gauge cells in VRAM via BIOS_WRTVRM if
        ; FUEL_LEVEL is in the low range. Called from DRAIN_FUEL_* variants during
        ; stage-clear bonus animation.
        ld      hl,STAGE_TIMER_OUTER                           ;#712E: 21 B8 E0
        dec     (hl)                                           ;#7131: 35
        ret     nz                                             ;#7132: C0
        ld      (hl),0Ah                                       ;#7133: 36 0A
        inc     hl                                             ;#7135: 23
        ld      a,(hl)                                         ;#7136: 7E
        cp      0Ah                                            ;#7137: FE 0A
        jr      nc,FUEL_TICK_GATE_RUNOUT                       ;#7139: 30 2C
        and     a                                              ;#713B: A7
        ret     z                                              ;#713C: C8
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#713D: 21 9C 07
        ld      a,81h                                          ;#7140: 3E 81
        call    BIOS_WRTVRM                                    ;#7142: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#7145: 21 9D 07
        ld      a,81h                                          ;#7148: 3E 81
        call    BIOS_WRTVRM                                    ;#714A: CD 4D 00
        ld      hl,FUEL_LEVEL                                  ;#714D: 21 B9 E0
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#7150: 3A 61 E5
        and     a                                              ;#7153: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#7154: 20 11
        ld      a,(STAGE_CLEAR_FLAG)                           ;#7156: 3A AF E0
        and     a                                              ;#7159: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#715A: 20 0B
        ld      a,(PLAYER_DEAD_FLAG)                           ;#715C: 3A BB E0
        and     a                                              ;#715F: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#7160: 20 05
        ld      a,1                                            ;#7162: 3E 01
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#7164: 32 61 E5
FUEL_TICK_GATE_RUNOUT:
        ; Run-out gate: arms PLAYER_MOVE_GATE when fuel-tick timer expires
        dec     (hl)                                           ;#7167: 35
        jr      nz,UPDATE_FUEL_GAUGE                           ;#7168: 20 05
        ld      a,1                                            ;#716A: 3E 01
        ld      (PLAYER_MOVE_GATE),a                           ;#716C: 32 C5 E0
UPDATE_FUEL_GAUGE:
        ; Render 8-tile fuel bar from FUEL_LEVEL; LDIRVM to VRAM 04D7h + mirror 14D7h
        ; UPDATE_FUEL_GAUGE renders the fuel bar as 8 tile codes in
        ; FUEL_GAUGE_BUFFER-E1E7h then LDIRVMs them to VRAM 04D7h (and bank-2 mirror
        ; 14D7h). Multi-segment fill: EEh = full segment, E7h = empty, the partial
        ; segment uses an intermediate tile encoding the fractional fill.
        ld      hl,FUEL_GAUGE_BUFFER                           ;#716F: 21 E0 E1
        ld      de,FUEL_GAUGE_BUFFER_TAIL                      ;#7172: 11 E1 E1
        ld      bc,7                                           ;#7175: 01 07 00
        ld      (hl),40h                                       ;#7178: 36 40
        ldir                                                   ;#717A: ED B0
        ld      a,(FUEL_LEVEL)                                 ;#717C: 3A B9 E0
        sub     7                                              ;#717F: D6 07
        jr      nc,FUEL_BAR_SET_HEAD                           ;#7181: 30 06
        add     a,0EFh                                         ;#7183: C6 EF
        ld      (hl),a                                         ;#7185: 77
        jp      FUEL_BAR_UPLOAD                                ;#7186: C3 97 71

FUEL_BAR_SET_HEAD:
        ; Set bar head tile (EEh = full segment)
        ld      (hl),0EEh                                      ;#7189: 36 EE
FUEL_BAR_FILL_LOOP:
        ; Fill bar middle with full segments via dec hl loop
        dec     hl                                             ;#718B: 2B
        sub     8                                              ;#718C: D6 08
        jr      c,FUEL_BAR_TAIL_PARTIAL                        ;#718E: 38 04
        ld      (hl),0E7h                                      ;#7190: 36 E7
        jr      FUEL_BAR_FILL_LOOP                             ;#7192: 18 F7

FUEL_BAR_TAIL_PARTIAL:
        ; Tail partial: paint a fractional segment as the bar shrinks
        add     a,0E8h                                         ;#7194: C6 E8
        ld      (hl),a                                         ;#7196: 77
FUEL_BAR_UPLOAD:
        ; LDIRVM the 8 fuel-bar tile codes to VRAM 04D7h
        LOAD_VRAM_ADDRESS de, 4D7h                             ;#7197: 11 D7 04
        ld      hl,FUEL_GAUGE_BUFFER                           ;#719A: 21 E0 E1
        ld      bc,8                                           ;#719D: 01 08 00
        call    BIOS_LDIRVM                                    ;#71A0: CD 5C 00
        ; fuel-gauge mirror → bank-B 14D7h
        ld      hl,FUEL_GAUGE_BUFFER                           ;#71A3: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 14D7h                            ;#71A6: 11 D7 14
        ld      bc,8                                           ;#71A9: 01 08 00
        jp      BIOS_LDIRVM                                    ;#71AC: C3 5C 00

LOAD_STAGE_PARAMS:
        ; Look up per-stage parameters from STAGE_PARAM_TABLE + STAGE_DIFFICULTY_TABLE
        ; LOAD_STAGE_PARAMS reads STAGE_PALETTE_INDEX, normalizes (stages >=14h wrap to
        ; 10h-13h), and indexes STAGE_PARAM_TABLE (4-byte records) to load
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD (reload), STAGE_DIFFICULTY_INDEX
        ; (subindex), and one more byte. Then uses STAGE_DIFFICULTY_INDEX to index
        ; STAGE_DIFFICULTY_TABLE (STAGE_DIFFICULTY_TABLE), offset by STAGE_DIFFICULTY (3
        ; difficulty tiers selected at thresholds 6 and 3), loading (ENEMY_STEP_SPEED) +
        ; (SCROLL_LIMIT_LO).
        ld      a,(STAGE_PALETTE_INDEX)                        ;#71AF: 3A B0 E0
        cp      14h                                            ;#71B2: FE 14
        jr      c,LOAD_STAGE_LOOKUP                            ;#71B4: 38 04
        and     3                                              ;#71B6: E6 03
        add     a,10h                                          ;#71B8: C6 10
LOAD_STAGE_LOOKUP:
        ; Lookup row: index STAGE_PARAM_TABLE by (palette*4) and read 4 fields
        dec     a                                              ;#71BA: 3D
        add     a,a                                            ;#71BB: 87
        add     a,a                                            ;#71BC: 87
        ld      c,a                                            ;#71BD: 4F
        ld      b,0                                            ;#71BE: 06 00
        ld      hl,STAGE_PARAM_TABLE                           ;#71C0: 21 0C 72
        add     hl,bc                                          ;#71C3: 09
        ld      a,(hl)                                         ;#71C4: 7E
        ld      (ROCK_SPAWN_COUNT),a                           ;#71C5: 32 9C E0
        inc     hl                                             ;#71C8: 23
        ld      a,(hl)                                         ;#71C9: 7E
        ld      (STAGE_ENEMY_SEED_LEN),a                       ;#71CA: 32 C0 E0
        inc     hl                                             ;#71CD: 23
        ld      a,(hl)                                         ;#71CE: 7E
        ld      (STAGE_TIMER_RELOAD),a                         ;#71CF: 32 BA E0
        inc     hl                                             ;#71D2: 23
        ld      a,(hl)                                         ;#71D3: 7E
        ld      (STAGE_DIFFICULTY_INDEX),a                     ;#71D4: 32 BF E0
LOAD_STAGE_DIFFICULTY_TIER:
        ; Choose difficulty tier based on STAGE_DIFFICULTY (>=6 / >=3 / else)
        ld      a,(STAGE_DIFFICULTY_INDEX)                     ;#71D7: 3A BF E0
        push    hl                                             ;#71DA: E5
        ld      hl,STAGE_DIFFICULTY_TABLE                      ;#71DB: 21 58 72
        add     a,l                                            ;#71DE: 85
        ld      l,a                                            ;#71DF: 6F
        ld      a,0                                            ;#71E0: 3E 00
        adc     a,h                                            ;#71E2: 8C
        ld      h,a                                            ;#71E3: 67
        ld      a,(STAGE_DIFFICULTY)                           ;#71E4: 3A AE E0
        cp      6                                              ;#71E7: FE 06
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#71E9: 30 0C
        inc     hl                                             ;#71EB: 23
        inc     hl                                             ;#71EC: 23
        inc     hl                                             ;#71ED: 23
        inc     hl                                             ;#71EE: 23
        cp      3                                              ;#71EF: FE 03
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#71F1: 30 04
        inc     hl                                             ;#71F3: 23
        inc     hl                                             ;#71F4: 23
        inc     hl                                             ;#71F5: 23
        inc     hl                                             ;#71F6: 23
LOAD_STAGE_READ_PARAMS:
        ; Read 4 bytes into (ENEMY_STEP_SPEED) and (SCROLL_LIMIT_LO) as two 16-bit pairs
        ld      a,(hl)                                         ;#71F7: 7E
        ld      (ENEMY_STEP_SPEED),a                           ;#71F8: 32 C1 E0
        inc     hl                                             ;#71FB: 23
        ld      a,(hl)                                         ;#71FC: 7E
        ld      (ENEMY_STEP_SPEED_HI),a                        ;#71FD: 32 C2 E0
        inc     hl                                             ;#7200: 23
        ld      a,(hl)                                         ;#7201: 7E
        ld      (SCROLL_LIMIT_LO),a                            ;#7202: 32 C3 E0
        inc     hl                                             ;#7205: 23
        ld      a,(hl)                                         ;#7206: 7E
        ld      (SCROLL_LIMIT_HI),a                            ;#7207: 32 C4 E0
        pop     hl                                             ;#720A: E1
        ret                                                    ;#720B: C9

STAGE_PARAM_TABLE:
        ; Per-stage 4-byte records: stage N indexes (N-1)*4 (stages >=14h wrap to 10h-13h)
        ; STAGE_PARAM_TABLE has 19 stage records of 4 bytes each. Stage N (N=1..19)
        ; reads bytes (N-1)*4..(N-1)*4+3 → loaded into ROCK_SPAWN_ COUNT,
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD, and STAGE_DIFFICULTY_INDEX. Stages
        ; 0x14h and above wrap to entries 0x10h..0x13h (4-stage cycle).
        STAGE_PARAMS rocks=0, enemies=2, reload=9, difficulty=0  ;#720C: 00 20 09 00
        STAGE_PARAMS rocks=2, enemies=3, reload=9, difficulty=1  ;#7210: 02 30 09 0C
        STAGE_PARAMS rocks=5, enemies=7, reload=7, difficulty=2  ;#7214: 05 70 07 18
        STAGE_PARAMS rocks=4, enemies=3, reload=8, difficulty=3  ;#7218: 04 30 08 24
        STAGE_PARAMS rocks=5, enemies=4, reload=8, difficulty=4  ;#721C: 05 40 08 30
        STAGE_PARAMS rocks=6, enemies=5, reload=7, difficulty=5  ;#7220: 06 50 07 3C
        STAGE_PARAMS rocks=7, enemies=7, reload=7, difficulty=6  ;#7224: 07 70 07 48
        STAGE_PARAMS rocks=5, enemies=5, reload=7, difficulty=7  ;#7228: 05 50 07 54
        STAGE_PARAMS rocks=6, enemies=5, reload=6, difficulty=8  ;#722C: 06 50 06 60
        STAGE_PARAMS rocks=7, enemies=5, reload=6, difficulty=9  ;#7230: 07 50 06 6C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#7234: 0A 70 06 78
        STAGE_PARAMS rocks=6, enemies=6, reload=6, difficulty=11  ;#7238: 06 60 06 84
        STAGE_PARAMS rocks=7, enemies=6, reload=6, difficulty=12  ;#723C: 07 60 06 90
        STAGE_PARAMS rocks=8, enemies=7, reload=6, difficulty=13  ;#7240: 08 70 06 9C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#7244: 0A 70 06 78
        STAGE_PARAMS rocks=8, enemies=7, reload=5, difficulty=13  ;#7248: 08 70 05 9C
        STAGE_PARAMS rocks=9, enemies=7, reload=5, difficulty=14  ;#724C: 09 70 05 A8
        STAGE_PARAMS rocks=10, enemies=7, reload=5, difficulty=14  ;#7250: 0A 70 05 A8
        STAGE_PARAMS rocks=12, enemies=7, reload=5, difficulty=15  ;#7254: 0C 70 05 B4

STAGE_DIFFICULTY_TABLE:
        ; 16 records x 12 bytes (3 tiers x 4 bytes); STAGE_DIFFICULTY_TABLE..7317h
        ; STAGE_DIFFICULTY_TABLE has 16 stage records, each containing 3 difficulty
        ; tiers (4 bytes each = 12 bytes per record, 192 total). LOAD_STAGE_PARAMS uses
        ; STAGE_DIFFICULTY against thresholds 6 and 3 to pick the tier — enemies get
        ; faster/smarter at later stages. STAGE_DIFFICULTY_INDEX selects which record to
        ; use and ranges 0..180 in steps of 12.
        dh      "00030003200300032003000320030003"             ;#7258: 00 03 00 03 20 03 00 03 20 03 00 03 20 03 00 03
        dh      "30030003300300030000000400000004"             ;#7268: 30 03 00 03 30 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004200300034003000340030003"             ;#7278: 00 00 00 04 20 03 00 03 40 03 00 03 40 03 00 03
        dh      "40030003500300035003000350030003"             ;#7288: 40 03 00 03 50 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003600300030000000400000004"             ;#7298: 60 03 00 03 60 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#72A8: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "50030003600300036003000350030003"             ;#72B8: 50 03 00 03 60 03 00 03 60 03 00 03 50 03 00 03
        dh      "70030003700300030000000400000004"             ;#72C8: 70 03 00 03 70 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#72D8: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003700300037003000370030003"             ;#72E8: 60 03 00 03 70 03 00 03 70 03 00 03 70 03 00 03
        dh      "70030003700300038003000380030003"             ;#72F8: 70 03 00 03 70 03 00 03 80 03 00 03 80 03 00 03
        dh      "80030003000000040000000400000004"             ;#7308: 80 03 00 03 00 00 00 04 00 00 00 04 00 00 00 04

PADDING:
        ; 2280 bytes of 0FFh padding between STAGE_DIFFICULTY_TABLE and MAZE_BITMAP_0
        ds      2280,0FFh                                      ;#7318

MAZE_BITMAP_0:
        ; 224-byte wall bitmap for maze 0 (stages 0..3, 16..19, ...)
        ; 4 mazes x 256 bytes (1024 bytes total). Per maze: - bytes 00..DFh: 32 x 56
        ; cell wall bitmap (LOOKUP_PLAYFIELD_CELL computes byte_offset = (4*L) | ((H>>3)
        ; & 3); bit pos = 7-(H&7)). - bytes E0..FFh: 16 (X, Y) rock-spawn candidate
        ; pairs picked by SCROLL_ROCKS_PICK_POSITION via a random byte index. The maze
        ; for stage N is selected by (STAGE_PALETTE_INDEX>>2) & 3.
        dh      "0001FE0077D81EFE77D81E00000000EE"             ;#7C00: 00 01 FE 00 77 D8 1E FE 77 D8 1E 00 00 00 00 EE
        dh      "7EF81EEE0001DE000FD7DEFE20570000"             ;#7C10: 7E F8 1E EE 00 01 DE 00 0F D7 DE FE 20 57 00 00
        dh      "2F5777FD285770052B5074052B5775F5"             ;#7C20: 2F 57 77 FD 28 57 70 05 2B 50 74 05 2B 57 75 F5
        dh      "685775F56BD004050817673D6BF7673D"             ;#7C30: 68 57 75 F5 6B D0 04 05 08 17 67 3D 6B F7 67 3D
        dh      "6007673D7FF700010300003B7B7F3F3B"             ;#7C40: 60 07 67 3D 7F F7 00 01 03 00 00 3B 7B 7F 3F 3B
        dh      "78073F037B77033903703339BF7F333D"             ;#7C50: 78 07 3F 03 7B 77 03 39 03 70 33 39 BF 7F 33 3D
        dh      "80003001BF7F3F3DBF7F3F3D80000001"             ;#7C60: 80 00 30 01 BF 7F 3F 3D BF 7F 3F 3D 80 00 00 01
        dh      "BB7B3B3DBB7B3B3DBB600331BB6B3B35"             ;#7C70: BB 7B 3B 3D BB 7B 3B 3D BB 60 03 31 BB 6B 3B 35
        dh      "80033835B77B0304377B3B3E001B3B3E"             ;#7C80: 80 03 38 35 B7 7B 03 04 37 7B 3B 3E 00 1B 3B 3E
        dh      "3DC000003DC000000076EF363776EF36"             ;#7C90: 3D C0 00 00 3D C0 00 00 00 76 EF 36 37 76 EF 36
        dh      "37700F363776E03030060B3637DEEB36"             ;#7CA0: 37 70 0F 36 37 76 E0 30 30 06 0B 36 37 DE EB 36
        dh      "37DEEB3600000806DDBEEB36DDBEEB36"             ;#7CB0: 37 DE EB 36 00 00 08 06 DD BE EB 36 DD BE EB 36
        dh      "C0000336DDAAAB36DDAAAB000C2AA83E"             ;#7CC0: C0 00 03 36 DD AA AB 36 DD AA AB 00 0C 2A A8 3E
        dh      "61AAAB3E6FAAAB066FAAAB3600000030"             ;#7CD0: 61 AA AB 3E 6F AA AB 06 6F AA AB 36 00 00 00 30

ROCK_POSITIONS_0:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 0
        ROCK_POSITION x=0Bh, y=5                               ;#7CE0: 0B 05
        ROCK_POSITION x=17h, y=5                               ;#7CE2: 17 05
        ROCK_POSITION x=17h, y=5                               ;#7CE4: 17 05
        ROCK_POSITION x=15h, y=9                               ;#7CE6: 15 09
        ROCK_POSITION x=15h, y=9                               ;#7CE8: 15 09
        ROCK_POSITION x=1, y=0Eh                               ;#7CEA: 01 0E
        ROCK_POSITION x=1, y=0Eh                               ;#7CEC: 01 0E
        ROCK_POSITION x=5, y=0Fh                               ;#7CEE: 05 0F
        ROCK_POSITION x=18h, y=11h                             ;#7CF0: 18 11
        ROCK_POSITION x=18h, y=11h                             ;#7CF2: 18 11
        ROCK_POSITION x=6, y=14h                               ;#7CF4: 06 14
        ROCK_POSITION x=14h, y=16h                             ;#7CF6: 14 16
        ROCK_POSITION x=11h, y=1Bh                             ;#7CF8: 11 1B
        ROCK_POSITION x=0Bh, y=20h                             ;#7CFA: 0B 20
        ROCK_POSITION x=1, y=23h                               ;#7CFC: 01 23
        ROCK_POSITION x=1Ch, y=2Bh                             ;#7CFE: 1C 2B

MAZE_BITMAP_1:
        ; 224-byte wall bitmap for maze 1 (stages 4..7)
        dh      "FFF80000800AAFDEBDEAAFDEA02AA002"             ;#7D00: FF F8 00 00 80 0A AF DE BD EA AF DE A0 2A A0 02
        dh      "ADAAAEDAA8AAAEDAA8A80000AAAADBFA"             ;#7D10: AD AA AE DA A8 AA AE DA A8 A8 00 00 AA AA DB FA
        dh      "AAAADA028A82DAFAAAAADA82A8A8003A"             ;#7D20: AA AA DA 02 8A 82 DA FA AA AA DA 82 A8 A8 00 3A
        dh      "A8AADA82ADAADAFAA02ADA02BDEADBFA"             ;#7D30: A8 AA DA 82 AD AA DA FA A0 2A DA 02 BD EA DB FA
        dh      "80080000FDFADB7A0002DB7AADEEC002"             ;#7D40: 80 08 00 00 FD FA DB 7A 00 02 DB 7A AD EE C0 02
        dh      "ADEEFBDAADEEFBDAADEEFBDA200003DA"             ;#7D50: AD EE FB DA AD EE FB DA AD EE FB DA 20 00 03 DA
        dh      "2EF7E0002EC1000020DD7BBE2EDD7BBE"             ;#7D60: 2E F7 E0 00 2E C1 00 00 20 DD 7B BE 2E DD 7B BE
        dh      "2EDC7BBE000071B02E7C75B62E7C75B6"             ;#7D70: 2E DC 7B BE 00 00 71 B0 2E 7C 75 B6 2E 7C 75 B6
        dh      "281C0006081C75B6299C75B6299C71B0"             ;#7D80: 28 1C 00 06 08 1C 75 B6 29 9C 75 B6 29 9C 71 B0
        dh      "28007BBE2FEC7BBE000C78006DAC7BFE"             ;#7D90: 28 00 7B BE 2F EC 7B BE 00 0C 78 00 6D AC 7B FE
        dh      "6DA00300000EDB766DAE18066DAEFBFE"             ;#7DA0: 6D A0 03 00 00 0E DB 76 6D AE 18 06 6D AE FB FE
        dh      "002000006DAEEFBB6DAEEFBB000003BB"             ;#7DB0: 00 20 00 00 6D AE EF BB 6D AE EF BB 00 00 03 BB
        dh      "EF6AA800EF2AABBEEFAAA80001AAABF6"             ;#7DC0: EF 6A A8 00 EF 2A AB BE EF AA A8 00 01 AA AB F6
        dh      "6DAAAA066C0002F66DBEFAF600000000"             ;#7DD0: 6D AA AA 06 6C 00 02 F6 6D BE FA F6 00 00 00 00

ROCK_POSITIONS_1:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 1
        ROCK_POSITION x=18h, y=3                               ;#7DE0: 18 03
        ROCK_POSITION x=16h, y=0Bh                             ;#7DE2: 16 0B
        ROCK_POSITION x=1Fh, y=0Bh                             ;#7DE4: 1F 0B
        ROCK_POSITION x=14h, y=10h                             ;#7DE6: 14 10
        ROCK_POSITION x=14h, y=10h                             ;#7DE8: 14 10
        ROCK_POSITION x=1, y=18h                               ;#7DEA: 01 18
        ROCK_POSITION x=1, y=18h                               ;#7DEC: 01 18
        ROCK_POSITION x=16h, y=20h                             ;#7DEE: 16 20
        ROCK_POSITION x=16h, y=20h                             ;#7DF0: 16 20
        ROCK_POSITION x=1Fh, y=20h                             ;#7DF2: 1F 20
        ROCK_POSITION x=0Ch, y=24h                             ;#7DF4: 0C 24
        ROCK_POSITION x=1Ah, y=28h                             ;#7DF6: 1A 28
        ROCK_POSITION x=3, y=29h                               ;#7DF8: 03 29
        ROCK_POSITION x=17h, y=30h                             ;#7DFA: 17 30
        ROCK_POSITION x=7, y=35h                               ;#7DFC: 07 35
        ROCK_POSITION x=7, y=35h                               ;#7DFE: 07 35

MAZE_BITMAP_2:
        ; 224-byte wall bitmap for maze 2 (stages 8..11)
        dh      "00000E003F7AAEEE207AA0E0207AAEEE"             ;#7E00: 00 00 0E 00 3F 7A AE EE 20 7A A0 E0 20 7A AE EE
        dh      "2002AE0E3FDAAFBE0FD80FBE2FDEE000"             ;#7E10: 20 02 AE 0E 3F DA AF BE 0F D8 0F BE 2F DE E0 00
        dh      "2000EFB22DDEEFB22DDE003201DEAFB2"             ;#7E20: 20 00 EF B2 2D DE EF B2 2D DE 00 32 01 DE AF B2
        dh      "7DDEAFB27DC0AFB07DDEAC027DDE2DF2"             ;#7E30: 7D DE AF B2 7D C0 AF B0 7D DE AC 02 7D DE 2D F2
        dh      "001EADF27DDEADF27DDEADF27DC00000"             ;#7E40: 00 1E AD F2 7D DE AD F2 7D DE AD F2 7D C0 00 00
        dh      "7DF60F6C6037FF6C6734016D07059D6D"             ;#7E50: 7D F6 0F 6C 60 37 FF 6C 67 34 01 6D 07 05 9D 6D
        dh      "603401617DF59D7D7DF4017D7DF79F01"             ;#7E60: 60 34 01 61 7D F5 9D 7D 7D F4 01 7D 7D F7 9F 01
        dh      "00079F7D00079F7D6DB000006DB00000"             ;#7E70: 00 07 9F 7D 00 07 9F 7D 6D B0 00 00 6D B0 00 00
        dh      "6DB7DEFE0D87DEFE7DEFDE1E7DEF06DE"             ;#7E80: 6D B7 DE FE 0D 87 DE FE 7D EF DE 1E 7D EF 06 DE
        dh      "000076C67DEF70F67DEF06F00D8F76FE"             ;#7E90: 00 00 76 C6 7D EF 70 F6 7D EF 06 F0 0D 8F 76 FE
        dh      "6DB876FE6D8300006DB77BDE60377BDE"             ;#7EA0: 6D B8 76 FE 6D 83 00 00 6D B7 7B DE 60 37 7B DE
        dh      "7D801BDE7DAED800002EDBFE7FA00000"             ;#7EB0: 7D 80 1B DE 7D AE D8 00 00 2E DB FE 7F A0 00 00
        dh      "7FAAABBE702AAA2077AAAAAA07AAAAAA"             ;#7EC0: 7F AA AB BE 70 2A AA 20 77 AA AA AA 07 AA AA AA
        dh      "7FAAAAAA7000028277BFBAFA00000000"             ;#7ED0: 7F AA AA AA 70 00 02 82 77 BF BA FA 00 00 00 00

ROCK_POSITIONS_2:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 2
        ROCK_POSITION x=1Bh, y=2                               ;#7EE0: 1B 02
        ROCK_POSITION x=8, y=3                                 ;#7EE2: 08 03
        ROCK_POSITION x=8, y=3                                 ;#7EE4: 08 03
        ROCK_POSITION x=0Ch, y=8                               ;#7EE6: 0C 08
        ROCK_POSITION x=0, y=0Ah                               ;#7EE8: 00 0A
        ROCK_POSITION x=1Eh, y=0Dh                             ;#7EEA: 1E 0D
        ROCK_POSITION x=11h, y=0Eh                             ;#7EEC: 11 0E
        ROCK_POSITION x=11h, y=0Eh                             ;#7EEE: 11 0E
        ROCK_POSITION x=6, y=13h                               ;#7EF0: 06 13
        ROCK_POSITION x=1Eh, y=14h                             ;#7EF2: 1E 14
        ROCK_POSITION x=0Ch, y=21h                             ;#7EF4: 0C 21
        ROCK_POSITION x=0Ch, y=21h                             ;#7EF6: 0C 21
        ROCK_POSITION x=14h, y=25h                             ;#7EF8: 14 25
        ROCK_POSITION x=14h, y=25h                             ;#7EFA: 14 25
        ROCK_POSITION x=1Ch, y=2Dh                             ;#7EFC: 1C 2D
        ROCK_POSITION x=7, y=2Eh                               ;#7EFE: 07 2E

MAZE_BITMAP_3:
        ; 224-byte wall bitmap for maze 3 (stages 12..15)
        dh      "000000007F781DFE1F781DFE4F781C00"             ;#7F00: 00 00 00 00 7F 78 1D FE 1F 78 1D FE 4F 78 1C 00
        dh      "677A5EF4701A5EF47BDA5EF47B824074"             ;#7F10: 67 7A 5E F4 70 1A 5E F4 7B DA 5E F4 7B 82 40 74
        dh      "7BBA5F747B9A5F7403DA5F7477D81F04"             ;#7F20: 7B BA 5F 74 7B 9A 5F 74 03 DA 5F 74 77 D8 1F 04
        dh      "701E7FB47DDE7FB47DD00FB47DD00FB0"             ;#7F30: 70 1E 7F B4 7D DE 7F B4 7D D0 0F B4 7D D0 0F B0
        dh      "7DD3CFBC0003C0000003C05EDDF3CD1E"             ;#7F40: 7D D3 CF BC 00 03 C0 00 00 03 C0 5E DD F3 CD 1E
        dh      "DDF00DDEDDF00842001E7B7ADDDE6300"             ;#7F50: DD F0 0D DE DD F0 08 42 00 1E 7B 7A DD DE 63 00
        dh      "DDDE6FDADDDE6E1AC0006EFADDD66EFA"             ;#7F60: DD DE 6F DA DD DE 6E 1A C0 00 6E FA DD D6 6E FA
        dh      "DDD66EFA0DD66EFA600000F0600E6EF6"             ;#7F70: DD D6 6E FA 0D D6 6E FA 60 00 00 F0 60 0E 6E F6
        dh      "6FEE6EF0202E6EF7272E6C37202E6D87"             ;#7F80: 6F EE 6E F0 20 2E 6E F7 27 2E 6C 37 20 2E 6D 87
        dh      "2F206DBF012E01BF2D2E6C002D2E6DBE"             ;#7F90: 2F 20 6D BF 01 2E 01 BF 2D 2E 6C 00 2D 2E 6D BE
        dh      "252E6DB8352E603A352E6DBA712E6D80"             ;#7FA0: 25 2E 6D B8 35 2E 60 3A 35 2E 6D BA 71 2E 6D 80
        dh      "7D2E6FBE7D2E6FA24000000A552AAB6A"             ;#7FB0: 7D 2E 6F BE 7D 2E 6F A2 40 00 00 0A 55 2A AB 6A
        dh      "552AAB6A152AAB62752AAB6A052AAB6A"             ;#7FC0: 55 2A AB 6A 15 2A AB 62 75 2A AB 6A 05 2A AB 6A
        dh      "7D20036A7D2FFB600120007E00000000"             ;#7FD0: 7D 20 03 6A 7D 2F FB 60 01 20 00 7E 00 00 00 00

ROCK_POSITIONS_3:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 3
        ROCK_POSITION x=1Fh, y=4                               ;#7FE0: 1F 04
        ROCK_POSITION x=1Fh, y=4                               ;#7FE2: 1F 04
        ROCK_POSITION x=1Fh, y=0Fh                             ;#7FE4: 1F 0F
        ROCK_POSITION x=18h, y=11h                             ;#7FE6: 18 11
        ROCK_POSITION x=18h, y=11h                             ;#7FE8: 18 11
        ROCK_POSITION x=6, y=14h                               ;#7FEA: 06 14
        ROCK_POSITION x=10h, y=16h                             ;#7FEC: 10 16
        ROCK_POSITION x=10h, y=16h                             ;#7FEE: 10 16
        ROCK_POSITION x=0Bh, y=1Eh                             ;#7FF0: 0B 1E
        ROCK_POSITION x=0Fh, y=21h                             ;#7FF2: 0F 21
        ROCK_POSITION x=0, y=22h                               ;#7FF4: 00 22
        ROCK_POSITION x=8, y=23h                               ;#7FF6: 08 23
        ROCK_POSITION x=8, y=23h                               ;#7FF8: 08 23
        ROCK_POSITION x=17h, y=26h                             ;#7FFA: 17 26
        ROCK_POSITION x=17h, y=36h                             ;#7FFC: 17 36
        ROCK_POSITION x=5, y=37h                               ;#7FFE: 05 37

END_POINTER:
        end
