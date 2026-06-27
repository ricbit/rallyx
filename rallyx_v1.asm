; Rally-X (MSX, Namcot, first release, 1984)
; Disassembled by Ricardo Bittencourt (bluepenguin@gmail.com)
; Last update at 2026-06-27
;
	output "rallyx_v1.rom"
	org 04000h

GAME_ACTIVE                      equ     0E000h    ; Non-zero ⇒ gameplay running (gates UPDATE_SOUND output and pause input)
HIGH_SCORE_BCD                   equ     0E001h    ; 3-byte BCD high score; displayed via UNPACK_BCD_DIGITS (default 200h)
HIGH_SCORE_BCD_HIGH              equ     0E003h    ; Top byte of HIGH_SCORE_BCD (+2); cleared in INITIAL_STATE_HANDLER
STATE_HANDLER_VECTOR             equ     0E005h    ; 16-bit pointer to current state handler; VBLANK_HANDLER tail-jumps via jp (hl)
FRAME_TICK                       equ     0E007h    ; Free-running per-frame counter; many handlers read this for animation timing
WORLD_X_POS                      equ     0E008h    ; 16-bit world X coordinate; SBC by player movement drives WORLD_SCROLL_DX
PLAYER_VELOCITY_X                equ     0E009h    ; Signed 8-bit X velocity (mirror of PLAYER_VELOCITY_Y); picks TILE_SLICE_N
WORLD_Y_POS                      equ     0E00Ah    ; 16-bit world Y coordinate
PLAYER_VELOCITY_Y                equ     0E00Bh    ; Player Y velocity; bit 7 = direction, lower bits = magnitude
STEP_COUNTER_HIGH                equ     0E00Ch    ; Companion byte to STEP_COUNTER; inc'd 3x by MOVE_PLAYER_DIRECTION_0/2
STEP_COUNTER                     equ     0E00Dh    ; Inc'd by 3 each player step; possibly drives distance bonus
NAME_BANK_FLAG                   equ     0E00Eh    ; Selects VDP R2 between name=0400h (0) and name=1400h (non-zero)
PLAYER_WORLD_POSITION_X          equ     0E00Fh    ; Signed 8-bit X-axis world position; +X velocity -> PLAYER_SCREEN_X
PLAYER_WORLD_POSITION_Y          equ     0E010h    ; Signed 8-bit Y-axis world position; mirror of PLAYER_WORLD_POSITION_X
PLAYER_DIRECTION                 equ     0E011h    ; Lower 2 bits select 1 of 4 facings (target for DRAW_PLAYER_CAR rotation)
PLAYFIELD_SCROLL_OFFSET          equ     0E012h    ; 16-bit world scroll/position offset; clamped to (0, C000h)
SAT_MIRROR_CURSOR                equ     0E014h    ; Write cursor into SAT_MIRROR; reset every frame by VBLANK_GAME_FRAME
WORLD_SCROLL_DX                  equ     0E016h    ; Per-frame world X delta added to object positions by SCROLL_OBJECTS_*
WORLD_SCROLL_DY                  equ     0E017h    ; Per-frame world Y delta added to object positions by SCROLL_OBJECTS_*
RNG_LCG                          equ     0E018h    ; 1-byte LCG state advanced by NEXT_RANDOM (x' = 5x + 1)
RNG_LFSR                         equ     0E019h    ; 2-byte LFSR state (xor-shift) advanced by NEXT_RANDOM
ROCK_SPAWN_COUNT                 equ     0E01Ch    ; Loaded from STAGE_PARAM_TABLE; loop count for SCROLL_ROCKS seeding
ENEMY_CAR_ITER_TIMER             equ     0E01Dh    ; Start-of-stage grace timer; while non-zero, enemy contact isn't lethal (5A74h)
PLAYER_SCREEN_X                  equ     0E023h    ; Per-frame: PLAYER_WORLD_POSITION_X + PLAYER_VELOCITY_X (offset)
PLAYER_SCREEN_Y                  equ     0E024h    ; Per-frame: PLAYER_WORLD_POSITION_Y + PLAYER_VELOCITY_Y (offset)
RADAR_LAST_DOT_PTR               equ     0E025h    ; 16-bit ptr to the radar cell most recently written by UPDATE_RADAR_DOT_*
SMOKE_COOLDOWN                   equ     0E027h    ; Counts down after a smoke drop; gates subsequent DEPLOY_SMOKE_IF_INPUT
SMOKE_TRAIL_WRITE_PTR            equ     0E028h    ; Write cursor into SMOKE_TRAIL_TABLE (advances by 10h per spawn)
SMOKE_TRAIL_WRITE_INDEX          equ     0E02Ah    ; 0..8 ring index; wraps to 0 after 9 entries
PLAYER_ROTATION_PHASE            equ     0E02Bh    ; Current animation phase (0..2Fh); slewed toward target by DRAW_PLAYER_CAR
FRAME_TICK_SUB                   equ     0E02Ch    ; Sub-counter cleared at GAMEPLAY_INIT; advances within FRAME_TICK
MOVEMENT_SUB_PHASE               equ     0E02Dh    ; Cleared at GAMEPLAY_INIT; tracked alongside PLAYER_ROTATION_PHASE
STAGE_DIFFICULTY                 equ     0E02Eh    ; Branch key in LOAD_STAGE_PARAMS (thresholds at 6 and 3 select one of 3 rows)
STAGE_CLEAR_FLAG                 equ     0E02Fh    ; Non-zero ⇒ trigger STAGE_CLEAR_BONUS at next frame check
STAGE_PALETTE_INDEX              equ     0E030h    ; Drives palette selection in INIT_PLAYFIELD_PATTERNS via (val>>2)&3
SCORE_BCD                        equ     0E031h    ; 3-byte BCD score (6 digits); unpacked by UPDATE_SCORE_HUD via UNPACK_BCD_DIGITS
SCORE_BCD_MID                    equ     0E032h    ; SCORE_BCD+1; tested by CHECK_SCORE_MILESTONE for 2/8 extra-life thresholds
SCORE_BCD_HIGH                   equ     0E033h    ; Top byte of SCORE_BCD (+2); cleared in INITIAL_STATE_HANDLER
BONUS_BCD                        equ     0E034h    ; 4-byte BCD bonus counter from STAGE_CLEAR_BONUS via BCD_ADD_TO_BONUS overlap
LIVES                            equ     0E035h    ; Lives remaining; decremented on death, gates jump back to title
VBLANK_PARITY                    equ     0E036h    ; Inc'd at top of VBLANK_GAME_FRAME; low bit gates alternating refresh path
STAGE_TIMER_INNER                equ     0E037h    ; Inner tick counter for TICK_STAGE_TIMER; resets to E0BA on rollover
STAGE_TIMER_OUTER                equ     0E038h    ; Outer countdown decremented by TICK_STAGE_TIMER and TICK_FUEL_REFRESH
FUEL_LEVEL                       equ     0E039h    ; Depletes by 3 per smoke; UPDATE_FUEL_GAUGE renders it as a tile bar
STAGE_TIMER_RELOAD               equ     0E03Ah    ; Reload value for STAGE_TIMER_INNER when it hits zero
PLAYER_DEAD_FLAG                 equ     0E03Bh    ; Non-zero ⇒ trigger death sequence (jp DEATH_SEQUENCE from frame check)
SAVED_TIMER_FOR_DEATH            equ     0E03Ch    ; Backup of (E0B8, E0B9) preserved across DEATH_SEQUENCE
EXTRA_LIFE_AWARDED               equ     0E03Eh    ; Flag: set by CHECK_SCORE_MILESTONE to avoid awarding the same extra life twice
STAGE_DIFFICULTY_INDEX           equ     0E03Fh    ; Per-stage sub-index; offsets into STAGE_DIFFICULTY_TABLE in LOAD_STAGE_PARAMS
STAGE_ENEMY_SEED_LEN             equ     0E040h    ; INIT_ENEMY_CARS seed-copy length in bytes (cars*16)
ENEMY_STEP_SPEED                 equ     0E041h    ; Per-stage enemy step velocity (8.8); added to position accumulator each tick
ENEMY_STEP_SPEED_HI              equ     0E042h    ; High byte of ENEMY_STEP_SPEED 16-bit pair; only ever read as part of (E0C1)
SCROLL_LIMIT_LO                  equ     0E043h    ; Low byte of forward-scroll cap; PLAYFIELD_SCROLL_OFFSET stops advancing at this
SCROLL_LIMIT_HI                  equ     0E044h    ; High byte of forward-scroll cap (paired with SCROLL_LIMIT_LO at E0C3)
PLAYER_MOVE_GATE                 equ     0E045h    ; Set during death/init transitions; gates player position updates and movement
VRAM_BANK_FLAG                   equ     0E046h    ; Drives VDP R4 toggle between pattern bank 0800h and 1800h (double-buffer)
PAUSE_KEY_HISTORY                equ     0E047h    ; Shift register; CHECK_PAUSE_KEY rotates key bits into here to debounce chord
PAUSE_FLAG                       equ     0E048h    ; Non-zero ⇒ game frozen in VBLANK_HANDLER (PSG silenced, no game work)
GAME_OVER_FLAG                   equ     0E049h    ; Non-zero ⇒ play SFX_BANG and freeze music; tail of game-over sequence
SPRITE_PATTERN_WORK_BUF          equ     0E060h    ; 96-byte work area inside TEMP_SPACE; bit-transposed before VRAM upload
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
RADAR_GRID                       equ     0EA00h    ; 112-byte radar/minimap cell grid; INIT_STAGE fills with 90h (empty)
RADAR_GRID_TAIL                  equ     0EA01h    ; RADAR_GRID+1 — used as LDIR destination when clearing RADAR_GRID to 90h
OBSTACLE_GRID                    equ     0EA80h    ; Per-cell obstacle/state layout adjacent to RADAR_GRID
SAT_MIRROR                       equ     0EB00h    ; RAM copy of sprite attribute table; uploaded to VRAM 0700h each frame
SAT_SLOT0_PATTERN_COLOR          equ     0EB02h    ; SAT slot 0 pattern+color (16-bit write); set to 844h at game-over
SAT_SLOT1_Y                      equ     0EB04h    ; Y-coord of SAT slot 1; written to D0h to terminate sprite list at game-over
TRACK_DATA_RING                  equ     0EC00h    ; 10 entries x 0x5A bytes filled by INIT_STAGE_TRACK_DATA
TRACK_DATA_RING_END              equ     0EF83h    ; Last byte of TRACK_DATA_RING; LDDR top anchor when scrolling on player move
PLAYFIELD_LOOKUP_TABLE           equ     0F400h    ; ~1800-byte precomputed table built by INIT_PLAYFIELD_LOOKUP
PLAYFIELD_LOOKUP_OUT_OF_BOUNDS   equ     0FB20h    ; Secondary tier of PLAYFIELD_LOOKUP_TABLE (H>=20h path)

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
BIOS_RSLREG                      equ     00138h    ; Read primary slot register into A
BIOS_WSLREG                      equ     0013Bh    ; Write to primary slot register (A=value)
BIOS_RDVDP                       equ     0013Eh    ; Read VDP status S#0; acknowledges VBLANK IRQ
BIOS_SNSMAT                      equ     00141h    ; Scan keyboard matrix row A; returns inverted bits in A
BIOS_H_TIMI                      equ     0FD9Ah    ; Timer-interrupt hook (5-byte JP slot called every VBLANK)
STACK                            equ     0F000h    ; Stack top — GAME_BOOT and VBLANK_HANDLER set SP here (F000h)
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
TEMP_SPACE                       equ     0E000h    ; Boot scratch at E000 (work-area base): RAM-zero + pattern-assembly buffer

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
;   E000-E049 game state flags/counters (work area),
;   E100-E4FF four object tables (E100/E200/E300/E400),
;   E500-E5FF PSG mirror + sound subsystem state,
;   EA00-EAFF RADAR_GRID + OBSTACLE_GRID,
;   EB00-EBxx SAT_MIRROR,
;   EC00-EF83 TRACK_DATA_RING,
;   F400-FBxx PLAYFIELD_LOOKUP_TABLE + OUT_OF_BOUNDS, stack top at FFFFh.
;
; (First-release RAM map: SAT_MIRROR, work area, lookup table, radar grid,
; track ring and stack all sit at different addresses than the second release.)
;
; Frame model: VBLANK_HANDLER (4051h) is hooked into BIOS_H_TIMI
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
        ; player (SOUND_ADVANCE_NOTE_DURATION at 6B5Ch) walks the stream two
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
        ; LOAD_STAGE_PARAMS (71AFh). rocks = ROCK_SPAWN_COUNT; enemies = number
        ; of enemy cars, emitted as enemies*16 — the STAGE_ENEMY_SEED_LEN byte
        ; count, since each ENEMY_CAR_TABLE seed record is 16 bytes; reload =
        ; STAGE_TIMER_RELOAD; difficulty = STAGE_DIFFICULTY_TABLE record
        ; index, emitted as difficulty*0Ch (its 12-byte record stride).
        macro STAGE_PARAMS rocks, enemies, reload, difficulty
                db      rocks, enemies*16, reload, difficulty*0Ch
        endm

        ; One maze cell's 3x3 tile block in PLAYFIELD_CELL_TILES: three rows of
        ; three character codes, each passed as a "XXXXXX" hex string and
        ; emitted with dh. QUERY_PLAYFIELD_EMIT (4ACCh) copies the 9 bytes into
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
        dw      GAME_BOOT                                      ;#4002: 1A 40
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
        ; Cart title: length byte 09h + "newRALLYX" (hacked build)
        db      9, "newRALLYX"                                 ;#4010: 09 6E 65 77 52 41 4C ...

GAME_BOOT:
        ; Entry point for ROM startup (init vector from header)
        ; place stack just below the RDPRIM BIOS routine
        ld      sp,STACK                                       ;#401A: 31 00 F0
        di                                                     ;#401D: F3
        call    BIOS_RSLREG                                    ;#401E: CD 38 01
        and     0CFh                                           ;#4021: E6 CF
        ld      c,a                                            ;#4023: 4F
        add     a,a                                            ;#4024: 87
        add     a,a                                            ;#4025: 87
        and     30h                                            ;#4026: E6 30
        or      c                                              ;#4028: B1
        call    BIOS_WSLREG                                    ;#4029: CD 3B 01
        call    INIT_VDP_AND_LOAD_GFX                          ;#402C: CD 09 4D
        ld      hl,VBLANK_HANDLER                              ;#402F: 21 5C 40
        ; opcode for JP nnnn, written into BIOS_H_TIMI
        ld      a,Z80_JP                                       ;#4032: 3E C3
        ld      (BIOS_H_TIMI),a                                ;#4034: 32 9A FD
        ld      (BIOS_H_TIMI+1),hl                             ;#4037: 22 9B FD
        ld      hl,TEMP_SPACE                                  ;#403A: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#403D: 11 01 E0
        ld      bc,6FFh                                        ;#4040: 01 FF 06
        ld      (hl),0                                         ;#4043: 36 00
        ldir                                                   ;#4045: ED B0
        ld      hl,INITIAL_STATE_HANDLER                       ;#4047: 21 74 43
        ld      (STATE_HANDLER_VECTOR),hl                      ;#404A: 22 05 E0
REFRESH_RNG_AND_SOUND:
        ; Tail of GAME_BOOT: stir RNG, then fall into FINISH_FRAME_AND_WAIT
        call    NEXT_RANDOM                                    ;#404D: CD EA 54
FINISH_FRAME_AND_WAIT:
        ; Tail used by GAME_BOOT and WAIT_VBLANK: call UPDATE_SOUND, ei, R1=E2h, halt
        call    UPDATE_SOUND                                   ;#4050: CD E2 8B
        ei                                                     ;#4053: FB
        ; enable screen + IRQs + 16x16 sprites
        ld      bc,ROCK_TABLE_TAIL                             ;#4054: 01 01 E2
        call    BIOS_WRTVDP                                    ;#4057: CD 47 00
WAIT_FIRST_VBLANK:
        ; Tight `jr $` loop waiting for first VBLANK after boot
        jr      WAIT_FIRST_VBLANK                              ;#405A: 18 FE

VBLANK_HANDLER:
        ; Per-frame main loop, hooked into H.TIMI by GAME_BOOT
        ; VBLANK_HANDLER is reached via the BIOS_H_TIMI hook installed at GAME_BOOT. The
        ; SP is reset on every entry so the previous frame's stack is discarded —
        ; combined with the WAIT_VBLANK_* coroutine yield, this means state handlers can
        ; "block" by simply jumping into FINISH_FRAME_AND_ WAIT after saving their
        ; resume point in STATE_HANDLER_VECTOR.
        ld      sp,STACK                                       ;#405C: 31 00 F0
        call    BIOS_RDVDP                                     ;#405F: CD 3E 01
        call    CHECK_PAUSE_KEY                                ;#4062: CD E1 40
        ld      a,(PAUSE_FLAG)                                 ;#4065: 3A 48 E0
        and     a                                              ;#4068: A7
        jr      z,VBLANK_GAME_FRAME                            ;#4069: 28 06
        call    SILENCE_PSG                                    ;#406B: CD CC 40
        ei                                                     ;#406E: FB
PAUSE_HALT_LOOP:
        ; Tight `jr $` loop while PAUSE_FLAG is set (PSG already silenced)
        jr      PAUSE_HALT_LOOP                                ;#406F: 18 FE

VBLANK_GAME_FRAME:
        ; Non-paused branch of VBLANK_HANDLER; runs per-frame game work
        ; VBLANK_GAME_FRAME runs the non-paused per-frame work: increments
        ; VBLANK_PARITY, gates VDP-bank swap (R4 between 01/03 via VRAM_BANK_FLAG and R2
        ; between 01/05 via NAME_BANK_FLAG), updates FRAME_TICK, refreshes the SAT
        ; mirror to VRAM 0700h, then jumps to STATE_HANDLER_VECTOR.
        ld      hl,VBLANK_PARITY                               ;#4071: 21 36 E0
        inc     (hl)                                           ;#4074: 34
        ld      a,(hl)                                         ;#4075: 7E
        rra                                                    ;#4076: 1F
        jr      nc,REFRESH_RNG_AND_SOUND                       ;#4077: 30 D4
        ld      a,(VRAM_BANK_FLAG)                             ;#4079: 3A 46 E0
        rra                                                    ;#407C: 1F
        jr      c,VBLANK_GAME_FRAME_R4_BANK_A                  ;#407D: 38 08
        ; R4=3 → pattern table bank B (1800h)
        ld      bc,304h                                        ;#407F: 01 04 03
        call    BIOS_WRTVDP                                    ;#4082: CD 47 00
        jr      VBLANK_GAME_FRAME_R1_WRITE                     ;#4085: 18 06

VBLANK_GAME_FRAME_R4_BANK_A:
        ; Bank-A path: VDP R4 = 01 (patterns at 0800h)
        ; R4=1 → pattern table bank A (0800h)
        ld      bc,104h                                        ;#4087: 01 04 01
        call    BIOS_WRTVDP                                    ;#408A: CD 47 00
VBLANK_GAME_FRAME_R1_WRITE:
        ; After R4 select, write R1 = C2h (display enable + VBLANK IRQ)
        ; R1=C2h → screen on, IRQ off (mid-frame state)
        ld      bc,0C201h                                      ;#408D: 01 01 C2
        call    BIOS_WRTVDP                                    ;#4090: CD 47 00
        ld      bc,102h                                        ;#4093: 01 02 01
        ld      a,(NAME_BANK_FLAG)                             ;#4096: 3A 0E E0
        and     a                                              ;#4099: A7
        jr      z,VBLANK_GAME_FRAME_R2_WRITE                   ;#409A: 28 03
        ; R2=5 → name table bank B (1400h)
        ld      bc,502h                                        ;#409C: 01 02 05
VBLANK_GAME_FRAME_R2_WRITE:
        ; Apply chosen R2 value (01h or 05h) to switch name-table bank
        call    BIOS_WRTVDP                                    ;#409F: CD 47 00
        ld      hl,FRAME_TICK                                  ;#40A2: 21 07 E0
        inc     (hl)                                           ;#40A5: 34
        ld      hl,SAT_MIRROR                                  ;#40A6: 21 00 EB
        ld      (SAT_MIRROR_CURSOR),hl                         ;#40A9: 22 14 E0
        LOAD_VRAM_ADDRESS de, 700h                             ;#40AC: 11 00 07
        ld      bc,80h                                         ;#40AF: 01 80 00
        call    BIOS_LDIRVM                                    ;#40B2: CD 5C 00
        ld      hl,(STATE_HANDLER_VECTOR)                      ;#40B5: 2A 05 E0
        jp      (hl)                                           ;#40B8: E9

WAIT_VBLANK_FINISH_SPRITES:
        ; Yield: save PC into STATE_HANDLER_VECTOR, terminate SAT, wait for VBLANK
        ; WAIT_VBLANK_FINISH_SPRITES and WAIT_VBLANK implement the coroutine yield
        ; idiom: `pop hl` grabs the caller's return address, stores it in
        ; STATE_HANDLER_VECTOR, then `jp FINISH_FRAME_AND_WAIT` (=FINISH_FRAME_AND_
        ; WAIT) which ticks sound, ei, and halts. Next vblank, VBLANK_HANDLER fires,
        ; dispatches via `jp (STATE_HANDLER_VECTOR)`, and execution resumes at the
        ; return point. The "FINISH_SPRITES" variant also writes the sprite-list
        ; terminator (D0h) before yielding.
        pop     hl                                             ;#40B9: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40BA: 22 05 E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#40BD: 2A 14 E0
        ; mark next sprite slot as end-of-list
        ld      (hl),SPRITE_Y_TERMINATOR                       ;#40C0: 36 D0
        jp      FINISH_FRAME_AND_WAIT                          ;#40C2: C3 50 40

WAIT_VBLANK:
        ; Yield: save caller PC into STATE_HANDLER_VECTOR, wait for next VBLANK
        pop     hl                                             ;#40C5: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40C6: 22 05 E0
        jp      FINISH_FRAME_AND_WAIT                          ;#40C9: C3 50 40

SILENCE_PSG:
        ; Zero PSG channel-volume registers (R8/R9/R10)
        ; SILENCE_PSG writes 0 to PSG R8/R9/R10 (channel A/B/C amplitude registers). All
        ; 3 channels go silent. Called when entering PAUSE state from VBLANK_HANDLER so
        ; the music doesn't keep playing while paused.
        ld      a,8                                            ;#40CC: 3E 08
        ld      e,0                                            ;#40CE: 1E 00
        call    BIOS_WRTPSG                                    ;#40D0: CD 93 00
        ; silence PSG channel B volume
        ld      a,9                                            ;#40D3: 3E 09
        ld      e,0                                            ;#40D5: 1E 00
        call    BIOS_WRTPSG                                    ;#40D7: CD 93 00
        ld      a,0Ah                                          ;#40DA: 3E 0A
        ld      e,0                                            ;#40DC: 1E 00
        ; tail call for R10 silence (covered manually)
        jp      BIOS_WRTPSG                                    ;#40DE: C3 93 00

CHECK_PAUSE_KEY:
        ; Poll SNSMAT row 7 and toggle PAUSE_FLAG on a sustained key chord
        ; CHECK_PAUSE_KEY runs once per frame. Reads SNSMAT row 7 (function keys),
        ; rotates the input bits into PAUSE_KEY_HISTORY as a 4-bit shift register, and
        ; tests for a stable held-down pattern (history & 0Fh == 0Ch). On match, toggles
        ; PAUSE_FLAG via cpl. The shift register debounces the keypress so single frames
        ; don't accidentally pause.
        ld      a,(GAME_ACTIVE)                                ;#40E1: 3A 00 E0
        and     a                                              ;#40E4: A7
        jr      z,CHECK_PAUSE_KEY_TOGGLE_PAUSE                 ;#40E5: 28 18
        ld      a,7                                            ;#40E7: 3E 07
        call    BIOS_SNSMAT                                    ;#40E9: CD 41 01
        ld      hl,PAUSE_KEY_HISTORY                           ;#40EC: 21 47 E0
        rla                                                    ;#40EF: 17
        rla                                                    ;#40F0: 17
        rla                                                    ;#40F1: 17
        rla                                                    ;#40F2: 17
        rl      (hl)                                           ;#40F3: CB 16
        ld      a,(hl)                                         ;#40F5: 7E
        and     0Fh                                            ;#40F6: E6 0F
        cp      0Ch                                            ;#40F8: FE 0C
        ret     nz                                             ;#40FA: C0
        ld      a,(PAUSE_FLAG)                                 ;#40FB: 3A 48 E0
        cpl                                                    ;#40FE: 2F
CHECK_PAUSE_KEY_TOGGLE_PAUSE:
        ; CHECK_PAUSE_KEY tail: toggle PAUSE_FLAG and return
        ld      (PAUSE_FLAG),a                                 ;#40FF: 32 48 E0
        ret                                                    ;#4102: C9

FILL_NAMETABLE_BLANK:
        ; Fill a 23x24 tile area at HL with tile 40h (clear playfield region)
        ; FILL_NAMETABLE_BLANK clears a 23-wide × 24-tall area at the name table base in
        ; HL. Per-row: BIOS_FILVRM fills 23 cells with TILE_BLANK (40h), then HL += 32
        ; (next row). Used by both INIT_PLAYFIELD_PATTERNS and CLEAR_PLAYFIELD to wipe
        ; the screen.
        ld      b,18h                                          ;#4103: 06 18
FILL_NAMETABLE_ROW_TOP:
        ; Outer djnz of FILL_NAMETABLE_BLANK (per-row body)
        push    bc                                             ;#4105: C5
        push    hl                                             ;#4106: E5
        ld      bc,17h                                         ;#4107: 01 17 00
        ld      a,40h                                          ;#410A: 3E 40
        call    BIOS_FILVRM                                    ;#410C: CD 56 00
        pop     hl                                             ;#410F: E1
        ld      bc,20h                                         ;#4110: 01 20 00
        add     hl,bc                                          ;#4113: 09
        pop     bc                                             ;#4114: C1
        djnz    FILL_NAMETABLE_ROW_TOP                         ;#4115: 10 EE
        ret                                                    ;#4117: C9

INIT_PLAYFIELD_PATTERNS:
        ; Clear name tables, upload tile patterns 80h..FFh, select stage palette
        ; INIT_PLAYFIELD_PATTERNS sets up the per-stage tile patterns: (1) clears both
        ; name table banks via FILL_NAMETABLE_BLANK, (2) zeros 256 bytes at VRAM
        ; 0C00h/1C00h (chars 80h-9Fh), (3) LDIRVMs BG_PATTERN_FILL 8 times to fill chars
        ; A0h-EFh in both banks, (4) LDIRVMs BG_PATTERN_DATA twice for chars F0h-FFh,
        ; (5) selects a color row from STAGE_PALETTES based on STAGE_PALETTE_INDEX.
        ld      hl,400h                                        ;#4118: 21 00 04
        call    FILL_NAMETABLE_BLANK                           ;#411B: CD 03 41
        ld      hl,1400h                                       ;#411E: 21 00 14
        call    FILL_NAMETABLE_BLANK                           ;#4121: CD 03 41
        LOAD_VRAM_ADDRESS hl, 0C00h                            ;#4124: 21 00 0C
        ld      bc,100h                                        ;#4127: 01 00 01
        xor     a                                              ;#412A: AF
        call    BIOS_FILVRM                                    ;#412B: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1C00h                            ;#412E: 21 00 1C
        ld      bc,100h                                        ;#4131: 01 00 01
        xor     a                                              ;#4134: AF
        call    BIOS_FILVRM                                    ;#4135: CD 56 00
        ld      hl,BG_PATTERN_FILL                             ;#4138: 21 B4 42
        LOAD_VRAM_ADDRESS de, 0D00h                            ;#413B: 11 00 0D
        ld      bc,80h                                         ;#413E: 01 80 00
        call    BIOS_LDIRVM                                    ;#4141: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4144: 21 B4 42
        LOAD_VRAM_ADDRESS de, 1D00h                            ;#4147: 11 00 1D
        ld      bc,80h                                         ;#414A: 01 80 00
        call    BIOS_LDIRVM                                    ;#414D: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4150: 21 B4 42
        LOAD_VRAM_ADDRESS de, 0D80h                            ;#4153: 11 80 0D
        ld      bc,80h                                         ;#4156: 01 80 00
        call    BIOS_LDIRVM                                    ;#4159: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#415C: 21 B4 42
        LOAD_VRAM_ADDRESS de, 1D80h                            ;#415F: 11 80 1D
        ld      bc,80h                                         ;#4162: 01 80 00
        call    BIOS_LDIRVM                                    ;#4165: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4168: 21 B4 42
        LOAD_VRAM_ADDRESS de, 0E00h                            ;#416B: 11 00 0E
        ld      bc,80h                                         ;#416E: 01 80 00
        call    BIOS_LDIRVM                                    ;#4171: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4174: 21 B4 42
        LOAD_VRAM_ADDRESS de, 1E00h                            ;#4177: 11 00 1E
        ld      bc,80h                                         ;#417A: 01 80 00
        call    BIOS_LDIRVM                                    ;#417D: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4180: 21 B4 42
        LOAD_VRAM_ADDRESS de, 0E80h                            ;#4183: 11 80 0E
        ld      bc,80h                                         ;#4186: 01 80 00
        call    BIOS_LDIRVM                                    ;#4189: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#418C: 21 B4 42
        LOAD_VRAM_ADDRESS de, 1E80h                            ;#418F: 11 80 1E
        ld      bc,80h                                         ;#4192: 01 80 00
        call    BIOS_LDIRVM                                    ;#4195: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#4198: 21 D4 41
        LOAD_VRAM_ADDRESS de, 0F00h                            ;#419B: 11 00 0F
        ld      bc,100h                                        ;#419E: 01 00 01
        call    BIOS_LDIRVM                                    ;#41A1: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#41A4: 21 D4 41
        LOAD_VRAM_ADDRESS de, 1F00h                            ;#41A7: 11 00 1F
        ld      bc,100h                                        ;#41AA: 01 00 01
        call    BIOS_LDIRVM                                    ;#41AD: CD 5C 00
        ld      hl,STAGE_PALETTES                              ;#41B0: 21 34 43
        ld      a,(STAGE_PALETTE_INDEX)                        ;#41B3: 3A 30 E0
        rra                                                    ;#41B6: 1F
        rra                                                    ;#41B7: 1F
        and     3                                              ;#41B8: E6 03
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41BA: 28 0F
        ld      hl,STAGE_PALETTE_1                             ;#41BC: 21 44 43
        dec     a                                              ;#41BF: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41C0: 28 09
        ld      hl,STAGE_PALETTE_2                             ;#41C2: 21 54 43
        dec     a                                              ;#41C5: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41C6: 28 03
        ; palette 4 → color row
        ld      hl,STAGE_PALETTE_3                             ;#41C8: 21 64 43
INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD:
        ; Tail: LDIRVM the chosen palette row to VRAM 0790h
        LOAD_VRAM_ADDRESS de, 790h                             ;#41CB: 11 90 07
        ld      bc,10h                                         ;#41CE: 01 10 00
        jp      BIOS_LDIRVM                                    ;#41D1: C3 5C 00

BG_PATTERN_DATA:
        ; 8-pixel-wide stripe patterns; loaded into tile patterns F0h..FFh
        dh      "00010101010101000003030303030300"             ;#41D4: 00 01 01 01 01 01 01 00 00 03 03 03 03 03 03 00
        dh      "0007070707070700000F0F0F0F0F0F00"             ;#41E4: 00 07 07 07 07 07 07 00 00 0F 0F 0F 0F 0F 0F 00
        dh      "001F1F1F1F1F1F00003F3F3F3F3F3F00"             ;#41F4: 00 1F 1F 1F 1F 1F 1F 00 00 3F 3F 3F 3F 3F 3F 00
        dh      "007F7F7F7F7F7F0000FFFFFFFFFFFF00"             ;#4204: 00 7F 7F 7F 7F 7F 7F 00 00 FF FF FF FF FF FF 00
        dh      "00000000000000000004040404040400"             ;#4214: 00 00 00 00 00 00 00 00 00 04 04 04 04 04 04 00
        dh      "000C0C0C0C0C0C00001C1C1C1C1C1C00"             ;#4224: 00 0C 0C 0C 0C 0C 0C 00 00 1C 1C 1C 1C 1C 1C 00
        dh      "003C3C3C3C3C3C00007C7C7C7C7C7C00"             ;#4234: 00 3C 3C 3C 3C 3C 3C 00 00 7C 7C 7C 7C 7C 7C 00
        dh      "00FCFCFCFCFCFC0000FCFCFCFCFCFC00"             ;#4244: 00 FC FC FC FC FC FC 00 00 FC FC FC FC FC FC 00
        dh      "00000000000030300000000000000082"             ;#4254: 00 00 00 00 00 00 30 30 00 00 00 00 00 00 00 82
        dh      "007E607C6060000800666666663C0020"             ;#4264: 00 7E 60 7C 60 60 00 08 00 66 66 66 66 3C 00 20
        dh      "007E607C607E808200606060607E0008"             ;#4274: 00 7E 60 7C 60 7E 80 82 00 60 60 60 60 7E 00 08
        dh      "00000000000000200000000000000686"             ;#4284: 00 00 00 00 00 00 00 20 00 00 00 00 00 00 06 86
        dh      "00010B0F0B0101031B1F190000000000"             ;#4294: 00 01 0B 0F 0B 01 01 03 1B 1F 19 00 00 00 00 00
        dh      "0080D0F0D08080C0D8F8980000000000"             ;#42A4: 00 80 D0 F0 D0 80 80 C0 D8 F8 98 00 00 00 00 00

BG_PATTERN_FILL:
        ; 128-byte filler pattern, LDIRVM'd 8 times to populate tile patterns 80h..EFh
        dh      "C0C00000000000003030000000000000"             ;#42B4: C0 C0 00 00 00 00 00 00 30 30 00 00 00 00 00 00
        dh      "0C0C0000000000000303000000000000"             ;#42C4: 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00 00 00
        dh      "0000C0C0000000000000303000000000"             ;#42D4: 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00 00 00
        dh      "00000C0C000000000000030300000000"             ;#42E4: 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00
        dh      "00000000C0C000000000000030300000"             ;#42F4: 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00
        dh      "000000000C0C00000000000003030000"             ;#4304: 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00
        dh      "000000000000C0C00000000000003030"             ;#4314: 00 00 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30
        dh      "0000000000000C0C0000000000000303"             ;#4324: 00 00 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03

STAGE_PALETTES:
        ; Base of 4 x 16-byte color-table rows (palette 0)
        ; STAGE_PALETTES — 4 rows of 16 bytes each (= 64 bytes total). Used by
        ; INIT_PLAYFIELD_PATTERNS to pick a color row based on STAGE_PALETTE_INDEX (see
        ; (val >> 2) & 3 logic at 41A8h). All 4 rows differ only in their first 2 bytes
        ; — those are the visible per-stage color differentiation (rest is the shared
        ; HUD palette).
        dh      "DEEDF5F5A5A5F5F515156565A1A1F1A1"             ;#4334: DE ED F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_1:
        ; 16-byte color-table row for palette 1
        dh      "4EE4F5F5A5A5F5F515156565A1A1F1A1"             ;#4344: 4E E4 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_2:
        ; 16-byte color-table row for palette 2
        dh      "6EE6F5F5A5A5F5F515156565A1A1F1A1"             ;#4354: 6E E6 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_3:
        ; 16-byte color-table row for palette 3
        dh      "2EE2F5F5A5A5F5F515156565A1A1F1A1"             ;#4364: 2E E2 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

INITIAL_STATE_HANDLER:
        ; First state handler installed by GAME_BOOT into STATE_HANDLER_VECTOR
        ; INITIAL_STATE_HANDLER is the first state-handler installed at boot. It walks
        ; the boot flow: reset counters, blank screen, LOAD_PLAYFIELD_GFX,
        ; TITLE_WAIT_INPUT (poll until any input), then GAMEPLAY_INIT which arms the
        ; start jingle. WAIT_START_MUSIC spins on SOUND_STATE_OPENING to drain, then
        ; CLEAR_PLAYFIELD wipes both name tables. After that: INIT_PLAYFIELD_PATTERNS,
        ; LOAD_STAGE_PARAMS, INIT_STAGE, the 4 INIT_OBJECT_TABLE_* helpers, and finally
        ; falls through to GAME_LOOP.
        ld      hl,200h                                        ;#4374: 21 00 02
        ld      (HIGH_SCORE_BCD),hl                            ;#4377: 22 01 E0
        ld      h,0                                            ;#437A: 26 00
        ld      (HIGH_SCORE_BCD_HIGH),hl                       ;#437C: 22 03 E0
        ld      (SCORE_BCD),hl                                 ;#437F: 22 31 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#4382: 22 33 E0
INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART:
        ; Stage-restart entry: clear GAME_ACTIVE, blank screen, reload tile patterns
        xor     a                                              ;#4385: AF
        ld      (GAME_ACTIVE),a                                ;#4386: 32 00 E0
        call    LOAD_PLAYFIELD_GFX                             ;#4389: CD 60 88
TITLE_WAIT_INPUT:
        ; Title-screen loop; polls POLL_INPUT until any key/joystick pressed
        ; TITLE_WAIT_INPUT spins waiting for any input. Calls WAIT_VBLANK_FINISH_SPRITES
        ; (yield), then POLL_INPUT. If no input bit is set in C (mask 0F0h after cpl),
        ; loops back to TITLE_WAIT_INPUT. Used during the title/attract sequence before
        ; the player can start.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#438C: CD B9 40
        call    POLL_INPUT                                     ;#438F: CD C5 4C
        ld      a,c                                            ;#4392: 79
        cpl                                                    ;#4393: 2F
        and     0F0h                                           ;#4394: E6 F0
        jr      z,TITLE_WAIT_INPUT                             ;#4396: 28 F4
        xor     a                                              ;#4398: AF
        ld      (STAGE_PALETTE_INDEX),a                        ;#4399: 32 30 E0
        ld      (EXTRA_LIFE_AWARDED),a                         ;#439C: 32 3E E0
        ld      hl,0                                           ;#439F: 21 00 00
        ld      (SCORE_BCD),hl                                 ;#43A2: 22 31 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#43A5: 22 33 E0
        inc     a                                              ;#43A8: 3C
        ld      (GAME_ACTIVE),a                                ;#43A9: 32 00 E0
        ld      a,2                                            ;#43AC: 3E 02
        ld      (LIVES),a                                      ;#43AE: 32 35 E0
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43B1: CD B9 40
        ld      a,1                                            ;#43B4: 3E 01
        ld      (SOUND_STATE_OPENING),a                        ;#43B6: 32 20 E5
WAIT_START_MUSIC:
        ; Spin on SOUND_STATE_OPENING until the opening jingle finishes
        ; WAIT_START_MUSIC spins until SOUND_STATE_OPENING reaches 0 — the start-jingle
        ; ends. Uses WAIT_VBLANK_FINISH_SPRITES as yield. After drain, proceeds to
        ; CLEAR_PLAYFIELD.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43B9: CD B9 40
        ld      a,(SOUND_STATE_OPENING)                        ;#43BC: 3A 20 E5
        and     a                                              ;#43BF: A7
        jr      nz,WAIT_START_MUSIC                            ;#43C0: 20 F7
        LOAD_VRAM_ADDRESS hl, 400h                             ;#43C2: 21 00 04
        ld      bc,300h                                        ;#43C5: 01 00 03
        ld      a,40h                                          ;#43C8: 3E 40
        call    BIOS_FILVRM                                    ;#43CA: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#43CD: 21 00 14
        ld      bc,300h                                        ;#43D0: 01 00 03
        ld      a,40h                                          ;#43D3: 3E 40
        call    BIOS_FILVRM                                    ;#43D5: CD 56 00
INITIAL_STATE_HANDLER_PALETTE_REFRESH:
        ; Wait one VBLANK, inc STAGE_PALETTE_INDEX, jump back to pattern init
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43D8: CD B9 40
        ld      hl,STAGE_PALETTE_INDEX                         ;#43DB: 21 30 E0
        inc     (hl)                                           ;#43DE: 34
        jr      nz,INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT    ;#43DF: 20 02
        ld      (hl),0F0h                                      ;#43E1: 36 F0
INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT:
        ; After tile-pattern setup: reset SMOKE_TRAIL_WRITE_INDEX and continue stage init
        call    INIT_PLAYFIELD_PATTERNS                        ;#43E3: CD 18 41
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43E6: CD B9 40
        ld      a,8                                            ;#43E9: 3E 08
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#43EB: 32 2A E0
        call    LOAD_STAGE_PARAMS                              ;#43EE: CD B5 94
        call    SCROLL_ROCKS                                   ;#43F1: CD 1E 56
        call    INIT_STAGE                                     ;#43F4: CD CD 53
        ld      a,1                                            ;#43F7: 3E 01
        ld      (STAGE_TIMER_INNER),a                          ;#43F9: 32 37 E0
        xor     a                                              ;#43FC: AF
        ld      (STAGE_CLEAR_FLAG),a                           ;#43FD: 32 2F E0
STAGE_RESUME:
        ; Re-seed enemy cars / flags / rocks / track data after death or stage clear
        call    INIT_ENEMY_CARS                                ;#4400: CD 34 4C
        call    INIT_FLAGS                                     ;#4403: CD 88 54
        call    INIT_ROCKS                                     ;#4406: CD 68 56
        call    INIT_STAGE_TRACK_DATA                          ;#4409: CD 02 4C
        xor     a                                              ;#440C: AF
        ld      (NAME_BANK_FLAG),a                             ;#440D: 32 0E E0
        ld      (MOVEMENT_SUB_PHASE),a                         ;#4410: 32 2D E0
        ld      (GAME_OVER_FLAG),a                             ;#4413: 32 49 E0
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#4416: 32 61 E5
        ld      (FRAME_TICK_SUB),a                             ;#4419: 32 2C E0
        ld      (PLAYER_MOVE_GATE),a                           ;#441C: 32 45 E0
        ld      hl,3C01h                                       ;#441F: 21 01 3C
        ld      (STAGE_TIMER_OUTER),hl                         ;#4422: 22 38 E0
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#4425: 21 9C 07
        ld      a,0A1h                                         ;#4428: 3E A1
        call    BIOS_WRTVRM                                    ;#442A: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#442D: 21 9D 07
        ld      a,0A1h                                         ;#4430: 3E A1
        call    BIOS_WRTVRM                                    ;#4432: CD 4D 00
        ld      hl,TEXT_ROUND                                  ;#4435: 21 2E 46
        ld      de,FUEL_GAUGE_BUFFER                           ;#4438: 11 E0 E1
        ld      bc,6                                           ;#443B: 01 06 00
        ldir                                                   ;#443E: ED B0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4440: 3A 30 E0
        cp      63h                                            ;#4443: FE 63
        jr      c,SHOW_ROUND_NUM_CAP                           ;#4445: 38 02
        ld      a,63h                                          ;#4447: 3E 63
SHOW_ROUND_NUM_CAP:
        ; Clamp STAGE_PALETTE_INDEX to 63h before round-number divmod
        ld      c,40h                                          ;#4449: 0E 40
SHOW_ROUND_NUM_DIVMOD:
        ; Divmod-10 loop body: subtract 10 from A, inc tens digit in C
        cp      0Ah                                            ;#444B: FE 0A
        jr      c,SHOW_ROUND_NUM_STORE                         ;#444D: 38 07
        sub     0Ah                                            ;#444F: D6 0A
        res     6,c                                            ;#4451: CB B1
        inc     c                                              ;#4453: 0C
        jr      SHOW_ROUND_NUM_DIVMOD                          ;#4454: 18 F5

SHOW_ROUND_NUM_STORE:
        ; Store ones digit at HL, tens at HL+1 in the round-number SAT cells
        ex      de,hl                                          ;#4456: EB
        ld      (hl),c                                         ;#4457: 71
        inc     hl                                             ;#4458: 23
        ld      (hl),a                                         ;#4459: 77
        ld      hl,DIGIT_TEMPLATE_F0                           ;#445A: 21 34 46
        LOAD_VRAM_ADDRESS de, 4B7h                             ;#445D: 11 B7 04
        ld      bc,8                                           ;#4460: 01 08 00
        call    BIOS_LDIRVM                                    ;#4463: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_F0                           ;#4466: 21 34 46
        LOAD_VRAM_ADDRESS de, 14B7h                            ;#4469: 11 B7 14
        ld      bc,8                                           ;#446C: 01 08 00
        call    BIOS_LDIRVM                                    ;#446F: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#4472: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 6F7h                             ;#4475: 11 F7 06
        ld      bc,8                                           ;#4478: 01 08 00
        call    BIOS_LDIRVM                                    ;#447B: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#447E: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 16F7h                            ;#4481: 11 F7 16
        ld      bc,8                                           ;#4484: 01 08 00
        call    BIOS_LDIRVM                                    ;#4487: CD 5C 00
        ld      hl,SMOKE_TRAIL_TABLE                           ;#448A: 21 00 E4
        ld      de,SMOKE_TRAIL_TABLE_TAIL                      ;#448D: 11 01 E4
        ld      bc,8Fh                                         ;#4490: 01 8F 00
        xor     a                                              ;#4493: AF
        ld      (PLAYER_DIRECTION),a                           ;#4494: 32 11 E0
        ld      (PLAYER_ROTATION_PHASE),a                      ;#4497: 32 2B E0
        ld      (SMOKE_COOLDOWN),a                             ;#449A: 32 27 E0
        ld      (hl),a                                         ;#449D: 77
        ldir                                                   ;#449E: ED B0
        call    UPDATE_LIVES_DISPLAY                           ;#44A0: CD 75 8B
        call    UPDATE_RADAR                                   ;#44A3: CD E5 52
        ld      a,(STAGE_PALETTE_INDEX)                        ;#44A6: 3A 30 E0
        rra                                                    ;#44A9: 1F
        jr      nc,GAME_LOOP                                   ;#44AA: 30 14
        rra                                                    ;#44AC: 1F
        jr      nc,GAME_LOOP                                   ;#44AD: 30 11
        call    DRAW_CHALLENGING_STAGE_SCREEN                  ;#44AF: CD E5 46
        ld      a,1                                            ;#44B2: 3E 01
        ld      (SOUND_STATE_C_STAGE),a                        ;#44B4: 32 65 E5
GAMELOOP_PRE_YIELD:
        ; Spin until SOUND_STATE_C_STAGE = 0 (jingle done)
        call    WAIT_VBLANK                                    ;#44B7: CD C5 40
        ld      a,(SOUND_STATE_C_STAGE)                        ;#44BA: 3A 65 E5
        and     a                                              ;#44BD: A7
        jr      nz,GAMELOOP_PRE_YIELD                          ;#44BE: 20 F7
GAME_LOOP:
        ; Per-frame gameplay loop: yield, music+sound, sprite updates, end-of-round checks
        ; GAME_LOOP is the per-frame heart of gameplay. Each iteration: yield via
        ; WAIT_VBLANK_FINISH_SPRITES, copy FRAME_TICK->VRAM_BANK_FLAG for the double-
        ; buffer swap, drive sound + sprites + scrolling, then check the three end-of-
        ; round flags (STAGE_CLEAR_FLAG / PLAYER_DEAD_FLAG / GAME_OVER_FLAG) and either
        ; continue looping or branch to STAGE_CLEAR_ BONUS / DEATH_SEQUENCE /
        ; GAME_OVER_SEQUENCE.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#44C0: CD B9 40
        ld      a,(FRAME_TICK)                                 ;#44C3: 3A 07 E0
        ld      (VRAM_BANK_FLAG),a                             ;#44C6: 32 46 E0
        ld      a,1                                            ;#44C9: 3E 01
        ld      (SOUND_STATE_THEME),a                          ;#44CB: 32 10 E5
        call    FLASH_AND_UPDATE_SCORE_HUD                     ;#44CE: CD 30 8A
        call    DRAW_PLAYER_CAR                                ;#44D1: CD 94 47
        call    UPLOAD_PATTERN_SLICE                           ;#44D4: CD 07 4E
        call    ITERATE_ENEMY_CARS                             ;#44D7: CD 84 57
        call    UPDATE_ROCKS_COLLISION                         ;#44DA: CD BF 56
        call    SCROLL_FLAGS                                   ;#44DD: CD 0E 55
        call    SCROLL_SMOKE_TRAILS                            ;#44E0: CD 82 5C
        call    UPDATE_SMOKE_STATE                             ;#44E3: CD 01 5C
        call    TICK_STAGE_TIMER                               ;#44E6: CD 2B 94
        ld      a,(STAGE_CLEAR_FLAG)                           ;#44E9: 3A 2F E0
        and     a                                              ;#44EC: A7
        jp      nz,STAGE_CLEAR_BONUS                           ;#44ED: C2 61 45
        ld      a,(PLAYER_DEAD_FLAG)                           ;#44F0: 3A 3B E0
        and     a                                              ;#44F3: A7
        jp      nz,DEATH_SEQUENCE                              ;#44F4: C2 3C 46
        ld      a,(GAME_OVER_FLAG)                             ;#44F7: 3A 49 E0
        and     a                                              ;#44FA: A7
        jr      z,GAME_LOOP                                    ;#44FB: 28 C3
        xor     a                                              ;#44FD: AF
        ld      (SOUND_STATE_THEME),a                          ;#44FE: 32 10 E5
        ld      (FRAME_TICK),a                                 ;#4501: 32 07 E0
        inc     a                                              ;#4504: 3C
        ld      (SOUND_STATE_BANG),a                           ;#4505: 32 62 E5
        ld      hl,844h                                        ;#4508: 21 44 08
        ld      (SAT_SLOT0_PATTERN_COLOR),hl                   ;#450B: 22 02 EB
GAMEOVER_WAIT_PHASE1:
        ; Wait until FRAME_TICK reaches 14h before placing sprite-list terminator
        call    WAIT_VBLANK                                    ;#450E: CD C5 40
        ld      a,(FRAME_TICK)                                 ;#4511: 3A 07 E0
        cp      14h                                            ;#4514: FE 14
        jr      c,GAMEOVER_WAIT_PHASE1                         ;#4516: 38 F6
        ; end sprite list at game over
        ld      a,SPRITE_Y_TERMINATOR                          ;#4518: 3E D0
        ld      (SAT_SLOT1_Y),a                                ;#451A: 32 04 EB
GAMEOVER_WAIT_PHASE2:
        ; Wait until FRAME_TICK reaches 28h before drawing GAME_OVER text
        call    WAIT_VBLANK                                    ;#451D: CD C5 40
        ld      a,(FRAME_TICK)                                 ;#4520: 3A 07 E0
        cp      28h                                            ;#4523: FE 28
        jr      c,GAMEOVER_WAIT_PHASE2                         ;#4525: 38 F6
        ld      a,(LIVES)                                      ;#4527: 3A 35 E0
        and     a                                              ;#452A: A7
        jr      z,GAMEOVER_SHOW_EXTRA_LIFE                     ;#452B: 28 10
        dec     a                                              ;#452D: 3D
        ld      (LIVES),a                                      ;#452E: 32 35 E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4531: 3A 30 E0
        cpl                                                    ;#4534: 2F
        and     3                                              ;#4535: E6 03
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4537: CA D8 43
        jp      STAGE_RESUME                                   ;#453A: C3 00 44

GAMEOVER_SHOW_EXTRA_LIFE:
        ; LIVES==0 branch: paint SAT_EXTRA_LIFE entry then fall into wait phase 3
        ld      hl,SAT_EXTRA_LIFE                              ;#453D: 21 58 45
        ld      de,SAT_MIRROR                                  ;#4540: 11 00 EB
        ld      bc,9                                           ;#4543: 01 09 00
        ldir                                                   ;#4546: ED B0
GAMEOVER_WAIT_PHASE3:
        ; Wait until FRAME_TICK >= 50h, then loop back to next-stage restart
        call    WAIT_VBLANK                                    ;#4548: CD C5 40
        ld      a,(FRAME_TICK)                                 ;#454B: 3A 07 E0
        cp      50h                                            ;#454E: FE 50
        jr      c,GAMEOVER_WAIT_PHASE3                         ;#4550: 38 F6
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#4552: CD B9 40
        jp      INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART       ;#4555: C3 85 43

SAT_EXTRA_LIFE:
        ; 9-byte SAT data: copied to SAT_MIRROR when an extra life is awarded
        ; SAT_EXTRA_LIFE is 9-byte SAT data copied into SAT_MIRROR when the player earns
        ; an extra life. Shows a brief sprite overlay (likely a "1UP" or "EXTRA"
        ; indicator) on the HUD.
        dh      "5750D00F5760D40FD0"                           ;#4558: 57 50 D0 0F 57 60 D4 0F D0

STAGE_CLEAR_BONUS:
        ; Kill MUSIC_THEME, start MUSIC_STAGE_CLEAR, drain FUEL_LEVEL into score
        ; STAGE_CLEAR_BONUS plays the stage-clear sequence: kill MUSIC_THEME, trigger
        ; MUSIC_STAGE_CLEAR (victory jingle), wait for it to drain, then convert
        ; remaining FUEL_LEVEL into bonus score using one of 4 DRAIN_FUEL_* variants
        ; (slower drain at higher stages = longer display = more "satisfying" bonus
        ; animation).
        xor     a                                              ;#4561: AF
        ld      (SOUND_STATE_THEME),a                          ;#4562: 32 10 E5
        ld      (PLAYER_DEAD_FLAG),a                           ;#4565: 32 3B E0
        inc     a                                              ;#4568: 3C
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#4569: 32 30 E5
        call    UPDATE_SCORE_HUD                               ;#456C: CD 5F 8A
STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR:
        ; Spin until SOUND_STATE_STAGE_CLEAR reaches 0 (victory jingle drained)
        call    WAIT_VBLANK                                    ;#456F: CD C5 40
        ld      a,(SOUND_STATE_STAGE_CLEAR)                    ;#4572: 3A 30 E5
        and     a                                              ;#4575: A7
        jr      nz,STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR    ;#4576: 20 F7
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4578: 3A 30 E0
        cp      0Ch                                            ;#457B: FE 0C
        jp      nc,STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH        ;#457D: D2 09 46
        cp      8                                              ;#4580: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP         ;#4582: 30 5D
        cp      4                                              ;#4584: FE 04
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP         ;#4586: 30 2E
STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP:
        ; Drain-fuel loop (stages 0-3): 4x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#4588: CD C5 40
        xor     a                                              ;#458B: AF
        ld      (SOUND_STATE_BONUS),a                          ;#458C: 32 51 E5
        ld      b,2                                            ;#458F: 06 02
STAGE_CLEAR_BONUS_QUAD_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#4591: 3A 39 E0
        and     a                                              ;#4594: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4595: CA D8 43
        call    DRAIN_FUEL_QUAD_TICK                           ;#4598: CD A4 45
        djnz    STAGE_CLEAR_BONUS_QUAD_TICK_TOP                ;#459B: 10 F4
        ld      a,1                                            ;#459D: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#459F: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP              ;#45A2: 18 E4

DRAIN_FUEL_QUAD_TICK:
        ; 4x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — fastest drain variant (stage 0-3)
        push    bc                                             ;#45A4: C5
        call    TICK_FUEL_REFRESH                              ;#45A5: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#45A8: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#45AB: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#45AE: CD 34 94
        call    BCD_ADD_TO_BONUS                               ;#45B1: CD 1D 8B
        pop     bc                                             ;#45B4: C1
        ret                                                    ;#45B5: C9

STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP:
        ; Drain-fuel loop (stages 4-7): 3x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45B6: CD C5 40
        xor     a                                              ;#45B9: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45BA: 32 51 E5
        ld      b,3                                            ;#45BD: 06 03
STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45BF: 3A 39 E0
        and     a                                              ;#45C2: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45C3: CA D8 43
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#45C6: CD D2 45
        djnz    STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP              ;#45C9: 10 F4
        ld      a,1                                            ;#45CB: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45CD: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP            ;#45D0: 18 E4

DRAIN_FUEL_TRIPLE_TICK:
        ; 3x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — drain variant (stage 4-7)
        push    bc                                             ;#45D2: C5
        call    TICK_FUEL_REFRESH                              ;#45D3: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#45D6: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#45D9: CD 34 94
        call    BCD_ADD_TO_BONUS                               ;#45DC: CD 1D 8B
        pop     bc                                             ;#45DF: C1
        ret                                                    ;#45E0: C9

STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP:
        ; Drain-fuel loop (stages 8-Bh): 2x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45E1: CD C5 40
        xor     a                                              ;#45E4: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45E5: 32 51 E5
        ld      b,4                                            ;#45E8: 06 04
STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45EA: 3A 39 E0
        and     a                                              ;#45ED: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45EE: CA D8 43
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#45F1: CD FD 45
        djnz    STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP              ;#45F4: 10 F4
        ld      a,1                                            ;#45F6: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45F8: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP            ;#45FB: 18 E4

DRAIN_FUEL_DOUBLE_TICK:
        ; Two TICK_FUEL_REFRESH calls + BCD_ADD_TO_BONUS overlap — 2x drain rate variant
        push    bc                                             ;#45FD: C5
        call    TICK_FUEL_REFRESH                              ;#45FE: CD 34 94
        call    TICK_FUEL_REFRESH                              ;#4601: CD 34 94
        call    BCD_ADD_TO_BONUS                               ;#4604: CD 1D 8B
        pop     bc                                             ;#4607: C1
        ret                                                    ;#4608: C9

STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH:
        ; Drain-fuel loop (stage >=Ch): 1x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#4609: CD C5 40
        xor     a                                              ;#460C: AF
        ld      (SOUND_STATE_BONUS),a                          ;#460D: 32 51 E5
        ld      b,8                                            ;#4610: 06 08
STAGE_CLEAR_BONUS_SINGLE_TICK_TOP:
        ; Inner djnz loop body (stage-8plus drain rate)
        ld      a,(FUEL_LEVEL)                                 ;#4612: 3A 39 E0
        and     a                                              ;#4615: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4616: CA D8 43
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#4619: CD 25 46
        djnz    STAGE_CLEAR_BONUS_SINGLE_TICK_TOP              ;#461C: 10 F4
        ld      a,1                                            ;#461E: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4620: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH           ;#4623: 18 E4

DRAIN_FUEL_TICK_TO_BONUS:
        ; Wrap TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS to drain one fuel into bonus
        ; DRAIN_FUEL_TICK_TO_BONUS — 1× wrap. Calls TICK_FUEL_REFRESH then
        ; BCD_ADD_TO_BONUS (overlap entry adding 10h to BONUS_BCD). Used by
        ; STAGE_CLEAR_BONUS at the slowest drain rate (stage 12+).
        push    bc                                             ;#4625: C5
        call    TICK_FUEL_REFRESH                              ;#4626: CD 34 94
        call    BCD_ADD_TO_BONUS                               ;#4629: CD 1D 8B
        pop     bc                                             ;#462C: C1
        ret                                                    ;#462D: C9

TEXT_ROUND:
        ; "ROUND " label (6 bytes, ASCII + trailing space tile 40h)
        db      "ROUND@"                                       ;#462E: 52 4F 55 4E 44 40

DIGIT_TEMPLATE_F0:
        ; 8-byte tile run F0..F7 used as 8 score-style digit slot positions
        dh      "F0F1F2F3F4F5F6F7"                             ;#4634: F0 F1 F2 F3 F4 F5 F6 F7

DEATH_SEQUENCE:
        ; Player-death animation entry; pp E0B8 to E0BC, etc., before respawn
        ; DEATH_SEQUENCE handles a player-rock or player-enemy collision. Saves
        ; STAGE_TIMER pair (E0B8, E0B9 → E0BC) so it can resume after the death
        ; animation. Plays death SFX, animates player car explosion, then either: LIVES
        ; > 0 → respawn at start position; LIVES = 0 → set GAME_OVER_FLAG to trigger
        ; GAME_OVER_SEQUENCE next frame.
        ld      hl,(STAGE_TIMER_OUTER)                         ;#463C: 2A 38 E0
        ld      (SAVED_TIMER_FOR_DEATH),hl                     ;#463F: 22 3C E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4642: 3A 30 E0
        cp      0Ch                                            ;#4645: FE 0C
        jr      nc,STAGE_CLEAR_BONUS_RESTORE_AND_RETURN        ;#4647: 30 59
        cp      8                                              ;#4649: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK          ;#464B: 30 3A
        cp      4                                              ;#464D: FE 04
        jr      nc,STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH        ;#464F: 30 1B
STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER:
        ; Single-tick branch: zero SFX_BONUS each iteration to retrigger drain sound
        call    WAIT_VBLANK                                    ;#4651: CD C5 40
        xor     a                                              ;#4654: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4655: 32 51 E5
        ld      b,2                                            ;#4658: 06 02
DEATH_RESET_LOOP_HEAD:
        ; Inner djnz loop within DEATH_SEQUENCE phase 1
        ld      a,(FUEL_LEVEL)                                 ;#465A: 3A 39 E0
        and     a                                              ;#465D: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#465E: 28 5D
        call    DRAIN_FUEL_QUAD_TICK                           ;#4660: CD A4 45
        djnz    DEATH_RESET_LOOP_HEAD                          ;#4663: 10 F5
        ld      a,1                                            ;#4665: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4667: 32 51 E5
        jr      STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER             ;#466A: 18 E5

STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH:
        ; Mirror of LOOP_SFX_TRIGGER for the stage-4plus drain path
        call    WAIT_VBLANK                                    ;#466C: CD C5 40
        xor     a                                              ;#466F: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4670: 32 51 E5
        ld      b,3                                            ;#4673: 06 03
DEATH_RESET_LOOP_HEAD_2:
        ; Inner djnz loop within DEATH_SEQUENCE phase 2
        ld      a,(FUEL_LEVEL)                                 ;#4675: 3A 39 E0
        and     a                                              ;#4678: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4679: 28 42
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#467B: CD D2 45
        djnz    DEATH_RESET_LOOP_HEAD_2                        ;#467E: 10 F5
        ld      a,1                                            ;#4680: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4682: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH           ;#4685: 18 E5

STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK:
        ; Check FUEL_LEVEL = 0: when drained, jump to ISH_PALETTE_REFRESH
        call    WAIT_VBLANK                                    ;#4687: CD C5 40
        xor     a                                              ;#468A: AF
        ld      (SOUND_STATE_BONUS),a                          ;#468B: 32 51 E5
        ld      b,4                                            ;#468E: 06 04
DEATH_RESET_LOOP_HEAD_3:
        ; Inner djnz loop within DEATH_SEQUENCE phase 3
        ld      a,(FUEL_LEVEL)                                 ;#4690: 3A 39 E0
        and     a                                              ;#4693: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4694: 28 27
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#4696: CD FD 45
        djnz    DEATH_RESET_LOOP_HEAD_3                        ;#4699: 10 F5
        ld      a,1                                            ;#469B: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#469D: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK             ;#46A0: 18 E5

STAGE_CLEAR_BONUS_RESTORE_AND_RETURN:
        ; Drain finished: restore SFX_BONUS trigger then return to gameplay flow
        call    WAIT_VBLANK                                    ;#46A2: CD C5 40
        xor     a                                              ;#46A5: AF
        ld      (SOUND_STATE_BONUS),a                          ;#46A6: 32 51 E5
        ld      b,8                                            ;#46A9: 06 08
DEATH_RESET_LOOP_HEAD_4:
        ; Inner djnz loop within DEATH_SEQUENCE phase 4
        ld      a,(FUEL_LEVEL)                                 ;#46AB: 3A 39 E0
        and     a                                              ;#46AE: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#46AF: 28 0C
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#46B1: CD 25 46
        djnz    DEATH_RESET_LOOP_HEAD_4                        ;#46B4: 10 F5
        ld      a,1                                            ;#46B6: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#46B8: 32 51 E5
        jr      STAGE_CLEAR_BONUS_RESTORE_AND_RETURN           ;#46BB: 18 E5

DEATH_RESTORE_TIMER:
        ; Restore (STAGE_TIMER_OUTER, FUEL_LEVEL) from SAVED_TIMER_FOR_DEATH and reset
        ld      hl,(SAVED_TIMER_FOR_DEATH)                     ;#46BD: 2A 3C E0
        ld      (STAGE_TIMER_OUTER),hl                         ;#46C0: 22 38 E0
        xor     a                                              ;#46C3: AF
        ld      (PLAYER_DEAD_FLAG),a                           ;#46C4: 32 3B E0
        ld      (PLAYER_MOVE_GATE),a                           ;#46C7: 32 45 E0
        ld      a,h                                            ;#46CA: 7C
        cp      0Ah                                            ;#46CB: FE 0A
        jr      c,DEATH_PAINT_DIGITS                           ;#46CD: 38 10
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#46CF: 21 9C 07
        ld      a,0A1h                                         ;#46D2: 3E A1
        call    BIOS_WRTVRM                                    ;#46D4: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#46D7: 21 9D 07
        ld      a,0A1h                                         ;#46DA: 3E A1
        call    BIOS_WRTVRM                                    ;#46DC: CD 4D 00
DEATH_PAINT_DIGITS:
        ; After digits painted: refresh fuel gauge and resume GAME_LOOP
        call    UPDATE_FUEL_GAUGE                              ;#46DF: CD 75 94
        jp      GAME_LOOP                                      ;#46E2: C3 C0 44

DRAW_CHALLENGING_STAGE_SCREEN:
        ; Render "CHALLENGING STAGE NO <N>" text + stage-number sprites
        ; DRAW_CHALLENGING_STAGE_SCREEN composes the "CHALLENGING STAGE NO X" screen
        ; between stages. Decodes the stage number into 2 digits via an inline decimal-
        ; conversion loop, writes both digits to the name table via BIOS_WRTVRM, then
        ; LDIRVMs TEXT_CHALLENGING_STAGE and TEXT_NO to fixed positions in the name
        ; table. SAT_STAGE_INDICATOR sprites overlay the digits at sprite-sized
        ; positions.
        and     3Fh                                            ;#46E5: E6 3F
        inc     a                                              ;#46E7: 3C
        ld      c,0                                            ;#46E8: 0E 00
DEATH_DIGIT_DIVMOD:
        ; Divmod-10 loop for death-screen score digit
        cp      0Ah                                            ;#46EA: FE 0A
        jr      c,DEATH_DIGIT_LOOP_TAIL                        ;#46EC: 38 05
        inc     c                                              ;#46EE: 0C
        sub     0Ah                                            ;#46EF: D6 0A
        jr      DEATH_DIGIT_DIVMOD                             ;#46F1: 18 F7

DEATH_DIGIT_LOOP_TAIL:
        ; Digit-loop tail: store B in VRAM at the computed position
        ld      b,a                                            ;#46F3: 47
        ld      hl,400h                                        ;#46F4: 21 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#46F7: 3A 0E E0
        and     a                                              ;#46FA: A7
        jr      z,CHALLENGE_RIGHT_BANK                         ;#46FB: 28 03
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#46FD: 21 00 14
CHALLENGE_RIGHT_BANK:
        ; CHALLENGING STAGE bank-B path: emit text to VRAM 14Eh + bank offset
        push    hl                                             ;#4700: E5
        ld      de,14Eh                                        ;#4701: 11 4E 01
        add     hl,de                                          ;#4704: 19
        ld      a,c                                            ;#4705: 79
        and     a                                              ;#4706: A7
        jr      z,CHALLENGE_FALLTHROUGH                        ;#4707: 28 08
        push    bc                                             ;#4709: C5
        push    hl                                             ;#470A: E5
        call    BIOS_WRTVRM                                    ;#470B: CD 4D 00
        pop     hl                                             ;#470E: E1
        pop     bc                                             ;#470F: C1
        inc     hl                                             ;#4710: 23
CHALLENGE_FALLTHROUGH:
        ; Common tail after bank-A/B selection: write ones digit via BIOS_WRTVRM
        ld      a,b                                            ;#4711: 78
        call    BIOS_WRTVRM                                    ;#4712: CD 4D 00
        pop     hl                                             ;#4715: E1
        push    hl                                             ;#4716: E5
        LOAD_VRAM_ADDRESS de, 104h                             ;#4717: 11 04 01
        add     hl,de                                          ;#471A: 19
        ex      de,hl                                          ;#471B: EB
        ld      hl,TEXT_CHALLENGING_STAGE                      ;#471C: 21 77 47
        ld      bc,11h                                         ;#471F: 01 11 00
        call    BIOS_LDIRVM                                    ;#4722: CD 5C 00
        pop     hl                                             ;#4725: E1
        push    hl                                             ;#4726: E5
        LOAD_VRAM_ADDRESS de, 14Bh                             ;#4727: 11 4B 01
        add     hl,de                                          ;#472A: 19
        ex      de,hl                                          ;#472B: EB
        ld      hl,TEXT_NO                                     ;#472C: 21 88 47
        ld      bc,3                                           ;#472F: 01 03 00
        call    BIOS_LDIRVM                                    ;#4732: CD 5C 00
        pop     hl                                             ;#4735: E1
        push    hl                                             ;#4736: E5
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#4737: 3A 40 E0
        rra                                                    ;#473A: 1F
        rra                                                    ;#473B: 1F
        rra                                                    ;#473C: 1F
        rra                                                    ;#473D: 1F
        and     0Fh                                            ;#473E: E6 0F
        ld      de,1AEh                                        ;#4740: 11 AE 01
        add     hl,de                                          ;#4743: 19
        call    BIOS_WRTVRM                                    ;#4744: CD 4D 00
        ld      a,(ROCK_SPAWN_COUNT)                           ;#4747: 3A 1C E0
        ld      c,0                                            ;#474A: 0E 00
        cp      0Ah                                            ;#474C: FE 0A
        jr      c,CHALLENGE_ROCK_NO_DIVMOD                     ;#474E: 38 03
        inc     c                                              ;#4750: 0C
        sub     0Ah                                            ;#4751: D6 0A
CHALLENGE_ROCK_NO_DIVMOD:
        ; No-divmod path: ROCK_SPAWN_COUNT < 10, draw ones digit only
        pop     hl                                             ;#4753: E1
        ld      de,20Eh                                        ;#4754: 11 0E 02
        add     hl,de                                          ;#4757: 19
        ld      b,a                                            ;#4758: 47
        ld      a,c                                            ;#4759: 79
        and     a                                              ;#475A: A7
        jr      z,CHALLENGE_WRITE_ONES_DIGIT                   ;#475B: 28 08
        push    hl                                             ;#475D: E5
        push    bc                                             ;#475E: C5
        call    BIOS_WRTVRM                                    ;#475F: CD 4D 00
        pop     bc                                             ;#4762: C1
        pop     hl                                             ;#4763: E1
        inc     hl                                             ;#4764: 23
CHALLENGE_WRITE_ONES_DIGIT:
        ; Write the ones digit of ROCK_SPAWN_COUNT, then LDIRVM the SAT indicator
        ld      a,b                                            ;#4765: 78
        call    BIOS_WRTVRM                                    ;#4766: CD 4D 00
        ld      hl,SAT_STAGE_INDICATOR                         ;#4769: 21 8B 47
        ld      de,SAT_MIRROR                                  ;#476C: 11 00 EB
        ld      bc,9                                           ;#476F: 01 09 00
        ldir                                                   ;#4772: ED B0
        jp      UPDATE_SCORE_HUD                               ;#4774: C3 5F 8A

TEXT_CHALLENGING_STAGE:
        ; "CHALLENGING STAGE" string (17 bytes, ASCII)
        db      "CHALLENGING STAGE"                            ;#4777: 43 48 41 4C 4C 45 4E 47 49 4E 47 20 53 54 41 47 45

TEXT_NO:
        ; "NO]" suffix text (3 bytes)
        db      "NO]"                                          ;#4788: 4E 4F 5D

SAT_STAGE_INDICATOR:
        ; 9-byte SAT data for stage-number sprite display (2 sprites + terminator)
        ; SAT_STAGE_INDICATOR is 9 bytes of SAT data uploaded to SAT_MIRROR to show the
        ; stage-number sprites on the "CHALLENGING STAGE" screen. Contains 2 sprite
        ; entries (4 bytes each) + terminator (Y=D0h).
        dh      "635800087B583C09D0"                           ;#478B: 63 58 00 08 7B 58 3C 09 D0

DRAW_PLAYER_CAR:
        ; Rotate animation phase toward PLAYER_DIRECTION; emit car sprite at screen centre
        ; DRAW_PLAYER_CAR runs every other frame (gated by FRAME_TICK low bit). Reads
        ; PLAYER_DIRECTION (lower 2 bits), computes a target rotation angle, and slews
        ; PLAYER_ROTATION_PHASE by +/-4 toward it (modulo 30h). Then emits the player
        ; car sprite at fixed screen-center (Y=57h, X=58h) with the rotation phase as
        ; the tile index and color 5 (cyan).
        ld      a,(FRAME_TICK)                                 ;#4794: 3A 07 E0
        rra                                                    ;#4797: 1F
        jr      nc,PLAYER_EMIT_SPRITE                          ;#4798: 30 2E
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#479A: 3A 2B E0
        ld      c,a                                            ;#479D: 4F
        ld      a,(PLAYER_DIRECTION)                           ;#479E: 3A 11 E0
        and     3                                              ;#47A1: E6 03
        ld      b,a                                            ;#47A3: 47
        add     a,a                                            ;#47A4: 87
        add     a,b                                            ;#47A5: 80
        add     a,a                                            ;#47A6: 87
        add     a,a                                            ;#47A7: 87
        sub     c                                              ;#47A8: 91
        jr      z,PLAYER_EMIT_SPRITE                           ;#47A9: 28 1D
        jr      nc,PLAYER_DELTA_NORMALIZED                     ;#47AB: 30 02
        add     a,30h                                          ;#47AD: C6 30
PLAYER_DELTA_NORMALIZED:
        ; Direction delta normalized to [0..2Fh]; pick rotate-minus or rotate-plus
        cp      18h                                            ;#47AF: FE 18
        jr      c,PLAYER_ROTATE_PLUS                           ;#47B1: 38 0A
        ld      a,c                                            ;#47B3: 79
        sub     4                                              ;#47B4: D6 04
        jr      nc,PLAYER_STORE_ROTATION                       ;#47B6: 30 0D
        ld      a,2Ch                                          ;#47B8: 3E 2C
        jp      PLAYER_STORE_ROTATION                          ;#47BA: C3 C5 47

PLAYER_ROTATE_PLUS:
        ; Rotate phase by +4 (mod 30h) toward target direction
        ld      a,c                                            ;#47BD: 79
        add     a,4                                            ;#47BE: C6 04
        cp      30h                                            ;#47C0: FE 30
        jr      c,PLAYER_STORE_ROTATION                        ;#47C2: 38 01
        xor     a                                              ;#47C4: AF
PLAYER_STORE_ROTATION:
        ; Store updated PLAYER_ROTATION_PHASE
        ld      (PLAYER_ROTATION_PHASE),a                      ;#47C5: 32 2B E0
PLAYER_EMIT_SPRITE:
        ; Skip-update branch (gated by FRAME_TICK low bit): emit player sprite
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#47C8: 3A 2B E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#47CB: 2A 14 E0
        ; emit player sprite
        ld      (hl),57h                                       ;#47CE: 36 57
        inc     hl                                             ;#47D0: 23
        ld      (hl),58h                                       ;#47D1: 36 58
        inc     hl                                             ;#47D3: 23
        ld      (hl),a                                         ;#47D4: 77
        inc     hl                                             ;#47D5: 23
        ld      (hl),5                                         ;#47D6: 36 05
        inc     hl                                             ;#47D8: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#47D9: 22 14 E0
        ld      bc,101h                                        ;#47DC: 01 01 01
        ld      a,(PLAYER_VELOCITY_X)                          ;#47DF: 3A 09 E0
        bit     7,a                                            ;#47E2: CB 7F
        jr      z,PLAYER_APPLY_X_VEL                           ;#47E4: 28 03
        neg                                                    ;#47E6: ED 44
        dec     b                                              ;#47E8: 05
PLAYER_APPLY_X_VEL:
        ; Velocity-Y not negative: store positive velocity and update WORLD_X_POS
        sub     0Ah                                            ;#47E9: D6 0A
        ld      e,a                                            ;#47EB: 5F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#47EC: 3A 0B E0
        bit     7,a                                            ;#47EF: CB 7F
        jr      z,PLAYER_APPLY_Y_VEL                           ;#47F1: 28 03
        neg                                                    ;#47F3: ED 44
        dec     c                                              ;#47F5: 0D
PLAYER_APPLY_Y_VEL:
        ; Velocity-Y negative: store inverted velocity and update WORLD_Y_POS
        sub     0Ah                                            ;#47F6: D6 0A
        ld      d,a                                            ;#47F8: 57
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#47F9: 21 0F E0
        ld      a,(hl)                                         ;#47FC: 7E
        add     a,b                                            ;#47FD: 80
        ld      (PLAYER_SCREEN_X),a                            ;#47FE: 32 23 E0
        ld      b,a                                            ;#4801: 47
        inc     hl                                             ;#4802: 23
        ld      a,(hl)                                         ;#4803: 7E
        add     a,c                                            ;#4804: 81
        ld      (PLAYER_SCREEN_Y),a                            ;#4805: 32 24 E0
        ld      l,a                                            ;#4808: 6F
        ld      h,b                                            ;#4809: 60
        call    DEPLOY_SMOKE_IF_INPUT                          ;#480A: CD B8 49
        ld      a,(PLAYER_DIRECTION)                           ;#480D: 3A 11 E0
        call    AI_PICK_VALID_DIRECTION                        ;#4810: CD 30 4A
        ld      hl,(PLAYFIELD_SCROLL_OFFSET)                   ;#4813: 2A 12 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#4816: 3A 45 E0
        and     a                                              ;#4819: A7
        jr      nz,SCROLL_CHECK_BACKWARD                       ;#481A: 20 17
        ld      a,(SCROLL_LIMIT_HI)                            ;#481C: 3A 44 E0
        cp      h                                              ;#481F: BC
        jr      nz,SCROLL_ADVANCE_FORWARD                      ;#4820: 20 08
        ld      a,(SCROLL_LIMIT_LO)                            ;#4822: 3A 43 E0
        cp      l                                              ;#4825: BD
        jr      z,DISPATCH_PLAYER_DIRECTION                    ;#4826: 28 1B
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#4828: 38 19
SCROLL_ADVANCE_FORWARD:
        ; Scroll bounds advance: increment PLAYFIELD_SCROLL_OFFSET by 10h
        ld      de,10h                                         ;#482A: 11 10 00
        add     hl,de                                          ;#482D: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#482E: 22 12 E0
        jr      DISPATCH_PLAYER_DIRECTION                      ;#4831: 18 10

SCROLL_CHECK_BACKWARD:
        ; Move-gate active: check whether scroll should retreat
        ld      a,h                                            ;#4833: 7C
        and     a                                              ;#4834: A7
        jr      nz,SCROLL_RETREAT                              ;#4835: 20 05
        ld      a,l                                            ;#4837: 7D
        cp      0C0h                                           ;#4838: FE C0
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#483A: 38 07
SCROLL_RETREAT:
        ; Scroll bounds retreat: subtract 8 from PLAYFIELD_SCROLL_OFFSET
        ld      de,-8                                          ;#483C: 11 F8 FF
        add     hl,de                                          ;#483F: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4840: 22 12 E0
DISPATCH_PLAYER_DIRECTION:
        ; 4-way switch on PLAYER_DIRECTION&3 into per-direction movement handlers
        ; DISPATCH_PLAYER_DIRECTION reads PLAYER_DIRECTION lower 2 bits (0/1/2/3 =
        ; up/right/down/left), then jumps to MOVE_PLAYER_DIRECTION_0..3. Each handler
        ; updates WORLD_X_POS or WORLD_Y_POS, derives WORLD_SCROLL_DX/DY for the per-
        ; frame world scroll, and verifies movement via LOOKUP_ PLAYFIELD_CELL to detect
        ; wall collisions.
        ex      de,hl                                          ;#4843: EB
        ld      a,(PLAYER_DIRECTION)                           ;#4844: 3A 11 E0
        and     3                                              ;#4847: E6 03
        jp      z,MOVE_PLAYER_DIRECTION_0                      ;#4849: CA AE 48
        dec     a                                              ;#484C: 3D
        jp      z,MOVE_PLAYER_DIRECTION_1                      ;#484D: CA 60 49
        dec     a                                              ;#4850: 3D
        jp      z,MOVE_PLAYER_DIRECTION_2                      ;#4851: CA 08 49
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4854: 3A 0B E0
        ld      c,a                                            ;#4857: 4F
        and     a                                              ;#4858: A7
        ld      a,0Ch                                          ;#4859: 3E 0C
        jp      p,MOVE_DIR3_STORE_VEL                          ;#485B: F2 60 48
        ld      a,0F4h                                         ;#485E: 3E F4
MOVE_DIR3_STORE_VEL:
        ; Direction-3 (left) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#4860: 32 0B E0
        sub     c                                              ;#4863: 91
        neg                                                    ;#4864: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#4866: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4869: CD 5E 57
        ld      hl,(WORLD_X_POS)                               ;#486C: 2A 08 E0
        and     a                                              ;#486F: A7
        ld      a,h                                            ;#4870: 7C
        sbc     hl,de                                          ;#4871: ED 52
        ld      (WORLD_X_POS),hl                               ;#4873: 22 08 E0
        sub     h                                              ;#4876: 94
        ld      (WORLD_SCROLL_DX),a                            ;#4877: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#487A: CD 38 57
        ld      a,h                                            ;#487D: 7C
        add     a,14h                                          ;#487E: C6 14
        ret     p                                              ;#4880: F0
        add     a,4                                            ;#4881: C6 04
        ld      (PLAYER_VELOCITY_X),a                          ;#4883: 32 09 E0
        ld      hl,STEP_COUNTER                                ;#4886: 21 0D E0
        inc     (hl)                                           ;#4889: 34
        inc     (hl)                                           ;#488A: 34
        inc     (hl)                                           ;#488B: 34
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#488C: 21 0F E0
        dec     (hl)                                           ;#488F: 35
        ld      hl,TRACK_DATA_RING_END-3                       ;#4890: 21 80 EF
        ld      de,TRACK_DATA_RING_END                         ;#4893: 11 83 EF
        ld      bc,381h                                        ;#4896: 01 81 03
        lddr                                                   ;#4899: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#489B: 21 0F E0
        ld      a,(hl)                                         ;#489E: 7E
        sub     4                                              ;#489F: D6 04
        ld      c,a                                            ;#48A1: 4F
        inc     hl                                             ;#48A2: 23
        ld      a,(hl)                                         ;#48A3: 7E
        sub     4                                              ;#48A4: D6 04
        ld      l,a                                            ;#48A6: 6F
        ld      h,c                                            ;#48A7: 61
        ld      de,TRACK_DATA_RING                             ;#48A8: 11 00 EC
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#48AB: C3 80 4A

MOVE_PLAYER_DIRECTION_0:
        ; Direction-0 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#48AE: 3A 09 E0
        ld      c,a                                            ;#48B1: 4F
        and     a                                              ;#48B2: A7
        ld      a,0Ch                                          ;#48B3: 3E 0C
        jp      p,MOVE_DIR0_STORE_VEL                          ;#48B5: F2 BA 48
        ld      a,0F4h                                         ;#48B8: 3E F4
MOVE_DIR0_STORE_VEL:
        ; Direction-0 (up) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#48BA: 32 09 E0
        sub     c                                              ;#48BD: 91
        neg                                                    ;#48BE: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#48C0: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#48C3: CD 38 57
        ld      hl,(WORLD_Y_POS)                               ;#48C6: 2A 0A E0
        and     a                                              ;#48C9: A7
        ld      a,h                                            ;#48CA: 7C
        sbc     hl,de                                          ;#48CB: ED 52
        ld      (WORLD_Y_POS),hl                               ;#48CD: 22 0A E0
        sub     h                                              ;#48D0: 94
        ld      (WORLD_SCROLL_DY),a                            ;#48D1: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#48D4: CD 5E 57
        ld      a,h                                            ;#48D7: 7C
        add     a,14h                                          ;#48D8: C6 14
        ret     p                                              ;#48DA: F0
        add     a,4                                            ;#48DB: C6 04
        ld      (PLAYER_VELOCITY_Y),a                          ;#48DD: 32 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#48E0: 21 0C E0
        inc     (hl)                                           ;#48E3: 34
        inc     (hl)                                           ;#48E4: 34
        inc     (hl)                                           ;#48E5: 34
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#48E6: 21 10 E0
        dec     (hl)                                           ;#48E9: 35
        ld      hl,TRACK_DATA_RING_END-5Ah                     ;#48EA: 21 29 EF
        ld      de,TRACK_DATA_RING_END                         ;#48ED: 11 83 EF
        ld      bc,32Ah                                        ;#48F0: 01 2A 03
        lddr                                                   ;#48F3: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#48F5: 21 0F E0
        ld      a,(hl)                                         ;#48F8: 7E
        sub     4                                              ;#48F9: D6 04
        ld      c,a                                            ;#48FB: 4F
        inc     hl                                             ;#48FC: 23
        ld      a,(hl)                                         ;#48FD: 7E
        sub     4                                              ;#48FE: D6 04
        ld      l,a                                            ;#4900: 6F
        ld      h,c                                            ;#4901: 61
        ld      de,TRACK_DATA_RING                             ;#4902: 11 00 EC
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#4905: C3 70 4A

MOVE_PLAYER_DIRECTION_2:
        ; Direction-2 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#4908: 3A 09 E0
        ld      c,a                                            ;#490B: 4F
        and     a                                              ;#490C: A7
        ld      a,0Ch                                          ;#490D: 3E 0C
        jp      p,MOVE_DIR2_STORE_VEL                          ;#490F: F2 14 49
        ld      a,0F4h                                         ;#4912: 3E F4
MOVE_DIR2_STORE_VEL:
        ; Direction-2 (right) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#4914: 32 09 E0
        sub     c                                              ;#4917: 91
        neg                                                    ;#4918: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#491A: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#491D: CD 38 57
        ld      hl,(WORLD_Y_POS)                               ;#4920: 2A 0A E0
        ld      a,h                                            ;#4923: 7C
        add     hl,de                                          ;#4924: 19
        ld      (WORLD_Y_POS),hl                               ;#4925: 22 0A E0
        sub     h                                              ;#4928: 94
        ld      (WORLD_SCROLL_DY),a                            ;#4929: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#492C: CD 5E 57
        ld      a,h                                            ;#492F: 7C
        sub     15h                                            ;#4930: D6 15
        ret     m                                              ;#4932: F8
        sub     3                                              ;#4933: D6 03
        ld      (PLAYER_VELOCITY_Y),a                          ;#4935: 32 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#4938: 21 0C E0
        dec     (hl)                                           ;#493B: 35
        dec     (hl)                                           ;#493C: 35
        dec     (hl)                                           ;#493D: 35
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#493E: 21 10 E0
        inc     (hl)                                           ;#4941: 34
        ld      hl,TRACK_DATA_RING+5Ah    ; 2nd enemy-path record ;#4942: 21 5A EC
        ld      de,TRACK_DATA_RING                             ;#4945: 11 00 EC
        ld      bc,32Ah                                        ;#4948: 01 2A 03
        ldir                                                   ;#494B: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#494D: 21 0F E0
        ld      a,(hl)                                         ;#4950: 7E
        sub     4                                              ;#4951: D6 04
        ld      c,a                                            ;#4953: 4F
        inc     hl                                             ;#4954: 23
        ld      a,(hl)                                         ;#4955: 7E
        add     a,5                                            ;#4956: C6 05
        ld      l,a                                            ;#4958: 6F
        ld      h,c                                            ;#4959: 61
        ld      de,TRACK_DATA_RING_END-59h                     ;#495A: 11 2A EF
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#495D: C3 70 4A

MOVE_PLAYER_DIRECTION_1:
        ; Direction-1 movement handler
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4960: 3A 0B E0
        ld      c,a                                            ;#4963: 4F
        and     a                                              ;#4964: A7
        ld      a,0Ch                                          ;#4965: 3E 0C
        jp      p,MOVE_DIR1_STORE_VEL                          ;#4967: F2 6C 49
        ld      a,0F4h                                         ;#496A: 3E F4
MOVE_DIR1_STORE_VEL:
        ; Direction-1 (down) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#496C: 32 0B E0
        sub     c                                              ;#496F: 91
        neg                                                    ;#4970: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#4972: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4975: CD 5E 57
        ld      hl,(WORLD_X_POS)                               ;#4978: 2A 08 E0
        ld      a,h                                            ;#497B: 7C
        add     hl,de                                          ;#497C: 19
        ld      (WORLD_X_POS),hl                               ;#497D: 22 08 E0
        sub     h                                              ;#4980: 94
        ld      (WORLD_SCROLL_DX),a                            ;#4981: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#4984: CD 38 57
        ld      a,h                                            ;#4987: 7C
        sub     15h                                            ;#4988: D6 15
        ret     m                                              ;#498A: F8
        sub     3                                              ;#498B: D6 03
        ld      (PLAYER_VELOCITY_X),a                          ;#498D: 32 09 E0
        ld      hl,STEP_COUNTER                                ;#4990: 21 0D E0
        dec     (hl)                                           ;#4993: 35
        dec     (hl)                                           ;#4994: 35
        dec     (hl)                                           ;#4995: 35
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4996: 21 0F E0
        inc     (hl)                                           ;#4999: 34
        ld      hl,TRACK_DATA_RING+3                           ;#499A: 21 03 EC
        ld      de,TRACK_DATA_RING                             ;#499D: 11 00 EC
        ld      bc,381h                                        ;#49A0: 01 81 03
        ldir                                                   ;#49A3: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#49A5: 21 0F E0
        ld      a,(hl)                                         ;#49A8: 7E
        add     a,5                                            ;#49A9: C6 05
        ld      c,a                                            ;#49AB: 4F
        inc     hl                                             ;#49AC: 23
        ld      a,(hl)                                         ;#49AD: 7E
        sub     4                                              ;#49AE: D6 04
        ld      l,a                                            ;#49B0: 6F
        ld      h,c                                            ;#49B1: 61
        ld      de,TRACK_DATA_RING+1Bh                         ;#49B2: 11 1B EC
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#49B5: C3 80 4A

DEPLOY_SMOKE_IF_INPUT:
        ; Check input + fuel via POLL_INPUT; if available, drop fuel and refresh gauge
        ; DEPLOY_SMOKE_IF_INPUT. Polls input via POLL_INPUT; if a smoke-deploy key is
        ; held AND SMOKE_COOLDOWN is 0 AND FUEL_LEVEL > 3, deducts 3 from fuel,
        ; refreshes UPDATE_FUEL_GAUGE, sets SMOKE_COOLDOWN=3 frames. The actual smoke
        ; entity spawn happens elsewhere in the smoke subsystem.
        push    hl                                             ;#49B8: E5
        push    de                                             ;#49B9: D5
        call    POLL_INPUT                                     ;#49BA: CD C5 4C
        ld      a,(STAGE_PALETTE_INDEX)                        ;#49BD: 3A 30 E0
        cpl                                                    ;#49C0: 2F
        and     3                                              ;#49C1: E6 03
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49C3: 28 22
        ld      a,c                                            ;#49C5: 79
        cpl                                                    ;#49C6: 2F
        and     0F0h                                           ;#49C7: E6 F0
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49C9: 28 1C
        ld      a,(SMOKE_COOLDOWN)                             ;#49CB: 3A 27 E0
        and     a                                              ;#49CE: A7
        jr      nz,PROCESS_DIRECTION_INPUT                     ;#49CF: 20 16
        ld      a,(FUEL_LEVEL)                                 ;#49D1: 3A 39 E0
        sub     3                                              ;#49D4: D6 03
        jr      c,PROCESS_DIRECTION_INPUT                      ;#49D6: 38 0F
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49D8: 28 0D
        ld      (FUEL_LEVEL),a                                 ;#49DA: 32 39 E0
        push    bc                                             ;#49DD: C5
        call    UPDATE_FUEL_GAUGE                              ;#49DE: CD 75 94
        pop     bc                                             ;#49E1: C1
        ld      a,3                                            ;#49E2: 3E 03
        ld      (SMOKE_COOLDOWN),a                             ;#49E4: 32 27 E0
PROCESS_DIRECTION_INPUT:
        ; Map 4 input bits (up/right/down/left) into TRY_SET_DIRECTION calls
        ; PROCESS_DIRECTION_INPUT takes the input mask in B (one bit per direction) and
        ; tests each bit, calling TRY_SET_DIRECTION with the appropriate direction code
        ; (0=up, 1=left, 2=right, 3=down). Earlier direction bits dominate — diagonal
        ; inputs resolve to vertical.
        ld      b,c                                            ;#49E7: 41
        ld      c,0                                            ;#49E8: 0E 00
        bit     0,b                                            ;#49EA: CB 40
        call    z,TRY_SET_DIRECTION                            ;#49EC: CC 07 4A
        ld      c,2                                            ;#49EF: 0E 02
        bit     1,b                                            ;#49F1: CB 48
        call    z,TRY_SET_DIRECTION                            ;#49F3: CC 07 4A
        ld      c,3                                            ;#49F6: 0E 03
        bit     2,b                                            ;#49F8: CB 50
        call    z,TRY_SET_DIRECTION                            ;#49FA: CC 07 4A
        ld      c,1                                            ;#49FD: 0E 01
        bit     3,b                                            ;#49FF: CB 58
        call    z,TRY_SET_DIRECTION                            ;#4A01: CC 07 4A
        pop     de                                             ;#4A04: D1
        pop     hl                                             ;#4A05: E1
        ret                                                    ;#4A06: C9

TRY_SET_DIRECTION:
        ; Inner: if dir C differs from PLAYER_DIRECTION, validate path then update
        ; TRY_SET_DIRECTION is the inner direction-update helper. The `inc sp; inc sp`
        ; at entry and `dec sp; dec sp` later discard the caller's return address
        ; temporarily — a stack-pointer trick that lets it return TWO frames up to
        ; PROCESS_DIRECTION_INPUT's caller when direction acceptance succeeds. Verifies
        ; the proposed direction via CHECK_DIRECTION_BLOCKED before updating
        ; PLAYER_DIRECTION.
        inc     sp                                             ;#4A07: 33
        inc     sp                                             ;#4A08: 33
        ld      a,(PLAYER_DIRECTION)                           ;#4A09: 3A 11 E0
        cp      c                                              ;#4A0C: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A0D: 28 18
        xor     2                                              ;#4A0F: EE 02
        cp      c                                              ;#4A11: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A12: 28 13
        pop     de                                             ;#4A14: D1
        push    de                                             ;#4A15: D5
        dec     sp                                             ;#4A16: 3B
        dec     sp                                             ;#4A17: 3B
        ld      a,d                                            ;#4A18: 7A
        cp      5                                              ;#4A19: FE 05
        ret     nc                                             ;#4A1B: D0
        ld      a,e                                            ;#4A1C: 7B
        cp      5                                              ;#4A1D: FE 05
        ret     nc                                             ;#4A1F: D0
        push    bc                                             ;#4A20: C5
        call    CHECK_DIRECTION_BLOCKED                        ;#4A21: CD 55 4A
        pop     bc                                             ;#4A24: C1
        ret     c                                              ;#4A25: D8
        pop     hl                                             ;#4A26: E1
TRY_SET_DIRECTION_END:
        ; Tail of TRY_SET_DIRECTION: restore sp adjustment, ret to outer caller
        pop     de                                             ;#4A27: D1
        pop     hl                                             ;#4A28: E1
AI_DIR_FOUND:
        ; Found unblocked direction: mask to 2 bits, store as PLAYER_DIRECTION
        ld      a,c                                            ;#4A29: 79
        and     3                                              ;#4A2A: E6 03
        ld      (PLAYER_DIRECTION),a                           ;#4A2C: 32 11 E0
        ret                                                    ;#4A2F: C9

AI_PICK_VALID_DIRECTION:
        ; Try alternate directions via CHECK_DIRECTION_BLOCKED, set PLAYER_DIRECTION
        ; AI_PICK_VALID_DIRECTION tries up to 4 directions and picks the first non-
        ; blocked one. Calls CHECK_DIRECTION_BLOCKED for each candidate (which returns
        ; carry=1 when blocked). The picked direction is stored in PLAYER_DIRECTION.
        ; Used by both player movement and enemy AI to navigate around obstacles.
        ld      c,a                                            ;#4A30: 4F
        ld      a,e                                            ;#4A31: 7B
        cp      5                                              ;#4A32: FE 05
        ret     nc                                             ;#4A34: D0
        ld      a,d                                            ;#4A35: 7A
        cp      5                                              ;#4A36: FE 05
        ret     nc                                             ;#4A38: D0
        ld      d,h                                            ;#4A39: 54
        ld      e,l                                            ;#4A3A: 5D
        call    CHECK_DIRECTION_BLOCKED                        ;#4A3B: CD 55 4A
        jr      nc,AI_DIR_FOUND                                ;#4A3E: 30 E9
        ld      h,d                                            ;#4A40: 62
        ld      l,e                                            ;#4A41: 6B
        inc     c                                              ;#4A42: 0C
        call    CHECK_DIRECTION_BLOCKED                        ;#4A43: CD 55 4A
        jr      nc,AI_DIR_FOUND                                ;#4A46: 30 E1
        inc     c                                              ;#4A48: 0C
        inc     c                                              ;#4A49: 0C
        ld      h,d                                            ;#4A4A: 62
        ld      l,e                                            ;#4A4B: 6B
        call    CHECK_DIRECTION_BLOCKED                        ;#4A4C: CD 55 4A
        jr      nc,AI_DIR_FOUND                                ;#4A4F: 30 D8
        dec     c                                              ;#4A51: 0D
        jp      AI_DIR_FOUND                                   ;#4A52: C3 29 4A

CHECK_DIRECTION_BLOCKED:
        ; Test if direction C is blocked; returns carry-set when blocked
        ; CHECK_DIRECTION_BLOCKED tests if direction C is blocked. Looks up the
        ; playfield cell adjacent to the current position in that direction via
        ; QUERY_PLAYFIELD_AT; returns carry=1 (blocked) if the cell is a rock/wall,
        ; carry=0 (free) otherwise. Called many times per frame by
        ; AI_PICK_VALID_DIRECTION and player movement.
        ld      a,c                                            ;#4A55: 79
        and     3                                              ;#4A56: E6 03
        jr      z,DIR_BLOCKED_LEFT                             ;#4A58: 28 0A
        dec     a                                              ;#4A5A: 3D
        jr      z,DIR_BLOCKED_DOWN                             ;#4A5B: 28 0B
        dec     a                                              ;#4A5D: 3D
        jr      z,DIR_BLOCKED_RIGHT                            ;#4A5E: 28 0C
        dec     h                                              ;#4A60: 25
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A61: C3 81 4B

DIR_BLOCKED_LEFT:
        ; Direction LEFT blocked path: dec L then jump to LOOKUP_PLAYFIELD_CELL
        dec     l                                              ;#4A64: 2D
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A65: C3 81 4B

DIR_BLOCKED_DOWN:
        ; Direction DOWN blocked path: inc H then jump to LOOKUP_PLAYFIELD_CELL
        inc     h                                              ;#4A68: 24
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A69: C3 81 4B

DIR_BLOCKED_RIGHT:
        ; Direction RIGHT blocked path: inc L then jump to LOOKUP_PLAYFIELD_CELL
        inc     l                                              ;#4A6C: 2C
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A6D: C3 81 4B

SCAN_PLAYFIELD_H_STRIP:
        ; Loop 10 cells along H axis (stride 3), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_H_STRIP scans 10 cells horizontally (along H axis, E += 3 per
        ; cell), invoking QUERY_PLAYFIELD_AT for each. Used by AI routines to find the
        ; closest rock/flag in a row.
        ld      b,0Ah                                          ;#4A70: 06 0A
SCAN_H_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_H_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A72: CD 90 4A
        inc     h                                              ;#4A75: 24
        ld      a,e                                            ;#4A76: 7B
        add     a,3                                            ;#4A77: C6 03
        ld      e,a                                            ;#4A79: 5F
        jr      nc,SCAN_H_STRIP_NEXT                           ;#4A7A: 30 01
        inc     d                                              ;#4A7C: 14
SCAN_H_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_H_STRIP (H += 1, E += 3)
        djnz    SCAN_H_STRIP_TOP                               ;#4A7D: 10 F3
        ret                                                    ;#4A7F: C9

SCAN_PLAYFIELD_L_STRIP:
        ; Loop 10 cells along L axis (stride 5Ah), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_L_STRIP is the L-axis equivalent (L += 0Ah per cell, E += 5Ah
        ; per cell — wider stride). Both share QUERY_PLAYFIELD_AT.
        ld      b,0Ah                                          ;#4A80: 06 0A
SCAN_L_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_L_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A82: CD 90 4A
        inc     l                                              ;#4A85: 2C
        ld      a,e                                            ;#4A86: 7B
        add     a,5Ah                                          ;#4A87: C6 5A
        ld      e,a                                            ;#4A89: 5F
        jr      nc,SCAN_L_STRIP_NEXT                           ;#4A8A: 30 01
        inc     d                                              ;#4A8C: 14
SCAN_L_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_L_STRIP (L += 1, E += 5Ah)
        djnz    SCAN_L_STRIP_TOP                               ;#4A8D: 10 F3
        ret                                                    ;#4A8F: C9

QUERY_PLAYFIELD_AT:
        ; Lookup playfield cell at (H, L) via PLAYFIELD_LOOKUP_TABLE
        ; QUERY_PLAYFIELD_AT looks up (H, L) coord in PLAYFIELD_LOOKUP_TABLE
        ; (PLAYFIELD_LOOKUP_TABLE). H>=20h uses one branch (returns from a higher tier
        ; of the table at PLAYFIELD_LOOKUP_OUT_OF_BOUNDS); H<20h takes the in-bounds
        ; path indexing PLAYFIELD_ LOOKUP_TABLE. Returns the cell value in A — used to
        ; detect rocks, walls, flag positions for AI and movement.
        push    bc                                             ;#4A90: C5
        push    de                                             ;#4A91: D5
        push    hl                                             ;#4A92: E5
        ld      a,h                                            ;#4A93: 7C
        cp      20h                                            ;#4A94: FE 20
        jr      c,QUERY_IN_BOUNDS                              ;#4A96: 38 15
        inc     a                                              ;#4A98: 3C
        jr      nz,QUERY_OUT_OF_BOUNDS                         ;#4A99: 20 2A
        ld      a,l                                            ;#4A9B: 7D
        cp      39h                                            ;#4A9C: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4A9E: 30 25
        ld      hl,PLAYFIELD_LOOKUP_OUT_OF_BOUNDS              ;#4AA0: 21 20 FB
        add     a,l                                            ;#4AA3: 85
        ld      l,a                                            ;#4AA4: 6F
        ld      a,0                                            ;#4AA5: 3E 00
        adc     a,h                                            ;#4AA7: 8C
        ld      h,a                                            ;#4AA8: 67
        ld      a,(hl)                                         ;#4AA9: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4AAA: C3 C7 4A

QUERY_IN_BOUNDS:
        ; In-bounds path: compute PLAYFIELD_LOOKUP_TABLE row index
        ld      c,a                                            ;#4AAD: 4F
        ld      a,l                                            ;#4AAE: 7D
        cp      39h                                            ;#4AAF: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4AB1: 30 12
        ld      h,0                                            ;#4AB3: 26 00
        add     hl,hl                                          ;#4AB5: 29
        add     hl,hl                                          ;#4AB6: 29
        add     hl,hl                                          ;#4AB7: 29
        add     hl,hl                                          ;#4AB8: 29
        add     hl,hl                                          ;#4AB9: 29
        ld      a,c                                            ;#4ABA: 79
        add     a,l                                            ;#4ABB: 85
        ld      l,a                                            ;#4ABC: 6F
        ld      bc,PLAYFIELD_LOOKUP_TABLE                      ;#4ABD: 01 00 F4
        add     hl,bc                                          ;#4AC0: 09
        ld      a,(hl)                                         ;#4AC1: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4AC2: C3 C7 4A

QUERY_OUT_OF_BOUNDS:
        ; Out-of-bounds path: substitute cell value 87h (no playfield)
        ld      a,87h                                          ;#4AC5: 3E 87
QUERY_PLAYFIELD_EMIT:
        ; Copy a cell's 3x3 block (9 bytes) to 3 tile-buffer rows at DE +0/+1Eh/+3Ch
        ld      hl,PLAYFIELD_CELL_TILES                        ;#4AC7: 21 F1 4A
        add     a,l                                            ;#4ACA: 85
        ld      l,a                                            ;#4ACB: 6F
        ld      a,0                                            ;#4ACC: 3E 00
        adc     a,h                                            ;#4ACE: 8C
        ld      h,a                                            ;#4ACF: 67
        ld      bc,3                                           ;#4AD0: 01 03 00
        ldir                                                   ;#4AD3: ED B0
        ld      a,e                                            ;#4AD5: 7B
        add     a,1Bh                                          ;#4AD6: C6 1B
        ld      e,a                                            ;#4AD8: 5F
        ld      a,0                                            ;#4AD9: 3E 00
        adc     a,d                                            ;#4ADB: 8A
        ld      d,a                                            ;#4ADC: 57
        ld      c,3                                            ;#4ADD: 0E 03
        ldir                                                   ;#4ADF: ED B0
        ld      a,e                                            ;#4AE1: 7B
        add     a,1Bh                                          ;#4AE2: C6 1B
        ld      e,a                                            ;#4AE4: 5F
        ld      a,0                                            ;#4AE5: 3E 00
        adc     a,d                                            ;#4AE7: 8A
        ld      d,a                                            ;#4AE8: 57
        ld      c,3                                            ;#4AE9: 0E 03
        ldir                                                   ;#4AEB: ED B0
        pop     hl                                             ;#4AED: E1
        pop     de                                             ;#4AEE: D1
        pop     bc                                             ;#4AEF: C1
        ret                                                    ;#4AF0: C9

PLAYFIELD_CELL_TILES:
        ; Maze cell -> 3x3 tile block (16 cells, chars 80h+); paints the tile buffer
        PLAYFIELD_TILES "8C8C8C", "8C8C8C", "8C8C8C"           ;#4AF1: 8C 8C 8C 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C80", "8C8C81", "8C8C81"           ;#4AFA: 8C 8C 80 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8C8C82", "8C8C8C", "8C8C8C"           ;#4B03: 8C 8C 82 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C81", "8C8C81", "8C8C81"           ;#4B0C: 8C 8C 81 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858587", "8C8C8C", "8C8C8C"           ;#4B15: 85 85 87 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B1E: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858585", "8C8C8C", "8C8C8C"           ;#4B27: 85 85 85 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B30: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B39: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8D", "848484", "848484"           ;#4B42: 8D 8D 8D 84 84 84 84 84 84
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B4B: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8F", "848484", "848484"           ;#4B54: 8D 8D 8F 84 84 84 84 84 84
        PLAYFIELD_TILES "848489", "848489", "848489"           ;#4B5D: 84 84 89 84 84 89 84 84 89
        PLAYFIELD_TILES "84848A", "848484", "848484"           ;#4B66: 84 84 8A 84 84 84 84 84 84
        PLAYFIELD_TILES "848488", "848489", "848489"           ;#4B6F: 84 84 88 84 84 89 84 84 89
        PLAYFIELD_TILES "848484", "848484", "848484"           ;#4B78: 84 84 84 84 84 84 84 84 84

LOOKUP_PLAYFIELD_CELL:
        ; Given (H, L) map coord, index MAZE_BITMAP_N per STAGE_PALETTE_INDEX
        ; LOOKUP_PLAYFIELD_CELL takes (H, L) as a map coordinate and returns the
        ; playfield cell value in BC. Indexes MAZE_BITMAP_N at 7C00..7F00 at offset
        ; based on STAGE_PALETTE_INDEX (top bits) + coord. Returns cell type so callers
        ; can distinguish rock vs flag vs road.
        push    bc                                             ;#4B81: C5
        ld      bc,MAZE_BITMAP_0                               ;#4B82: 01 00 9C
        ld      a,l                                            ;#4B85: 7D
        cp      38h                                            ;#4B86: FE 38
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B88: 30 25
        add     a,a                                            ;#4B8A: 87
        add     a,a                                            ;#4B8B: 87
        ld      c,a                                            ;#4B8C: 4F
        ld      a,h                                            ;#4B8D: 7C
        cp      20h                                            ;#4B8E: FE 20
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B90: 30 1D
        rra                                                    ;#4B92: 1F
        rra                                                    ;#4B93: 1F
        rra                                                    ;#4B94: 1F
        and     3                                              ;#4B95: E6 03
        or      c                                              ;#4B97: B1
        ld      c,a                                            ;#4B98: 4F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4B99: 3A 30 E0
        rra                                                    ;#4B9C: 1F
        rra                                                    ;#4B9D: 1F
        and     3                                              ;#4B9E: E6 03
        or      b                                              ;#4BA0: B0
        ld      b,a                                            ;#4BA1: 47
        ld      a,(bc)                                         ;#4BA2: 0A
        push    af                                             ;#4BA3: F5
        ld      a,h                                            ;#4BA4: 7C
        and     7                                              ;#4BA5: E6 07
        inc     a                                              ;#4BA7: 3C
        ld      b,a                                            ;#4BA8: 47
        pop     af                                             ;#4BA9: F1
LOOKUP_SHIFT_LOOP:
        ; Inner djnz of LOOKUP_PLAYFIELD_CELL (bit-extract per row)
        add     a,a                                            ;#4BAA: 87
        djnz    LOOKUP_SHIFT_LOOP                              ;#4BAB: 10 FD
        pop     bc                                             ;#4BAD: C1
        ret                                                    ;#4BAE: C9

LOOKUP_OUT_OF_BOUNDS:
        ; Coord out of range: set carry and return (signal blocked cell)
        scf                                                    ;#4BAF: 37
        pop     bc                                             ;#4BB0: C1
        ret                                                    ;#4BB1: C9

PLAYFIELD_TILE_LOOKUP:
        ; Helper called by INIT_PLAYFIELD_LOOKUP to compute one cell's value
        ld      c,0                                            ;#4BB2: 0E 00
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BB4: CD 81 4B
        rl      c                                              ;#4BB7: CB 11
        dec     l                                              ;#4BB9: 2D
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BBA: CD 81 4B
        rl      c                                              ;#4BBD: CB 11
        inc     h                                              ;#4BBF: 24
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BC0: CD 81 4B
        rl      c                                              ;#4BC3: CB 11
        inc     l                                              ;#4BC5: 2C
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BC6: CD 81 4B
        rl      c                                              ;#4BC9: CB 11
        ret                                                    ;#4BCB: C9

INIT_PLAYFIELD_LOOKUP:
        ; Build PLAYFIELD_LOOKUP_TABLE over coords 0..38h x 0..1Fh
        ; INIT_PLAYFIELD_LOOKUP builds a precomputed lookup table at
        ; PLAYFIELD_LOOKUP_TABLE (~1800 bytes). Iterates a 32x57 grid (l=0..38h,
        ; h=0..1Fh), calling PLAYFIELD_TILE_LOOKUP per cell to compute one 9-byte sub-
        ; record. The table speeds up per-frame queries via QUERY_PLAYFIELD_AT (replaces
        ; an arithmetic recompute with an indexed read).
        ld      de,PLAYFIELD_LOOKUP_TABLE                      ;#4BCC: 11 00 F4
        ld      hl,0                                           ;#4BCF: 21 00 00
INIT_LOOKUP_LOOP:
        ; INIT_PLAYFIELD_LOOKUP main grid loop: H over 0..1Fh, L stays
        push    hl                                             ;#4BD2: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BD3: CD B2 4B
        pop     hl                                             ;#4BD6: E1
        ld      a,c                                            ;#4BD7: 79
        add     a,a                                            ;#4BD8: 87
        add     a,a                                            ;#4BD9: 87
        add     a,a                                            ;#4BDA: 87
        add     a,c                                            ;#4BDB: 81
        ld      (de),a                                         ;#4BDC: 12
        inc     de                                             ;#4BDD: 13
        inc     h                                              ;#4BDE: 24
        ld      a,h                                            ;#4BDF: 7C
        cp      20h                                            ;#4BE0: FE 20
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BE2: 20 EE
        ld      h,0                                            ;#4BE4: 26 00
        inc     l                                              ;#4BE6: 2C
        ld      a,l                                            ;#4BE7: 7D
        cp      39h                                            ;#4BE8: FE 39
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BEA: 20 E6
        ld      hl,0FF00h                                      ;#4BEC: 21 00 FF
INIT_LOOKUP_TAIL_LOOP:
        ; INIT_PLAYFIELD_LOOKUP tail loop with H=FF (wrap-around row at top)
        push    hl                                             ;#4BEF: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BF0: CD B2 4B
        pop     hl                                             ;#4BF3: E1
        ld      a,c                                            ;#4BF4: 79
        add     a,a                                            ;#4BF5: 87
        add     a,a                                            ;#4BF6: 87
        add     a,a                                            ;#4BF7: 87
        add     a,c                                            ;#4BF8: 81
        ld      (de),a                                         ;#4BF9: 12
        inc     de                                             ;#4BFA: 13
        inc     l                                              ;#4BFB: 2C
        ld      a,l                                            ;#4BFC: 7D
        cp      39h                                            ;#4BFD: FE 39
        jr      nz,INIT_LOOKUP_TAIL_LOOP                       ;#4BFF: 20 EE
        ret                                                    ;#4C01: C9

INIT_STAGE_TRACK_DATA:
        ; Initialize TRACK_DATA_RING region (10 x 0x5A blocks) with stage path/track state
        ; INIT_STAGE_TRACK_DATA initializes TRACK_DATA_RING. Sets up two 16-bit pointers
        ; (E088 = E08A = F400h, E08F = 320Fh, E092 = 0). Then loops 10 times, calling
        ; SCAN_PLAYFIELD_H_STRIP with HL=0B2Eh and DE walking by 0x5A per iter —
        ; populates the 10 enemy-car path/track records.
        ld      hl,PLAYFIELD_LOOKUP_TABLE                      ;#4C02: 21 00 F4
        ld      (WORLD_X_POS),hl                               ;#4C05: 22 08 E0
        ld      (WORLD_Y_POS),hl                               ;#4C08: 22 0A E0
        ld      hl,320Fh                                       ;#4C0B: 21 0F 32
        ld      (PLAYER_WORLD_POSITION_X),hl                   ;#4C0E: 22 0F E0
        ld      hl,0                                           ;#4C11: 21 00 00
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4C14: 22 12 E0
        call    INIT_PLAYFIELD_LOOKUP                          ;#4C17: CD CC 4B
        ld      b,0Ah                                          ;#4C1A: 06 0A
        ld      de,TRACK_DATA_RING                             ;#4C1C: 11 00 EC
        ld      hl,0B2Eh                                       ;#4C1F: 21 2E 0B
INIT_TRACK_DATA_LOOP:
        ; Inner djnz of INIT_STAGE_TRACK_DATA (10 enemy paths)
        push    hl                                             ;#4C22: E5
        push    de                                             ;#4C23: D5
        push    bc                                             ;#4C24: C5
        call    SCAN_PLAYFIELD_H_STRIP                         ;#4C25: CD 70 4A
        pop     bc                                             ;#4C28: C1
        pop     de                                             ;#4C29: D1
        ld      hl,5Ah                                         ;#4C2A: 21 5A 00
        add     hl,de                                          ;#4C2D: 19
        ex      de,hl                                          ;#4C2E: EB
        pop     hl                                             ;#4C2F: E1
        inc     l                                              ;#4C30: 2C
        djnz    INIT_TRACK_DATA_LOOP                           ;#4C31: 10 EF
        ret                                                    ;#4C33: C9

INIT_ENEMY_CARS:
        ; Clear 0x6F bytes at E300 and reset its iterator timer (E09D = 70h)
        ; INIT_ENEMY_CARS clears 6Fh bytes of ENEMY_CAR_TABLE to 0 and resets
        ; ENEMY_CAR_ITER_TIMER to 70h. Then loads stage-specific seed data from
        ; INITIAL_ENEMY_CARS_DATA using STAGE_ENEMY_SEED_LEN bytes worth.
        ld      a,70h                                          ;#4C34: 3E 70
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#4C36: 32 1D E0
        ld      hl,ENEMY_CAR_TABLE                             ;#4C39: 21 00 E3
        ld      de,ENEMY_CAR_TABLE_TAIL                        ;#4C3C: 11 01 E3
        ld      bc,6Fh                                         ;#4C3F: 01 6F 00
        ld      (hl),0                                         ;#4C42: 36 00
        ldir                                                   ;#4C44: ED B0
        ld      hl,INITIAL_ENEMY_CARS_DATA                     ;#4C46: 21 55 4C
        ld      de,ENEMY_CAR_TABLE                             ;#4C49: 11 00 E3
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#4C4C: 3A 40 E0
        ld      c,a                                            ;#4C4F: 4F
        ld      b,0                                            ;#4C50: 06 00
        ldir                                                   ;#4C52: ED B0
        ret                                                    ;#4C54: C9

INITIAL_ENEMY_CARS_DATA:
        ; Stage-specific initial state for ENEMY_CAR_TABLE (E0C0 bytes copied)
        ; INITIAL_ENEMY_CARS_DATA holds the stage-specific seed for ENEMY_CAR_TABLE.
        ; STAGE_ENEMY_SEED_LEN bytes (=enemies*16) get copied in by INIT_ENEMY_CARS.
        ; Each 16-byte enemy record encodes type, initial position, direction, and AI
        ; state, rendered as the four ENEMY_SEED_1/_2/_3/_4 macro calls. Enemy car 1
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C55: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4C58: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=58h, screen_y=9Fh    ;#4C5D: 34 58 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C62: 00 06 00
        ; Enemy car 2
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C65: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4C68: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=88h, screen_y=9Fh    ;#4C6D: 34 88 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C72: 00 06 00
        ; Enemy car 3
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C75: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Dh, y_accum=0C00h  ;#4C78: 00 0C 0D 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=28h, screen_y=9Fh    ;#4C7D: 34 28 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C82: 00 06 00
        ; Enemy car 4
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C85: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=13h, y_accum=0C00h  ;#4C88: 00 0C 13 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0B8h, screen_y=9Fh   ;#4C8D: 34 B8 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C92: 00 06 00
        ; Enemy car 5
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C95: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Bh, y_accum=0C00h  ;#4C98: 00 0C 0B 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0FFF8h, screen_y=9Fh ;#4C9D: 34 F8 FF 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4CA2: 00 06 00
        ; Enemy car 6
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CA5: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4CA8: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=58h, screen_y=0FBEFh   ;#4CAD: 02 58 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CB2: 24 06 02
        ; Enemy car 7
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CB5: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4CB8: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=88h, screen_y=0FBEFh   ;#4CBD: 02 88 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CC2: 24 06 02
POLL_INPUT:
        ; Read PSG R14 joystick + SNSMAT row 8 keys; return combined input bits in C
        ; POLL_INPUT reads both joystick (via PSG R14 after configuring R15 as output
        ; via SET_PSG_REG) AND keyboard (SNSMAT row 8) and OR-combines them into C. Each
        ; direction/button has a unique bit in C. The combined state then feeds
        ; PROCESS_DIRECTION_INPUT and DEPLOY_SMOKE_IF_INPUT.
        ld      a,0Fh                                          ;#4CC5: 3E 0F
        ld      e,8Fh                                          ;#4CC7: 1E 8F
        call    BIOS_WRTPSG                                    ;#4CC9: CD 93 00
        ld      a,0Eh                                          ;#4CCC: 3E 0E
        call    BIOS_RDPSG                                     ;#4CCE: CD 96 00
        or      0C0h                                           ;#4CD1: F6 C0
        ld      c,a                                            ;#4CD3: 4F
        ld      a,8                                            ;#4CD4: 3E 08
        call    SNSMAT_PRESERVE_BC                             ;#4CD6: CD 03 4D
        rla                                                    ;#4CD9: 17
        jr      c,POLL_KEY_LEFT_DONE                           ;#4CDA: 38 02
        res     3,c                                            ;#4CDC: CB 99
POLL_KEY_LEFT_DONE:
        ; After clearing LEFT bit, fall through to DOWN probe
        rla                                                    ;#4CDE: 17
        jr      c,POLL_KEY_DOWN_DONE                           ;#4CDF: 38 02
        res     1,c                                            ;#4CE1: CB 89
POLL_KEY_DOWN_DONE:
        ; After clearing DOWN bit, fall through to UP probe
        rla                                                    ;#4CE3: 17
        jr      c,POLL_KEY_UP_DONE                             ;#4CE4: 38 02
        res     0,c                                            ;#4CE6: CB 81
POLL_KEY_UP_DONE:
        ; After clearing UP bit, fall through to RIGHT probe
        rla                                                    ;#4CE8: 17
        jr      c,POLL_KEY_RIGHT_DONE                          ;#4CE9: 38 02
        res     2,c                                            ;#4CEB: CB 91
POLL_KEY_RIGHT_DONE:
        ; After clearing RIGHT bit, fall through to TRIGGER probe
        and     10h                                            ;#4CED: E6 10
        jr      nz,POLL_KEY_TRIGGER_DONE                       ;#4CEF: 20 02
        res     7,c                                            ;#4CF1: CB B9
POLL_KEY_TRIGGER_DONE:
        ; Read SNSMAT row 5: check joystick trigger 1 bit
        ld      a,5                                            ;#4CF3: 3E 05
        call    SNSMAT_PRESERVE_BC                             ;#4CF5: CD 03 4D
        rla                                                    ;#4CF8: 17
        jr      c,POLL_KEY_GTRIG_DONE                          ;#4CF9: 38 02
        res     5,c                                            ;#4CFB: CB A9
POLL_KEY_GTRIG_DONE:
        ; Read SNSMAT row 5: check joystick trigger 2 bit (general trigger)
        rla                                                    ;#4CFD: 17
        rla                                                    ;#4CFE: 17
        ret     c                                              ;#4CFF: D8
        res     4,c                                            ;#4D00: CB A1
        ret                                                    ;#4D02: C9

SNSMAT_PRESERVE_BC:
        ; Tiny stub: call BIOS_SNSMAT preserving BC across the call
        push    bc                                             ;#4D03: C5
        call    BIOS_SNSMAT                                    ;#4D04: CD 41 01
        pop     bc                                             ;#4D07: C1
        ret                                                    ;#4D08: C9

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
        ld      hl,INITIAL_VDP_REGISTERS                       ;#4D09: 21 A2 4D
        ld      bc,800h                                        ;#4D0C: 01 00 08
VDP_REG_INIT_LOOP:
        ; Inner djnz of INIT_VDP_AND_LOAD_GFX (8 registers)
        push    bc                                             ;#4D0F: C5
        ld      b,(hl)                                         ;#4D10: 46
        call    BIOS_WRTVDP                                    ;#4D11: CD 47 00
        pop     bc                                             ;#4D14: C1
        inc     hl                                             ;#4D15: 23
        inc     c                                              ;#4D16: 0C
        djnz    VDP_REG_INIT_LOOP                              ;#4D17: 10 F6
        ld      hl,INITIAL_COLOR_TABLE                         ;#4D19: 21 AA 4D
        LOAD_VRAM_ADDRESS de, 780h                             ;#4D1C: 11 80 07
        ld      bc,20h                                         ;#4D1F: 01 20 00
        call    BIOS_LDIRVM                                    ;#4D22: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D25: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#4D28: 11 01 E0
        ld      (hl),0                                         ;#4D2B: 36 00
        ld      bc,7FFh                                        ;#4D2D: 01 FF 07
        ldir                                                   ;#4D30: ED B0
        ld      hl,TILE_PATTERN_HEX_DIGITS                     ;#4D32: 21 E0 83
        ld      de,TEMP_SPACE                                  ;#4D35: 11 00 E0
        ld      bc,100h                                        ;#4D38: 01 00 01
        ldir                                                   ;#4D3B: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D3D: 21 A0 84
        ld      b,1                                            ;#4D40: 06 01
        ldir                                                   ;#4D42: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D44: 21 A0 84
        ld      b,1                                            ;#4D47: 06 01
        ldir                                                   ;#4D49: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D4B: 21 A0 84
        ld      b,1                                            ;#4D4E: 06 01
        ldir                                                   ;#4D50: ED B0
        ld      hl,TEMP_SPACE                                  ;#4D52: 21 00 E0
        LOAD_VRAM_ADDRESS de, 800h                             ;#4D55: 11 00 08
        ld      bc,800h                                        ;#4D58: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D5B: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D5E: 21 00 E0
        LOAD_VRAM_ADDRESS de, 1800h                            ;#4D61: 11 00 18
        ld      bc,800h                                        ;#4D64: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D67: CD 5C 00
        ld      hl,SPRITE_CAR                                  ;#4D6A: 21 00 80
        ld      de,TEMP_SPACE                                  ;#4D6D: 11 00 E0
        ld      bc,60h                                         ;#4D70: 01 60 00
        ldir                                                   ;#4D73: ED B0
        ld      hl,SPRITE_PATTERN_WORK_BUF                     ;#4D75: 21 60 E0
        ld      de,TEMP_SPACE                                  ;#4D78: 11 00 E0
        call    TRANSPOSE_TILE_BLOCKS                          ;#4D7B: CD CA 4D
        ld      hl,TEMP_SPACE                                  ;#4D7E: 21 00 E0
        LOAD_VRAM_ADDRESS de, 3000h                            ;#4D81: 11 00 30
        ld      bc,180h                                        ;#4D84: 01 80 01
        call    BIOS_LDIRVM                                    ;#4D87: CD 5C 00
        ld      hl,SPRITE_FLAG                                 ;#4D8A: 21 60 80
        LOAD_VRAM_ADDRESS de, 3180h                            ;#4D8D: 11 80 31
        ld      bc,100h                                        ;#4D90: 01 00 01
        call    BIOS_LDIRVM                                    ;#4D93: CD 5C 00
        ld      hl,SPRITE_BONUS_100                            ;#4D96: 21 20 81
        LOAD_VRAM_ADDRESS de, 3400h                            ;#4D99: 11 00 34
        ld      bc,2C0h                                        ;#4D9C: 01 C0 02
        jp      BIOS_LDIRVM                                    ;#4D9F: C3 5C 00

INITIAL_VDP_REGISTERS:
        ; Screen-1 R0..R7 init block: name=0400h, SAT=0700h, patterns=0800h
        ; INITIAL_VDP_REGISTERS — 8 bytes loaded into VDP R0..R7 by boot. R0=00 (M3=0,
        ; no horiz IRQ), R1=82h (screen blank, IRQs off, 16x16 sprites — screen 1 mode),
        ; R2=01 (name table 0400h), R3=1E (color 0780h), R4=01 (patterns 0800h), R5=0E
        ; (SAT 0700h), R6=06 (sprite patterns 3000h), R7=F0 (FG=white BG=transparent).
        db      0, 0C2h, 1, 1Eh, 1, 0Eh, 6, 0F0h ; VDP registers R0..R7  ;#4DA2: 00 C2 01 1E 01 0E 06 F0

INITIAL_COLOR_TABLE:
        ; 32-byte screen-1 colour table uploaded to VRAM 0780h (not SAT)
        dh      "F0F080F070707070F0F0F0F080808080"             ;#4DAA: F0 F0 80 F0 70 70 70 70 F0 F0 F0 F0 80 80 80 80
        dh      "2992F0F0A0A0F0F010106060F0F0F0F0"             ;#4DBA: 29 92 F0 F0 A0 A0 F0 F0 10 10 60 60 F0 F0 F0 F0

TRANSPOSE_TILE_BLOCKS:
        ; Process 9 32-byte blocks via 4 sub-quadrant TRANSPOSE_TILE_BITS calls each
        ; TRANSPOSE_TILE_BLOCKS processes 9 tile-pattern blocks of 32 bytes each by
        ; calling TRANSPOSE_TILE_BITS 4 times per iteration (one per 8-byte quadrant).
        ; The 4 quadrant offsets within a 32-byte tile are +16, +0, +24, +8 (i.e.
        ; quadrant order is bottom-left, top-left, bottom-right, top-right). This
        ; rearranges packed source data into VRAM-pattern-table format before LDIRVM.
        ld      b,9                                            ;#4DCA: 06 09
TRANSPOSE_BLOCKS_LOOP:
        ; Outer djnz of TRANSPOSE_TILE_BLOCKS (9 tile blocks)
        push    bc                                             ;#4DCC: C5
        push    hl                                             ;#4DCD: E5
        ld      bc,10h                                         ;#4DCE: 01 10 00
        add     hl,bc                                          ;#4DD1: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DD2: CD F5 4D
        pop     hl                                             ;#4DD5: E1
        push    hl                                             ;#4DD6: E5
        call    TRANSPOSE_TILE_BITS                            ;#4DD7: CD F5 4D
        pop     hl                                             ;#4DDA: E1
        push    hl                                             ;#4DDB: E5
        ld      bc,18h                                         ;#4DDC: 01 18 00
        add     hl,bc                                          ;#4DDF: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DE0: CD F5 4D
        pop     hl                                             ;#4DE3: E1
        push    hl                                             ;#4DE4: E5
        ld      bc,8                                           ;#4DE5: 01 08 00
        add     hl,bc                                          ;#4DE8: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DE9: CD F5 4D
        pop     hl                                             ;#4DEC: E1
        ld      bc,20h                                         ;#4DED: 01 20 00
        add     hl,bc                                          ;#4DF0: 09
        pop     bc                                             ;#4DF1: C1
        djnz    TRANSPOSE_BLOCKS_LOOP                          ;#4DF2: 10 D8
        ret                                                    ;#4DF4: C9

TRANSPOSE_TILE_BITS:
        ; 8x8 bit-matrix transpose: 8 input bytes -> 8 output bytes (bit-column-first)
        ; TRANSPOSE_TILE_BITS is the classic 8×8 bit-matrix transpose: 8 input bytes
        ; interpreted as an 8×8 bit grid become 8 output bytes with rows and columns
        ; swapped. Implemented as 2 nested loops: inner 8x `add a,a; rr (hl); inc hl`
        ; (shifts bits column-wise), outer 8x to consume each input byte.
        ld      c,8                                            ;#4DF5: 0E 08
TRANSPOSE_OUTER_LOOP:
        ; Outer 8-byte loop of TRANSPOSE_TILE_BITS (one column per iter)
        ld      a,(de)                                         ;#4DF7: 1A
        inc     de                                             ;#4DF8: 13
        push    hl                                             ;#4DF9: E5
        ld      b,8                                            ;#4DFA: 06 08
TRANSPOSE_INNER_BIT:
        ; Inner djnz of TRANSPOSE_TILE_BITS (bit-by-bit shift)
        add     a,a                                            ;#4DFC: 87
        rr      (hl)                                           ;#4DFD: CB 1E
        inc     hl                                             ;#4DFF: 23
        djnz    TRANSPOSE_INNER_BIT                            ;#4E00: 10 FA
        pop     hl                                             ;#4E02: E1
        dec     c                                              ;#4E03: 0D
        jr      nz,TRANSPOSE_OUTER_LOOP                        ;#4E04: 20 F1
        ret                                                    ;#4E06: C9

UPLOAD_PATTERN_SLICE:
        ; Pick a slice via TILE_PATTERN_SLICE_TABLE then LDIRVM to VRAM 0C00h
        ; UPLOAD_PATTERN_SLICE selects a 128-byte tile-pattern slice from
        ; TILE_PATTERN_SLICE_TABLE based on PLAYER_VELOCITY_X, then LDIRVMs it to VRAM
        ; 0C00h (pattern table). Used to switch dynamic patterns per game state.
        ld      a,(PLAYER_VELOCITY_X)                          ;#4E07: 3A 09 E0
        add     a,18h                                          ;#4E0A: C6 18
        and     7                                              ;#4E0C: E6 07
        add     a,a                                            ;#4E0E: 87
        ld      hl,TILE_PATTERN_SLICE_TABLE                    ;#4E0F: 21 CD 4E
        add     a,l                                            ;#4E12: 85
        ld      l,a                                            ;#4E13: 6F
        ld      a,0                                            ;#4E14: 3E 00
        adc     a,h                                            ;#4E16: 8C
        ld      h,a                                            ;#4E17: 67
        ld      a,(hl)                                         ;#4E18: 7E
        inc     hl                                             ;#4E19: 23
        ld      h,(hl)                                         ;#4E1A: 66
        ld      l,a                                            ;#4E1B: 6F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4E1C: 3A 0B E0
        add     a,18h                                          ;#4E1F: C6 18
        neg                                                    ;#4E21: ED 44
        and     7                                              ;#4E23: E6 07
        inc     a                                              ;#4E25: 3C
        ld      b,a                                            ;#4E26: 47
UPLOAD_PATTERN_SLICE_DEC_HL:
        ; Inner djnz of UPLOAD_PATTERN_SLICE (rewind HL)
        dec     hl                                             ;#4E27: 2B
        djnz    UPLOAD_PATTERN_SLICE_DEC_HL                    ;#4E28: 10 FD
        ld      a,(FRAME_TICK)                                 ;#4E2A: 3A 07 E0
        rra                                                    ;#4E2D: 1F
        jr      nc,UPLOAD_PATTERN_SLICE_BANK_B                 ;#4E2E: 30 0C
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#4E30: 11 00 0C
        ld      bc,80h                                         ;#4E33: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E36: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E39: C3 48 4E

UPLOAD_PATTERN_SLICE_BANK_B:
        ; Bank-B path: LDIRVM the slice to VRAM 1C00h instead of 0C00h
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#4E3C: 11 00 1C
        ld      bc,80h                                         ;#4E3F: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E42: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E45: C3 48 4E

UPLOAD_PATTERN_SLICE_AFTER_LDIRVM:
        ; After both bank LDIRVM paths: prepare to update VRAM cursor for next slice
        ld      de,PLAYER_VELOCITY_Y                           ;#4E48: 11 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#4E4B: 21 0C E0
        ld      a,(de)                                         ;#4E4E: 1A
        add     a,1Fh                                          ;#4E4F: C6 1F
        rra                                                    ;#4E51: 1F
        rra                                                    ;#4E52: 1F
        rra                                                    ;#4E53: 1F
        and     7                                              ;#4E54: E6 07
        cp      (hl)                                           ;#4E56: BE
        jr      nz,UPLOAD_PATTERN_SLICE_FIRST_ROW              ;#4E57: 20 21
        ld      b,a                                            ;#4E59: 47
        dec     de                                             ;#4E5A: 1B
        dec     de                                             ;#4E5B: 1B
        inc     hl                                             ;#4E5C: 23
        ld      a,(de)                                         ;#4E5D: 1A
        add     a,18h                                          ;#4E5E: C6 18
        rra                                                    ;#4E60: 1F
        rra                                                    ;#4E61: 1F
        rra                                                    ;#4E62: 1F
        and     7                                              ;#4E63: E6 07
        cp      (hl)                                           ;#4E65: BE
        jp      z,UPDATE_RADAR                                 ;#4E66: CA E5 52
        ld      (hl),a                                         ;#4E69: 77
        ld      hl,TRACK_DATA_RING                             ;#4E6A: 21 00 EC
        add     a,l                                            ;#4E6D: 85
        ld      l,a                                            ;#4E6E: 6F
        ld      a,0                                            ;#4E6F: 3E 00
        adc     a,h                                            ;#4E71: 8C
        ld      h,a                                            ;#4E72: 67
        ld      de,1Eh                                         ;#4E73: 11 1E 00
        inc     b                                              ;#4E76: 04
        jp      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E77: C3 95 4E

UPLOAD_PATTERN_SLICE_FIRST_ROW:
        ; First-row branch: update the playfield-position byte, then advance the loop
        ld      (hl),a                                         ;#4E7A: 77
        ld      b,a                                            ;#4E7B: 47
        dec     de                                             ;#4E7C: 1B
        dec     de                                             ;#4E7D: 1B
        inc     hl                                             ;#4E7E: 23
        ld      a,(de)                                         ;#4E7F: 1A
        add     a,18h                                          ;#4E80: C6 18
        rra                                                    ;#4E82: 1F
        rra                                                    ;#4E83: 1F
        rra                                                    ;#4E84: 1F
        and     7                                              ;#4E85: E6 07
        ld      (hl),a                                         ;#4E87: 77
        ld      hl,TRACK_DATA_RING                             ;#4E88: 21 00 EC
        add     a,l                                            ;#4E8B: 85
        ld      l,a                                            ;#4E8C: 6F
        ld      a,0                                            ;#4E8D: 3E 00
        adc     a,h                                            ;#4E8F: 8C
        ld      h,a                                            ;#4E90: 67
        ld      de,1Eh                                         ;#4E91: 11 1E 00
        inc     b                                              ;#4E94: 04
UPLOAD_PATTERN_SLICE_ADVANCE_LOOP:
        ; Inner djnz: HL += 1Eh per iteration (skip 30 chars between visible rows)
        dec     b                                              ;#4E95: 05
        jr      z,UPLOAD_PATTERN_SLICE_BANK_SWAP               ;#4E96: 28 03
        add     hl,de                                          ;#4E98: 19
        jr      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E99: 18 FA

UPLOAD_PATTERN_SLICE_BANK_SWAP:
        ; Frame-parity gate: choose bank-A (NAME_BANK_FLAG=0) or bank-B path
        ld      b,18h                                          ;#4E9B: 06 18
        ld      de,400h                                        ;#4E9D: 11 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#4EA0: 3A 0E E0
        and     a                                              ;#4EA3: A7
        jp      nz,UPLOAD_PATTERN_SLICE_BANK_CLEAR             ;#4EA4: C2 B2 4E
        ld      a,1                                            ;#4EA7: 3E 01
        ld      (NAME_BANK_FLAG),a                             ;#4EA9: 32 0E E0
        LOAD_VRAM_ADDRESS de, 1400h                            ;#4EAC: 11 00 14
        jp      UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4EAF: C3 B6 4E

UPLOAD_PATTERN_SLICE_BANK_CLEAR:
        ; Bank-A path: clear NAME_BANK_FLAG so the next frame uses bank-B
        xor     a                                              ;#4EB2: AF
        ld      (NAME_BANK_FLAG),a                             ;#4EB3: 32 0E E0
UPLOAD_PATTERN_SLICE_LDIRVM_SLICE:
        ; LDIRVM the 23-tile row to the name table at chosen bank
        push    bc                                             ;#4EB6: C5
        push    hl                                             ;#4EB7: E5
        push    de                                             ;#4EB8: D5
        ld      bc,17h                                         ;#4EB9: 01 17 00
        call    BIOS_LDIRVM                                    ;#4EBC: CD 5C 00
        pop     hl                                             ;#4EBF: E1
        ld      bc,20h                                         ;#4EC0: 01 20 00
        add     hl,bc                                          ;#4EC3: 09
        ex      de,hl                                          ;#4EC4: EB
        pop     hl                                             ;#4EC5: E1
        ld      c,1Eh                                          ;#4EC6: 0E 1E
        add     hl,bc                                          ;#4EC8: 09
        pop     bc                                             ;#4EC9: C1
        djnz    UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4ECA: 10 EA
        ret                                                    ;#4ECC: C9

TILE_PATTERN_SLICE_TABLE:
        ; 8 endpoint pointers into the per-substate tile-pattern data block
        dw TILE_SLICE_0 + 9                                    ;#4ECD: E6 4E
        dw TILE_SLICE_1 + 9                                    ;#4ECF: 66 4F
        dw TILE_SLICE_2 + 9                                    ;#4ED1: E6 4F
        dw TILE_SLICE_3 + 9                                    ;#4ED3: 66 50
        dw TILE_SLICE_4 + 9                                    ;#4ED5: E6 50
        dw TILE_SLICE_5 + 9                                    ;#4ED7: 66 51
        dw TILE_SLICE_6 + 9                                    ;#4ED9: E6 51
        dw TILE_SLICE_7 + 9                                    ;#4EDB: 66 52

TILE_SLICE_0:
        ; 128-byte tile-pattern slice 0 (table points to TILE_SLICE_0 + 9)
        dh      "00000000000000000000000000000000"             ;#4EDD: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4EED: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4EFD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F0D: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF
        dh      "00000000000000000000000000000000"             ;#4F1D: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4F2D: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F3D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F4D: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF

TILE_SLICE_1:
        ; 128-byte tile-pattern slice 1
        dh      "00000000000000000101010101010101"             ;#4F5D: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4F6D: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F7D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4F8D: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE
        dh      "00000000000000000101010101010101"             ;#4F9D: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4FAD: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4FBD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4FCD: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE

TILE_SLICE_2:
        ; 128-byte tile-pattern slice 2
        dh      "00000000000000000303030303030303"             ;#4FDD: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#4FED: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4FFD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#500D: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC
        dh      "00000000000000000303030303030303"             ;#501D: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#502D: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#503D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#504D: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC

TILE_SLICE_3:
        ; 128-byte tile-pattern slice 3
        dh      "00000000000000000707070707070707"             ;#505D: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#506D: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#507D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#508D: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8
        dh      "00000000000000000707070707070707"             ;#509D: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#50AD: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#50BD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#50CD: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8

TILE_SLICE_4:
        ; 128-byte tile-pattern slice 4
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#50DD: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#50ED: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#50FD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#510D: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#511D: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#512D: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#513D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#514D: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0

TILE_SLICE_5:
        ; 128-byte tile-pattern slice 5
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#515D: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#516D: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#517D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#518D: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#519D: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#51AD: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#51BD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#51CD: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0

TILE_SLICE_6:
        ; 128-byte tile-pattern slice 6
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#51DD: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#51ED: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#51FD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#520D: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#521D: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#522D: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#523D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#524D: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0

TILE_SLICE_7:
        ; 136-byte tile-pattern slice 7 (extended tail)
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#525D: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#526D: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#527D: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#528D: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#529D: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#52AD: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#52BD: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#52CD: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "0000000000000000"                             ;#52DD: 00 00 00 00 00 00 00 00

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
        ld      hl,RADAR_GRID                                  ;#52E5: 21 00 EA
        ld      de,OBSTACLE_GRID                               ;#52E8: 11 80 EA
        ld      bc,70h                                         ;#52EB: 01 70 00
        ldir                                                   ;#52EE: ED B0
        ld      a,(FRAME_TICK)                                 ;#52F0: 3A 07 E0
        and     8                                              ;#52F3: E6 08
        jr      z,RADAR_AFTER_CLEAR                            ;#52F5: 28 05
        ld      hl,(RADAR_LAST_DOT_PTR)                        ;#52F7: 2A 25 E0
        ld      (hl),90h                                       ;#52FA: 36 90
RADAR_AFTER_CLEAR:
        ; After optional player-dot clear: set up IX = ENEMY_CAR_TABLE for plot
        ld      ix,ENEMY_CAR_TABLE                             ;#52FC: DD 21 00 E3
        call    UPDATE_RADAR_DOT_A                             ;#5300: CD 55 53
        call    UPDATE_RADAR_DOT_B                             ;#5303: CD 91 53
        call    UPDATE_RADAR_DOT_B                             ;#5306: CD 91 53
        call    UPDATE_RADAR_DOT_A                             ;#5309: CD 55 53
        call    UPDATE_RADAR_DOT_A                             ;#530C: CD 55 53
        call    UPDATE_RADAR_DOT_B                             ;#530F: CD 91 53
        call    UPDATE_RADAR_DOT_A                             ;#5312: CD 55 53
        ld      a,(PLAYER_SCREEN_X)                            ;#5315: 3A 23 E0
        ld      d,a                                            ;#5318: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#5319: 3A 24 E0
        ld      e,a                                            ;#531C: 5F
        ld      c,0B0h                                         ;#531D: 0E B0
        ld      a,(FRAME_TICK)                                 ;#531F: 3A 07 E0
        and     10h                                            ;#5322: E6 10
        jr      z,RADAR_PROBE_PLAYER                           ;#5324: 28 02
        ld      c,0C0h                                         ;#5326: 0E C0
RADAR_PROBE_PLAYER:
        ; Plot the player dot at PLAYER_SCREEN_X/Y with blinking color B0h/C0h
        call    PROBE_OBSTACLE_CELL                            ;#5328: CD 67 53
        ld      hl,OBSTACLE_GRID                               ;#532B: 21 80 EA
        ld      b,0Eh                                          ;#532E: 06 0E
        ld      de,4F7h                                        ;#5330: 11 F7 04
        ld      a,(NAME_BANK_FLAG)                             ;#5333: 3A 0E E0
        and     a                                              ;#5336: A7
        jr      z,RADAR_UPLOAD_ROW_LOOP                        ;#5337: 28 03
        LOAD_VRAM_ADDRESS de, 14F7h                            ;#5339: 11 F7 14
RADAR_UPLOAD_ROW_LOOP:
        ; Inner djnz: LDIRVM 8 radar bytes per row, then HL+=8, DE+=20h
        push    bc                                             ;#533C: C5
        push    de                                             ;#533D: D5
        push    hl                                             ;#533E: E5
        ld      bc,8                                           ;#533F: 01 08 00
        ; BIOS_LDIRVM call inside the radar-clear loop. Used by UPDATE_RADAR to bulk-
        ; clear the radar grid before redrawing entity dots. Just a standard LDIRVM call
        ; site (no enclosing macro because the source is computed register, not
        ; literal).
        call    BIOS_LDIRVM                                    ;#5342: CD 5C 00
        pop     hl                                             ;#5345: E1
        ld      bc,8                                           ;#5346: 01 08 00
        add     hl,bc                                          ;#5349: 09
        pop     de                                             ;#534A: D1
        ex      de,hl                                          ;#534B: EB
        ld      bc,20h                                         ;#534C: 01 20 00
        add     hl,bc                                          ;#534F: 09
        ex      de,hl                                          ;#5350: EB
        pop     bc                                             ;#5351: C1
        djnz    RADAR_UPLOAD_ROW_LOOP                          ;#5352: 10 E8
        ret                                                    ;#5354: C9

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
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5355: DD 7E 00
        and     a                                              ;#5358: A7
        ret     z                                              ;#5359: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#535A: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#535D: DD 5E 08
        ld      bc,10h                                         ;#5360: 01 10 00
        add     ix,bc                                          ;#5363: DD 09
        ld      c,0D0h                                         ;#5365: 0E D0
PROBE_OBSTACLE_CELL:
        ; Compute OBSTACLE_GRID index from (D, E) coord and read cell; compare to 90h
        ; PROBE_OBSTACLE_CELL takes (D, E) as a map coordinate, computes a bit index
        ; into OBSTACLE_GRID (128 bytes covering 32x32 cells), reads the cell value, and
        ; compares to 90h (empty marker). Returns z-flag set if cell is empty, clear if
        ; occupied. Used by AI for collision/path checks.
        ld      a,d                                            ;#5367: 7A
        and     3                                              ;#5368: E6 03
        or      c                                              ;#536A: B1
        ld      c,a                                            ;#536B: 4F
        ld      a,e                                            ;#536C: 7B
        add     a,a                                            ;#536D: 87
        add     a,a                                            ;#536E: 87
        and     0Ch                                            ;#536F: E6 0C
        or      c                                              ;#5371: B1
        ld      c,a                                            ;#5372: 4F
        ld      a,d                                            ;#5373: 7A
        rra                                                    ;#5374: 1F
        rra                                                    ;#5375: 1F
        and     7                                              ;#5376: E6 07
        ld      l,a                                            ;#5378: 6F
        ld      a,e                                            ;#5379: 7B
        add     a,a                                            ;#537A: 87
        and     78h                                            ;#537B: E6 78
        or      l                                              ;#537D: B5
        ld      l,a                                            ;#537E: 6F
        ld      h,0                                            ;#537F: 26 00
        ld      de,OBSTACLE_GRID                               ;#5381: 11 80 EA
        add     hl,de                                          ;#5384: 19
        ld      a,(hl)                                         ;#5385: 7E
        cp      90h                                            ;#5386: FE 90
        jr      z,RADAR_A_WRITE_CELL                           ;#5388: 28 05
        ld      a,(FRAME_TICK)                                 ;#538A: 3A 07 E0
        rra                                                    ;#538D: 1F
        ret     c                                              ;#538E: D8
RADAR_A_WRITE_CELL:
        ; Variant A write: store color C into the radar cell (occupied or empty)
        ld      (hl),c                                         ;#538F: 71
        ret                                                    ;#5390: C9

UPDATE_RADAR_DOT_B:
        ; Per-entity radar update helper (variant B)
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5391: DD 7E 00
        and     a                                              ;#5394: A7
        ret     z                                              ;#5395: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#5396: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5399: DD 5E 08
        ld      bc,10h                                         ;#539C: 01 10 00
        add     ix,bc                                          ;#539F: DD 09
        ld      c,0D0h                                         ;#53A1: 0E D0
        ld      a,d                                            ;#53A3: 7A
        and     3                                              ;#53A4: E6 03
        or      c                                              ;#53A6: B1
        ld      c,a                                            ;#53A7: 4F
        ld      a,e                                            ;#53A8: 7B
        add     a,a                                            ;#53A9: 87
        add     a,a                                            ;#53AA: 87
        and     0Ch                                            ;#53AB: E6 0C
        or      c                                              ;#53AD: B1
        ld      c,a                                            ;#53AE: 4F
        ld      a,d                                            ;#53AF: 7A
        rra                                                    ;#53B0: 1F
        rra                                                    ;#53B1: 1F
        and     7                                              ;#53B2: E6 07
        ld      l,a                                            ;#53B4: 6F
        ld      a,e                                            ;#53B5: 7B
        add     a,a                                            ;#53B6: 87
        and     78h                                            ;#53B7: E6 78
        or      l                                              ;#53B9: B5
        ld      l,a                                            ;#53BA: 6F
        ld      h,0                                            ;#53BB: 26 00
        ld      de,OBSTACLE_GRID                               ;#53BD: 11 80 EA
        add     hl,de                                          ;#53C0: 19
        ld      a,(hl)                                         ;#53C1: 7E
        cp      90h                                            ;#53C2: FE 90
        jr      z,RADAR_B_WRITE_CELL                           ;#53C4: 28 05
        ld      a,(FRAME_TICK)                                 ;#53C6: 3A 07 E0
        rra                                                    ;#53C9: 1F
        ret     nc                                             ;#53CA: D0
RADAR_B_WRITE_CELL:
        ; Variant B write: store color C into the radar cell (opposite frame parity)
        ld      (hl),c                                         ;#53CB: 71
        ret                                                    ;#53CC: C9

INIT_STAGE:
        ; Fill RADAR_GRID with 90h and seed FLAG_TABLE with 10 random entries
        ; INIT_STAGE first fills RADAR_GRID (112 bytes) with 90h (empty-cell marker).
        ; Then loops 10 times: write 1 to flag's active byte, call NEXT_RANDOM twice for
        ; X/Y, place flag at random position. The 10 flags = 8 yellow + 2 red special,
        ; matching tile pattern in INIT_FLAGS at stage start.
        ld      hl,RADAR_GRID                                  ;#53CD: 21 00 EA
        ld      de,RADAR_GRID_TAIL                             ;#53D0: 11 01 EA
        ld      bc,6Fh                                         ;#53D3: 01 6F 00
        ld      (hl),90h                                       ;#53D6: 36 90
        ldir                                                   ;#53D8: ED B0
        ld      hl,FLAG_TABLE                                  ;#53DA: 21 00 E1
        ld      a,0Ah                                          ;#53DD: 3E 0A
        ld      (STAGE_DIFFICULTY),a                           ;#53DF: 32 2E E0
        ld      b,a                                            ;#53E2: 47
INIT_STAGE_FLAG_LOOP:
        ; Outer loop body: write 1 to active byte, push pointer, pick new random pos
        ld      (hl),1                                         ;#53E3: 36 01
        inc     hl                                             ;#53E5: 23
        push    hl                                             ;#53E6: E5
INIT_STAGE_RANDOM_X:
        ; Pick a random X (in [0..1Fh])
        call    NEXT_RANDOM                                    ;#53E7: CD EA 54
        and     1Fh                                            ;#53EA: E6 1F
        ld      h,a                                            ;#53EC: 67
INIT_STAGE_RANDOM_Y:
        ; Pick a random Y (must be < 38h; retry if larger)
        call    NEXT_RANDOM                                    ;#53ED: CD EA 54
        and     3Fh                                            ;#53F0: E6 3F
        cp      38h                                            ;#53F2: FE 38
        jr      nc,INIT_STAGE_RANDOM_Y                         ;#53F4: 30 F7
        ld      l,a                                            ;#53F6: 6F
        cp      4                                              ;#53F7: FE 04
        jr      c,INIT_STAGE_CHECK_Y_BOUNDS                    ;#53F9: 38 04
        cp      32h                                            ;#53FB: FE 32
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#53FD: 38 09
INIT_STAGE_CHECK_Y_BOUNDS:
        ; Y in range: check that X is not in PLAYER_SPAWN_ZONE (0..9 or 10h..14h)
        ld      a,h                                            ;#53FF: 7C
        cp      0Ah                                            ;#5400: FE 0A
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#5402: 38 04
        cp      15h                                            ;#5404: FE 15
        jr      c,INIT_STAGE_RANDOM_X                          ;#5406: 38 DF
INIT_STAGE_CHECK_PLAYFIELD:
        ; Coord passed; verify cell is not a wall via LOOKUP_PLAYFIELD_CELL
        call    LOOKUP_PLAYFIELD_CELL                          ;#5408: CD 81 4B
        jr      c,INIT_STAGE_RANDOM_X                          ;#540B: 38 DA
        ex      de,hl                                          ;#540D: EB
        ld      hl,ROCK_TABLE                                  ;#540E: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5411: 3A 1C E0
        and     a                                              ;#5414: A7
        jr      z,INIT_STAGE_AFTER_ROCKS                       ;#5415: 28 1A
        ld      c,a                                            ;#5417: 4F
INIT_STAGE_ROCK_DIST_LOOP:
        ; Check distance from each existing ROCK_TABLE entry (>=7 cells away)
        inc     hl                                             ;#5418: 23
        ld      a,(hl)                                         ;#5419: 7E
        inc     hl                                             ;#541A: 23
        sub     d                                              ;#541B: 92
        add     a,3                                            ;#541C: C6 03
        cp      7                                              ;#541E: FE 07
        jr      nc,INIT_STAGE_ROCK_NEXT                        ;#5420: 30 08
        ld      a,(hl)                                         ;#5422: 7E
        sub     e                                              ;#5423: 93
        add     a,3                                            ;#5424: C6 03
        cp      7                                              ;#5426: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#5428: 38 BD
INIT_STAGE_ROCK_NEXT:
        ; ROCK distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#542A: 7D
        add     a,0Eh                                          ;#542B: C6 0E
        ld      l,a                                            ;#542D: 6F
        dec     c                                              ;#542E: 0D
        jr      nz,INIT_STAGE_ROCK_DIST_LOOP                   ;#542F: 20 E7
INIT_STAGE_AFTER_ROCKS:
        ; After rock-dedup: check distance from existing FLAG_TABLE entries too
        ld      hl,FLAG_TABLE                                  ;#5431: 21 00 E1
        ld      a,0Ah                                          ;#5434: 3E 0A
        sub     b                                              ;#5436: 90
        jr      z,INIT_STAGE_PLACE_FLAG                        ;#5437: 28 1A
        ld      c,a                                            ;#5439: 4F
INIT_STAGE_FLAG_DIST_LOOP:
        ; Inner loop: compare candidate vs each placed flag in FLAG_TABLE
        inc     hl                                             ;#543A: 23
        ld      a,(hl)                                         ;#543B: 7E
        inc     hl                                             ;#543C: 23
        sub     d                                              ;#543D: 92
        add     a,3                                            ;#543E: C6 03
        cp      7                                              ;#5440: FE 07
        jr      nc,INIT_STAGE_FLAG_NEXT                        ;#5442: 30 08
        ld      a,(hl)                                         ;#5444: 7E
        sub     e                                              ;#5445: 93
        add     a,3                                            ;#5446: C6 03
        cp      7                                              ;#5448: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#544A: 38 9B
INIT_STAGE_FLAG_NEXT:
        ; FLAG distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#544C: 7D
        add     a,0Eh                                          ;#544D: C6 0E
        ld      l,a                                            ;#544F: 6F
        dec     c                                              ;#5450: 0D
        jr      nz,INIT_STAGE_FLAG_DIST_LOOP                   ;#5451: 20 E7
INIT_STAGE_PLACE_FLAG:
        ; All distance checks passed: write (X, Y) to flag entry and seed RADAR_GRID
        pop     hl                                             ;#5453: E1
        ld      (hl),d                                         ;#5454: 72
        inc     hl                                             ;#5455: 23
        ld      (hl),e                                         ;#5456: 73
        inc     hl                                             ;#5457: 23
        push    hl                                             ;#5458: E5
        ld      a,d                                            ;#5459: 7A
        and     3                                              ;#545A: E6 03
        ld      c,a                                            ;#545C: 4F
        ld      a,e                                            ;#545D: 7B
        add     a,a                                            ;#545E: 87
        add     a,a                                            ;#545F: 87
        or      c                                              ;#5460: B1
        and     0Fh                                            ;#5461: E6 0F
        or      0A0h                                           ;#5463: F6 A0
        ld      c,a                                            ;#5465: 4F
        ld      hl,RADAR_GRID                                  ;#5466: 21 00 EA
        ld      a,d                                            ;#5469: 7A
        rra                                                    ;#546A: 1F
        rra                                                    ;#546B: 1F
        and     7                                              ;#546C: E6 07
        add     a,l                                            ;#546E: 85
        ld      l,a                                            ;#546F: 6F
        ld      a,e                                            ;#5470: 7B
        add     a,a                                            ;#5471: 87
        and     78h                                            ;#5472: E6 78
        add     a,l                                            ;#5474: 85
        ld      l,a                                            ;#5475: 6F
        ld      (hl),c                                         ;#5476: 71
        set     7,l                                            ;#5477: CB FD
        ld      (RADAR_LAST_DOT_PTR),hl                        ;#5479: 22 25 E0
        pop     hl                                             ;#547C: E1
        ld      a,l                                            ;#547D: 7D
        and     0F0h                                           ;#547E: E6 F0
        add     a,10h                                          ;#5480: C6 10
        ld      l,a                                            ;#5482: 6F
        dec     b                                              ;#5483: 05
        jp      nz,INIT_STAGE_FLAG_LOOP                        ;#5484: C2 E3 53
        ret                                                    ;#5487: C9

INIT_FLAGS:
        ; Initialize FLAG_TABLE: 10 flags (8 regular + 2 special) at stage start
        ; INIT_FLAGS places the 10 stage flags. Walks FLAG_TABLE (10 entries x 8 bytes),
        ; for each: writes the active flag (1), uses NEXT_RANDOM to pick X/Y inside the
        ; playfield bounds, sets sprite parameters. The last 2 entries (index 9, 8 — set
        ; first in the iteration since B counts down) get tile 38h/34h color 8 (red
        ; SPECIAL flags); the rest get tile 30h color 2 (regular yellow flags). 10 = 8
        ; yellow + 2 red.
        ld      hl,FLAG_TABLE                                  ;#5488: 21 00 E1
        ld      b,0Ah                                          ;#548B: 06 0A
INIT_FLAGS_LOOP_TOP:
        ; Outer djnz of INIT_FLAGS (10 flag entries)
        ld      a,(hl)                                         ;#548D: 7E
        and     a                                              ;#548E: A7
        jp      z,INIT_FLAGS_NEXT_ENTRY                        ;#548F: CA E1 54
        inc     hl                                             ;#5492: 23
        ld      d,(hl)                                         ;#5493: 56
        inc     hl                                             ;#5494: 23
        ld      e,(hl)                                         ;#5495: 5E
        inc     hl                                             ;#5496: 23
        push    hl                                             ;#5497: E5
        ld      h,0                                            ;#5498: 26 00
        ld      a,d                                            ;#549A: 7A
        sub     0Fh                                            ;#549B: D6 0F
        jp      p,INIT_FLAGS_X_POS                             ;#549D: F2 A1 54
        dec     h                                              ;#54A0: 25
INIT_FLAGS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended for negative side of screen
        ld      c,a                                            ;#54A1: 4F
        add     a,a                                            ;#54A2: 87
        add     a,c                                            ;#54A3: 81
        ld      l,a                                            ;#54A4: 6F
        add     hl,hl                                          ;#54A5: 29
        add     hl,hl                                          ;#54A6: 29
        add     hl,hl                                          ;#54A7: 29
        ld      a,e                                            ;#54A8: 7B
        ld      de,58h                                         ;#54A9: 11 58 00
        add     hl,de                                          ;#54AC: 19
        ex      de,hl                                          ;#54AD: EB
        pop     hl                                             ;#54AE: E1
        ld      (hl),e                                         ;#54AF: 73
        inc     hl                                             ;#54B0: 23
        ld      (hl),d                                         ;#54B1: 72
        inc     hl                                             ;#54B2: 23
        push    hl                                             ;#54B3: E5
        ld      h,0                                            ;#54B4: 26 00
        sub     32h                                            ;#54B6: D6 32
        jp      p,INIT_FLAGS_Y_POS                             ;#54B8: F2 BC 54
        dec     h                                              ;#54BB: 25
INIT_FLAGS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended for top half of screen
        ld      l,a                                            ;#54BC: 6F
        add     a,a                                            ;#54BD: 87
        add     a,l                                            ;#54BE: 85
        ld      l,a                                            ;#54BF: 6F
        add     hl,hl                                          ;#54C0: 29
        add     hl,hl                                          ;#54C1: 29
        add     hl,hl                                          ;#54C2: 29
        ld      de,6Fh                                         ;#54C3: 11 6F 00
        add     hl,de                                          ;#54C6: 19
        ex      de,hl                                          ;#54C7: EB
        pop     hl                                             ;#54C8: E1
        ld      (hl),e                                         ;#54C9: 73
        inc     hl                                             ;#54CA: 23
        ld      (hl),d                                         ;#54CB: 72
        inc     hl                                             ;#54CC: 23
        ld      a,38h                                          ;#54CD: 3E 38
        ld      e,8                                            ;#54CF: 1E 08
        ld      c,b                                            ;#54D1: 48
        dec     c                                              ;#54D2: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54D3: 28 09
        ld      a,34h                                          ;#54D5: 3E 34
        dec     c                                              ;#54D7: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54D8: 28 04
        ld      a,30h                                          ;#54DA: 3E 30
        ld      e,2                                            ;#54DC: 1E 02
INIT_FLAGS_STORE_TILE:
        ; Choose tile/color: last-2 entries get the 34h/38h red SPECIAL flags
        ld      (hl),a                                         ;#54DE: 77
        inc     hl                                             ;#54DF: 23
        ld      (hl),e                                         ;#54E0: 73
INIT_FLAGS_NEXT_ENTRY:
        ; Advance HL by 10h to next FLAG_TABLE entry, djnz back to top
        ld      a,l                                            ;#54E1: 7D
        and     0F0h                                           ;#54E2: E6 F0
        add     a,10h                                          ;#54E4: C6 10
        ld      l,a                                            ;#54E6: 6F
        djnz    INIT_FLAGS_LOOP_TOP                            ;#54E7: 10 A4
        ret                                                    ;#54E9: C9

NEXT_RANDOM:
        ; LCG+LFSR random byte generator; advances RNG_LCG and RNG_LFSR, returns byte in A
        ; NEXT_RANDOM is a hybrid: an 8-bit LCG (RNG_LCG: x' = 5x + 1) combined with a
        ; 16-bit xor-shift LFSR (RNG_LFSR, seeded to 55AAh if it ever hits 0). Returns
        ; RNG_LCG + (RNG_LFSR low byte) in A. Used by INIT_STAGE for flag placement,
        ; SCROLL_ROCKS for rock positions, and ITERATE_ENEMY_CARS for AI decisions.
        ld      a,(RNG_LCG)                                    ;#54EA: 3A 18 E0
        ld      c,a                                            ;#54ED: 4F
        add     a,a                                            ;#54EE: 87
        add     a,a                                            ;#54EF: 87
        add     a,c                                            ;#54F0: 81
        inc     a                                              ;#54F1: 3C
        ld      (RNG_LCG),a                                    ;#54F2: 32 18 E0
        ld      c,a                                            ;#54F5: 4F
        push    hl                                             ;#54F6: E5
        ld      hl,(RNG_LFSR)                                  ;#54F7: 2A 19 E0
        ld      a,h                                            ;#54FA: 7C
        or      l                                              ;#54FB: B5
        jr      nz,RNG_LFSR_TICK                               ;#54FC: 20 03
        ld      hl,55AAh                                       ;#54FE: 21 AA 55
RNG_LFSR_TICK:
        ; LFSR step: A = H XOR L, shift, then xor bit 6 of XOR back into bit 0
        ld      a,h                                            ;#5501: 7C
        xor     l                                              ;#5502: AD
        add     a,a                                            ;#5503: 87
        add     a,a                                            ;#5504: 87
        adc     hl,hl                                          ;#5505: ED 6A
        ld      (RNG_LFSR),hl                                  ;#5507: 22 19 E0
        ld      a,l                                            ;#550A: 7D
        pop     hl                                             ;#550B: E1
        add     a,c                                            ;#550C: 81
        ret                                                    ;#550D: C9

SCROLL_FLAGS:
        ; Iterate FLAG_TABLE: apply world scroll, draw each flag sprite, detect collect
        ; SCROLL_FLAGS iterates the 10-entry FLAG_TABLE. For each active flag, it: (1)
        ; world-scrolls the entry's screen position, (2) checks player proximity, (3) on
        ; collect — calls ADD_SCORE, clears the flag's RADAR_GRID dot, decrements
        ; STAGE_DIFFICULTY (the remaining-flags counter); when that reaches 0, sets
        ; STAGE_CLEAR_FLAG. Draws non-collected flags as sprites at their screen
        ; position.
        ld      hl,FLAG_TABLE                                  ;#550E: 21 00 E1
        ld      b,0Ah                                          ;#5511: 06 0A
SCROLL_FLAGS_LOOP_TOP:
        ; Outer djnz of SCROLL_FLAGS (10 entries)
        ld      a,(hl)                                         ;#5513: 7E
        and     a                                              ;#5514: A7
        jp      z,SCROLL_FLAG_NEXT                             ;#5515: CA 7B 55
        inc     hl                                             ;#5518: 23
        inc     hl                                             ;#5519: 23
        inc     hl                                             ;#551A: 23
        ld      e,(hl)                                         ;#551B: 5E
        inc     hl                                             ;#551C: 23
        ld      d,(hl)                                         ;#551D: 56
        push    hl                                             ;#551E: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#551F: 3A 16 E0
        ld      l,a                                            ;#5522: 6F
        ld      h,0                                            ;#5523: 26 00
        rla                                                    ;#5525: 17
        jr      nc,SCROLL_FLAG_APPLY_DX                        ;#5526: 30 01
        dec     h                                              ;#5528: 25
SCROLL_FLAG_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to flag X position
        add     hl,de                                          ;#5529: 19
        ex      de,hl                                          ;#552A: EB
        pop     hl                                             ;#552B: E1
        ld      (hl),d                                         ;#552C: 72
        dec     hl                                             ;#552D: 2B
        ld      (hl),e                                         ;#552E: 73
        inc     hl                                             ;#552F: 23
        inc     hl                                             ;#5530: 23
        push    bc                                             ;#5531: C5
        ld      c,(hl)                                         ;#5532: 4E
        inc     hl                                             ;#5533: 23
        ld      b,(hl)                                         ;#5534: 46
        push    hl                                             ;#5535: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#5536: 3A 17 E0
        ld      l,a                                            ;#5539: 6F
        ld      h,0                                            ;#553A: 26 00
        rla                                                    ;#553C: 17
        jr      nc,SCROLL_FLAG_APPLY_DY                        ;#553D: 30 01
        dec     h                                              ;#553F: 25
SCROLL_FLAG_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to flag Y position
        add     hl,bc                                          ;#5540: 09
        ld      b,h                                            ;#5541: 44
        ld      c,l                                            ;#5542: 4D
        pop     hl                                             ;#5543: E1
        ld      (hl),b                                         ;#5544: 70
        dec     hl                                             ;#5545: 2B
        ld      (hl),c                                         ;#5546: 71
        ld      a,b                                            ;#5547: 78
        or      d                                              ;#5548: B2
        jr      nz,SCROLL_FLAG_OFFSCREEN                       ;#5549: 20 39
        ld      a,e                                            ;#554B: 7B
        cp      0A9h                                           ;#554C: FE A9
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#554E: 30 34
        ld      a,c                                            ;#5550: 79
        cp      0E0h                                           ;#5551: FE E0
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#5553: 30 2F
        sub     18h                                            ;#5555: D6 18
        inc     hl                                             ;#5557: 23
        inc     hl                                             ;#5558: 23
        ld      d,(hl)                                         ;#5559: 56
        inc     hl                                             ;#555A: 23
        ld      c,(hl)                                         ;#555B: 4E
        push    hl                                             ;#555C: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#555D: 2A 14 E0
        ld      (hl),a                                         ;#5560: 77
        inc     hl                                             ;#5561: 23
        ld      (hl),e                                         ;#5562: 73
        inc     hl                                             ;#5563: 23
        ld      (hl),d                                         ;#5564: 72
        inc     hl                                             ;#5565: 23
        ld      (hl),c                                         ;#5566: 71
        inc     hl                                             ;#5567: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5568: 22 14 E0
        pop     hl                                             ;#556B: E1
        sub     4Bh                                            ;#556C: D6 4B
        cp      19h                                            ;#556E: FE 19
        jr      nc,SCROLL_FLAG_POPBC                           ;#5570: 30 08
        ld      a,e                                            ;#5572: 7B
        sub     4Ch                                            ;#5573: D6 4C
        cp      19h                                            ;#5575: FE 19
        jp      c,SCROLL_FLAG_COLLECT                          ;#5577: DA 91 55
SCROLL_FLAG_POPBC:
        ; After collect check: restore BC saved during the inner body
        pop     bc                                             ;#557A: C1
SCROLL_FLAG_NEXT:
        ; Skip-this-flag path: advance HL by 10h, djnz back to next entry
        ld      a,l                                            ;#557B: 7D
        and     0F0h                                           ;#557C: E6 F0
SCROLL_FLAG_ADV_PTR:
        ; Tail of the per-frame loop: shared HL advance code
        add     a,10h                                          ;#557E: C6 10
        ld      l,a                                            ;#5580: 6F
        djnz    SCROLL_FLAGS_LOOP_TOP                          ;#5581: 10 90
        ret                                                    ;#5583: C9

SCROLL_FLAG_OFFSCREEN:
        ; Off-screen path: deactivate the flag entry and continue
        pop     bc                                             ;#5584: C1
        ld      a,l                                            ;#5585: 7D
        and     0F0h                                           ;#5586: E6 F0
        ld      l,a                                            ;#5588: 6F
        ld      c,(hl)                                         ;#5589: 4E
        dec     c                                              ;#558A: 0D
        jr      z,SCROLL_FLAG_ADV_PTR                          ;#558B: 28 F1
        ld      (hl),0                                         ;#558D: 36 00
        jr      SCROLL_FLAG_ADV_PTR                            ;#558F: 18 ED

SCROLL_FLAG_COLLECT:
        ; Collect: trigger SFX_FLAG, dec STAGE_DIFFICULTY, set STAGE_CLEAR if last
        ld      a,1                                            ;#5591: 3E 01
        ld      (hl),a                                         ;#5593: 77
        dec     hl                                             ;#5594: 2B
        push    hl                                             ;#5595: E5
        ld      a,l                                            ;#5596: 7D
        and     0F0h                                           ;#5597: E6 F0
        ld      l,a                                            ;#5599: 6F
        ld      a,(hl)                                         ;#559A: 7E
        pop     hl                                             ;#559B: E1
        dec     a                                              ;#559C: 3D
        jp      nz,SCROLL_FLAG_POPBC                           ;#559D: C2 7A 55
        inc     a                                              ;#55A0: 3C
        ld      (SOUND_STATE_FLAG),a                           ;#55A1: 32 40 E5
        ld      a,d                                            ;#55A4: 7A
        cp      34h                                            ;#55A5: FE 34
        jr      nz,SCROLL_FLAG_CHECK_SPECIAL                   ;#55A7: 20 07
        ld      a,1                                            ;#55A9: 3E 01
        ld      (PLAYER_DEAD_FLAG),a                           ;#55AB: 32 3B E0
        jr      SCROLL_FLAG_SCORE_TICK                         ;#55AE: 18 11

SCROLL_FLAG_CHECK_SPECIAL:
        ; Check whether this is a SPECIAL (red) flag for bonus scoring
        cp      38h                                            ;#55B0: FE 38
        jr      nz,SCROLL_FLAG_SCORE_TICK                      ;#55B2: 20 0D
        xor     a                                              ;#55B4: AF
        ld      (SOUND_STATE_FLAG),a                           ;#55B5: 32 40 E5
        inc     a                                              ;#55B8: 3C
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#55B9: 32 41 E5
        ld      a,1                                            ;#55BC: 3E 01
        ld      (MOVEMENT_SUB_PHASE),a                         ;#55BE: 32 2D E0
SCROLL_FLAG_SCORE_TICK:
        ; Award score chunk per-tick during the collect animation
        ld      a,(FRAME_TICK_SUB)                             ;#55C1: 3A 2C E0
        inc     a                                              ;#55C4: 3C
        ld      (FRAME_TICK_SUB),a                             ;#55C5: 32 2C E0
        add     a,a                                            ;#55C8: 87
        add     a,a                                            ;#55C9: 87
        add     a,a                                            ;#55CA: 87
        add     a,78h                                          ;#55CB: C6 78
        ld      c,a                                            ;#55CD: 4F
        ld      a,(MOVEMENT_SUB_PHASE)                         ;#55CE: 3A 2D E0
        and     a                                              ;#55D1: A7
        jr      z,SCROLL_FLAG_PHASE_SET                        ;#55D2: 28 04
        ld      a,c                                            ;#55D4: 79
        add     a,4                                            ;#55D5: C6 04
        ld      c,a                                            ;#55D7: 4F
SCROLL_FLAG_PHASE_SET:
        ; Phase-set: write target SAT cell color/tile for the score bubble
        ld      (hl),c                                         ;#55D8: 71
        push    hl                                             ;#55D9: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#55DA: 2A 14 E0
        dec     hl                                             ;#55DD: 2B
        ld      (hl),1                                         ;#55DE: 36 01
        dec     hl                                             ;#55E0: 2B
        ld      (hl),c                                         ;#55E1: 71
        pop     hl                                             ;#55E2: E1
        ld      a,l                                            ;#55E3: 7D
        and     0F0h                                           ;#55E4: E6 F0
        ld      l,a                                            ;#55E6: 6F
        ld      (hl),2                                         ;#55E7: 36 02
        ld      a,c                                            ;#55E9: 79
        rra                                                    ;#55EA: 1F
        rra                                                    ;#55EB: 1F
        and     1Fh                                            ;#55EC: E6 1F
        call    ADD_SCORE                                      ;#55EE: CD EC 8A
        push    hl                                             ;#55F1: E5
        inc     hl                                             ;#55F2: 23
        ld      d,(hl)                                         ;#55F3: 56
        inc     hl                                             ;#55F4: 23
        ld      e,(hl)                                         ;#55F5: 5E
        ld      hl,RADAR_GRID                                  ;#55F6: 21 00 EA
        ld      a,d                                            ;#55F9: 7A
        rra                                                    ;#55FA: 1F
        rra                                                    ;#55FB: 1F
        and     7                                              ;#55FC: E6 07
        add     a,l                                            ;#55FE: 85
        ld      l,a                                            ;#55FF: 6F
        ld      a,e                                            ;#5600: 7B
        add     a,a                                            ;#5601: 87
        and     78h                                            ;#5602: E6 78
        add     a,l                                            ;#5604: 85
        ld      l,a                                            ;#5605: 6F
        ld      (hl),90h                                       ;#5606: 36 90
        pop     hl                                             ;#5608: E1
        ld      a,(STAGE_DIFFICULTY)                           ;#5609: 3A 2E E0
        dec     a                                              ;#560C: 3D
        ld      (STAGE_DIFFICULTY),a                           ;#560D: 32 2E E0
        jp      nz,SCROLL_FLAG_NOT_LAST                        ;#5610: C2 18 56
        ld      a,1                                            ;#5613: 3E 01
        ld      (STAGE_CLEAR_FLAG),a                           ;#5615: 32 2F E0
SCROLL_FLAG_NOT_LAST:
        ; Not the last flag: fall through to LBL_71D7 (update HUD count)
        call    LOAD_STAGE_DIFFICULTY_TIER                     ;#5618: CD DD 94
        jp      SCROLL_FLAG_POPBC                              ;#561B: C3 7A 55

SCROLL_ROCKS:
        ; Iterate ROCK_TABLE: world-scroll + sprite draw
        ; SCROLL_ROCKS uses ROCK_SPAWN_COUNT as the iteration count. Each entry is
        ; seeded with a random position from ROCK_POSITIONS_N (using NEXT_RANDOM as the
        ; index byte), then drawn as a rock sprite at its world-scrolled screen
        ; position. Rocks are static obstacles — no AI.
        ld      hl,ROCK_TABLE                                  ;#561E: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5621: 3A 1C E0
        and     a                                              ;#5624: A7
        ret     z                                              ;#5625: C8
        ld      b,a                                            ;#5626: 47
SCROLL_ROCKS_LOOP_TOP:
        ; Outer djnz of SCROLL_ROCKS
        ld      (hl),1                                         ;#5627: 36 01
        inc     hl                                             ;#5629: 23
        push    hl                                             ;#562A: E5
SCROLL_ROCKS_PICK_POSITION:
        ; Pick a random ROCK_POSITIONS_N index, jump out if dup vs other rocks
        call    NEXT_RANDOM                                    ;#562B: CD EA 54
        ld      hl,MAZE_BITMAP_0                               ;#562E: 21 00 9C
        add     a,a                                            ;#5631: 87
        or      0E0h                                           ;#5632: F6 E0
        ld      l,a                                            ;#5634: 6F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#5635: 3A 30 E0
        rra                                                    ;#5638: 1F
        rra                                                    ;#5639: 1F
        and     3                                              ;#563A: E6 03
        or      h                                              ;#563C: B4
        ld      h,a                                            ;#563D: 67
        ld      d,(hl)                                         ;#563E: 56
        inc     hl                                             ;#563F: 23
        ld      e,(hl)                                         ;#5640: 5E
        ld      hl,ROCK_TABLE                                  ;#5641: 21 00 E2
        ld      a,0Ch                                          ;#5644: 3E 0C
        sub     b                                              ;#5646: 90
        jr      z,SCROLL_ROCKS_STORE                           ;#5647: 28 12
        ld      c,a                                            ;#5649: 4F
SCROLL_ROCKS_DEDUP_LOOP:
        ; Dedup loop: check candidate vs each placed rock entry
        inc     hl                                             ;#564A: 23
        ld      a,(hl)                                         ;#564B: 7E
        inc     hl                                             ;#564C: 23
        cp      d                                              ;#564D: BA
        jr      nz,SCROLL_ROCKS_DEDUP_NEXT                     ;#564E: 20 04
        ld      a,(hl)                                         ;#5650: 7E
        cp      e                                              ;#5651: BB
        jr      z,SCROLL_ROCKS_PICK_POSITION                   ;#5652: 28 D7
SCROLL_ROCKS_DEDUP_NEXT:
        ; Dedup OK for this entry: advance pointer to next rock
        ld      a,l                                            ;#5654: 7D
        add     a,0Eh                                          ;#5655: C6 0E
        ld      l,a                                            ;#5657: 6F
        dec     c                                              ;#5658: 0D
        jr      nz,SCROLL_ROCKS_DEDUP_LOOP                     ;#5659: 20 EF
SCROLL_ROCKS_STORE:
        ; All checks passed: write rock (X, Y) into ROCK_TABLE
        pop     hl                                             ;#565B: E1
        ld      (hl),d                                         ;#565C: 72
        inc     hl                                             ;#565D: 23
        ld      (hl),e                                         ;#565E: 73
        ld      a,l                                            ;#565F: 7D
        and     0F0h                                           ;#5660: E6 F0
        add     a,10h                                          ;#5662: C6 10
        ld      l,a                                            ;#5664: 6F
        djnz    SCROLL_ROCKS_LOOP_TOP                          ;#5665: 10 C0
        ret                                                    ;#5667: C9

INIT_ROCKS:
        ; Initialize ROCK_TABLE at stage start
        ; INIT_ROCKS clears ROCK_TABLE and seeds it from MAZE_BITMAP_N at 7C00..7F00
        ; using random positions. ROCK_SPAWN_COUNT (ROCK_SPAWN_COUNT) controls the
        ; count. Called once per stage from INITIAL_STATE_HANDLER's tail.
        ld      hl,ROCK_TABLE                                  ;#5668: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#566B: 3A 1C E0
        and     a                                              ;#566E: A7
        ret     z                                              ;#566F: C8
        ld      b,a                                            ;#5670: 47
INIT_ROCKS_LOOP_TOP:
        ; Outer djnz of INIT_ROCKS
        ld      a,(hl)                                         ;#5671: 7E
        and     a                                              ;#5672: A7
        jp      z,INIT_ROCKS_NEXT_ENTRY                        ;#5673: CA B6 56
        inc     hl                                             ;#5676: 23
        ld      d,(hl)                                         ;#5677: 56
        inc     hl                                             ;#5678: 23
        ld      e,(hl)                                         ;#5679: 5E
        inc     hl                                             ;#567A: 23
        push    hl                                             ;#567B: E5
        ld      h,0                                            ;#567C: 26 00
        ld      a,d                                            ;#567E: 7A
        sub     0Fh                                            ;#567F: D6 0F
        jp      p,INIT_ROCKS_X_POS                             ;#5681: F2 85 56
        dec     h                                              ;#5684: 25
INIT_ROCKS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended
        ld      c,a                                            ;#5685: 4F
        add     a,a                                            ;#5686: 87
        add     a,c                                            ;#5687: 81
        ld      l,a                                            ;#5688: 6F
        add     hl,hl                                          ;#5689: 29
        add     hl,hl                                          ;#568A: 29
        add     hl,hl                                          ;#568B: 29
        ld      a,e                                            ;#568C: 7B
        ld      de,58h                                         ;#568D: 11 58 00
        add     hl,de                                          ;#5690: 19
        ex      de,hl                                          ;#5691: EB
        pop     hl                                             ;#5692: E1
        ld      (hl),e                                         ;#5693: 73
        inc     hl                                             ;#5694: 23
        ld      (hl),d                                         ;#5695: 72
        inc     hl                                             ;#5696: 23
        push    hl                                             ;#5697: E5
        ld      h,0                                            ;#5698: 26 00
        sub     32h                                            ;#569A: D6 32
        jp      p,INIT_ROCKS_Y_POS                             ;#569C: F2 A0 56
        dec     h                                              ;#569F: 25
INIT_ROCKS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended
        ld      l,a                                            ;#56A0: 6F
        add     a,a                                            ;#56A1: 87
        add     a,l                                            ;#56A2: 85
        ld      l,a                                            ;#56A3: 6F
        add     hl,hl                                          ;#56A4: 29
        add     hl,hl                                          ;#56A5: 29
        add     hl,hl                                          ;#56A6: 29
        ld      de,6Fh                                         ;#56A7: 11 6F 00
        add     hl,de                                          ;#56AA: 19
        ex      de,hl                                          ;#56AB: EB
        pop     hl                                             ;#56AC: E1
        ld      (hl),e                                         ;#56AD: 73
        inc     hl                                             ;#56AE: 23
        ld      (hl),d                                         ;#56AF: 72
        inc     hl                                             ;#56B0: 23
        ld      (hl),3Ch                                       ;#56B1: 36 3C
        inc     hl                                             ;#56B3: 23
        ld      (hl),6                                         ;#56B4: 36 06
INIT_ROCKS_NEXT_ENTRY:
        ; Advance HL by 10h to next ROCK_TABLE entry, djnz back to top
        ld      a,l                                            ;#56B6: 7D
        and     0F0h                                           ;#56B7: E6 F0
        add     a,10h                                          ;#56B9: C6 10
        ld      l,a                                            ;#56BB: 6F
        djnz    INIT_ROCKS_LOOP_TOP                            ;#56BC: 10 B3
        ret                                                    ;#56BE: C9

UPDATE_ROCKS_COLLISION:
        ; Second pass over ROCK_TABLE (different update phase)
        ; UPDATE_ROCKS_COLLISION is the second iteration over ROCK_TABLE per frame,
        ; performing the "did the player hit a rock" detection. Different from
        ; SCROLL_ROCKS which renders sprites — PASS2 is collision logic.
        ld      hl,ROCK_TABLE                                  ;#56BF: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#56C2: 3A 1C E0
        and     a                                              ;#56C5: A7
        ret     z                                              ;#56C6: C8
        ld      b,a                                            ;#56C7: 47
UPDATE_ROCKS_COLLISION_LOOP_TOP:
        ; Outer djnz of UPDATE_ROCKS_COLLISION
        inc     hl                                             ;#56C8: 23
        inc     hl                                             ;#56C9: 23
        inc     hl                                             ;#56CA: 23
        ld      e,(hl)                                         ;#56CB: 5E
        inc     hl                                             ;#56CC: 23
        ld      d,(hl)                                         ;#56CD: 56
        push    hl                                             ;#56CE: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#56CF: 3A 16 E0
        ld      l,a                                            ;#56D2: 6F
        ld      h,0                                            ;#56D3: 26 00
        rla                                                    ;#56D5: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DX             ;#56D6: 30 01
        dec     h                                              ;#56D8: 25
UPDATE_ROCKS_COLLISION_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to rock X position
        add     hl,de                                          ;#56D9: 19
        ex      de,hl                                          ;#56DA: EB
        pop     hl                                             ;#56DB: E1
        ld      (hl),d                                         ;#56DC: 72
        dec     hl                                             ;#56DD: 2B
        ld      (hl),e                                         ;#56DE: 73
        inc     hl                                             ;#56DF: 23
        inc     hl                                             ;#56E0: 23
        push    bc                                             ;#56E1: C5
        ld      c,(hl)                                         ;#56E2: 4E
        inc     hl                                             ;#56E3: 23
        ld      b,(hl)                                         ;#56E4: 46
        push    hl                                             ;#56E5: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#56E6: 3A 17 E0
        ld      l,a                                            ;#56E9: 6F
        ld      h,0                                            ;#56EA: 26 00
        rla                                                    ;#56EC: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DY             ;#56ED: 30 01
        dec     h                                              ;#56EF: 25
UPDATE_ROCKS_COLLISION_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to rock Y position
        add     hl,bc                                          ;#56F0: 09
        ld      b,h                                            ;#56F1: 44
        ld      c,l                                            ;#56F2: 4D
        pop     hl                                             ;#56F3: E1
        ld      (hl),b                                         ;#56F4: 70
        dec     hl                                             ;#56F5: 2B
        ld      (hl),c                                         ;#56F6: 71
        ld      a,b                                            ;#56F7: 78
        or      d                                              ;#56F8: B2
        jr      nz,UPDATE_ROCKS_COLLISION_NEXT                 ;#56F9: 20 33
        ld      a,e                                            ;#56FB: 7B
        cp      0A9h                                           ;#56FC: FE A9
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#56FE: 30 2E
        ld      a,c                                            ;#5700: 79
        cp      0E0h                                           ;#5701: FE E0
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#5703: 30 29
        sub     18h                                            ;#5705: D6 18
        inc     hl                                             ;#5707: 23
        inc     hl                                             ;#5708: 23
        ld      d,(hl)                                         ;#5709: 56
        inc     hl                                             ;#570A: 23
        ld      c,(hl)                                         ;#570B: 4E
        push    hl                                             ;#570C: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#570D: 2A 14 E0
        ld      (hl),a                                         ;#5710: 77
        inc     hl                                             ;#5711: 23
        ld      (hl),e                                         ;#5712: 73
        inc     hl                                             ;#5713: 23
        ld      (hl),d                                         ;#5714: 72
        inc     hl                                             ;#5715: 23
        ld      (hl),c                                         ;#5716: 71
        inc     hl                                             ;#5717: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5718: 22 14 E0
        sub     4Fh                                            ;#571B: D6 4F
        cp      11h                                            ;#571D: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#571F: 30 0C
        ld      a,e                                            ;#5721: 7B
        sub     50h                                            ;#5722: D6 50
        cp      11h                                            ;#5724: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#5726: 30 05
        ld      a,1                                            ;#5728: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#572A: 32 49 E0
UPDATE_ROCKS_COLLISION_DEATH:
        ; Player-on-rock collision: set GAME_OVER_FLAG=1
        pop     hl                                             ;#572D: E1
UPDATE_ROCKS_COLLISION_NEXT:
        ; Skip-this-rock: advance HL by 10h, djnz back
        pop     bc                                             ;#572E: C1
        ld      a,l                                            ;#572F: 7D
        and     0F0h                                           ;#5730: E6 F0
        add     a,10h                                          ;#5732: C6 10
        ld      l,a                                            ;#5734: 6F
        djnz    UPDATE_ROCKS_COLLISION_LOOP_TOP                ;#5735: 10 91
        ret                                                    ;#5737: C9

ADD_DE_TO_ENEMY_X:
        ; Add DE (sign-extended) to ENEMY_OFFSET_X (9..0Ah) of all 7 enemies
        ; ADD_DE_TO_ENEMY_X iterates 7 ENEMY_CAR_TABLE entries (skipping E300+0=type).
        ; For each entry, adds DE (sign-extended via rla) to ENEMY_OFFSET_X (screen X,
        ; 9..0Ah). Applies the world-scroll delta to every enemy's screen X when the
        ; player moves.
        exx                                                    ;#5738: D9
        ld      e,a                                            ;#5739: 5F
        ld      d,0                                            ;#573A: 16 00
        rla                                                    ;#573C: 17
        jr      nc,ADD_DE_ENEMY_X_INIT                         ;#573D: 30 01
        dec     d                                              ;#573F: 15
ADD_DE_ENEMY_X_INIT:
        ; ADD_DE_TO_ENEMY_X init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#5740: DD 21 00 E3
        ld      bc,10h                                         ;#5744: 01 10 00
        ld      a,7                                            ;#5747: 3E 07
ADD_DE_ENEMY_X_LOOP:
        ; Per-enemy djnz body: load (ix+9..0Ah), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5749: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#574C: DD 6E 09
        add     hl,de                                          ;#574F: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5750: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#5753: DD 75 09
        add     ix,bc                                          ;#5756: DD 09
        dec     a                                              ;#5758: 3D
        jr      nz,ADD_DE_ENEMY_X_LOOP                         ;#5759: 20 EE
        ld      a,e                                            ;#575B: 7B
        exx                                                    ;#575C: D9
        ret                                                    ;#575D: C9

ADD_DE_TO_ENEMY_Y:
        ; Add DE (sign-extended) to ENEMY_OFFSET_Y (0Bh..0Ch) of all 7 enemies
        ; ADD_DE_TO_ENEMY_Y is the same shape for ENEMY_OFFSET_Y (screen Y, 0Bh..0Ch).
        ; Together they scroll all enemies' screen X/Y with the world.
        exx                                                    ;#575E: D9
        ld      e,a                                            ;#575F: 5F
        ld      d,0                                            ;#5760: 16 00
        rla                                                    ;#5762: 17
        jr      nc,ADD_DE_ENEMY_Y_INIT                         ;#5763: 30 01
        dec     d                                              ;#5765: 15
ADD_DE_ENEMY_Y_INIT:
        ; ADD_DE_TO_ENEMY_Y init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#5766: DD 21 00 E3
        ld      bc,10h                                         ;#576A: 01 10 00
        ld      a,7                                            ;#576D: 3E 07
ADD_DE_ENEMY_Y_LOOP:
        ; Per-enemy djnz body: load (ix+0Bh..0Ch), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#576F: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5772: DD 6E 0B
        add     hl,de                                          ;#5775: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5776: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5779: DD 75 0B
        add     ix,bc                                          ;#577C: DD 09
        dec     a                                              ;#577E: 3D
        jr      nz,ADD_DE_ENEMY_Y_LOOP                         ;#577F: 20 EE
        ld      a,e                                            ;#5781: 7B
        exx                                                    ;#5782: D9
        ret                                                    ;#5783: C9

ITERATE_ENEMY_CARS:
        ; Dec ENEMY_CAR_ITER_TIMER, then call UPDATE_ENEMY_CAR_ENTRY 6x (AI every frame)
        ; ITERATE_ENEMY_CARS decrements ENEMY_CAR_ITER_TIMER toward 0 each frame, then
        ; unconditionally calls UPDATE_ENEMY_CAR_ENTRY 6 times — the AI runs every frame
        ; regardless of the timer. The timer is a start-of-stage grace period: while it
        ; is non-zero an enemy touching the player does not set GAME_OVER_FLAG (checked
        ; at 5A74h).
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#5784: 3A 1D E0
        and     a                                              ;#5787: A7
        jr      z,ITER_ENEMY_KICK_AI                           ;#5788: 28 04
        dec     a                                              ;#578A: 3D
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#578B: 32 1D E0
ITER_ENEMY_KICK_AI:
        ; After timer dec: call UPDATE_ENEMY_CAR_ENTRY 6 times in a row
        ld      ix,ENEMY_CAR_TABLE                             ;#578E: DD 21 00 E3
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5792: CD A4 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5795: CD A4 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5798: CD A4 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#579B: CD A4 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#579E: CD A4 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#57A1: CD A4 57
UPDATE_ENEMY_CAR_ENTRY:
        ; Update ENEMY_CAR_TABLE entry; branch on (ix+0) type, reads PLAYER_MOVE_GATE
        ; UPDATE_ENEMY_CAR_ENTRY runs each enemy car's AI per tick. Reads (ix+0) type;
        ; if 2 (special "hit player" state), branches to DRAW_ENEMY_CAR_SPRITE.
        ; Otherwise (PLAYER_MOVE_GATE clear and ENEMY_STEP_SPEED non-zero) chases the
        ; player: rock/smoke bounce via CHECK_ENEMY_HITS_ROCK, then a direction pick
        ; toward PLAYER_SCREEN_X/Y using APPLY_DIRECTION_TO_POS and the SCAN_PLAYFIELD_*
        ; helpers, moving at ENEMY_STEP_SPEED. See ENEMY_AI.md.
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#57A4: DD 7E 00
        and     a                                              ;#57A7: A7
        ret     z                                              ;#57A8: C8
        cp      2                                              ;#57A9: FE 02
        jp      z,ENEMY_HIT_PHASE                              ;#57AB: CA 16 5A
        ld      a,(PLAYER_MOVE_GATE)                           ;#57AE: 3A 45 E0
        and     a                                              ;#57B1: A7
        jr      nz,ENEMY_AI_RUN_TICK                           ;#57B2: 20 08
        ld      hl,(ENEMY_STEP_SPEED)                          ;#57B4: 2A 41 E0
        ld      a,h                                            ;#57B7: 7C
        or      l                                              ;#57B8: B5
        jp      z,DRAW_ENEMY_CAR_SPRITE                        ;#57B9: CA 37 5A
ENEMY_AI_RUN_TICK:
        ; Run AI for this enemy: rock collision, AI tick countdown, target chase
        call    CHECK_ENEMY_HITS_ROCK                          ;#57BC: CD 7F 5B
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#57BF: DD 7E 01
        dec     (ix+ENEMY_OFFSET_TIMER)                        ;#57C2: DD 35 01
        cp      6                                              ;#57C5: FE 06
        jp      nc,DRAW_ENEMY_CAR_SPRITE                       ;#57C7: D2 37 5A
        and     a                                              ;#57CA: A7
        jr      nz,ENEMY_BOUNCE_DELAY                          ;#57CB: 20 03
        inc     (ix+ENEMY_OFFSET_TIMER)                        ;#57CD: DD 34 01
ENEMY_BOUNCE_DELAY:
        ; Bounce-delay over: re-evaluate target direction
        ld      a,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#57D0: DD 7E 04
        sub     0Ah                                            ;#57D3: D6 0A
        cp      5                                              ;#57D5: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57D7: D2 85 58
        ld      a,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#57DA: DD 7E 07
        sub     0Ah                                            ;#57DD: D6 0A
        cp      5                                              ;#57DF: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57E1: D2 85 58
        dec     (ix+ENEMY_OFFSET_STATE)                        ;#57E4: DD 35 02
        jp      nz,ENEMY_RETRY_DIRS                            ;#57E7: C2 59 58
        ld      (ix+ENEMY_OFFSET_STATE),2                      ;#57EA: DD 36 02 02
        ld      a,(PLAYER_SCREEN_Y)                            ;#57EE: 3A 24 E0
        sub     (ix+ENEMY_OFFSET_CELL_Y)                       ;#57F1: DD 96 08
        ld      h,a                                            ;#57F4: 67
        jr      nc,ENEMY_ABS_DY                                ;#57F5: 30 02
        neg                                                    ;#57F7: ED 44
ENEMY_ABS_DY:
        ; |target_y - my_y| - jr nc skips neg, branch falls into ABS_DY
        ld      l,a                                            ;#57F9: 6F
        ld      a,(PLAYER_SCREEN_X)                            ;#57FA: 3A 23 E0
        sub     (ix+ENEMY_OFFSET_CELL_X)                       ;#57FD: DD 96 05
        ld      d,a                                            ;#5800: 57
        jr      nc,ENEMY_ABS_DX                                ;#5801: 30 02
        neg                                                    ;#5803: ED 44
ENEMY_ABS_DX:
        ; |target_x - my_x| - jr nc skips neg, branch falls into ABS_DX
        cp      l                                              ;#5805: BD
        jp      nc,ENEMY_PREFER_HORIZ                          ;#5806: D2 32 58
        xor     a                                              ;#5809: AF
        bit     7,h                                            ;#580A: CB 7C
        jr      nz,ENEMY_STORE_DIR_VERT                        ;#580C: 20 02
        ld      a,2                                            ;#580E: 3E 02
ENEMY_STORE_DIR_VERT:
        ; Vertical preferred: store dir 0 or 2 based on sign(dy) into c
        ld      c,a                                            ;#5810: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#5811: DD 96 0F
        and     3                                              ;#5814: E6 03
        cp      2                                              ;#5816: FE 02
        ld      a,c                                            ;#5818: 79
        jr      z,ENEMY_ROTATE_HORIZ                           ;#5819: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#581B: CD DF 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#581E: D2 77 58
ENEMY_ROTATE_HORIZ:
        ; Rotate to horizontal: fall back to horiz when vertical fails APPLY_DIR
        ld      a,1                                            ;#5821: 3E 01
        bit     7,d                                            ;#5823: CB 7A
        jr      z,ENEMY_FALLBACK_HORIZ                         ;#5825: 28 02
        ld      a,3                                            ;#5827: 3E 03
ENEMY_FALLBACK_HORIZ:
        ; Horizontal fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#5829: CD DF 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#582C: D2 77 58
        jp      ENEMY_RETRY_DIRS                               ;#582F: C3 59 58

ENEMY_PREFER_HORIZ:
        ; Horizontal preferred: store dir 1 or 3 based on sign(dx) into c
        ld      a,1                                            ;#5832: 3E 01
        ld      e,h                                            ;#5834: 5C
        bit     7,d                                            ;#5835: CB 7A
        jr      z,ENEMY_STORE_DIR_HORIZ                        ;#5837: 28 02
        ld      a,3                                            ;#5839: 3E 03
ENEMY_STORE_DIR_HORIZ:
        ; Horizontal store: keep direction in c, try APPLY_DIRECTION_TO_POS
        ld      c,a                                            ;#583B: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#583C: DD 96 0F
        and     3                                              ;#583F: E6 03
        cp      2                                              ;#5841: FE 02
        ld      a,c                                            ;#5843: 79
        jr      z,ENEMY_ROTATE_VERT                            ;#5844: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#5846: CD DF 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5849: D2 77 58
ENEMY_ROTATE_VERT:
        ; Rotate to vertical: fall back to vertical when horiz fails APPLY_DIR
        xor     a                                              ;#584C: AF
        bit     7,e                                            ;#584D: CB 7B
        jr      nz,ENEMY_FALLBACK_VERT                         ;#584F: 20 02
        ld      a,2                                            ;#5851: 3E 02
ENEMY_FALLBACK_VERT:
        ; Vertical fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#5853: CD DF 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5856: D2 77 58
ENEMY_RETRY_DIRS:
        ; Retry directions: cycle through 4 directions looking for an unblocked one
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5859: DD 7E 0F
        call    APPLY_DIRECTION_TO_POS                         ;#585C: CD DF 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#585F: 30 0E
        inc     a                                              ;#5861: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#5862: CD DF 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#5865: 30 08
        inc     a                                              ;#5867: 3C
        inc     a                                              ;#5868: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#5869: CD DF 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#586C: 30 01
        dec     a                                              ;#586E: 3D
ENEMY_PICK_DIR_OK:
        ; Direction picked: mask to 2 bits and store as (ix+0Fh)
        and     3                                              ;#586F: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5871: DD 77 0F
        jp      ENEMY_DISPATCH_DIR                             ;#5874: C3 88 58

ENEMY_REVERSE_GUARD:
        ; Reverse-guard: don't flip 180 degrees on consecutive ticks
        and     3                                              ;#5877: E6 03
        ld      c,a                                            ;#5879: 4F
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#587A: DD 7E 0F
        xor     2                                              ;#587D: EE 02
        cp      c                                              ;#587F: B9
        jr      z,ENEMY_RETRY_DIRS                             ;#5880: 28 D7
        ld      (ix+ENEMY_OFFSET_DIR),c                        ;#5882: DD 71 0F
ENEMY_READ_DIR:
        ; Read (ix+0Fh) as current AI direction byte
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5885: DD 7E 0F
ENEMY_DISPATCH_DIR:
        ; Dispatch on direction bits: 0/1/2/3 -> DIR0/DIR1/DIR2/DIR3 paths
        rra                                                    ;#5888: 1F
        jp      nc,ENEMY_DIR2_RUN                              ;#5889: D2 51 59
        rra                                                    ;#588C: 1F
        jr      nc,ENEMY_DIR1_RUN                              ;#588D: 30 62
        ld      a,0Ch                                          ;#588F: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#5891: DD 96 07
        jr      z,ENEMY_DIR2_DONE                              ;#5894: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#5896: DD 36 07 0C
        ld      e,a                                            ;#589A: 5F
        ld      d,0                                            ;#589B: 16 00
        jr      nc,ENEMY_DIR2_ADD                              ;#589D: 30 01
        dec     d                                              ;#589F: 15
ENEMY_DIR2_ADD:
        ; DIR2 (right) inner: add velocity to (ix+0Bh..0Ch) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#58A0: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#58A3: DD 6E 0B
        add     hl,de                                          ;#58A6: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#58A7: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#58AA: DD 75 0B
ENEMY_DIR2_DONE:
        ; DIR2 done: update target_pos and shape change
        ld      de,(ENEMY_STEP_SPEED)                          ;#58AD: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#58B1: 3A 45 E0
        and     a                                              ;#58B4: A7
        jr      z,ENEMY_DIR0_RUN                               ;#58B5: 28 03
        ld      de,300h                                        ;#58B7: 11 00 03
ENEMY_DIR0_RUN:
        ; DIR0 (up) main: write velocity to (ix+4) and propagate
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#58BA: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#58BD: DD 6E 03
        and     a                                              ;#58C0: A7
        ld      a,h                                            ;#58C1: 7C
        sbc     hl,de                                          ;#58C2: ED 52
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#58C4: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#58C7: DD 75 03
        sub     h                                              ;#58CA: 94
        neg                                                    ;#58CB: ED 44
        ld      e,a                                            ;#58CD: 5F
        ld      d,0                                            ;#58CE: 16 00
        rla                                                    ;#58D0: 17
        jr      nc,ENEMY_DIR0_BORROW_CHECK                     ;#58D1: 30 01
        dec     d                                              ;#58D3: 15
ENEMY_DIR0_BORROW_CHECK:
        ; DIR0 borrow check: if (ix+4) overflowed negative, fix +18h and dec (ix+5)
        bit     7,h                                            ;#58D4: CB 7C
        jr      z,ENEMY_DIR0_STORE_POS                         ;#58D6: 28 09
        ld      a,h                                            ;#58D8: 7C
        add     a,18h                                          ;#58D9: C6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#58DB: DD 77 04
        dec     (ix+ENEMY_OFFSET_CELL_X)                       ;#58DE: DD 35 05
ENEMY_DIR0_STORE_POS:
        ; DIR0 store: write updated world X (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#58E1: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#58E4: DD 6E 09
        add     hl,de                                          ;#58E7: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#58E8: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#58EB: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#58EE: C3 37 5A

ENEMY_DIR1_RUN:
        ; DIR1 (right) main: write velocity to (ix+7) and propagate to world Y
        ld      a,0Ch                                          ;#58F1: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#58F3: DD 96 07
        jr      z,ENEMY_DIR1_PHASE2                            ;#58F6: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#58F8: DD 36 07 0C
        ld      e,a                                            ;#58FC: 5F
        ld      d,0                                            ;#58FD: 16 00
        jr      nc,ENEMY_DIR1_ADD                              ;#58FF: 30 01
        dec     d                                              ;#5901: 15
ENEMY_DIR1_ADD:
        ; DIR1 add: adjust position by delta and store new (ix+0Bh..0Ch)
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5902: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5905: DD 6E 0B
        add     hl,de                                          ;#5908: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5909: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#590C: DD 75 0B
ENEMY_DIR1_PHASE2:
        ; DIR1 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#590F: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#5913: 3A 45 E0
        and     a                                              ;#5916: A7
        jr      z,ENEMY_DIR1_APPLY                             ;#5917: 28 03
        ld      de,300h                                        ;#5919: 11 00 03
ENEMY_DIR1_APPLY:
        ; DIR1 apply: add target step into (ix+3..+4) world X
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#591C: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#591F: DD 6E 03
        ld      a,h                                            ;#5922: 7C
        add     hl,de                                          ;#5923: 19
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#5924: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#5927: DD 75 03
        sub     h                                              ;#592A: 94
        neg                                                    ;#592B: ED 44
        ld      e,a                                            ;#592D: 5F
        ld      d,0                                            ;#592E: 16 00
        rla                                                    ;#5930: 17
        jr      nc,ENEMY_DIR1_CARRY_CHECK                      ;#5931: 30 01
        dec     d                                              ;#5933: 15
ENEMY_DIR1_CARRY_CHECK:
        ; DIR1 carry check: if (ix+4) >= 18h, fix -18h and inc (ix+5)
        ld      a,h                                            ;#5934: 7C
        cp      18h                                            ;#5935: FE 18
        jr      c,ENEMY_DIR1_STORE_POS                         ;#5937: 38 08
        sub     18h                                            ;#5939: D6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#593B: DD 77 04
        inc     (ix+ENEMY_OFFSET_CELL_X)                       ;#593E: DD 34 05
ENEMY_DIR1_STORE_POS:
        ; DIR1 store: write updated world Y (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5941: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5944: DD 6E 09
        add     hl,de                                          ;#5947: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#5948: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#594B: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#594E: C3 37 5A

ENEMY_DIR2_RUN:
        ; DIR2 (down) main: shift back from DIR0/1 paths into common
        rra                                                    ;#5951: 1F
        jr      c,ENEMY_DIR3_RUN                               ;#5952: 38 62
        ld      a,0Ch                                          ;#5954: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#5956: DD 96 04
        jr      z,ENEMY_DIR2_PHASE2                            ;#5959: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#595B: DD 36 04 0C
        ld      e,a                                            ;#595F: 5F
        ld      d,0                                            ;#5960: 16 00
        jr      nc,ENEMY_DIR2_ADD2                             ;#5962: 30 01
        dec     d                                              ;#5964: 15
ENEMY_DIR2_ADD2:
        ; DIR2 add 2: secondary add to (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5965: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5968: DD 6E 09
        add     hl,de                                          ;#596B: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#596C: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#596F: DD 75 09
ENEMY_DIR2_PHASE2:
        ; DIR2 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#5972: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#5976: 3A 45 E0
        and     a                                              ;#5979: A7
        jr      z,ENEMY_DIR2_APPLY                             ;#597A: 28 03
        ld      de,300h                                        ;#597C: 11 00 03
ENEMY_DIR2_APPLY:
        ; DIR2 apply: subtract step from (ix+6..7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#597F: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#5982: DD 6E 06
        and     a                                              ;#5985: A7
        ld      a,h                                            ;#5986: 7C
        sbc     hl,de                                          ;#5987: ED 52
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#5989: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#598C: DD 75 06
        sub     h                                              ;#598F: 94
        neg                                                    ;#5990: ED 44
        ld      e,a                                            ;#5992: 5F
        ld      d,0                                            ;#5993: 16 00
        rla                                                    ;#5995: 17
        jr      nc,ENEMY_DIR2_BORROW_CHECK                     ;#5996: 30 01
        dec     d                                              ;#5998: 15
ENEMY_DIR2_BORROW_CHECK:
        ; DIR2 borrow check: if (ix+7) underflowed, fix +18h and dec (ix+8)
        bit     7,h                                            ;#5999: CB 7C
        jr      z,ENEMY_DIR2_STORE_POS                         ;#599B: 28 09
        ld      a,h                                            ;#599D: 7C
        add     a,18h                                          ;#599E: C6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#59A0: DD 77 07
        dec     (ix+ENEMY_OFFSET_CELL_Y)                       ;#59A3: DD 35 08
ENEMY_DIR2_STORE_POS:
        ; DIR2 store: write updated world (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#59A6: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#59A9: DD 6E 0B
        add     hl,de                                          ;#59AC: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#59AD: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#59B0: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#59B3: C3 37 5A

ENEMY_DIR3_RUN:
        ; DIR3 (left) main: write velocity to (ix+4) and propagate
        ld      a,0Ch                                          ;#59B6: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#59B8: DD 96 04
        jr      z,ENEMY_DIR3_PHASE2                            ;#59BB: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#59BD: DD 36 04 0C
        ld      e,a                                            ;#59C1: 5F
        ld      d,0                                            ;#59C2: 16 00
        jr      nc,ENEMY_DIR3_ADD                              ;#59C4: 30 01
        dec     d                                              ;#59C6: 15
ENEMY_DIR3_ADD:
        ; DIR3 add: adjust position and store (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#59C7: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#59CA: DD 6E 09
        add     hl,de                                          ;#59CD: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#59CE: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#59D1: DD 75 09
ENEMY_DIR3_PHASE2:
        ; DIR3 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#59D4: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#59D8: 3A 45 E0
        and     a                                              ;#59DB: A7
        jr      z,ENEMY_DIR3_APPLY                             ;#59DC: 28 03
        ld      de,300h                                        ;#59DE: 11 00 03
ENEMY_DIR3_APPLY:
        ; DIR3 apply: add target step into (ix+6..+7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#59E1: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#59E4: DD 6E 06
        ld      a,h                                            ;#59E7: 7C
        add     hl,de                                          ;#59E8: 19
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#59E9: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#59EC: DD 75 06
        sub     h                                              ;#59EF: 94
        neg                                                    ;#59F0: ED 44
        ld      e,a                                            ;#59F2: 5F
        ld      d,0                                            ;#59F3: 16 00
        rla                                                    ;#59F5: 17
        jr      nc,ENEMY_DIR3_CARRY_CHECK                      ;#59F6: 30 01
        dec     d                                              ;#59F8: 15
ENEMY_DIR3_CARRY_CHECK:
        ; DIR3 carry check: if (ix+7) >= 18h, fix -18h and inc (ix+8)
        ld      a,h                                            ;#59F9: 7C
        cp      18h                                            ;#59FA: FE 18
        jr      c,ENEMY_DIR3_STORE_POS                         ;#59FC: 38 08
        sub     18h                                            ;#59FE: D6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#5A00: DD 77 07
        inc     (ix+ENEMY_OFFSET_CELL_Y)                       ;#5A03: DD 34 08
ENEMY_DIR3_STORE_POS:
        ; DIR3 store: write updated (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5A06: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5A09: DD 6E 0B
        add     hl,de                                          ;#5A0C: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5A0D: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5A10: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A13: C3 37 5A

ENEMY_HIT_PHASE:
        ; Enemy hit state (type=2): tick the bounce-away animation phase
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5A16: DD 7E 01
        dec     a                                              ;#5A19: 3D
        jr      z,ENEMY_HIT_RESET                              ;#5A1A: 28 17
        ld      (ix+ENEMY_OFFSET_TIMER),a                      ;#5A1C: DD 77 01
        and     1                                              ;#5A1F: E6 01
        jr      nz,DRAW_ENEMY_CAR_SPRITE                       ;#5A21: 20 14
        ld      a,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A23: DD 7E 0D
        add     a,4                                            ;#5A26: C6 04
        cp      30h                                            ;#5A28: FE 30
        jr      c,ENEMY_HIT_STORE_ROT                          ;#5A2A: 38 01
        xor     a                                              ;#5A2C: AF
ENEMY_HIT_STORE_ROT:
        ; Store updated bounce rotation back to (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5A2D: DD 77 0D
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A30: C3 37 5A

ENEMY_HIT_RESET:
        ; Bounce finished: re-activate enemy with type=1
        ld      (ix+ENEMY_OFFSET_TYPE),1                       ;#5A33: DD 36 00 01
DRAW_ENEMY_CAR_SPRITE:
        ; Bounds-check (ix+9..0Ch) entry position, write sprite to SAT_MIRROR
        ; DRAW_ENEMY_CAR_SPRITE validates enemy-car position then writes one sprite to
        ; SAT_MIRROR. Bounds: (ix+0Ah) and (ix+0Ch) must be 0 (high bytes of 16-bit
        ; X/Y), (ix+9) < 0A9h, (ix+0Bh) < 0E0h. Sprite Y = pos-Y - 18h (height offset).
        ld      a,(ix+ENEMY_OFFSET_X_HI)                       ;#5A37: DD 7E 0A
        or      (ix+ENEMY_OFFSET_Y_HI)                         ;#5A3A: DD B6 0C
        jp      nz,ENEMY_AI_ADVANCE_IX                         ;#5A3D: C2 04 5B
        ld      a,(ix+ENEMY_OFFSET_X)                          ;#5A40: DD 7E 09
        cp      0A9h                                           ;#5A43: FE A9
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A45: D2 04 5B
        ld      d,a                                            ;#5A48: 57
        ld      a,(ix+ENEMY_OFFSET_Y)                          ;#5A49: DD 7E 0B
        ld      e,a                                            ;#5A4C: 5F
        cp      0E0h                                           ;#5A4D: FE E0
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A4F: D2 04 5B
        ld      (ix+ENEMY_OFFSET_STATE),1                      ;#5A52: DD 36 02 01
        sub     18h                                            ;#5A56: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5A58: 2A 14 E0
        ld      (hl),a                                         ;#5A5B: 77
        inc     hl                                             ;#5A5C: 23
        ld      (hl),d                                         ;#5A5D: 72
        inc     hl                                             ;#5A5E: 23
        ld      c,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A5F: DD 4E 0D
        ld      (hl),c                                         ;#5A62: 71
        inc     hl                                             ;#5A63: 23
        ld      b,(ix+ENEMY_OFFSET_COLOR)                      ;#5A64: DD 46 0E
        ld      (hl),b                                         ;#5A67: 70
        inc     hl                                             ;#5A68: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5A69: 22 14 E0
        sub     4Fh                                            ;#5A6C: D6 4F
        cp      11h                                            ;#5A6E: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A70: 30 12
        ld      a,d                                            ;#5A72: 7A
        sub     50h                                            ;#5A73: D6 50
        cp      11h                                            ;#5A75: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A77: 30 0B
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#5A79: 3A 1D E0
        and     a                                              ;#5A7C: A7
        jr      nz,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A7D: 20 05
        ld      a,1                                            ;#5A7F: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#5A81: 32 49 E0
DRAW_ENEMY_VS_SMOKE_LOOP:
        ; For each smoke trail entry: check overlap with this enemy car
        ex      de,hl                                          ;#5A84: EB
        ld      iy,SMOKE_TRAIL_TABLE                           ;#5A85: FD 21 00 E4
        ld      b,9                                            ;#5A89: 06 09
DRAW_ENEMY_SMOKE_INNER:
        ; Inner djnz of DRAW_ENEMY_VS_SMOKE_LOOP
        ld      a,(iy+SMOKE_OFFSET_ACTIVE)                     ;#5A8B: FD 7E 00
        and     a                                              ;#5A8E: A7
        jr      z,DRAW_ENEMY_SMOKE_NEXT                        ;#5A8F: 28 31
        ld      a,(iy+SMOKE_OFFSET_X)                          ;#5A91: FD 7E 03
        sub     h                                              ;#5A94: 94
        add     a,4                                            ;#5A95: C6 04
        cp      9                                              ;#5A97: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5A99: 30 27
        ld      a,(iy+SMOKE_OFFSET_Y)                          ;#5A9B: FD 7E 05
        sub     l                                              ;#5A9E: 95
        add     a,4                                            ;#5A9F: C6 04
        cp      9                                              ;#5AA1: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5AA3: 30 1D
        ld      (iy+SMOKE_OFFSET_ACTIVE),0                     ;#5AA5: FD 36 00 00
        ld      (ix+ENEMY_OFFSET_TYPE),2                       ;#5AA9: DD 36 00 02
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5AAD: DD 7E 0F
        add     a,2                                            ;#5AB0: C6 02
        and     3                                              ;#5AB2: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5AB4: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5AB7: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5ABB: DD 36 02 03
        jp      ENEMY_AI_TAIL_ADV                              ;#5ABF: C3 19 5B

DRAW_ENEMY_SMOKE_NEXT:
        ; Advance IY to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5AC2: 11 10 00
        add     iy,de                                          ;#5AC5: FD 19
        djnz    DRAW_ENEMY_SMOKE_INNER                         ;#5AC7: 10 C2
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5AC9: DD 7E 00
        cp      2                                              ;#5ACC: FE 02
        jp      z,ENEMY_AI_TAIL_ADV                            ;#5ACE: CA 19 5B
        ld      a,(FRAME_TICK)                                 ;#5AD1: 3A 07 E0
        rra                                                    ;#5AD4: 1F
        jr      nc,ENEMY_AI_ADVANCE_IX                         ;#5AD5: 30 2D
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5AD7: DD 7E 0F
        and     3                                              ;#5ADA: E6 03
        ld      b,a                                            ;#5ADC: 47
        add     a,a                                            ;#5ADD: 87
        add     a,b                                            ;#5ADE: 80
        add     a,a                                            ;#5ADF: 87
        add     a,a                                            ;#5AE0: 87
        sub     c                                              ;#5AE1: 91
        jr      z,ENEMY_AI_ADVANCE_IX                          ;#5AE2: 28 20
        jr      nc,ENEMY_SMOKE_ROT_TOP                         ;#5AE4: 30 02
        add     a,30h                                          ;#5AE6: C6 30
ENEMY_SMOKE_ROT_TOP:
        ; Compute rotation delta < 18h: pick MINUS or PLUS step
        cp      18h                                            ;#5AE8: FE 18
        jr      c,ENEMY_SMOKE_ROT_PLUS                         ;#5AEA: 38 0D
        ld      a,c                                            ;#5AEC: 79
        sub     4                                              ;#5AED: D6 04
        jr      nc,ENEMY_SMOKE_ROT_MINUS_STORE                 ;#5AEF: 30 02
        ld      a,2Ch                                          ;#5AF1: 3E 2C
ENEMY_SMOKE_ROT_MINUS_STORE:
        ; Rotate enemy sprite by -4 (mod 30h), clamp at 2Ch
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5AF3: DD 77 0D
        jp      ENEMY_AI_ADVANCE_IX                            ;#5AF6: C3 04 5B

ENEMY_SMOKE_ROT_PLUS:
        ; Rotate enemy sprite by +4 (mod 30h), wrap to 0
        ld      a,c                                            ;#5AF9: 79
        add     a,4                                            ;#5AFA: C6 04
        cp      30h                                            ;#5AFC: FE 30
        jr      c,ENEMY_SMOKE_ROT_STORE                        ;#5AFE: 38 01
        xor     a                                              ;#5B00: AF
ENEMY_SMOKE_ROT_STORE:
        ; Store new rotation phase at (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5B01: DD 77 0D
ENEMY_AI_ADVANCE_IX:
        ; Advance IX by 10h to next ENEMY_CAR_TABLE entry, return to caller
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5B04: DD 7E 01
        and     a                                              ;#5B07: A7
        jr      nz,ENEMY_AI_TAIL_ADV                           ;#5B08: 20 0F
        push    ix                                             ;#5B0A: DD E5
        pop     iy                                             ;#5B0C: FD E1
ENEMY_COLLIDE_LOOP:
        ; Enemy-vs-enemy collision loop: walk subsequent entries via IY
        ld      de,10h                                         ;#5B0E: 11 10 00
        add     iy,de                                          ;#5B11: FD 19
        ld      a,(iy+ENEMY_OFFSET_TYPE)                       ;#5B13: FD 7E 00
        and     a                                              ;#5B16: A7
        jr      nz,ENEMY_COLLIDE_TEST_Y                        ;#5B17: 20 06
ENEMY_AI_TAIL_ADV:
        ; Common tail: advance IX by 10h and return
        ld      de,10h                                         ;#5B19: 11 10 00
        add     ix,de                                          ;#5B1C: DD 19
        ret                                                    ;#5B1E: C9

ENEMY_COLLIDE_TEST_Y:
        ; Test Y delta < 0Ch: rejected -> jump back to loop; accepted -> check X
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B1F: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B22: DD 6E 09
        ld      d,(iy+ENEMY_OFFSET_X_HI)                       ;#5B25: FD 56 0A
        ld      e,(iy+ENEMY_OFFSET_X)                          ;#5B28: FD 5E 09
        and     a                                              ;#5B2B: A7
        sbc     hl,de                                          ;#5B2C: ED 52
        ld      de,0Ch                                         ;#5B2E: 11 0C 00
        add     hl,de                                          ;#5B31: 19
        ld      a,h                                            ;#5B32: 7C
        and     a                                              ;#5B33: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B34: 20 D8
        ld      a,l                                            ;#5B36: 7D
        cp      19h                                            ;#5B37: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B39: 30 D3
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5B3B: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5B3E: DD 6E 0B
        ld      d,(iy+ENEMY_OFFSET_Y_HI)                       ;#5B41: FD 56 0C
        ld      e,(iy+ENEMY_OFFSET_Y)                          ;#5B44: FD 5E 0B
        and     a                                              ;#5B47: A7
        sbc     hl,de                                          ;#5B48: ED 52
        ld      de,0Ch                                         ;#5B4A: 11 0C 00
        add     hl,de                                          ;#5B4D: 19
        ld      a,h                                            ;#5B4E: 7C
        and     a                                              ;#5B4F: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B50: 20 BC
        ld      a,l                                            ;#5B52: 7D
        cp      19h                                            ;#5B53: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B55: 30 B7
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5B57: DD 7E 0F
        xor     2                                              ;#5B5A: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5B5C: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5B5F: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5B63: DD 36 02 03
        ld      a,(iy+ENEMY_OFFSET_DIR)                        ;#5B67: FD 7E 0F
        xor     2                                              ;#5B6A: EE 02
        cp      (ix+ENEMY_OFFSET_DIR)                          ;#5B6C: DD BE 0F
        jr      z,ENEMY_COLLIDE_STORE_OTHER                    ;#5B6F: 28 03
        ld      (iy+ENEMY_OFFSET_DIR),a                        ;#5B71: FD 77 0F
ENEMY_COLLIDE_STORE_OTHER:
        ; Both cars collided: also set bounce-away flags on the other car
        ld      (iy+ENEMY_OFFSET_TIMER),78h                    ;#5B74: FD 36 01 78
        ld      (iy+ENEMY_OFFSET_STATE),3                      ;#5B78: FD 36 02 03
        jp      ENEMY_COLLIDE_LOOP                             ;#5B7C: C3 0E 5B

CHECK_ENEMY_HITS_ROCK:
        ; AABB-style check (|dx|<0Ch & |dy|<0Ch) between IX (E300) and IY (E200)
        ; CHECK_ENEMY_HITS_ROCK does an AABB check between the current enemy car (IX =
        ; ENEMY_CAR_TABLE entry) and every ROCK_TABLE entry (IY). |dx| < 0Ch AND |dy| <
        ; 0Ch ⇒ hit; on hit, XOR bit 1 of (ix+0Fh) — a flag the enemy uses to reverse
        ; direction on its next AI tick.
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5B7F: DD 7E 01
        and     a                                              ;#5B82: A7
        ret     nz                                             ;#5B83: C0
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5B84: 3A 1C E0
        and     a                                              ;#5B87: A7
        ret     z                                              ;#5B88: C8
        ld      b,a                                            ;#5B89: 47
        ld      iy,ROCK_TABLE                                  ;#5B8A: FD 21 00 E2
CHECK_ROCK_LOOP_TOP:
        ; Outer djnz of CHECK_ENEMY_HITS_ROCK
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B8E: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B91: DD 6E 09
        ld      d,(iy+ROCK_OFFSET_X_HI)                        ;#5B94: FD 56 04
        ld      e,(iy+ROCK_OFFSET_X)                           ;#5B97: FD 5E 03
        and     a                                              ;#5B9A: A7
        sbc     hl,de                                          ;#5B9B: ED 52
        ld      de,0Ch                                         ;#5B9D: 11 0C 00
        add     hl,de                                          ;#5BA0: 19
        ld      a,h                                            ;#5BA1: 7C
        and     a                                              ;#5BA2: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5BA3: 20 32
        ld      a,l                                            ;#5BA5: 7D
        cp      19h                                            ;#5BA6: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BA8: 30 2D
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5BAA: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5BAD: DD 6E 0B
        ld      d,(iy+ROCK_OFFSET_Y_HI)                        ;#5BB0: FD 56 06
        ld      e,(iy+ROCK_OFFSET_Y)                           ;#5BB3: FD 5E 05
        and     a                                              ;#5BB6: A7
        sbc     hl,de                                          ;#5BB7: ED 52
        ld      de,0Ch                                         ;#5BB9: 11 0C 00
        add     hl,de                                          ;#5BBC: 19
        ld      a,h                                            ;#5BBD: 7C
        and     a                                              ;#5BBE: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5BBF: 20 16
        ld      a,l                                            ;#5BC1: 7D
        cp      19h                                            ;#5BC2: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BC4: 30 11
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5BC6: DD 7E 0F
        xor     2                                              ;#5BC9: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5BCB: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5BCE: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5BD2: DD 36 02 03
        ret                                                    ;#5BD6: C9

CHECK_ROCK_NEXT:
        ; Skip-this-rock: advance IY by 10h, djnz back to outer loop
        ld      de,10h                                         ;#5BD7: 11 10 00
        add     iy,de                                          ;#5BDA: FD 19
        djnz    CHECK_ROCK_LOOP_TOP                            ;#5BDC: 10 B0
        ret                                                    ;#5BDE: C9

APPLY_DIRECTION_TO_POS:
        ; Adjust H/L by direction A then call LOOKUP_PLAYFIELD_CELL
        ; APPLY_DIRECTION_TO_POS reads (ix+5, ix+8) as a 16-bit (H, L) position, adjusts
        ; by direction code in A: 0 = H-1 (up), 1 = H+1 (down), 2 = L-1 (left), 3 = L+1
        ; (right). Then calls LOOKUP_PLAYFIELD_CELL to fetch the cell at the new coord.
        ; Used by enemy and player movement code to "look ahead" before committing a
        ; move.
        ld      c,a                                            ;#5BDF: 4F
        ld      h,(ix+ENEMY_OFFSET_CELL_X)                     ;#5BE0: DD 66 05
        ld      l,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5BE3: DD 6E 08
        rra                                                    ;#5BE6: 1F
        jr      nc,APPLY_DIR_HORIZ                             ;#5BE7: 30 0B
        rra                                                    ;#5BE9: 1F
        jr      nc,APPLY_DIR_INC_H                             ;#5BEA: 30 04
        dec     h                                              ;#5BEC: 25
        jp      APPLY_DIR_LOOKUP                               ;#5BED: C3 FC 5B

APPLY_DIR_INC_H:
        ; APPLY_DIR direction 1 (down): inc H, then lookup
        inc     h                                              ;#5BF0: 24
        jp      APPLY_DIR_LOOKUP                               ;#5BF1: C3 FC 5B

APPLY_DIR_HORIZ:
        ; APPLY_DIR horizontal (dir 2/3): switch on dir bit
        rra                                                    ;#5BF4: 1F
        jr      c,APPLY_DIR_INC_L                              ;#5BF5: 38 04
        dec     l                                              ;#5BF7: 2D
        jp      APPLY_DIR_LOOKUP                               ;#5BF8: C3 FC 5B

APPLY_DIR_INC_L:
        ; APPLY_DIR direction 3 (right): inc L, then lookup
        inc     l                                              ;#5BFB: 2C
APPLY_DIR_LOOKUP:
        ; Common lookup: call LOOKUP_PLAYFIELD_CELL with adjusted (H, L)
        call    LOOKUP_PLAYFIELD_CELL                          ;#5BFC: CD 81 4B
        ld      a,c                                            ;#5BFF: 79
        ret                                                    ;#5C00: C9

UPDATE_SMOKE_STATE:
        ; Per-frame smoke-state update; gated by SMOKE_COOLDOWN and PLAYER_VELOCITY_X
        ; UPDATE_SMOKE_STATE runs once per frame. No-op if SMOKE_COOLDOWN is zero.
        ; Otherwise reads PLAYER_VELOCITY_X for direction bits, then iterates
        ; SMOKE_TRAIL_TABLE; for each entry not too close to the player
        ; (PLAYER_VELOCITY_Y in safe range), updates state. Tail-falls into SPAWN_SMOKE
        ; which allocates the next smoke trail puff.
        ld      a,(SMOKE_COOLDOWN)                             ;#5C01: 3A 27 E0
        and     a                                              ;#5C04: A7
        ret     z                                              ;#5C05: C8
        ld      a,(PLAYER_VELOCITY_X)                          ;#5C06: 3A 09 E0
        and     a                                              ;#5C09: A7
        jp      p,SMOKE_DIR_ABS                                ;#5C0A: F2 0F 5C
        neg                                                    ;#5C0D: ED 44
SMOKE_DIR_ABS:
        ; Take |PLAYER_VELOCITY_X| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C0F: D6 0A
        cp      5                                              ;#5C11: FE 05
        ret     nc                                             ;#5C13: D0
        ld      a,(PLAYER_VELOCITY_Y)                          ;#5C14: 3A 0B E0
        and     a                                              ;#5C17: A7
        jp      p,SMOKE_VEL_ABS                                ;#5C18: F2 1D 5C
        neg                                                    ;#5C1B: ED 44
SMOKE_VEL_ABS:
        ; Take |PLAYER_VELOCITY_Y| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C1D: D6 0A
        cp      5                                              ;#5C1F: FE 05
        ret     nc                                             ;#5C21: D0
        ld      a,(PLAYER_SCREEN_X)                            ;#5C22: 3A 23 E0
        ld      d,a                                            ;#5C25: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#5C26: 3A 24 E0
        ld      e,a                                            ;#5C29: 5F
        ; SPAWN_SMOKE (inside UPDATE_SMOKE_STATE's tail). Allocates the next
        ; SMOKE_TRAIL_TABLE entry: advance SMOKE_TRAIL_WRITE_PTR by 0x10, wrap
        ; SMOKE_TRAIL_WRITE_INDEX modulo 9. Initialize: active=1, pos=(D,E), tile=58h,
        ; attr=0, life=6Fh, etc. Decrement SMOKE_COOLDOWN and trigger SFX_TRIGGER_SMOKE
        ; (=1) for the deploy sound.
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C2A: 21 00 E4
        ld      b,9                                            ;#5C2D: 06 09
SMOKE_SCAN_LOOP_TOP:
        ; Inner djnz of SPAWN_SMOKE (scan SMOKE_TRAIL_TABLE)
        ld      a,(hl)                                         ;#5C2F: 7E
        and     a                                              ;#5C30: A7
        jr      z,SMOKE_SPAWN_NEXT                             ;#5C31: 28 12
        inc     hl                                             ;#5C33: 23
        inc     hl                                             ;#5C34: 23
        inc     hl                                             ;#5C35: 23
        ld      a,(hl)                                         ;#5C36: 7E
        sub     50h                                            ;#5C37: D6 50
        cp      10h                                            ;#5C39: FE 10
        jr      nc,SMOKE_SPAWN_NEXT                            ;#5C3B: 30 08
        inc     hl                                             ;#5C3D: 23
        inc     hl                                             ;#5C3E: 23
        ld      a,(hl)                                         ;#5C3F: 7E
        sub     67h                                            ;#5C40: D6 67
        cp      10h                                            ;#5C42: FE 10
        ret     c                                              ;#5C44: D8
SMOKE_SPAWN_NEXT:
        ; Try next smoke slot if current entry too close to player
        ld      a,l                                            ;#5C45: 7D
        and     0F0h                                           ;#5C46: E6 F0
        add     a,10h                                          ;#5C48: C6 10
        ld      l,a                                            ;#5C4A: 6F
        djnz    SMOKE_SCAN_LOOP_TOP                            ;#5C4B: 10 E2
        ld      hl,(SMOKE_TRAIL_WRITE_PTR)                     ;#5C4D: 2A 28 E0
        ld      bc,10h                                         ;#5C50: 01 10 00
        add     hl,bc                                          ;#5C53: 09
        ld      a,(SMOKE_TRAIL_WRITE_INDEX)                    ;#5C54: 3A 2A E0
        inc     a                                              ;#5C57: 3C
        cp      9                                              ;#5C58: FE 09
        jr      nz,SMOKE_ALLOC_ENTRY                           ;#5C5A: 20 04
        xor     a                                              ;#5C5C: AF
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C5D: 21 00 E4
SMOKE_ALLOC_ENTRY:
        ; Init new smoke entry: active=1, pos=(D,E), tile=58h, life=6Fh
        ld      (SMOKE_TRAIL_WRITE_PTR),hl                     ;#5C60: 22 28 E0
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#5C63: 32 2A E0
        ld      (hl),1                                         ;#5C66: 36 01
        inc     hl                                             ;#5C68: 23
        ld      (hl),d                                         ;#5C69: 72
        inc     hl                                             ;#5C6A: 23
        ld      (hl),e                                         ;#5C6B: 73
        inc     hl                                             ;#5C6C: 23
        ld      (hl),58h                                       ;#5C6D: 36 58
        inc     hl                                             ;#5C6F: 23
        ld      (hl),0                                         ;#5C70: 36 00
        inc     hl                                             ;#5C72: 23
        ld      (hl),6Fh                                       ;#5C73: 36 6F
        inc     hl                                             ;#5C75: 23
        ld      (hl),0                                         ;#5C76: 36 00
        ld      hl,SMOKE_COOLDOWN                              ;#5C78: 21 27 E0
        dec     (hl)                                           ;#5C7B: 35
        ld      a,1                                            ;#5C7C: 3E 01
        ld      (SFX_TRIGGER_SMOKE),a                          ;#5C7E: 32 50 E5
        ret                                                    ;#5C81: C9

SCROLL_SMOKE_TRAILS:
        ; Iterate SMOKE_TRAIL_TABLE (9 entries x 16 bytes): world-scroll + draw
        ; SCROLL_SMOKE_TRAILS iterates the 9-entry SMOKE_TRAIL_TABLE. Active entries
        ; have their X/Y advanced by WORLD_SCROLL_DX/DY. When the position goes off-
        ; screen (X >= 0A9h or Y >= 0E0h), the entry is deactivated. In-bounds entries
        ; are drawn as smoke sprites at the SAT_MIRROR cursor (tile 40h, color 0Fh =
        ; white smoke).
        ld      ix,SMOKE_TRAIL_TABLE                           ;#5C82: DD 21 00 E4
        ld      b,9                                            ;#5C86: 06 09
SCROLL_SMOKE_LOOP_TOP:
        ; Outer djnz of SCROLL_SMOKE_TRAILS
        ld      a,(ix+SMOKE_OFFSET_ACTIVE)                     ;#5C88: DD 7E 00
        and     a                                              ;#5C8B: A7
        jr      z,SMOKE_ADVANCE_IX                             ;#5C8C: 28 53
        ld      a,(WORLD_SCROLL_DX)                            ;#5C8E: 3A 16 E0
        ld      e,a                                            ;#5C91: 5F
        ld      d,0                                            ;#5C92: 16 00
        rla                                                    ;#5C94: 17
        jr      nc,SMOKE_APPLY_DX                              ;#5C95: 30 01
        dec     d                                              ;#5C97: 15
SMOKE_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to smoke entry X
        ld      l,(ix+SMOKE_OFFSET_X)                          ;#5C98: DD 6E 03
        ld      h,(ix+SMOKE_OFFSET_X_HI)                       ;#5C9B: DD 66 04
        add     hl,de                                          ;#5C9E: 19
        ld      (ix+SMOKE_OFFSET_X_HI),h                       ;#5C9F: DD 74 04
        ld      (ix+SMOKE_OFFSET_X),l                          ;#5CA2: DD 75 03
        ld      a,h                                            ;#5CA5: 7C
        and     a                                              ;#5CA6: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CA7: 20 40
        ld      a,l                                            ;#5CA9: 7D
        cp      0A9h                                           ;#5CAA: FE A9
        jr      nc,SMOKE_DEACTIVATE                            ;#5CAC: 30 3B
        ld      c,l                                            ;#5CAE: 4D
        ld      a,(WORLD_SCROLL_DY)                            ;#5CAF: 3A 17 E0
        ld      e,a                                            ;#5CB2: 5F
        ld      d,0                                            ;#5CB3: 16 00
        rla                                                    ;#5CB5: 17
        jr      nc,SMOKE_APPLY_DY                              ;#5CB6: 30 01
        dec     d                                              ;#5CB8: 15
SMOKE_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to smoke entry Y
        ld      l,(ix+SMOKE_OFFSET_Y)                          ;#5CB9: DD 6E 05
        ld      h,(ix+SMOKE_OFFSET_Y_HI)                       ;#5CBC: DD 66 06
        add     hl,de                                          ;#5CBF: 19
        ld      (ix+SMOKE_OFFSET_Y),l                          ;#5CC0: DD 75 05
        ld      (ix+SMOKE_OFFSET_Y_HI),h                       ;#5CC3: DD 74 06
        ld      a,h                                            ;#5CC6: 7C
        and     a                                              ;#5CC7: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CC8: 20 1F
        ld      a,l                                            ;#5CCA: 7D
        cp      0E0h                                           ;#5CCB: FE E0
        jr      nc,SMOKE_DEACTIVATE                            ;#5CCD: 30 1A
        sub     18h                                            ;#5CCF: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5CD1: 2A 14 E0
        ; emit one E400 object sprite
        ld      (hl),a                                         ;#5CD4: 77
        inc     hl                                             ;#5CD5: 23
        ld      (hl),c                                         ;#5CD6: 71
        inc     hl                                             ;#5CD7: 23
        ld      (hl),40h                                       ;#5CD8: 36 40
        inc     hl                                             ;#5CDA: 23
        ld      (hl),0Fh                                       ;#5CDB: 36 0F
        inc     hl                                             ;#5CDD: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5CDE: 22 14 E0
SMOKE_ADVANCE_IX:
        ; Advance IX by 10h to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5CE1: 11 10 00
        add     ix,de                                          ;#5CE4: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CE6: 10 A0
        ret                                                    ;#5CE8: C9

SMOKE_DEACTIVATE:
        ; Off-screen / hit smoke: zero entry, advance IX, djnz back
        ld      (ix+SMOKE_OFFSET_ACTIVE),0                     ;#5CE9: DD 36 00 00
        ld      de,10h                                         ;#5CED: 11 10 00
        add     ix,de                                          ;#5CF0: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CF2: 10 94
        ret                                                    ;#5CF4: C9

PADDING_TO_8000:
        ; 779 bytes of 0FFh padding ending the first 8KB before the 0x8000 phase boundary
        ds      779, 0FFh                                      ;#5CF5

        phase   8000h
SPRITE_CAR:
        ; Player car sprite (16x16); stored pre-transpose, see TRANSPOSE_TILE_BLOCKS
        dh      "0103777F7703030206EEEEFEEFE70202"             ;#8000: 01 03 77 7F 77 03 03 02 06 EE EE FE EF E7 02 02
        dh      "80C0EEFEEEC0C0406077777FF7E74040"             ;#8010: 80 C0 EE FE EE C0 C0 40 60 77 77 7F F7 E7 40 40

SPRITE_CAR_ROTATED_30:
        ; Player car rotated 30 degrees (pre-transpose)
        dh      "060E0F0C007173F2FEFC181C1F171404"             ;#8020: 06 0E 0F 0C 00 71 73 F2 FE FC 18 1C 1F 17 14 04
        dh      "0070F8F8FFFFFF662060C0F8F8F87070"             ;#8030: 00 70 F8 F8 FF FF FF 66 20 60 C0 F8 F8 F8 70 70

SPRITE_CAR_ROTATED_45:
        ; Player car rotated 45 degrees (pre-transpose)
        dh      "00000038F8FBFE3C3031FB1F7F030303"             ;#8040: 00 00 00 38 F8 FB FE 3C 30 31 FB 1F 7F 03 03 03
        dh      "70F0F07C7EFEFE7C64C70F0EE0E0E080"             ;#8050: 70 F0 F0 7C 7E FE FE 7C 64 C7 0F 0E E0 E0 E0 80

SPRITE_FLAG:
        ; Checkpoint flag sprite (16x16); base of the 3180h sprite upload
        dh      "00000000000000000000010100000000"             ;#8060: 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#8070: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_L_FLAG:
        ; 'L' flag sprite
        dh      "006060606060607E0000010100000000"             ;#8080: 00 60 60 60 60 60 60 7E 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#8090: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_S_FLAG:
        ; Special 'S' flag sprite (doubles bonus values)
        dh      "003C66603C06663C0000010100000000"             ;#80A0: 00 3C 66 60 3C 06 66 3C 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#80B0: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_ROCK:
        ; Rock obstacle sprite
        dh      "00104161033337071F3F3F7F7F7F3F0F"             ;#80C0: 00 10 41 61 03 33 37 07 1F 3F 3F 7F 7F 7F 3F 0F
        dh      "00E0F0F8FCFCFCFCFEFEFEFFFFFFFFC6"             ;#80D0: 00 E0 F0 F8 FC FC FC FC FE FE FE FF FF FF FF C6

SPRITE_SMOKE:
        ; Smoke-screen sprite
        dh      "00193F3F7F7F7F7F3F7F7F3F3F1F0E00"             ;#80E0: 00 19 3F 3F 7F 7F 7F 7F 3F 7F 7F 3F 3F 1F 0E 00
        dh      "0014BEFFFEFEFCFCFEFFFFFFFEBC1800"             ;#80F0: 00 14 BE FF FE FE FC FC FE FF FF FF FE BC 18 00

SPRITE_BANG:
        ; Crash 'BANG' explosion sprite
        dh      "9945B310C6A9A9CFA9A9C900B7654D99"             ;#8100: 99 45 B3 10 C6 A9 A9 CF A9 A9 C9 00 B7 65 4D 99
        dh      "275C91005354747575555700B5565249"             ;#8110: 27 5C 91 00 53 54 74 75 75 55 57 00 B5 56 52 49

SPRITE_BONUS_100:
        ; Bonus 100 score popup sprite
        dh      "00113212121212390000000000000000"             ;#8120: 00 11 32 12 12 12 12 39 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#8130: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_100X2:
        ; Bonus 100 doubled (special-flag) popup sprite
        dh      "00113212121212390000110A040A1100"             ;#8140: 00 11 32 12 12 12 12 39 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8150: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_200:
        ; Bonus 200 score popup sprite
        dh      "00718A8A122242F90000000000000000"             ;#8160: 00 71 8A 8A 12 22 42 F9 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#8170: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_200X2:
        ; Bonus 200 doubled (special-flag) popup sprite
        dh      "00718A8A122242F90000110A040A1100"             ;#8180: 00 71 8A 8A 12 22 42 F9 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8190: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_300:
        ; Bonus 300 score popup sprite
        dh      "00718A0A320A8A710000000000000000"             ;#81A0: 00 71 8A 0A 32 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#81B0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_300X2:
        ; Bonus 300 doubled (special-flag) popup sprite
        dh      "00718A0A320A8A710000110A040A1100"             ;#81C0: 00 71 8A 0A 32 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#81D0: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_400:
        ; Bonus 400 score popup sprite
        dh      "0011325292FA12110000000000000000"             ;#81E0: 00 11 32 52 92 FA 12 11 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#81F0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_400X2:
        ; Bonus 400 doubled (special-flag) popup sprite
        dh      "0011325292FA12110000110A040A1100"             ;#8200: 00 11 32 52 92 FA 12 11 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8210: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_500:
        ; Bonus 500 score popup sprite
        dh      "00F982F20A0A8A710000000000000000"             ;#8220: 00 F9 82 F2 0A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#8230: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_500X2:
        ; Bonus 500 doubled (special-flag) popup sprite
        dh      "00F982F20A0A8A710000110A040A1100"             ;#8240: 00 F9 82 F2 0A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8250: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_600:
        ; Bonus 600 score popup sprite
        dh      "00718A82F28A8A710000000000000000"             ;#8260: 00 71 8A 82 F2 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#8270: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_600X2:
        ; Bonus 600 doubled (special-flag) popup sprite
        dh      "00718A82F28A8A710000110A040A1100"             ;#8280: 00 71 8A 82 F2 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8290: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_700:
        ; Bonus 700 score popup sprite
        dh      "00F90A0A122222210000000000000000"             ;#82A0: 00 F9 0A 0A 12 22 22 21 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#82B0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_700X2:
        ; Bonus 700 doubled (special-flag) popup sprite
        dh      "00F90A0A122222210000110A040A1100"             ;#82C0: 00 F9 0A 0A 12 22 22 21 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#82D0: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_800:
        ; Bonus 800 score popup sprite
        dh      "00718A8A728A8A710000000000000000"             ;#82E0: 00 71 8A 8A 72 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#82F0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_800X2:
        ; Bonus 800 doubled (special-flag) popup sprite
        dh      "00718A8A728A8A710000110A040A1100"             ;#8300: 00 71 8A 8A 72 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8310: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_900:
        ; Bonus 900 score popup sprite
        dh      "00718A8A7A0A8A710000000000000000"             ;#8320: 00 71 8A 8A 7A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#8330: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_900X2:
        ; Bonus 900 doubled (special-flag) popup sprite
        dh      "00718A8A7A0A8A710000110A040A1100"             ;#8340: 00 71 8A 8A 7A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#8350: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_1000:
        ; Bonus 1000 score popup sprite
        dh      "0098A5A5A5A5A5980000000000000000"             ;#8360: 00 98 A5 A5 A5 A5 A5 98 00 00 00 00 00 00 00 00
        dh      "00C62929292929C60000000000000000"             ;#8370: 00 C6 29 29 29 29 29 C6 00 00 00 00 00 00 00 00

SPRITE_BONUS_1000X2:
        ; Bonus 1000 doubled (special-flag) popup sprite
        dh      "0098A5A5A5A5A5980000110A040A1100"             ;#8380: 00 98 A5 A5 A5 A5 A5 98 00 00 11 0A 04 0A 11 00
        dh      "00C62929292929C6003844440810207C"             ;#8390: 00 C6 29 29 29 29 29 C6 00 38 44 44 08 10 20 7C

SPRITE_GAMEOVER_LEFT:
        ; GAME OVER text, left half
        dh      "1F30606763331F003E63636363633E00"             ;#83A0: 1F 30 60 67 63 33 1F 00 3E 63 63 63 63 63 3E 00
        dh      "1C3663637F636300636363773E1C0800"             ;#83B0: 1C 36 63 63 7F 63 63 00 63 63 63 77 3E 1C 08 00

SPRITE_GAMEOVER_RIGHT:
        ; GAME OVER text, right half
        dh      "63777F7F6B6363003F30303E30303F00"             ;#83C0: 63 77 7F 7F 6B 63 63 00 3F 30 30 3E 30 30 3F 00
        dh      "3F30303E30303F007E6363677C6E6700"             ;#83D0: 3F 30 30 3E 30 30 3F 00 7E 63 63 67 7C 6E 67 00

TILE_PATTERN_HEX_DIGITS:
        ; Hex digit font 0-F (16x 8x8); base of the boot pattern-table upload
        dh      "1C26636363321C000C1C0C0C0C0C3F00"             ;#83E0: 1C 26 63 63 63 32 1C 00 0C 1C 0C 0C 0C 0C 3F 00
        dh      "3E63071E3C707F003F060C1703633E00"             ;#83F0: 3E 63 07 1E 3C 70 7F 00 3F 06 0C 17 03 63 3E 00
        dh      "0E1E36667F0606007E607E0303633E00"             ;#8400: 0E 1E 36 66 7F 06 06 00 7E 60 7E 03 03 63 3E 00
        dh      "1E30607E63633E007F62060C18181800"             ;#8410: 1E 30 60 7E 63 63 3E 00 7F 62 06 0C 18 18 18 00
        dh      "3C62723C4F433E003E63633F03063C00"             ;#8420: 3C 62 72 3C 4F 43 3E 00 3E 63 63 3F 03 06 3C 00
        dh      "1C3663637F6363007E63637E63637E00"             ;#8430: 1C 36 63 63 7F 63 63 00 7E 63 63 7E 63 63 7E 00
        dh      "1E33606060331E007C66636363667C00"             ;#8440: 1E 33 60 60 60 33 1E 00 7C 66 63 63 63 66 7C 00
        dh      "3F30303E30303F007F60607E60606000"             ;#8450: 3F 30 30 3E 30 30 3F 00 7F 60 60 7E 60 60 60 00

TILE_PATTERN_NAMCOT_LOGO:
        ; Namcot publisher logo, 8x 8x8 tiles
        dh      "7F7F60606060606087C7C0C7CFCCCFC7"             ;#8460: 7F 7F 60 60 60 60 60 60 87 C7 C0 C7 CF CC CF C7
        dh      "F1F939F9F939F9F9FFFF999999999999"             ;#8470: F1 F9 39 F9 F9 39 F9 F9 FF FF 99 99 99 99 99 99
        dh      "0F9F989898989F8FE3E706060606E7E3"             ;#8480: 0F 9F 98 98 98 98 9F 8F E3 E7 06 06 06 06 E7 E3
        dh      "F8FC0C0C0C0CFCF8FFFF181818181818"             ;#8490: F8 FC 0C 0C 0C 0C FC F8 FF FF 18 18 18 18 18 18

TILE_PATTERN_CHAR_FONT:
        ; Uppercase font tiles: A-Z © . − (32x 8x8); LDIR'd 3x to E100-E3FF
        dh      "00000000000000001C3663637F636300"             ;#84A0: 00 00 00 00 00 00 00 00 1C 36 63 63 7F 63 63 00
        dh      "7E63637E63637E001E33606060331E00"             ;#84B0: 7E 63 63 7E 63 63 7E 00 1E 33 60 60 60 33 1E 00
        dh      "7C66636363667C003F30303E30303F00"             ;#84C0: 7C 66 63 63 63 66 7C 00 3F 30 30 3E 30 30 3F 00
        dh      "7F60607E606060001F30606763331F00"             ;#84D0: 7F 60 60 7E 60 60 60 00 1F 30 60 67 63 33 1F 00
        dh      "6363637F636363003F0C0C0C0C0C3F00"             ;#84E0: 63 63 63 7F 63 63 63 00 3F 0C 0C 0C 0C 0C 3F 00
        dh      "0303030303633E0063666C787C6E6700"             ;#84F0: 03 03 03 03 03 63 3E 00 63 66 6C 78 7C 6E 67 00
        dh      "3030303030303F0063777F7F6B636300"             ;#8500: 30 30 30 30 30 30 3F 00 63 77 7F 7F 6B 63 63 00
        dh      "63737B7F6F6763003E63636363633E00"             ;#8510: 63 73 7B 7F 6F 67 63 00 3E 63 63 63 63 63 3E 00
        dh      "7E6363637E6060003E6363636F663D00"             ;#8520: 7E 63 63 63 7E 60 60 00 3E 63 63 63 6F 66 3D 00
        dh      "7E6363677C6E67003C66603E03633E00"             ;#8530: 7E 63 63 67 7C 6E 67 00 3C 66 60 3E 03 63 3E 00
        dh      "3F0C0C0C0C0C0C006363636363633E00"             ;#8540: 3F 0C 0C 0C 0C 0C 0C 00 63 63 63 63 63 63 3E 00
        dh      "636363773E1C080063636B7F7F776300"             ;#8550: 63 63 63 77 3E 1C 08 00 63 63 6B 7F 7F 77 63 00
        dh      "63773E1C3E7763003333331E0C0C0C00"             ;#8560: 63 77 3E 1C 3E 77 63 00 33 33 33 1E 0C 0C 0C 00
        dh      "7F070E1C38707F003C4299A1A199423C"             ;#8570: 7F 07 0E 1C 38 70 7F 00 3C 42 99 A1 A1 99 42 3C
        dh      "00000000000000000000000000181800"             ;#8580: 00 00 00 00 00 00 00 00 00 00 00 00 00 18 18 00
        dh      "00000000000000000000007E00000000"             ;#8590: 00 00 00 00 00 00 00 00 00 00 00 7E 00 00 00 00

PATTERN_RALLYX_LOGO:
        ; Rally-X logo char patterns (88x 8x8, chars 80h+); LDIRVM'd to VRAM 0C00h/1C00h
        dh      "3F6040C080808080FF00000000000000"             ;#85A0: 3F 60 40 C0 80 80 80 80 FF 00 00 00 00 00 00 00
        dh      "FF0100000000000000C0406020301018"             ;#85B0: FF 01 00 00 00 00 00 00 00 C0 40 60 20 30 10 18
        dh      "00000000000000000F1830206040C080"             ;#85C0: 00 00 00 00 00 00 00 00 0F 18 30 20 60 40 C0 80
        dh      "C0701018080C04060001010302020202"             ;#85D0: C0 70 10 18 08 0C 04 06 00 01 01 03 02 02 02 02
        dh      "80808080808080801E1F1E0000000000"             ;#85E0: 80 80 80 80 80 80 80 80 1E 1F 1E 00 00 00 00 00
        dh      "1C1C1E1F1F1F3F7F01010302028684C4"             ;#85F0: 1C 1C 1E 1F 1F 1F 3F 7F 01 01 03 02 02 86 84 C4
        dh      "820707070F0F1F000303030181818000"             ;#8600: 82 07 07 07 0F 0F 1F 00 03 03 03 01 81 81 80 00
        dh      "020282C2C2E2F2F2000000081C1C1C1C"             ;#8610: 02 02 82 C2 C2 E2 F2 F2 00 00 00 08 1C 1C 1C 1C
        dh      "0301000000000000FFFF7F3F3F3F3F3F"             ;#8620: 03 01 00 00 00 00 00 00 FF FF 7F 3F 3F 3F 3F 3F
        dh      "CCE8F8F0F0E0E0C0FA7A7E7E7E7E3E3E"             ;#8630: CC E8 F8 F0 F0 E0 E0 C0 FA 7A 7E 7E 7E 7E 3E 3E
        dh      "1C1C1C1C1C1C1C1C3F3F3F3F3F3E3E3E"             ;#8640: 1C 1C 1C 1C 1C 1C 1C 1C 3F 3F 3F 3F 3F 3E 3E 3E
        dh      "C0808000000000003E3E1E1E1E1E0E0E"             ;#8650: C0 80 80 00 00 00 00 00 3E 3E 1E 1E 1E 1E 0E 0E
        dh      "8080808080C040601C1C1C1C1C1C1C3E"             ;#8660: 80 80 80 80 80 C0 40 60 1C 1C 1C 1C 1C 1C 1C 3E
        dh      "3C3C38383838387C0E0E0E0707070F1F"             ;#8670: 3C 3C 38 38 38 38 38 7C 0E 0E 0E 07 07 07 0F 1F
        dh      "3F3F1F1F0F070301FFFFFFFFFFFFFFFF"             ;#8680: 3F 3F 1F 1F 0F 07 03 01 FF FF FF FF FF FF FF FF
        dh      "FFFF7F3F1F000000FFFFFFFFFF000000"             ;#8690: FF FF 7F 3F 1F 00 00 00 FF FF FF FF FF 00 00 00
        dh      "FF80000000000000C06030180C0C0E0F"             ;#86A0: FF 80 00 00 00 00 00 00 C0 60 30 18 0C 0C 0E 0F
        dh      "F018080C060203031F30303038181C0C"             ;#86B0: F0 18 08 0C 06 02 03 03 1F 30 30 30 38 18 1C 0C
        dh      "F80C0603010000000000000080C04161"             ;#86C0: F8 0C 06 03 01 00 00 00 00 00 00 00 80 C0 41 61
        dh      "0F0F0F0F0F0703000080C0C0E0E0F010"             ;#86D0: 0F 0F 0F 0F 0F 07 03 00 00 80 C0 C0 E0 E0 F0 10
        dh      "03030303030100008E87C7C3E1F1F808"             ;#86E0: 03 03 03 03 03 01 00 00 8E 87 C7 C3 E1 F1 F8 08
        dh      "00000080C0C0E0F033121E0C00000000"             ;#86F0: 00 00 00 80 C0 C0 E0 F0 33 12 1E 0C 00 00 00 00
        dh      "180C0E0E0F0F0F0F0C06070707070707"             ;#8700: 18 0C 0E 0E 0F 0F 0F 0F 0C 06 07 07 07 07 07 07
        dh      "783C1C0C84C4E4F40F0F0F0F0F0F0F0F"             ;#8710: 78 3C 1C 0C 84 C4 E4 F4 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0707070707070707F4FCFCFCFCFCFCFC"             ;#8720: 07 07 07 07 07 07 07 07 F4 FC FC FC FC FC FC FC
        dh      "00000000000080C00F0F0F0F0F0F0F1F"             ;#8730: 00 00 00 00 00 00 80 C0 0F 0F 0F 0F 0F 0F 0F 1F
        dh      "808080C0C0C0E0F0070707070707070F"             ;#8740: 80 80 80 C0 C0 C0 E0 F0 07 07 07 07 07 07 07 0F
        dh      "FCFCFCFCFCFCFCFE0000000000000001"             ;#8750: FC FC FC FC FC FC FC FE 00 00 00 00 00 00 00 01
        dh      "FFFFF7F7F7F3F3F1F1F0F0F0F0000000"             ;#8760: FF FF F7 F7 F7 F3 F3 F1 F1 F0 F0 F0 F0 00 00 00
        dh      "FFFFFF7F7F0000000F19103061C18307"             ;#8770: FF FF FF 7F 7F 00 00 00 0F 19 10 30 61 C1 83 07
        dh      "008080E0E0F0F0F80306060202020301"             ;#8780: 00 80 80 E0 E0 F0 F0 F8 03 06 06 02 02 02 03 01
        dh      "F80C06020301010000010306040C98F0"             ;#8790: F8 0C 06 02 03 01 01 00 00 01 03 06 04 0C 98 F0
        dh      "F8880C0C0C1C3C3C070F1F1F3F7F7EFE"             ;#87A0: F8 88 0C 0C 0C 1C 3C 3C 07 0F 1F 1F 3F 7F 7E FE
        dh      "F8FCFCFF80000000010101E03018080C"             ;#87B0: F8 FC FC FF 80 00 00 00 01 01 01 E0 30 18 08 0C
        dh      "8080C0E0E0E0F0786000000101030307"             ;#87C0: 80 80 C0 E0 E0 E0 F0 78 60 00 00 01 01 03 03 07
        dh      "7C7CFCF8F8F0F0E0FEFEFFFFFFFFFFFE"             ;#87D0: 7C 7C FC F8 F8 F0 F0 E0 FE FE FF FF FF FF FF FE
        dh      "000000FFFF7F3F1F0C0E1EFEFEFEFCF8"             ;#87E0: 00 00 00 FF FF 7F 3F 1F 0C 0E 1E FE FE FE FC F8
        dh      "78707030202060400303010101000000"             ;#87F0: 78 70 70 30 20 20 60 40 03 03 01 01 01 00 00 00
        dh      "E0C0C080808080C0FEFEFEFEFEFEFEFE"             ;#8800: E0 C0 C0 80 80 80 80 C0 FE FE FE FE FE FE FE FE
        dh      "0000010103020604C080800000000000"             ;#8810: 00 00 01 01 03 02 06 04 C0 80 80 00 00 00 00 00
        dh      "4060203018080C060C18103060602030"             ;#8820: 40 60 20 30 18 08 0C 06 0C 18 10 30 60 60 20 30
        dh      "0000000001010307000040E0E0F0F8FC"             ;#8830: 00 00 00 00 01 01 03 07 00 00 40 E0 E0 F0 F8 FC
        dh      "02030101010101011F1F1F0F0F070707"             ;#8840: 02 03 01 01 01 01 01 01 1F 1F 1F 0F 0F 07 07 07
        dh      "FEFEFEFEFE0000000303010100000000"             ;#8850: FE FE FE FE FE 00 00 00 03 03 01 01 00 00 00 00

LOAD_PLAYFIELD_GFX:
        ; Fill name table, upload status/digit patterns, init both VRAM banks
        ; LOAD_PLAYFIELD_GFX uploads the HUD-and-text static graphics: tile patterns for
        ; chars 80h-FFh (PATTERN_RALLYX_LOGO → VRAM 0C00h + bank-B 1C00h), the HUD row
        ; tile-mapping (TILES_RALLYX_LOGO → 04A0h), the SCORE/HI_SCORE labels, digit-row
        ; templates, and the NAMCO copyright text. Also unpacks the initial scores
        ; (HIGH_SCORE_BCD via UNPACK_BCD_DIGITS).
        LOAD_VRAM_ADDRESS hl, 400h                             ;#8860: 21 00 04
        ld      bc,300h                                        ;#8863: 01 00 03
        ld      a,40h                                          ;#8866: 3E 40
        call    BIOS_FILVRM                                    ;#8868: CD 56 00
        xor     a                                              ;#886B: AF
        ld      (NAME_BANK_FLAG),a                             ;#886C: 32 0E E0
        LOAD_VRAM_ADDRESS hl, 790h                             ;#886F: 21 90 07
        ld      bc,10h                                         ;#8872: 01 10 00
        ld      a,50h                                          ;#8875: 3E 50
        call    BIOS_FILVRM                                    ;#8877: CD 56 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#887A: 21 A0 85
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#887D: 11 00 0C
        ld      bc,400h                                        ;#8880: 01 00 04
        call    BIOS_LDIRVM                                    ;#8883: CD 5C 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#8886: 21 A0 85
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#8889: 11 00 1C
        ld      bc,400h                                        ;#888C: 01 00 04
        call    BIOS_LDIRVM                                    ;#888F: CD 5C 00
        ld      hl,TILES_RALLYX_LOGO                           ;#8892: 21 50 89
        LOAD_VRAM_ADDRESS de, 4A0h                             ;#8895: 11 A0 04
        ld      bc,0E0h                                        ;#8898: 01 E0 00
        call    BIOS_LDIRVM                                    ;#889B: CD 5C 00
        ld      hl,PLAYFIELD_NAMETABLE_DATA                    ;#889E: 21 FE 88
        LOAD_VRAM_ADDRESS de, 406h                             ;#88A1: 11 06 04
        ld      bc,13h                                         ;#88A4: 01 13 00
        call    BIOS_LDIRVM                                    ;#88A7: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#88AA: 21 31 E0
        call    UNPACK_BCD_DIGITS                              ;#88AD: CD B0 8A
        ld      hl,DIGIT_TILE_BUFFER                           ;#88B0: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 423h                             ;#88B3: 11 23 04
        ld      bc,8                                           ;#88B6: 01 08 00
        call    BIOS_LDIRVM                                    ;#88B9: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#88BC: 21 01 E0
        call    UNPACK_BCD_DIGITS                              ;#88BF: CD B0 8A
        ld      hl,DIGIT_TILE_BUFFER                           ;#88C2: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 430h                             ;#88C5: 11 30 04
        ld      bc,8                                           ;#88C8: 01 08 00
        call    BIOS_LDIRVM                                    ;#88CB: CD 5C 00
        ld      hl,DEFAULT_SCORE_VALUES                        ;#88CE: 21 11 89
        LOAD_VRAM_ADDRESS de, 5C8h                             ;#88D1: 11 C8 05
        ld      bc,0Eh                                         ;#88D4: 01 0E 00
        call    BIOS_LDIRVM                                    ;#88D7: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_10_17                        ;#88DA: 21 1F 89
        LOAD_VRAM_ADDRESS de, 62Bh                             ;#88DD: 11 2B 06
        ld      bc,8                                           ;#88E0: 01 08 00
        call    BIOS_LDIRVM                                    ;#88E3: CD 5C 00
        ld      hl,TEXT_NAMCO_LTD                              ;#88E6: 21 27 89
        LOAD_VRAM_ADDRESS de, 685h                             ;#88E9: 11 85 06
        ld      bc,16h                                         ;#88EC: 01 16 00
        call    BIOS_LDIRVM                                    ;#88EF: CD 5C 00
        ld      hl,TEXT_RIGHTS_RESERVED                        ;#88F2: 21 3D 89
        LOAD_VRAM_ADDRESS de, 6C6h                             ;#88F5: 11 C6 06
        ld      bc,13h                                         ;#88F8: 01 13 00
        jp      BIOS_LDIRVM                                    ;#88FB: C3 5C 00

PLAYFIELD_NAMETABLE_DATA:
SCORE_HI_SCORE_LABELS:
        ; 19-byte "score      hi" + "score" label row LDIRVM'd to VRAM 0406h
        db      "score      hi", 7Fh, "score"                  ;#88FE: 73 63 6F 72 65 20 20 20 20 20 20 68 69 7F 73 63 6F 72 65

DEFAULT_SCORE_VALUES:
        ; 14-byte initial-displayed score digits LDIRVM'd to VRAM 05C8h
        dh      "30353328203330212325202B2539"                 ;#8911: 30 35 33 28 20 33 30 21 23 25 20 2B 25 39

DIGIT_TEMPLATE_10_17:
        ; 8 tile codes (10h..17h) LDIRVM'd to VRAM 062Bh as digit slot template
        dh      "1011121314151617"                             ;#891F: 10 11 12 13 14 15 16 17

TEXT_NAMCO_LTD:
        ; 22-byte "[ ... NAMCO LTD]" decoration + text LDIRVM'd to VRAM 0685h
        db      "[ ", 1, 9, 8, 0, " ", 1, 9, 8, 4, " NAMCO LTD]"  ;#8927: 5B 20 01 09 08 00 20 01 09 08 04 20 4E 41 4D 43 4F 20 4C 54 44 5D

TEXT_RIGHTS_RESERVED:
        ; 19-byte "ALL RIGHTS RESERVED" string LDIRVM'd to VRAM 06C6h
        db      "ALL RIGHTS RESERVED"                          ;#893D: 41 4C 4C 20 52 49 47 48 54 53 20 52 45 53 45 52 56 45 44

TILES_RALLYX_LOGO:
        ; Rally-X logo name-table layout (32x7 tile codes 80h-D7h); LDIRVM'd to VRAM 04A0h
        dh      "20202020208081828384858687A0A184"             ;#8950: 20 20 20 20 20 80 81 82 83 84 85 86 87 A0 A1 84
        dh      "80A2A3A4A5BBBCBDBEBFC02020202020"             ;#8960: 80 A2 A3 A4 A5 BB BC BD BE BF C0 20 20 20 20 20
        dh      "20202020208889848A8B8C8D8E84A6A7"             ;#8970: 20 20 20 20 20 88 89 84 8A 8B 8C 8D 8E 84 A6 A7
        dh      "88A8A9AAABC1C2C3C4C5C62020202020"             ;#8980: 88 A8 A9 AA AB C1 C2 C3 C4 C5 C6 20 20 20 20 20
        dh      "2020202020888F9091928484938484AC"             ;#8990: 20 20 20 20 20 88 8F 90 91 92 84 84 93 84 84 AC
        dh      "8884ADAE84C7C8C9CACBCC2020202020"             ;#89A0: 88 84 AD AE 84 C7 C8 C9 CA CB CC 20 20 20 20 20
        dh      "202020202088948495968484978484AF"             ;#89B0: 20 20 20 20 20 88 94 84 95 96 84 84 97 84 84 AF
        dh      "8884B0B184CD84CECF84D02020202020"             ;#89C0: 88 84 B0 B1 84 CD 84 CE CF 84 D0 20 20 20 20 20
        dh      "20202020209899849A8484849BB284B3"             ;#89D0: 20 20 20 20 20 98 99 84 9A 84 84 84 9B B2 84 B3
        dh      "B484B5B6B7CD84D1D2D3D42020202020"             ;#89E0: B4 84 B5 B6 B7 CD 84 D1 D2 D3 D4 20 20 20 20 20
        dh      "20202020209C9D9D9D9D9D9D9D9D9D9D"             ;#89F0: 20 20 20 20 20 9C 9D 9D 9D 9D 9D 9D 9D 9D 9D 9D
        dh      "9D9D9DB89DCD84D59D9D9D2020202020"             ;#8A00: 9D 9D 9D B8 9D CD 84 D5 9D 9D 9D 20 20 20 20 20
        dh      "2020202020849E9F9F9F9F9F9F9F9F9F"             ;#8A10: 20 20 20 20 20 84 9E 9F 9F 9F 9F 9F 9F 9F 9F 9F
        dh      "9F9F9FB9BAD684D79F9F9F2020202020"             ;#8A20: 9F 9F 9F B9 BA D6 84 D7 9F 9F 9F 20 20 20 20 20

FLASH_AND_UPDATE_SCORE_HUD:
        ; Blink the SCORE label every 8 frames + redraw score digits each frame
        ; FLASH_AND_UPDATE_SCORE_HUD. Like UPDATE_SCORE_HUD but adds a visibility flash:
        ; when FRAME_TICK & 8, the SCORE label is replaced with spaces (FILVRM with
        ; value 20h) to make it blink. Otherwise it redraws normally. Used during
        ; attract mode or "1UP/2UP" highlighting.
        ld      hl,SCORE_LABEL                                 ;#8A30: 21 52 8A
        ld      de,457h                                        ;#8A33: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#8A36: 3A 0E E0
        and     a                                              ;#8A39: A7
        jr      z,FLASH_SCORE_LDIRVM_OR_FILL                   ;#8A3A: 28 03
        ld      de,1457h                                       ;#8A3C: 11 57 14
FLASH_SCORE_LDIRVM_OR_FILL:
        ; Branch: if FRAME_TICK & 8 then FILVRM blanks, else LDIRVM the label
        push    de                                             ;#8A3F: D5
        ld      bc,5                                           ;#8A40: 01 05 00
        ld      a,(FRAME_TICK)                                 ;#8A43: 3A 07 E0
        and     8                                              ;#8A46: E6 08
        jr      z,UPDATE_SCORE_HUD_LDIRVM_LABEL                ;#8A48: 28 28
        ex      de,hl                                          ;#8A4A: EB
        ld      a,20h                                          ;#8A4B: 3E 20
        call    BIOS_FILVRM                                    ;#8A4D: CD 56 00
        jr      UPDATE_SCORE_HUD_AFTER_LABEL                   ;#8A50: 18 23

SCORE_LABEL:
        ; "SCORE" HUD label (5 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "SCORE"                                        ;#8A52: 53 43 4F 52 45

HI_SCORE_LABEL:
        ; "HI_SCORE" HUD label (8 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "HI_SCORE"                                     ;#8A57: 48 49 5F 53 43 4F 52 45

UPDATE_SCORE_HUD:
        ; Draw SCORE label and BCD-unpacked SCORE_BCD digits into the HUD name-table row
        ; UPDATE_SCORE_HUD redraws the score row each frame. LDIRVM the "SCORE" /
        ; "HI_SCORE" labels (SCORE_LABEL/HI_SCORE_LABEL), then UNPACK_BCD_DIGITS on
        ; SCORE_BCD (3 bytes BCD = 6 digits, leading-zero suppressed) and LDIRVM the
        ; digit row to the score VRAM position. Does the same for HIGH_SCORE_BCD.
        ld      hl,SCORE_LABEL                                 ;#8A5F: 21 52 8A
        ld      de,457h                                        ;#8A62: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#8A65: 3A 0E E0
        and     a                                              ;#8A68: A7
        jr      z,UPDATE_SCORE_HUD_PUSH_DE                     ;#8A69: 28 03
        LOAD_VRAM_ADDRESS de, 1457h                            ;#8A6B: 11 57 14
UPDATE_SCORE_HUD_PUSH_DE:
        ; Save DE (VRAM dest of SCORE row) for re-use across LDIRVM calls
        push    de                                             ;#8A6E: D5
        ld      bc,5                                           ;#8A6F: 01 05 00
UPDATE_SCORE_HUD_LDIRVM_LABEL:
        ; LDIRVM the SCORE label string
        call    BIOS_LDIRVM                                    ;#8A72: CD 5C 00
UPDATE_SCORE_HUD_AFTER_LABEL:
        ; After SCORE label: restore DE, set up HI_SCORE position via DE - 40h
        pop     de                                             ;#8A75: D1
        push    de                                             ;#8A76: D5
        ld      hl,-40h                                        ;#8A77: 21 C0 FF
        add     hl,de                                          ;#8A7A: 19
        ex      de,hl                                          ;#8A7B: EB
        ld      hl,HI_SCORE_LABEL                              ;#8A7C: 21 57 8A
        ld      bc,8                                           ;#8A7F: 01 08 00
        call    BIOS_LDIRVM                                    ;#8A82: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#8A85: 21 31 E0
        call    UNPACK_BCD_DIGITS                              ;#8A88: CD B0 8A
        pop     de                                             ;#8A8B: D1
        push    de                                             ;#8A8C: D5
        ld      hl,20h                                         ;#8A8D: 21 20 00
        add     hl,de                                          ;#8A90: 19
        ex      de,hl                                          ;#8A91: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#8A92: 21 F0 E1
        ld      bc,8                                           ;#8A95: 01 08 00
        call    BIOS_LDIRVM                                    ;#8A98: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#8A9B: 21 01 E0
        call    UNPACK_BCD_DIGITS                              ;#8A9E: CD B0 8A
        pop     de                                             ;#8AA1: D1
        ld      hl,-20h                                        ;#8AA2: 21 E0 FF
        add     hl,de                                          ;#8AA5: 19
        ex      de,hl                                          ;#8AA6: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#8AA7: 21 F0 E1
        ld      bc,8                                           ;#8AAA: 01 08 00
        jp      BIOS_LDIRVM                                    ;#8AAD: C3 5C 00

UNPACK_BCD_DIGITS:
        ; Decode BCD bytes at HL into 8 tile indices at DIGIT_TILE_BUFFER
        ; UNPACK_BCD_DIGITS reads BCD bytes at HL and writes 8 tile indices at
        ; DIGIT_TILE_BUFFER. Each BCD nibble becomes a tile in the range 0..9. Leading
        ; zeros are suppressed (tile 40h = blank). The output is then LDIRVM'd to a
        ; digit row in VRAM by callers.
        ld      de,DIGIT_TILE_BUFFER_END                       ;#8AB0: 11 F8 E1
        ld      b,8                                            ;#8AB3: 06 08
        ld      a,40h                                          ;#8AB5: 3E 40
UNPACK_BCD_CLEAR_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (init blanks)
        dec     de                                             ;#8AB7: 1B
        ld      (de),a                                         ;#8AB8: 12
        djnz    UNPACK_BCD_CLEAR_LOOP                          ;#8AB9: 10 FC
        ld      b,3                                            ;#8ABB: 06 03
UNPACK_BCD_SKIP_LZ_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (skip leading zero bytes)
        ld      a,(hl)                                         ;#8ABD: 7E
        and     a                                              ;#8ABE: A7
        jr      nz,UNPACK_BCD_NONZERO                          ;#8ABF: 20 09
        inc     de                                             ;#8AC1: 13
        inc     de                                             ;#8AC2: 13
        inc     hl                                             ;#8AC3: 23
        djnz    UNPACK_BCD_SKIP_LZ_LOOP                        ;#8AC4: 10 F7
        ld      b,1                                            ;#8AC6: 06 01
        jr      UNPACK_BCD_LOOP                                ;#8AC8: 18 10

UNPACK_BCD_NONZERO:
        ; BCD byte non-zero: unpack high nibble (skip if leading zero), then low
        rra                                                    ;#8ACA: 1F
        rra                                                    ;#8ACB: 1F
        rra                                                    ;#8ACC: 1F
        rra                                                    ;#8ACD: 1F
        and     0Fh                                            ;#8ACE: E6 0F
        jr      z,UNPACK_BCD_AFTER_HIGH                        ;#8AD0: 28 01
        ld      (de),a                                         ;#8AD2: 12
UNPACK_BCD_AFTER_HIGH:
        ; Common path after high nibble: store low nibble
        inc     de                                             ;#8AD3: 13
        ld      a,(hl)                                         ;#8AD4: 7E
        and     0Fh                                            ;#8AD5: E6 0F
        ld      (de),a                                         ;#8AD7: 12
        inc     de                                             ;#8AD8: 13
        inc     hl                                             ;#8AD9: 23
UNPACK_BCD_LOOP:
        ; Loop body: unpack high+low nibbles from one BCD byte, advance DE
        ld      a,(hl)                                         ;#8ADA: 7E
        rra                                                    ;#8ADB: 1F
        rra                                                    ;#8ADC: 1F
        rra                                                    ;#8ADD: 1F
        rra                                                    ;#8ADE: 1F
        and     0Fh                                            ;#8ADF: E6 0F
        ld      (de),a                                         ;#8AE1: 12
        inc     de                                             ;#8AE2: 13
        ld      a,(hl)                                         ;#8AE3: 7E
        and     0Fh                                            ;#8AE4: E6 0F
        ld      (de),a                                         ;#8AE6: 12
        inc     de                                             ;#8AE7: 13
        inc     hl                                             ;#8AE8: 23
        djnz    UNPACK_BCD_LOOP                                ;#8AE9: 10 EF
        ret                                                    ;#8AEB: C9

ADD_SCORE:
        ; Look up SCORE_BONUS_TABLE[A] and BCD-add it into SCORE_BCD
        ; ADD_SCORE indexes SCORE_BONUS_TABLE by A, reads the BCD value, and adds it
        ; into SCORE_BCD with daa carry propagation. Then calls CHECK_SCORE_MILESTONE
        ; which awards an extra life on milestone scores.
        push    hl                                             ;#8AEC: E5
        ld      hl,SCORE_BONUS_TABLE                           ;#8AED: 21 09 8B
        add     a,l                                            ;#8AF0: 85
        ld      l,a                                            ;#8AF1: 6F
        jr      nc,ADD_SCORE_NO_CARRY                          ;#8AF2: 30 01
        inc     h                                              ;#8AF4: 24
ADD_SCORE_NO_CARRY:
        ; No carry from index offset: continue with high byte unchanged
        ld      a,(hl)                                         ;#8AF5: 7E
        ld      hl,SCORE_BCD_HIGH                              ;#8AF6: 21 33 E0
        ld      b,3                                            ;#8AF9: 06 03
        and     a                                              ;#8AFB: A7
ADD_SCORE_BCD_LOOP:
        ; Inner djnz of ADD_SCORE (3-byte BCD add)
        adc     a,(hl)                                         ;#8AFC: 8E
        daa                                                    ;#8AFD: 27
        ld      (hl),a                                         ;#8AFE: 77
        ld      a,0                                            ;#8AFF: 3E 00
        dec     hl                                             ;#8B01: 2B
        djnz    ADD_SCORE_BCD_LOOP                             ;#8B02: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#8B04: CD 33 8B
        pop     hl                                             ;#8B07: E1
        ret                                                    ;#8B08: C9

SCORE_BONUS_TABLE:
        ; Points table indexed by event id; consumed by ADD_SCORE
        dh      "01020204030604080510061207140816"             ;#8B09: 01 02 02 04 03 06 04 08 05 10 06 12 07 14 08 16
        dh      "09181020"                                     ;#8B19: 09 18 10 20

BCD_ADD_TO_BONUS:
        ; Opcode-overlap entry adding 10h to BONUS_BCD (see CONVENTIONS § OVERLAP_LD_A)
        ld      a,10h                                          ;#8B1D: 3E 10
        ld      hl,BONUS_BCD                                   ;#8B1F: 21 34 E0
        ld      b,4                                            ;#8B22: 06 04
        and     a                                              ;#8B24: A7
SCORE_BONUS_BCD_LOOP:
        ; Inner djnz inside SCORE_BONUS_TABLE area (alt entry)
        adc     a,(hl)                                         ;#8B25: 8E
        daa                                                    ;#8B26: 27
        ld      (hl),a                                         ;#8B27: 77
        ld      a,0                                            ;#8B28: 3E 00
        dec     hl                                             ;#8B2A: 2B
        djnz    SCORE_BONUS_BCD_LOOP                           ;#8B2B: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#8B2D: CD 33 8B
        jp      UPDATE_SCORE_HUD                               ;#8B30: C3 5F 8A

CHECK_SCORE_MILESTONE:
        ; Inspect SCORE_BCD mid-byte for extra-life thresholds (2, 8); triggers SFX_60
        ; CHECK_SCORE_MILESTONE tests SCORE_BCD mid-byte (SCORE_BCD_MID) against 2 and 8
        ; (extra-life thresholds at every 200/800-thousand). When hit, increments LIVES,
        ; sets EXTRA_LIFE_AWARDED to prevent re-award, and triggers
        ; SFX_TRIGGER_EXTRA_LIFE for the celebratory jingle.
        ld      a,(SCORE_BCD_MID)                              ;#8B33: 3A 32 E0
        cp      2                                              ;#8B36: FE 02
        jr      nz,MILESTONE_CHECK_8                           ;#8B38: 20 09
        ld      hl,EXTRA_LIFE_AWARDED                          ;#8B3A: 21 3E E0
        ld      a,(hl)                                         ;#8B3D: 7E
        and     a                                              ;#8B3E: A7
        jr      nz,UPDATE_HIGH_SCORE                           ;#8B3F: 20 1A
        jr      MILESTONE_AWARD_LIFE                           ;#8B41: 18 0B

MILESTONE_CHECK_8:
        ; Check second milestone (8 -> 800k pts) for extra life
        cp      8                                              ;#8B43: FE 08
        jr      nz,UPDATE_HIGH_SCORE                           ;#8B45: 20 14
        ld      hl,EXTRA_LIFE_AWARDED                          ;#8B47: 21 3E E0
        ld      a,(hl)                                         ;#8B4A: 7E
        dec     a                                              ;#8B4B: 3D
        jr      nz,UPDATE_HIGH_SCORE                           ;#8B4C: 20 0D
MILESTONE_AWARD_LIFE:
        ; Award extra life: set EXTRA_LIFE_AWARDED, trigger SFX, inc LIVES
        inc     (hl)                                           ;#8B4E: 34
        ld      a,1                                            ;#8B4F: 3E 01
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#8B51: 32 60 E5
        ld      hl,LIVES                                       ;#8B54: 21 35 E0
        inc     (hl)                                           ;#8B57: 34
        call    UPDATE_LIVES_DISPLAY                           ;#8B58: CD 75 8B
UPDATE_HIGH_SCORE:
        ; Compare SCORE_BCD vs HIGH_SCORE_BCD; if greater, copy SCORE into HIGH_SCORE
        ; UPDATE_HIGH_SCORE compares SCORE_BCD byte-by-byte (high to low) against
        ; HIGH_SCORE_BCD. If SCORE > HIGH_SCORE at any byte position (early-exit on
        ; lower byte), copies the entire SCORE_BCD into HIGH_SCORE_BCD. Otherwise leaves
        ; HIGH_SCORE unchanged.
        ld      hl,HIGH_SCORE_BCD                              ;#8B5B: 21 01 E0
        ld      de,SCORE_BCD                                   ;#8B5E: 11 31 E0
        ld      b,4                                            ;#8B61: 06 04
HIGH_SCORE_COMPARE_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (compare path)
        ld      a,(de)                                         ;#8B63: 1A
        cp      (hl)                                           ;#8B64: BE
        ret     c                                              ;#8B65: D8
        ld      (hl),a                                         ;#8B66: 77
        inc     hl                                             ;#8B67: 23
        inc     de                                             ;#8B68: 13
        jr      nz,HIGH_SCORE_TAIL_LOOP                        ;#8B69: 20 07
        djnz    HIGH_SCORE_COMPARE_LOOP                        ;#8B6B: 10 F6
        ret                                                    ;#8B6D: C9

HIGH_SCORE_COPY_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (copy path)
        ld      a,(de)                                         ;#8B6E: 1A
        ld      (hl),a                                         ;#8B6F: 77
        inc     hl                                             ;#8B70: 23
        inc     de                                             ;#8B71: 13
HIGH_SCORE_TAIL_LOOP:
        ; Inner copy loop: SCORE_BCD bytes 2..4 over to HIGH_SCORE_BCD
        djnz    HIGH_SCORE_COPY_LOOP                           ;#8B72: 10 FA
        ret                                                    ;#8B74: C9

UPDATE_LIVES_DISPLAY:
        ; Draw LIVES as mini-car tiles in the HUD name-table row; indexes LIVES_ICON_TILES
        ; UPDATE_LIVES_DISPLAY reads LIVES, indexes LIVES_ICON_TILES - 2*LIVES (so
        ; LIVES_ICON_TILES_TOP extends backward to prepend N car-top tiles), and LDIRVMs
        ; the two tile rows into the HUD name-table row (06B7h/06D7h) in both banks.
        ; LIVES=0 -> blank; LIVES=1 -> 1 mini-car icon; etc. These are name-table
        ; tiles, not sprites.
        ld      a,(LIVES)                                      ;#8B75: 3A 35 E0
        ld      hl,LIVES_ICON_TILES                            ;#8B78: 21 BC 8B
        add     a,a                                            ;#8B7B: 87
        jr      z,LIVES_DRAW_LOOP                              ;#8B7C: 28 08
        neg                                                    ;#8B7E: ED 44
        add     a,l                                            ;#8B80: 85
        ld      l,a                                            ;#8B81: 6F
        ld      a,0FFh                                         ;#8B82: 3E FF
        adc     a,h                                            ;#8B84: 8C
        ld      h,a                                            ;#8B85: 67
LIVES_DRAW_LOOP:
        ; Per-row LDIRVM loop: two 8-byte tile rows to two name-table bank mirrors
        push    hl                                             ;#8B86: E5
        LOAD_VRAM_ADDRESS de, 6B7h                             ;#8B87: 11 B7 06
        ld      bc,8                                           ;#8B8A: 01 08 00
        call    BIOS_LDIRVM                                    ;#8B8D: CD 5C 00
        pop     hl                                             ;#8B90: E1
        push    hl                                             ;#8B91: E5
        LOAD_VRAM_ADDRESS de, 16B7h                            ;#8B92: 11 B7 16
        ld      bc,8                                           ;#8B95: 01 08 00
        call    BIOS_LDIRVM                                    ;#8B98: CD 5C 00
        pop     hl                                             ;#8B9B: E1
        ld      bc,10h                                         ;#8B9C: 01 10 00
        add     hl,bc                                          ;#8B9F: 09
        push    hl                                             ;#8BA0: E5
        LOAD_VRAM_ADDRESS de, 6D7h                             ;#8BA1: 11 D7 06
        ld      bc,8                                           ;#8BA4: 01 08 00
        call    BIOS_LDIRVM                                    ;#8BA7: CD 5C 00
        pop     hl                                             ;#8BAA: E1
        LOAD_VRAM_ADDRESS de, 16D7h                            ;#8BAB: 11 D7 16
        ld      bc,8                                           ;#8BAE: 01 08 00
        jp      BIOS_LDIRVM                                    ;#8BB1: C3 5C 00

LIVES_ICON_TILES_TOP:
        ; Top-row tiles (F8/FA) of the lives mini-car icons; prepended via negative offset
        dh      "F8FAF8FAF8FAF8FA"                             ;#8BB4: F8 FA F8 FA F8 FA F8 FA

LIVES_ICON_TILES:
        ; Name-table tiles for the lives indicator (car-bottom F9/FB + blank 40h padding)
        dh      "4040404040404040F9FBF9FBF9FBF9FB"             ;#8BBC: 40 40 40 40 40 40 40 40 F9 FB F9 FB F9 FB F9 FB
        dh      "4040404040404040"                             ;#8BCC: 40 40 40 40 40 40 40 40

PSG_SILENCE_DEFAULTS:
        ; 14 bytes copied to PSG_MIRROR each frame before sound subsystems mix in
        dh      "00000000000000B8000000000000"                 ;#8BD4: 00 00 00 00 00 00 00 B8 00 00 00 00 00 00

UPDATE_SOUND:
        ; Render PSG output from PSG_MIRROR; runs 8 sound subsystems when GAME_ACTIVE
        ; UPDATE_SOUND copies the 14-byte PSG_SILENCE_DEFAULTS into PSG_MIRROR each
        ; frame as the "silent" baseline. Then, gated by GAME_ACTIVE, runs the 8 sound-
        ; tick subroutines (3 music + 5 SFX). Each subsystem reads a "control byte"
        ; (zero = no sound on this channel, non-zero = play the addressed stream). After
        ; ticking, writes PSG_MIRROR to PSG R0..R11 sequentially, plus R12 if
        ; PSG_MIRROR[0Dh] is non-zero (envelope-shape trigger). The 8 logical voices
        ; share the 3 PSG channels via priority.
        ld      hl,PSG_SILENCE_DEFAULTS                        ;#8BE2: 21 D4 8B
        ld      de,PSG_MIRROR                                  ;#8BE5: 11 00 E5
        ld      bc,0Eh                                         ;#8BE8: 01 0E 00
        ldir                                                   ;#8BEB: ED B0
        ld      a,(GAME_ACTIVE)                                ;#8BED: 3A 00 E0
        and     a                                              ;#8BF0: A7
        jr      z,SOUND_WRITE_PSG                              ;#8BF1: 28 18
        call    SOUND_TICK_MUSIC_THEME                         ;#8BF3: CD 7B 8F
        call    SOUND_TICK_SFX_FLAG                            ;#8BF6: CD 77 8D
        call    SOUND_TICK_MUSIC_OPENING                       ;#8BF9: CD FA 8D
        call    SOUND_TICK_MUSIC_STAGE_CLEAR                   ;#8BFC: CD 2E 8E
        call    SOUND_TICK_SFX_C_STAGE                         ;#8BFF: CD 3E 8C
        call    SOUND_TICK_SFX_SMOKE                           ;#8C02: CD 31 8D
        call    SOUND_TICK_SFX_BONUS                           ;#8C05: CD F5 8C
        call    SOUND_TICK_SFX_BANG                            ;#8C08: CD 7C 8C
SOUND_WRITE_PSG:
        ; Walk PSG_MIRROR[0..0Bh] and write each register via BIOS_WRTPSG
        ld      hl,PSG_MIRROR                                  ;#8C0B: 21 00 E5
        xor     a                                              ;#8C0E: AF
        ld      b,0Ch                                          ;#8C0F: 06 0C
SOUND_PSG_WRITE_LOOP:
        ; Inner djnz of SOUND_WRITE_PSG (12 PSG registers)
        ld      e,(hl)                                         ;#8C11: 5E
        inc     hl                                             ;#8C12: 23
        call    BIOS_WRTPSG                                    ;#8C13: CD 93 00
        inc     a                                              ;#8C16: 3C
        djnz    SOUND_PSG_WRITE_LOOP                           ;#8C17: 10 F8
        ld      a,(hl)                                         ;#8C19: 7E
        and     a                                              ;#8C1A: A7
        ret     z                                              ;#8C1B: C8
        ld      e,a                                            ;#8C1C: 5F
        ld      a,0Ch                                          ;#8C1D: 3E 0C
        call    BIOS_WRTPSG                                    ;#8C1F: CD 93 00
        inc     hl                                             ;#8C22: 23
        ld      e,(hl)                                         ;#8C23: 5E
        inc     a                                              ;#8C24: 3C
        jp      BIOS_WRTPSG                                    ;#8C25: C3 93 00

SFX_C_STAGE_RESET:
        ; Done: clear SOUND_STATE_C_STAGE then fall into init
        xor     a                                              ;#8C28: AF
        ld      (SOUND_STATE_C_STAGE),a                        ;#8C29: 32 65 E5
SFX_C_STAGE_INIT_STREAM:
        ; Init SFX_C_STAGE stream pointers, counter, and volume cursor
        ld      hl,SFX_C_STAGE_STREAM                          ;#8C2C: 21 D6 91
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),hl            ;#8C2F: 22 66 E5
        inc     hl                                             ;#8C32: 23
        ld      a,(hl)                                         ;#8C33: 7E
        ld      (SOUND_STATE_C_STAGE_COUNTER),a                ;#8C34: 32 68 E5
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#8C37: 21 65 90
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#8C3A: 22 69 E5
        ret                                                    ;#8C3D: C9

SOUND_TICK_SFX_C_STAGE:
        ; Sound subsystem driven by state at SOUND_STATE_C_STAGE
        ld      a,(SOUND_STATE_C_STAGE)                        ;#8C3E: 3A 65 E5
        and     a                                              ;#8C41: A7
        jr      z,SFX_C_STAGE_INIT_STREAM                      ;#8C42: 28 E8
        ld      de,(SOUND_STATE_C_STAGE_STREAM_PTR)            ;#8C44: ED 5B 66 E5
        ld      a,(de)                                         ;#8C48: 1A
        ld      c,a                                            ;#8C49: 4F
        inc     a                                              ;#8C4A: 3C
        jr      z,SFX_C_STAGE_RESET                            ;#8C4B: 28 DB
        ld      hl,(SOUND_STATE_C_STAGE_VOL_PTR)               ;#8C4D: 2A 69 E5
        ld      a,(hl)                                         ;#8C50: 7E
        inc     hl                                             ;#8C51: 23
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#8C52: 22 69 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#8C55: 32 0A E5
        ld      hl,SOUND_STATE_C_STAGE_COUNTER                 ;#8C58: 21 68 E5
        dec     (hl)                                           ;#8C5B: 35
        jr      nz,SFX_C_STAGE_LOAD_PITCH                      ;#8C5C: 20 10
        inc     de                                             ;#8C5E: 13
        inc     de                                             ;#8C5F: 13
        inc     de                                             ;#8C60: 13
        ld      a,(de)                                         ;#8C61: 1A
        dec     de                                             ;#8C62: 1B
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),de            ;#8C63: ED 53 66 E5
        ld      (hl),a                                         ;#8C67: 77
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#8C68: 21 65 90
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#8C6B: 22 69 E5
SFX_C_STAGE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_C_STAGE channel C
        ld      b,0                                            ;#8C6E: 06 00
        ld      hl,NOTE_PERIOD_TABLE                           ;#8C70: 21 99 93
        add     hl,bc                                          ;#8C73: 09
        ld      e,(hl)                                         ;#8C74: 5E
        inc     hl                                             ;#8C75: 23
        ld      d,(hl)                                         ;#8C76: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#8C77: ED 53 04 E5
        ret                                                    ;#8C7B: C9

SOUND_TICK_SFX_BANG:
        ; Sound subsystem driven by state at SOUND_STATE_BANG
        ld      a,(SOUND_STATE_BANG)                           ;#8C7C: 3A 62 E5
        dec     a                                              ;#8C7F: 3D
        jr      nz,SFX_BANG_TICK_BRANCH                        ;#8C80: 20 36
        xor     a                                              ;#8C82: AF
        ld      (SOUND_STATE_THEME),a                          ;#8C83: 32 10 E5
        ld      (SOUND_STATE_OPENING),a                        ;#8C86: 32 20 E5
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#8C89: 32 30 E5
        ld      (SOUND_STATE_FLAG),a                           ;#8C8C: 32 40 E5
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#8C8F: 32 41 E5
        ld      (SOUND_STATE_SMOKE),a                          ;#8C92: 32 42 E5
        ld      (SFX_TRIGGER_SMOKE),a                          ;#8C95: 32 50 E5
        ld      (SOUND_STATE_BONUS),a                          ;#8C98: 32 51 E5
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#8C9B: 32 60 E5
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#8C9E: 32 61 E5
        ld      a,2                                            ;#8CA1: 3E 02
        ld      (SOUND_STATE_BANG),a                           ;#8CA3: 32 62 E5
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#8CA6: 21 DC 8C
        ld      de,PSG_MIRROR                                  ;#8CA9: 11 00 E5
        ld      bc,0Bh                                         ;#8CAC: 01 0B 00
        ldir                                                   ;#8CAF: ED B0
        ld      hl,SFX_BANG_VOLUME_ENVELOPE                    ;#8CB1: 21 85 90
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#8CB4: 22 63 E5
        ret                                                    ;#8CB7: C9

SFX_BANG_TICK_BRANCH:
        ; SFX_BANG tick branch: ldir 8 bytes from precomputed envelope into PSG_MIRROR
        inc     a                                              ;#8CB8: 3C
        ret     z                                              ;#8CB9: C8
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#8CBA: 21 DC 8C
        ld      de,PSG_MIRROR                                  ;#8CBD: 11 00 E5
        ld      bc,8                                           ;#8CC0: 01 08 00
        ldir                                                   ;#8CC3: ED B0
        ld      hl,(SOUND_STATE_BANG_STREAM_PTR)               ;#8CC5: 2A 63 E5
        ld      a,(hl)                                         ;#8CC8: 7E
        inc     hl                                             ;#8CC9: 23
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#8CCA: 22 63 E5
        inc     a                                              ;#8CCD: 3C
        jr      nz,SFX_BANG_WRITE_VOL                          ;#8CCE: 20 03
        ld      (SOUND_STATE_BANG),a                           ;#8CD0: 32 62 E5
SFX_BANG_WRITE_VOL:
        ; Write the current envelope volume to PSG_MIRROR_VOL_A/B/C
        ld      hl,PSG_MIRROR_VOL_A                            ;#8CD3: 21 08 E5
        ld      (hl),a                                         ;#8CD6: 77
        inc     hl                                             ;#8CD7: 23
        ld      (hl),a                                         ;#8CD8: 77
        inc     hl                                             ;#8CD9: 23
        ld      (hl),a                                         ;#8CDA: 77
        ret                                                    ;#8CDB: C9

SFX_BANG_INIT_PSG_BLOCK:
        ; 11-byte PSG silence/init block; LDIR-copied to PSG_MIRROR when SFX_BANG fires
        dh      "FF0FF205FF0F1F820F0F0F"                       ;#8CDC: FF 0F F2 05 FF 0F 1F 82 0F 0F 0F

SFX_BONUS_INIT_STREAM:
        ; Init SFX_BONUS stream pointer at SFX_BONUS_STREAM
        ld      de,SFX_BONUS_STREAM                            ;#8CE7: 11 C5 91
        ld      hl,SOUND_STATE_BONUS_STREAM_PTR                ;#8CEA: 21 52 E5
        ld      (hl),e                                         ;#8CED: 73
        inc     hl                                             ;#8CEE: 23
        ld      (hl),d                                         ;#8CEF: 72
        inc     hl                                             ;#8CF0: 23
        inc     de                                             ;#8CF1: 13
        ld      a,(de)                                         ;#8CF2: 1A
        ld      (hl),a                                         ;#8CF3: 77
        ret                                                    ;#8CF4: C9

SOUND_TICK_SFX_BONUS:
        ; Sound subsystem driven by state at SOUND_STATE_BONUS
        ld      hl,SOUND_STATE_BONUS                           ;#8CF5: 21 51 E5
        ld      a,(hl)                                         ;#8CF8: 7E
        and     a                                              ;#8CF9: A7
        jr      z,SFX_BONUS_INIT_STREAM                        ;#8CFA: 28 EB
        inc     hl                                             ;#8CFC: 23
        ld      e,(hl)                                         ;#8CFD: 5E
        inc     hl                                             ;#8CFE: 23
        ld      d,(hl)                                         ;#8CFF: 56
        inc     hl                                             ;#8D00: 23
        ld      a,(de)                                         ;#8D01: 1A
        ld      c,a                                            ;#8D02: 4F
        inc     a                                              ;#8D03: 3C
        jr      z,SFX_BONUS_INIT_STREAM                        ;#8D04: 28 E1
        dec     (hl)                                           ;#8D06: 35
        jr      nz,SFX_BONUS_LOAD_PITCH                        ;#8D07: 20 0A
        inc     de                                             ;#8D09: 13
        inc     de                                             ;#8D0A: 13
        inc     de                                             ;#8D0B: 13
        ld      a,(de)                                         ;#8D0C: 1A
        ld      (hl),a                                         ;#8D0D: 77
        dec     de                                             ;#8D0E: 1B
        dec     hl                                             ;#8D0F: 2B
        ld      (hl),d                                         ;#8D10: 72
        dec     hl                                             ;#8D11: 2B
        ld      (hl),e                                         ;#8D12: 73
SFX_BONUS_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_BONUS channel B
        ld      hl,NOTE_PERIOD_TABLE                           ;#8D13: 21 99 93
        ld      b,0                                            ;#8D16: 06 00
        add     hl,bc                                          ;#8D18: 09
        ld      e,(hl)                                         ;#8D19: 5E
        inc     hl                                             ;#8D1A: 23
        ld      d,(hl)                                         ;#8D1B: 56
        ld      (PSG_MIRROR_PITCH_B),de                        ;#8D1C: ED 53 02 E5
        ld      a,0Ch                                          ;#8D20: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#8D22: 32 09 E5
        ret                                                    ;#8D25: C9

SFX_SMOKE_RESET:
        ; Done: reset volume pointer to SFX_SMOKE_VOLUME_ENVELOPE and clear state
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#8D26: 21 55 90
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#8D29: 22 47 E5
        xor     a                                              ;#8D2C: AF
        ld      (SOUND_STATE_SMOKE_VOL_PTR),a                  ;#8D2D: 32 47 E5
        ret                                                    ;#8D30: C9

SOUND_TICK_SFX_SMOKE:
        ; Sound subsystem driven by state at SOUND_STATE_SMOKE
        ld      a,(SOUND_STATE_SMOKE)                          ;#8D31: 3A 42 E5
        and     a                                              ;#8D34: A7
        jr      z,SFX_SMOKE_RESET                              ;#8D35: 28 EF
        ld      de,(SOUND_STATE_SMOKE_STREAM_PTR)              ;#8D37: ED 5B 43 E5
        ld      a,(de)                                         ;#8D3B: 1A
        cp      0FFh                                           ;#8D3C: FE FF
        jr      z,SFX_SMOKE_RESET                              ;#8D3E: 28 E6
        ld      hl,SOUND_STATE_SMOKE_COUNTER                   ;#8D40: 21 45 E5
        dec     (hl)                                           ;#8D43: 35
        jr      nz,SFX_SMOKE_LOAD_PITCH                        ;#8D44: 20 0F
        inc     hl                                             ;#8D46: 23
        ld      c,(hl)                                         ;#8D47: 4E
        dec     hl                                             ;#8D48: 2B
        ld      (hl),c                                         ;#8D49: 71
        dec     hl                                             ;#8D4A: 2B
        inc     de                                             ;#8D4B: 13
        ld      (hl),d                                         ;#8D4C: 72
        dec     hl                                             ;#8D4D: 2B
        ld      (hl),e                                         ;#8D4E: 73
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#8D4F: 21 55 90
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#8D52: 22 47 E5
SFX_SMOKE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_SMOKE channel C
        ld      hl,NOTE_PERIOD_TABLE                           ;#8D55: 21 99 93
        add     a,l                                            ;#8D58: 85
        ld      l,a                                            ;#8D59: 6F
        ld      a,0                                            ;#8D5A: 3E 00
        adc     a,h                                            ;#8D5C: 8C
        ld      h,a                                            ;#8D5D: 67
        ld      e,(hl)                                         ;#8D5E: 5E
        inc     hl                                             ;#8D5F: 23
        ld      d,(hl)                                         ;#8D60: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#8D61: ED 53 04 E5
        ld      hl,(SOUND_STATE_SMOKE_VOL_PTR)                 ;#8D65: 2A 47 E5
        ld      a,(hl)                                         ;#8D68: 7E
        inc     hl                                             ;#8D69: 23
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#8D6A: 22 47 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#8D6D: 32 0A E5
        ld      hl,0                                           ;#8D70: 21 00 00
        ld      (PSG_MIRROR_VOL_A),hl                          ;#8D73: 22 08 E5
        ret                                                    ;#8D76: C9

SOUND_TICK_SFX_FLAG:
        ; Sound subsystem driven by state at SOUND_STATE_FLAG
        ld      a,(SOUND_STATE_FLAG)                           ;#8D77: 3A 40 E5
        and     a                                              ;#8D7A: A7
        jr      z,SFX_FLAG_CHECK_VARIANT                       ;#8D7B: 28 17
        xor     a                                              ;#8D7D: AF
        ld      (SOUND_STATE_FLAG),a                           ;#8D7E: 32 40 E5
        ld      de,SFX_FLAG_STREAM_BASE                        ;#8D81: 11 8D 91
SFX_FLAG_INIT_SFX_SMOKE:
        ; SFX_FLAG fires variant A: seed SOUND_STATE_SMOKE with stream and durations
        ld      hl,SOUND_STATE_SMOKE                           ;#8D84: 21 42 E5
        ld      (hl),1                                         ;#8D87: 36 01
        inc     hl                                             ;#8D89: 23
        ld      (hl),e                                         ;#8D8A: 73
        inc     hl                                             ;#8D8B: 23
        ld      (hl),d                                         ;#8D8C: 72
        inc     hl                                             ;#8D8D: 23
        ld      (hl),2                                         ;#8D8E: 36 02
        inc     hl                                             ;#8D90: 23
        ld      (hl),2                                         ;#8D91: 36 02
        ret                                                    ;#8D93: C9

SFX_FLAG_CHECK_VARIANT:
        ; Check second SFX_FLAG variant flag (SOUND_STATE_FLAG_ALT)
        ld      a,(SOUND_STATE_FLAG_ALT)                       ;#8D94: 3A 41 E5
        and     a                                              ;#8D97: A7
        jr      z,SFX_FLAG_CHECK_EXTRA_LIFE                    ;#8D98: 28 0A
        xor     a                                              ;#8D9A: AF
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#8D9B: 32 41 E5
        ld      de,SFX_FLAG_STREAM_FLAG_GET                    ;#8D9E: 11 7F 91
        jp      SFX_FLAG_INIT_SFX_SMOKE                        ;#8DA1: C3 84 8D

SFX_FLAG_CHECK_EXTRA_LIFE:
        ; Check SFX_TRIGGER_EXTRA_LIFE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_EXTRA_LIFE)                     ;#8DA4: 3A 60 E5
        and     a                                              ;#8DA7: A7
        jr      z,SFX_FLAG_CHECK_SMOKE                         ;#8DA8: 28 17
        xor     a                                              ;#8DAA: AF
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#8DAB: 32 60 E5
        ld      de,SFX_FLAG_STREAM_EXTRA_LIFE                  ;#8DAE: 11 A1 91
        ld      hl,SOUND_STATE_SMOKE                           ;#8DB1: 21 42 E5
        ld      (hl),1                                         ;#8DB4: 36 01
        inc     hl                                             ;#8DB6: 23
        ld      (hl),e                                         ;#8DB7: 73
        inc     hl                                             ;#8DB8: 23
        ld      (hl),d                                         ;#8DB9: 72
        inc     hl                                             ;#8DBA: 23
        ld      (hl),4                                         ;#8DBB: 36 04
        inc     hl                                             ;#8DBD: 23
        ld      (hl),4                                         ;#8DBE: 36 04
        ret                                                    ;#8DC0: C9

SFX_FLAG_CHECK_SMOKE:
        ; Check SFX_TRIGGER_SMOKE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_SMOKE)                          ;#8DC1: 3A 50 E5
        and     a                                              ;#8DC4: A7
        jr      z,SFX_FLAG_CHECK_E561                          ;#8DC5: 28 17
        xor     a                                              ;#8DC7: AF
        ld      (SFX_TRIGGER_SMOKE),a                          ;#8DC8: 32 50 E5
        ld      de,SFX_SMOKE_STREAM                            ;#8DCB: 11 95 91
        ld      hl,SOUND_STATE_SMOKE                           ;#8DCE: 21 42 E5
        ld      (hl),1                                         ;#8DD1: 36 01
        inc     hl                                             ;#8DD3: 23
        ld      (hl),e                                         ;#8DD4: 73
        inc     hl                                             ;#8DD5: 23
        ld      (hl),d                                         ;#8DD6: 72
        inc     hl                                             ;#8DD7: 23
        ld      (hl),2                                         ;#8DD8: 36 02
        inc     hl                                             ;#8DDA: 23
        ld      (hl),2                                         ;#8DDB: 36 02
        ret                                                    ;#8DDD: C9

SFX_FLAG_CHECK_E561:
        ; Check SOUND_STATE_BANG_TRIGGER (fuel-low tick): kick SFX_SMOKE if just fired
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#8DDE: 3A 61 E5
        dec     a                                              ;#8DE1: 3D
        ret     nz                                             ;#8DE2: C0
        ld      a,2                                            ;#8DE3: 3E 02
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#8DE5: 32 61 E5
        ld      hl,SFX_FLAG_STREAM_FUEL_LOW                    ;#8DE8: 21 9A 91
        ld      (SOUND_STATE_SMOKE_STREAM_PTR),hl              ;#8DEB: 22 43 E5
        ld      hl,0F0Fh                                       ;#8DEE: 21 0F 0F
        ld      (SOUND_STATE_SMOKE_COUNTER),hl                 ;#8DF1: 22 45 E5
        ld      a,1                                            ;#8DF4: 3E 01
        ld      (SOUND_STATE_SMOKE),a                          ;#8DF6: 32 42 E5
        ret                                                    ;#8DF9: C9

SOUND_TICK_MUSIC_OPENING:
        ; Music channel B tick; state at SOUND_STATE_OPENING
        ld      hl,SOUND_STATE_OPENING                         ;#8DFA: 21 20 E5
        ld      a,(hl)                                         ;#8DFD: 7E
        and     a                                              ;#8DFE: A7
        jr      z,SOUND_TICK_MUSIC_OPENING_INIT                ;#8DFF: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#8E01: CD 62 8E
        and     a                                              ;#8E04: A7
        ret     nz                                             ;#8E05: C0
SOUND_TICK_MUSIC_OPENING_INIT:
        ; MUSIC_OPENING init: clear state and seed pointers for three streams
        ld      hl,SOUND_STATE_OPENING                         ;#8E06: 21 20 E5
        xor     a                                              ;#8E09: AF
        ld      (hl),a                                         ;#8E0A: 77
        inc     hl                                             ;#8E0B: 23
        ld      de,MUSIC_OPENING_VOICE_0                       ;#8E0C: 11 74 93
        ld      (hl),e                                         ;#8E0F: 73
        inc     hl                                             ;#8E10: 23
        ld      (hl),d                                         ;#8E11: 72
        inc     hl                                             ;#8E12: 23
        inc     de                                             ;#8E13: 13
        ld      a,(de)                                         ;#8E14: 1A
        ld      (hl),a                                         ;#8E15: 77
        inc     hl                                             ;#8E16: 23
        ld      de,MUSIC_OPENING_VOICE_1                       ;#8E17: 11 54 93
        ld      (hl),e                                         ;#8E1A: 73
        inc     hl                                             ;#8E1B: 23
        ld      (hl),d                                         ;#8E1C: 72
        inc     hl                                             ;#8E1D: 23
        inc     de                                             ;#8E1E: 13
        ld      a,(de)                                         ;#8E1F: 1A
        ld      (hl),a                                         ;#8E20: 77
        inc     hl                                             ;#8E21: 23
        ld      de,MUSIC_OPENING_VOICE_2                       ;#8E22: 11 22 93
        ld      (hl),e                                         ;#8E25: 73
        inc     hl                                             ;#8E26: 23
        ld      (hl),d                                         ;#8E27: 72
        inc     hl                                             ;#8E28: 23
        inc     de                                             ;#8E29: 13
        ld      a,(de)                                         ;#8E2A: 1A
        ld      (hl),a                                         ;#8E2B: 77
        inc     hl                                             ;#8E2C: 23
        ret                                                    ;#8E2D: C9

SOUND_TICK_MUSIC_STAGE_CLEAR:
        ; Music channel C tick; state at SOUND_STATE_STAGE_CLEAR
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#8E2E: 21 30 E5
        ld      a,(hl)                                         ;#8E31: 7E
        and     a                                              ;#8E32: A7
        jr      z,SOUND_TICK_MUSIC_STAGE_CLEAR_INIT            ;#8E33: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#8E35: CD 62 8E
        and     a                                              ;#8E38: A7
        ret     nz                                             ;#8E39: C0
SOUND_TICK_MUSIC_STAGE_CLEAR_INIT:
        ; MUSIC_STAGE_CLEAR init: clear state and seed pointers for three voices
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#8E3A: 21 30 E5
        xor     a                                              ;#8E3D: AF
        ld      (hl),a                                         ;#8E3E: 77
        inc     hl                                             ;#8E3F: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_2            ;#8E40: 11 B2 91
        ld      (hl),e                                         ;#8E43: 73
        inc     hl                                             ;#8E44: 23
        ld      (hl),d                                         ;#8E45: 72
        inc     hl                                             ;#8E46: 23
        inc     de                                             ;#8E47: 13
        ld      a,(de)                                         ;#8E48: 1A
        ld      (hl),a                                         ;#8E49: 77
        inc     hl                                             ;#8E4A: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_1            ;#8E4B: 11 B0 91
        ld      (hl),e                                         ;#8E4E: 73
        inc     hl                                             ;#8E4F: 23
        ld      (hl),d                                         ;#8E50: 72
        inc     hl                                             ;#8E51: 23
        inc     de                                             ;#8E52: 13
        ld      a,(de)                                         ;#8E53: 1A
        ld      (hl),a                                         ;#8E54: 77
        inc     hl                                             ;#8E55: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_0            ;#8E56: 11 AE 91
        ld      (hl),e                                         ;#8E59: 73
        inc     hl                                             ;#8E5A: 23
        ld      (hl),d                                         ;#8E5B: 72
        inc     hl                                             ;#8E5C: 23
        inc     de                                             ;#8E5D: 13
        ld      a,(de)                                         ;#8E5E: 1A
        ld      (hl),a                                         ;#8E5F: 77
        inc     hl                                             ;#8E60: 23
        ret                                                    ;#8E61: C9

SOUND_ADVANCE_NOTE_DURATION:
        ; Decrement note-duration counter; on rollover, advance to next note byte
        inc     hl                                             ;#8E62: 23
        ld      e,(hl)                                         ;#8E63: 5E
        inc     hl                                             ;#8E64: 23
        ld      d,(hl)                                         ;#8E65: 56
        inc     hl                                             ;#8E66: 23
        dec     (hl)                                           ;#8E67: 35
        jr      nz,SOUND_ADVANCE_TAIL                          ;#8E68: 20 0C
        inc     de                                             ;#8E6A: 13
        inc     de                                             ;#8E6B: 13
        inc     de                                             ;#8E6C: 13
        ld      a,(de)                                         ;#8E6D: 1A
        dec     de                                             ;#8E6E: 1B
        ld      (hl),a                                         ;#8E6F: 77
        dec     hl                                             ;#8E70: 2B
        ld      (hl),d                                         ;#8E71: 72
        dec     hl                                             ;#8E72: 2B
        ld      (hl),e                                         ;#8E73: 73
        inc     hl                                             ;#8E74: 23
        inc     hl                                             ;#8E75: 23
SOUND_ADVANCE_TAIL:
        ; Common tail of SOUND_ADVANCE_NOTE_DURATION: ret nz
        ld      a,(de)                                         ;#8E76: 1A
        inc     a                                              ;#8E77: 3C
        ret     z                                              ;#8E78: C8
        dec     a                                              ;#8E79: 3D
        ld      de,NOTE_PERIOD_TABLE                           ;#8E7A: 11 99 93
        add     a,e                                            ;#8E7D: 83
        ld      e,a                                            ;#8E7E: 5F
        ld      a,0                                            ;#8E7F: 3E 00
        adc     a,d                                            ;#8E81: 8A
        ld      d,a                                            ;#8E82: 57
        ld      a,(de)                                         ;#8E83: 1A
        ld      c,a                                            ;#8E84: 4F
        inc     de                                             ;#8E85: 13
        ld      a,(de)                                         ;#8E86: 1A
        ld      b,a                                            ;#8E87: 47
        ld      (PSG_MIRROR),bc                                ;#8E88: ED 43 00 E5
        ld      a,0Ch                                          ;#8E8C: 3E 0C
        ld      (PSG_MIRROR_VOL_A),a                           ;#8E8E: 32 08 E5
        inc     hl                                             ;#8E91: 23
        ld      e,(hl)                                         ;#8E92: 5E
        inc     hl                                             ;#8E93: 23
        ld      d,(hl)                                         ;#8E94: 56
        inc     hl                                             ;#8E95: 23
        dec     (hl)                                           ;#8E96: 35
        jr      nz,SOUND_B_LOAD_PITCH                          ;#8E97: 20 0C
        inc     de                                             ;#8E99: 13
        inc     de                                             ;#8E9A: 13
        inc     de                                             ;#8E9B: 13
        ld      a,(de)                                         ;#8E9C: 1A
        dec     de                                             ;#8E9D: 1B
        ld      (hl),a                                         ;#8E9E: 77
        dec     hl                                             ;#8E9F: 2B
        ld      (hl),d                                         ;#8EA0: 72
        dec     hl                                             ;#8EA1: 2B
        ld      (hl),e                                         ;#8EA2: 73
        inc     hl                                             ;#8EA3: 23
        inc     hl                                             ;#8EA4: 23
SOUND_B_LOAD_PITCH:
        ; After advance: look up channel-B note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#8EA5: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#8EA6: 11 99 93
        add     a,e                                            ;#8EA9: 83
        ld      e,a                                            ;#8EAA: 5F
        ld      a,0                                            ;#8EAB: 3E 00
        adc     a,d                                            ;#8EAD: 8A
        ld      d,a                                            ;#8EAE: 57
        ld      a,(de)                                         ;#8EAF: 1A
        ld      c,a                                            ;#8EB0: 4F
        inc     de                                             ;#8EB1: 13
        ld      a,(de)                                         ;#8EB2: 1A
        ld      b,a                                            ;#8EB3: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#8EB4: ED 43 02 E5
        ld      a,0Ch                                          ;#8EB8: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#8EBA: 32 09 E5
        inc     hl                                             ;#8EBD: 23
        ld      e,(hl)                                         ;#8EBE: 5E
        inc     hl                                             ;#8EBF: 23
        ld      d,(hl)                                         ;#8EC0: 56
        inc     hl                                             ;#8EC1: 23
        dec     (hl)                                           ;#8EC2: 35
        jr      nz,SOUND_C_LOAD_PITCH                          ;#8EC3: 20 0C
        inc     de                                             ;#8EC5: 13
        inc     de                                             ;#8EC6: 13
        inc     de                                             ;#8EC7: 13
        ld      a,(de)                                         ;#8EC8: 1A
        dec     de                                             ;#8EC9: 1B
        ld      (hl),a                                         ;#8ECA: 77
        dec     hl                                             ;#8ECB: 2B
        ld      (hl),d                                         ;#8ECC: 72
        dec     hl                                             ;#8ECD: 2B
        ld      (hl),e                                         ;#8ECE: 73
        inc     hl                                             ;#8ECF: 23
        inc     hl                                             ;#8ED0: 23
SOUND_C_LOAD_PITCH:
        ; After advance: look up channel-C note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#8ED1: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#8ED2: 11 99 93
        add     a,e                                            ;#8ED5: 83
        ld      e,a                                            ;#8ED6: 5F
        ld      a,0                                            ;#8ED7: 3E 00
        adc     a,d                                            ;#8ED9: 8A
        ld      d,a                                            ;#8EDA: 57
        ld      a,(de)                                         ;#8EDB: 1A
        ld      c,a                                            ;#8EDC: 4F
        inc     de                                             ;#8EDD: 13
        ld      a,(de)                                         ;#8EDE: 1A
        ld      b,a                                            ;#8EDF: 47
        ld      (PSG_MIRROR_PITCH_C),bc                        ;#8EE0: ED 43 04 E5
        ld      a,0Ch                                          ;#8EE4: 3E 0C
        ld      (PSG_MIRROR_VOL_C),a                           ;#8EE6: 32 0A E5
        ret                                                    ;#8EE9: C9

MUSIC_THEME_RESTART:
        ; Stream end: bump SOUND_STATE_THEME index; restart substream 0/1/2
        ld      hl,SOUND_STATE_THEME                           ;#8EEA: 21 10 E5
        inc     hl                                             ;#8EED: 23
        inc     (hl)                                           ;#8EEE: 34
        ld      a,(hl)                                         ;#8EEF: 7E
        cp      3                                              ;#8EF0: FE 03
        jr      z,MUSIC_THEME_REPICK                           ;#8EF2: 28 2B
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#8EF4: 11 D5 90
        inc     hl                                             ;#8EF7: 23
        ld      (hl),e                                         ;#8EF8: 73
        inc     hl                                             ;#8EF9: 23
        ld      (hl),d                                         ;#8EFA: 72
        inc     de                                             ;#8EFB: 13
        ld      a,(de)                                         ;#8EFC: 1A
        inc     hl                                             ;#8EFD: 23
        ld      (hl),a                                         ;#8EFE: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#8EFF: 11 45 90
        inc     hl                                             ;#8F02: 23
        ld      (hl),e                                         ;#8F03: 73
        inc     hl                                             ;#8F04: 23
        ld      (hl),d                                         ;#8F05: 72
        inc     hl                                             ;#8F06: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE0_2                ;#8F07: 11 16 91
        ld      (hl),e                                         ;#8F0A: 73
        inc     hl                                             ;#8F0B: 23
        ld      (hl),d                                         ;#8F0C: 72
        inc     hl                                             ;#8F0D: 23
        inc     de                                             ;#8F0E: 13
        ld      a,(de)                                         ;#8F0F: 1A
        ld      (hl),a                                         ;#8F10: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#8F11: 11 05 90
        inc     hl                                             ;#8F14: 23
        ld      (hl),e                                         ;#8F15: 73
        inc     hl                                             ;#8F16: 23
        ld      (hl),d                                         ;#8F17: 72
        inc     de                                             ;#8F18: 13
        inc     hl                                             ;#8F19: 23
        ld      a,(de)                                         ;#8F1A: 1A
        ld      (hl),a                                         ;#8F1B: 77
        jp      SOUND_TICK_MUSIC_THEME                         ;#8F1C: C3 7B 8F

MUSIC_THEME_REPICK:
        ; After substream 3: call PICK_MUSIC_STREAM then re-enter SOUND_TICK_MUSIC_THEME
        call    PICK_MUSIC_STREAM                              ;#8F1F: CD 26 8F
        jp      SOUND_TICK_MUSIC_THEME                         ;#8F22: C3 7B 8F

MUSIC_THEME_REFRESH_HEAD:
        ; Substream 0 head refresh: clear state and re-seed (used after silence/start)
        inc     hl                                             ;#8F25: 23
PICK_MUSIC_STREAM:
        ; Select music data stream for SOUND_TICK_MUSIC_THEME based on STAGE_PALETTE_INDEX
        xor     a                                              ;#8F26: AF
        ld      (hl),a                                         ;#8F27: 77
        ld      a,(STAGE_PALETTE_INDEX)                        ;#8F28: 3A 30 E0
        cpl                                                    ;#8F2B: 2F
        and     3                                              ;#8F2C: E6 03
        jp      z,MUSIC_THEME_PICK_VARIANT                     ;#8F2E: CA 56 8F
        ld      de,MUSIC_THEME_VOICE0_BASELINE                 ;#8F31: 11 0B 92
        inc     hl                                             ;#8F34: 23
        ld      (hl),e                                         ;#8F35: 73
        inc     hl                                             ;#8F36: 23
        ld      (hl),d                                         ;#8F37: 72
        inc     de                                             ;#8F38: 13
        ld      a,(de)                                         ;#8F39: 1A
        inc     hl                                             ;#8F3A: 23
        ld      (hl),a                                         ;#8F3B: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#8F3C: 11 45 90
        inc     hl                                             ;#8F3F: 23
        ld      (hl),e                                         ;#8F40: 73
        inc     hl                                             ;#8F41: 23
        ld      (hl),d                                         ;#8F42: 72
        inc     hl                                             ;#8F43: 23
        ld      de,MUSIC_THEME_VOICE1_BASELINE                 ;#8F44: 11 90 92
        ld      (hl),e                                         ;#8F47: 73
        inc     hl                                             ;#8F48: 23
        ld      (hl),d                                         ;#8F49: 72
        inc     hl                                             ;#8F4A: 23
        inc     de                                             ;#8F4B: 13
        ld      a,(de)                                         ;#8F4C: 1A
        ld      (hl),a                                         ;#8F4D: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#8F4E: 11 05 90
        inc     hl                                             ;#8F51: 23
        ld      (hl),e                                         ;#8F52: 73
        inc     hl                                             ;#8F53: 23
        ld      (hl),d                                         ;#8F54: 72
        ret                                                    ;#8F55: C9

MUSIC_THEME_PICK_VARIANT:
        ; Pick the substream variant based on STAGE_PALETTE_INDEX bits
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#8F56: 11 D5 90
        inc     hl                                             ;#8F59: 23
        ld      (hl),e                                         ;#8F5A: 73
        inc     hl                                             ;#8F5B: 23
        ld      (hl),d                                         ;#8F5C: 72
        inc     de                                             ;#8F5D: 13
        ld      a,(de)                                         ;#8F5E: 1A
        inc     hl                                             ;#8F5F: 23
        ld      (hl),a                                         ;#8F60: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#8F61: 11 45 90
        inc     hl                                             ;#8F64: 23
        ld      (hl),e                                         ;#8F65: 73
        inc     hl                                             ;#8F66: 23
        ld      (hl),d                                         ;#8F67: 72
        inc     hl                                             ;#8F68: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE1                  ;#8F69: 11 46 91
        ld      (hl),e                                         ;#8F6C: 73
        inc     hl                                             ;#8F6D: 23
        ld      (hl),d                                         ;#8F6E: 72
        inc     hl                                             ;#8F6F: 23
        inc     de                                             ;#8F70: 13
        ld      a,(de)                                         ;#8F71: 1A
        ld      (hl),a                                         ;#8F72: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#8F73: 11 05 90
        inc     hl                                             ;#8F76: 23
        ld      (hl),e                                         ;#8F77: 73
        inc     hl                                             ;#8F78: 23
        ld      (hl),d                                         ;#8F79: 72
        ret                                                    ;#8F7A: C9

SOUND_TICK_MUSIC_THEME:
        ; Music channel A tick; state at SOUND_STATE_THEME, writes PSG R0/R1
        ld      hl,SOUND_STATE_THEME                           ;#8F7B: 21 10 E5
        ld      a,(hl)                                         ;#8F7E: 7E
        and     a                                              ;#8F7F: A7
        jp      z,MUSIC_THEME_REFRESH_HEAD                     ;#8F80: CA 25 8F
        inc     hl                                             ;#8F83: 23
        inc     hl                                             ;#8F84: 23
        ld      e,(hl)                                         ;#8F85: 5E
        inc     hl                                             ;#8F86: 23
        ld      d,(hl)                                         ;#8F87: 56
        inc     hl                                             ;#8F88: 23
        ld      a,(hl)                                         ;#8F89: 7E
        dec     (hl)                                           ;#8F8A: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH                      ;#8F8B: 20 15
        inc     de                                             ;#8F8D: 13
        inc     de                                             ;#8F8E: 13
        inc     de                                             ;#8F8F: 13
        ld      a,(de)                                         ;#8F90: 1A
        ld      (hl),a                                         ;#8F91: 77
        dec     de                                             ;#8F92: 1B
        dec     hl                                             ;#8F93: 2B
        ld      (hl),d                                         ;#8F94: 72
        dec     hl                                             ;#8F95: 2B
        ld      (hl),e                                         ;#8F96: 73
        inc     hl                                             ;#8F97: 23
        inc     hl                                             ;#8F98: 23
        ld      de,MUSIC_THEME_DURATIONS                       ;#8F99: 11 45 90
        inc     hl                                             ;#8F9C: 23
        ld      (hl),e                                         ;#8F9D: 73
        inc     hl                                             ;#8F9E: 23
        ld      (hl),d                                         ;#8F9F: 72
        dec     hl                                             ;#8FA0: 2B
        dec     hl                                             ;#8FA1: 2B
MUSIC_THEME_LOAD_PITCH:
        ; MUSIC_THEME tick: look up pitch byte from current stream
        ld      a,(de)                                         ;#8FA2: 1A
        cp      0FFh                                           ;#8FA3: FE FF
        jp      z,MUSIC_THEME_RESTART                          ;#8FA5: CA EA 8E
        ld      de,NOTE_PERIOD_TABLE                           ;#8FA8: 11 99 93
        add     a,e                                            ;#8FAB: 83
        ld      e,a                                            ;#8FAC: 5F
        ld      a,0                                            ;#8FAD: 3E 00
        adc     a,d                                            ;#8FAF: 8A
        ld      d,a                                            ;#8FB0: 57
        ld      a,(de)                                         ;#8FB1: 1A
        ld      c,a                                            ;#8FB2: 4F
        inc     de                                             ;#8FB3: 13
        ld      a,(de)                                         ;#8FB4: 1A
        ld      b,a                                            ;#8FB5: 47
        ld      (PSG_MIRROR),bc                                ;#8FB6: ED 43 00 E5
        inc     hl                                             ;#8FBA: 23
        ld      e,(hl)                                         ;#8FBB: 5E
        inc     hl                                             ;#8FBC: 23
        ld      d,(hl)                                         ;#8FBD: 56
        ld      a,(de)                                         ;#8FBE: 1A
        inc     de                                             ;#8FBF: 13
        ld      (hl),d                                         ;#8FC0: 72
        dec     hl                                             ;#8FC1: 2B
        ld      (hl),e                                         ;#8FC2: 73
        ld      (PSG_MIRROR_VOL_A),a                           ;#8FC3: 32 08 E5
        inc     hl                                             ;#8FC6: 23
        inc     hl                                             ;#8FC7: 23
        ld      e,(hl)                                         ;#8FC8: 5E
        inc     hl                                             ;#8FC9: 23
        ld      d,(hl)                                         ;#8FCA: 56
        inc     hl                                             ;#8FCB: 23
        ld      a,(hl)                                         ;#8FCC: 7E
        dec     (hl)                                           ;#8FCD: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH_B                    ;#8FCE: 20 15
        inc     de                                             ;#8FD0: 13
        inc     de                                             ;#8FD1: 13
        inc     de                                             ;#8FD2: 13
        ld      a,(de)                                         ;#8FD3: 1A
        ld      (hl),a                                         ;#8FD4: 77
        dec     de                                             ;#8FD5: 1B
        dec     hl                                             ;#8FD6: 2B
        ld      (hl),d                                         ;#8FD7: 72
        dec     hl                                             ;#8FD8: 2B
        ld      (hl),e                                         ;#8FD9: 73
        inc     hl                                             ;#8FDA: 23
        inc     hl                                             ;#8FDB: 23
        ld      de,SOUND_ENVELOPE_TABLE                        ;#8FDC: 11 05 90
        inc     hl                                             ;#8FDF: 23
        ld      (hl),e                                         ;#8FE0: 73
        inc     hl                                             ;#8FE1: 23
        ld      (hl),d                                         ;#8FE2: 72
        dec     hl                                             ;#8FE3: 2B
        dec     hl                                             ;#8FE4: 2B
MUSIC_THEME_LOAD_PITCH_B:
        ; MUSIC_THEME second-voice: look up pitch byte from second stream
        ld      a,(de)                                         ;#8FE5: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#8FE6: 11 99 93
        add     a,e                                            ;#8FE9: 83
        ld      e,a                                            ;#8FEA: 5F
        ld      a,0                                            ;#8FEB: 3E 00
        adc     a,d                                            ;#8FED: 8A
        ld      d,a                                            ;#8FEE: 57
        ld      a,(de)                                         ;#8FEF: 1A
        ld      c,a                                            ;#8FF0: 4F
        inc     de                                             ;#8FF1: 13
        ld      a,(de)                                         ;#8FF2: 1A
        ld      b,a                                            ;#8FF3: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#8FF4: ED 43 02 E5
        inc     hl                                             ;#8FF8: 23
        ld      e,(hl)                                         ;#8FF9: 5E
        inc     hl                                             ;#8FFA: 23
        ld      d,(hl)                                         ;#8FFB: 56
        ld      a,(de)                                         ;#8FFC: 1A
        inc     de                                             ;#8FFD: 13
        ld      (hl),d                                         ;#8FFE: 72
        dec     hl                                             ;#8FFF: 2B
        ld      (hl),e                                         ;#9000: 73
        ld      (PSG_MIRROR_VOL_B),a                           ;#9001: 32 09 E5
        ret                                                    ;#9004: C9

SOUND_ENVELOPE_TABLE:
        ; Initial sound envelope/volume curve
        dh      "0B0B0B0B0B0B0A0A0909080807070707"             ;#9005: 0B 0B 0B 0B 0B 0B 0A 0A 09 09 08 08 07 07 07 07
        dh      "07070707060605050504040404030303"             ;#9015: 07 07 07 07 06 06 05 05 05 04 04 04 04 03 03 03
        dh      "03030202020202020101010101010101"             ;#9025: 03 03 02 02 02 02 02 02 01 01 01 01 01 01 01 01
        dh      "01010101010101000000000000000000"             ;#9035: 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00 00

MUSIC_THEME_DURATIONS:
        ; Sound sub-table (referenced from music tick advance)
        dh      "0A0A0909070705050000000000000000"             ;#9045: 0A 0A 09 09 07 07 05 05 00 00 00 00 00 00 00 00

SFX_SMOKE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_SMOKE)
        dh      "0C0C0C0C0C0C0C0C0C0C0C0C00000000"             ;#9055: 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 00 00 00 00

SFX_C_STAGE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BANG/5)
        dh      "0F0D0B0A0A0A0A0A0A09080706050403"             ;#9065: 0F 0D 0B 0A 0A 0A 0A 0A 0A 09 08 07 06 05 04 03
        dh      "02010000000000000000000000000000"             ;#9075: 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00

SFX_BANG_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BONUS)
        dh      "080E0D0C0B0B0B0B0B0B0B0B0B0B0B0B"             ;#9085: 08 0E 0D 0C 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B
        dh      "0A0A0A0A0A0A0A0A0A0A090909090909"             ;#9095: 0A 0A 0A 0A 0A 0A 0A 0A 0A 0A 09 09 09 09 09 09
        dh      "09090909080808080808080808080707"             ;#90A5: 09 09 09 09 08 08 08 08 08 08 08 08 08 08 07 07
        dh      "07070707070707070606060606060606"             ;#90B5: 07 07 07 07 07 07 07 07 06 06 06 06 06 06 06 06
        dh      "060605050505050505050505040302FF"             ;#90C5: 06 06 05 05 05 05 05 05 05 05 05 05 04 03 02 FF

MUSIC_THEME_VARIANT_VOICE0:
        ; Sound sub-table (referenced from music note advance)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#90D5: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90D7: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90D9: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90DB: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90DD: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90DF: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90E1: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90E3: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90E5: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90E7: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90E9: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90EB: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90ED: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#90EF: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90F1: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#90F3: 38 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#90F5: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#90F7: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#90F9: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#90FB: 2A 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#90FD: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#90FF: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#9101: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#9103: 2A 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9105: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9107: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9109: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#910B: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#910D: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#910F: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9111: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9113: 38 0C
        db      0FFh    ; substream end                        ;#9115: FF

MUSIC_THEME_VARIANT_VOICE0_2:
        ; Voice-0 2nd substream (after FF 6E05h); MUSIC_THEME_RESTART ptr
        NOTE    note=NOTE_O5_D, duration=19h                   ;#9116: 5E 19
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#9118: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#911A: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#911C: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#911E: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#9120: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#9122: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#9124: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#9126: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9128: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#912A: 4A 0C
        NOTE    note=NOTE_O4_G, duration=30h                   ;#912C: 50 30
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#912E: 4A 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9130: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#9132: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9134: 50 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#9136: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#9138: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#913A: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#913C: 54 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#913E: 58 0C
        NOTE    note=NOTE_O4_G, duration=18h                   ;#9140: 50 18
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#9142: 4A 0C
        NOTE    note=NOTE_O4_D, duration=30h                   ;#9144: 46 30

MUSIC_THEME_VARIANT_VOICE1:
        ; Sound sub-table
        NOTE    note=NOTE_O4_G, duration=0Dh                   ;#9146: 50 0D
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#9148: 4C 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#914A: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#914C: 50 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#914E: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9150: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#9152: 42 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9154: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#9156: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#9158: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#915A: 38 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#915C: 42 0C
        NOTE    note=NOTE_O3_B, duration=0Ch                   ;#915E: 40 0C
        NOTE    note=NOTE_O3_G, duration=24h                   ;#9160: 38 24
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#9162: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#9164: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9166: 38 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#9168: 34 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#916A: 38 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#916C: 3E 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#916E: 42 0C
        NOTE    note=NOTE_O4_C_SHARP, duration=0Ch             ;#9170: 44 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9172: 46 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#9174: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9176: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#9178: 42 0C
        NOTE    note=NOTE_O3_B, duration=30h                   ;#917A: 40 30
        db      4,4,0Eh    ; last note pair + orphan byte (song ends via voice-0 FF) ;#917C: 04 04 0E

SFX_FLAG_STREAM_FLAG_GET:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_C                             ;#917F: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#9180: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#9181: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#9182: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#9183: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#9184: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#9185: 78
        SINGLE_NOTE note=NOTE_O5_C                             ;#9186: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#9187: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#9188: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#9189: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#918A: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#918B: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#918C: 78

SFX_FLAG_STREAM_BASE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#918D: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#918E: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#918F: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#9190: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#9191: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#9192: 78
        SINGLE_NOTE note=NOTE_O6_F                             ;#9193: 7C
        db      0FFh    ; end of stream                        ;#9194: FF

SFX_SMOKE_STREAM:
        ; Smoke SFX note stream (SFX_SMOKE); loaded by SFX_FLAG_CHECK_SMOKE at 6ABBh
        SINGLE_NOTE note=NOTE_O2_A_SHARP                       ;#9195: 26
        SINGLE_NOTE note=NOTE_O2_B                             ;#9196: 28
        SINGLE_NOTE note=NOTE_O3_C                             ;#9197: 2A
        SINGLE_NOTE note=NOTE_O3_C_SHARP                       ;#9198: 2C
        db      0FFh    ; end of stream                        ;#9199: FF

SFX_FLAG_STREAM_FUEL_LOW:
        ; SFX sub-stream (fuel-low warning beep)
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919A: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919B: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919C: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919D: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919E: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#919F: 44
        db      0FFh    ; end of stream                        ;#91A0: FF

SFX_FLAG_STREAM_EXTRA_LIFE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O6_C                             ;#91A1: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91A2: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#91A3: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91A4: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#91A5: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91A6: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#91A7: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91A8: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#91A9: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91AA: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#91AB: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#91AC: 76
        db      0FFh    ; end of stream                        ;#91AD: FF

MUSIC_STAGE_CLEAR_STREAM_VOICE_0:
        ; Music channel C voice 0 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#91AE: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_1:
        ; Music channel C voice 1 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#91B0: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_2:
        ; Music channel C voice 2 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=9                     ;#91B2: 00 09
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#91B4: 56 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#91B6: 5E 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#91B8: 64 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#91BA: 5A 0C
        NOTE    note=NOTE_O5_D_SHARP, duration=0Ch             ;#91BC: 60 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#91BE: 5E 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=0Ch             ;#91C0: 6E 0C
        NOTE    note=NOTE_REST, duration=10h                   ;#91C2: 00 10
        db      0FFh    ; substream end                        ;#91C4: FF

SFX_BONUS_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_BONUS)
        NOTE    note=NOTE_O5_G, duration=1                     ;#91C5: 68 01
        NOTE    note=NOTE_O5_A, duration=5                     ;#91C7: 6C 05
        NOTE    note=NOTE_O5_B, duration=5                     ;#91C9: 70 05
        NOTE    note=NOTE_O6_C, duration=5                     ;#91CB: 72 05
        NOTE    note=NOTE_O6_D, duration=5                     ;#91CD: 76 05
        NOTE    note=NOTE_O6_E, duration=5                     ;#91CF: 7A 05
        NOTE    note=NOTE_O6_F_SHARP, duration=5               ;#91D1: 7E 05
        NOTE    note=NOTE_O6_G, duration=5                     ;#91D3: 80 05
        db      0FFh    ; substream end                        ;#91D5: FF

SFX_C_STAGE_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_C_STAGE)
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#91D6: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#91D8: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#91DA: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#91DC: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#91DE: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#91E0: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#91E2: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#91E4: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#91E6: 34 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#91E8: 38 06
        NOTE    note=NOTE_REST, duration=6                     ;#91EA: 00 06
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#91EC: 3E 0C
        NOTE    note=NOTE_O3_G, duration=6                     ;#91EE: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#91F0: 34 06
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#91F2: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#91F4: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#91F6: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#91F8: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#91FA: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#91FC: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#91FE: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#9200: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#9202: 34 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#9204: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#9206: 2E 06
        NOTE    note=NOTE_O2_A_SHARP, duration=0Ch             ;#9208: 26 0C
        db      0FFh    ; substream end                        ;#920A: FF

MUSIC_THEME_VOICE0_BASELINE:
        ; Music data stream (channel A track)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#920B: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#920D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#920F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9211: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9213: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9215: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9217: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9219: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#921B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#921D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#921F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9221: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9223: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9225: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9227: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9229: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#922B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#922D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#922F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9231: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9233: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9235: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9237: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9239: 38 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#923B: 16 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#923D: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#923F: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#9241: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#9243: 2E 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#9245: 16 0C
        NOTE    note=NOTE_O2_E, duration=0Ch                   ;#9247: 1A 0C
        NOTE    note=NOTE_O2_F_SHARP, duration=0Ch             ;#9249: 1E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#924B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#924D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#924F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9251: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9253: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9255: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9257: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9259: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#925B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#925D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#925F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9261: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9263: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9265: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9267: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9269: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#926B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#926D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#926F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9271: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9273: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9275: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9277: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9279: 38 0C
        NOTE    note=NOTE_O2_C, duration=1                     ;#927B: 12 01
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#927D: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#927F: 2A 0C
        NOTE    note=NOTE_O2_D, duration=1                     ;#9281: 16 01
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#9283: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#9285: 2E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#9287: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#9289: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#928B: 38 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#928D: 00 0C
        db      0FFh    ; substream end                        ;#928F: FF

MUSIC_THEME_VOICE1_BASELINE:
        ; Music data stream (channel A alt)
        NOTE    note=NOTE_O4_G, duration=0Bh                   ;#9290: 50 0B
        NOTE    note=NOTE_REST, duration=2                     ;#9292: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9294: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#9296: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9298: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#929A: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#929C: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#929E: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#92A0: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#92A2: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92A4: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#92A6: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#92A8: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92AA: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#92AC: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#92AE: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#92B0: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#92B2: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92B4: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#92B6: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#92B8: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92BA: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#92BC: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#92BE: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#92C0: 5C 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#92C2: 5E 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#92C4: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#92C6: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#92C8: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#92CA: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#92CC: 5C 06
        NOTE    note=NOTE_O5_D, duration=4                     ;#92CE: 5E 04
        NOTE    note=NOTE_REST, duration=2                     ;#92D0: 00 02
        NOTE    note=NOTE_O5_D, duration=14h                   ;#92D2: 5E 14
        NOTE    note=NOTE_REST, duration=4                     ;#92D4: 00 04
        NOTE    note=NOTE_O5_D, duration=6                     ;#92D6: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#92D8: 5A 06
        NOTE    note=NOTE_O4_B, duration=6                     ;#92DA: 58 06
        NOTE    note=NOTE_O4_A, duration=6                     ;#92DC: 54 06
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#92DE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#92E0: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92E2: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#92E4: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#92E6: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92E8: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#92EA: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#92EC: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#92EE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#92F0: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92F2: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#92F4: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#92F6: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#92F8: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#92FA: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#92FC: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#92FE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#9300: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9302: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#9304: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#9306: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9308: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#930A: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#930C: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#930E: 5C 0C
        NOTE    note=NOTE_O5_G, duration=0Ch                   ;#9310: 68 0C
        NOTE    note=NOTE_O5_D, duration=6                     ;#9312: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#9314: 5A 06
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#9316: 56 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#9318: 50 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#931A: 4C 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#931C: 4E 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#931E: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#9320: 00 0C

MUSIC_OPENING_VOICE_2:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=0Dh                   ;#9322: 5A 0D
        NOTE    note=NOTE_O5_D, duration=4                     ;#9324: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#9326: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#9328: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#932A: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#932C: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#932E: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#9330: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#9332: 64 0C
        NOTE    note=NOTE_O5_G_SHARP, duration=10h             ;#9334: 6A 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#9336: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#9338: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#933A: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#933C: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#933E: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#9340: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#9342: 64 04
        NOTE    note=NOTE_O5_A, duration=0Ch                   ;#9344: 6C 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#9346: 6E 04
        NOTE    note=NOTE_O6_C, duration=0Ch                   ;#9348: 72 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#934A: 6E 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#934C: 6A 0C
        NOTE    note=NOTE_O5_F, duration=4                     ;#934E: 64 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#9350: 6A 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#9352: 64 0C

MUSIC_OPENING_VOICE_1:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=1Dh                   ;#9354: 5A 1D
        NOTE    note=NOTE_O4_A, duration=10h                   ;#9356: 54 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#9358: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#935A: 5A 1C
        NOTE    note=NOTE_O4_G_SHARP, duration=10h             ;#935C: 52 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#935E: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#9360: 5A 1C
        NOTE    note=NOTE_O4_A, duration=10h                   ;#9362: 54 10
        NOTE    note=NOTE_O4_F, duration=10h                   ;#9364: 4C 10
        NOTE    note=NOTE_O5_C, duration=4                     ;#9366: 5A 04
        NOTE    note=NOTE_O4_G_SHARP, duration=0Ch             ;#9368: 52 0C
        NOTE    note=NOTE_O4_F, duration=4                     ;#936A: 4C 04
        NOTE    note=NOTE_O4_D_SHARP, duration=0Ch             ;#936C: 48 0C
        NOTE    note=NOTE_O4_C, duration=4                     ;#936E: 42 04
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#9370: 4A 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#9372: 4C 0C

MUSIC_OPENING_VOICE_0:
        ; Music data stream (channel B/C)
        NOTE    note=NOTE_O2_F, duration=11h                   ;#9374: 1C 11
        NOTE    note=NOTE_O3_F, duration=10h                   ;#9376: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#9378: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#937A: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#937C: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#937E: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#9380: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#9382: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#9384: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#9386: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#9388: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#938A: 34 10
        NOTE    note=NOTE_O1_A_SHARP, duration=0Ch             ;#938C: 0E 0C
        NOTE    note=NOTE_O2_A_SHARP, duration=4               ;#938E: 26 04
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#9390: 12 0C
        NOTE    note=NOTE_O3_C, duration=4                     ;#9392: 2A 04
        NOTE    note=NOTE_O2_F, duration=0Ch                   ;#9394: 1C 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#9396: 34 0C
        db      0FFh    ; substream end                        ;#9398: FF

NOTE_PERIOD_TABLE:
        ; PSG tone-period entries (73 x 2 bytes) indexed by note byte
        ; NOTE_PERIOD_TABLE — 73 entries x 2 bytes (146 bytes total). Indexed by note
        ; byte from music data streams. Each 16-bit entry is a PSG tone-period value
        ; (12-bit; high 4 bits ignored by PSG). Covers ~6 octaves of musical pitch
        ; range.
        dw      0     ; rest                                   ;#9399: 00 00
        dw      0A88h  ;    41.5 Hz  O1 E                      ;#939B: 88 0A
        dw      9F0h   ;    44.0 Hz  O1 F                      ;#939D: F0 09
        dw      960h   ;    46.6 Hz  O1 F#                     ;#939F: 60 09
        dw      8DCh   ;    49.3 Hz  O1 G                      ;#93A1: DC 08
        dw      85Ch   ;    52.3 Hz  O1 G#                     ;#93A3: 5C 08
        dw      7E4h   ;    55.4 Hz  O1 A                      ;#93A5: E4 07
        dw      770h   ;    58.8 Hz  O1 A#                     ;#93A7: 70 07
        dw      708h   ;    62.1 Hz  O1 B                      ;#93A9: 08 07
        dw      6A0h   ;    66.0 Hz  O2 C                      ;#93AB: A0 06
        dw      644h   ;    69.7 Hz  O2 C#                     ;#93AD: 44 06
        dw      5E8h   ;    74.0 Hz  O2 D                      ;#93AF: E8 05
        dw      594h   ;    78.3 Hz  O2 D#                     ;#93B1: 94 05
        dw      544h   ;    83.0 Hz  O2 E                      ;#93B3: 44 05
        dw      4F8h   ;    87.9 Hz  O2 F                      ;#93B5: F8 04
        dw      4B0h   ;    93.2 Hz  O2 F#                     ;#93B7: B0 04
        dw      46Eh   ;    98.6 Hz  O2 G                      ;#93B9: 6E 04
        dw      42Eh   ;   104.5 Hz  O2 G#                     ;#93BB: 2E 04
        dw      3F2h   ;   110.8 Hz  O2 A                      ;#93BD: F2 03
        dw      3B8h   ;   117.5 Hz  O2 A#                     ;#93BF: B8 03
        dw      384h   ;   124.3 Hz  O2 B                      ;#93C1: 84 03
        dw      350h   ;   131.9 Hz  O3 C                      ;#93C3: 50 03
        dw      322h   ;   139.5 Hz  O3 C#                     ;#93C5: 22 03
        dw      2F4h   ;   148.0 Hz  O3 D                      ;#93C7: F4 02
        dw      2CAh   ;   156.7 Hz  O3 D#                     ;#93C9: CA 02
        dw      2A2h   ;   166.0 Hz  O3 E                      ;#93CB: A2 02
        dw      27Ch   ;   175.9 Hz  O3 F                      ;#93CD: 7C 02
        dw      258h   ;   186.4 Hz  O3 F#                     ;#93CF: 58 02
        dw      237h   ;   197.3 Hz  O3 G                      ;#93D1: 37 02
        dw      217h   ;   209.1 Hz  O3 G#                     ;#93D3: 17 02
        dw      1F9h   ;   221.5 Hz  O3 A                      ;#93D5: F9 01
        dw      1DCh   ;   235.0 Hz  O3 A#                     ;#93D7: DC 01
        dw      1C2h   ;   248.6 Hz  O3 B                      ;#93D9: C2 01
        dw      1A8h   ;   263.8 Hz  O4 C                      ;#93DB: A8 01
        dw      191h   ;   279.0 Hz  O4 C#                     ;#93DD: 91 01
        dw      17Ah   ;   295.9 Hz  O4 D                      ;#93DF: 7A 01
        dw      165h   ;   313.3 Hz  O4 D#                     ;#93E1: 65 01
        dw      151h   ;   331.9 Hz  O4 E                      ;#93E3: 51 01
        dw      13Eh   ;   351.8 Hz  O4 F                      ;#93E5: 3E 01
        dw      12Ch   ;   372.9 Hz  O4 F#                     ;#93E7: 2C 01
        dw      11Bh   ;   395.3 Hz  O4 G                      ;#93E9: 1B 01
        dw      10Bh   ;   419.0 Hz  O4 G#                     ;#93EB: 0B 01
        dw      0FCh   ;   443.9 Hz  O4 A                      ;#93ED: FC 00
        dw      0EEh   ;   470.0 Hz  O4 A#                     ;#93EF: EE 00
        dw      0E1h   ;   497.2 Hz  O4 B                      ;#93F1: E1 00
        dw      0D4h   ;   527.6 Hz  O5 C                      ;#93F3: D4 00
        dw      0C8h   ;   559.3 Hz  O5 C#                     ;#93F5: C8 00
        dw      0BDh   ;   591.9 Hz  O5 D                      ;#93F7: BD 00
        dw      0B2h   ;   628.4 Hz  O5 D#                     ;#93F9: B2 00
        dw      0A8h   ;   665.8 Hz  O5 E                      ;#93FB: A8 00
        dw      9Fh    ;   703.5 Hz  O5 F                      ;#93FD: 9F 00
        dw      96h    ;   745.7 Hz  O5 F#                     ;#93FF: 96 00
        dw      8Dh    ;   793.3 Hz  O5 G                      ;#9401: 8D 00
        dw      85h    ;   841.1 Hz  O5 G#                     ;#9403: 85 00
        dw      7Eh    ;   887.8 Hz  O5 A                      ;#9405: 7E 00
        dw      77h    ;   940.0 Hz  O5 A#                     ;#9407: 77 00
        dw      70h    ;   998.8 Hz  O5 B                      ;#9409: 70 00
        dw      6Ah    ;  1055.3 Hz  O6 C                      ;#940B: 6A 00
        dw      64h    ;  1118.6 Hz  O6 C#                     ;#940D: 64 00
        dw      5Eh    ;  1190.0 Hz  O6 D                      ;#940F: 5E 00
        dw      59h    ;  1256.9 Hz  O6 D#                     ;#9411: 59 00
        dw      54h    ;  1331.7 Hz  O6 E                      ;#9413: 54 00
        dw      4Fh    ;  1416.0 Hz  O6 F                      ;#9415: 4F 00
        dw      4Bh    ;  1491.5 Hz  O6 F#                     ;#9417: 4B 00
        dw      46h    ;  1598.0 Hz  O6 G                      ;#9419: 46 00
        dw      42h    ;  1694.9 Hz  O6 G#                     ;#941B: 42 00
        dw      3Fh    ;  1775.6 Hz  O6 A                      ;#941D: 3F 00
        dw      3Bh    ;  1895.9 Hz  O6 A#                     ;#941F: 3B 00
        dw      38h    ;  1997.5 Hz  O6 B                      ;#9421: 38 00
        dw      35h    ;  2110.6 Hz  O7 C                      ;#9423: 35 00
        dw      32h    ;  2237.2 Hz  O7 C#                     ;#9425: 32 00
        dw      2Fh    ;  2380.0 Hz  O7 D                      ;#9427: 2F 00
        dw      2Ch    ;  2542.3 Hz  O7 D#                     ;#9429: 2C 00

TICK_STAGE_TIMER:
        ; Two-stage countdown: dec E0B7, on zero reload from E0BA and dec E0B8
        ; TICK_STAGE_TIMER is the two-stage countdown: dec STAGE_TIMER_INNER
        ; (STAGE_TIMER_INNER). If non-zero, return. Else reload from STAGE_TIMER_RELOAD
        ; (STAGE_TIMER_RELOAD) and dec STAGE_TIMER_OUTER. Used as a sub-frame pacing
        ; tick by various game-flow states.
        ld      hl,STAGE_TIMER_INNER                           ;#942B: 21 37 E0
        dec     (hl)                                           ;#942E: 35
        ret     nz                                             ;#942F: C0
        ld      a,(STAGE_TIMER_RELOAD)                         ;#9430: 3A 3A E0
        ld      (hl),a                                         ;#9433: 77
TICK_FUEL_REFRESH:
        ; Dec E0B8 (reload 0Ah); on rollover, refresh fuel gauge cells
        ; TICK_FUEL_REFRESH dec STAGE_TIMER_OUTER (the outer timer) with auto-reload to
        ; 0Ah. On rollover, refreshes the fuel gauge cells in VRAM via BIOS_WRTVRM if
        ; FUEL_LEVEL is in the low range. Called from DRAIN_FUEL_* variants during
        ; stage-clear bonus animation.
        ld      hl,STAGE_TIMER_OUTER                           ;#9434: 21 38 E0
        dec     (hl)                                           ;#9437: 35
        ret     nz                                             ;#9438: C0
        ld      (hl),0Ah                                       ;#9439: 36 0A
        inc     hl                                             ;#943B: 23
        ld      a,(hl)                                         ;#943C: 7E
        cp      0Ah                                            ;#943D: FE 0A
        jr      nc,FUEL_TICK_GATE_RUNOUT                       ;#943F: 30 2C
        and     a                                              ;#9441: A7
        ret     z                                              ;#9442: C8
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#9443: 21 9C 07
        ld      a,81h                                          ;#9446: 3E 81
        call    BIOS_WRTVRM                                    ;#9448: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#944B: 21 9D 07
        ld      a,81h                                          ;#944E: 3E 81
        call    BIOS_WRTVRM                                    ;#9450: CD 4D 00
        ld      hl,FUEL_LEVEL                                  ;#9453: 21 39 E0
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#9456: 3A 61 E5
        and     a                                              ;#9459: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#945A: 20 11
        ld      a,(STAGE_CLEAR_FLAG)                           ;#945C: 3A 2F E0
        and     a                                              ;#945F: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#9460: 20 0B
        ld      a,(PLAYER_DEAD_FLAG)                           ;#9462: 3A 3B E0
        and     a                                              ;#9465: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#9466: 20 05
        ld      a,1                                            ;#9468: 3E 01
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#946A: 32 61 E5
FUEL_TICK_GATE_RUNOUT:
        ; Run-out gate: arms PLAYER_MOVE_GATE when fuel-tick timer expires
        dec     (hl)                                           ;#946D: 35
        jr      nz,UPDATE_FUEL_GAUGE                           ;#946E: 20 05
        ld      a,1                                            ;#9470: 3E 01
        ld      (PLAYER_MOVE_GATE),a                           ;#9472: 32 45 E0
UPDATE_FUEL_GAUGE:
        ; Render 8-tile fuel bar from FUEL_LEVEL; LDIRVM to VRAM 04D7h + mirror 14D7h
        ; UPDATE_FUEL_GAUGE renders the fuel bar as 8 tile codes in
        ; FUEL_GAUGE_BUFFER-E1E7h then LDIRVMs them to VRAM 04D7h (and bank-2 mirror
        ; 14D7h). Multi-segment fill: EEh = full segment, E7h = empty, the partial
        ; segment uses an intermediate tile encoding the fractional fill.
        ld      hl,FUEL_GAUGE_BUFFER                           ;#9475: 21 E0 E1
        ld      de,FUEL_GAUGE_BUFFER_TAIL                      ;#9478: 11 E1 E1
        ld      bc,7                                           ;#947B: 01 07 00
        ld      (hl),40h                                       ;#947E: 36 40
        ldir                                                   ;#9480: ED B0
        ld      a,(FUEL_LEVEL)                                 ;#9482: 3A 39 E0
        sub     7                                              ;#9485: D6 07
        jr      nc,FUEL_BAR_SET_HEAD                           ;#9487: 30 06
        add     a,0EFh                                         ;#9489: C6 EF
        ld      (hl),a                                         ;#948B: 77
        jp      FUEL_BAR_UPLOAD                                ;#948C: C3 9D 94

FUEL_BAR_SET_HEAD:
        ; Set bar head tile (EEh = full segment)
        ld      (hl),0EEh                                      ;#948F: 36 EE
FUEL_BAR_FILL_LOOP:
        ; Fill bar middle with full segments via dec hl loop
        dec     hl                                             ;#9491: 2B
        sub     8                                              ;#9492: D6 08
        jr      c,FUEL_BAR_TAIL_PARTIAL                        ;#9494: 38 04
        ld      (hl),0E7h                                      ;#9496: 36 E7
        jr      FUEL_BAR_FILL_LOOP                             ;#9498: 18 F7

FUEL_BAR_TAIL_PARTIAL:
        ; Tail partial: paint a fractional segment as the bar shrinks
        add     a,0E8h                                         ;#949A: C6 E8
        ld      (hl),a                                         ;#949C: 77
FUEL_BAR_UPLOAD:
        ; LDIRVM the 8 fuel-bar tile codes to VRAM 04D7h
        LOAD_VRAM_ADDRESS de, 4D7h                             ;#949D: 11 D7 04
        ld      hl,FUEL_GAUGE_BUFFER                           ;#94A0: 21 E0 E1
        ld      bc,8                                           ;#94A3: 01 08 00
        call    BIOS_LDIRVM                                    ;#94A6: CD 5C 00
        ; fuel-gauge mirror → bank-B 14D7h
        ld      hl,FUEL_GAUGE_BUFFER                           ;#94A9: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 14D7h                            ;#94AC: 11 D7 14
        ld      bc,8                                           ;#94AF: 01 08 00
        jp      BIOS_LDIRVM                                    ;#94B2: C3 5C 00

LOAD_STAGE_PARAMS:
        ; Look up per-stage parameters from STAGE_PARAM_TABLE + STAGE_DIFFICULTY_TABLE
        ; LOAD_STAGE_PARAMS reads STAGE_PALETTE_INDEX, normalizes (stages >=14h wrap to
        ; 10h-13h), and indexes STAGE_PARAM_TABLE (4-byte records) to load
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD (reload), STAGE_DIFFICULTY_INDEX
        ; (subindex), and one more byte. Then uses STAGE_DIFFICULTY_INDEX to index
        ; STAGE_DIFFICULTY_TABLE (STAGE_DIFFICULTY_TABLE), offset by STAGE_DIFFICULTY (3
        ; difficulty tiers selected at thresholds 6 and 3), loading (ENEMY_STEP_SPEED) +
        ; (SCROLL_LIMIT_LO).
        ld      a,(STAGE_PALETTE_INDEX)                        ;#94B5: 3A 30 E0
        cp      14h                                            ;#94B8: FE 14
        jr      c,LOAD_STAGE_LOOKUP                            ;#94BA: 38 04
        and     3                                              ;#94BC: E6 03
        add     a,10h                                          ;#94BE: C6 10
LOAD_STAGE_LOOKUP:
        ; Lookup row: index STAGE_PARAM_TABLE by (palette*4) and read 4 fields
        dec     a                                              ;#94C0: 3D
        add     a,a                                            ;#94C1: 87
        add     a,a                                            ;#94C2: 87
        ld      c,a                                            ;#94C3: 4F
        ld      b,0                                            ;#94C4: 06 00
        ld      hl,STAGE_PARAM_TABLE                           ;#94C6: 21 12 95
        add     hl,bc                                          ;#94C9: 09
        ld      a,(hl)                                         ;#94CA: 7E
        ld      (ROCK_SPAWN_COUNT),a                           ;#94CB: 32 1C E0
        inc     hl                                             ;#94CE: 23
        ld      a,(hl)                                         ;#94CF: 7E
        ld      (STAGE_ENEMY_SEED_LEN),a                       ;#94D0: 32 40 E0
        inc     hl                                             ;#94D3: 23
        ld      a,(hl)                                         ;#94D4: 7E
        ld      (STAGE_TIMER_RELOAD),a                         ;#94D5: 32 3A E0
        inc     hl                                             ;#94D8: 23
        ld      a,(hl)                                         ;#94D9: 7E
        ld      (STAGE_DIFFICULTY_INDEX),a                     ;#94DA: 32 3F E0
LOAD_STAGE_DIFFICULTY_TIER:
        ; Choose difficulty tier based on STAGE_DIFFICULTY (>=6 / >=3 / else)
        ld      a,(STAGE_DIFFICULTY_INDEX)                     ;#94DD: 3A 3F E0
        push    hl                                             ;#94E0: E5
        ld      hl,STAGE_DIFFICULTY_TABLE                      ;#94E1: 21 5E 95
        add     a,l                                            ;#94E4: 85
        ld      l,a                                            ;#94E5: 6F
        ld      a,0                                            ;#94E6: 3E 00
        adc     a,h                                            ;#94E8: 8C
        ld      h,a                                            ;#94E9: 67
        ld      a,(STAGE_DIFFICULTY)                           ;#94EA: 3A 2E E0
        cp      6                                              ;#94ED: FE 06
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#94EF: 30 0C
        inc     hl                                             ;#94F1: 23
        inc     hl                                             ;#94F2: 23
        inc     hl                                             ;#94F3: 23
        inc     hl                                             ;#94F4: 23
        cp      3                                              ;#94F5: FE 03
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#94F7: 30 04
        inc     hl                                             ;#94F9: 23
        inc     hl                                             ;#94FA: 23
        inc     hl                                             ;#94FB: 23
        inc     hl                                             ;#94FC: 23
LOAD_STAGE_READ_PARAMS:
        ; Read 4 bytes into (ENEMY_STEP_SPEED) and (SCROLL_LIMIT_LO) as two 16-bit pairs
        ld      a,(hl)                                         ;#94FD: 7E
        ld      (ENEMY_STEP_SPEED),a                           ;#94FE: 32 41 E0
        inc     hl                                             ;#9501: 23
        ld      a,(hl)                                         ;#9502: 7E
        ld      (ENEMY_STEP_SPEED_HI),a                        ;#9503: 32 42 E0
        inc     hl                                             ;#9506: 23
        ld      a,(hl)                                         ;#9507: 7E
        ld      (SCROLL_LIMIT_LO),a                            ;#9508: 32 43 E0
        inc     hl                                             ;#950B: 23
        ld      a,(hl)                                         ;#950C: 7E
        ld      (SCROLL_LIMIT_HI),a                            ;#950D: 32 44 E0
        pop     hl                                             ;#9510: E1
        ret                                                    ;#9511: C9

STAGE_PARAM_TABLE:
        ; Per-stage 4-byte records: stage N indexes (N-1)*4 (stages >=14h wrap to 10h-13h)
        ; STAGE_PARAM_TABLE has 19 stage records of 4 bytes each. Stage N (N=1..19)
        ; reads bytes (N-1)*4..(N-1)*4+3 → loaded into ROCK_SPAWN_ COUNT,
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD, and STAGE_DIFFICULTY_INDEX. Stages
        ; 0x14h and above wrap to entries 0x10h..0x13h (4-stage cycle).
        STAGE_PARAMS rocks=0, enemies=2, reload=9, difficulty=0  ;#9512: 00 20 09 00
        STAGE_PARAMS rocks=2, enemies=3, reload=9, difficulty=1  ;#9516: 02 30 09 0C
        STAGE_PARAMS rocks=5, enemies=7, reload=7, difficulty=2  ;#951A: 05 70 07 18
        STAGE_PARAMS rocks=4, enemies=3, reload=8, difficulty=3  ;#951E: 04 30 08 24
        STAGE_PARAMS rocks=5, enemies=4, reload=8, difficulty=4  ;#9522: 05 40 08 30
        STAGE_PARAMS rocks=6, enemies=5, reload=7, difficulty=5  ;#9526: 06 50 07 3C
        STAGE_PARAMS rocks=7, enemies=7, reload=7, difficulty=6  ;#952A: 07 70 07 48
        STAGE_PARAMS rocks=5, enemies=5, reload=7, difficulty=7  ;#952E: 05 50 07 54
        STAGE_PARAMS rocks=6, enemies=5, reload=6, difficulty=8  ;#9532: 06 50 06 60
        STAGE_PARAMS rocks=7, enemies=5, reload=6, difficulty=9  ;#9536: 07 50 06 6C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#953A: 0A 70 06 78
        STAGE_PARAMS rocks=6, enemies=6, reload=6, difficulty=11  ;#953E: 06 60 06 84
        STAGE_PARAMS rocks=7, enemies=6, reload=6, difficulty=12  ;#9542: 07 60 06 90
        STAGE_PARAMS rocks=8, enemies=7, reload=6, difficulty=13  ;#9546: 08 70 06 9C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#954A: 0A 70 06 78
        STAGE_PARAMS rocks=8, enemies=7, reload=5, difficulty=13  ;#954E: 08 70 05 9C
        STAGE_PARAMS rocks=9, enemies=7, reload=5, difficulty=14  ;#9552: 09 70 05 A8
        STAGE_PARAMS rocks=10, enemies=7, reload=5, difficulty=14  ;#9556: 0A 70 05 A8
        STAGE_PARAMS rocks=12, enemies=7, reload=5, difficulty=15  ;#955A: 0C 70 05 B4

STAGE_DIFFICULTY_TABLE:
        ; 16 records x 12 bytes (3 tiers x 4 bytes); STAGE_DIFFICULTY_TABLE..730Dh
        ; STAGE_DIFFICULTY_TABLE has 16 stage records, each containing 3 difficulty
        ; tiers (4 bytes each = 12 bytes per record, 192 total). LOAD_STAGE_PARAMS uses
        ; STAGE_DIFFICULTY against thresholds 6 and 3 to pick the tier — enemies get
        ; faster/smarter at later stages. STAGE_DIFFICULTY_INDEX selects which record to
        ; use and ranges 0..180 in steps of 12.
        dh      "00030003200300032003000320030003"             ;#955E: 00 03 00 03 20 03 00 03 20 03 00 03 20 03 00 03
        dh      "30030003300300030000000400000004"             ;#956E: 30 03 00 03 30 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004200300034003000340030003"             ;#957E: 00 00 00 04 20 03 00 03 40 03 00 03 40 03 00 03
        dh      "40030003500300035003000350030003"             ;#958E: 40 03 00 03 50 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003600300030000000400000004"             ;#959E: 60 03 00 03 60 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#95AE: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "50030003600300036003000350030003"             ;#95BE: 50 03 00 03 60 03 00 03 60 03 00 03 50 03 00 03
        dh      "70030003700300030000000400000004"             ;#95CE: 70 03 00 03 70 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#95DE: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003700300037003000370030003"             ;#95EE: 60 03 00 03 70 03 00 03 70 03 00 03 70 03 00 03
        dh      "70030003700300038003000380030003"             ;#95FE: 70 03 00 03 70 03 00 03 80 03 00 03 80 03 00 03
        dh      "80030003000000040000000400000004"             ;#960E: 80 03 00 03 00 00 00 04 00 00 00 04 00 00 00 04

PADDING:
        ; 1506 bytes of 0FFh padding before MAZE_BITMAP_0 (second 8KB)
        ds      1506, 0FFh                                     ;#961E

MAZE_BITMAP_0:
        ; 224-byte wall bitmap for maze 0 (stages 0..3, 16..19, ...)
        ; 4 mazes x 256 bytes (1024 bytes total). Per maze: - bytes 00..DFh: 32 x 56
        ; cell wall bitmap (LOOKUP_PLAYFIELD_CELL computes byte_offset = (4*L) | ((H>>3)
        ; & 3); bit pos = 7-(H&7)). - bytes E0..FFh: 16 (X, Y) rock-spawn candidate
        ; pairs picked by SCROLL_ROCKS_PICK_POSITION via a random byte index. The maze
        ; for stage N is selected by (STAGE_PALETTE_INDEX>>2) & 3.
        dh      "0001FE0077D81EFE77D81E00000000EE"             ;#9C00: 00 01 FE 00 77 D8 1E FE 77 D8 1E 00 00 00 00 EE
        dh      "7EF81EEE0001DE000FD7DEFE20570000"             ;#9C10: 7E F8 1E EE 00 01 DE 00 0F D7 DE FE 20 57 00 00
        dh      "2F5777FD285770052B5074052B5775F5"             ;#9C20: 2F 57 77 FD 28 57 70 05 2B 50 74 05 2B 57 75 F5
        dh      "685775F56BD004050817673D6BF7673D"             ;#9C30: 68 57 75 F5 6B D0 04 05 08 17 67 3D 6B F7 67 3D
        dh      "6007673D7FF700010300003B7B7F3F3B"             ;#9C40: 60 07 67 3D 7F F7 00 01 03 00 00 3B 7B 7F 3F 3B
        dh      "78073F037B77033903703339BF7F333D"             ;#9C50: 78 07 3F 03 7B 77 03 39 03 70 33 39 BF 7F 33 3D
        dh      "80003001BF7F3F3DBF7F3F3D80000001"             ;#9C60: 80 00 30 01 BF 7F 3F 3D BF 7F 3F 3D 80 00 00 01
        dh      "BB7B3B3DBB7B3B3DBB600331BB6B3B35"             ;#9C70: BB 7B 3B 3D BB 7B 3B 3D BB 60 03 31 BB 6B 3B 35
        dh      "80033835B77B0304377B3B3E001B3B3E"             ;#9C80: 80 03 38 35 B7 7B 03 04 37 7B 3B 3E 00 1B 3B 3E
        dh      "3DC000003DC000000076EF363776EF36"             ;#9C90: 3D C0 00 00 3D C0 00 00 00 76 EF 36 37 76 EF 36
        dh      "37700F363776E03030060B3637DEEB36"             ;#9CA0: 37 70 0F 36 37 76 E0 30 30 06 0B 36 37 DE EB 36
        dh      "37DEEB3600000806DDBEEB36DDBEEB36"             ;#9CB0: 37 DE EB 36 00 00 08 06 DD BE EB 36 DD BE EB 36
        dh      "C0000336DDAAAB36DDAAAB000C2AA83E"             ;#9CC0: C0 00 03 36 DD AA AB 36 DD AA AB 00 0C 2A A8 3E
        dh      "61AAAB3E6FAAAB066FAAAB3600000030"             ;#9CD0: 61 AA AB 3E 6F AA AB 06 6F AA AB 36 00 00 00 30

ROCK_POSITIONS_0:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 0
        ROCK_POSITION x=0Bh, y=5                               ;#9CE0: 0B 05
        ROCK_POSITION x=17h, y=5                               ;#9CE2: 17 05
        ROCK_POSITION x=17h, y=5                               ;#9CE4: 17 05
        ROCK_POSITION x=15h, y=9                               ;#9CE6: 15 09
        ROCK_POSITION x=15h, y=9                               ;#9CE8: 15 09
        ROCK_POSITION x=1, y=0Eh                               ;#9CEA: 01 0E
        ROCK_POSITION x=1, y=0Eh                               ;#9CEC: 01 0E
        ROCK_POSITION x=5, y=0Fh                               ;#9CEE: 05 0F
        ROCK_POSITION x=18h, y=11h                             ;#9CF0: 18 11
        ROCK_POSITION x=18h, y=11h                             ;#9CF2: 18 11
        ROCK_POSITION x=6, y=14h                               ;#9CF4: 06 14
        ROCK_POSITION x=14h, y=16h                             ;#9CF6: 14 16
        ROCK_POSITION x=11h, y=1Bh                             ;#9CF8: 11 1B
        ROCK_POSITION x=0Bh, y=20h                             ;#9CFA: 0B 20
        ROCK_POSITION x=1, y=23h                               ;#9CFC: 01 23
        ROCK_POSITION x=1Ch, y=2Bh                             ;#9CFE: 1C 2B

MAZE_BITMAP_1:
        ; 224-byte wall bitmap for maze 1 (stages 4..7)
        dh      "FFF80000800AAFDEBDEAAFDEA02AA002"             ;#9D00: FF F8 00 00 80 0A AF DE BD EA AF DE A0 2A A0 02
        dh      "ADAAAEDAA8AAAEDAA8A80000AAAADBFA"             ;#9D10: AD AA AE DA A8 AA AE DA A8 A8 00 00 AA AA DB FA
        dh      "AAAADA028A82DAFAAAAADA82A8A8003A"             ;#9D20: AA AA DA 02 8A 82 DA FA AA AA DA 82 A8 A8 00 3A
        dh      "A8AADA82ADAADAFAA02ADA02BDEADBFA"             ;#9D30: A8 AA DA 82 AD AA DA FA A0 2A DA 02 BD EA DB FA
        dh      "80080000FDFADB7A0002DB7AADEEC002"             ;#9D40: 80 08 00 00 FD FA DB 7A 00 02 DB 7A AD EE C0 02
        dh      "ADEEFBDAADEEFBDAADEEFBDA200003DA"             ;#9D50: AD EE FB DA AD EE FB DA AD EE FB DA 20 00 03 DA
        dh      "2EF7E0002EC1000020DD7BBE2EDD7BBE"             ;#9D60: 2E F7 E0 00 2E C1 00 00 20 DD 7B BE 2E DD 7B BE
        dh      "2EDC7BBE000071B02E7C75B62E7C75B6"             ;#9D70: 2E DC 7B BE 00 00 71 B0 2E 7C 75 B6 2E 7C 75 B6
        dh      "281C0006081C75B6299C75B6299C71B0"             ;#9D80: 28 1C 00 06 08 1C 75 B6 29 9C 75 B6 29 9C 71 B0
        dh      "28007BBE2FEC7BBE000C78006DAC7BFE"             ;#9D90: 28 00 7B BE 2F EC 7B BE 00 0C 78 00 6D AC 7B FE
        dh      "6DA00300000EDB766DAE18066DAEFBFE"             ;#9DA0: 6D A0 03 00 00 0E DB 76 6D AE 18 06 6D AE FB FE
        dh      "002000006DAEEFBB6DAEEFBB000003BB"             ;#9DB0: 00 20 00 00 6D AE EF BB 6D AE EF BB 00 00 03 BB
        dh      "EF6AA800EF2AABBEEFAAA80001AAABF6"             ;#9DC0: EF 6A A8 00 EF 2A AB BE EF AA A8 00 01 AA AB F6
        dh      "6DAAAA066C0002F66DBEFAF600000000"             ;#9DD0: 6D AA AA 06 6C 00 02 F6 6D BE FA F6 00 00 00 00

ROCK_POSITIONS_1:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 1
        ROCK_POSITION x=18h, y=3                               ;#9DE0: 18 03
        ROCK_POSITION x=16h, y=0Bh                             ;#9DE2: 16 0B
        ROCK_POSITION x=1Fh, y=0Bh                             ;#9DE4: 1F 0B
        ROCK_POSITION x=14h, y=10h                             ;#9DE6: 14 10
        ROCK_POSITION x=14h, y=10h                             ;#9DE8: 14 10
        ROCK_POSITION x=1, y=18h                               ;#9DEA: 01 18
        ROCK_POSITION x=1, y=18h                               ;#9DEC: 01 18
        ROCK_POSITION x=16h, y=20h                             ;#9DEE: 16 20
        ROCK_POSITION x=16h, y=20h                             ;#9DF0: 16 20
        ROCK_POSITION x=1Fh, y=20h                             ;#9DF2: 1F 20
        ROCK_POSITION x=0Ch, y=24h                             ;#9DF4: 0C 24
        ROCK_POSITION x=1Ah, y=28h                             ;#9DF6: 1A 28
        ROCK_POSITION x=3, y=29h                               ;#9DF8: 03 29
        ROCK_POSITION x=17h, y=30h                             ;#9DFA: 17 30
        ROCK_POSITION x=7, y=35h                               ;#9DFC: 07 35
        ROCK_POSITION x=7, y=35h                               ;#9DFE: 07 35

MAZE_BITMAP_2:
        ; 224-byte wall bitmap for maze 2 (stages 8..11)
        dh      "00000E003F7AAEEE207AA0E0207AAEEE"             ;#9E00: 00 00 0E 00 3F 7A AE EE 20 7A A0 E0 20 7A AE EE
        dh      "2002AE0E3FDAAFBE0FD80FBE2FDEE000"             ;#9E10: 20 02 AE 0E 3F DA AF BE 0F D8 0F BE 2F DE E0 00
        dh      "2000EFB22DDEEFB22DDE003201DEAFB2"             ;#9E20: 20 00 EF B2 2D DE EF B2 2D DE 00 32 01 DE AF B2
        dh      "7DDEAFB27DC0AFB07DDEAC027DDE2DF2"             ;#9E30: 7D DE AF B2 7D C0 AF B0 7D DE AC 02 7D DE 2D F2
        dh      "001EADF27DDEADF27DDEADF27DC00000"             ;#9E40: 00 1E AD F2 7D DE AD F2 7D DE AD F2 7D C0 00 00
        dh      "7DF60F6C6037FF6C6734016D07059D6D"             ;#9E50: 7D F6 0F 6C 60 37 FF 6C 67 34 01 6D 07 05 9D 6D
        dh      "603401617DF59D7D7DF4017D7DF79F01"             ;#9E60: 60 34 01 61 7D F5 9D 7D 7D F4 01 7D 7D F7 9F 01
        dh      "00079F7D00079F7D6DB000006DB00000"             ;#9E70: 00 07 9F 7D 00 07 9F 7D 6D B0 00 00 6D B0 00 00
        dh      "6DB7DEFE0D87DEFE7DEFDE1E7DEF06DE"             ;#9E80: 6D B7 DE FE 0D 87 DE FE 7D EF DE 1E 7D EF 06 DE
        dh      "000076C67DEF70F67DEF06F00D8F76FE"             ;#9E90: 00 00 76 C6 7D EF 70 F6 7D EF 06 F0 0D 8F 76 FE
        dh      "6DB876FE6D8300006DB77BDE60377BDE"             ;#9EA0: 6D B8 76 FE 6D 83 00 00 6D B7 7B DE 60 37 7B DE
        dh      "7D801BDE7DAED800002EDBFE7FA00000"             ;#9EB0: 7D 80 1B DE 7D AE D8 00 00 2E DB FE 7F A0 00 00
        dh      "7FAAABBE702AAA2077AAAAAA07AAAAAA"             ;#9EC0: 7F AA AB BE 70 2A AA 20 77 AA AA AA 07 AA AA AA
        dh      "7FAAAAAA7000028277BFBAFA00000000"             ;#9ED0: 7F AA AA AA 70 00 02 82 77 BF BA FA 00 00 00 00

ROCK_POSITIONS_2:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 2
        ROCK_POSITION x=1Bh, y=2                               ;#9EE0: 1B 02
        ROCK_POSITION x=8, y=3                                 ;#9EE2: 08 03
        ROCK_POSITION x=8, y=3                                 ;#9EE4: 08 03
        ROCK_POSITION x=0Ch, y=8                               ;#9EE6: 0C 08
        ROCK_POSITION x=0, y=0Ah                               ;#9EE8: 00 0A
        ROCK_POSITION x=1Eh, y=0Dh                             ;#9EEA: 1E 0D
        ROCK_POSITION x=11h, y=0Eh                             ;#9EEC: 11 0E
        ROCK_POSITION x=11h, y=0Eh                             ;#9EEE: 11 0E
        ROCK_POSITION x=6, y=13h                               ;#9EF0: 06 13
        ROCK_POSITION x=1Eh, y=14h                             ;#9EF2: 1E 14
        ROCK_POSITION x=0Ch, y=21h                             ;#9EF4: 0C 21
        ROCK_POSITION x=0Ch, y=21h                             ;#9EF6: 0C 21
        ROCK_POSITION x=14h, y=25h                             ;#9EF8: 14 25
        ROCK_POSITION x=14h, y=25h                             ;#9EFA: 14 25
        ROCK_POSITION x=1Ch, y=2Dh                             ;#9EFC: 1C 2D
        ROCK_POSITION x=7, y=2Eh                               ;#9EFE: 07 2E

MAZE_BITMAP_3:
        ; 224-byte wall bitmap for maze 3 (stages 12..15)
        dh      "000000007F781DFE1F781DFE4F781C00"             ;#9F00: 00 00 00 00 7F 78 1D FE 1F 78 1D FE 4F 78 1C 00
        dh      "677A5EF4701A5EF47BDA5EF47B824074"             ;#9F10: 67 7A 5E F4 70 1A 5E F4 7B DA 5E F4 7B 82 40 74
        dh      "7BBA5F747B9A5F7403DA5F7477D81F04"             ;#9F20: 7B BA 5F 74 7B 9A 5F 74 03 DA 5F 74 77 D8 1F 04
        dh      "701E7FB47DDE7FB47DD00FB47DD00FB0"             ;#9F30: 70 1E 7F B4 7D DE 7F B4 7D D0 0F B4 7D D0 0F B0
        dh      "7DD3CFBC0003C0000003C05EDDF3CD1E"             ;#9F40: 7D D3 CF BC 00 03 C0 00 00 03 C0 5E DD F3 CD 1E
        dh      "DDF00DDEDDF00842001E7B7ADDDE6300"             ;#9F50: DD F0 0D DE DD F0 08 42 00 1E 7B 7A DD DE 63 00
        dh      "DDDE6FDADDDE6E1AC0006EFADDD66EFA"             ;#9F60: DD DE 6F DA DD DE 6E 1A C0 00 6E FA DD D6 6E FA
        dh      "DDD66EFA0DD66EFA600000F0600E6EF6"             ;#9F70: DD D6 6E FA 0D D6 6E FA 60 00 00 F0 60 0E 6E F6
        dh      "6FEE6EF0202E6EF7272E6C37202E6D87"             ;#9F80: 6F EE 6E F0 20 2E 6E F7 27 2E 6C 37 20 2E 6D 87
        dh      "2F206DBF012E01BF2D2E6C002D2E6DBE"             ;#9F90: 2F 20 6D BF 01 2E 01 BF 2D 2E 6C 00 2D 2E 6D BE
        dh      "252E6DB8352E603A352E6DBA712E6D80"             ;#9FA0: 25 2E 6D B8 35 2E 60 3A 35 2E 6D BA 71 2E 6D 80
        dh      "7D2E6FBE7D2E6FA24000000A552AAB6A"             ;#9FB0: 7D 2E 6F BE 7D 2E 6F A2 40 00 00 0A 55 2A AB 6A
        dh      "552AAB6A152AAB62752AAB6A052AAB6A"             ;#9FC0: 55 2A AB 6A 15 2A AB 62 75 2A AB 6A 05 2A AB 6A
        dh      "7D20036A7D2FFB600120007E00000000"             ;#9FD0: 7D 20 03 6A 7D 2F FB 60 01 20 00 7E 00 00 00 00

ROCK_POSITIONS_3:
        ; 16 (X,Y) rock-spawn candidate pairs for maze 3
        ROCK_POSITION x=1Fh, y=4                               ;#9FE0: 1F 04
        ROCK_POSITION x=1Fh, y=4                               ;#9FE2: 1F 04
        ROCK_POSITION x=1Fh, y=0Fh                             ;#9FE4: 1F 0F
        ROCK_POSITION x=18h, y=11h                             ;#9FE6: 18 11
        ROCK_POSITION x=18h, y=11h                             ;#9FE8: 18 11
        ROCK_POSITION x=6, y=14h                               ;#9FEA: 06 14
        ROCK_POSITION x=10h, y=16h                             ;#9FEC: 10 16
        ROCK_POSITION x=10h, y=16h                             ;#9FEE: 10 16
        ROCK_POSITION x=0Bh, y=1Eh                             ;#9FF0: 0B 1E
        ROCK_POSITION x=0Fh, y=21h                             ;#9FF2: 0F 21
        ROCK_POSITION x=0, y=22h                               ;#9FF4: 00 22
        ROCK_POSITION x=8, y=23h                               ;#9FF6: 08 23
        ROCK_POSITION x=8, y=23h                               ;#9FF8: 08 23
        ROCK_POSITION x=17h, y=26h                             ;#9FFA: 17 26
        ROCK_POSITION x=17h, y=36h                             ;#9FFC: 17 36
        ROCK_POSITION x=5, y=37h                               ;#9FFE: 05 37
        dephase

END_POINTER:
        end
