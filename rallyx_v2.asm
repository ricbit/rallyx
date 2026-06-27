; Rally-X (MSX, Namcot, second release, 1984)
; Disassembled by Ricardo Bittencourt (bluepenguin@gmail.com)
; Last update at 2026-06-27
;
	output "rallyx_v2.rom"
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
STAGE_TIMER_INNER                equ     0E037h    ; Inner tick counter; resets to STAGE_TIMER_RELOAD on rollover
STAGE_TIMER_OUTER                equ     0E038h    ; Outer countdown decremented by TICK_STAGE_TIMER and TICK_FUEL_REFRESH
FUEL_LEVEL                       equ     0E039h    ; Depletes by 3 per smoke; UPDATE_FUEL_GAUGE renders it as a tile bar
STAGE_TIMER_RELOAD               equ     0E03Ah    ; Reload value for STAGE_TIMER_INNER when it hits zero
PLAYER_DEAD_FLAG                 equ     0E03Bh    ; Non-zero ⇒ trigger death sequence (jp DEATH_SEQUENCE from frame check)
SAVED_TIMER_FOR_DEATH            equ     0E03Ch    ; Backup of (STAGE_TIMER_OUTER, FUEL_LEVEL) preserved across DEATH_SEQUENCE
EXTRA_LIFE_AWARDED               equ     0E03Eh    ; Flag: set by CHECK_SCORE_MILESTONE to avoid awarding the same extra life twice
STAGE_DIFFICULTY_INDEX           equ     0E03Fh    ; Per-stage sub-index; offsets into STAGE_DIFFICULTY_TABLE in LOAD_STAGE_PARAMS
STAGE_ENEMY_SEED_LEN             equ     0E040h    ; INIT_ENEMY_CARS seed-copy length in bytes (cars*16)
ENEMY_STEP_SPEED                 equ     0E041h    ; Per-stage enemy step velocity (8.8); added to position accumulator each tick
ENEMY_STEP_SPEED_HI              equ     0E042h    ; High byte of the ENEMY_STEP_SPEED 16-bit pair; read only as part of it
SCROLL_LIMIT_LO                  equ     0E043h    ; Low byte of forward-scroll cap; PLAYFIELD_SCROLL_OFFSET stops advancing at this
SCROLL_LIMIT_HI                  equ     0E044h    ; High byte of forward-scroll cap (paired with SCROLL_LIMIT_LO)
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
BIOS_RDVDP                       equ     0013Eh    ; Read VDP status S#0; acknowledges VBLANK IRQ
BIOS_SNSMAT                      equ     00141h    ; Scan keyboard matrix row A; returns inverted bits in A
BIOS_H_TIMI                      equ     0FD9Ah    ; Timer-interrupt hook (5-byte JP slot called every VBLANK)
STACK                            equ     0FFFFh    ; Stack top — GAME_BOOT and VBLANK_HANDLER set SP here (F380h)
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
;   E100-E4FF object tables: FLAG_TABLE/ROCK_TABLE/ENEMY_CAR_TABLE/SMOKE_TRAIL_TABLE,
;   E500-E5FF PSG mirror + sound subsystem state,
;   EA00-EAFF RADAR_GRID + OBSTACLE_GRID,
;   EB00-EBxx SAT_MIRROR,
;   EC00-EF83 TRACK_DATA_RING,
;   F400-FBxx PLAYFIELD_LOOKUP_TABLE + OUT_OF_BOUNDS, stack top at FFFFh.
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
        ; Cart title: length byte 09h + "newRALLYX"
        db      9, "newRALLYX"                                 ;#4010: 09 6E 65 77 52 41 4C ...

GAME_BOOT:
        ; Entry point for ROM startup (init vector from header)
        ; place stack just below the RDPRIM BIOS routine
        ld      sp,STACK                                       ;#401A: 31 FF FF
        di                                                     ;#401D: F3
        call    INIT_VDP_AND_LOAD_GFX                          ;#401E: CD 04 4D
        ld      hl,VBLANK_HANDLER                              ;#4021: 21 51 40
        ; opcode for JP nnnn, written into BIOS_H_TIMI
        ld      a,Z80_JP                                       ;#4024: 3E C3
        ld      (BIOS_H_TIMI),a                                ;#4026: 32 9A FD
        ld      (BIOS_H_TIMI+1),hl                             ;#4029: 22 9B FD
        ld      hl,TEMP_SPACE                                  ;#402C: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#402F: 11 01 E0
        ld      bc,6FFh                                        ;#4032: 01 FF 06
        ld      (hl),0                                         ;#4035: 36 00
        ldir                                                   ;#4037: ED B0
        ld      hl,INITIAL_STATE_HANDLER                       ;#4039: 21 69 43
        ld      (STATE_HANDLER_VECTOR),hl                      ;#403C: 22 05 E0
        call    LOAD_PLAYFIELD_GFX                             ;#403F: CD 50 65
REFRESH_RNG_AND_SOUND:
        ; Tail of GAME_BOOT: stir RNG, then fall into FINISH_FRAME_AND_WAIT
        call    NEXT_RANDOM                                    ;#4042: CD E5 54
FINISH_FRAME_AND_WAIT:
        ; Tail used by GAME_BOOT and WAIT_VBLANK: call UPDATE_SOUND, ei, R1=E2h, halt
        call    UPDATE_SOUND                                   ;#4045: CD D2 68
        ei                                                     ;#4048: FB
        ; enable screen + IRQs + 16x16 sprites
        ld      bc,ROCK_TABLE_TAIL                             ;#4049: 01 01 E2
        call    BIOS_WRTVDP                                    ;#404C: CD 47 00
WAIT_FIRST_VBLANK:
        ; Tight `jr $` loop waiting for first VBLANK after boot
        jr      WAIT_FIRST_VBLANK                              ;#404F: 18 FE

VBLANK_HANDLER:
        ; Per-frame main loop, hooked into H.TIMI by GAME_BOOT
        ; VBLANK_HANDLER is reached via the BIOS_H_TIMI hook installed at GAME_BOOT. The
        ; SP is reset on every entry so the previous frame's stack is discarded —
        ; combined with the WAIT_VBLANK_* coroutine yield, this means state handlers can
        ; "block" by simply jumping into FINISH_FRAME_AND_ WAIT after saving their
        ; resume point in STATE_HANDLER_VECTOR.
        ld      sp,STACK                                       ;#4051: 31 FF FF
        call    BIOS_RDVDP                                     ;#4054: CD 3E 01
        call    CHECK_PAUSE_KEY                                ;#4057: CD D6 40
        ld      a,(PAUSE_FLAG)                                 ;#405A: 3A 48 E0
        and     a                                              ;#405D: A7
        jr      z,VBLANK_GAME_FRAME                            ;#405E: 28 06
        call    SILENCE_PSG                                    ;#4060: CD C1 40
        ei                                                     ;#4063: FB
PAUSE_HALT_LOOP:
        ; Tight `jr $` loop while PAUSE_FLAG is set (PSG already silenced)
        jr      PAUSE_HALT_LOOP                                ;#4064: 18 FE

VBLANK_GAME_FRAME:
        ; Non-paused branch of VBLANK_HANDLER; runs per-frame game work
        ; VBLANK_GAME_FRAME runs the non-paused per-frame work: increments
        ; VBLANK_PARITY, gates VDP-bank swap (R4 between 01/03 via VRAM_BANK_FLAG and R2
        ; between 01/05 via NAME_BANK_FLAG), updates FRAME_TICK, refreshes the SAT
        ; mirror to VRAM 0700h, then jumps to STATE_HANDLER_VECTOR.
        ld      hl,VBLANK_PARITY                               ;#4066: 21 36 E0
        inc     (hl)                                           ;#4069: 34
        ld      a,(hl)                                         ;#406A: 7E
        rra                                                    ;#406B: 1F
        jr      nc,REFRESH_RNG_AND_SOUND                       ;#406C: 30 D4
        ld      a,(VRAM_BANK_FLAG)                             ;#406E: 3A 46 E0
        rra                                                    ;#4071: 1F
        jr      c,VBLANK_GAME_FRAME_R4_BANK_A                  ;#4072: 38 08
        ; R4=3 → pattern table bank B (1800h)
        ld      bc,304h                                        ;#4074: 01 04 03
        call    BIOS_WRTVDP                                    ;#4077: CD 47 00
        jr      VBLANK_GAME_FRAME_R1_WRITE                     ;#407A: 18 06

VBLANK_GAME_FRAME_R4_BANK_A:
        ; Bank-A path: VDP R4 = 01 (patterns at 0800h)
        ; R4=1 → pattern table bank A (0800h)
        ld      bc,104h                                        ;#407C: 01 04 01
        call    BIOS_WRTVDP                                    ;#407F: CD 47 00
VBLANK_GAME_FRAME_R1_WRITE:
        ; After R4 select, write R1 = C2h (display enable + VBLANK IRQ)
        ; R1=C2h → screen on, IRQ off (mid-frame state)
        ld      bc,0C201h                                      ;#4082: 01 01 C2
        call    BIOS_WRTVDP                                    ;#4085: CD 47 00
        ld      bc,102h                                        ;#4088: 01 02 01
        ld      a,(NAME_BANK_FLAG)                             ;#408B: 3A 0E E0
        and     a                                              ;#408E: A7
        jr      z,VBLANK_GAME_FRAME_R2_WRITE                   ;#408F: 28 03
        ; R2=5 → name table bank B (1400h)
        ld      bc,502h                                        ;#4091: 01 02 05
VBLANK_GAME_FRAME_R2_WRITE:
        ; Apply chosen R2 value (01h or 05h) to switch name-table bank
        call    BIOS_WRTVDP                                    ;#4094: CD 47 00
        ld      hl,FRAME_TICK                                  ;#4097: 21 07 E0
        inc     (hl)                                           ;#409A: 34
        ld      hl,SAT_MIRROR                                  ;#409B: 21 00 EB
        ld      (SAT_MIRROR_CURSOR),hl                         ;#409E: 22 14 E0
        LOAD_VRAM_ADDRESS de, 700h                             ;#40A1: 11 00 07
        ld      bc,80h                                         ;#40A4: 01 80 00
        call    BIOS_LDIRVM                                    ;#40A7: CD 5C 00
        ld      hl,(STATE_HANDLER_VECTOR)                      ;#40AA: 2A 05 E0
        jp      (hl)                                           ;#40AD: E9

WAIT_VBLANK_FINISH_SPRITES:
        ; Yield: save PC into STATE_HANDLER_VECTOR, terminate SAT, wait for VBLANK
        ; WAIT_VBLANK_FINISH_SPRITES and WAIT_VBLANK implement the coroutine yield
        ; idiom: `pop hl` grabs the caller's return address, stores it in
        ; STATE_HANDLER_VECTOR, then `jp FINISH_FRAME_AND_WAIT` (=FINISH_FRAME_AND_
        ; WAIT) which ticks sound, ei, and halts. Next vblank, VBLANK_HANDLER fires,
        ; dispatches via `jp (STATE_HANDLER_VECTOR)`, and execution resumes at the
        ; return point. The "FINISH_SPRITES" variant also writes the sprite-list
        ; terminator (D0h) before yielding.
        pop     hl                                             ;#40AE: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40AF: 22 05 E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#40B2: 2A 14 E0
        ; mark next sprite slot as end-of-list
        ld      (hl),SPRITE_Y_TERMINATOR                       ;#40B5: 36 D0
        jp      FINISH_FRAME_AND_WAIT                          ;#40B7: C3 45 40

WAIT_VBLANK:
        ; Yield: save caller PC into STATE_HANDLER_VECTOR, wait for next VBLANK
        pop     hl                                             ;#40BA: E1
        ld      (STATE_HANDLER_VECTOR),hl                      ;#40BB: 22 05 E0
        jp      FINISH_FRAME_AND_WAIT                          ;#40BE: C3 45 40

SILENCE_PSG:
        ; Zero PSG channel-volume registers (R8/R9/R10)
        ; SILENCE_PSG writes 0 to PSG R8/R9/R10 (channel A/B/C amplitude registers). All
        ; 3 channels go silent. Called when entering PAUSE state from VBLANK_HANDLER so
        ; the music doesn't keep playing while paused.
        ld      a,8                                            ;#40C1: 3E 08
        ld      e,0                                            ;#40C3: 1E 00
        call    BIOS_WRTPSG                                    ;#40C5: CD 93 00
        ; silence PSG channel B volume
        ld      a,9                                            ;#40C8: 3E 09
        ld      e,0                                            ;#40CA: 1E 00
        call    BIOS_WRTPSG                                    ;#40CC: CD 93 00
        ld      a,0Ah                                          ;#40CF: 3E 0A
        ld      e,0                                            ;#40D1: 1E 00
        ; tail call for R10 silence (covered manually)
        jp      BIOS_WRTPSG                                    ;#40D3: C3 93 00

CHECK_PAUSE_KEY:
        ; Poll SNSMAT row 7 and toggle PAUSE_FLAG on a sustained key chord
        ; CHECK_PAUSE_KEY runs once per frame. Reads SNSMAT row 7 (function keys),
        ; rotates the input bits into PAUSE_KEY_HISTORY as a 4-bit shift register, and
        ; tests for a stable held-down pattern (history & 0Fh == 0Ch). On match, toggles
        ; PAUSE_FLAG via cpl. The shift register debounces the keypress so single frames
        ; don't accidentally pause.
        ld      a,(GAME_ACTIVE)                                ;#40D6: 3A 00 E0
        and     a                                              ;#40D9: A7
        jr      z,CHECK_PAUSE_KEY_TOGGLE_PAUSE                 ;#40DA: 28 18
        ld      a,7                                            ;#40DC: 3E 07
        call    BIOS_SNSMAT                                    ;#40DE: CD 41 01
        ld      hl,PAUSE_KEY_HISTORY                           ;#40E1: 21 47 E0
        rla                                                    ;#40E4: 17
        rla                                                    ;#40E5: 17
        rla                                                    ;#40E6: 17
        rla                                                    ;#40E7: 17
        rl      (hl)                                           ;#40E8: CB 16
        ld      a,(hl)                                         ;#40EA: 7E
        and     0Fh                                            ;#40EB: E6 0F
        cp      0Ch                                            ;#40ED: FE 0C
        ret     nz                                             ;#40EF: C0
        ld      a,(PAUSE_FLAG)                                 ;#40F0: 3A 48 E0
        cpl                                                    ;#40F3: 2F
CHECK_PAUSE_KEY_TOGGLE_PAUSE:
        ; CHECK_PAUSE_KEY tail: toggle PAUSE_FLAG and return
        ld      (PAUSE_FLAG),a                                 ;#40F4: 32 48 E0
        ret                                                    ;#40F7: C9

FILL_NAMETABLE_BLANK:
        ; Fill a 23x24 tile area at HL with tile 40h (clear playfield region)
        ; FILL_NAMETABLE_BLANK clears a 23-wide × 24-tall area at the name table base in
        ; HL. Per-row: BIOS_FILVRM fills 23 cells with TILE_BLANK (40h), then HL += 32
        ; (next row). Used by both INIT_PLAYFIELD_PATTERNS and CLEAR_PLAYFIELD to wipe
        ; the screen.
        ld      b,18h                                          ;#40F8: 06 18
FILL_NAMETABLE_ROW_TOP:
        ; Outer djnz of FILL_NAMETABLE_BLANK (per-row body)
        push    bc                                             ;#40FA: C5
        push    hl                                             ;#40FB: E5
        ld      bc,17h                                         ;#40FC: 01 17 00
        ld      a,40h                                          ;#40FF: 3E 40
        call    BIOS_FILVRM                                    ;#4101: CD 56 00
        pop     hl                                             ;#4104: E1
        ld      bc,20h                                         ;#4105: 01 20 00
        add     hl,bc                                          ;#4108: 09
        pop     bc                                             ;#4109: C1
        djnz    FILL_NAMETABLE_ROW_TOP                         ;#410A: 10 EE
        ret                                                    ;#410C: C9

INIT_PLAYFIELD_PATTERNS:
        ; Clear name tables, upload tile patterns 80h..FFh, select stage palette
        ; INIT_PLAYFIELD_PATTERNS sets up the per-stage tile patterns: (1) clears both
        ; name table banks via FILL_NAMETABLE_BLANK, (2) zeros 256 bytes at VRAM
        ; 0C00h/1C00h (chars 80h-9Fh), (3) LDIRVMs BG_PATTERN_FILL 8 times to fill chars
        ; A0h-EFh in both banks, (4) LDIRVMs BG_PATTERN_DATA twice for chars F0h-FFh,
        ; (5) selects a color row from STAGE_PALETTES based on STAGE_PALETTE_INDEX.
        ld      hl,400h                                        ;#410D: 21 00 04
        call    FILL_NAMETABLE_BLANK                           ;#4110: CD F8 40
        ld      hl,1400h                                       ;#4113: 21 00 14
        call    FILL_NAMETABLE_BLANK                           ;#4116: CD F8 40
        LOAD_VRAM_ADDRESS hl, 0C00h                            ;#4119: 21 00 0C
        ld      bc,100h                                        ;#411C: 01 00 01
        xor     a                                              ;#411F: AF
        call    BIOS_FILVRM                                    ;#4120: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1C00h                            ;#4123: 21 00 1C
        ld      bc,100h                                        ;#4126: 01 00 01
        xor     a                                              ;#4129: AF
        call    BIOS_FILVRM                                    ;#412A: CD 56 00
        ld      hl,BG_PATTERN_FILL                             ;#412D: 21 A9 42
        LOAD_VRAM_ADDRESS de, 0D00h                            ;#4130: 11 00 0D
        ld      bc,80h                                         ;#4133: 01 80 00
        call    BIOS_LDIRVM                                    ;#4136: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4139: 21 A9 42
        LOAD_VRAM_ADDRESS de, 1D00h                            ;#413C: 11 00 1D
        ld      bc,80h                                         ;#413F: 01 80 00
        call    BIOS_LDIRVM                                    ;#4142: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4145: 21 A9 42
        LOAD_VRAM_ADDRESS de, 0D80h                            ;#4148: 11 80 0D
        ld      bc,80h                                         ;#414B: 01 80 00
        call    BIOS_LDIRVM                                    ;#414E: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4151: 21 A9 42
        LOAD_VRAM_ADDRESS de, 1D80h                            ;#4154: 11 80 1D
        ld      bc,80h                                         ;#4157: 01 80 00
        call    BIOS_LDIRVM                                    ;#415A: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#415D: 21 A9 42
        LOAD_VRAM_ADDRESS de, 0E00h                            ;#4160: 11 00 0E
        ld      bc,80h                                         ;#4163: 01 80 00
        call    BIOS_LDIRVM                                    ;#4166: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4169: 21 A9 42
        LOAD_VRAM_ADDRESS de, 1E00h                            ;#416C: 11 00 1E
        ld      bc,80h                                         ;#416F: 01 80 00
        call    BIOS_LDIRVM                                    ;#4172: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4175: 21 A9 42
        LOAD_VRAM_ADDRESS de, 0E80h                            ;#4178: 11 80 0E
        ld      bc,80h                                         ;#417B: 01 80 00
        call    BIOS_LDIRVM                                    ;#417E: CD 5C 00
        ld      hl,BG_PATTERN_FILL                             ;#4181: 21 A9 42
        LOAD_VRAM_ADDRESS de, 1E80h                            ;#4184: 11 80 1E
        ld      bc,80h                                         ;#4187: 01 80 00
        call    BIOS_LDIRVM                                    ;#418A: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#418D: 21 C9 41
        LOAD_VRAM_ADDRESS de, 0F00h                            ;#4190: 11 00 0F
        ld      bc,100h                                        ;#4193: 01 00 01
        call    BIOS_LDIRVM                                    ;#4196: CD 5C 00
        ld      hl,BG_PATTERN_DATA                             ;#4199: 21 C9 41
        LOAD_VRAM_ADDRESS de, 1F00h                            ;#419C: 11 00 1F
        ld      bc,100h                                        ;#419F: 01 00 01
        call    BIOS_LDIRVM                                    ;#41A2: CD 5C 00
        ld      hl,STAGE_PALETTES                              ;#41A5: 21 29 43
        ld      a,(STAGE_PALETTE_INDEX)                        ;#41A8: 3A 30 E0
        rra                                                    ;#41AB: 1F
        rra                                                    ;#41AC: 1F
        and     3                                              ;#41AD: E6 03
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41AF: 28 0F
        ld      hl,STAGE_PALETTE_1                             ;#41B1: 21 39 43
        dec     a                                              ;#41B4: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41B5: 28 09
        ld      hl,STAGE_PALETTE_2                             ;#41B7: 21 49 43
        dec     a                                              ;#41BA: 3D
        jr      z,INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD       ;#41BB: 28 03
        ; palette 4 → color row
        ld      hl,STAGE_PALETTE_3                             ;#41BD: 21 59 43
INIT_PLAYFIELD_PATTERNS_PALETTE_UPLOAD:
        ; Tail: LDIRVM the chosen palette row to VRAM 0790h
        LOAD_VRAM_ADDRESS de, 790h                             ;#41C0: 11 90 07
        ld      bc,10h                                         ;#41C3: 01 10 00
        jp      BIOS_LDIRVM                                    ;#41C6: C3 5C 00

BG_PATTERN_DATA:
        ; 8-pixel-wide stripe patterns; loaded into tile patterns F0h..FFh
        dh      "00010101010101000003030303030300"             ;#41C9: 00 01 01 01 01 01 01 00 00 03 03 03 03 03 03 00
        dh      "0007070707070700000F0F0F0F0F0F00"             ;#41D9: 00 07 07 07 07 07 07 00 00 0F 0F 0F 0F 0F 0F 00
        dh      "001F1F1F1F1F1F00003F3F3F3F3F3F00"             ;#41E9: 00 1F 1F 1F 1F 1F 1F 00 00 3F 3F 3F 3F 3F 3F 00
        dh      "007F7F7F7F7F7F0000FFFFFFFFFFFF00"             ;#41F9: 00 7F 7F 7F 7F 7F 7F 00 00 FF FF FF FF FF FF 00
        dh      "00000000000000000004040404040400"             ;#4209: 00 00 00 00 00 00 00 00 00 04 04 04 04 04 04 00
        dh      "000C0C0C0C0C0C00001C1C1C1C1C1C00"             ;#4219: 00 0C 0C 0C 0C 0C 0C 00 00 1C 1C 1C 1C 1C 1C 00
        dh      "003C3C3C3C3C3C00007C7C7C7C7C7C00"             ;#4229: 00 3C 3C 3C 3C 3C 3C 00 00 7C 7C 7C 7C 7C 7C 00
        dh      "00FCFCFCFCFCFC0000FCFCFCFCFCFC00"             ;#4239: 00 FC FC FC FC FC FC 00 00 FC FC FC FC FC FC 00
        dh      "00000000000030300000000000000082"             ;#4249: 00 00 00 00 00 00 30 30 00 00 00 00 00 00 00 82
        dh      "007E607C6060000800666666663C0020"             ;#4259: 00 7E 60 7C 60 60 00 08 00 66 66 66 66 3C 00 20
        dh      "007E607C607E808200606060607E0008"             ;#4269: 00 7E 60 7C 60 7E 80 82 00 60 60 60 60 7E 00 08
        dh      "00000000000000200000000000000686"             ;#4279: 00 00 00 00 00 00 00 20 00 00 00 00 00 00 06 86
        dh      "00010B0F0B0101031B1F190000000000"             ;#4289: 00 01 0B 0F 0B 01 01 03 1B 1F 19 00 00 00 00 00
        dh      "0080D0F0D08080C0D8F8980000000000"             ;#4299: 00 80 D0 F0 D0 80 80 C0 D8 F8 98 00 00 00 00 00

BG_PATTERN_FILL:
        ; 128-byte filler pattern, LDIRVM'd 8 times to populate tile patterns 80h..EFh
        dh      "C0C00000000000003030000000000000"             ;#42A9: C0 C0 00 00 00 00 00 00 30 30 00 00 00 00 00 00
        dh      "0C0C0000000000000303000000000000"             ;#42B9: 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00 00 00
        dh      "0000C0C0000000000000303000000000"             ;#42C9: 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00 00 00
        dh      "00000C0C000000000000030300000000"             ;#42D9: 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00 00 00
        dh      "00000000C0C000000000000030300000"             ;#42E9: 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30 00 00
        dh      "000000000C0C00000000000003030000"             ;#42F9: 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03 00 00
        dh      "000000000000C0C00000000000003030"             ;#4309: 00 00 00 00 00 00 C0 C0 00 00 00 00 00 00 30 30
        dh      "0000000000000C0C0000000000000303"             ;#4319: 00 00 00 00 00 00 0C 0C 00 00 00 00 00 00 03 03

STAGE_PALETTES:
        ; Base of 4 x 16-byte color-table rows (palette 0)
        ; STAGE_PALETTES — 4 rows of 16 bytes each (= 64 bytes total). Used by
        ; INIT_PLAYFIELD_PATTERNS to pick a color row based on STAGE_PALETTE_INDEX (see
        ; (val >> 2) & 3 logic at 41A8h). All 4 rows differ only in their first 2 bytes
        ; — those are the visible per-stage color differentiation (rest is the shared
        ; HUD palette).
        dh      "DEEDF5F5A5A5F5F515156565A1A1F1A1"             ;#4329: DE ED F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_1:
        ; 16-byte color-table row for palette 1
        dh      "4EE4F5F5A5A5F5F515156565A1A1F1A1"             ;#4339: 4E E4 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_2:
        ; 16-byte color-table row for palette 2
        dh      "6EE6F5F5A5A5F5F515156565A1A1F1A1"             ;#4349: 6E E6 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

STAGE_PALETTE_3:
        ; 16-byte color-table row for palette 3
        dh      "2EE2F5F5A5A5F5F515156565A1A1F1A1"             ;#4359: 2E E2 F5 F5 A5 A5 F5 F5 15 15 65 65 A1 A1 F1 A1

INITIAL_STATE_HANDLER:
        ; First state handler installed by GAME_BOOT into STATE_HANDLER_VECTOR
        ; INITIAL_STATE_HANDLER is the first state-handler installed at boot. It walks
        ; the boot flow: reset counters, blank screen, LOAD_PLAYFIELD_GFX,
        ; TITLE_WAIT_INPUT (poll until any input), then GAMEPLAY_INIT which arms the
        ; start jingle. WAIT_START_MUSIC spins on SOUND_STATE_OPENING to drain, then
        ; CLEAR_PLAYFIELD wipes both name tables. After that: INIT_PLAYFIELD_PATTERNS,
        ; LOAD_STAGE_PARAMS, INIT_STAGE, the 4 INIT_OBJECT_TABLE_* helpers, and finally
        ; falls through to GAME_LOOP.
        ld      hl,200h                                        ;#4369: 21 00 02
        ld      (HIGH_SCORE_BCD),hl                            ;#436C: 22 01 E0
        ld      h,0                                            ;#436F: 26 00
        ld      (HIGH_SCORE_BCD_HIGH),hl                       ;#4371: 22 03 E0
        ld      (SCORE_BCD),hl                                 ;#4374: 22 31 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#4377: 22 33 E0
INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART:
        ; Stage-restart entry: clear GAME_ACTIVE, blank screen, reload tile patterns
        xor     a                                              ;#437A: AF
        ld      (GAME_ACTIVE),a                                ;#437B: 32 00 E0
        ; blank screen (R1=82h) during stage setup
        ld      bc,8201h                                       ;#437E: 01 01 82
        call    BIOS_WRTVDP                                    ;#4381: CD 47 00
        call    LOAD_PLAYFIELD_GFX                             ;#4384: CD 50 65
TITLE_WAIT_INPUT:
        ; Title-screen loop; polls POLL_INPUT until any key/joystick pressed
        ; TITLE_WAIT_INPUT spins waiting for any input. Calls WAIT_VBLANK_FINISH_SPRITES
        ; (yield), then POLL_INPUT. If no input bit is set in C (mask 0F0h after cpl),
        ; loops back to TITLE_WAIT_INPUT. Used during the title/attract sequence before
        ; the player can start.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#4387: CD AE 40
        call    POLL_INPUT                                     ;#438A: CD C0 4C
        ld      a,c                                            ;#438D: 79
        cpl                                                    ;#438E: 2F
        and     0F0h                                           ;#438F: E6 F0
        jr      z,TITLE_WAIT_INPUT                             ;#4391: 28 F4
        xor     a                                              ;#4393: AF
        ld      (STAGE_PALETTE_INDEX),a                        ;#4394: 32 30 E0
        ld      (EXTRA_LIFE_AWARDED),a                         ;#4397: 32 3E E0
        ld      hl,0                                           ;#439A: 21 00 00
        ld      (SCORE_BCD),hl                                 ;#439D: 22 31 E0
        ld      (SCORE_BCD_HIGH),hl                            ;#43A0: 22 33 E0
        inc     a                                              ;#43A3: 3C
        ld      (GAME_ACTIVE),a                                ;#43A4: 32 00 E0
        ld      a,2                                            ;#43A7: 3E 02
        ld      (LIVES),a                                      ;#43A9: 32 35 E0
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43AC: CD AE 40
        ld      a,1                                            ;#43AF: 3E 01
        ld      (SOUND_STATE_OPENING),a                        ;#43B1: 32 20 E5
WAIT_START_MUSIC:
        ; Spin on SOUND_STATE_OPENING until the opening jingle finishes
        ; WAIT_START_MUSIC spins until SOUND_STATE_OPENING reaches 0 — the start-jingle
        ; ends. Uses WAIT_VBLANK_FINISH_SPRITES as yield. After drain, proceeds to
        ; CLEAR_PLAYFIELD.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43B4: CD AE 40
        ld      a,(SOUND_STATE_OPENING)                        ;#43B7: 3A 20 E5
        and     a                                              ;#43BA: A7
        jr      nz,WAIT_START_MUSIC                            ;#43BB: 20 F7
        LOAD_VRAM_ADDRESS hl, 400h                             ;#43BD: 21 00 04
        ld      bc,300h                                        ;#43C0: 01 00 03
        ld      a,40h                                          ;#43C3: 3E 40
        call    BIOS_FILVRM                                    ;#43C5: CD 56 00
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#43C8: 21 00 14
        ld      bc,300h                                        ;#43CB: 01 00 03
        ld      a,40h                                          ;#43CE: 3E 40
        call    BIOS_FILVRM                                    ;#43D0: CD 56 00
INITIAL_STATE_HANDLER_PALETTE_REFRESH:
        ; Wait one VBLANK, inc STAGE_PALETTE_INDEX, jump back to pattern init
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43D3: CD AE 40
        ld      hl,STAGE_PALETTE_INDEX                         ;#43D6: 21 30 E0
        inc     (hl)                                           ;#43D9: 34
        jr      nz,INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT    ;#43DA: 20 02
        ld      (hl),0F0h                                      ;#43DC: 36 F0
INITIAL_STATE_HANDLER_AFTER_PATTERN_INIT:
        ; After tile-pattern setup: reset SMOKE_TRAIL_WRITE_INDEX and continue stage init
        call    INIT_PLAYFIELD_PATTERNS                        ;#43DE: CD 0D 41
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#43E1: CD AE 40
        ld      a,8                                            ;#43E4: 3E 08
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#43E6: 32 2A E0
        call    LOAD_STAGE_PARAMS                              ;#43E9: CD A5 71
        call    SCROLL_ROCKS                                   ;#43EC: CD 19 56
        call    INIT_STAGE                                     ;#43EF: CD C8 53
        ld      a,1                                            ;#43F2: 3E 01
        ld      (STAGE_TIMER_INNER),a                          ;#43F4: 32 37 E0
        xor     a                                              ;#43F7: AF
        ld      (STAGE_CLEAR_FLAG),a                           ;#43F8: 32 2F E0
STAGE_RESUME:
        ; Re-seed enemy cars / flags / rocks / track data after death or stage clear
        call    INIT_ENEMY_CARS                                ;#43FB: CD 2F 4C
        call    INIT_FLAGS                                     ;#43FE: CD 83 54
        call    INIT_ROCKS                                     ;#4401: CD 63 56
        call    INIT_STAGE_TRACK_DATA                          ;#4404: CD FD 4B
        xor     a                                              ;#4407: AF
        ld      (NAME_BANK_FLAG),a                             ;#4408: 32 0E E0
        ld      (MOVEMENT_SUB_PHASE),a                         ;#440B: 32 2D E0
        ld      (GAME_OVER_FLAG),a                             ;#440E: 32 49 E0
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#4411: 32 61 E5
        ld      (FRAME_TICK_SUB),a                             ;#4414: 32 2C E0
        ld      (PLAYER_MOVE_GATE),a                           ;#4417: 32 45 E0
        ld      hl,3C01h                                       ;#441A: 21 01 3C
        ld      (STAGE_TIMER_OUTER),hl                         ;#441D: 22 38 E0
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#4420: 21 9C 07
        ld      a,0A1h                                         ;#4423: 3E A1
        call    BIOS_WRTVRM                                    ;#4425: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#4428: 21 9D 07
        ld      a,0A1h                                         ;#442B: 3E A1
        call    BIOS_WRTVRM                                    ;#442D: CD 4D 00
        ld      hl,TEXT_ROUND                                  ;#4430: 21 29 46
        ld      de,FUEL_GAUGE_BUFFER                           ;#4433: 11 E0 E1
        ld      bc,6                                           ;#4436: 01 06 00
        ldir                                                   ;#4439: ED B0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#443B: 3A 30 E0
        cp      63h                                            ;#443E: FE 63
        jr      c,SHOW_ROUND_NUM_CAP                           ;#4440: 38 02
        ld      a,63h                                          ;#4442: 3E 63
SHOW_ROUND_NUM_CAP:
        ; Clamp STAGE_PALETTE_INDEX to 63h before round-number divmod
        ld      c,40h                                          ;#4444: 0E 40
SHOW_ROUND_NUM_DIVMOD:
        ; Divmod-10 loop body: subtract 10 from A, inc tens digit in C
        cp      0Ah                                            ;#4446: FE 0A
        jr      c,SHOW_ROUND_NUM_STORE                         ;#4448: 38 07
        sub     0Ah                                            ;#444A: D6 0A
        res     6,c                                            ;#444C: CB B1
        inc     c                                              ;#444E: 0C
        jr      SHOW_ROUND_NUM_DIVMOD                          ;#444F: 18 F5

SHOW_ROUND_NUM_STORE:
        ; Store ones digit at HL, tens at HL+1 in the round-number SAT cells
        ex      de,hl                                          ;#4451: EB
        ld      (hl),c                                         ;#4452: 71
        inc     hl                                             ;#4453: 23
        ld      (hl),a                                         ;#4454: 77
        ld      hl,DIGIT_TEMPLATE_F0                           ;#4455: 21 2F 46
        LOAD_VRAM_ADDRESS de, 4B7h                             ;#4458: 11 B7 04
        ld      bc,8                                           ;#445B: 01 08 00
        call    BIOS_LDIRVM                                    ;#445E: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_F0                           ;#4461: 21 2F 46
        LOAD_VRAM_ADDRESS de, 14B7h                            ;#4464: 11 B7 14
        ld      bc,8                                           ;#4467: 01 08 00
        call    BIOS_LDIRVM                                    ;#446A: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#446D: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 6F7h                             ;#4470: 11 F7 06
        ld      bc,8                                           ;#4473: 01 08 00
        call    BIOS_LDIRVM                                    ;#4476: CD 5C 00
        ld      hl,FUEL_GAUGE_BUFFER                           ;#4479: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 16F7h                            ;#447C: 11 F7 16
        ld      bc,8                                           ;#447F: 01 08 00
        call    BIOS_LDIRVM                                    ;#4482: CD 5C 00
        ld      hl,SMOKE_TRAIL_TABLE                           ;#4485: 21 00 E4
        ld      de,SMOKE_TRAIL_TABLE_TAIL                      ;#4488: 11 01 E4
        ld      bc,8Fh                                         ;#448B: 01 8F 00
        xor     a                                              ;#448E: AF
        ld      (PLAYER_DIRECTION),a                           ;#448F: 32 11 E0
        ld      (PLAYER_ROTATION_PHASE),a                      ;#4492: 32 2B E0
        ld      (SMOKE_COOLDOWN),a                             ;#4495: 32 27 E0
        ld      (hl),a                                         ;#4498: 77
        ldir                                                   ;#4499: ED B0
        call    UPDATE_LIVES_DISPLAY                           ;#449B: CD 65 68
        call    UPDATE_RADAR                                   ;#449E: CD E0 52
        ld      a,(STAGE_PALETTE_INDEX)                        ;#44A1: 3A 30 E0
        rra                                                    ;#44A4: 1F
        jr      nc,GAME_LOOP                                   ;#44A5: 30 14
        rra                                                    ;#44A7: 1F
        jr      nc,GAME_LOOP                                   ;#44A8: 30 11
        call    DRAW_CHALLENGING_STAGE_SCREEN                  ;#44AA: CD E0 46
        ld      a,1                                            ;#44AD: 3E 01
        ld      (SOUND_STATE_C_STAGE),a                        ;#44AF: 32 65 E5
GAMELOOP_PRE_YIELD:
        ; Spin until SOUND_STATE_C_STAGE = 0 (jingle done)
        call    WAIT_VBLANK                                    ;#44B2: CD BA 40
        ld      a,(SOUND_STATE_C_STAGE)                        ;#44B5: 3A 65 E5
        and     a                                              ;#44B8: A7
        jr      nz,GAMELOOP_PRE_YIELD                          ;#44B9: 20 F7
GAME_LOOP:
        ; Per-frame gameplay loop: yield, music+sound, sprite updates, end-of-round checks
        ; GAME_LOOP is the per-frame heart of gameplay. Each iteration: yield via
        ; WAIT_VBLANK_FINISH_SPRITES, copy FRAME_TICK->VRAM_BANK_FLAG for the double-
        ; buffer swap, drive sound + sprites + scrolling, then check the three end-of-
        ; round flags (STAGE_CLEAR_FLAG / PLAYER_DEAD_FLAG / GAME_OVER_FLAG) and either
        ; continue looping or branch to STAGE_CLEAR_ BONUS / DEATH_SEQUENCE /
        ; GAME_OVER_SEQUENCE.
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#44BB: CD AE 40
        ld      a,(FRAME_TICK)                                 ;#44BE: 3A 07 E0
        ld      (VRAM_BANK_FLAG),a                             ;#44C1: 32 46 E0
        ld      a,1                                            ;#44C4: 3E 01
        ld      (SOUND_STATE_THEME),a                          ;#44C6: 32 10 E5
        call    FLASH_AND_UPDATE_SCORE_HUD                     ;#44C9: CD 20 67
        call    DRAW_PLAYER_CAR                                ;#44CC: CD 8F 47
        call    UPLOAD_PATTERN_SLICE                           ;#44CF: CD 02 4E
        call    ITERATE_ENEMY_CARS                             ;#44D2: CD 7F 57
        call    UPDATE_ROCKS_COLLISION                         ;#44D5: CD BA 56
        call    SCROLL_FLAGS                                   ;#44D8: CD 09 55
        call    SCROLL_SMOKE_TRAILS                            ;#44DB: CD 7D 5C
        call    UPDATE_SMOKE_STATE                             ;#44DE: CD FC 5B
        call    TICK_STAGE_TIMER                               ;#44E1: CD 1B 71
        ld      a,(STAGE_CLEAR_FLAG)                           ;#44E4: 3A 2F E0
        and     a                                              ;#44E7: A7
        jp      nz,STAGE_CLEAR_BONUS                           ;#44E8: C2 5C 45
        ld      a,(PLAYER_DEAD_FLAG)                           ;#44EB: 3A 3B E0
        and     a                                              ;#44EE: A7
        jp      nz,DEATH_SEQUENCE                              ;#44EF: C2 37 46
        ld      a,(GAME_OVER_FLAG)                             ;#44F2: 3A 49 E0
        and     a                                              ;#44F5: A7
        jr      z,GAME_LOOP                                    ;#44F6: 28 C3
        xor     a                                              ;#44F8: AF
        ld      (SOUND_STATE_THEME),a                          ;#44F9: 32 10 E5
        ld      (FRAME_TICK),a                                 ;#44FC: 32 07 E0
        inc     a                                              ;#44FF: 3C
        ld      (SOUND_STATE_BANG),a                           ;#4500: 32 62 E5
        ld      hl,844h                                        ;#4503: 21 44 08
        ld      (SAT_SLOT0_PATTERN_COLOR),hl                   ;#4506: 22 02 EB
GAMEOVER_WAIT_PHASE1:
        ; Wait until FRAME_TICK reaches 14h before placing sprite-list terminator
        call    WAIT_VBLANK                                    ;#4509: CD BA 40
        ld      a,(FRAME_TICK)                                 ;#450C: 3A 07 E0
        cp      14h                                            ;#450F: FE 14
        jr      c,GAMEOVER_WAIT_PHASE1                         ;#4511: 38 F6
        ; end sprite list at game over
        ld      a,SPRITE_Y_TERMINATOR                          ;#4513: 3E D0
        ld      (SAT_SLOT1_Y),a                                ;#4515: 32 04 EB
GAMEOVER_WAIT_PHASE2:
        ; Wait until FRAME_TICK reaches 28h before drawing GAME_OVER text
        call    WAIT_VBLANK                                    ;#4518: CD BA 40
        ld      a,(FRAME_TICK)                                 ;#451B: 3A 07 E0
        cp      28h                                            ;#451E: FE 28
        jr      c,GAMEOVER_WAIT_PHASE2                         ;#4520: 38 F6
        ld      a,(LIVES)                                      ;#4522: 3A 35 E0
        and     a                                              ;#4525: A7
        jr      z,GAMEOVER_SHOW_EXTRA_LIFE                     ;#4526: 28 10
        dec     a                                              ;#4528: 3D
        ld      (LIVES),a                                      ;#4529: 32 35 E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#452C: 3A 30 E0
        cpl                                                    ;#452F: 2F
        and     3                                              ;#4530: E6 03
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4532: CA D3 43
        jp      STAGE_RESUME                                   ;#4535: C3 FB 43

GAMEOVER_SHOW_EXTRA_LIFE:
        ; LIVES==0 branch: paint SAT_EXTRA_LIFE entry then fall into wait phase 3
        ld      hl,SAT_EXTRA_LIFE                              ;#4538: 21 53 45
        ld      de,SAT_MIRROR                                  ;#453B: 11 00 EB
        ld      bc,9                                           ;#453E: 01 09 00
        ldir                                                   ;#4541: ED B0
GAMEOVER_WAIT_PHASE3:
        ; Wait until FRAME_TICK >= 50h, then loop back to next-stage restart
        call    WAIT_VBLANK                                    ;#4543: CD BA 40
        ld      a,(FRAME_TICK)                                 ;#4546: 3A 07 E0
        cp      50h                                            ;#4549: FE 50
        jr      c,GAMEOVER_WAIT_PHASE3                         ;#454B: 38 F6
        call    WAIT_VBLANK_FINISH_SPRITES                     ;#454D: CD AE 40
        jp      INITIAL_STATE_HANDLER_NEXT_STAGE_RESTART       ;#4550: C3 7A 43

SAT_EXTRA_LIFE:
        ; 9-byte SAT data: copied to SAT_MIRROR when an extra life is awarded
        ; SAT_EXTRA_LIFE is 9-byte SAT data copied into SAT_MIRROR when the player earns
        ; an extra life. Shows a brief sprite overlay (likely a "1UP" or "EXTRA"
        ; indicator) on the HUD.
        dh      "5750D00F5760D40FD0"                           ;#4553: 57 50 D0 0F 57 60 D4 0F D0

STAGE_CLEAR_BONUS:
        ; Kill MUSIC_THEME, start MUSIC_STAGE_CLEAR, drain FUEL_LEVEL into score
        ; STAGE_CLEAR_BONUS plays the stage-clear sequence: kill MUSIC_THEME, trigger
        ; MUSIC_STAGE_CLEAR (victory jingle), wait for it to drain, then convert
        ; remaining FUEL_LEVEL into bonus score using one of 4 DRAIN_FUEL_* variants
        ; (slower drain at higher stages = longer display = more "satisfying" bonus
        ; animation).
        xor     a                                              ;#455C: AF
        ld      (SOUND_STATE_THEME),a                          ;#455D: 32 10 E5
        ld      (PLAYER_DEAD_FLAG),a                           ;#4560: 32 3B E0
        inc     a                                              ;#4563: 3C
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#4564: 32 30 E5
        call    UPDATE_SCORE_HUD                               ;#4567: CD 4F 67
STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR:
        ; Spin until SOUND_STATE_STAGE_CLEAR reaches 0 (victory jingle drained)
        call    WAIT_VBLANK                                    ;#456A: CD BA 40
        ld      a,(SOUND_STATE_STAGE_CLEAR)                    ;#456D: 3A 30 E5
        and     a                                              ;#4570: A7
        jr      nz,STAGE_CLEAR_BONUS_WAIT_MUSIC_STAGE_CLEAR    ;#4571: 20 F7
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4573: 3A 30 E0
        cp      0Ch                                            ;#4576: FE 0C
        jp      nc,STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH        ;#4578: D2 04 46
        cp      8                                              ;#457B: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP         ;#457D: 30 5D
        cp      4                                              ;#457F: FE 04
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP         ;#4581: 30 2E
STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP:
        ; Drain-fuel loop (stages 0-3): 4x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#4583: CD BA 40
        xor     a                                              ;#4586: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4587: 32 51 E5
        ld      b,2                                            ;#458A: 06 02
STAGE_CLEAR_BONUS_QUAD_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#458C: 3A 39 E0
        and     a                                              ;#458F: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4590: CA D3 43
        call    DRAIN_FUEL_QUAD_TICK                           ;#4593: CD 9F 45
        djnz    STAGE_CLEAR_BONUS_QUAD_TICK_TOP                ;#4596: 10 F4
        ld      a,1                                            ;#4598: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#459A: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_QUAD_LOOP              ;#459D: 18 E4

DRAIN_FUEL_QUAD_TICK:
        ; 4x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — fastest drain variant (stage 0-3)
        push    bc                                             ;#459F: C5
        call    TICK_FUEL_REFRESH                              ;#45A0: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45A3: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45A6: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45A9: CD 24 71
        call    BCD_ADD_TO_BONUS                               ;#45AC: CD 0D 68
        pop     bc                                             ;#45AF: C1
        ret                                                    ;#45B0: C9

STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP:
        ; Drain-fuel loop (stages 4-7): 3x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45B1: CD BA 40
        xor     a                                              ;#45B4: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45B5: 32 51 E5
        ld      b,3                                            ;#45B8: 06 03
STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45BA: 3A 39 E0
        and     a                                              ;#45BD: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45BE: CA D3 43
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#45C1: CD CD 45
        djnz    STAGE_CLEAR_BONUS_TRIPLE_TICK_TOP              ;#45C4: 10 F4
        ld      a,1                                            ;#45C6: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45C8: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_TRIPLE_LOOP            ;#45CB: 18 E4

DRAIN_FUEL_TRIPLE_TICK:
        ; 3x TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS — drain variant (stage 4-7)
        push    bc                                             ;#45CD: C5
        call    TICK_FUEL_REFRESH                              ;#45CE: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45D1: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45D4: CD 24 71
        call    BCD_ADD_TO_BONUS                               ;#45D7: CD 0D 68
        pop     bc                                             ;#45DA: C1
        ret                                                    ;#45DB: C9

STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP:
        ; Drain-fuel loop (stages 8-Bh): 2x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#45DC: CD BA 40
        xor     a                                              ;#45DF: AF
        ld      (SOUND_STATE_BONUS),a                          ;#45E0: 32 51 E5
        ld      b,4                                            ;#45E3: 06 04
STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP:
        ; Inner djnz loop body of STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP
        ld      a,(FUEL_LEVEL)                                 ;#45E5: 3A 39 E0
        and     a                                              ;#45E8: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#45E9: CA D3 43
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#45EC: CD F8 45
        djnz    STAGE_CLEAR_BONUS_DOUBLE_TICK_TOP              ;#45EF: 10 F4
        ld      a,1                                            ;#45F1: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#45F3: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DOUBLE_LOOP            ;#45F6: 18 E4

DRAIN_FUEL_DOUBLE_TICK:
        ; Two TICK_FUEL_REFRESH calls + BCD_ADD_TO_BONUS overlap — 2x drain rate variant
        push    bc                                             ;#45F8: C5
        call    TICK_FUEL_REFRESH                              ;#45F9: CD 24 71
        call    TICK_FUEL_REFRESH                              ;#45FC: CD 24 71
        call    BCD_ADD_TO_BONUS                               ;#45FF: CD 0D 68
        pop     bc                                             ;#4602: C1
        ret                                                    ;#4603: C9

STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH:
        ; Drain-fuel loop (stage >=Ch): 1x TICK_FUEL_REFRESH per iteration
        call    WAIT_VBLANK                                    ;#4604: CD BA 40
        xor     a                                              ;#4607: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4608: 32 51 E5
        ld      b,8                                            ;#460B: 06 08
STAGE_CLEAR_BONUS_SINGLE_TICK_TOP:
        ; Inner djnz loop body (stage-8plus drain rate)
        ld      a,(FUEL_LEVEL)                                 ;#460D: 3A 39 E0
        and     a                                              ;#4610: A7
        jp      z,INITIAL_STATE_HANDLER_PALETTE_REFRESH        ;#4611: CA D3 43
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#4614: CD 20 46
        djnz    STAGE_CLEAR_BONUS_SINGLE_TICK_TOP              ;#4617: 10 F4
        ld      a,1                                            ;#4619: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#461B: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_8PLUS_BRANCH           ;#461E: 18 E4

DRAIN_FUEL_TICK_TO_BONUS:
        ; Wrap TICK_FUEL_REFRESH + BCD_ADD_TO_BONUS to drain one fuel into bonus
        ; DRAIN_FUEL_TICK_TO_BONUS — 1× wrap. Calls TICK_FUEL_REFRESH then
        ; BCD_ADD_TO_BONUS (overlap entry adding 10h to BONUS_BCD). Used by
        ; STAGE_CLEAR_BONUS at the slowest drain rate (stage 12+).
        push    bc                                             ;#4620: C5
        call    TICK_FUEL_REFRESH                              ;#4621: CD 24 71
        call    BCD_ADD_TO_BONUS                               ;#4624: CD 0D 68
        pop     bc                                             ;#4627: C1
        ret                                                    ;#4628: C9

TEXT_ROUND:
        ; "ROUND " label (6 bytes, ASCII + trailing space tile 40h)
        db      "ROUND@"                                       ;#4629: 52 4F 55 4E 44 40

DIGIT_TEMPLATE_F0:
        ; 8-byte tile run F0..F7 used as 8 score-style digit slot positions
        dh      "F0F1F2F3F4F5F6F7"                             ;#462F: F0 F1 F2 F3 F4 F5 F6 F7

DEATH_SEQUENCE:
        ; Player-death entry; saves STAGE_TIMER_OUTER..SAVED_TIMER_FOR_DEATH on respawn
        ; DEATH_SEQUENCE handles a player-rock or player-enemy collision. Saves
        ; STAGE_TIMER pair (STAGE_TIMER_OUTER, FUEL_LEVEL → SAVED_TIMER_FOR_DEATH) so it
        ; can resume after the death animation. Plays death SFX, animates player car
        ; explosion, then either: LIVES > 0 → respawn at start position; LIVES = 0 → set
        ; GAME_OVER_FLAG to trigger GAME_OVER_SEQUENCE next frame.
        ld      hl,(STAGE_TIMER_OUTER)                         ;#4637: 2A 38 E0
        ld      (SAVED_TIMER_FOR_DEATH),hl                     ;#463A: 22 3C E0
        ld      a,(STAGE_PALETTE_INDEX)                        ;#463D: 3A 30 E0
        cp      0Ch                                            ;#4640: FE 0C
        jr      nc,STAGE_CLEAR_BONUS_RESTORE_AND_RETURN        ;#4642: 30 59
        cp      8                                              ;#4644: FE 08
        jr      nc,STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK          ;#4646: 30 3A
        cp      4                                              ;#4648: FE 04
        jr      nc,STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH        ;#464A: 30 1B
STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER:
        ; Single-tick branch: zero SFX_BONUS each iteration to retrigger drain sound
        call    WAIT_VBLANK                                    ;#464C: CD BA 40
        xor     a                                              ;#464F: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4650: 32 51 E5
        ld      b,2                                            ;#4653: 06 02
DEATH_RESET_LOOP_HEAD:
        ; Inner djnz loop within DEATH_SEQUENCE phase 1
        ld      a,(FUEL_LEVEL)                                 ;#4655: 3A 39 E0
        and     a                                              ;#4658: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4659: 28 5D
        call    DRAIN_FUEL_QUAD_TICK                           ;#465B: CD 9F 45
        djnz    DEATH_RESET_LOOP_HEAD                          ;#465E: 10 F5
        ld      a,1                                            ;#4660: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4662: 32 51 E5
        jr      STAGE_CLEAR_BONUS_LOOP_SFX_TRIGGER             ;#4665: 18 E5

STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH:
        ; Mirror of LOOP_SFX_TRIGGER for the stage-4plus drain path
        call    WAIT_VBLANK                                    ;#4667: CD BA 40
        xor     a                                              ;#466A: AF
        ld      (SOUND_STATE_BONUS),a                          ;#466B: 32 51 E5
        ld      b,3                                            ;#466E: 06 03
DEATH_RESET_LOOP_HEAD_2:
        ; Inner djnz loop within DEATH_SEQUENCE phase 2
        ld      a,(FUEL_LEVEL)                                 ;#4670: 3A 39 E0
        and     a                                              ;#4673: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#4674: 28 42
        call    DRAIN_FUEL_TRIPLE_TICK                         ;#4676: CD CD 45
        djnz    DEATH_RESET_LOOP_HEAD_2                        ;#4679: 10 F5
        ld      a,1                                            ;#467B: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#467D: 32 51 E5
        jr      STAGE_CLEAR_BONUS_STAGE_4PLUS_BRANCH           ;#4680: 18 E5

STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK:
        ; Check FUEL_LEVEL = 0: when drained, jump to ISH_PALETTE_REFRESH
        call    WAIT_VBLANK                                    ;#4682: CD BA 40
        xor     a                                              ;#4685: AF
        ld      (SOUND_STATE_BONUS),a                          ;#4686: 32 51 E5
        ld      b,4                                            ;#4689: 06 04
DEATH_RESET_LOOP_HEAD_3:
        ; Inner djnz loop within DEATH_SEQUENCE phase 3
        ld      a,(FUEL_LEVEL)                                 ;#468B: 3A 39 E0
        and     a                                              ;#468E: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#468F: 28 27
        call    DRAIN_FUEL_DOUBLE_TICK                         ;#4691: CD F8 45
        djnz    DEATH_RESET_LOOP_HEAD_3                        ;#4694: 10 F5
        ld      a,1                                            ;#4696: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#4698: 32 51 E5
        jr      STAGE_CLEAR_BONUS_DRAIN_DONE_CHECK             ;#469B: 18 E5

STAGE_CLEAR_BONUS_RESTORE_AND_RETURN:
        ; Drain finished: restore SFX_BONUS trigger then return to gameplay flow
        call    WAIT_VBLANK                                    ;#469D: CD BA 40
        xor     a                                              ;#46A0: AF
        ld      (SOUND_STATE_BONUS),a                          ;#46A1: 32 51 E5
        ld      b,8                                            ;#46A4: 06 08
DEATH_RESET_LOOP_HEAD_4:
        ; Inner djnz loop within DEATH_SEQUENCE phase 4
        ld      a,(FUEL_LEVEL)                                 ;#46A6: 3A 39 E0
        and     a                                              ;#46A9: A7
        jr      z,DEATH_RESTORE_TIMER                          ;#46AA: 28 0C
        call    DRAIN_FUEL_TICK_TO_BONUS                       ;#46AC: CD 20 46
        djnz    DEATH_RESET_LOOP_HEAD_4                        ;#46AF: 10 F5
        ld      a,1                                            ;#46B1: 3E 01
        ld      (SOUND_STATE_BONUS),a                          ;#46B3: 32 51 E5
        jr      STAGE_CLEAR_BONUS_RESTORE_AND_RETURN           ;#46B6: 18 E5

DEATH_RESTORE_TIMER:
        ; Restore (STAGE_TIMER_OUTER, FUEL_LEVEL) from SAVED_TIMER_FOR_DEATH and reset
        ld      hl,(SAVED_TIMER_FOR_DEATH)                     ;#46B8: 2A 3C E0
        ld      (STAGE_TIMER_OUTER),hl                         ;#46BB: 22 38 E0
        xor     a                                              ;#46BE: AF
        ld      (PLAYER_DEAD_FLAG),a                           ;#46BF: 32 3B E0
        ld      (PLAYER_MOVE_GATE),a                           ;#46C2: 32 45 E0
        ld      a,h                                            ;#46C5: 7C
        cp      0Ah                                            ;#46C6: FE 0A
        jr      c,DEATH_PAINT_DIGITS                           ;#46C8: 38 10
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#46CA: 21 9C 07
        ld      a,0A1h                                         ;#46CD: 3E A1
        call    BIOS_WRTVRM                                    ;#46CF: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#46D2: 21 9D 07
        ld      a,0A1h                                         ;#46D5: 3E A1
        call    BIOS_WRTVRM                                    ;#46D7: CD 4D 00
DEATH_PAINT_DIGITS:
        ; After digits painted: refresh fuel gauge and resume GAME_LOOP
        call    UPDATE_FUEL_GAUGE                              ;#46DA: CD 65 71
        jp      GAME_LOOP                                      ;#46DD: C3 BB 44

DRAW_CHALLENGING_STAGE_SCREEN:
        ; Render "CHALLENGING STAGE NO <N>" text + stage-number sprites
        ; DRAW_CHALLENGING_STAGE_SCREEN composes the "CHALLENGING STAGE NO X" screen
        ; between stages. Decodes the stage number into 2 digits via an inline decimal-
        ; conversion loop, writes both digits to the name table via BIOS_WRTVRM, then
        ; LDIRVMs TEXT_CHALLENGING_STAGE and TEXT_NO to fixed positions in the name
        ; table. SAT_STAGE_INDICATOR sprites overlay the digits at sprite-sized
        ; positions.
        and     3Fh                                            ;#46E0: E6 3F
        inc     a                                              ;#46E2: 3C
        ld      c,0                                            ;#46E3: 0E 00
DEATH_DIGIT_DIVMOD:
        ; Divmod-10 loop for death-screen score digit
        cp      0Ah                                            ;#46E5: FE 0A
        jr      c,DEATH_DIGIT_LOOP_TAIL                        ;#46E7: 38 05
        inc     c                                              ;#46E9: 0C
        sub     0Ah                                            ;#46EA: D6 0A
        jr      DEATH_DIGIT_DIVMOD                             ;#46EC: 18 F7

DEATH_DIGIT_LOOP_TAIL:
        ; Digit-loop tail: store B in VRAM at the computed position
        ld      b,a                                            ;#46EE: 47
        ld      hl,400h                                        ;#46EF: 21 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#46F2: 3A 0E E0
        and     a                                              ;#46F5: A7
        jr      z,CHALLENGE_RIGHT_BANK                         ;#46F6: 28 03
        LOAD_VRAM_ADDRESS hl, 1400h                            ;#46F8: 21 00 14
CHALLENGE_RIGHT_BANK:
        ; CHALLENGING STAGE bank-B path: emit text to VRAM 14Eh + bank offset
        push    hl                                             ;#46FB: E5
        ld      de,14Eh                                        ;#46FC: 11 4E 01
        add     hl,de                                          ;#46FF: 19
        ld      a,c                                            ;#4700: 79
        and     a                                              ;#4701: A7
        jr      z,CHALLENGE_FALLTHROUGH                        ;#4702: 28 08
        push    bc                                             ;#4704: C5
        push    hl                                             ;#4705: E5
        call    BIOS_WRTVRM                                    ;#4706: CD 4D 00
        pop     hl                                             ;#4709: E1
        pop     bc                                             ;#470A: C1
        inc     hl                                             ;#470B: 23
CHALLENGE_FALLTHROUGH:
        ; Common tail after bank-A/B selection: write ones digit via BIOS_WRTVRM
        ld      a,b                                            ;#470C: 78
        call    BIOS_WRTVRM                                    ;#470D: CD 4D 00
        pop     hl                                             ;#4710: E1
        push    hl                                             ;#4711: E5
        LOAD_VRAM_ADDRESS de, 104h                             ;#4712: 11 04 01
        add     hl,de                                          ;#4715: 19
        ex      de,hl                                          ;#4716: EB
        ld      hl,TEXT_CHALLENGING_STAGE                      ;#4717: 21 72 47
        ld      bc,11h                                         ;#471A: 01 11 00
        call    BIOS_LDIRVM                                    ;#471D: CD 5C 00
        pop     hl                                             ;#4720: E1
        push    hl                                             ;#4721: E5
        LOAD_VRAM_ADDRESS de, 14Bh                             ;#4722: 11 4B 01
        add     hl,de                                          ;#4725: 19
        ex      de,hl                                          ;#4726: EB
        ld      hl,TEXT_NO                                     ;#4727: 21 83 47
        ld      bc,3                                           ;#472A: 01 03 00
        call    BIOS_LDIRVM                                    ;#472D: CD 5C 00
        pop     hl                                             ;#4730: E1
        push    hl                                             ;#4731: E5
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#4732: 3A 40 E0
        rra                                                    ;#4735: 1F
        rra                                                    ;#4736: 1F
        rra                                                    ;#4737: 1F
        rra                                                    ;#4738: 1F
        and     0Fh                                            ;#4739: E6 0F
        ld      de,1AEh                                        ;#473B: 11 AE 01
        add     hl,de                                          ;#473E: 19
        call    BIOS_WRTVRM                                    ;#473F: CD 4D 00
        ld      a,(ROCK_SPAWN_COUNT)                           ;#4742: 3A 1C E0
        ld      c,0                                            ;#4745: 0E 00
        cp      0Ah                                            ;#4747: FE 0A
        jr      c,CHALLENGE_ROCK_NO_DIVMOD                     ;#4749: 38 03
        inc     c                                              ;#474B: 0C
        sub     0Ah                                            ;#474C: D6 0A
CHALLENGE_ROCK_NO_DIVMOD:
        ; No-divmod path: ROCK_SPAWN_COUNT < 10, draw ones digit only
        pop     hl                                             ;#474E: E1
        ld      de,20Eh                                        ;#474F: 11 0E 02
        add     hl,de                                          ;#4752: 19
        ld      b,a                                            ;#4753: 47
        ld      a,c                                            ;#4754: 79
        and     a                                              ;#4755: A7
        jr      z,CHALLENGE_WRITE_ONES_DIGIT                   ;#4756: 28 08
        push    hl                                             ;#4758: E5
        push    bc                                             ;#4759: C5
        call    BIOS_WRTVRM                                    ;#475A: CD 4D 00
        pop     bc                                             ;#475D: C1
        pop     hl                                             ;#475E: E1
        inc     hl                                             ;#475F: 23
CHALLENGE_WRITE_ONES_DIGIT:
        ; Write the ones digit of ROCK_SPAWN_COUNT, then LDIRVM the SAT indicator
        ld      a,b                                            ;#4760: 78
        call    BIOS_WRTVRM                                    ;#4761: CD 4D 00
        ld      hl,SAT_STAGE_INDICATOR                         ;#4764: 21 86 47
        ld      de,SAT_MIRROR                                  ;#4767: 11 00 EB
        ld      bc,9                                           ;#476A: 01 09 00
        ldir                                                   ;#476D: ED B0
        jp      UPDATE_SCORE_HUD                               ;#476F: C3 4F 67

TEXT_CHALLENGING_STAGE:
        ; "CHALLENGING STAGE" string (17 bytes, ASCII)
        db      "CHALLENGING STAGE"                            ;#4772: 43 48 41 4C 4C 45 4E 47 49 4E 47 20 53 54 41 47 45

TEXT_NO:
        ; "NO]" suffix text (3 bytes)
        db      "NO]"                                          ;#4783: 4E 4F 5D

SAT_STAGE_INDICATOR:
        ; 9-byte SAT data for stage-number sprite display (2 sprites + terminator)
        ; SAT_STAGE_INDICATOR is 9 bytes of SAT data uploaded to SAT_MIRROR to show the
        ; stage-number sprites on the "CHALLENGING STAGE" screen. Contains 2 sprite
        ; entries (4 bytes each) + terminator (Y=D0h).
        dh      "635800087B583C09D0"                           ;#4786: 63 58 00 08 7B 58 3C 09 D0

DRAW_PLAYER_CAR:
        ; Rotate animation phase toward PLAYER_DIRECTION; emit car sprite at screen centre
        ; DRAW_PLAYER_CAR runs every other frame (gated by FRAME_TICK low bit). Reads
        ; PLAYER_DIRECTION (lower 2 bits), computes a target rotation angle, and slews
        ; PLAYER_ROTATION_PHASE by +/-4 toward it (modulo 30h). Then emits the player
        ; car sprite at fixed screen-center (Y=57h, X=58h) with the rotation phase as
        ; the tile index and color 5 (cyan).
        ld      a,(FRAME_TICK)                                 ;#478F: 3A 07 E0
        rra                                                    ;#4792: 1F
        jr      nc,PLAYER_EMIT_SPRITE                          ;#4793: 30 2E
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#4795: 3A 2B E0
        ld      c,a                                            ;#4798: 4F
        ld      a,(PLAYER_DIRECTION)                           ;#4799: 3A 11 E0
        and     3                                              ;#479C: E6 03
        ld      b,a                                            ;#479E: 47
        add     a,a                                            ;#479F: 87
        add     a,b                                            ;#47A0: 80
        add     a,a                                            ;#47A1: 87
        add     a,a                                            ;#47A2: 87
        sub     c                                              ;#47A3: 91
        jr      z,PLAYER_EMIT_SPRITE                           ;#47A4: 28 1D
        jr      nc,PLAYER_DELTA_NORMALIZED                     ;#47A6: 30 02
        add     a,30h                                          ;#47A8: C6 30
PLAYER_DELTA_NORMALIZED:
        ; Direction delta normalized to [0..2Fh]; pick rotate-minus or rotate-plus
        cp      18h                                            ;#47AA: FE 18
        jr      c,PLAYER_ROTATE_PLUS                           ;#47AC: 38 0A
        ld      a,c                                            ;#47AE: 79
        sub     4                                              ;#47AF: D6 04
        jr      nc,PLAYER_STORE_ROTATION                       ;#47B1: 30 0D
        ld      a,2Ch                                          ;#47B3: 3E 2C
        jp      PLAYER_STORE_ROTATION                          ;#47B5: C3 C0 47

PLAYER_ROTATE_PLUS:
        ; Rotate phase by +4 (mod 30h) toward target direction
        ld      a,c                                            ;#47B8: 79
        add     a,4                                            ;#47B9: C6 04
        cp      30h                                            ;#47BB: FE 30
        jr      c,PLAYER_STORE_ROTATION                        ;#47BD: 38 01
        xor     a                                              ;#47BF: AF
PLAYER_STORE_ROTATION:
        ; Store updated PLAYER_ROTATION_PHASE
        ld      (PLAYER_ROTATION_PHASE),a                      ;#47C0: 32 2B E0
PLAYER_EMIT_SPRITE:
        ; Skip-update branch (gated by FRAME_TICK low bit): emit player sprite
        ld      a,(PLAYER_ROTATION_PHASE)                      ;#47C3: 3A 2B E0
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#47C6: 2A 14 E0
        ; emit player sprite
        ld      (hl),57h                                       ;#47C9: 36 57
        inc     hl                                             ;#47CB: 23
        ld      (hl),58h                                       ;#47CC: 36 58
        inc     hl                                             ;#47CE: 23
        ld      (hl),a                                         ;#47CF: 77
        inc     hl                                             ;#47D0: 23
        ld      (hl),5                                         ;#47D1: 36 05
        inc     hl                                             ;#47D3: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#47D4: 22 14 E0
        ld      bc,101h                                        ;#47D7: 01 01 01
        ld      a,(PLAYER_VELOCITY_X)                          ;#47DA: 3A 09 E0
        bit     7,a                                            ;#47DD: CB 7F
        jr      z,PLAYER_APPLY_X_VEL                           ;#47DF: 28 03
        neg                                                    ;#47E1: ED 44
        dec     b                                              ;#47E3: 05
PLAYER_APPLY_X_VEL:
        ; Velocity-Y not negative: store positive velocity and update WORLD_X_POS
        sub     0Ah                                            ;#47E4: D6 0A
        ld      e,a                                            ;#47E6: 5F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#47E7: 3A 0B E0
        bit     7,a                                            ;#47EA: CB 7F
        jr      z,PLAYER_APPLY_Y_VEL                           ;#47EC: 28 03
        neg                                                    ;#47EE: ED 44
        dec     c                                              ;#47F0: 0D
PLAYER_APPLY_Y_VEL:
        ; Velocity-Y negative: store inverted velocity and update WORLD_Y_POS
        sub     0Ah                                            ;#47F1: D6 0A
        ld      d,a                                            ;#47F3: 57
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#47F4: 21 0F E0
        ld      a,(hl)                                         ;#47F7: 7E
        add     a,b                                            ;#47F8: 80
        ld      (PLAYER_SCREEN_X),a                            ;#47F9: 32 23 E0
        ld      b,a                                            ;#47FC: 47
        inc     hl                                             ;#47FD: 23
        ld      a,(hl)                                         ;#47FE: 7E
        add     a,c                                            ;#47FF: 81
        ld      (PLAYER_SCREEN_Y),a                            ;#4800: 32 24 E0
        ld      l,a                                            ;#4803: 6F
        ld      h,b                                            ;#4804: 60
        call    DEPLOY_SMOKE_IF_INPUT                          ;#4805: CD B3 49
        ld      a,(PLAYER_DIRECTION)                           ;#4808: 3A 11 E0
        call    AI_PICK_VALID_DIRECTION                        ;#480B: CD 2B 4A
        ld      hl,(PLAYFIELD_SCROLL_OFFSET)                   ;#480E: 2A 12 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#4811: 3A 45 E0
        and     a                                              ;#4814: A7
        jr      nz,SCROLL_CHECK_BACKWARD                       ;#4815: 20 17
        ld      a,(SCROLL_LIMIT_HI)                            ;#4817: 3A 44 E0
        cp      h                                              ;#481A: BC
        jr      nz,SCROLL_ADVANCE_FORWARD                      ;#481B: 20 08
        ld      a,(SCROLL_LIMIT_LO)                            ;#481D: 3A 43 E0
        cp      l                                              ;#4820: BD
        jr      z,DISPATCH_PLAYER_DIRECTION                    ;#4821: 28 1B
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#4823: 38 19
SCROLL_ADVANCE_FORWARD:
        ; Scroll bounds advance: increment PLAYFIELD_SCROLL_OFFSET by 10h
        ld      de,10h                                         ;#4825: 11 10 00
        add     hl,de                                          ;#4828: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4829: 22 12 E0
        jr      DISPATCH_PLAYER_DIRECTION                      ;#482C: 18 10

SCROLL_CHECK_BACKWARD:
        ; Move-gate active: check whether scroll should retreat
        ld      a,h                                            ;#482E: 7C
        and     a                                              ;#482F: A7
        jr      nz,SCROLL_RETREAT                              ;#4830: 20 05
        ld      a,l                                            ;#4832: 7D
        cp      0C0h                                           ;#4833: FE C0
        jr      c,DISPATCH_PLAYER_DIRECTION                    ;#4835: 38 07
SCROLL_RETREAT:
        ; Scroll bounds retreat: subtract 8 from PLAYFIELD_SCROLL_OFFSET
        ld      de,-8                                          ;#4837: 11 F8 FF
        add     hl,de                                          ;#483A: 19
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#483B: 22 12 E0
DISPATCH_PLAYER_DIRECTION:
        ; 4-way switch on PLAYER_DIRECTION&3 into per-direction movement handlers
        ; DISPATCH_PLAYER_DIRECTION reads PLAYER_DIRECTION lower 2 bits (0/1/2/3 =
        ; up/right/down/left), then jumps to MOVE_PLAYER_DIRECTION_0..3. Each handler
        ; updates WORLD_X_POS or WORLD_Y_POS, derives WORLD_SCROLL_DX/DY for the per-
        ; frame world scroll, and verifies movement via LOOKUP_ PLAYFIELD_CELL to detect
        ; wall collisions.
        ex      de,hl                                          ;#483E: EB
        ld      a,(PLAYER_DIRECTION)                           ;#483F: 3A 11 E0
        and     3                                              ;#4842: E6 03
        jp      z,MOVE_PLAYER_DIRECTION_0                      ;#4844: CA A9 48
        dec     a                                              ;#4847: 3D
        jp      z,MOVE_PLAYER_DIRECTION_1                      ;#4848: CA 5B 49
        dec     a                                              ;#484B: 3D
        jp      z,MOVE_PLAYER_DIRECTION_2                      ;#484C: CA 03 49
        ld      a,(PLAYER_VELOCITY_Y)                          ;#484F: 3A 0B E0
        ld      c,a                                            ;#4852: 4F
        and     a                                              ;#4853: A7
        ld      a,0Ch                                          ;#4854: 3E 0C
        jp      p,MOVE_DIR3_STORE_VEL                          ;#4856: F2 5B 48
        ld      a,0F4h                                         ;#4859: 3E F4
MOVE_DIR3_STORE_VEL:
        ; Direction-3 (left) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#485B: 32 0B E0
        sub     c                                              ;#485E: 91
        neg                                                    ;#485F: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#4861: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4864: CD 59 57
        ld      hl,(WORLD_X_POS)                               ;#4867: 2A 08 E0
        and     a                                              ;#486A: A7
        ld      a,h                                            ;#486B: 7C
        sbc     hl,de                                          ;#486C: ED 52
        ld      (WORLD_X_POS),hl                               ;#486E: 22 08 E0
        sub     h                                              ;#4871: 94
        ld      (WORLD_SCROLL_DX),a                            ;#4872: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#4875: CD 33 57
        ld      a,h                                            ;#4878: 7C
        add     a,14h                                          ;#4879: C6 14
        ret     p                                              ;#487B: F0
        add     a,4                                            ;#487C: C6 04
        ld      (PLAYER_VELOCITY_X),a                          ;#487E: 32 09 E0
        ld      hl,STEP_COUNTER                                ;#4881: 21 0D E0
        inc     (hl)                                           ;#4884: 34
        inc     (hl)                                           ;#4885: 34
        inc     (hl)                                           ;#4886: 34
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4887: 21 0F E0
        dec     (hl)                                           ;#488A: 35
        ld      hl,TRACK_DATA_RING_END-3                       ;#488B: 21 80 EF
        ld      de,TRACK_DATA_RING_END                         ;#488E: 11 83 EF
        ld      bc,381h                                        ;#4891: 01 81 03
        lddr                                                   ;#4894: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4896: 21 0F E0
        ld      a,(hl)                                         ;#4899: 7E
        sub     4                                              ;#489A: D6 04
        ld      c,a                                            ;#489C: 4F
        inc     hl                                             ;#489D: 23
        ld      a,(hl)                                         ;#489E: 7E
        sub     4                                              ;#489F: D6 04
        ld      l,a                                            ;#48A1: 6F
        ld      h,c                                            ;#48A2: 61
        ld      de,TRACK_DATA_RING                             ;#48A3: 11 00 EC
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#48A6: C3 7B 4A

MOVE_PLAYER_DIRECTION_0:
        ; Direction-0 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#48A9: 3A 09 E0
        ld      c,a                                            ;#48AC: 4F
        and     a                                              ;#48AD: A7
        ld      a,0Ch                                          ;#48AE: 3E 0C
        jp      p,MOVE_DIR0_STORE_VEL                          ;#48B0: F2 B5 48
        ld      a,0F4h                                         ;#48B3: 3E F4
MOVE_DIR0_STORE_VEL:
        ; Direction-0 (up) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#48B5: 32 09 E0
        sub     c                                              ;#48B8: 91
        neg                                                    ;#48B9: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#48BB: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#48BE: CD 33 57
        ld      hl,(WORLD_Y_POS)                               ;#48C1: 2A 0A E0
        and     a                                              ;#48C4: A7
        ld      a,h                                            ;#48C5: 7C
        sbc     hl,de                                          ;#48C6: ED 52
        ld      (WORLD_Y_POS),hl                               ;#48C8: 22 0A E0
        sub     h                                              ;#48CB: 94
        ld      (WORLD_SCROLL_DY),a                            ;#48CC: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#48CF: CD 59 57
        ld      a,h                                            ;#48D2: 7C
        add     a,14h                                          ;#48D3: C6 14
        ret     p                                              ;#48D5: F0
        add     a,4                                            ;#48D6: C6 04
        ld      (PLAYER_VELOCITY_Y),a                          ;#48D8: 32 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#48DB: 21 0C E0
        inc     (hl)                                           ;#48DE: 34
        inc     (hl)                                           ;#48DF: 34
        inc     (hl)                                           ;#48E0: 34
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#48E1: 21 10 E0
        dec     (hl)                                           ;#48E4: 35
        ld      hl,TRACK_DATA_RING_END-5Ah                     ;#48E5: 21 29 EF
        ld      de,TRACK_DATA_RING_END                         ;#48E8: 11 83 EF
        ld      bc,32Ah                                        ;#48EB: 01 2A 03
        lddr                                                   ;#48EE: ED B8
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#48F0: 21 0F E0
        ld      a,(hl)                                         ;#48F3: 7E
        sub     4                                              ;#48F4: D6 04
        ld      c,a                                            ;#48F6: 4F
        inc     hl                                             ;#48F7: 23
        ld      a,(hl)                                         ;#48F8: 7E
        sub     4                                              ;#48F9: D6 04
        ld      l,a                                            ;#48FB: 6F
        ld      h,c                                            ;#48FC: 61
        ld      de,TRACK_DATA_RING                             ;#48FD: 11 00 EC
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#4900: C3 6B 4A

MOVE_PLAYER_DIRECTION_2:
        ; Direction-2 movement handler
        ld      a,(PLAYER_VELOCITY_X)                          ;#4903: 3A 09 E0
        ld      c,a                                            ;#4906: 4F
        and     a                                              ;#4907: A7
        ld      a,0Ch                                          ;#4908: 3E 0C
        jp      p,MOVE_DIR2_STORE_VEL                          ;#490A: F2 0F 49
        ld      a,0F4h                                         ;#490D: 3E F4
MOVE_DIR2_STORE_VEL:
        ; Direction-2 (right) store: write WORLD_SCROLL_DX before applying velocity sign
        ld      (PLAYER_VELOCITY_X),a                          ;#490F: 32 09 E0
        sub     c                                              ;#4912: 91
        neg                                                    ;#4913: ED 44
        ld      (WORLD_SCROLL_DX),a                            ;#4915: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#4918: CD 33 57
        ld      hl,(WORLD_Y_POS)                               ;#491B: 2A 0A E0
        ld      a,h                                            ;#491E: 7C
        add     hl,de                                          ;#491F: 19
        ld      (WORLD_Y_POS),hl                               ;#4920: 22 0A E0
        sub     h                                              ;#4923: 94
        ld      (WORLD_SCROLL_DY),a                            ;#4924: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4927: CD 59 57
        ld      a,h                                            ;#492A: 7C
        sub     15h                                            ;#492B: D6 15
        ret     m                                              ;#492D: F8
        sub     3                                              ;#492E: D6 03
        ld      (PLAYER_VELOCITY_Y),a                          ;#4930: 32 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#4933: 21 0C E0
        dec     (hl)                                           ;#4936: 35
        dec     (hl)                                           ;#4937: 35
        dec     (hl)                                           ;#4938: 35
        ld      hl,PLAYER_WORLD_POSITION_Y                     ;#4939: 21 10 E0
        inc     (hl)                                           ;#493C: 34
        ld      hl,TRACK_DATA_RING+5Ah    ; 2nd enemy-path record ;#493D: 21 5A EC
        ld      de,TRACK_DATA_RING                             ;#4940: 11 00 EC
        ld      bc,32Ah                                        ;#4943: 01 2A 03
        ldir                                                   ;#4946: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4948: 21 0F E0
        ld      a,(hl)                                         ;#494B: 7E
        sub     4                                              ;#494C: D6 04
        ld      c,a                                            ;#494E: 4F
        inc     hl                                             ;#494F: 23
        ld      a,(hl)                                         ;#4950: 7E
        add     a,5                                            ;#4951: C6 05
        ld      l,a                                            ;#4953: 6F
        ld      h,c                                            ;#4954: 61
        ld      de,TRACK_DATA_RING_END-59h                     ;#4955: 11 2A EF
        jp      SCAN_PLAYFIELD_H_STRIP                         ;#4958: C3 6B 4A

MOVE_PLAYER_DIRECTION_1:
        ; Direction-1 movement handler
        ld      a,(PLAYER_VELOCITY_Y)                          ;#495B: 3A 0B E0
        ld      c,a                                            ;#495E: 4F
        and     a                                              ;#495F: A7
        ld      a,0Ch                                          ;#4960: 3E 0C
        jp      p,MOVE_DIR1_STORE_VEL                          ;#4962: F2 67 49
        ld      a,0F4h                                         ;#4965: 3E F4
MOVE_DIR1_STORE_VEL:
        ; Direction-1 (down) store: write WORLD_SCROLL_DY before applying velocity sign
        ld      (PLAYER_VELOCITY_Y),a                          ;#4967: 32 0B E0
        sub     c                                              ;#496A: 91
        neg                                                    ;#496B: ED 44
        ld      (WORLD_SCROLL_DY),a                            ;#496D: 32 17 E0
        call    ADD_DE_TO_ENEMY_Y                              ;#4970: CD 59 57
        ld      hl,(WORLD_X_POS)                               ;#4973: 2A 08 E0
        ld      a,h                                            ;#4976: 7C
        add     hl,de                                          ;#4977: 19
        ld      (WORLD_X_POS),hl                               ;#4978: 22 08 E0
        sub     h                                              ;#497B: 94
        ld      (WORLD_SCROLL_DX),a                            ;#497C: 32 16 E0
        call    ADD_DE_TO_ENEMY_X                              ;#497F: CD 33 57
        ld      a,h                                            ;#4982: 7C
        sub     15h                                            ;#4983: D6 15
        ret     m                                              ;#4985: F8
        sub     3                                              ;#4986: D6 03
        ld      (PLAYER_VELOCITY_X),a                          ;#4988: 32 09 E0
        ld      hl,STEP_COUNTER                                ;#498B: 21 0D E0
        dec     (hl)                                           ;#498E: 35
        dec     (hl)                                           ;#498F: 35
        dec     (hl)                                           ;#4990: 35
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#4991: 21 0F E0
        inc     (hl)                                           ;#4994: 34
        ld      hl,TRACK_DATA_RING+3                           ;#4995: 21 03 EC
        ld      de,TRACK_DATA_RING                             ;#4998: 11 00 EC
        ld      bc,381h                                        ;#499B: 01 81 03
        ldir                                                   ;#499E: ED B0
        ld      hl,PLAYER_WORLD_POSITION_X                     ;#49A0: 21 0F E0
        ld      a,(hl)                                         ;#49A3: 7E
        add     a,5                                            ;#49A4: C6 05
        ld      c,a                                            ;#49A6: 4F
        inc     hl                                             ;#49A7: 23
        ld      a,(hl)                                         ;#49A8: 7E
        sub     4                                              ;#49A9: D6 04
        ld      l,a                                            ;#49AB: 6F
        ld      h,c                                            ;#49AC: 61
        ld      de,TRACK_DATA_RING+1Bh                         ;#49AD: 11 1B EC
        jp      SCAN_PLAYFIELD_L_STRIP                         ;#49B0: C3 7B 4A

DEPLOY_SMOKE_IF_INPUT:
        ; Check input + fuel via POLL_INPUT; if available, drop fuel and refresh gauge
        ; DEPLOY_SMOKE_IF_INPUT. Polls input via POLL_INPUT; if a smoke-deploy key is
        ; held AND SMOKE_COOLDOWN is 0 AND FUEL_LEVEL > 3, deducts 3 from fuel,
        ; refreshes UPDATE_FUEL_GAUGE, sets SMOKE_COOLDOWN=3 frames. The actual smoke
        ; entity spawn happens elsewhere in the smoke subsystem.
        push    hl                                             ;#49B3: E5
        push    de                                             ;#49B4: D5
        call    POLL_INPUT                                     ;#49B5: CD C0 4C
        ld      a,(STAGE_PALETTE_INDEX)                        ;#49B8: 3A 30 E0
        cpl                                                    ;#49BB: 2F
        and     3                                              ;#49BC: E6 03
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49BE: 28 22
        ld      a,c                                            ;#49C0: 79
        cpl                                                    ;#49C1: 2F
        and     0F0h                                           ;#49C2: E6 F0
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49C4: 28 1C
        ld      a,(SMOKE_COOLDOWN)                             ;#49C6: 3A 27 E0
        and     a                                              ;#49C9: A7
        jr      nz,PROCESS_DIRECTION_INPUT                     ;#49CA: 20 16
        ld      a,(FUEL_LEVEL)                                 ;#49CC: 3A 39 E0
        sub     3                                              ;#49CF: D6 03
        jr      c,PROCESS_DIRECTION_INPUT                      ;#49D1: 38 0F
        jr      z,PROCESS_DIRECTION_INPUT                      ;#49D3: 28 0D
        ld      (FUEL_LEVEL),a                                 ;#49D5: 32 39 E0
        push    bc                                             ;#49D8: C5
        call    UPDATE_FUEL_GAUGE                              ;#49D9: CD 65 71
        pop     bc                                             ;#49DC: C1
        ld      a,3                                            ;#49DD: 3E 03
        ld      (SMOKE_COOLDOWN),a                             ;#49DF: 32 27 E0
PROCESS_DIRECTION_INPUT:
        ; Map 4 input bits (up/right/down/left) into TRY_SET_DIRECTION calls
        ; PROCESS_DIRECTION_INPUT takes the input mask in B (one bit per direction) and
        ; tests each bit, calling TRY_SET_DIRECTION with the appropriate direction code
        ; (0=up, 1=left, 2=right, 3=down). Earlier direction bits dominate — diagonal
        ; inputs resolve to vertical.
        ld      b,c                                            ;#49E2: 41
        ld      c,0                                            ;#49E3: 0E 00
        bit     0,b                                            ;#49E5: CB 40
        call    z,TRY_SET_DIRECTION                            ;#49E7: CC 02 4A
        ld      c,2                                            ;#49EA: 0E 02
        bit     1,b                                            ;#49EC: CB 48
        call    z,TRY_SET_DIRECTION                            ;#49EE: CC 02 4A
        ld      c,3                                            ;#49F1: 0E 03
        bit     2,b                                            ;#49F3: CB 50
        call    z,TRY_SET_DIRECTION                            ;#49F5: CC 02 4A
        ld      c,1                                            ;#49F8: 0E 01
        bit     3,b                                            ;#49FA: CB 58
        call    z,TRY_SET_DIRECTION                            ;#49FC: CC 02 4A
        pop     de                                             ;#49FF: D1
        pop     hl                                             ;#4A00: E1
        ret                                                    ;#4A01: C9

TRY_SET_DIRECTION:
        ; Inner: if dir C differs from PLAYER_DIRECTION, validate path then update
        ; TRY_SET_DIRECTION is the inner direction-update helper. The `inc sp; inc sp`
        ; at entry and `dec sp; dec sp` later discard the caller's return address
        ; temporarily — a stack-pointer trick that lets it return TWO frames up to
        ; PROCESS_DIRECTION_INPUT's caller when direction acceptance succeeds. Verifies
        ; the proposed direction via CHECK_DIRECTION_BLOCKED before updating
        ; PLAYER_DIRECTION.
        inc     sp                                             ;#4A02: 33
        inc     sp                                             ;#4A03: 33
        ld      a,(PLAYER_DIRECTION)                           ;#4A04: 3A 11 E0
        cp      c                                              ;#4A07: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A08: 28 18
        xor     2                                              ;#4A0A: EE 02
        cp      c                                              ;#4A0C: B9
        jr      z,TRY_SET_DIRECTION_END                        ;#4A0D: 28 13
        pop     de                                             ;#4A0F: D1
        push    de                                             ;#4A10: D5
        dec     sp                                             ;#4A11: 3B
        dec     sp                                             ;#4A12: 3B
        ld      a,d                                            ;#4A13: 7A
        cp      5                                              ;#4A14: FE 05
        ret     nc                                             ;#4A16: D0
        ld      a,e                                            ;#4A17: 7B
        cp      5                                              ;#4A18: FE 05
        ret     nc                                             ;#4A1A: D0
        push    bc                                             ;#4A1B: C5
        call    CHECK_DIRECTION_BLOCKED                        ;#4A1C: CD 50 4A
        pop     bc                                             ;#4A1F: C1
        ret     c                                              ;#4A20: D8
        pop     hl                                             ;#4A21: E1
TRY_SET_DIRECTION_END:
        ; Tail of TRY_SET_DIRECTION: restore sp adjustment, ret to outer caller
        pop     de                                             ;#4A22: D1
        pop     hl                                             ;#4A23: E1
AI_DIR_FOUND:
        ; Found unblocked direction: mask to 2 bits, store as PLAYER_DIRECTION
        ld      a,c                                            ;#4A24: 79
        and     3                                              ;#4A25: E6 03
        ld      (PLAYER_DIRECTION),a                           ;#4A27: 32 11 E0
        ret                                                    ;#4A2A: C9

AI_PICK_VALID_DIRECTION:
        ; Try alternate directions via CHECK_DIRECTION_BLOCKED, set PLAYER_DIRECTION
        ; AI_PICK_VALID_DIRECTION tries up to 4 directions and picks the first non-
        ; blocked one. Calls CHECK_DIRECTION_BLOCKED for each candidate (which returns
        ; carry=1 when blocked). The picked direction is stored in PLAYER_DIRECTION.
        ; Used by both player movement and enemy AI to navigate around obstacles.
        ld      c,a                                            ;#4A2B: 4F
        ld      a,e                                            ;#4A2C: 7B
        cp      5                                              ;#4A2D: FE 05
        ret     nc                                             ;#4A2F: D0
        ld      a,d                                            ;#4A30: 7A
        cp      5                                              ;#4A31: FE 05
        ret     nc                                             ;#4A33: D0
        ld      d,h                                            ;#4A34: 54
        ld      e,l                                            ;#4A35: 5D
        call    CHECK_DIRECTION_BLOCKED                        ;#4A36: CD 50 4A
        jr      nc,AI_DIR_FOUND                                ;#4A39: 30 E9
        ld      h,d                                            ;#4A3B: 62
        ld      l,e                                            ;#4A3C: 6B
        inc     c                                              ;#4A3D: 0C
        call    CHECK_DIRECTION_BLOCKED                        ;#4A3E: CD 50 4A
        jr      nc,AI_DIR_FOUND                                ;#4A41: 30 E1
        inc     c                                              ;#4A43: 0C
        inc     c                                              ;#4A44: 0C
        ld      h,d                                            ;#4A45: 62
        ld      l,e                                            ;#4A46: 6B
        call    CHECK_DIRECTION_BLOCKED                        ;#4A47: CD 50 4A
        jr      nc,AI_DIR_FOUND                                ;#4A4A: 30 D8
        dec     c                                              ;#4A4C: 0D
        jp      AI_DIR_FOUND                                   ;#4A4D: C3 24 4A

CHECK_DIRECTION_BLOCKED:
        ; Test if direction C is blocked; returns carry-set when blocked
        ; CHECK_DIRECTION_BLOCKED tests if direction C is blocked. Looks up the
        ; playfield cell adjacent to the current position in that direction via
        ; QUERY_PLAYFIELD_AT; returns carry=1 (blocked) if the cell is a rock/wall,
        ; carry=0 (free) otherwise. Called many times per frame by
        ; AI_PICK_VALID_DIRECTION and player movement.
        ld      a,c                                            ;#4A50: 79
        and     3                                              ;#4A51: E6 03
        jr      z,DIR_BLOCKED_LEFT                             ;#4A53: 28 0A
        dec     a                                              ;#4A55: 3D
        jr      z,DIR_BLOCKED_DOWN                             ;#4A56: 28 0B
        dec     a                                              ;#4A58: 3D
        jr      z,DIR_BLOCKED_RIGHT                            ;#4A59: 28 0C
        dec     h                                              ;#4A5B: 25
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A5C: C3 7C 4B

DIR_BLOCKED_LEFT:
        ; Direction LEFT blocked path: dec L then jump to LOOKUP_PLAYFIELD_CELL
        dec     l                                              ;#4A5F: 2D
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A60: C3 7C 4B

DIR_BLOCKED_DOWN:
        ; Direction DOWN blocked path: inc H then jump to LOOKUP_PLAYFIELD_CELL
        inc     h                                              ;#4A63: 24
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A64: C3 7C 4B

DIR_BLOCKED_RIGHT:
        ; Direction RIGHT blocked path: inc L then jump to LOOKUP_PLAYFIELD_CELL
        inc     l                                              ;#4A67: 2C
        jp      LOOKUP_PLAYFIELD_CELL                          ;#4A68: C3 7C 4B

SCAN_PLAYFIELD_H_STRIP:
        ; Loop 10 cells along H axis (stride 3), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_H_STRIP scans 10 cells horizontally (along H axis, E += 3 per
        ; cell), invoking QUERY_PLAYFIELD_AT for each. Used by AI routines to find the
        ; closest rock/flag in a row.
        ld      b,0Ah                                          ;#4A6B: 06 0A
SCAN_H_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_H_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A6D: CD 8B 4A
        inc     h                                              ;#4A70: 24
        ld      a,e                                            ;#4A71: 7B
        add     a,3                                            ;#4A72: C6 03
        ld      e,a                                            ;#4A74: 5F
        jr      nc,SCAN_H_STRIP_NEXT                           ;#4A75: 30 01
        inc     d                                              ;#4A77: 14
SCAN_H_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_H_STRIP (H += 1, E += 3)
        djnz    SCAN_H_STRIP_TOP                               ;#4A78: 10 F3
        ret                                                    ;#4A7A: C9

SCAN_PLAYFIELD_L_STRIP:
        ; Loop 10 cells along L axis (stride 5Ah), call QUERY_PLAYFIELD_AT each
        ; SCAN_PLAYFIELD_L_STRIP is the L-axis equivalent (L += 0Ah per cell, E += 5Ah
        ; per cell — wider stride). Both share QUERY_PLAYFIELD_AT.
        ld      b,0Ah                                          ;#4A7B: 06 0A
SCAN_L_STRIP_TOP:
        ; Inner djnz loop of SCAN_PLAYFIELD_L_STRIP
        call    QUERY_PLAYFIELD_AT                             ;#4A7D: CD 8B 4A
        inc     l                                              ;#4A80: 2C
        ld      a,e                                            ;#4A81: 7B
        add     a,5Ah                                          ;#4A82: C6 5A
        ld      e,a                                            ;#4A84: 5F
        jr      nc,SCAN_L_STRIP_NEXT                           ;#4A85: 30 01
        inc     d                                              ;#4A87: 14
SCAN_L_STRIP_NEXT:
        ; Inner djnz advance for SCAN_PLAYFIELD_L_STRIP (L += 1, E += 5Ah)
        djnz    SCAN_L_STRIP_TOP                               ;#4A88: 10 F3
        ret                                                    ;#4A8A: C9

QUERY_PLAYFIELD_AT:
        ; Lookup playfield cell at (H, L) via PLAYFIELD_LOOKUP_TABLE
        ; QUERY_PLAYFIELD_AT looks up (H, L) coord in PLAYFIELD_LOOKUP_TABLE
        ; (PLAYFIELD_LOOKUP_TABLE). H>=20h uses one branch (returns from a higher tier
        ; of the table at PLAYFIELD_LOOKUP_OUT_OF_BOUNDS); H<20h takes the in-bounds
        ; path indexing PLAYFIELD_ LOOKUP_TABLE. Returns the cell value in A — used to
        ; detect rocks, walls, flag positions for AI and movement.
        push    bc                                             ;#4A8B: C5
        push    de                                             ;#4A8C: D5
        push    hl                                             ;#4A8D: E5
        ld      a,h                                            ;#4A8E: 7C
        cp      20h                                            ;#4A8F: FE 20
        jr      c,QUERY_IN_BOUNDS                              ;#4A91: 38 15
        inc     a                                              ;#4A93: 3C
        jr      nz,QUERY_OUT_OF_BOUNDS                         ;#4A94: 20 2A
        ld      a,l                                            ;#4A96: 7D
        cp      39h                                            ;#4A97: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4A99: 30 25
        ld      hl,PLAYFIELD_LOOKUP_OUT_OF_BOUNDS              ;#4A9B: 21 20 FB
        add     a,l                                            ;#4A9E: 85
        ld      l,a                                            ;#4A9F: 6F
        ld      a,0                                            ;#4AA0: 3E 00
        adc     a,h                                            ;#4AA2: 8C
        ld      h,a                                            ;#4AA3: 67
        ld      a,(hl)                                         ;#4AA4: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4AA5: C3 C2 4A

QUERY_IN_BOUNDS:
        ; In-bounds path: compute PLAYFIELD_LOOKUP_TABLE row index
        ld      c,a                                            ;#4AA8: 4F
        ld      a,l                                            ;#4AA9: 7D
        cp      39h                                            ;#4AAA: FE 39
        jr      nc,QUERY_OUT_OF_BOUNDS                         ;#4AAC: 30 12
        ld      h,0                                            ;#4AAE: 26 00
        add     hl,hl                                          ;#4AB0: 29
        add     hl,hl                                          ;#4AB1: 29
        add     hl,hl                                          ;#4AB2: 29
        add     hl,hl                                          ;#4AB3: 29
        add     hl,hl                                          ;#4AB4: 29
        ld      a,c                                            ;#4AB5: 79
        add     a,l                                            ;#4AB6: 85
        ld      l,a                                            ;#4AB7: 6F
        ld      bc,PLAYFIELD_LOOKUP_TABLE                      ;#4AB8: 01 00 F4
        add     hl,bc                                          ;#4ABB: 09
        ld      a,(hl)                                         ;#4ABC: 7E
        jp      QUERY_PLAYFIELD_EMIT                           ;#4ABD: C3 C2 4A

QUERY_OUT_OF_BOUNDS:
        ; Out-of-bounds path: substitute cell value 87h (no playfield)
        ld      a,87h                                          ;#4AC0: 3E 87
QUERY_PLAYFIELD_EMIT:
        ; Copy a cell's 3x3 block (9 bytes) to 3 tile-buffer rows at DE +0/+1Eh/+3Ch
        ld      hl,PLAYFIELD_CELL_TILES                        ;#4AC2: 21 EC 4A
        add     a,l                                            ;#4AC5: 85
        ld      l,a                                            ;#4AC6: 6F
        ld      a,0                                            ;#4AC7: 3E 00
        adc     a,h                                            ;#4AC9: 8C
        ld      h,a                                            ;#4ACA: 67
        ld      bc,3                                           ;#4ACB: 01 03 00
        ldir                                                   ;#4ACE: ED B0
        ld      a,e                                            ;#4AD0: 7B
        add     a,1Bh                                          ;#4AD1: C6 1B
        ld      e,a                                            ;#4AD3: 5F
        ld      a,0                                            ;#4AD4: 3E 00
        adc     a,d                                            ;#4AD6: 8A
        ld      d,a                                            ;#4AD7: 57
        ld      c,3                                            ;#4AD8: 0E 03
        ldir                                                   ;#4ADA: ED B0
        ld      a,e                                            ;#4ADC: 7B
        add     a,1Bh                                          ;#4ADD: C6 1B
        ld      e,a                                            ;#4ADF: 5F
        ld      a,0                                            ;#4AE0: 3E 00
        adc     a,d                                            ;#4AE2: 8A
        ld      d,a                                            ;#4AE3: 57
        ld      c,3                                            ;#4AE4: 0E 03
        ldir                                                   ;#4AE6: ED B0
        pop     hl                                             ;#4AE8: E1
        pop     de                                             ;#4AE9: D1
        pop     bc                                             ;#4AEA: C1
        ret                                                    ;#4AEB: C9

PLAYFIELD_CELL_TILES:
        ; Maze cell -> 3x3 tile block (16 cells, chars 80h+); paints the tile buffer
        PLAYFIELD_TILES "8C8C8C", "8C8C8C", "8C8C8C"           ;#4AEC: 8C 8C 8C 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C80", "8C8C81", "8C8C81"           ;#4AF5: 8C 8C 80 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8C8C82", "8C8C8C", "8C8C8C"           ;#4AFE: 8C 8C 82 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "8C8C81", "8C8C81", "8C8C81"           ;#4B07: 8C 8C 81 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858587", "8C8C8C", "8C8C8C"           ;#4B10: 85 85 87 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B19: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "858585", "8C8C8C", "8C8C8C"           ;#4B22: 85 85 85 8C 8C 8C 8C 8C 8C
        PLAYFIELD_TILES "85858E", "8C8C81", "8C8C81"           ;#4B2B: 85 85 8E 8C 8C 81 8C 8C 81
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B34: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8D", "848484", "848484"           ;#4B3D: 8D 8D 8D 84 84 84 84 84 84
        PLAYFIELD_TILES "8D8D86", "848489", "848489"           ;#4B46: 8D 8D 86 84 84 89 84 84 89
        PLAYFIELD_TILES "8D8D8F", "848484", "848484"           ;#4B4F: 8D 8D 8F 84 84 84 84 84 84
        PLAYFIELD_TILES "848489", "848489", "848489"           ;#4B58: 84 84 89 84 84 89 84 84 89
        PLAYFIELD_TILES "84848A", "848484", "848484"           ;#4B61: 84 84 8A 84 84 84 84 84 84
        PLAYFIELD_TILES "848488", "848489", "848489"           ;#4B6A: 84 84 88 84 84 89 84 84 89
        PLAYFIELD_TILES "848484", "848484", "848484"           ;#4B73: 84 84 84 84 84 84 84 84 84

LOOKUP_PLAYFIELD_CELL:
        ; Given (H, L) map coord, index MAZE_BITMAP_N per STAGE_PALETTE_INDEX
        ; LOOKUP_PLAYFIELD_CELL takes (H, L) as a map coordinate and returns the
        ; playfield cell value in BC. Indexes MAZE_BITMAP_N at
        ; MAZE_BITMAP_0..MAZE_BITMAP_3 at offset based on STAGE_PALETTE_INDEX (top bits)
        ; + coord. Returns cell type so callers can distinguish rock vs flag vs road.
        push    bc                                             ;#4B7C: C5
        ld      bc,MAZE_BITMAP_0                               ;#4B7D: 01 00 7C
        ld      a,l                                            ;#4B80: 7D
        cp      38h                                            ;#4B81: FE 38
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B83: 30 25
        add     a,a                                            ;#4B85: 87
        add     a,a                                            ;#4B86: 87
        ld      c,a                                            ;#4B87: 4F
        ld      a,h                                            ;#4B88: 7C
        cp      20h                                            ;#4B89: FE 20
        jr      nc,LOOKUP_OUT_OF_BOUNDS                        ;#4B8B: 30 1D
        rra                                                    ;#4B8D: 1F
        rra                                                    ;#4B8E: 1F
        rra                                                    ;#4B8F: 1F
        and     3                                              ;#4B90: E6 03
        or      c                                              ;#4B92: B1
        ld      c,a                                            ;#4B93: 4F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#4B94: 3A 30 E0
        rra                                                    ;#4B97: 1F
        rra                                                    ;#4B98: 1F
        and     3                                              ;#4B99: E6 03
        or      b                                              ;#4B9B: B0
        ld      b,a                                            ;#4B9C: 47
        ld      a,(bc)                                         ;#4B9D: 0A
        push    af                                             ;#4B9E: F5
        ld      a,h                                            ;#4B9F: 7C
        and     7                                              ;#4BA0: E6 07
        inc     a                                              ;#4BA2: 3C
        ld      b,a                                            ;#4BA3: 47
        pop     af                                             ;#4BA4: F1
LOOKUP_SHIFT_LOOP:
        ; Inner djnz of LOOKUP_PLAYFIELD_CELL (bit-extract per row)
        add     a,a                                            ;#4BA5: 87
        djnz    LOOKUP_SHIFT_LOOP                              ;#4BA6: 10 FD
        pop     bc                                             ;#4BA8: C1
        ret                                                    ;#4BA9: C9

LOOKUP_OUT_OF_BOUNDS:
        ; Coord out of range: set carry and return (signal blocked cell)
        scf                                                    ;#4BAA: 37
        pop     bc                                             ;#4BAB: C1
        ret                                                    ;#4BAC: C9

PLAYFIELD_TILE_LOOKUP:
        ; Helper called by INIT_PLAYFIELD_LOOKUP to compute one cell's value
        ld      c,0                                            ;#4BAD: 0E 00
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BAF: CD 7C 4B
        rl      c                                              ;#4BB2: CB 11
        dec     l                                              ;#4BB4: 2D
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BB5: CD 7C 4B
        rl      c                                              ;#4BB8: CB 11
        inc     h                                              ;#4BBA: 24
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BBB: CD 7C 4B
        rl      c                                              ;#4BBE: CB 11
        inc     l                                              ;#4BC0: 2C
        call    LOOKUP_PLAYFIELD_CELL                          ;#4BC1: CD 7C 4B
        rl      c                                              ;#4BC4: CB 11
        ret                                                    ;#4BC6: C9

INIT_PLAYFIELD_LOOKUP:
        ; Build PLAYFIELD_LOOKUP_TABLE over coords 0..38h x 0..1Fh
        ; INIT_PLAYFIELD_LOOKUP builds a precomputed lookup table at
        ; PLAYFIELD_LOOKUP_TABLE (~1800 bytes). Iterates a 32x57 grid (l=0..38h,
        ; h=0..1Fh), calling PLAYFIELD_TILE_LOOKUP per cell to compute one 9-byte sub-
        ; record. The table speeds up per-frame queries via QUERY_PLAYFIELD_AT (replaces
        ; an arithmetic recompute with an indexed read).
        ld      de,PLAYFIELD_LOOKUP_TABLE                      ;#4BC7: 11 00 F4
        ld      hl,0                                           ;#4BCA: 21 00 00
INIT_LOOKUP_LOOP:
        ; INIT_PLAYFIELD_LOOKUP main grid loop: H over 0..1Fh, L stays
        push    hl                                             ;#4BCD: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BCE: CD AD 4B
        pop     hl                                             ;#4BD1: E1
        ld      a,c                                            ;#4BD2: 79
        add     a,a                                            ;#4BD3: 87
        add     a,a                                            ;#4BD4: 87
        add     a,a                                            ;#4BD5: 87
        add     a,c                                            ;#4BD6: 81
        ld      (de),a                                         ;#4BD7: 12
        inc     de                                             ;#4BD8: 13
        inc     h                                              ;#4BD9: 24
        ld      a,h                                            ;#4BDA: 7C
        cp      20h                                            ;#4BDB: FE 20
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BDD: 20 EE
        ld      h,0                                            ;#4BDF: 26 00
        inc     l                                              ;#4BE1: 2C
        ld      a,l                                            ;#4BE2: 7D
        cp      39h                                            ;#4BE3: FE 39
        jr      nz,INIT_LOOKUP_LOOP                            ;#4BE5: 20 E6
        ld      hl,0FF00h                                      ;#4BE7: 21 00 FF
INIT_LOOKUP_TAIL_LOOP:
        ; INIT_PLAYFIELD_LOOKUP tail loop with H=FF (wrap-around row at top)
        push    hl                                             ;#4BEA: E5
        call    PLAYFIELD_TILE_LOOKUP                          ;#4BEB: CD AD 4B
        pop     hl                                             ;#4BEE: E1
        ld      a,c                                            ;#4BEF: 79
        add     a,a                                            ;#4BF0: 87
        add     a,a                                            ;#4BF1: 87
        add     a,a                                            ;#4BF2: 87
        add     a,c                                            ;#4BF3: 81
        ld      (de),a                                         ;#4BF4: 12
        inc     de                                             ;#4BF5: 13
        inc     l                                              ;#4BF6: 2C
        ld      a,l                                            ;#4BF7: 7D
        cp      39h                                            ;#4BF8: FE 39
        jr      nz,INIT_LOOKUP_TAIL_LOOP                       ;#4BFA: 20 EE
        ret                                                    ;#4BFC: C9

INIT_STAGE_TRACK_DATA:
        ; Initialize TRACK_DATA_RING region (10 x 0x5A blocks) with stage path/track state
        ; INIT_STAGE_TRACK_DATA initializes TRACK_DATA_RING. Sets up two 16-bit pointers
        ; (WORLD_X_POS = WORLD_Y_POS = F400h, PLAYER_WORLD_POSITION_X = 320Fh,
        ; PLAYFIELD_SCROLL_OFFSET = 0). Then loops 10 times, calling
        ; SCAN_PLAYFIELD_H_STRIP with HL=0B2Eh and DE walking by 0x5A per iter —
        ; populates the 10 enemy-car path/track records.
        ld      hl,PLAYFIELD_LOOKUP_TABLE                      ;#4BFD: 21 00 F4
        ld      (WORLD_X_POS),hl                               ;#4C00: 22 08 E0
        ld      (WORLD_Y_POS),hl                               ;#4C03: 22 0A E0
        ld      hl,320Fh                                       ;#4C06: 21 0F 32
        ld      (PLAYER_WORLD_POSITION_X),hl                   ;#4C09: 22 0F E0
        ld      hl,0                                           ;#4C0C: 21 00 00
        ld      (PLAYFIELD_SCROLL_OFFSET),hl                   ;#4C0F: 22 12 E0
        call    INIT_PLAYFIELD_LOOKUP                          ;#4C12: CD C7 4B
        ld      b,0Ah                                          ;#4C15: 06 0A
        ld      de,TRACK_DATA_RING                             ;#4C17: 11 00 EC
        ld      hl,0B2Eh                                       ;#4C1A: 21 2E 0B
INIT_TRACK_DATA_LOOP:
        ; Inner djnz of INIT_STAGE_TRACK_DATA (10 enemy paths)
        push    hl                                             ;#4C1D: E5
        push    de                                             ;#4C1E: D5
        push    bc                                             ;#4C1F: C5
        call    SCAN_PLAYFIELD_H_STRIP                         ;#4C20: CD 6B 4A
        pop     bc                                             ;#4C23: C1
        pop     de                                             ;#4C24: D1
        ld      hl,5Ah                                         ;#4C25: 21 5A 00
        add     hl,de                                          ;#4C28: 19
        ex      de,hl                                          ;#4C29: EB
        pop     hl                                             ;#4C2A: E1
        inc     l                                              ;#4C2B: 2C
        djnz    INIT_TRACK_DATA_LOOP                           ;#4C2C: 10 EF
        ret                                                    ;#4C2E: C9

INIT_ENEMY_CARS:
        ; Clear ENEMY_CAR_TABLE (0x6F bytes) and reset ENEMY_CAR_ITER_TIMER to 70h
        ; INIT_ENEMY_CARS clears 6Fh bytes of ENEMY_CAR_TABLE to 0 and resets
        ; ENEMY_CAR_ITER_TIMER to 70h. Then loads stage-specific seed data from
        ; INITIAL_ENEMY_CARS_DATA using STAGE_ENEMY_SEED_LEN bytes worth.
        ld      a,70h                                          ;#4C2F: 3E 70
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#4C31: 32 1D E0
        ld      hl,ENEMY_CAR_TABLE                             ;#4C34: 21 00 E3
        ld      de,ENEMY_CAR_TABLE_TAIL                        ;#4C37: 11 01 E3
        ld      bc,6Fh                                         ;#4C3A: 01 6F 00
        ld      (hl),0                                         ;#4C3D: 36 00
        ldir                                                   ;#4C3F: ED B0
        ld      hl,INITIAL_ENEMY_CARS_DATA                     ;#4C41: 21 50 4C
        ld      de,ENEMY_CAR_TABLE                             ;#4C44: 11 00 E3
        ld      a,(STAGE_ENEMY_SEED_LEN)                       ;#4C47: 3A 40 E0
        ld      c,a                                            ;#4C4A: 4F
        ld      b,0                                            ;#4C4B: 06 00
        ldir                                                   ;#4C4D: ED B0
        ret                                                    ;#4C4F: C9

INITIAL_ENEMY_CARS_DATA:
        ; Stage-specific initial ENEMY_CAR_TABLE state (STAGE_ENEMY_SEED_LEN bytes)
        ; INITIAL_ENEMY_CARS_DATA holds the stage-specific seed for ENEMY_CAR_TABLE.
        ; STAGE_ENEMY_SEED_LEN bytes (=enemies*16) get copied in by INIT_ENEMY_CARS.
        ; Each 16-byte enemy record encodes type, initial position, direction, and AI
        ; state, rendered as the four ENEMY_SEED_1/_2/_3/_4 macro calls. Enemy car 1
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C50: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4C53: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=58h, screen_y=9Fh    ;#4C58: 34 58 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C5D: 00 06 00
        ; Enemy car 2
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C60: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4C63: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=88h, screen_y=9Fh    ;#4C68: 34 88 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C6D: 00 06 00
        ; Enemy car 3
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C70: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Dh, y_accum=0C00h  ;#4C73: 00 0C 0D 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=28h, screen_y=9Fh    ;#4C78: 34 28 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C7D: 00 06 00
        ; Enemy car 4
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C80: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=13h, y_accum=0C00h  ;#4C83: 00 0C 13 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0B8h, screen_y=9Fh   ;#4C88: 34 B8 00 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C8D: 00 06 00
        ; Enemy car 5
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4C90: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Bh, y_accum=0C00h  ;#4C93: 00 0C 0B 00 0C
        ENEMY_SEED_3 cell_y=34h, screen_x=0FFF8h, screen_y=9Fh ;#4C98: 34 F8 FF 9F 00
        ENEMY_SEED_4 pattern=0, color=6, dir=0                 ;#4C9D: 00 06 00
        ; Enemy car 6
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CA0: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=0Fh, y_accum=0C00h  ;#4CA3: 00 0C 0F 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=58h, screen_y=0FBEFh   ;#4CA8: 02 58 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CAD: 24 06 02
        ; Enemy car 7
        ENEMY_SEED_1 type=1, timer=70h, state=4                ;#4CB0: 01 70 04
        ENEMY_SEED_2 x_accum=0C00h, cell_x=11h, y_accum=0C00h  ;#4CB3: 00 0C 11 00 0C
        ENEMY_SEED_3 cell_y=2, screen_x=88h, screen_y=0FBEFh   ;#4CB8: 02 88 00 EF FB
        ENEMY_SEED_4 pattern=24h, color=6, dir=2               ;#4CBD: 24 06 02
POLL_INPUT:
        ; Read PSG R14 joystick + SNSMAT row 8 keys; return combined input bits in C
        ; POLL_INPUT reads both joystick (via PSG R14 after configuring R15 as output
        ; via SET_PSG_REG) AND keyboard (SNSMAT row 8) and OR-combines them into C. Each
        ; direction/button has a unique bit in C. The combined state then feeds
        ; PROCESS_DIRECTION_INPUT and DEPLOY_SMOKE_IF_INPUT.
        ld      a,0Fh                                          ;#4CC0: 3E 0F
        ld      e,8Fh                                          ;#4CC2: 1E 8F
        call    BIOS_WRTPSG                                    ;#4CC4: CD 93 00
        ld      a,0Eh                                          ;#4CC7: 3E 0E
        call    BIOS_RDPSG                                     ;#4CC9: CD 96 00
        or      0C0h                                           ;#4CCC: F6 C0
        ld      c,a                                            ;#4CCE: 4F
        ld      a,8                                            ;#4CCF: 3E 08
        call    SNSMAT_PRESERVE_BC                             ;#4CD1: CD FE 4C
        rla                                                    ;#4CD4: 17
        jr      c,POLL_KEY_LEFT_DONE                           ;#4CD5: 38 02
        res     3,c                                            ;#4CD7: CB 99
POLL_KEY_LEFT_DONE:
        ; After clearing LEFT bit, fall through to DOWN probe
        rla                                                    ;#4CD9: 17
        jr      c,POLL_KEY_DOWN_DONE                           ;#4CDA: 38 02
        res     1,c                                            ;#4CDC: CB 89
POLL_KEY_DOWN_DONE:
        ; After clearing DOWN bit, fall through to UP probe
        rla                                                    ;#4CDE: 17
        jr      c,POLL_KEY_UP_DONE                             ;#4CDF: 38 02
        res     0,c                                            ;#4CE1: CB 81
POLL_KEY_UP_DONE:
        ; After clearing UP bit, fall through to RIGHT probe
        rla                                                    ;#4CE3: 17
        jr      c,POLL_KEY_RIGHT_DONE                          ;#4CE4: 38 02
        res     2,c                                            ;#4CE6: CB 91
POLL_KEY_RIGHT_DONE:
        ; After clearing RIGHT bit, fall through to TRIGGER probe
        and     10h                                            ;#4CE8: E6 10
        jr      nz,POLL_KEY_TRIGGER_DONE                       ;#4CEA: 20 02
        res     7,c                                            ;#4CEC: CB B9
POLL_KEY_TRIGGER_DONE:
        ; Read SNSMAT row 5: check joystick trigger 1 bit
        ld      a,5                                            ;#4CEE: 3E 05
        call    SNSMAT_PRESERVE_BC                             ;#4CF0: CD FE 4C
        rla                                                    ;#4CF3: 17
        jr      c,POLL_KEY_GTRIG_DONE                          ;#4CF4: 38 02
        res     5,c                                            ;#4CF6: CB A9
POLL_KEY_GTRIG_DONE:
        ; Read SNSMAT row 5: check joystick trigger 2 bit (general trigger)
        rla                                                    ;#4CF8: 17
        rla                                                    ;#4CF9: 17
        ret     c                                              ;#4CFA: D8
        res     4,c                                            ;#4CFB: CB A1
        ret                                                    ;#4CFD: C9

SNSMAT_PRESERVE_BC:
        ; Tiny stub: call BIOS_SNSMAT preserving BC across the call
        push    bc                                             ;#4CFE: C5
        call    BIOS_SNSMAT                                    ;#4CFF: CD 41 01
        pop     bc                                             ;#4D02: C1
        ret                                                    ;#4D03: C9

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
        ld      hl,INITIAL_VDP_REGISTERS                       ;#4D04: 21 9D 4D
        ld      bc,800h                                        ;#4D07: 01 00 08
VDP_REG_INIT_LOOP:
        ; Inner djnz of INIT_VDP_AND_LOAD_GFX (8 registers)
        push    bc                                             ;#4D0A: C5
        ld      b,(hl)                                         ;#4D0B: 46
        call    BIOS_WRTVDP                                    ;#4D0C: CD 47 00
        pop     bc                                             ;#4D0F: C1
        inc     hl                                             ;#4D10: 23
        inc     c                                              ;#4D11: 0C
        djnz    VDP_REG_INIT_LOOP                              ;#4D12: 10 F6
        ld      hl,INITIAL_COLOR_TABLE                         ;#4D14: 21 A5 4D
        LOAD_VRAM_ADDRESS de, 780h                             ;#4D17: 11 80 07
        ld      bc,20h                                         ;#4D1A: 01 20 00
        call    BIOS_LDIRVM                                    ;#4D1D: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D20: 21 00 E0
        ld      de,TEMP_SPACE+1                                ;#4D23: 11 01 E0
        ld      (hl),0                                         ;#4D26: 36 00
        ld      bc,7FFh                                        ;#4D28: 01 FF 07
        ldir                                                   ;#4D2B: ED B0
        ld      hl,TILE_PATTERN_HEX_DIGITS                     ;#4D2D: 21 D0 60
        ld      de,TEMP_SPACE                                  ;#4D30: 11 00 E0
        ld      bc,100h                                        ;#4D33: 01 00 01
        ldir                                                   ;#4D36: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D38: 21 90 61
        ld      b,1                                            ;#4D3B: 06 01
        ldir                                                   ;#4D3D: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D3F: 21 90 61
        ld      b,1                                            ;#4D42: 06 01
        ldir                                                   ;#4D44: ED B0
        ld      hl,TILE_PATTERN_CHAR_FONT                      ;#4D46: 21 90 61
        ld      b,1                                            ;#4D49: 06 01
        ldir                                                   ;#4D4B: ED B0
        ld      hl,TEMP_SPACE                                  ;#4D4D: 21 00 E0
        LOAD_VRAM_ADDRESS de, 800h                             ;#4D50: 11 00 08
        ld      bc,800h                                        ;#4D53: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D56: CD 5C 00
        ld      hl,TEMP_SPACE                                  ;#4D59: 21 00 E0
        LOAD_VRAM_ADDRESS de, 1800h                            ;#4D5C: 11 00 18
        ld      bc,800h                                        ;#4D5F: 01 00 08
        call    BIOS_LDIRVM                                    ;#4D62: CD 5C 00
        ld      hl,SPRITE_CAR                                  ;#4D65: 21 F0 5C
        ld      de,TEMP_SPACE                                  ;#4D68: 11 00 E0
        ld      bc,60h                                         ;#4D6B: 01 60 00
        ldir                                                   ;#4D6E: ED B0
        ld      hl,SPRITE_PATTERN_WORK_BUF                     ;#4D70: 21 60 E0
        ld      de,TEMP_SPACE                                  ;#4D73: 11 00 E0
        call    TRANSPOSE_TILE_BLOCKS                          ;#4D76: CD C5 4D
        ld      hl,TEMP_SPACE                                  ;#4D79: 21 00 E0
        LOAD_VRAM_ADDRESS de, 3000h                            ;#4D7C: 11 00 30
        ld      bc,180h                                        ;#4D7F: 01 80 01
        call    BIOS_LDIRVM                                    ;#4D82: CD 5C 00
        ld      hl,SPRITE_FLAG                                 ;#4D85: 21 50 5D
        LOAD_VRAM_ADDRESS de, 3180h                            ;#4D88: 11 80 31
        ld      bc,100h                                        ;#4D8B: 01 00 01
        call    BIOS_LDIRVM                                    ;#4D8E: CD 5C 00
        ld      hl,SPRITE_BONUS_100                            ;#4D91: 21 10 5E
        LOAD_VRAM_ADDRESS de, 3400h                            ;#4D94: 11 00 34
        ld      bc,2C0h                                        ;#4D97: 01 C0 02
        jp      BIOS_LDIRVM                                    ;#4D9A: C3 5C 00

INITIAL_VDP_REGISTERS:
        ; Screen-1 R0..R7 init block: name=0400h, SAT=0700h, patterns=0800h
        ; INITIAL_VDP_REGISTERS — 8 bytes loaded into VDP R0..R7 by boot. R0=00 (M3=0,
        ; no horiz IRQ), R1=82h (screen blank, IRQs off, 16x16 sprites — screen 1 mode),
        ; R2=01 (name table 0400h), R3=1E (color 0780h), R4=01 (patterns 0800h), R5=0E
        ; (SAT 0700h), R6=06 (sprite patterns 3000h), R7=F0 (FG=white BG=transparent).
        db      0, 82h, 1, 1Eh, 1, 0Eh, 6, 0F0h ; VDP registers R0..R7  ;#4D9D: 00 82 01 1E 01 0E 06 F0

INITIAL_COLOR_TABLE:
        ; 32-byte screen-1 colour table uploaded to VRAM 0780h (not SAT)
        dh      "F0F080F070707070F0F0F0F080808080"             ;#4DA5: F0 F0 80 F0 70 70 70 70 F0 F0 F0 F0 80 80 80 80
        dh      "2992F0F0A0A0F0F010106060F0F0F0F0"             ;#4DB5: 29 92 F0 F0 A0 A0 F0 F0 10 10 60 60 F0 F0 F0 F0

TRANSPOSE_TILE_BLOCKS:
        ; Process 9 32-byte blocks via 4 sub-quadrant TRANSPOSE_TILE_BITS calls each
        ; TRANSPOSE_TILE_BLOCKS processes 9 tile-pattern blocks of 32 bytes each by
        ; calling TRANSPOSE_TILE_BITS 4 times per iteration (one per 8-byte quadrant).
        ; The 4 quadrant offsets within a 32-byte tile are +16, +0, +24, +8 (i.e.
        ; quadrant order is bottom-left, top-left, bottom-right, top-right). This
        ; rearranges packed source data into VRAM-pattern-table format before LDIRVM.
        ld      b,9                                            ;#4DC5: 06 09
TRANSPOSE_BLOCKS_LOOP:
        ; Outer djnz of TRANSPOSE_TILE_BLOCKS (9 tile blocks)
        push    bc                                             ;#4DC7: C5
        push    hl                                             ;#4DC8: E5
        ld      bc,10h                                         ;#4DC9: 01 10 00
        add     hl,bc                                          ;#4DCC: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DCD: CD F0 4D
        pop     hl                                             ;#4DD0: E1
        push    hl                                             ;#4DD1: E5
        call    TRANSPOSE_TILE_BITS                            ;#4DD2: CD F0 4D
        pop     hl                                             ;#4DD5: E1
        push    hl                                             ;#4DD6: E5
        ld      bc,18h                                         ;#4DD7: 01 18 00
        add     hl,bc                                          ;#4DDA: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DDB: CD F0 4D
        pop     hl                                             ;#4DDE: E1
        push    hl                                             ;#4DDF: E5
        ld      bc,8                                           ;#4DE0: 01 08 00
        add     hl,bc                                          ;#4DE3: 09
        call    TRANSPOSE_TILE_BITS                            ;#4DE4: CD F0 4D
        pop     hl                                             ;#4DE7: E1
        ld      bc,20h                                         ;#4DE8: 01 20 00
        add     hl,bc                                          ;#4DEB: 09
        pop     bc                                             ;#4DEC: C1
        djnz    TRANSPOSE_BLOCKS_LOOP                          ;#4DED: 10 D8
        ret                                                    ;#4DEF: C9

TRANSPOSE_TILE_BITS:
        ; 8x8 bit-matrix transpose: 8 input bytes -> 8 output bytes (bit-column-first)
        ; TRANSPOSE_TILE_BITS is the classic 8×8 bit-matrix transpose: 8 input bytes
        ; interpreted as an 8×8 bit grid become 8 output bytes with rows and columns
        ; swapped. Implemented as 2 nested loops: inner 8x `add a,a; rr (hl); inc hl`
        ; (shifts bits column-wise), outer 8x to consume each input byte.
        ld      c,8                                            ;#4DF0: 0E 08
TRANSPOSE_OUTER_LOOP:
        ; Outer 8-byte loop of TRANSPOSE_TILE_BITS (one column per iter)
        ld      a,(de)                                         ;#4DF2: 1A
        inc     de                                             ;#4DF3: 13
        push    hl                                             ;#4DF4: E5
        ld      b,8                                            ;#4DF5: 06 08
TRANSPOSE_INNER_BIT:
        ; Inner djnz of TRANSPOSE_TILE_BITS (bit-by-bit shift)
        add     a,a                                            ;#4DF7: 87
        rr      (hl)                                           ;#4DF8: CB 1E
        inc     hl                                             ;#4DFA: 23
        djnz    TRANSPOSE_INNER_BIT                            ;#4DFB: 10 FA
        pop     hl                                             ;#4DFD: E1
        dec     c                                              ;#4DFE: 0D
        jr      nz,TRANSPOSE_OUTER_LOOP                        ;#4DFF: 20 F1
        ret                                                    ;#4E01: C9

UPLOAD_PATTERN_SLICE:
        ; Pick a slice via TILE_PATTERN_SLICE_TABLE then LDIRVM to VRAM 0C00h
        ; UPLOAD_PATTERN_SLICE selects a 128-byte tile-pattern slice from
        ; TILE_PATTERN_SLICE_TABLE based on PLAYER_VELOCITY_X, then LDIRVMs it to VRAM
        ; 0C00h (pattern table). Used to switch dynamic patterns per game state.
        ld      a,(PLAYER_VELOCITY_X)                          ;#4E02: 3A 09 E0
        add     a,18h                                          ;#4E05: C6 18
        and     7                                              ;#4E07: E6 07
        add     a,a                                            ;#4E09: 87
        ld      hl,TILE_PATTERN_SLICE_TABLE                    ;#4E0A: 21 C8 4E
        add     a,l                                            ;#4E0D: 85
        ld      l,a                                            ;#4E0E: 6F
        ld      a,0                                            ;#4E0F: 3E 00
        adc     a,h                                            ;#4E11: 8C
        ld      h,a                                            ;#4E12: 67
        ld      a,(hl)                                         ;#4E13: 7E
        inc     hl                                             ;#4E14: 23
        ld      h,(hl)                                         ;#4E15: 66
        ld      l,a                                            ;#4E16: 6F
        ld      a,(PLAYER_VELOCITY_Y)                          ;#4E17: 3A 0B E0
        add     a,18h                                          ;#4E1A: C6 18
        neg                                                    ;#4E1C: ED 44
        and     7                                              ;#4E1E: E6 07
        inc     a                                              ;#4E20: 3C
        ld      b,a                                            ;#4E21: 47
UPLOAD_PATTERN_SLICE_DEC_HL:
        ; Inner djnz of UPLOAD_PATTERN_SLICE (rewind HL)
        dec     hl                                             ;#4E22: 2B
        djnz    UPLOAD_PATTERN_SLICE_DEC_HL                    ;#4E23: 10 FD
        ld      a,(FRAME_TICK)                                 ;#4E25: 3A 07 E0
        rra                                                    ;#4E28: 1F
        jr      nc,UPLOAD_PATTERN_SLICE_BANK_B                 ;#4E29: 30 0C
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#4E2B: 11 00 0C
        ld      bc,80h                                         ;#4E2E: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E31: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E34: C3 43 4E

UPLOAD_PATTERN_SLICE_BANK_B:
        ; Bank-B path: LDIRVM the slice to VRAM 1C00h instead of 0C00h
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#4E37: 11 00 1C
        ld      bc,80h                                         ;#4E3A: 01 80 00
        call    BIOS_LDIRVM                                    ;#4E3D: CD 5C 00
        jp      UPLOAD_PATTERN_SLICE_AFTER_LDIRVM              ;#4E40: C3 43 4E

UPLOAD_PATTERN_SLICE_AFTER_LDIRVM:
        ; After both bank LDIRVM paths: prepare to update VRAM cursor for next slice
        ld      de,PLAYER_VELOCITY_Y                           ;#4E43: 11 0B E0
        ld      hl,STEP_COUNTER_HIGH                           ;#4E46: 21 0C E0
        ld      a,(de)                                         ;#4E49: 1A
        add     a,1Fh                                          ;#4E4A: C6 1F
        rra                                                    ;#4E4C: 1F
        rra                                                    ;#4E4D: 1F
        rra                                                    ;#4E4E: 1F
        and     7                                              ;#4E4F: E6 07
        cp      (hl)                                           ;#4E51: BE
        jr      nz,UPLOAD_PATTERN_SLICE_FIRST_ROW              ;#4E52: 20 21
        ld      b,a                                            ;#4E54: 47
        dec     de                                             ;#4E55: 1B
        dec     de                                             ;#4E56: 1B
        inc     hl                                             ;#4E57: 23
        ld      a,(de)                                         ;#4E58: 1A
        add     a,18h                                          ;#4E59: C6 18
        rra                                                    ;#4E5B: 1F
        rra                                                    ;#4E5C: 1F
        rra                                                    ;#4E5D: 1F
        and     7                                              ;#4E5E: E6 07
        cp      (hl)                                           ;#4E60: BE
        jp      z,UPDATE_RADAR                                 ;#4E61: CA E0 52
        ld      (hl),a                                         ;#4E64: 77
        ld      hl,TRACK_DATA_RING                             ;#4E65: 21 00 EC
        add     a,l                                            ;#4E68: 85
        ld      l,a                                            ;#4E69: 6F
        ld      a,0                                            ;#4E6A: 3E 00
        adc     a,h                                            ;#4E6C: 8C
        ld      h,a                                            ;#4E6D: 67
        ld      de,1Eh                                         ;#4E6E: 11 1E 00
        inc     b                                              ;#4E71: 04
        jp      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E72: C3 90 4E

UPLOAD_PATTERN_SLICE_FIRST_ROW:
        ; First-row branch: update the playfield-position byte, then advance the loop
        ld      (hl),a                                         ;#4E75: 77
        ld      b,a                                            ;#4E76: 47
        dec     de                                             ;#4E77: 1B
        dec     de                                             ;#4E78: 1B
        inc     hl                                             ;#4E79: 23
        ld      a,(de)                                         ;#4E7A: 1A
        add     a,18h                                          ;#4E7B: C6 18
        rra                                                    ;#4E7D: 1F
        rra                                                    ;#4E7E: 1F
        rra                                                    ;#4E7F: 1F
        and     7                                              ;#4E80: E6 07
        ld      (hl),a                                         ;#4E82: 77
        ld      hl,TRACK_DATA_RING                             ;#4E83: 21 00 EC
        add     a,l                                            ;#4E86: 85
        ld      l,a                                            ;#4E87: 6F
        ld      a,0                                            ;#4E88: 3E 00
        adc     a,h                                            ;#4E8A: 8C
        ld      h,a                                            ;#4E8B: 67
        ld      de,1Eh                                         ;#4E8C: 11 1E 00
        inc     b                                              ;#4E8F: 04
UPLOAD_PATTERN_SLICE_ADVANCE_LOOP:
        ; Inner djnz: HL += 1Eh per iteration (skip 30 chars between visible rows)
        dec     b                                              ;#4E90: 05
        jr      z,UPLOAD_PATTERN_SLICE_BANK_SWAP               ;#4E91: 28 03
        add     hl,de                                          ;#4E93: 19
        jr      UPLOAD_PATTERN_SLICE_ADVANCE_LOOP              ;#4E94: 18 FA

UPLOAD_PATTERN_SLICE_BANK_SWAP:
        ; Frame-parity gate: choose bank-A (NAME_BANK_FLAG=0) or bank-B path
        ld      b,18h                                          ;#4E96: 06 18
        ld      de,400h                                        ;#4E98: 11 00 04
        ld      a,(NAME_BANK_FLAG)                             ;#4E9B: 3A 0E E0
        and     a                                              ;#4E9E: A7
        jp      nz,UPLOAD_PATTERN_SLICE_BANK_CLEAR             ;#4E9F: C2 AD 4E
        ld      a,1                                            ;#4EA2: 3E 01
        ld      (NAME_BANK_FLAG),a                             ;#4EA4: 32 0E E0
        LOAD_VRAM_ADDRESS de, 1400h                            ;#4EA7: 11 00 14
        jp      UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4EAA: C3 B1 4E

UPLOAD_PATTERN_SLICE_BANK_CLEAR:
        ; Bank-A path: clear NAME_BANK_FLAG so the next frame uses bank-B
        xor     a                                              ;#4EAD: AF
        ld      (NAME_BANK_FLAG),a                             ;#4EAE: 32 0E E0
UPLOAD_PATTERN_SLICE_LDIRVM_SLICE:
        ; LDIRVM the 23-tile row to the name table at chosen bank
        push    bc                                             ;#4EB1: C5
        push    hl                                             ;#4EB2: E5
        push    de                                             ;#4EB3: D5
        ld      bc,17h                                         ;#4EB4: 01 17 00
        call    BIOS_LDIRVM                                    ;#4EB7: CD 5C 00
        pop     hl                                             ;#4EBA: E1
        ld      bc,20h                                         ;#4EBB: 01 20 00
        add     hl,bc                                          ;#4EBE: 09
        ex      de,hl                                          ;#4EBF: EB
        pop     hl                                             ;#4EC0: E1
        ld      c,1Eh                                          ;#4EC1: 0E 1E
        add     hl,bc                                          ;#4EC3: 09
        pop     bc                                             ;#4EC4: C1
        djnz    UPLOAD_PATTERN_SLICE_LDIRVM_SLICE              ;#4EC5: 10 EA
        ret                                                    ;#4EC7: C9

TILE_PATTERN_SLICE_TABLE:
        ; 8 endpoint pointers into the per-substate tile-pattern data block
        dw TILE_SLICE_0 + 9                                    ;#4EC8: E1 4E
        dw TILE_SLICE_1 + 9                                    ;#4ECA: 61 4F
        dw TILE_SLICE_2 + 9                                    ;#4ECC: E1 4F
        dw TILE_SLICE_3 + 9                                    ;#4ECE: 61 50
        dw TILE_SLICE_4 + 9                                    ;#4ED0: E1 50
        dw TILE_SLICE_5 + 9                                    ;#4ED2: 61 51
        dw TILE_SLICE_6 + 9                                    ;#4ED4: E1 51
        dw TILE_SLICE_7 + 9                                    ;#4ED6: 61 52

TILE_SLICE_0:
        ; 128-byte tile-pattern slice 0 (table points to TILE_SLICE_0 + 9)
        dh      "00000000000000000000000000000000"             ;#4ED8: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4EE8: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4EF8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F08: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF
        dh      "00000000000000000000000000000000"             ;#4F18: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "00000000000000000000000000000000"             ;#4F28: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F38: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FFFFFFFFFFFFFFFF"             ;#4F48: 00 00 00 00 00 00 00 00 FF FF FF FF FF FF FF FF

TILE_SLICE_1:
        ; 128-byte tile-pattern slice 1
        dh      "00000000000000000101010101010101"             ;#4F58: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4F68: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4F78: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4F88: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE
        dh      "00000000000000000101010101010101"             ;#4F98: 00 00 00 00 00 00 00 00 01 01 01 01 01 01 01 01
        dh      "01010101010101010000000000000000"             ;#4FA8: 01 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4FB8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FEFEFEFEFEFEFEFE"             ;#4FC8: 00 00 00 00 00 00 00 00 FE FE FE FE FE FE FE FE

TILE_SLICE_2:
        ; 128-byte tile-pattern slice 2
        dh      "00000000000000000303030303030303"             ;#4FD8: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#4FE8: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#4FF8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#5008: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC
        dh      "00000000000000000303030303030303"             ;#5018: 00 00 00 00 00 00 00 00 03 03 03 03 03 03 03 03
        dh      "03030303030303030000000000000000"             ;#5028: 03 03 03 03 03 03 03 03 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5038: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000FCFCFCFCFCFCFCFC"             ;#5048: 00 00 00 00 00 00 00 00 FC FC FC FC FC FC FC FC

TILE_SLICE_3:
        ; 128-byte tile-pattern slice 3
        dh      "00000000000000000707070707070707"             ;#5058: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#5068: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5078: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#5088: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8
        dh      "00000000000000000707070707070707"             ;#5098: 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07
        dh      "07070707070707070000000000000000"             ;#50A8: 07 07 07 07 07 07 07 07 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#50B8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F8F8F8F8F8F8F8F8"             ;#50C8: 00 00 00 00 00 00 00 00 F8 F8 F8 F8 F8 F8 F8 F8

TILE_SLICE_4:
        ; 128-byte tile-pattern slice 4
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#50D8: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#50E8: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#50F8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#5108: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0
        dh      "00000000000000000F0F0F0F0F0F0F0F"             ;#5118: 00 00 00 00 00 00 00 00 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0F0F0F0F0F0F0F0F0000000000000000"             ;#5128: 0F 0F 0F 0F 0F 0F 0F 0F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5138: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000F0F0F0F0F0F0F0F0"             ;#5148: 00 00 00 00 00 00 00 00 F0 F0 F0 F0 F0 F0 F0 F0

TILE_SLICE_5:
        ; 128-byte tile-pattern slice 5
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#5158: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#5168: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5178: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#5188: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0
        dh      "00000000000000001F1F1F1F1F1F1F1F"             ;#5198: 00 00 00 00 00 00 00 00 1F 1F 1F 1F 1F 1F 1F 1F
        dh      "1F1F1F1F1F1F1F1F0000000000000000"             ;#51A8: 1F 1F 1F 1F 1F 1F 1F 1F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#51B8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000E0E0E0E0E0E0E0E0"             ;#51C8: 00 00 00 00 00 00 00 00 E0 E0 E0 E0 E0 E0 E0 E0

TILE_SLICE_6:
        ; 128-byte tile-pattern slice 6
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#51D8: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#51E8: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#51F8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#5208: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0
        dh      "00000000000000003F3F3F3F3F3F3F3F"             ;#5218: 00 00 00 00 00 00 00 00 3F 3F 3F 3F 3F 3F 3F 3F
        dh      "3F3F3F3F3F3F3F3F0000000000000000"             ;#5228: 3F 3F 3F 3F 3F 3F 3F 3F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5238: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "0000000000000000C0C0C0C0C0C0C0C0"             ;#5248: 00 00 00 00 00 00 00 00 C0 C0 C0 C0 C0 C0 C0 C0

TILE_SLICE_7:
        ; 136-byte tile-pattern slice 7 (extended tail)
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#5258: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#5268: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#5278: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#5288: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "00000000000000007F7F7F7F7F7F7F7F"             ;#5298: 00 00 00 00 00 00 00 00 7F 7F 7F 7F 7F 7F 7F 7F
        dh      "7F7F7F7F7F7F7F7F0000000000000000"             ;#52A8: 7F 7F 7F 7F 7F 7F 7F 7F 00 00 00 00 00 00 00 00
        dh      "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"             ;#52B8: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
        dh      "00000000000000008080808080808080"             ;#52C8: 00 00 00 00 00 00 00 00 80 80 80 80 80 80 80 80
        dh      "0000000000000000"                             ;#52D8: 00 00 00 00 00 00 00 00

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
        ld      hl,RADAR_GRID                                  ;#52E0: 21 00 EA
        ld      de,OBSTACLE_GRID                               ;#52E3: 11 80 EA
        ld      bc,70h                                         ;#52E6: 01 70 00
        ldir                                                   ;#52E9: ED B0
        ld      a,(FRAME_TICK)                                 ;#52EB: 3A 07 E0
        and     8                                              ;#52EE: E6 08
        jr      z,RADAR_AFTER_CLEAR                            ;#52F0: 28 05
        ld      hl,(RADAR_LAST_DOT_PTR)                        ;#52F2: 2A 25 E0
        ld      (hl),90h                                       ;#52F5: 36 90
RADAR_AFTER_CLEAR:
        ; After optional player-dot clear: set up IX = ENEMY_CAR_TABLE for plot
        ld      ix,ENEMY_CAR_TABLE                             ;#52F7: DD 21 00 E3
        call    UPDATE_RADAR_DOT_A                             ;#52FB: CD 50 53
        call    UPDATE_RADAR_DOT_B                             ;#52FE: CD 8C 53
        call    UPDATE_RADAR_DOT_B                             ;#5301: CD 8C 53
        call    UPDATE_RADAR_DOT_A                             ;#5304: CD 50 53
        call    UPDATE_RADAR_DOT_A                             ;#5307: CD 50 53
        call    UPDATE_RADAR_DOT_B                             ;#530A: CD 8C 53
        call    UPDATE_RADAR_DOT_A                             ;#530D: CD 50 53
        ld      a,(PLAYER_SCREEN_X)                            ;#5310: 3A 23 E0
        ld      d,a                                            ;#5313: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#5314: 3A 24 E0
        ld      e,a                                            ;#5317: 5F
        ld      c,0B0h                                         ;#5318: 0E B0
        ld      a,(FRAME_TICK)                                 ;#531A: 3A 07 E0
        and     10h                                            ;#531D: E6 10
        jr      z,RADAR_PROBE_PLAYER                           ;#531F: 28 02
        ld      c,0C0h                                         ;#5321: 0E C0
RADAR_PROBE_PLAYER:
        ; Plot the player dot at PLAYER_SCREEN_X/Y with blinking color B0h/C0h
        call    PROBE_OBSTACLE_CELL                            ;#5323: CD 62 53
        ld      hl,OBSTACLE_GRID                               ;#5326: 21 80 EA
        ld      b,0Eh                                          ;#5329: 06 0E
        ld      de,4F7h                                        ;#532B: 11 F7 04
        ld      a,(NAME_BANK_FLAG)                             ;#532E: 3A 0E E0
        and     a                                              ;#5331: A7
        jr      z,RADAR_UPLOAD_ROW_LOOP                        ;#5332: 28 03
        LOAD_VRAM_ADDRESS de, 14F7h                            ;#5334: 11 F7 14
RADAR_UPLOAD_ROW_LOOP:
        ; Inner djnz: LDIRVM 8 radar bytes per row, then HL+=8, DE+=20h
        push    bc                                             ;#5337: C5
        push    de                                             ;#5338: D5
        push    hl                                             ;#5339: E5
        ld      bc,8                                           ;#533A: 01 08 00
        ; BIOS_LDIRVM call inside the radar-clear loop. Used by UPDATE_RADAR to bulk-
        ; clear the radar grid before redrawing entity dots. Just a standard LDIRVM call
        ; site (no enclosing macro because the source is computed register, not
        ; literal).
        call    BIOS_LDIRVM                                    ;#533D: CD 5C 00
        pop     hl                                             ;#5340: E1
        ld      bc,8                                           ;#5341: 01 08 00
        add     hl,bc                                          ;#5344: 09
        pop     de                                             ;#5345: D1
        ex      de,hl                                          ;#5346: EB
        ld      bc,20h                                         ;#5347: 01 20 00
        add     hl,bc                                          ;#534A: 09
        ex      de,hl                                          ;#534B: EB
        pop     bc                                             ;#534C: C1
        djnz    RADAR_UPLOAD_ROW_LOOP                          ;#534D: 10 E8
        ret                                                    ;#534F: C9

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
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5350: DD 7E 00
        and     a                                              ;#5353: A7
        ret     z                                              ;#5354: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#5355: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5358: DD 5E 08
        ld      bc,10h                                         ;#535B: 01 10 00
        add     ix,bc                                          ;#535E: DD 09
        ld      c,0D0h                                         ;#5360: 0E D0
PROBE_OBSTACLE_CELL:
        ; Compute OBSTACLE_GRID index from (D, E) coord and read cell; compare to 90h
        ; PROBE_OBSTACLE_CELL takes (D, E) as a map coordinate, computes a bit index
        ; into OBSTACLE_GRID (128 bytes covering 32x32 cells), reads the cell value, and
        ; compares to 90h (empty marker). Returns z-flag set if cell is empty, clear if
        ; occupied. Used by AI for collision/path checks.
        ld      a,d                                            ;#5362: 7A
        and     3                                              ;#5363: E6 03
        or      c                                              ;#5365: B1
        ld      c,a                                            ;#5366: 4F
        ld      a,e                                            ;#5367: 7B
        add     a,a                                            ;#5368: 87
        add     a,a                                            ;#5369: 87
        and     0Ch                                            ;#536A: E6 0C
        or      c                                              ;#536C: B1
        ld      c,a                                            ;#536D: 4F
        ld      a,d                                            ;#536E: 7A
        rra                                                    ;#536F: 1F
        rra                                                    ;#5370: 1F
        and     7                                              ;#5371: E6 07
        ld      l,a                                            ;#5373: 6F
        ld      a,e                                            ;#5374: 7B
        add     a,a                                            ;#5375: 87
        and     78h                                            ;#5376: E6 78
        or      l                                              ;#5378: B5
        ld      l,a                                            ;#5379: 6F
        ld      h,0                                            ;#537A: 26 00
        ld      de,OBSTACLE_GRID                               ;#537C: 11 80 EA
        add     hl,de                                          ;#537F: 19
        ld      a,(hl)                                         ;#5380: 7E
        cp      90h                                            ;#5381: FE 90
        jr      z,RADAR_A_WRITE_CELL                           ;#5383: 28 05
        ld      a,(FRAME_TICK)                                 ;#5385: 3A 07 E0
        rra                                                    ;#5388: 1F
        ret     c                                              ;#5389: D8
RADAR_A_WRITE_CELL:
        ; Variant A write: store color C into the radar cell (occupied or empty)
        ld      (hl),c                                         ;#538A: 71
        ret                                                    ;#538B: C9

UPDATE_RADAR_DOT_B:
        ; Per-entity radar update helper (variant B)
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#538C: DD 7E 00
        and     a                                              ;#538F: A7
        ret     z                                              ;#5390: C8
        ld      d,(ix+ENEMY_OFFSET_CELL_X)                     ;#5391: DD 56 05
        ld      e,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5394: DD 5E 08
        ld      bc,10h                                         ;#5397: 01 10 00
        add     ix,bc                                          ;#539A: DD 09
        ld      c,0D0h                                         ;#539C: 0E D0
        ld      a,d                                            ;#539E: 7A
        and     3                                              ;#539F: E6 03
        or      c                                              ;#53A1: B1
        ld      c,a                                            ;#53A2: 4F
        ld      a,e                                            ;#53A3: 7B
        add     a,a                                            ;#53A4: 87
        add     a,a                                            ;#53A5: 87
        and     0Ch                                            ;#53A6: E6 0C
        or      c                                              ;#53A8: B1
        ld      c,a                                            ;#53A9: 4F
        ld      a,d                                            ;#53AA: 7A
        rra                                                    ;#53AB: 1F
        rra                                                    ;#53AC: 1F
        and     7                                              ;#53AD: E6 07
        ld      l,a                                            ;#53AF: 6F
        ld      a,e                                            ;#53B0: 7B
        add     a,a                                            ;#53B1: 87
        and     78h                                            ;#53B2: E6 78
        or      l                                              ;#53B4: B5
        ld      l,a                                            ;#53B5: 6F
        ld      h,0                                            ;#53B6: 26 00
        ld      de,OBSTACLE_GRID                               ;#53B8: 11 80 EA
        add     hl,de                                          ;#53BB: 19
        ld      a,(hl)                                         ;#53BC: 7E
        cp      90h                                            ;#53BD: FE 90
        jr      z,RADAR_B_WRITE_CELL                           ;#53BF: 28 05
        ld      a,(FRAME_TICK)                                 ;#53C1: 3A 07 E0
        rra                                                    ;#53C4: 1F
        ret     nc                                             ;#53C5: D0
RADAR_B_WRITE_CELL:
        ; Variant B write: store color C into the radar cell (opposite frame parity)
        ld      (hl),c                                         ;#53C6: 71
        ret                                                    ;#53C7: C9

INIT_STAGE:
        ; Fill RADAR_GRID with 90h and seed FLAG_TABLE with 10 random entries
        ; INIT_STAGE first fills RADAR_GRID (112 bytes) with 90h (empty-cell marker).
        ; Then loops 10 times: write 1 to flag's active byte, call NEXT_RANDOM twice for
        ; X/Y, place flag at random position. The 10 flags = 8 yellow + 2 red special,
        ; matching tile pattern in INIT_FLAGS at stage start.
        ld      hl,RADAR_GRID                                  ;#53C8: 21 00 EA
        ld      de,RADAR_GRID_TAIL                             ;#53CB: 11 01 EA
        ld      bc,6Fh                                         ;#53CE: 01 6F 00
        ld      (hl),90h                                       ;#53D1: 36 90
        ldir                                                   ;#53D3: ED B0
        ld      hl,FLAG_TABLE                                  ;#53D5: 21 00 E1
        ld      a,0Ah                                          ;#53D8: 3E 0A
        ld      (STAGE_DIFFICULTY),a                           ;#53DA: 32 2E E0
        ld      b,a                                            ;#53DD: 47
INIT_STAGE_FLAG_LOOP:
        ; Outer loop body: write 1 to active byte, push pointer, pick new random pos
        ld      (hl),1                                         ;#53DE: 36 01
        inc     hl                                             ;#53E0: 23
        push    hl                                             ;#53E1: E5
INIT_STAGE_RANDOM_X:
        ; Pick a random X (in [0..1Fh])
        call    NEXT_RANDOM                                    ;#53E2: CD E5 54
        and     1Fh                                            ;#53E5: E6 1F
        ld      h,a                                            ;#53E7: 67
INIT_STAGE_RANDOM_Y:
        ; Pick a random Y (must be < 38h; retry if larger)
        call    NEXT_RANDOM                                    ;#53E8: CD E5 54
        and     3Fh                                            ;#53EB: E6 3F
        cp      38h                                            ;#53ED: FE 38
        jr      nc,INIT_STAGE_RANDOM_Y                         ;#53EF: 30 F7
        ld      l,a                                            ;#53F1: 6F
        cp      4                                              ;#53F2: FE 04
        jr      c,INIT_STAGE_CHECK_Y_BOUNDS                    ;#53F4: 38 04
        cp      32h                                            ;#53F6: FE 32
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#53F8: 38 09
INIT_STAGE_CHECK_Y_BOUNDS:
        ; Y in range: check that X is not in PLAYER_SPAWN_ZONE (0..9 or 10h..14h)
        ld      a,h                                            ;#53FA: 7C
        cp      0Ah                                            ;#53FB: FE 0A
        jr      c,INIT_STAGE_CHECK_PLAYFIELD                   ;#53FD: 38 04
        cp      15h                                            ;#53FF: FE 15
        jr      c,INIT_STAGE_RANDOM_X                          ;#5401: 38 DF
INIT_STAGE_CHECK_PLAYFIELD:
        ; Coord passed; verify cell is not a wall via LOOKUP_PLAYFIELD_CELL
        call    LOOKUP_PLAYFIELD_CELL                          ;#5403: CD 7C 4B
        jr      c,INIT_STAGE_RANDOM_X                          ;#5406: 38 DA
        ex      de,hl                                          ;#5408: EB
        ld      hl,ROCK_TABLE                                  ;#5409: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#540C: 3A 1C E0
        and     a                                              ;#540F: A7
        jr      z,INIT_STAGE_AFTER_ROCKS                       ;#5410: 28 1A
        ld      c,a                                            ;#5412: 4F
INIT_STAGE_ROCK_DIST_LOOP:
        ; Check distance from each existing ROCK_TABLE entry (>=7 cells away)
        inc     hl                                             ;#5413: 23
        ld      a,(hl)                                         ;#5414: 7E
        inc     hl                                             ;#5415: 23
        sub     d                                              ;#5416: 92
        add     a,3                                            ;#5417: C6 03
        cp      7                                              ;#5419: FE 07
        jr      nc,INIT_STAGE_ROCK_NEXT                        ;#541B: 30 08
        ld      a,(hl)                                         ;#541D: 7E
        sub     e                                              ;#541E: 93
        add     a,3                                            ;#541F: C6 03
        cp      7                                              ;#5421: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#5423: 38 BD
INIT_STAGE_ROCK_NEXT:
        ; ROCK distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#5425: 7D
        add     a,0Eh                                          ;#5426: C6 0E
        ld      l,a                                            ;#5428: 6F
        dec     c                                              ;#5429: 0D
        jr      nz,INIT_STAGE_ROCK_DIST_LOOP                   ;#542A: 20 E7
INIT_STAGE_AFTER_ROCKS:
        ; After rock-dedup: check distance from existing FLAG_TABLE entries too
        ld      hl,FLAG_TABLE                                  ;#542C: 21 00 E1
        ld      a,0Ah                                          ;#542F: 3E 0A
        sub     b                                              ;#5431: 90
        jr      z,INIT_STAGE_PLACE_FLAG                        ;#5432: 28 1A
        ld      c,a                                            ;#5434: 4F
INIT_STAGE_FLAG_DIST_LOOP:
        ; Inner loop: compare candidate vs each placed flag in FLAG_TABLE
        inc     hl                                             ;#5435: 23
        ld      a,(hl)                                         ;#5436: 7E
        inc     hl                                             ;#5437: 23
        sub     d                                              ;#5438: 92
        add     a,3                                            ;#5439: C6 03
        cp      7                                              ;#543B: FE 07
        jr      nc,INIT_STAGE_FLAG_NEXT                        ;#543D: 30 08
        ld      a,(hl)                                         ;#543F: 7E
        sub     e                                              ;#5440: 93
        add     a,3                                            ;#5441: C6 03
        cp      7                                              ;#5443: FE 07
        jr      c,INIT_STAGE_RANDOM_X                          ;#5445: 38 9B
INIT_STAGE_FLAG_NEXT:
        ; FLAG distance OK: advance to next entry in dedup loop
        ld      a,l                                            ;#5447: 7D
        add     a,0Eh                                          ;#5448: C6 0E
        ld      l,a                                            ;#544A: 6F
        dec     c                                              ;#544B: 0D
        jr      nz,INIT_STAGE_FLAG_DIST_LOOP                   ;#544C: 20 E7
INIT_STAGE_PLACE_FLAG:
        ; All distance checks passed: write (X, Y) to flag entry and seed RADAR_GRID
        pop     hl                                             ;#544E: E1
        ld      (hl),d                                         ;#544F: 72
        inc     hl                                             ;#5450: 23
        ld      (hl),e                                         ;#5451: 73
        inc     hl                                             ;#5452: 23
        push    hl                                             ;#5453: E5
        ld      a,d                                            ;#5454: 7A
        and     3                                              ;#5455: E6 03
        ld      c,a                                            ;#5457: 4F
        ld      a,e                                            ;#5458: 7B
        add     a,a                                            ;#5459: 87
        add     a,a                                            ;#545A: 87
        or      c                                              ;#545B: B1
        and     0Fh                                            ;#545C: E6 0F
        or      0A0h                                           ;#545E: F6 A0
        ld      c,a                                            ;#5460: 4F
        ld      hl,RADAR_GRID                                  ;#5461: 21 00 EA
        ld      a,d                                            ;#5464: 7A
        rra                                                    ;#5465: 1F
        rra                                                    ;#5466: 1F
        and     7                                              ;#5467: E6 07
        add     a,l                                            ;#5469: 85
        ld      l,a                                            ;#546A: 6F
        ld      a,e                                            ;#546B: 7B
        add     a,a                                            ;#546C: 87
        and     78h                                            ;#546D: E6 78
        add     a,l                                            ;#546F: 85
        ld      l,a                                            ;#5470: 6F
        ld      (hl),c                                         ;#5471: 71
        set     7,l                                            ;#5472: CB FD
        ld      (RADAR_LAST_DOT_PTR),hl                        ;#5474: 22 25 E0
        pop     hl                                             ;#5477: E1
        ld      a,l                                            ;#5478: 7D
        and     0F0h                                           ;#5479: E6 F0
        add     a,10h                                          ;#547B: C6 10
        ld      l,a                                            ;#547D: 6F
        dec     b                                              ;#547E: 05
        jp      nz,INIT_STAGE_FLAG_LOOP                        ;#547F: C2 DE 53
        ret                                                    ;#5482: C9

INIT_FLAGS:
        ; Initialize FLAG_TABLE: 10 flags (8 regular + 2 special) at stage start
        ; INIT_FLAGS places the 10 stage flags. Walks FLAG_TABLE (10 entries x 8 bytes),
        ; for each: writes the active flag (1), uses NEXT_RANDOM to pick X/Y inside the
        ; playfield bounds, sets sprite parameters. The last 2 entries (index 9, 8 — set
        ; first in the iteration since B counts down) get tile 38h/34h color 8 (red
        ; SPECIAL flags); the rest get tile 30h color 2 (regular yellow flags). 10 = 8
        ; yellow + 2 red.
        ld      hl,FLAG_TABLE                                  ;#5483: 21 00 E1
        ld      b,0Ah                                          ;#5486: 06 0A
INIT_FLAGS_LOOP_TOP:
        ; Outer djnz of INIT_FLAGS (10 flag entries)
        ld      a,(hl)                                         ;#5488: 7E
        and     a                                              ;#5489: A7
        jp      z,INIT_FLAGS_NEXT_ENTRY                        ;#548A: CA DC 54
        inc     hl                                             ;#548D: 23
        ld      d,(hl)                                         ;#548E: 56
        inc     hl                                             ;#548F: 23
        ld      e,(hl)                                         ;#5490: 5E
        inc     hl                                             ;#5491: 23
        push    hl                                             ;#5492: E5
        ld      h,0                                            ;#5493: 26 00
        ld      a,d                                            ;#5495: 7A
        sub     0Fh                                            ;#5496: D6 0F
        jp      p,INIT_FLAGS_X_POS                             ;#5498: F2 9C 54
        dec     h                                              ;#549B: 25
INIT_FLAGS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended for negative side of screen
        ld      c,a                                            ;#549C: 4F
        add     a,a                                            ;#549D: 87
        add     a,c                                            ;#549E: 81
        ld      l,a                                            ;#549F: 6F
        add     hl,hl                                          ;#54A0: 29
        add     hl,hl                                          ;#54A1: 29
        add     hl,hl                                          ;#54A2: 29
        ld      a,e                                            ;#54A3: 7B
        ld      de,58h                                         ;#54A4: 11 58 00
        add     hl,de                                          ;#54A7: 19
        ex      de,hl                                          ;#54A8: EB
        pop     hl                                             ;#54A9: E1
        ld      (hl),e                                         ;#54AA: 73
        inc     hl                                             ;#54AB: 23
        ld      (hl),d                                         ;#54AC: 72
        inc     hl                                             ;#54AD: 23
        push    hl                                             ;#54AE: E5
        ld      h,0                                            ;#54AF: 26 00
        sub     32h                                            ;#54B1: D6 32
        jp      p,INIT_FLAGS_Y_POS                             ;#54B3: F2 B7 54
        dec     h                                              ;#54B6: 25
INIT_FLAGS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended for top half of screen
        ld      l,a                                            ;#54B7: 6F
        add     a,a                                            ;#54B8: 87
        add     a,l                                            ;#54B9: 85
        ld      l,a                                            ;#54BA: 6F
        add     hl,hl                                          ;#54BB: 29
        add     hl,hl                                          ;#54BC: 29
        add     hl,hl                                          ;#54BD: 29
        ld      de,6Fh                                         ;#54BE: 11 6F 00
        add     hl,de                                          ;#54C1: 19
        ex      de,hl                                          ;#54C2: EB
        pop     hl                                             ;#54C3: E1
        ld      (hl),e                                         ;#54C4: 73
        inc     hl                                             ;#54C5: 23
        ld      (hl),d                                         ;#54C6: 72
        inc     hl                                             ;#54C7: 23
        ld      a,38h                                          ;#54C8: 3E 38
        ld      e,8                                            ;#54CA: 1E 08
        ld      c,b                                            ;#54CC: 48
        dec     c                                              ;#54CD: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54CE: 28 09
        ld      a,34h                                          ;#54D0: 3E 34
        dec     c                                              ;#54D2: 0D
        jr      z,INIT_FLAGS_STORE_TILE                        ;#54D3: 28 04
        ld      a,30h                                          ;#54D5: 3E 30
        ld      e,2                                            ;#54D7: 1E 02
INIT_FLAGS_STORE_TILE:
        ; Choose tile/color: last-2 entries get the 34h/38h red SPECIAL flags
        ld      (hl),a                                         ;#54D9: 77
        inc     hl                                             ;#54DA: 23
        ld      (hl),e                                         ;#54DB: 73
INIT_FLAGS_NEXT_ENTRY:
        ; Advance HL by 10h to next FLAG_TABLE entry, djnz back to top
        ld      a,l                                            ;#54DC: 7D
        and     0F0h                                           ;#54DD: E6 F0
        add     a,10h                                          ;#54DF: C6 10
        ld      l,a                                            ;#54E1: 6F
        djnz    INIT_FLAGS_LOOP_TOP                            ;#54E2: 10 A4
        ret                                                    ;#54E4: C9

NEXT_RANDOM:
        ; LCG+LFSR random byte generator; advances RNG_LCG and RNG_LFSR, returns byte in A
        ; NEXT_RANDOM is a hybrid: an 8-bit LCG (RNG_LCG: x' = 5x + 1) combined with a
        ; 16-bit xor-shift LFSR (RNG_LFSR, seeded to 55AAh if it ever hits 0). Returns
        ; RNG_LCG + (RNG_LFSR low byte) in A. Used by INIT_STAGE for flag placement,
        ; SCROLL_ROCKS for rock positions, and ITERATE_ENEMY_CARS for AI decisions.
        ld      a,(RNG_LCG)                                    ;#54E5: 3A 18 E0
        ld      c,a                                            ;#54E8: 4F
        add     a,a                                            ;#54E9: 87
        add     a,a                                            ;#54EA: 87
        add     a,c                                            ;#54EB: 81
        inc     a                                              ;#54EC: 3C
        ld      (RNG_LCG),a                                    ;#54ED: 32 18 E0
        ld      c,a                                            ;#54F0: 4F
        push    hl                                             ;#54F1: E5
        ld      hl,(RNG_LFSR)                                  ;#54F2: 2A 19 E0
        ld      a,h                                            ;#54F5: 7C
        or      l                                              ;#54F6: B5
        jr      nz,RNG_LFSR_TICK                               ;#54F7: 20 03
        ld      hl,55AAh                                       ;#54F9: 21 AA 55
RNG_LFSR_TICK:
        ; LFSR step: A = H XOR L, shift, then xor bit 6 of XOR back into bit 0
        ld      a,h                                            ;#54FC: 7C
        xor     l                                              ;#54FD: AD
        add     a,a                                            ;#54FE: 87
        add     a,a                                            ;#54FF: 87
        adc     hl,hl                                          ;#5500: ED 6A
        ld      (RNG_LFSR),hl                                  ;#5502: 22 19 E0
        ld      a,l                                            ;#5505: 7D
        pop     hl                                             ;#5506: E1
        add     a,c                                            ;#5507: 81
        ret                                                    ;#5508: C9

SCROLL_FLAGS:
        ; Iterate FLAG_TABLE: apply world scroll, draw each flag sprite, detect collect
        ; SCROLL_FLAGS iterates the 10-entry FLAG_TABLE. For each active flag, it: (1)
        ; world-scrolls the entry's screen position, (2) checks player proximity, (3) on
        ; collect — calls ADD_SCORE, clears the flag's RADAR_GRID dot, decrements
        ; STAGE_DIFFICULTY (the remaining-flags counter); when that reaches 0, sets
        ; STAGE_CLEAR_FLAG. Draws non-collected flags as sprites at their screen
        ; position.
        ld      hl,FLAG_TABLE                                  ;#5509: 21 00 E1
        ld      b,0Ah                                          ;#550C: 06 0A
SCROLL_FLAGS_LOOP_TOP:
        ; Outer djnz of SCROLL_FLAGS (10 entries)
        ld      a,(hl)                                         ;#550E: 7E
        and     a                                              ;#550F: A7
        jp      z,SCROLL_FLAG_NEXT                             ;#5510: CA 76 55
        inc     hl                                             ;#5513: 23
        inc     hl                                             ;#5514: 23
        inc     hl                                             ;#5515: 23
        ld      e,(hl)                                         ;#5516: 5E
        inc     hl                                             ;#5517: 23
        ld      d,(hl)                                         ;#5518: 56
        push    hl                                             ;#5519: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#551A: 3A 16 E0
        ld      l,a                                            ;#551D: 6F
        ld      h,0                                            ;#551E: 26 00
        rla                                                    ;#5520: 17
        jr      nc,SCROLL_FLAG_APPLY_DX                        ;#5521: 30 01
        dec     h                                              ;#5523: 25
SCROLL_FLAG_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to flag X position
        add     hl,de                                          ;#5524: 19
        ex      de,hl                                          ;#5525: EB
        pop     hl                                             ;#5526: E1
        ld      (hl),d                                         ;#5527: 72
        dec     hl                                             ;#5528: 2B
        ld      (hl),e                                         ;#5529: 73
        inc     hl                                             ;#552A: 23
        inc     hl                                             ;#552B: 23
        push    bc                                             ;#552C: C5
        ld      c,(hl)                                         ;#552D: 4E
        inc     hl                                             ;#552E: 23
        ld      b,(hl)                                         ;#552F: 46
        push    hl                                             ;#5530: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#5531: 3A 17 E0
        ld      l,a                                            ;#5534: 6F
        ld      h,0                                            ;#5535: 26 00
        rla                                                    ;#5537: 17
        jr      nc,SCROLL_FLAG_APPLY_DY                        ;#5538: 30 01
        dec     h                                              ;#553A: 25
SCROLL_FLAG_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to flag Y position
        add     hl,bc                                          ;#553B: 09
        ld      b,h                                            ;#553C: 44
        ld      c,l                                            ;#553D: 4D
        pop     hl                                             ;#553E: E1
        ld      (hl),b                                         ;#553F: 70
        dec     hl                                             ;#5540: 2B
        ld      (hl),c                                         ;#5541: 71
        ld      a,b                                            ;#5542: 78
        or      d                                              ;#5543: B2
        jr      nz,SCROLL_FLAG_OFFSCREEN                       ;#5544: 20 39
        ld      a,e                                            ;#5546: 7B
        cp      0A9h                                           ;#5547: FE A9
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#5549: 30 34
        ld      a,c                                            ;#554B: 79
        cp      0E0h                                           ;#554C: FE E0
        jr      nc,SCROLL_FLAG_OFFSCREEN                       ;#554E: 30 2F
        sub     18h                                            ;#5550: D6 18
        inc     hl                                             ;#5552: 23
        inc     hl                                             ;#5553: 23
        ld      d,(hl)                                         ;#5554: 56
        inc     hl                                             ;#5555: 23
        ld      c,(hl)                                         ;#5556: 4E
        push    hl                                             ;#5557: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5558: 2A 14 E0
        ld      (hl),a                                         ;#555B: 77
        inc     hl                                             ;#555C: 23
        ld      (hl),e                                         ;#555D: 73
        inc     hl                                             ;#555E: 23
        ld      (hl),d                                         ;#555F: 72
        inc     hl                                             ;#5560: 23
        ld      (hl),c                                         ;#5561: 71
        inc     hl                                             ;#5562: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5563: 22 14 E0
        pop     hl                                             ;#5566: E1
        sub     4Bh                                            ;#5567: D6 4B
        cp      19h                                            ;#5569: FE 19
        jr      nc,SCROLL_FLAG_POPBC                           ;#556B: 30 08
        ld      a,e                                            ;#556D: 7B
        sub     4Ch                                            ;#556E: D6 4C
        cp      19h                                            ;#5570: FE 19
        jp      c,SCROLL_FLAG_COLLECT                          ;#5572: DA 8C 55
SCROLL_FLAG_POPBC:
        ; After collect check: restore BC saved during the inner body
        pop     bc                                             ;#5575: C1
SCROLL_FLAG_NEXT:
        ; Skip-this-flag path: advance HL by 10h, djnz back to next entry
        ld      a,l                                            ;#5576: 7D
        and     0F0h                                           ;#5577: E6 F0
SCROLL_FLAG_ADV_PTR:
        ; Tail of the per-frame loop: shared HL advance code
        add     a,10h                                          ;#5579: C6 10
        ld      l,a                                            ;#557B: 6F
        djnz    SCROLL_FLAGS_LOOP_TOP                          ;#557C: 10 90
        ret                                                    ;#557E: C9

SCROLL_FLAG_OFFSCREEN:
        ; Off-screen path: deactivate the flag entry and continue
        pop     bc                                             ;#557F: C1
        ld      a,l                                            ;#5580: 7D
        and     0F0h                                           ;#5581: E6 F0
        ld      l,a                                            ;#5583: 6F
        ld      c,(hl)                                         ;#5584: 4E
        dec     c                                              ;#5585: 0D
        jr      z,SCROLL_FLAG_ADV_PTR                          ;#5586: 28 F1
        ld      (hl),0                                         ;#5588: 36 00
        jr      SCROLL_FLAG_ADV_PTR                            ;#558A: 18 ED

SCROLL_FLAG_COLLECT:
        ; Collect: trigger SFX_FLAG, dec STAGE_DIFFICULTY, set STAGE_CLEAR if last
        ld      a,1                                            ;#558C: 3E 01
        ld      (hl),a                                         ;#558E: 77
        dec     hl                                             ;#558F: 2B
        push    hl                                             ;#5590: E5
        ld      a,l                                            ;#5591: 7D
        and     0F0h                                           ;#5592: E6 F0
        ld      l,a                                            ;#5594: 6F
        ld      a,(hl)                                         ;#5595: 7E
        pop     hl                                             ;#5596: E1
        dec     a                                              ;#5597: 3D
        jp      nz,SCROLL_FLAG_POPBC                           ;#5598: C2 75 55
        inc     a                                              ;#559B: 3C
        ld      (SOUND_STATE_FLAG),a                           ;#559C: 32 40 E5
        ld      a,d                                            ;#559F: 7A
        cp      34h                                            ;#55A0: FE 34
        jr      nz,SCROLL_FLAG_CHECK_SPECIAL                   ;#55A2: 20 07
        ld      a,1                                            ;#55A4: 3E 01
        ld      (PLAYER_DEAD_FLAG),a                           ;#55A6: 32 3B E0
        jr      SCROLL_FLAG_SCORE_TICK                         ;#55A9: 18 11

SCROLL_FLAG_CHECK_SPECIAL:
        ; Check whether this is a SPECIAL (red) flag for bonus scoring
        cp      38h                                            ;#55AB: FE 38
        jr      nz,SCROLL_FLAG_SCORE_TICK                      ;#55AD: 20 0D
        xor     a                                              ;#55AF: AF
        ld      (SOUND_STATE_FLAG),a                           ;#55B0: 32 40 E5
        inc     a                                              ;#55B3: 3C
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#55B4: 32 41 E5
        ld      a,1                                            ;#55B7: 3E 01
        ld      (MOVEMENT_SUB_PHASE),a                         ;#55B9: 32 2D E0
SCROLL_FLAG_SCORE_TICK:
        ; Award score chunk per-tick during the collect animation
        ld      a,(FRAME_TICK_SUB)                             ;#55BC: 3A 2C E0
        inc     a                                              ;#55BF: 3C
        ld      (FRAME_TICK_SUB),a                             ;#55C0: 32 2C E0
        add     a,a                                            ;#55C3: 87
        add     a,a                                            ;#55C4: 87
        add     a,a                                            ;#55C5: 87
        add     a,78h                                          ;#55C6: C6 78
        ld      c,a                                            ;#55C8: 4F
        ld      a,(MOVEMENT_SUB_PHASE)                         ;#55C9: 3A 2D E0
        and     a                                              ;#55CC: A7
        jr      z,SCROLL_FLAG_PHASE_SET                        ;#55CD: 28 04
        ld      a,c                                            ;#55CF: 79
        add     a,4                                            ;#55D0: C6 04
        ld      c,a                                            ;#55D2: 4F
SCROLL_FLAG_PHASE_SET:
        ; Phase-set: write target SAT cell color/tile for the score bubble
        ld      (hl),c                                         ;#55D3: 71
        push    hl                                             ;#55D4: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#55D5: 2A 14 E0
        dec     hl                                             ;#55D8: 2B
        ld      (hl),1                                         ;#55D9: 36 01
        dec     hl                                             ;#55DB: 2B
        ld      (hl),c                                         ;#55DC: 71
        pop     hl                                             ;#55DD: E1
        ld      a,l                                            ;#55DE: 7D
        and     0F0h                                           ;#55DF: E6 F0
        ld      l,a                                            ;#55E1: 6F
        ld      (hl),2                                         ;#55E2: 36 02
        ld      a,c                                            ;#55E4: 79
        rra                                                    ;#55E5: 1F
        rra                                                    ;#55E6: 1F
        and     1Fh                                            ;#55E7: E6 1F
        call    ADD_SCORE                                      ;#55E9: CD DC 67
        push    hl                                             ;#55EC: E5
        inc     hl                                             ;#55ED: 23
        ld      d,(hl)                                         ;#55EE: 56
        inc     hl                                             ;#55EF: 23
        ld      e,(hl)                                         ;#55F0: 5E
        ld      hl,RADAR_GRID                                  ;#55F1: 21 00 EA
        ld      a,d                                            ;#55F4: 7A
        rra                                                    ;#55F5: 1F
        rra                                                    ;#55F6: 1F
        and     7                                              ;#55F7: E6 07
        add     a,l                                            ;#55F9: 85
        ld      l,a                                            ;#55FA: 6F
        ld      a,e                                            ;#55FB: 7B
        add     a,a                                            ;#55FC: 87
        and     78h                                            ;#55FD: E6 78
        add     a,l                                            ;#55FF: 85
        ld      l,a                                            ;#5600: 6F
        ld      (hl),90h                                       ;#5601: 36 90
        pop     hl                                             ;#5603: E1
        ld      a,(STAGE_DIFFICULTY)                           ;#5604: 3A 2E E0
        dec     a                                              ;#5607: 3D
        ld      (STAGE_DIFFICULTY),a                           ;#5608: 32 2E E0
        jp      nz,SCROLL_FLAG_NOT_LAST                        ;#560B: C2 13 56
        ld      a,1                                            ;#560E: 3E 01
        ld      (STAGE_CLEAR_FLAG),a                           ;#5610: 32 2F E0
SCROLL_FLAG_NOT_LAST:
        ; Not the last flag: fall through to LBL_71D7 (update HUD count)
        call    LOAD_STAGE_DIFFICULTY_TIER                     ;#5613: CD CD 71
        jp      SCROLL_FLAG_POPBC                              ;#5616: C3 75 55

SCROLL_ROCKS:
        ; Iterate ROCK_TABLE: world-scroll + sprite draw
        ; SCROLL_ROCKS uses ROCK_SPAWN_COUNT as the iteration count. Each entry is
        ; seeded with a random position from ROCK_POSITIONS_N (using NEXT_RANDOM as the
        ; index byte), then drawn as a rock sprite at its world-scrolled screen
        ; position. Rocks are static obstacles — no AI.
        ld      hl,ROCK_TABLE                                  ;#5619: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#561C: 3A 1C E0
        and     a                                              ;#561F: A7
        ret     z                                              ;#5620: C8
        ld      b,a                                            ;#5621: 47
SCROLL_ROCKS_LOOP_TOP:
        ; Outer djnz of SCROLL_ROCKS
        ld      (hl),1                                         ;#5622: 36 01
        inc     hl                                             ;#5624: 23
        push    hl                                             ;#5625: E5
SCROLL_ROCKS_PICK_POSITION:
        ; Pick a random ROCK_POSITIONS_N index, jump out if dup vs other rocks
        call    NEXT_RANDOM                                    ;#5626: CD E5 54
        ld      hl,MAZE_BITMAP_0                               ;#5629: 21 00 7C
        add     a,a                                            ;#562C: 87
        or      0E0h                                           ;#562D: F6 E0
        ld      l,a                                            ;#562F: 6F
        ld      a,(STAGE_PALETTE_INDEX)                        ;#5630: 3A 30 E0
        rra                                                    ;#5633: 1F
        rra                                                    ;#5634: 1F
        and     3                                              ;#5635: E6 03
        or      h                                              ;#5637: B4
        ld      h,a                                            ;#5638: 67
        ld      d,(hl)                                         ;#5639: 56
        inc     hl                                             ;#563A: 23
        ld      e,(hl)                                         ;#563B: 5E
        ld      hl,ROCK_TABLE                                  ;#563C: 21 00 E2
        ld      a,0Ch                                          ;#563F: 3E 0C
        sub     b                                              ;#5641: 90
        jr      z,SCROLL_ROCKS_STORE                           ;#5642: 28 12
        ld      c,a                                            ;#5644: 4F
SCROLL_ROCKS_DEDUP_LOOP:
        ; Dedup loop: check candidate vs each placed rock entry
        inc     hl                                             ;#5645: 23
        ld      a,(hl)                                         ;#5646: 7E
        inc     hl                                             ;#5647: 23
        cp      d                                              ;#5648: BA
        jr      nz,SCROLL_ROCKS_DEDUP_NEXT                     ;#5649: 20 04
        ld      a,(hl)                                         ;#564B: 7E
        cp      e                                              ;#564C: BB
        jr      z,SCROLL_ROCKS_PICK_POSITION                   ;#564D: 28 D7
SCROLL_ROCKS_DEDUP_NEXT:
        ; Dedup OK for this entry: advance pointer to next rock
        ld      a,l                                            ;#564F: 7D
        add     a,0Eh                                          ;#5650: C6 0E
        ld      l,a                                            ;#5652: 6F
        dec     c                                              ;#5653: 0D
        jr      nz,SCROLL_ROCKS_DEDUP_LOOP                     ;#5654: 20 EF
SCROLL_ROCKS_STORE:
        ; All checks passed: write rock (X, Y) into ROCK_TABLE
        pop     hl                                             ;#5656: E1
        ld      (hl),d                                         ;#5657: 72
        inc     hl                                             ;#5658: 23
        ld      (hl),e                                         ;#5659: 73
        ld      a,l                                            ;#565A: 7D
        and     0F0h                                           ;#565B: E6 F0
        add     a,10h                                          ;#565D: C6 10
        ld      l,a                                            ;#565F: 6F
        djnz    SCROLL_ROCKS_LOOP_TOP                          ;#5660: 10 C0
        ret                                                    ;#5662: C9

INIT_ROCKS:
        ; Initialize ROCK_TABLE at stage start
        ; INIT_ROCKS clears ROCK_TABLE and seeds it from MAZE_BITMAP_N at
        ; MAZE_BITMAP_0..MAZE_BITMAP_3 using random positions. ROCK_SPAWN_COUNT
        ; (ROCK_SPAWN_COUNT) controls the count. Called once per stage from
        ; INITIAL_STATE_HANDLER's tail.
        ld      hl,ROCK_TABLE                                  ;#5663: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5666: 3A 1C E0
        and     a                                              ;#5669: A7
        ret     z                                              ;#566A: C8
        ld      b,a                                            ;#566B: 47
INIT_ROCKS_LOOP_TOP:
        ; Outer djnz of INIT_ROCKS
        ld      a,(hl)                                         ;#566C: 7E
        and     a                                              ;#566D: A7
        jp      z,INIT_ROCKS_NEXT_ENTRY                        ;#566E: CA B1 56
        inc     hl                                             ;#5671: 23
        ld      d,(hl)                                         ;#5672: 56
        inc     hl                                             ;#5673: 23
        ld      e,(hl)                                         ;#5674: 5E
        inc     hl                                             ;#5675: 23
        push    hl                                             ;#5676: E5
        ld      h,0                                            ;#5677: 26 00
        ld      a,d                                            ;#5679: 7A
        sub     0Fh                                            ;#567A: D6 0F
        jp      p,INIT_ROCKS_X_POS                             ;#567C: F2 80 56
        dec     h                                              ;#567F: 25
INIT_ROCKS_X_POS:
        ; X mapping: (X-15)*3*8 + 58h, sign-extended
        ld      c,a                                            ;#5680: 4F
        add     a,a                                            ;#5681: 87
        add     a,c                                            ;#5682: 81
        ld      l,a                                            ;#5683: 6F
        add     hl,hl                                          ;#5684: 29
        add     hl,hl                                          ;#5685: 29
        add     hl,hl                                          ;#5686: 29
        ld      a,e                                            ;#5687: 7B
        ld      de,58h                                         ;#5688: 11 58 00
        add     hl,de                                          ;#568B: 19
        ex      de,hl                                          ;#568C: EB
        pop     hl                                             ;#568D: E1
        ld      (hl),e                                         ;#568E: 73
        inc     hl                                             ;#568F: 23
        ld      (hl),d                                         ;#5690: 72
        inc     hl                                             ;#5691: 23
        push    hl                                             ;#5692: E5
        ld      h,0                                            ;#5693: 26 00
        sub     32h                                            ;#5695: D6 32
        jp      p,INIT_ROCKS_Y_POS                             ;#5697: F2 9B 56
        dec     h                                              ;#569A: 25
INIT_ROCKS_Y_POS:
        ; Y mapping: (Y-50)*3*8 + 6Fh, sign-extended
        ld      l,a                                            ;#569B: 6F
        add     a,a                                            ;#569C: 87
        add     a,l                                            ;#569D: 85
        ld      l,a                                            ;#569E: 6F
        add     hl,hl                                          ;#569F: 29
        add     hl,hl                                          ;#56A0: 29
        add     hl,hl                                          ;#56A1: 29
        ld      de,6Fh                                         ;#56A2: 11 6F 00
        add     hl,de                                          ;#56A5: 19
        ex      de,hl                                          ;#56A6: EB
        pop     hl                                             ;#56A7: E1
        ld      (hl),e                                         ;#56A8: 73
        inc     hl                                             ;#56A9: 23
        ld      (hl),d                                         ;#56AA: 72
        inc     hl                                             ;#56AB: 23
        ld      (hl),3Ch                                       ;#56AC: 36 3C
        inc     hl                                             ;#56AE: 23
        ld      (hl),6                                         ;#56AF: 36 06
INIT_ROCKS_NEXT_ENTRY:
        ; Advance HL by 10h to next ROCK_TABLE entry, djnz back to top
        ld      a,l                                            ;#56B1: 7D
        and     0F0h                                           ;#56B2: E6 F0
        add     a,10h                                          ;#56B4: C6 10
        ld      l,a                                            ;#56B6: 6F
        djnz    INIT_ROCKS_LOOP_TOP                            ;#56B7: 10 B3
        ret                                                    ;#56B9: C9

UPDATE_ROCKS_COLLISION:
        ; Second pass over ROCK_TABLE (different update phase)
        ; UPDATE_ROCKS_COLLISION is the second iteration over ROCK_TABLE per frame,
        ; performing the "did the player hit a rock" detection. Different from
        ; SCROLL_ROCKS which renders sprites — PASS2 is collision logic.
        ld      hl,ROCK_TABLE                                  ;#56BA: 21 00 E2
        ld      a,(ROCK_SPAWN_COUNT)                           ;#56BD: 3A 1C E0
        and     a                                              ;#56C0: A7
        ret     z                                              ;#56C1: C8
        ld      b,a                                            ;#56C2: 47
UPDATE_ROCKS_COLLISION_LOOP_TOP:
        ; Outer djnz of UPDATE_ROCKS_COLLISION
        inc     hl                                             ;#56C3: 23
        inc     hl                                             ;#56C4: 23
        inc     hl                                             ;#56C5: 23
        ld      e,(hl)                                         ;#56C6: 5E
        inc     hl                                             ;#56C7: 23
        ld      d,(hl)                                         ;#56C8: 56
        push    hl                                             ;#56C9: E5
        ld      a,(WORLD_SCROLL_DX)                            ;#56CA: 3A 16 E0
        ld      l,a                                            ;#56CD: 6F
        ld      h,0                                            ;#56CE: 26 00
        rla                                                    ;#56D0: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DX             ;#56D1: 30 01
        dec     h                                              ;#56D3: 25
UPDATE_ROCKS_COLLISION_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to rock X position
        add     hl,de                                          ;#56D4: 19
        ex      de,hl                                          ;#56D5: EB
        pop     hl                                             ;#56D6: E1
        ld      (hl),d                                         ;#56D7: 72
        dec     hl                                             ;#56D8: 2B
        ld      (hl),e                                         ;#56D9: 73
        inc     hl                                             ;#56DA: 23
        inc     hl                                             ;#56DB: 23
        push    bc                                             ;#56DC: C5
        ld      c,(hl)                                         ;#56DD: 4E
        inc     hl                                             ;#56DE: 23
        ld      b,(hl)                                         ;#56DF: 46
        push    hl                                             ;#56E0: E5
        ld      a,(WORLD_SCROLL_DY)                            ;#56E1: 3A 17 E0
        ld      l,a                                            ;#56E4: 6F
        ld      h,0                                            ;#56E5: 26 00
        rla                                                    ;#56E7: 17
        jr      nc,UPDATE_ROCKS_COLLISION_APPLY_DY             ;#56E8: 30 01
        dec     h                                              ;#56EA: 25
UPDATE_ROCKS_COLLISION_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to rock Y position
        add     hl,bc                                          ;#56EB: 09
        ld      b,h                                            ;#56EC: 44
        ld      c,l                                            ;#56ED: 4D
        pop     hl                                             ;#56EE: E1
        ld      (hl),b                                         ;#56EF: 70
        dec     hl                                             ;#56F0: 2B
        ld      (hl),c                                         ;#56F1: 71
        ld      a,b                                            ;#56F2: 78
        or      d                                              ;#56F3: B2
        jr      nz,UPDATE_ROCKS_COLLISION_NEXT                 ;#56F4: 20 33
        ld      a,e                                            ;#56F6: 7B
        cp      0A9h                                           ;#56F7: FE A9
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#56F9: 30 2E
        ld      a,c                                            ;#56FB: 79
        cp      0E0h                                           ;#56FC: FE E0
        jr      nc,UPDATE_ROCKS_COLLISION_NEXT                 ;#56FE: 30 29
        sub     18h                                            ;#5700: D6 18
        inc     hl                                             ;#5702: 23
        inc     hl                                             ;#5703: 23
        ld      d,(hl)                                         ;#5704: 56
        inc     hl                                             ;#5705: 23
        ld      c,(hl)                                         ;#5706: 4E
        push    hl                                             ;#5707: E5
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5708: 2A 14 E0
        ld      (hl),a                                         ;#570B: 77
        inc     hl                                             ;#570C: 23
        ld      (hl),e                                         ;#570D: 73
        inc     hl                                             ;#570E: 23
        ld      (hl),d                                         ;#570F: 72
        inc     hl                                             ;#5710: 23
        ld      (hl),c                                         ;#5711: 71
        inc     hl                                             ;#5712: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5713: 22 14 E0
        sub     4Fh                                            ;#5716: D6 4F
        cp      11h                                            ;#5718: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#571A: 30 0C
        ld      a,e                                            ;#571C: 7B
        sub     50h                                            ;#571D: D6 50
        cp      11h                                            ;#571F: FE 11
        jr      nc,UPDATE_ROCKS_COLLISION_DEATH                ;#5721: 30 05
        ld      a,1                                            ;#5723: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#5725: 32 49 E0
UPDATE_ROCKS_COLLISION_DEATH:
        ; Player-on-rock collision: set GAME_OVER_FLAG=1
        pop     hl                                             ;#5728: E1
UPDATE_ROCKS_COLLISION_NEXT:
        ; Skip-this-rock: advance HL by 10h, djnz back
        pop     bc                                             ;#5729: C1
        ld      a,l                                            ;#572A: 7D
        and     0F0h                                           ;#572B: E6 F0
        add     a,10h                                          ;#572D: C6 10
        ld      l,a                                            ;#572F: 6F
        djnz    UPDATE_ROCKS_COLLISION_LOOP_TOP                ;#5730: 10 91
        ret                                                    ;#5732: C9

ADD_DE_TO_ENEMY_X:
        ; Add DE (sign-extended) to ENEMY_OFFSET_X (9..0Ah) of all 7 enemies
        ; ADD_DE_TO_ENEMY_X iterates 7 ENEMY_CAR_TABLE entries (skipping
        ; ENEMY_CAR_TABLE+0=type). For each entry, adds DE (sign-extended via rla) to
        ; ENEMY_OFFSET_X (screen X, 9..0Ah). Applies the world-scroll delta to every
        ; enemy's screen X when the player moves.
        exx                                                    ;#5733: D9
        ld      e,a                                            ;#5734: 5F
        ld      d,0                                            ;#5735: 16 00
        rla                                                    ;#5737: 17
        jr      nc,ADD_DE_ENEMY_X_INIT                         ;#5738: 30 01
        dec     d                                              ;#573A: 15
ADD_DE_ENEMY_X_INIT:
        ; ADD_DE_TO_ENEMY_X init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#573B: DD 21 00 E3
        ld      bc,10h                                         ;#573F: 01 10 00
        ld      a,7                                            ;#5742: 3E 07
ADD_DE_ENEMY_X_LOOP:
        ; Per-enemy djnz body: load (ix+9..0Ah), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5744: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5747: DD 6E 09
        add     hl,de                                          ;#574A: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#574B: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#574E: DD 75 09
        add     ix,bc                                          ;#5751: DD 09
        dec     a                                              ;#5753: 3D
        jr      nz,ADD_DE_ENEMY_X_LOOP                         ;#5754: 20 EE
        ld      a,e                                            ;#5756: 7B
        exx                                                    ;#5757: D9
        ret                                                    ;#5758: C9

ADD_DE_TO_ENEMY_Y:
        ; Add DE (sign-extended) to ENEMY_OFFSET_Y (0Bh..0Ch) of all 7 enemies
        ; ADD_DE_TO_ENEMY_Y is the same shape for ENEMY_OFFSET_Y (screen Y, 0Bh..0Ch).
        ; Together they scroll all enemies' screen X/Y with the world.
        exx                                                    ;#5759: D9
        ld      e,a                                            ;#575A: 5F
        ld      d,0                                            ;#575B: 16 00
        rla                                                    ;#575D: 17
        jr      nc,ADD_DE_ENEMY_Y_INIT                         ;#575E: 30 01
        dec     d                                              ;#5760: 15
ADD_DE_ENEMY_Y_INIT:
        ; ADD_DE_TO_ENEMY_Y init: sign-extend A into DE
        ld      ix,ENEMY_CAR_TABLE                             ;#5761: DD 21 00 E3
        ld      bc,10h                                         ;#5765: 01 10 00
        ld      a,7                                            ;#5768: 3E 07
ADD_DE_ENEMY_Y_LOOP:
        ; Per-enemy djnz body: load (ix+0Bh..0Ch), add DE, store back
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#576A: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#576D: DD 6E 0B
        add     hl,de                                          ;#5770: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5771: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5774: DD 75 0B
        add     ix,bc                                          ;#5777: DD 09
        dec     a                                              ;#5779: 3D
        jr      nz,ADD_DE_ENEMY_Y_LOOP                         ;#577A: 20 EE
        ld      a,e                                            ;#577C: 7B
        exx                                                    ;#577D: D9
        ret                                                    ;#577E: C9

ITERATE_ENEMY_CARS:
        ; Dec ENEMY_CAR_ITER_TIMER, then call UPDATE_ENEMY_CAR_ENTRY 6x (AI every frame)
        ; ITERATE_ENEMY_CARS decrements ENEMY_CAR_ITER_TIMER toward 0 each frame, then
        ; unconditionally calls UPDATE_ENEMY_CAR_ENTRY 6 times — the AI runs every frame
        ; regardless of the timer. The timer is a start-of-stage grace period: while it
        ; is non-zero an enemy touching the player does not set GAME_OVER_FLAG (checked
        ; at 5A74h).
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#577F: 3A 1D E0
        and     a                                              ;#5782: A7
        jr      z,ITER_ENEMY_KICK_AI                           ;#5783: 28 04
        dec     a                                              ;#5785: 3D
        ld      (ENEMY_CAR_ITER_TIMER),a                       ;#5786: 32 1D E0
ITER_ENEMY_KICK_AI:
        ; After timer dec: call UPDATE_ENEMY_CAR_ENTRY 6 times in a row
        ld      ix,ENEMY_CAR_TABLE                             ;#5789: DD 21 00 E3
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#578D: CD 9F 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5790: CD 9F 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5793: CD 9F 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5796: CD 9F 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#5799: CD 9F 57
        call    UPDATE_ENEMY_CAR_ENTRY                         ;#579C: CD 9F 57
UPDATE_ENEMY_CAR_ENTRY:
        ; Update ENEMY_CAR_TABLE entry; branch on (ix+0) type, reads PLAYER_MOVE_GATE
        ; UPDATE_ENEMY_CAR_ENTRY runs each enemy car's AI per tick. Reads (ix+0) type;
        ; if 2 (special "hit player" state), branches to DRAW_ENEMY_CAR_SPRITE.
        ; Otherwise (PLAYER_MOVE_GATE clear and ENEMY_STEP_SPEED non-zero) chases the
        ; player: rock/smoke bounce via CHECK_ENEMY_HITS_ROCK, then a direction pick
        ; toward PLAYER_SCREEN_X/Y using APPLY_DIRECTION_TO_POS and the SCAN_PLAYFIELD_*
        ; helpers, moving at ENEMY_STEP_SPEED. See ENEMY_AI.md.
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#579F: DD 7E 00
        and     a                                              ;#57A2: A7
        ret     z                                              ;#57A3: C8
        cp      2                                              ;#57A4: FE 02
        jp      z,ENEMY_HIT_PHASE                              ;#57A6: CA 11 5A
        ld      a,(PLAYER_MOVE_GATE)                           ;#57A9: 3A 45 E0
        and     a                                              ;#57AC: A7
        jr      nz,ENEMY_AI_RUN_TICK                           ;#57AD: 20 08
        ld      hl,(ENEMY_STEP_SPEED)                          ;#57AF: 2A 41 E0
        ld      a,h                                            ;#57B2: 7C
        or      l                                              ;#57B3: B5
        jp      z,DRAW_ENEMY_CAR_SPRITE                        ;#57B4: CA 32 5A
ENEMY_AI_RUN_TICK:
        ; Run AI for this enemy: rock collision, AI tick countdown, target chase
        call    CHECK_ENEMY_HITS_ROCK                          ;#57B7: CD 7A 5B
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#57BA: DD 7E 01
        dec     (ix+ENEMY_OFFSET_TIMER)                        ;#57BD: DD 35 01
        cp      6                                              ;#57C0: FE 06
        jp      nc,DRAW_ENEMY_CAR_SPRITE                       ;#57C2: D2 32 5A
        and     a                                              ;#57C5: A7
        jr      nz,ENEMY_BOUNCE_DELAY                          ;#57C6: 20 03
        inc     (ix+ENEMY_OFFSET_TIMER)                        ;#57C8: DD 34 01
ENEMY_BOUNCE_DELAY:
        ; Bounce-delay over: re-evaluate target direction
        ld      a,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#57CB: DD 7E 04
        sub     0Ah                                            ;#57CE: D6 0A
        cp      5                                              ;#57D0: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57D2: D2 80 58
        ld      a,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#57D5: DD 7E 07
        sub     0Ah                                            ;#57D8: D6 0A
        cp      5                                              ;#57DA: FE 05
        jp      nc,ENEMY_READ_DIR                              ;#57DC: D2 80 58
        dec     (ix+ENEMY_OFFSET_STATE)                        ;#57DF: DD 35 02
        jp      nz,ENEMY_RETRY_DIRS                            ;#57E2: C2 54 58
        ld      (ix+ENEMY_OFFSET_STATE),2                      ;#57E5: DD 36 02 02
        ld      a,(PLAYER_SCREEN_Y)                            ;#57E9: 3A 24 E0
        sub     (ix+ENEMY_OFFSET_CELL_Y)                       ;#57EC: DD 96 08
        ld      h,a                                            ;#57EF: 67
        jr      nc,ENEMY_ABS_DY                                ;#57F0: 30 02
        neg                                                    ;#57F2: ED 44
ENEMY_ABS_DY:
        ; |target_y - my_y| - jr nc skips neg, branch falls into ABS_DY
        ld      l,a                                            ;#57F4: 6F
        ld      a,(PLAYER_SCREEN_X)                            ;#57F5: 3A 23 E0
        sub     (ix+ENEMY_OFFSET_CELL_X)                       ;#57F8: DD 96 05
        ld      d,a                                            ;#57FB: 57
        jr      nc,ENEMY_ABS_DX                                ;#57FC: 30 02
        neg                                                    ;#57FE: ED 44
ENEMY_ABS_DX:
        ; |target_x - my_x| - jr nc skips neg, branch falls into ABS_DX
        cp      l                                              ;#5800: BD
        jp      nc,ENEMY_PREFER_HORIZ                          ;#5801: D2 2D 58
        xor     a                                              ;#5804: AF
        bit     7,h                                            ;#5805: CB 7C
        jr      nz,ENEMY_STORE_DIR_VERT                        ;#5807: 20 02
        ld      a,2                                            ;#5809: 3E 02
ENEMY_STORE_DIR_VERT:
        ; Vertical preferred: store dir 0 or 2 based on sign(dy) into c
        ld      c,a                                            ;#580B: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#580C: DD 96 0F
        and     3                                              ;#580F: E6 03
        cp      2                                              ;#5811: FE 02
        ld      a,c                                            ;#5813: 79
        jr      z,ENEMY_ROTATE_HORIZ                           ;#5814: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#5816: CD DA 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5819: D2 72 58
ENEMY_ROTATE_HORIZ:
        ; Rotate to horizontal: fall back to horiz when vertical fails APPLY_DIR
        ld      a,1                                            ;#581C: 3E 01
        bit     7,d                                            ;#581E: CB 7A
        jr      z,ENEMY_FALLBACK_HORIZ                         ;#5820: 28 02
        ld      a,3                                            ;#5822: 3E 03
ENEMY_FALLBACK_HORIZ:
        ; Horizontal fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#5824: CD DA 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5827: D2 72 58
        jp      ENEMY_RETRY_DIRS                               ;#582A: C3 54 58

ENEMY_PREFER_HORIZ:
        ; Horizontal preferred: store dir 1 or 3 based on sign(dx) into c
        ld      a,1                                            ;#582D: 3E 01
        ld      e,h                                            ;#582F: 5C
        bit     7,d                                            ;#5830: CB 7A
        jr      z,ENEMY_STORE_DIR_HORIZ                        ;#5832: 28 02
        ld      a,3                                            ;#5834: 3E 03
ENEMY_STORE_DIR_HORIZ:
        ; Horizontal store: keep direction in c, try APPLY_DIRECTION_TO_POS
        ld      c,a                                            ;#5836: 4F
        sub     (ix+ENEMY_OFFSET_DIR)                          ;#5837: DD 96 0F
        and     3                                              ;#583A: E6 03
        cp      2                                              ;#583C: FE 02
        ld      a,c                                            ;#583E: 79
        jr      z,ENEMY_ROTATE_VERT                            ;#583F: 28 06
        call    APPLY_DIRECTION_TO_POS                         ;#5841: CD DA 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5844: D2 72 58
ENEMY_ROTATE_VERT:
        ; Rotate to vertical: fall back to vertical when horiz fails APPLY_DIR
        xor     a                                              ;#5847: AF
        bit     7,e                                            ;#5848: CB 7B
        jr      nz,ENEMY_FALLBACK_VERT                         ;#584A: 20 02
        ld      a,2                                            ;#584C: 3E 02
ENEMY_FALLBACK_VERT:
        ; Vertical fallback after rotate: try APPLY_DIRECTION_TO_POS again
        call    APPLY_DIRECTION_TO_POS                         ;#584E: CD DA 5B
        jp      nc,ENEMY_REVERSE_GUARD                         ;#5851: D2 72 58
ENEMY_RETRY_DIRS:
        ; Retry directions: cycle through 4 directions looking for an unblocked one
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5854: DD 7E 0F
        call    APPLY_DIRECTION_TO_POS                         ;#5857: CD DA 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#585A: 30 0E
        inc     a                                              ;#585C: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#585D: CD DA 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#5860: 30 08
        inc     a                                              ;#5862: 3C
        inc     a                                              ;#5863: 3C
        call    APPLY_DIRECTION_TO_POS                         ;#5864: CD DA 5B
        jr      nc,ENEMY_PICK_DIR_OK                           ;#5867: 30 01
        dec     a                                              ;#5869: 3D
ENEMY_PICK_DIR_OK:
        ; Direction picked: mask to 2 bits and store as (ix+0Fh)
        and     3                                              ;#586A: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#586C: DD 77 0F
        jp      ENEMY_DISPATCH_DIR                             ;#586F: C3 83 58

ENEMY_REVERSE_GUARD:
        ; Reverse-guard: don't flip 180 degrees on consecutive ticks
        and     3                                              ;#5872: E6 03
        ld      c,a                                            ;#5874: 4F
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5875: DD 7E 0F
        xor     2                                              ;#5878: EE 02
        cp      c                                              ;#587A: B9
        jr      z,ENEMY_RETRY_DIRS                             ;#587B: 28 D7
        ld      (ix+ENEMY_OFFSET_DIR),c                        ;#587D: DD 71 0F
ENEMY_READ_DIR:
        ; Read (ix+0Fh) as current AI direction byte
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5880: DD 7E 0F
ENEMY_DISPATCH_DIR:
        ; Dispatch on direction bits: 0/1/2/3 -> DIR0/DIR1/DIR2/DIR3 paths
        rra                                                    ;#5883: 1F
        jp      nc,ENEMY_DIR2_RUN                              ;#5884: D2 4C 59
        rra                                                    ;#5887: 1F
        jr      nc,ENEMY_DIR1_RUN                              ;#5888: 30 62
        ld      a,0Ch                                          ;#588A: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#588C: DD 96 07
        jr      z,ENEMY_DIR2_DONE                              ;#588F: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#5891: DD 36 07 0C
        ld      e,a                                            ;#5895: 5F
        ld      d,0                                            ;#5896: 16 00
        jr      nc,ENEMY_DIR2_ADD                              ;#5898: 30 01
        dec     d                                              ;#589A: 15
ENEMY_DIR2_ADD:
        ; DIR2 (right) inner: add velocity to (ix+0Bh..0Ch) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#589B: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#589E: DD 6E 0B
        add     hl,de                                          ;#58A1: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#58A2: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#58A5: DD 75 0B
ENEMY_DIR2_DONE:
        ; DIR2 done: update target_pos and shape change
        ld      de,(ENEMY_STEP_SPEED)                          ;#58A8: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#58AC: 3A 45 E0
        and     a                                              ;#58AF: A7
        jr      z,ENEMY_DIR0_RUN                               ;#58B0: 28 03
        ld      de,300h                                        ;#58B2: 11 00 03
ENEMY_DIR0_RUN:
        ; DIR0 (up) main: write velocity to (ix+4) and propagate
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#58B5: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#58B8: DD 6E 03
        and     a                                              ;#58BB: A7
        ld      a,h                                            ;#58BC: 7C
        sbc     hl,de                                          ;#58BD: ED 52
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#58BF: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#58C2: DD 75 03
        sub     h                                              ;#58C5: 94
        neg                                                    ;#58C6: ED 44
        ld      e,a                                            ;#58C8: 5F
        ld      d,0                                            ;#58C9: 16 00
        rla                                                    ;#58CB: 17
        jr      nc,ENEMY_DIR0_BORROW_CHECK                     ;#58CC: 30 01
        dec     d                                              ;#58CE: 15
ENEMY_DIR0_BORROW_CHECK:
        ; DIR0 borrow check: if (ix+4) overflowed negative, fix +18h and dec (ix+5)
        bit     7,h                                            ;#58CF: CB 7C
        jr      z,ENEMY_DIR0_STORE_POS                         ;#58D1: 28 09
        ld      a,h                                            ;#58D3: 7C
        add     a,18h                                          ;#58D4: C6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#58D6: DD 77 04
        dec     (ix+ENEMY_OFFSET_CELL_X)                       ;#58D9: DD 35 05
ENEMY_DIR0_STORE_POS:
        ; DIR0 store: write updated world X (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#58DC: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#58DF: DD 6E 09
        add     hl,de                                          ;#58E2: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#58E3: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#58E6: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#58E9: C3 32 5A

ENEMY_DIR1_RUN:
        ; DIR1 (right) main: write velocity to (ix+7) and propagate to world Y
        ld      a,0Ch                                          ;#58EC: 3E 0C
        sub     (ix+ENEMY_OFFSET_Y_ACCUM_HI)                   ;#58EE: DD 96 07
        jr      z,ENEMY_DIR1_PHASE2                            ;#58F1: 28 17
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),0Ch               ;#58F3: DD 36 07 0C
        ld      e,a                                            ;#58F7: 5F
        ld      d,0                                            ;#58F8: 16 00
        jr      nc,ENEMY_DIR1_ADD                              ;#58FA: 30 01
        dec     d                                              ;#58FC: 15
ENEMY_DIR1_ADD:
        ; DIR1 add: adjust position by delta and store new (ix+0Bh..0Ch)
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#58FD: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5900: DD 6E 0B
        add     hl,de                                          ;#5903: 19
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5904: DD 74 0C
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5907: DD 75 0B
ENEMY_DIR1_PHASE2:
        ; DIR1 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#590A: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#590E: 3A 45 E0
        and     a                                              ;#5911: A7
        jr      z,ENEMY_DIR1_APPLY                             ;#5912: 28 03
        ld      de,300h                                        ;#5914: 11 00 03
ENEMY_DIR1_APPLY:
        ; DIR1 apply: add target step into (ix+3..+4) world X
        ld      h,(ix+ENEMY_OFFSET_X_ACCUM_HI)                 ;#5917: DD 66 04
        ld      l,(ix+ENEMY_OFFSET_X_ACCUM_LO)                 ;#591A: DD 6E 03
        ld      a,h                                            ;#591D: 7C
        add     hl,de                                          ;#591E: 19
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),h                 ;#591F: DD 74 04
        ld      (ix+ENEMY_OFFSET_X_ACCUM_LO),l                 ;#5922: DD 75 03
        sub     h                                              ;#5925: 94
        neg                                                    ;#5926: ED 44
        ld      e,a                                            ;#5928: 5F
        ld      d,0                                            ;#5929: 16 00
        rla                                                    ;#592B: 17
        jr      nc,ENEMY_DIR1_CARRY_CHECK                      ;#592C: 30 01
        dec     d                                              ;#592E: 15
ENEMY_DIR1_CARRY_CHECK:
        ; DIR1 carry check: if (ix+4) >= 18h, fix -18h and inc (ix+5)
        ld      a,h                                            ;#592F: 7C
        cp      18h                                            ;#5930: FE 18
        jr      c,ENEMY_DIR1_STORE_POS                         ;#5932: 38 08
        sub     18h                                            ;#5934: D6 18
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),a                 ;#5936: DD 77 04
        inc     (ix+ENEMY_OFFSET_CELL_X)                       ;#5939: DD 34 05
ENEMY_DIR1_STORE_POS:
        ; DIR1 store: write updated world Y (ix+9, +0Ah) then draw
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#593C: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#593F: DD 6E 09
        add     hl,de                                          ;#5942: 19
        ld      (ix+ENEMY_OFFSET_X),l                          ;#5943: DD 75 09
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5946: DD 74 0A
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5949: C3 32 5A

ENEMY_DIR2_RUN:
        ; DIR2 (down) main: shift back from DIR0/1 paths into common
        rra                                                    ;#594C: 1F
        jr      c,ENEMY_DIR3_RUN                               ;#594D: 38 62
        ld      a,0Ch                                          ;#594F: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#5951: DD 96 04
        jr      z,ENEMY_DIR2_PHASE2                            ;#5954: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#5956: DD 36 04 0C
        ld      e,a                                            ;#595A: 5F
        ld      d,0                                            ;#595B: 16 00
        jr      nc,ENEMY_DIR2_ADD2                             ;#595D: 30 01
        dec     d                                              ;#595F: 15
ENEMY_DIR2_ADD2:
        ; DIR2 add 2: secondary add to (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5960: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5963: DD 6E 09
        add     hl,de                                          ;#5966: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#5967: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#596A: DD 75 09
ENEMY_DIR2_PHASE2:
        ; DIR2 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#596D: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#5971: 3A 45 E0
        and     a                                              ;#5974: A7
        jr      z,ENEMY_DIR2_APPLY                             ;#5975: 28 03
        ld      de,300h                                        ;#5977: 11 00 03
ENEMY_DIR2_APPLY:
        ; DIR2 apply: subtract step from (ix+6..7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#597A: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#597D: DD 6E 06
        and     a                                              ;#5980: A7
        ld      a,h                                            ;#5981: 7C
        sbc     hl,de                                          ;#5982: ED 52
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#5984: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#5987: DD 75 06
        sub     h                                              ;#598A: 94
        neg                                                    ;#598B: ED 44
        ld      e,a                                            ;#598D: 5F
        ld      d,0                                            ;#598E: 16 00
        rla                                                    ;#5990: 17
        jr      nc,ENEMY_DIR2_BORROW_CHECK                     ;#5991: 30 01
        dec     d                                              ;#5993: 15
ENEMY_DIR2_BORROW_CHECK:
        ; DIR2 borrow check: if (ix+7) underflowed, fix +18h and dec (ix+8)
        bit     7,h                                            ;#5994: CB 7C
        jr      z,ENEMY_DIR2_STORE_POS                         ;#5996: 28 09
        ld      a,h                                            ;#5998: 7C
        add     a,18h                                          ;#5999: C6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#599B: DD 77 07
        dec     (ix+ENEMY_OFFSET_CELL_Y)                       ;#599E: DD 35 08
ENEMY_DIR2_STORE_POS:
        ; DIR2 store: write updated world (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#59A1: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#59A4: DD 6E 0B
        add     hl,de                                          ;#59A7: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#59A8: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#59AB: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#59AE: C3 32 5A

ENEMY_DIR3_RUN:
        ; DIR3 (left) main: write velocity to (ix+4) and propagate
        ld      a,0Ch                                          ;#59B1: 3E 0C
        sub     (ix+ENEMY_OFFSET_X_ACCUM_HI)                   ;#59B3: DD 96 04
        jr      z,ENEMY_DIR3_PHASE2                            ;#59B6: 28 17
        ld      (ix+ENEMY_OFFSET_X_ACCUM_HI),0Ch               ;#59B8: DD 36 04 0C
        ld      e,a                                            ;#59BC: 5F
        ld      d,0                                            ;#59BD: 16 00
        jr      nc,ENEMY_DIR3_ADD                              ;#59BF: 30 01
        dec     d                                              ;#59C1: 15
ENEMY_DIR3_ADD:
        ; DIR3 add: adjust position and store (ix+9..0Ah)
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#59C2: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#59C5: DD 6E 09
        add     hl,de                                          ;#59C8: 19
        ld      (ix+ENEMY_OFFSET_X_HI),h                       ;#59C9: DD 74 0A
        ld      (ix+ENEMY_OFFSET_X),l                          ;#59CC: DD 75 09
ENEMY_DIR3_PHASE2:
        ; DIR3 phase 2: load ENEMY_STEP_SPEED and apply player-move gate
        ld      de,(ENEMY_STEP_SPEED)                          ;#59CF: ED 5B 41 E0
        ld      a,(PLAYER_MOVE_GATE)                           ;#59D3: 3A 45 E0
        and     a                                              ;#59D6: A7
        jr      z,ENEMY_DIR3_APPLY                             ;#59D7: 28 03
        ld      de,300h                                        ;#59D9: 11 00 03
ENEMY_DIR3_APPLY:
        ; DIR3 apply: add target step into (ix+6..+7) world Y
        ld      h,(ix+ENEMY_OFFSET_Y_ACCUM_HI)                 ;#59DC: DD 66 07
        ld      l,(ix+ENEMY_OFFSET_Y_ACCUM_LO)                 ;#59DF: DD 6E 06
        ld      a,h                                            ;#59E2: 7C
        add     hl,de                                          ;#59E3: 19
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),h                 ;#59E4: DD 74 07
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_LO),l                 ;#59E7: DD 75 06
        sub     h                                              ;#59EA: 94
        neg                                                    ;#59EB: ED 44
        ld      e,a                                            ;#59ED: 5F
        ld      d,0                                            ;#59EE: 16 00
        rla                                                    ;#59F0: 17
        jr      nc,ENEMY_DIR3_CARRY_CHECK                      ;#59F1: 30 01
        dec     d                                              ;#59F3: 15
ENEMY_DIR3_CARRY_CHECK:
        ; DIR3 carry check: if (ix+7) >= 18h, fix -18h and inc (ix+8)
        ld      a,h                                            ;#59F4: 7C
        cp      18h                                            ;#59F5: FE 18
        jr      c,ENEMY_DIR3_STORE_POS                         ;#59F7: 38 08
        sub     18h                                            ;#59F9: D6 18
        ld      (ix+ENEMY_OFFSET_Y_ACCUM_HI),a                 ;#59FB: DD 77 07
        inc     (ix+ENEMY_OFFSET_CELL_Y)                       ;#59FE: DD 34 08
ENEMY_DIR3_STORE_POS:
        ; DIR3 store: write updated (ix+0Bh, +0Ch) then draw
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5A01: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5A04: DD 6E 0B
        add     hl,de                                          ;#5A07: 19
        ld      (ix+ENEMY_OFFSET_Y),l                          ;#5A08: DD 75 0B
        ld      (ix+ENEMY_OFFSET_Y_HI),h                       ;#5A0B: DD 74 0C
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A0E: C3 32 5A

ENEMY_HIT_PHASE:
        ; Enemy hit state (type=2): tick the bounce-away animation phase
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5A11: DD 7E 01
        dec     a                                              ;#5A14: 3D
        jr      z,ENEMY_HIT_RESET                              ;#5A15: 28 17
        ld      (ix+ENEMY_OFFSET_TIMER),a                      ;#5A17: DD 77 01
        and     1                                              ;#5A1A: E6 01
        jr      nz,DRAW_ENEMY_CAR_SPRITE                       ;#5A1C: 20 14
        ld      a,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A1E: DD 7E 0D
        add     a,4                                            ;#5A21: C6 04
        cp      30h                                            ;#5A23: FE 30
        jr      c,ENEMY_HIT_STORE_ROT                          ;#5A25: 38 01
        xor     a                                              ;#5A27: AF
ENEMY_HIT_STORE_ROT:
        ; Store updated bounce rotation back to (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5A28: DD 77 0D
        jp      DRAW_ENEMY_CAR_SPRITE                          ;#5A2B: C3 32 5A

ENEMY_HIT_RESET:
        ; Bounce finished: re-activate enemy with type=1
        ld      (ix+ENEMY_OFFSET_TYPE),1                       ;#5A2E: DD 36 00 01
DRAW_ENEMY_CAR_SPRITE:
        ; Bounds-check (ix+9..0Ch) entry position, write sprite to SAT_MIRROR
        ; DRAW_ENEMY_CAR_SPRITE validates enemy-car position then writes one sprite to
        ; SAT_MIRROR. Bounds: (ix+0Ah) and (ix+0Ch) must be 0 (high bytes of 16-bit
        ; X/Y), (ix+9) < 0A9h, (ix+0Bh) < 0E0h. Sprite Y = pos-Y - 18h (height offset).
        ld      a,(ix+ENEMY_OFFSET_X_HI)                       ;#5A32: DD 7E 0A
        or      (ix+ENEMY_OFFSET_Y_HI)                         ;#5A35: DD B6 0C
        jp      nz,ENEMY_AI_ADVANCE_IX                         ;#5A38: C2 FF 5A
        ld      a,(ix+ENEMY_OFFSET_X)                          ;#5A3B: DD 7E 09
        cp      0A9h                                           ;#5A3E: FE A9
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A40: D2 FF 5A
        ld      d,a                                            ;#5A43: 57
        ld      a,(ix+ENEMY_OFFSET_Y)                          ;#5A44: DD 7E 0B
        ld      e,a                                            ;#5A47: 5F
        cp      0E0h                                           ;#5A48: FE E0
        jp      nc,ENEMY_AI_ADVANCE_IX                         ;#5A4A: D2 FF 5A
        ld      (ix+ENEMY_OFFSET_STATE),1                      ;#5A4D: DD 36 02 01
        sub     18h                                            ;#5A51: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5A53: 2A 14 E0
        ld      (hl),a                                         ;#5A56: 77
        inc     hl                                             ;#5A57: 23
        ld      (hl),d                                         ;#5A58: 72
        inc     hl                                             ;#5A59: 23
        ld      c,(ix+ENEMY_OFFSET_PATTERN)                    ;#5A5A: DD 4E 0D
        ld      (hl),c                                         ;#5A5D: 71
        inc     hl                                             ;#5A5E: 23
        ld      b,(ix+ENEMY_OFFSET_COLOR)                      ;#5A5F: DD 46 0E
        ld      (hl),b                                         ;#5A62: 70
        inc     hl                                             ;#5A63: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5A64: 22 14 E0
        sub     4Fh                                            ;#5A67: D6 4F
        cp      11h                                            ;#5A69: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A6B: 30 12
        ld      a,d                                            ;#5A6D: 7A
        sub     50h                                            ;#5A6E: D6 50
        cp      11h                                            ;#5A70: FE 11
        jr      nc,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A72: 30 0B
        ld      a,(ENEMY_CAR_ITER_TIMER)                       ;#5A74: 3A 1D E0
        and     a                                              ;#5A77: A7
        jr      nz,DRAW_ENEMY_VS_SMOKE_LOOP                    ;#5A78: 20 05
        ld      a,1                                            ;#5A7A: 3E 01
        ld      (GAME_OVER_FLAG),a                             ;#5A7C: 32 49 E0
DRAW_ENEMY_VS_SMOKE_LOOP:
        ; For each smoke trail entry: check overlap with this enemy car
        ex      de,hl                                          ;#5A7F: EB
        ld      iy,SMOKE_TRAIL_TABLE                           ;#5A80: FD 21 00 E4
        ld      b,9                                            ;#5A84: 06 09
DRAW_ENEMY_SMOKE_INNER:
        ; Inner djnz of DRAW_ENEMY_VS_SMOKE_LOOP
        ld      a,(iy+SMOKE_OFFSET_ACTIVE)                     ;#5A86: FD 7E 00
        and     a                                              ;#5A89: A7
        jr      z,DRAW_ENEMY_SMOKE_NEXT                        ;#5A8A: 28 31
        ld      a,(iy+SMOKE_OFFSET_X)                          ;#5A8C: FD 7E 03
        sub     h                                              ;#5A8F: 94
        add     a,4                                            ;#5A90: C6 04
        cp      9                                              ;#5A92: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5A94: 30 27
        ld      a,(iy+SMOKE_OFFSET_Y)                          ;#5A96: FD 7E 05
        sub     l                                              ;#5A99: 95
        add     a,4                                            ;#5A9A: C6 04
        cp      9                                              ;#5A9C: FE 09
        jr      nc,DRAW_ENEMY_SMOKE_NEXT                       ;#5A9E: 30 1D
        ld      (iy+SMOKE_OFFSET_ACTIVE),0                     ;#5AA0: FD 36 00 00
        ld      (ix+ENEMY_OFFSET_TYPE),2                       ;#5AA4: DD 36 00 02
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5AA8: DD 7E 0F
        add     a,2                                            ;#5AAB: C6 02
        and     3                                              ;#5AAD: E6 03
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5AAF: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5AB2: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5AB6: DD 36 02 03
        jp      ENEMY_AI_TAIL_ADV                              ;#5ABA: C3 14 5B

DRAW_ENEMY_SMOKE_NEXT:
        ; Advance IY to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5ABD: 11 10 00
        add     iy,de                                          ;#5AC0: FD 19
        djnz    DRAW_ENEMY_SMOKE_INNER                         ;#5AC2: 10 C2
        ld      a,(ix+ENEMY_OFFSET_TYPE)                       ;#5AC4: DD 7E 00
        cp      2                                              ;#5AC7: FE 02
        jp      z,ENEMY_AI_TAIL_ADV                            ;#5AC9: CA 14 5B
        ld      a,(FRAME_TICK)                                 ;#5ACC: 3A 07 E0
        rra                                                    ;#5ACF: 1F
        jr      nc,ENEMY_AI_ADVANCE_IX                         ;#5AD0: 30 2D
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5AD2: DD 7E 0F
        and     3                                              ;#5AD5: E6 03
        ld      b,a                                            ;#5AD7: 47
        add     a,a                                            ;#5AD8: 87
        add     a,b                                            ;#5AD9: 80
        add     a,a                                            ;#5ADA: 87
        add     a,a                                            ;#5ADB: 87
        sub     c                                              ;#5ADC: 91
        jr      z,ENEMY_AI_ADVANCE_IX                          ;#5ADD: 28 20
        jr      nc,ENEMY_SMOKE_ROT_TOP                         ;#5ADF: 30 02
        add     a,30h                                          ;#5AE1: C6 30
ENEMY_SMOKE_ROT_TOP:
        ; Compute rotation delta < 18h: pick MINUS or PLUS step
        cp      18h                                            ;#5AE3: FE 18
        jr      c,ENEMY_SMOKE_ROT_PLUS                         ;#5AE5: 38 0D
        ld      a,c                                            ;#5AE7: 79
        sub     4                                              ;#5AE8: D6 04
        jr      nc,ENEMY_SMOKE_ROT_MINUS_STORE                 ;#5AEA: 30 02
        ld      a,2Ch                                          ;#5AEC: 3E 2C
ENEMY_SMOKE_ROT_MINUS_STORE:
        ; Rotate enemy sprite by -4 (mod 30h), clamp at 2Ch
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5AEE: DD 77 0D
        jp      ENEMY_AI_ADVANCE_IX                            ;#5AF1: C3 FF 5A

ENEMY_SMOKE_ROT_PLUS:
        ; Rotate enemy sprite by +4 (mod 30h), wrap to 0
        ld      a,c                                            ;#5AF4: 79
        add     a,4                                            ;#5AF5: C6 04
        cp      30h                                            ;#5AF7: FE 30
        jr      c,ENEMY_SMOKE_ROT_STORE                        ;#5AF9: 38 01
        xor     a                                              ;#5AFB: AF
ENEMY_SMOKE_ROT_STORE:
        ; Store new rotation phase at (ix+0Dh)
        ld      (ix+ENEMY_OFFSET_PATTERN),a                    ;#5AFC: DD 77 0D
ENEMY_AI_ADVANCE_IX:
        ; Advance IX by 10h to next ENEMY_CAR_TABLE entry, return to caller
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5AFF: DD 7E 01
        and     a                                              ;#5B02: A7
        jr      nz,ENEMY_AI_TAIL_ADV                           ;#5B03: 20 0F
        push    ix                                             ;#5B05: DD E5
        pop     iy                                             ;#5B07: FD E1
ENEMY_COLLIDE_LOOP:
        ; Enemy-vs-enemy collision loop: walk subsequent entries via IY
        ld      de,10h                                         ;#5B09: 11 10 00
        add     iy,de                                          ;#5B0C: FD 19
        ld      a,(iy+ENEMY_OFFSET_TYPE)                       ;#5B0E: FD 7E 00
        and     a                                              ;#5B11: A7
        jr      nz,ENEMY_COLLIDE_TEST_Y                        ;#5B12: 20 06
ENEMY_AI_TAIL_ADV:
        ; Common tail: advance IX by 10h and return
        ld      de,10h                                         ;#5B14: 11 10 00
        add     ix,de                                          ;#5B17: DD 19
        ret                                                    ;#5B19: C9

ENEMY_COLLIDE_TEST_Y:
        ; Test Y delta < 0Ch: rejected -> jump back to loop; accepted -> check X
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B1A: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B1D: DD 6E 09
        ld      d,(iy+ENEMY_OFFSET_X_HI)                       ;#5B20: FD 56 0A
        ld      e,(iy+ENEMY_OFFSET_X)                          ;#5B23: FD 5E 09
        and     a                                              ;#5B26: A7
        sbc     hl,de                                          ;#5B27: ED 52
        ld      de,0Ch                                         ;#5B29: 11 0C 00
        add     hl,de                                          ;#5B2C: 19
        ld      a,h                                            ;#5B2D: 7C
        and     a                                              ;#5B2E: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B2F: 20 D8
        ld      a,l                                            ;#5B31: 7D
        cp      19h                                            ;#5B32: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B34: 30 D3
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5B36: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5B39: DD 6E 0B
        ld      d,(iy+ENEMY_OFFSET_Y_HI)                       ;#5B3C: FD 56 0C
        ld      e,(iy+ENEMY_OFFSET_Y)                          ;#5B3F: FD 5E 0B
        and     a                                              ;#5B42: A7
        sbc     hl,de                                          ;#5B43: ED 52
        ld      de,0Ch                                         ;#5B45: 11 0C 00
        add     hl,de                                          ;#5B48: 19
        ld      a,h                                            ;#5B49: 7C
        and     a                                              ;#5B4A: A7
        jr      nz,ENEMY_COLLIDE_LOOP                          ;#5B4B: 20 BC
        ld      a,l                                            ;#5B4D: 7D
        cp      19h                                            ;#5B4E: FE 19
        jr      nc,ENEMY_COLLIDE_LOOP                          ;#5B50: 30 B7
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5B52: DD 7E 0F
        xor     2                                              ;#5B55: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5B57: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5B5A: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5B5E: DD 36 02 03
        ld      a,(iy+ENEMY_OFFSET_DIR)                        ;#5B62: FD 7E 0F
        xor     2                                              ;#5B65: EE 02
        cp      (ix+ENEMY_OFFSET_DIR)                          ;#5B67: DD BE 0F
        jr      z,ENEMY_COLLIDE_STORE_OTHER                    ;#5B6A: 28 03
        ld      (iy+ENEMY_OFFSET_DIR),a                        ;#5B6C: FD 77 0F
ENEMY_COLLIDE_STORE_OTHER:
        ; Both cars collided: also set bounce-away flags on the other car
        ld      (iy+ENEMY_OFFSET_TIMER),78h                    ;#5B6F: FD 36 01 78
        ld      (iy+ENEMY_OFFSET_STATE),3                      ;#5B73: FD 36 02 03
        jp      ENEMY_COLLIDE_LOOP                             ;#5B77: C3 09 5B

CHECK_ENEMY_HITS_ROCK:
        ; AABB check (|dx|,|dy| < 0Ch) between IX (ENEMY_CAR_TABLE) and IY (ROCK_TABLE)
        ; CHECK_ENEMY_HITS_ROCK does an AABB check between the current enemy car (IX =
        ; ENEMY_CAR_TABLE entry) and every ROCK_TABLE entry (IY). |dx| < 0Ch AND |dy| <
        ; 0Ch ⇒ hit; on hit, XOR bit 1 of (ix+0Fh) — a flag the enemy uses to reverse
        ; direction on its next AI tick.
        ld      a,(ix+ENEMY_OFFSET_TIMER)                      ;#5B7A: DD 7E 01
        and     a                                              ;#5B7D: A7
        ret     nz                                             ;#5B7E: C0
        ld      a,(ROCK_SPAWN_COUNT)                           ;#5B7F: 3A 1C E0
        and     a                                              ;#5B82: A7
        ret     z                                              ;#5B83: C8
        ld      b,a                                            ;#5B84: 47
        ld      iy,ROCK_TABLE                                  ;#5B85: FD 21 00 E2
CHECK_ROCK_LOOP_TOP:
        ; Outer djnz of CHECK_ENEMY_HITS_ROCK
        ld      h,(ix+ENEMY_OFFSET_X_HI)                       ;#5B89: DD 66 0A
        ld      l,(ix+ENEMY_OFFSET_X)                          ;#5B8C: DD 6E 09
        ld      d,(iy+ROCK_OFFSET_X_HI)                        ;#5B8F: FD 56 04
        ld      e,(iy+ROCK_OFFSET_X)                           ;#5B92: FD 5E 03
        and     a                                              ;#5B95: A7
        sbc     hl,de                                          ;#5B96: ED 52
        ld      de,0Ch                                         ;#5B98: 11 0C 00
        add     hl,de                                          ;#5B9B: 19
        ld      a,h                                            ;#5B9C: 7C
        and     a                                              ;#5B9D: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5B9E: 20 32
        ld      a,l                                            ;#5BA0: 7D
        cp      19h                                            ;#5BA1: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BA3: 30 2D
        ld      h,(ix+ENEMY_OFFSET_Y_HI)                       ;#5BA5: DD 66 0C
        ld      l,(ix+ENEMY_OFFSET_Y)                          ;#5BA8: DD 6E 0B
        ld      d,(iy+ROCK_OFFSET_Y_HI)                        ;#5BAB: FD 56 06
        ld      e,(iy+ROCK_OFFSET_Y)                           ;#5BAE: FD 5E 05
        and     a                                              ;#5BB1: A7
        sbc     hl,de                                          ;#5BB2: ED 52
        ld      de,0Ch                                         ;#5BB4: 11 0C 00
        add     hl,de                                          ;#5BB7: 19
        ld      a,h                                            ;#5BB8: 7C
        and     a                                              ;#5BB9: A7
        jr      nz,CHECK_ROCK_NEXT                             ;#5BBA: 20 16
        ld      a,l                                            ;#5BBC: 7D
        cp      19h                                            ;#5BBD: FE 19
        jr      nc,CHECK_ROCK_NEXT                             ;#5BBF: 30 11
        ld      a,(ix+ENEMY_OFFSET_DIR)                        ;#5BC1: DD 7E 0F
        xor     2                                              ;#5BC4: EE 02
        ld      (ix+ENEMY_OFFSET_DIR),a                        ;#5BC6: DD 77 0F
        ld      (ix+ENEMY_OFFSET_TIMER),78h                    ;#5BC9: DD 36 01 78
        ld      (ix+ENEMY_OFFSET_STATE),3                      ;#5BCD: DD 36 02 03
        ret                                                    ;#5BD1: C9

CHECK_ROCK_NEXT:
        ; Skip-this-rock: advance IY by 10h, djnz back to outer loop
        ld      de,10h                                         ;#5BD2: 11 10 00
        add     iy,de                                          ;#5BD5: FD 19
        djnz    CHECK_ROCK_LOOP_TOP                            ;#5BD7: 10 B0
        ret                                                    ;#5BD9: C9

APPLY_DIRECTION_TO_POS:
        ; Adjust H/L by direction A then call LOOKUP_PLAYFIELD_CELL
        ; APPLY_DIRECTION_TO_POS reads (ix+5, ix+8) as a 16-bit (H, L) position, adjusts
        ; by direction code in A: 0 = H-1 (up), 1 = H+1 (down), 2 = L-1 (left), 3 = L+1
        ; (right). Then calls LOOKUP_PLAYFIELD_CELL to fetch the cell at the new coord.
        ; Used by enemy and player movement code to "look ahead" before committing a
        ; move.
        ld      c,a                                            ;#5BDA: 4F
        ld      h,(ix+ENEMY_OFFSET_CELL_X)                     ;#5BDB: DD 66 05
        ld      l,(ix+ENEMY_OFFSET_CELL_Y)                     ;#5BDE: DD 6E 08
        rra                                                    ;#5BE1: 1F
        jr      nc,APPLY_DIR_HORIZ                             ;#5BE2: 30 0B
        rra                                                    ;#5BE4: 1F
        jr      nc,APPLY_DIR_INC_H                             ;#5BE5: 30 04
        dec     h                                              ;#5BE7: 25
        jp      APPLY_DIR_LOOKUP                               ;#5BE8: C3 F7 5B

APPLY_DIR_INC_H:
        ; APPLY_DIR direction 1 (down): inc H, then lookup
        inc     h                                              ;#5BEB: 24
        jp      APPLY_DIR_LOOKUP                               ;#5BEC: C3 F7 5B

APPLY_DIR_HORIZ:
        ; APPLY_DIR horizontal (dir 2/3): switch on dir bit
        rra                                                    ;#5BEF: 1F
        jr      c,APPLY_DIR_INC_L                              ;#5BF0: 38 04
        dec     l                                              ;#5BF2: 2D
        jp      APPLY_DIR_LOOKUP                               ;#5BF3: C3 F7 5B

APPLY_DIR_INC_L:
        ; APPLY_DIR direction 3 (right): inc L, then lookup
        inc     l                                              ;#5BF6: 2C
APPLY_DIR_LOOKUP:
        ; Common lookup: call LOOKUP_PLAYFIELD_CELL with adjusted (H, L)
        call    LOOKUP_PLAYFIELD_CELL                          ;#5BF7: CD 7C 4B
        ld      a,c                                            ;#5BFA: 79
        ret                                                    ;#5BFB: C9

UPDATE_SMOKE_STATE:
        ; Per-frame smoke-state update; gated by SMOKE_COOLDOWN and PLAYER_VELOCITY_X
        ; UPDATE_SMOKE_STATE runs once per frame. No-op if SMOKE_COOLDOWN is zero.
        ; Otherwise reads PLAYER_VELOCITY_X for direction bits, then iterates
        ; SMOKE_TRAIL_TABLE; for each entry not too close to the player
        ; (PLAYER_VELOCITY_Y in safe range), updates state. Tail-falls into SPAWN_SMOKE
        ; which allocates the next smoke trail puff.
        ld      a,(SMOKE_COOLDOWN)                             ;#5BFC: 3A 27 E0
        and     a                                              ;#5BFF: A7
        ret     z                                              ;#5C00: C8
        ld      a,(PLAYER_VELOCITY_X)                          ;#5C01: 3A 09 E0
        and     a                                              ;#5C04: A7
        jp      p,SMOKE_DIR_ABS                                ;#5C05: F2 0A 5C
        neg                                                    ;#5C08: ED 44
SMOKE_DIR_ABS:
        ; Take |PLAYER_VELOCITY_X| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C0A: D6 0A
        cp      5                                              ;#5C0C: FE 05
        ret     nc                                             ;#5C0E: D0
        ld      a,(PLAYER_VELOCITY_Y)                          ;#5C0F: 3A 0B E0
        and     a                                              ;#5C12: A7
        jp      p,SMOKE_VEL_ABS                                ;#5C13: F2 18 5C
        neg                                                    ;#5C16: ED 44
SMOKE_VEL_ABS:
        ; Take |PLAYER_VELOCITY_Y| - 0Ah, must be < 5 to allow smoke
        sub     0Ah                                            ;#5C18: D6 0A
        cp      5                                              ;#5C1A: FE 05
        ret     nc                                             ;#5C1C: D0
        ld      a,(PLAYER_SCREEN_X)                            ;#5C1D: 3A 23 E0
        ld      d,a                                            ;#5C20: 57
        ld      a,(PLAYER_SCREEN_Y)                            ;#5C21: 3A 24 E0
        ld      e,a                                            ;#5C24: 5F
        ; SPAWN_SMOKE (inside UPDATE_SMOKE_STATE's tail). Allocates the next
        ; SMOKE_TRAIL_TABLE entry: advance SMOKE_TRAIL_WRITE_PTR by 0x10, wrap
        ; SMOKE_TRAIL_WRITE_INDEX modulo 9. Initialize: active=1, pos=(D,E), tile=58h,
        ; attr=0, life=6Fh, etc. Decrement SMOKE_COOLDOWN and trigger SFX_TRIGGER_SMOKE
        ; (=1) for the deploy sound.
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C25: 21 00 E4
        ld      b,9                                            ;#5C28: 06 09
SMOKE_SCAN_LOOP_TOP:
        ; Inner djnz of SPAWN_SMOKE (scan SMOKE_TRAIL_TABLE)
        ld      a,(hl)                                         ;#5C2A: 7E
        and     a                                              ;#5C2B: A7
        jr      z,SMOKE_SPAWN_NEXT                             ;#5C2C: 28 12
        inc     hl                                             ;#5C2E: 23
        inc     hl                                             ;#5C2F: 23
        inc     hl                                             ;#5C30: 23
        ld      a,(hl)                                         ;#5C31: 7E
        sub     50h                                            ;#5C32: D6 50
        cp      10h                                            ;#5C34: FE 10
        jr      nc,SMOKE_SPAWN_NEXT                            ;#5C36: 30 08
        inc     hl                                             ;#5C38: 23
        inc     hl                                             ;#5C39: 23
        ld      a,(hl)                                         ;#5C3A: 7E
        sub     67h                                            ;#5C3B: D6 67
        cp      10h                                            ;#5C3D: FE 10
        ret     c                                              ;#5C3F: D8
SMOKE_SPAWN_NEXT:
        ; Try next smoke slot if current entry too close to player
        ld      a,l                                            ;#5C40: 7D
        and     0F0h                                           ;#5C41: E6 F0
        add     a,10h                                          ;#5C43: C6 10
        ld      l,a                                            ;#5C45: 6F
        djnz    SMOKE_SCAN_LOOP_TOP                            ;#5C46: 10 E2
        ld      hl,(SMOKE_TRAIL_WRITE_PTR)                     ;#5C48: 2A 28 E0
        ld      bc,10h                                         ;#5C4B: 01 10 00
        add     hl,bc                                          ;#5C4E: 09
        ld      a,(SMOKE_TRAIL_WRITE_INDEX)                    ;#5C4F: 3A 2A E0
        inc     a                                              ;#5C52: 3C
        cp      9                                              ;#5C53: FE 09
        jr      nz,SMOKE_ALLOC_ENTRY                           ;#5C55: 20 04
        xor     a                                              ;#5C57: AF
        ld      hl,SMOKE_TRAIL_TABLE                           ;#5C58: 21 00 E4
SMOKE_ALLOC_ENTRY:
        ; Init new smoke entry: active=1, pos=(D,E), tile=58h, life=6Fh
        ld      (SMOKE_TRAIL_WRITE_PTR),hl                     ;#5C5B: 22 28 E0
        ld      (SMOKE_TRAIL_WRITE_INDEX),a                    ;#5C5E: 32 2A E0
        ld      (hl),1                                         ;#5C61: 36 01
        inc     hl                                             ;#5C63: 23
        ld      (hl),d                                         ;#5C64: 72
        inc     hl                                             ;#5C65: 23
        ld      (hl),e                                         ;#5C66: 73
        inc     hl                                             ;#5C67: 23
        ld      (hl),58h                                       ;#5C68: 36 58
        inc     hl                                             ;#5C6A: 23
        ld      (hl),0                                         ;#5C6B: 36 00
        inc     hl                                             ;#5C6D: 23
        ld      (hl),6Fh                                       ;#5C6E: 36 6F
        inc     hl                                             ;#5C70: 23
        ld      (hl),0                                         ;#5C71: 36 00
        ld      hl,SMOKE_COOLDOWN                              ;#5C73: 21 27 E0
        dec     (hl)                                           ;#5C76: 35
        ld      a,1                                            ;#5C77: 3E 01
        ld      (SFX_TRIGGER_SMOKE),a                          ;#5C79: 32 50 E5
        ret                                                    ;#5C7C: C9

SCROLL_SMOKE_TRAILS:
        ; Iterate SMOKE_TRAIL_TABLE (9 entries x 16 bytes): world-scroll + draw
        ; SCROLL_SMOKE_TRAILS iterates the 9-entry SMOKE_TRAIL_TABLE. Active entries
        ; have their X/Y advanced by WORLD_SCROLL_DX/DY. When the position goes off-
        ; screen (X >= 0A9h or Y >= 0E0h), the entry is deactivated. In-bounds entries
        ; are drawn as smoke sprites at the SAT_MIRROR cursor (tile 40h, color 0Fh =
        ; white smoke).
        ld      ix,SMOKE_TRAIL_TABLE                           ;#5C7D: DD 21 00 E4
        ld      b,9                                            ;#5C81: 06 09
SCROLL_SMOKE_LOOP_TOP:
        ; Outer djnz of SCROLL_SMOKE_TRAILS
        ld      a,(ix+SMOKE_OFFSET_ACTIVE)                     ;#5C83: DD 7E 00
        and     a                                              ;#5C86: A7
        jr      z,SMOKE_ADVANCE_IX                             ;#5C87: 28 53
        ld      a,(WORLD_SCROLL_DX)                            ;#5C89: 3A 16 E0
        ld      e,a                                            ;#5C8C: 5F
        ld      d,0                                            ;#5C8D: 16 00
        rla                                                    ;#5C8F: 17
        jr      nc,SMOKE_APPLY_DX                              ;#5C90: 30 01
        dec     d                                              ;#5C92: 15
SMOKE_APPLY_DX:
        ; Apply WORLD_SCROLL_DX (sign-extended) to smoke entry X
        ld      l,(ix+SMOKE_OFFSET_X)                          ;#5C93: DD 6E 03
        ld      h,(ix+SMOKE_OFFSET_X_HI)                       ;#5C96: DD 66 04
        add     hl,de                                          ;#5C99: 19
        ld      (ix+SMOKE_OFFSET_X_HI),h                       ;#5C9A: DD 74 04
        ld      (ix+SMOKE_OFFSET_X),l                          ;#5C9D: DD 75 03
        ld      a,h                                            ;#5CA0: 7C
        and     a                                              ;#5CA1: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CA2: 20 40
        ld      a,l                                            ;#5CA4: 7D
        cp      0A9h                                           ;#5CA5: FE A9
        jr      nc,SMOKE_DEACTIVATE                            ;#5CA7: 30 3B
        ld      c,l                                            ;#5CA9: 4D
        ld      a,(WORLD_SCROLL_DY)                            ;#5CAA: 3A 17 E0
        ld      e,a                                            ;#5CAD: 5F
        ld      d,0                                            ;#5CAE: 16 00
        rla                                                    ;#5CB0: 17
        jr      nc,SMOKE_APPLY_DY                              ;#5CB1: 30 01
        dec     d                                              ;#5CB3: 15
SMOKE_APPLY_DY:
        ; Apply WORLD_SCROLL_DY (sign-extended) to smoke entry Y
        ld      l,(ix+SMOKE_OFFSET_Y)                          ;#5CB4: DD 6E 05
        ld      h,(ix+SMOKE_OFFSET_Y_HI)                       ;#5CB7: DD 66 06
        add     hl,de                                          ;#5CBA: 19
        ld      (ix+SMOKE_OFFSET_Y),l                          ;#5CBB: DD 75 05
        ld      (ix+SMOKE_OFFSET_Y_HI),h                       ;#5CBE: DD 74 06
        ld      a,h                                            ;#5CC1: 7C
        and     a                                              ;#5CC2: A7
        jr      nz,SMOKE_DEACTIVATE                            ;#5CC3: 20 1F
        ld      a,l                                            ;#5CC5: 7D
        cp      0E0h                                           ;#5CC6: FE E0
        jr      nc,SMOKE_DEACTIVATE                            ;#5CC8: 30 1A
        sub     18h                                            ;#5CCA: D6 18
        ld      hl,(SAT_MIRROR_CURSOR)                         ;#5CCC: 2A 14 E0
        ; emit one SMOKE_TRAIL_TABLE object sprite
        ld      (hl),a                                         ;#5CCF: 77
        inc     hl                                             ;#5CD0: 23
        ld      (hl),c                                         ;#5CD1: 71
        inc     hl                                             ;#5CD2: 23
        ld      (hl),40h                                       ;#5CD3: 36 40
        inc     hl                                             ;#5CD5: 23
        ld      (hl),0Fh                                       ;#5CD6: 36 0F
        inc     hl                                             ;#5CD8: 23
        ld      (SAT_MIRROR_CURSOR),hl                         ;#5CD9: 22 14 E0
SMOKE_ADVANCE_IX:
        ; Advance IX by 10h to next SMOKE_TRAIL_TABLE entry, djnz back
        ld      de,10h                                         ;#5CDC: 11 10 00
        add     ix,de                                          ;#5CDF: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CE1: 10 A0
        ret                                                    ;#5CE3: C9

SMOKE_DEACTIVATE:
        ; Off-screen / hit smoke: zero entry, advance IX, djnz back
        ld      (ix+SMOKE_OFFSET_ACTIVE),0                     ;#5CE4: DD 36 00 00
        ld      de,10h                                         ;#5CE8: 11 10 00
        add     ix,de                                          ;#5CEB: DD 19
        djnz    SCROLL_SMOKE_LOOP_TOP                          ;#5CED: 10 94
        ret                                                    ;#5CEF: C9

SPRITE_CAR:
        ; Player car sprite (16x16); stored pre-transpose, see TRANSPOSE_TILE_BLOCKS
        dh      "0103777F7703030206EEEEFEEFE70202"             ;#5CF0: 01 03 77 7F 77 03 03 02 06 EE EE FE EF E7 02 02
        dh      "80C0EEFEEEC0C0406077777FF7E74040"             ;#5D00: 80 C0 EE FE EE C0 C0 40 60 77 77 7F F7 E7 40 40

SPRITE_CAR_ROTATED_30:
        ; Player car rotated 30 degrees (pre-transpose)
        dh      "060E0F0C007173F2FEFC181C1F171404"             ;#5D10: 06 0E 0F 0C 00 71 73 F2 FE FC 18 1C 1F 17 14 04
        dh      "0070F8F8FFFFFF662060C0F8F8F87070"             ;#5D20: 00 70 F8 F8 FF FF FF 66 20 60 C0 F8 F8 F8 70 70

SPRITE_CAR_ROTATED_45:
        ; Player car rotated 45 degrees (pre-transpose)
        dh      "00000038F8FBFE3C3031FB1F7F030303"             ;#5D30: 00 00 00 38 F8 FB FE 3C 30 31 FB 1F 7F 03 03 03
        dh      "70F0F07C7EFEFE7C64C70F0EE0E0E080"             ;#5D40: 70 F0 F0 7C 7E FE FE 7C 64 C7 0F 0E E0 E0 E0 80

SPRITE_FLAG:
        ; Checkpoint flag sprite (16x16); base of the 3180h sprite upload
        dh      "00000000000000000000010100000000"             ;#5D50: 00 00 00 00 00 00 00 00 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5D60: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_L_FLAG:
        ; 'L' flag sprite
        dh      "006060606060607E0000010100000000"             ;#5D70: 00 60 60 60 60 60 60 7E 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5D80: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_S_FLAG:
        ; Special 'S' flag sprite (doubles bonus values)
        dh      "003C66603C06663C0000010100000000"             ;#5D90: 00 3C 66 60 3C 06 66 3C 00 00 01 01 00 00 00 00
        dh      "0080E0F8FEF8E0808080C0C000000000"             ;#5DA0: 00 80 E0 F8 FE F8 E0 80 80 80 C0 C0 00 00 00 00

SPRITE_ROCK:
        ; Rock obstacle sprite
        dh      "00104161033337071F3F3F7F7F7F3F0F"             ;#5DB0: 00 10 41 61 03 33 37 07 1F 3F 3F 7F 7F 7F 3F 0F
        dh      "00E0F0F8FCFCFCFCFEFEFEFFFFFFFFC6"             ;#5DC0: 00 E0 F0 F8 FC FC FC FC FE FE FE FF FF FF FF C6

SPRITE_SMOKE:
        ; Smoke-screen sprite
        dh      "00193F3F7F7F7F7F3F7F7F3F3F1F0E00"             ;#5DD0: 00 19 3F 3F 7F 7F 7F 7F 3F 7F 7F 3F 3F 1F 0E 00
        dh      "0014BEFFFEFEFCFCFEFFFFFFFEBC1800"             ;#5DE0: 00 14 BE FF FE FE FC FC FE FF FF FF FE BC 18 00

SPRITE_BANG:
        ; Crash 'BANG' explosion sprite
        dh      "9945B310C6A9A9CFA9A9C900B7654D99"             ;#5DF0: 99 45 B3 10 C6 A9 A9 CF A9 A9 C9 00 B7 65 4D 99
        dh      "275C91005354747575555700B5565249"             ;#5E00: 27 5C 91 00 53 54 74 75 75 55 57 00 B5 56 52 49

SPRITE_BONUS_100:
        ; Bonus 100 score popup sprite
        dh      "00113212121212390000000000000000"             ;#5E10: 00 11 32 12 12 12 12 39 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5E20: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_100X2:
        ; Bonus 100 doubled (special-flag) popup sprite
        dh      "00113212121212390000110A040A1100"             ;#5E30: 00 11 32 12 12 12 12 39 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5E40: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_200:
        ; Bonus 200 score popup sprite
        dh      "00718A8A122242F90000000000000000"             ;#5E50: 00 71 8A 8A 12 22 42 F9 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5E60: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_200X2:
        ; Bonus 200 doubled (special-flag) popup sprite
        dh      "00718A8A122242F90000110A040A1100"             ;#5E70: 00 71 8A 8A 12 22 42 F9 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5E80: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_300:
        ; Bonus 300 score popup sprite
        dh      "00718A0A320A8A710000000000000000"             ;#5E90: 00 71 8A 0A 32 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5EA0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_300X2:
        ; Bonus 300 doubled (special-flag) popup sprite
        dh      "00718A0A320A8A710000110A040A1100"             ;#5EB0: 00 71 8A 0A 32 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5EC0: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_400:
        ; Bonus 400 score popup sprite
        dh      "0011325292FA12110000000000000000"             ;#5ED0: 00 11 32 52 92 FA 12 11 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5EE0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_400X2:
        ; Bonus 400 doubled (special-flag) popup sprite
        dh      "0011325292FA12110000110A040A1100"             ;#5EF0: 00 11 32 52 92 FA 12 11 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F00: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_500:
        ; Bonus 500 score popup sprite
        dh      "00F982F20A0A8A710000000000000000"             ;#5F10: 00 F9 82 F2 0A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5F20: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_500X2:
        ; Bonus 500 doubled (special-flag) popup sprite
        dh      "00F982F20A0A8A710000110A040A1100"             ;#5F30: 00 F9 82 F2 0A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F40: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_600:
        ; Bonus 600 score popup sprite
        dh      "00718A82F28A8A710000000000000000"             ;#5F50: 00 71 8A 82 F2 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5F60: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_600X2:
        ; Bonus 600 doubled (special-flag) popup sprite
        dh      "00718A82F28A8A710000110A040A1100"             ;#5F70: 00 71 8A 82 F2 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5F80: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_700:
        ; Bonus 700 score popup sprite
        dh      "00F90A0A122222210000000000000000"             ;#5F90: 00 F9 0A 0A 12 22 22 21 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5FA0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_700X2:
        ; Bonus 700 doubled (special-flag) popup sprite
        dh      "00F90A0A122222210000110A040A1100"             ;#5FB0: 00 F9 0A 0A 12 22 22 21 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#5FC0: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_800:
        ; Bonus 800 score popup sprite
        dh      "00718A8A728A8A710000000000000000"             ;#5FD0: 00 71 8A 8A 72 8A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#5FE0: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_800X2:
        ; Bonus 800 doubled (special-flag) popup sprite
        dh      "00718A8A728A8A710000110A040A1100"             ;#5FF0: 00 71 8A 8A 72 8A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#6000: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_900:
        ; Bonus 900 score popup sprite
        dh      "00718A8A7A0A8A710000000000000000"             ;#6010: 00 71 8A 8A 7A 0A 8A 71 00 00 00 00 00 00 00 00
        dh      "008C52525252528C0000000000000000"             ;#6020: 00 8C 52 52 52 52 52 8C 00 00 00 00 00 00 00 00

SPRITE_BONUS_900X2:
        ; Bonus 900 doubled (special-flag) popup sprite
        dh      "00718A8A7A0A8A710000110A040A1100"             ;#6030: 00 71 8A 8A 7A 0A 8A 71 00 00 11 0A 04 0A 11 00
        dh      "008C52525252528C003844440810207C"             ;#6040: 00 8C 52 52 52 52 52 8C 00 38 44 44 08 10 20 7C

SPRITE_BONUS_1000:
        ; Bonus 1000 score popup sprite
        dh      "0098A5A5A5A5A5980000000000000000"             ;#6050: 00 98 A5 A5 A5 A5 A5 98 00 00 00 00 00 00 00 00
        dh      "00C62929292929C60000000000000000"             ;#6060: 00 C6 29 29 29 29 29 C6 00 00 00 00 00 00 00 00

SPRITE_BONUS_1000X2:
        ; Bonus 1000 doubled (special-flag) popup sprite
        dh      "0098A5A5A5A5A5980000110A040A1100"             ;#6070: 00 98 A5 A5 A5 A5 A5 98 00 00 11 0A 04 0A 11 00
        dh      "00C62929292929C6003844440810207C"             ;#6080: 00 C6 29 29 29 29 29 C6 00 38 44 44 08 10 20 7C

SPRITE_GAMEOVER_LEFT:
        ; GAME OVER text, left half
        dh      "1F30606763331F003E63636363633E00"             ;#6090: 1F 30 60 67 63 33 1F 00 3E 63 63 63 63 63 3E 00
        dh      "1C3663637F636300636363773E1C0800"             ;#60A0: 1C 36 63 63 7F 63 63 00 63 63 63 77 3E 1C 08 00

SPRITE_GAMEOVER_RIGHT:
        ; GAME OVER text, right half
        dh      "63777F7F6B6363003F30303E30303F00"             ;#60B0: 63 77 7F 7F 6B 63 63 00 3F 30 30 3E 30 30 3F 00
        dh      "3F30303E30303F007E6363677C6E6700"             ;#60C0: 3F 30 30 3E 30 30 3F 00 7E 63 63 67 7C 6E 67 00

TILE_PATTERN_HEX_DIGITS:
        ; Hex digit font 0-F (16x 8x8); base of the boot pattern-table upload
        dh      "1C26636363321C000C1C0C0C0C0C3F00"             ;#60D0: 1C 26 63 63 63 32 1C 00 0C 1C 0C 0C 0C 0C 3F 00
        dh      "3E63071E3C707F003F060C1703633E00"             ;#60E0: 3E 63 07 1E 3C 70 7F 00 3F 06 0C 17 03 63 3E 00
        dh      "0E1E36667F0606007E607E0303633E00"             ;#60F0: 0E 1E 36 66 7F 06 06 00 7E 60 7E 03 03 63 3E 00
        dh      "1E30607E63633E007F62060C18181800"             ;#6100: 1E 30 60 7E 63 63 3E 00 7F 62 06 0C 18 18 18 00
        dh      "3C62723C4F433E003E63633F03063C00"             ;#6110: 3C 62 72 3C 4F 43 3E 00 3E 63 63 3F 03 06 3C 00
        dh      "1C3663637F6363007E63637E63637E00"             ;#6120: 1C 36 63 63 7F 63 63 00 7E 63 63 7E 63 63 7E 00
        dh      "1E33606060331E007C66636363667C00"             ;#6130: 1E 33 60 60 60 33 1E 00 7C 66 63 63 63 66 7C 00
        dh      "3F30303E30303F007F60607E60606000"             ;#6140: 3F 30 30 3E 30 30 3F 00 7F 60 60 7E 60 60 60 00

TILE_PATTERN_NAMCOT_LOGO:
        ; Namcot publisher logo, 8x 8x8 tiles
        dh      "7F7F60606060606087C7C0C7CFCCCFC7"             ;#6150: 7F 7F 60 60 60 60 60 60 87 C7 C0 C7 CF CC CF C7
        dh      "F1F939F9F939F9F9FFFF999999999999"             ;#6160: F1 F9 39 F9 F9 39 F9 F9 FF FF 99 99 99 99 99 99
        dh      "0F9F989898989F8FE3E706060606E7E3"             ;#6170: 0F 9F 98 98 98 98 9F 8F E3 E7 06 06 06 06 E7 E3
        dh      "F8FC0C0C0C0CFCF8FFFF181818181818"             ;#6180: F8 FC 0C 0C 0C 0C FC F8 FF FF 18 18 18 18 18 18

TILE_PATTERN_CHAR_FONT:
        ; Uppercase font tiles: A-Z © . − (32x 8x8); LDIR'd 3x to FLAG_TABLE (E100-E3FF)
        dh      "00000000000000001C3663637F636300"             ;#6190: 00 00 00 00 00 00 00 00 1C 36 63 63 7F 63 63 00
        dh      "7E63637E63637E001E33606060331E00"             ;#61A0: 7E 63 63 7E 63 63 7E 00 1E 33 60 60 60 33 1E 00
        dh      "7C66636363667C003F30303E30303F00"             ;#61B0: 7C 66 63 63 63 66 7C 00 3F 30 30 3E 30 30 3F 00
        dh      "7F60607E606060001F30606763331F00"             ;#61C0: 7F 60 60 7E 60 60 60 00 1F 30 60 67 63 33 1F 00
        dh      "6363637F636363003F0C0C0C0C0C3F00"             ;#61D0: 63 63 63 7F 63 63 63 00 3F 0C 0C 0C 0C 0C 3F 00
        dh      "0303030303633E0063666C787C6E6700"             ;#61E0: 03 03 03 03 03 63 3E 00 63 66 6C 78 7C 6E 67 00
        dh      "3030303030303F0063777F7F6B636300"             ;#61F0: 30 30 30 30 30 30 3F 00 63 77 7F 7F 6B 63 63 00
        dh      "63737B7F6F6763003E63636363633E00"             ;#6200: 63 73 7B 7F 6F 67 63 00 3E 63 63 63 63 63 3E 00
        dh      "7E6363637E6060003E6363636F663D00"             ;#6210: 7E 63 63 63 7E 60 60 00 3E 63 63 63 6F 66 3D 00
        dh      "7E6363677C6E67003C66603E03633E00"             ;#6220: 7E 63 63 67 7C 6E 67 00 3C 66 60 3E 03 63 3E 00
        dh      "3F0C0C0C0C0C0C006363636363633E00"             ;#6230: 3F 0C 0C 0C 0C 0C 0C 00 63 63 63 63 63 63 3E 00
        dh      "636363773E1C080063636B7F7F776300"             ;#6240: 63 63 63 77 3E 1C 08 00 63 63 6B 7F 7F 77 63 00
        dh      "63773E1C3E7763003333331E0C0C0C00"             ;#6250: 63 77 3E 1C 3E 77 63 00 33 33 33 1E 0C 0C 0C 00
        dh      "7F070E1C38707F003C4299A1A199423C"             ;#6260: 7F 07 0E 1C 38 70 7F 00 3C 42 99 A1 A1 99 42 3C
        dh      "00000000000000000000000000181800"             ;#6270: 00 00 00 00 00 00 00 00 00 00 00 00 00 18 18 00
        dh      "00000000000000000000007E00000000"             ;#6280: 00 00 00 00 00 00 00 00 00 00 00 7E 00 00 00 00

PATTERN_RALLYX_LOGO:
        ; Rally-X logo char patterns (88x 8x8, chars 80h+); LDIRVM'd to VRAM 0C00h/1C00h
        dh      "3F6040C080808080FF00000000000000"             ;#6290: 3F 60 40 C0 80 80 80 80 FF 00 00 00 00 00 00 00
        dh      "FF0100000000000000C0406020301018"             ;#62A0: FF 01 00 00 00 00 00 00 00 C0 40 60 20 30 10 18
        dh      "00000000000000000F1830206040C080"             ;#62B0: 00 00 00 00 00 00 00 00 0F 18 30 20 60 40 C0 80
        dh      "C0701018080C04060001010302020202"             ;#62C0: C0 70 10 18 08 0C 04 06 00 01 01 03 02 02 02 02
        dh      "80808080808080801E1F1E0000000000"             ;#62D0: 80 80 80 80 80 80 80 80 1E 1F 1E 00 00 00 00 00
        dh      "1C1C1E1F1F1F3F7F01010302028684C4"             ;#62E0: 1C 1C 1E 1F 1F 1F 3F 7F 01 01 03 02 02 86 84 C4
        dh      "820707070F0F1F000303030181818000"             ;#62F0: 82 07 07 07 0F 0F 1F 00 03 03 03 01 81 81 80 00
        dh      "020282C2C2E2F2F2000000081C1C1C1C"             ;#6300: 02 02 82 C2 C2 E2 F2 F2 00 00 00 08 1C 1C 1C 1C
        dh      "0301000000000000FFFF7F3F3F3F3F3F"             ;#6310: 03 01 00 00 00 00 00 00 FF FF 7F 3F 3F 3F 3F 3F
        dh      "CCE8F8F0F0E0E0C0FA7A7E7E7E7E3E3E"             ;#6320: CC E8 F8 F0 F0 E0 E0 C0 FA 7A 7E 7E 7E 7E 3E 3E
        dh      "1C1C1C1C1C1C1C1C3F3F3F3F3F3E3E3E"             ;#6330: 1C 1C 1C 1C 1C 1C 1C 1C 3F 3F 3F 3F 3F 3E 3E 3E
        dh      "C0808000000000003E3E1E1E1E1E0E0E"             ;#6340: C0 80 80 00 00 00 00 00 3E 3E 1E 1E 1E 1E 0E 0E
        dh      "8080808080C040601C1C1C1C1C1C1C3E"             ;#6350: 80 80 80 80 80 C0 40 60 1C 1C 1C 1C 1C 1C 1C 3E
        dh      "3C3C38383838387C0E0E0E0707070F1F"             ;#6360: 3C 3C 38 38 38 38 38 7C 0E 0E 0E 07 07 07 0F 1F
        dh      "3F3F1F1F0F070301FFFFFFFFFFFFFFFF"             ;#6370: 3F 3F 1F 1F 0F 07 03 01 FF FF FF FF FF FF FF FF
        dh      "FFFF7F3F1F000000FFFFFFFFFF000000"             ;#6380: FF FF 7F 3F 1F 00 00 00 FF FF FF FF FF 00 00 00
        dh      "FF80000000000000C06030180C0C0E0F"             ;#6390: FF 80 00 00 00 00 00 00 C0 60 30 18 0C 0C 0E 0F
        dh      "F018080C060203031F30303038181C0C"             ;#63A0: F0 18 08 0C 06 02 03 03 1F 30 30 30 38 18 1C 0C
        dh      "F80C0603010000000000000080C04161"             ;#63B0: F8 0C 06 03 01 00 00 00 00 00 00 00 80 C0 41 61
        dh      "0F0F0F0F0F0703000080C0C0E0E0F010"             ;#63C0: 0F 0F 0F 0F 0F 07 03 00 00 80 C0 C0 E0 E0 F0 10
        dh      "03030303030100008E87C7C3E1F1F808"             ;#63D0: 03 03 03 03 03 01 00 00 8E 87 C7 C3 E1 F1 F8 08
        dh      "00000080C0C0E0F033121E0C00000000"             ;#63E0: 00 00 00 80 C0 C0 E0 F0 33 12 1E 0C 00 00 00 00
        dh      "180C0E0E0F0F0F0F0C06070707070707"             ;#63F0: 18 0C 0E 0E 0F 0F 0F 0F 0C 06 07 07 07 07 07 07
        dh      "783C1C0C84C4E4F40F0F0F0F0F0F0F0F"             ;#6400: 78 3C 1C 0C 84 C4 E4 F4 0F 0F 0F 0F 0F 0F 0F 0F
        dh      "0707070707070707F4FCFCFCFCFCFCFC"             ;#6410: 07 07 07 07 07 07 07 07 F4 FC FC FC FC FC FC FC
        dh      "00000000000080C00F0F0F0F0F0F0F1F"             ;#6420: 00 00 00 00 00 00 80 C0 0F 0F 0F 0F 0F 0F 0F 1F
        dh      "808080C0C0C0E0F0070707070707070F"             ;#6430: 80 80 80 C0 C0 C0 E0 F0 07 07 07 07 07 07 07 0F
        dh      "FCFCFCFCFCFCFCFE0000000000000001"             ;#6440: FC FC FC FC FC FC FC FE 00 00 00 00 00 00 00 01
        dh      "FFFFF7F7F7F3F3F1F1F0F0F0F0000000"             ;#6450: FF FF F7 F7 F7 F3 F3 F1 F1 F0 F0 F0 F0 00 00 00
        dh      "FFFFFF7F7F0000000F19103061C18307"             ;#6460: FF FF FF 7F 7F 00 00 00 0F 19 10 30 61 C1 83 07
        dh      "008080E0E0F0F0F80306060202020301"             ;#6470: 00 80 80 E0 E0 F0 F0 F8 03 06 06 02 02 02 03 01
        dh      "F80C06020301010000010306040C98F0"             ;#6480: F8 0C 06 02 03 01 01 00 00 01 03 06 04 0C 98 F0
        dh      "F8880C0C0C1C3C3C070F1F1F3F7F7EFE"             ;#6490: F8 88 0C 0C 0C 1C 3C 3C 07 0F 1F 1F 3F 7F 7E FE
        dh      "F8FCFCFF80000000010101E03018080C"             ;#64A0: F8 FC FC FF 80 00 00 00 01 01 01 E0 30 18 08 0C
        dh      "8080C0E0E0E0F0786000000101030307"             ;#64B0: 80 80 C0 E0 E0 E0 F0 78 60 00 00 01 01 03 03 07
        dh      "7C7CFCF8F8F0F0E0FEFEFFFFFFFFFFFE"             ;#64C0: 7C 7C FC F8 F8 F0 F0 E0 FE FE FF FF FF FF FF FE
        dh      "000000FFFF7F3F1F0C0E1EFEFEFEFCF8"             ;#64D0: 00 00 00 FF FF 7F 3F 1F 0C 0E 1E FE FE FE FC F8
        dh      "78707030202060400303010101000000"             ;#64E0: 78 70 70 30 20 20 60 40 03 03 01 01 01 00 00 00
        dh      "E0C0C080808080C0FEFEFEFEFEFEFEFE"             ;#64F0: E0 C0 C0 80 80 80 80 C0 FE FE FE FE FE FE FE FE
        dh      "0000010103020604C080800000000000"             ;#6500: 00 00 01 01 03 02 06 04 C0 80 80 00 00 00 00 00
        dh      "4060203018080C060C18103060602030"             ;#6510: 40 60 20 30 18 08 0C 06 0C 18 10 30 60 60 20 30
        dh      "0000000001010307000040E0E0F0F8FC"             ;#6520: 00 00 00 00 01 01 03 07 00 00 40 E0 E0 F0 F8 FC
        dh      "02030101010101011F1F1F0F0F070707"             ;#6530: 02 03 01 01 01 01 01 01 1F 1F 1F 0F 0F 07 07 07
        dh      "FEFEFEFEFE0000000303010100000000"             ;#6540: FE FE FE FE FE 00 00 00 03 03 01 01 00 00 00 00

LOAD_PLAYFIELD_GFX:
        ; Fill name table, upload status/digit patterns, init both VRAM banks
        ; LOAD_PLAYFIELD_GFX uploads the HUD-and-text static graphics: tile patterns for
        ; chars 80h-FFh (PATTERN_RALLYX_LOGO → VRAM 0C00h + bank-B 1C00h), the HUD row
        ; tile-mapping (TILES_RALLYX_LOGO → 04A0h), the SCORE/HI_SCORE labels, digit-row
        ; templates, and the NAMCO copyright text. Also unpacks the initial scores
        ; (HIGH_SCORE_BCD via UNPACK_BCD_DIGITS).
        LOAD_VRAM_ADDRESS hl, 400h                             ;#6550: 21 00 04
        ld      bc,300h                                        ;#6553: 01 00 03
        ld      a,40h                                          ;#6556: 3E 40
        call    BIOS_FILVRM                                    ;#6558: CD 56 00
        xor     a                                              ;#655B: AF
        ld      (NAME_BANK_FLAG),a                             ;#655C: 32 0E E0
        LOAD_VRAM_ADDRESS hl, 790h                             ;#655F: 21 90 07
        ld      bc,10h                                         ;#6562: 01 10 00
        ld      a,50h                                          ;#6565: 3E 50
        call    BIOS_FILVRM                                    ;#6567: CD 56 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#656A: 21 90 62
        LOAD_VRAM_ADDRESS de, 0C00h                            ;#656D: 11 00 0C
        ld      bc,400h                                        ;#6570: 01 00 04
        call    BIOS_LDIRVM                                    ;#6573: CD 5C 00
        ld      hl,PATTERN_RALLYX_LOGO                         ;#6576: 21 90 62
        LOAD_VRAM_ADDRESS de, 1C00h                            ;#6579: 11 00 1C
        ld      bc,400h                                        ;#657C: 01 00 04
        call    BIOS_LDIRVM                                    ;#657F: CD 5C 00
        ld      hl,TILES_RALLYX_LOGO                           ;#6582: 21 40 66
        LOAD_VRAM_ADDRESS de, 4A0h                             ;#6585: 11 A0 04
        ld      bc,0E0h                                        ;#6588: 01 E0 00
        call    BIOS_LDIRVM                                    ;#658B: CD 5C 00
        ld      hl,PLAYFIELD_NAMETABLE_DATA                    ;#658E: 21 EE 65
        LOAD_VRAM_ADDRESS de, 406h                             ;#6591: 11 06 04
        ld      bc,13h                                         ;#6594: 01 13 00
        call    BIOS_LDIRVM                                    ;#6597: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#659A: 21 31 E0
        call    UNPACK_BCD_DIGITS                              ;#659D: CD A0 67
        ld      hl,DIGIT_TILE_BUFFER                           ;#65A0: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 423h                             ;#65A3: 11 23 04
        ld      bc,8                                           ;#65A6: 01 08 00
        call    BIOS_LDIRVM                                    ;#65A9: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#65AC: 21 01 E0
        call    UNPACK_BCD_DIGITS                              ;#65AF: CD A0 67
        ld      hl,DIGIT_TILE_BUFFER                           ;#65B2: 21 F0 E1
        LOAD_VRAM_ADDRESS de, 430h                             ;#65B5: 11 30 04
        ld      bc,8                                           ;#65B8: 01 08 00
        call    BIOS_LDIRVM                                    ;#65BB: CD 5C 00
        ld      hl,DEFAULT_SCORE_VALUES                        ;#65BE: 21 01 66
        LOAD_VRAM_ADDRESS de, 5C8h                             ;#65C1: 11 C8 05
        ld      bc,0Eh                                         ;#65C4: 01 0E 00
        call    BIOS_LDIRVM                                    ;#65C7: CD 5C 00
        ld      hl,DIGIT_TEMPLATE_10_17                        ;#65CA: 21 0F 66
        LOAD_VRAM_ADDRESS de, 62Bh                             ;#65CD: 11 2B 06
        ld      bc,8                                           ;#65D0: 01 08 00
        call    BIOS_LDIRVM                                    ;#65D3: CD 5C 00
        ld      hl,TEXT_NAMCO_LTD                              ;#65D6: 21 17 66
        LOAD_VRAM_ADDRESS de, 685h                             ;#65D9: 11 85 06
        ld      bc,16h                                         ;#65DC: 01 16 00
        call    BIOS_LDIRVM                                    ;#65DF: CD 5C 00
        ld      hl,TEXT_RIGHTS_RESERVED                        ;#65E2: 21 2D 66
        LOAD_VRAM_ADDRESS de, 6C6h                             ;#65E5: 11 C6 06
        ld      bc,13h                                         ;#65E8: 01 13 00
        jp      BIOS_LDIRVM                                    ;#65EB: C3 5C 00

PLAYFIELD_NAMETABLE_DATA:
SCORE_HI_SCORE_LABELS:
        ; 19-byte "score      hi" + "score" label row LDIRVM'd to VRAM 0406h
        db      "score      hi", 7Fh, "score"                  ;#65EE: 73 63 6F 72 65 20 20 20 20 20 20 68 69 7F 73 63 6F 72 65

DEFAULT_SCORE_VALUES:
        ; 14-byte initial-displayed score digits LDIRVM'd to VRAM 05C8h
        dh      "30353328203330212325202B2539"                 ;#6601: 30 35 33 28 20 33 30 21 23 25 20 2B 25 39

DIGIT_TEMPLATE_10_17:
        ; 8 tile codes (10h..17h) LDIRVM'd to VRAM 062Bh as digit slot template
        dh      "1011121314151617"                             ;#660F: 10 11 12 13 14 15 16 17

TEXT_NAMCO_LTD:
        ; 22-byte "[ ... NAMCO LTD]" decoration + text LDIRVM'd to VRAM 0685h
        db      "[ ", 1, 9, 8, 0, " ", 1, 9, 8, 4, " NAMCO LTD]"  ;#6617: 5B 20 01 09 08 00 20 01 09 08 04 20 4E 41 4D 43 4F 20 4C 54 44 5D

TEXT_RIGHTS_RESERVED:
        ; 19-byte "ALL RIGHTS RESERVED" string LDIRVM'd to VRAM 06C6h
        db      "ALL RIGHTS RESERVED"                          ;#662D: 41 4C 4C 20 52 49 47 48 54 53 20 52 45 53 45 52 56 45 44

TILES_RALLYX_LOGO:
        ; Rally-X logo name-table layout (32x7 tile codes 80h-D7h); LDIRVM'd to VRAM 04A0h
        dh      "20202020208081828384858687A0A184"             ;#6640: 20 20 20 20 20 80 81 82 83 84 85 86 87 A0 A1 84
        dh      "80A2A3A4A5BBBCBDBEBFC02020202020"             ;#6650: 80 A2 A3 A4 A5 BB BC BD BE BF C0 20 20 20 20 20
        dh      "20202020208889848A8B8C8D8E84A6A7"             ;#6660: 20 20 20 20 20 88 89 84 8A 8B 8C 8D 8E 84 A6 A7
        dh      "88A8A9AAABC1C2C3C4C5C62020202020"             ;#6670: 88 A8 A9 AA AB C1 C2 C3 C4 C5 C6 20 20 20 20 20
        dh      "2020202020888F9091928484938484AC"             ;#6680: 20 20 20 20 20 88 8F 90 91 92 84 84 93 84 84 AC
        dh      "8884ADAE84C7C8C9CACBCC2020202020"             ;#6690: 88 84 AD AE 84 C7 C8 C9 CA CB CC 20 20 20 20 20
        dh      "202020202088948495968484978484AF"             ;#66A0: 20 20 20 20 20 88 94 84 95 96 84 84 97 84 84 AF
        dh      "8884B0B184CD84CECF84D02020202020"             ;#66B0: 88 84 B0 B1 84 CD 84 CE CF 84 D0 20 20 20 20 20
        dh      "20202020209899849A8484849BB284B3"             ;#66C0: 20 20 20 20 20 98 99 84 9A 84 84 84 9B B2 84 B3
        dh      "B484B5B6B7CD84D1D2D3D42020202020"             ;#66D0: B4 84 B5 B6 B7 CD 84 D1 D2 D3 D4 20 20 20 20 20
        dh      "20202020209C9D9D9D9D9D9D9D9D9D9D"             ;#66E0: 20 20 20 20 20 9C 9D 9D 9D 9D 9D 9D 9D 9D 9D 9D
        dh      "9D9D9DB89DCD84D59D9D9D2020202020"             ;#66F0: 9D 9D 9D B8 9D CD 84 D5 9D 9D 9D 20 20 20 20 20
        dh      "2020202020849E9F9F9F9F9F9F9F9F9F"             ;#6700: 20 20 20 20 20 84 9E 9F 9F 9F 9F 9F 9F 9F 9F 9F
        dh      "9F9F9FB9BAD684D79F9F9F2020202020"             ;#6710: 9F 9F 9F B9 BA D6 84 D7 9F 9F 9F 20 20 20 20 20

FLASH_AND_UPDATE_SCORE_HUD:
        ; Blink the SCORE label every 8 frames + redraw score digits each frame
        ; FLASH_AND_UPDATE_SCORE_HUD. Like UPDATE_SCORE_HUD but adds a visibility flash:
        ; when FRAME_TICK & 8, the SCORE label is replaced with spaces (FILVRM with
        ; value 20h) to make it blink. Otherwise it redraws normally. Used during
        ; attract mode or "1UP/2UP" highlighting.
        ld      hl,SCORE_LABEL                                 ;#6720: 21 42 67
        ld      de,457h                                        ;#6723: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#6726: 3A 0E E0
        and     a                                              ;#6729: A7
        jr      z,FLASH_SCORE_LDIRVM_OR_FILL                   ;#672A: 28 03
        ld      de,1457h                                       ;#672C: 11 57 14
FLASH_SCORE_LDIRVM_OR_FILL:
        ; Branch: if FRAME_TICK & 8 then FILVRM blanks, else LDIRVM the label
        push    de                                             ;#672F: D5
        ld      bc,5                                           ;#6730: 01 05 00
        ld      a,(FRAME_TICK)                                 ;#6733: 3A 07 E0
        and     8                                              ;#6736: E6 08
        jr      z,UPDATE_SCORE_HUD_LDIRVM_LABEL                ;#6738: 28 28
        ex      de,hl                                          ;#673A: EB
        ld      a,20h                                          ;#673B: 3E 20
        call    BIOS_FILVRM                                    ;#673D: CD 56 00
        jr      UPDATE_SCORE_HUD_AFTER_LABEL                   ;#6740: 18 23

SCORE_LABEL:
        ; "SCORE" HUD label (5 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "SCORE"                                        ;#6742: 53 43 4F 52 45

HI_SCORE_LABEL:
        ; "HI_SCORE" HUD label (8 bytes); LDIRVM'd by UPDATE_SCORE_HUD
        db      "HI_SCORE"                                     ;#6747: 48 49 5F 53 43 4F 52 45

UPDATE_SCORE_HUD:
        ; Draw SCORE label and BCD-unpacked SCORE_BCD digits into the HUD name-table row
        ; UPDATE_SCORE_HUD redraws the score row each frame. LDIRVM the "SCORE" /
        ; "HI_SCORE" labels (SCORE_LABEL/HI_SCORE_LABEL), then UNPACK_BCD_DIGITS on
        ; SCORE_BCD (3 bytes BCD = 6 digits, leading-zero suppressed) and LDIRVM the
        ; digit row to the score VRAM position. Does the same for HIGH_SCORE_BCD.
        ld      hl,SCORE_LABEL                                 ;#674F: 21 42 67
        ld      de,457h                                        ;#6752: 11 57 04
        ld      a,(NAME_BANK_FLAG)                             ;#6755: 3A 0E E0
        and     a                                              ;#6758: A7
        jr      z,UPDATE_SCORE_HUD_PUSH_DE                     ;#6759: 28 03
        LOAD_VRAM_ADDRESS de, 1457h                            ;#675B: 11 57 14
UPDATE_SCORE_HUD_PUSH_DE:
        ; Save DE (VRAM dest of SCORE row) for re-use across LDIRVM calls
        push    de                                             ;#675E: D5
        ld      bc,5                                           ;#675F: 01 05 00
UPDATE_SCORE_HUD_LDIRVM_LABEL:
        ; LDIRVM the SCORE label string
        call    BIOS_LDIRVM                                    ;#6762: CD 5C 00
UPDATE_SCORE_HUD_AFTER_LABEL:
        ; After SCORE label: restore DE, set up HI_SCORE position via DE - 40h
        pop     de                                             ;#6765: D1
        push    de                                             ;#6766: D5
        ld      hl,-40h                                        ;#6767: 21 C0 FF
        add     hl,de                                          ;#676A: 19
        ex      de,hl                                          ;#676B: EB
        ld      hl,HI_SCORE_LABEL                              ;#676C: 21 47 67
        ld      bc,8                                           ;#676F: 01 08 00
        call    BIOS_LDIRVM                                    ;#6772: CD 5C 00
        ld      hl,SCORE_BCD                                   ;#6775: 21 31 E0
        call    UNPACK_BCD_DIGITS                              ;#6778: CD A0 67
        pop     de                                             ;#677B: D1
        push    de                                             ;#677C: D5
        ld      hl,20h                                         ;#677D: 21 20 00
        add     hl,de                                          ;#6780: 19
        ex      de,hl                                          ;#6781: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#6782: 21 F0 E1
        ld      bc,8                                           ;#6785: 01 08 00
        call    BIOS_LDIRVM                                    ;#6788: CD 5C 00
        ld      hl,HIGH_SCORE_BCD                              ;#678B: 21 01 E0
        call    UNPACK_BCD_DIGITS                              ;#678E: CD A0 67
        pop     de                                             ;#6791: D1
        ld      hl,-20h                                        ;#6792: 21 E0 FF
        add     hl,de                                          ;#6795: 19
        ex      de,hl                                          ;#6796: EB
        ld      hl,DIGIT_TILE_BUFFER                           ;#6797: 21 F0 E1
        ld      bc,8                                           ;#679A: 01 08 00
        jp      BIOS_LDIRVM                                    ;#679D: C3 5C 00

UNPACK_BCD_DIGITS:
        ; Decode BCD bytes at HL into 8 tile indices at DIGIT_TILE_BUFFER
        ; UNPACK_BCD_DIGITS reads BCD bytes at HL and writes 8 tile indices at
        ; DIGIT_TILE_BUFFER. Each BCD nibble becomes a tile in the range 0..9. Leading
        ; zeros are suppressed (tile 40h = blank). The output is then LDIRVM'd to a
        ; digit row in VRAM by callers.
        ld      de,DIGIT_TILE_BUFFER_END                       ;#67A0: 11 F8 E1
        ld      b,8                                            ;#67A3: 06 08
        ld      a,40h                                          ;#67A5: 3E 40
UNPACK_BCD_CLEAR_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (init blanks)
        dec     de                                             ;#67A7: 1B
        ld      (de),a                                         ;#67A8: 12
        djnz    UNPACK_BCD_CLEAR_LOOP                          ;#67A9: 10 FC
        ld      b,3                                            ;#67AB: 06 03
UNPACK_BCD_SKIP_LZ_LOOP:
        ; Inner djnz of UNPACK_BCD_DIGITS (skip leading zero bytes)
        ld      a,(hl)                                         ;#67AD: 7E
        and     a                                              ;#67AE: A7
        jr      nz,UNPACK_BCD_NONZERO                          ;#67AF: 20 09
        inc     de                                             ;#67B1: 13
        inc     de                                             ;#67B2: 13
        inc     hl                                             ;#67B3: 23
        djnz    UNPACK_BCD_SKIP_LZ_LOOP                        ;#67B4: 10 F7
        ld      b,1                                            ;#67B6: 06 01
        jr      UNPACK_BCD_LOOP                                ;#67B8: 18 10

UNPACK_BCD_NONZERO:
        ; BCD byte non-zero: unpack high nibble (skip if leading zero), then low
        rra                                                    ;#67BA: 1F
        rra                                                    ;#67BB: 1F
        rra                                                    ;#67BC: 1F
        rra                                                    ;#67BD: 1F
        and     0Fh                                            ;#67BE: E6 0F
        jr      z,UNPACK_BCD_AFTER_HIGH                        ;#67C0: 28 01
        ld      (de),a                                         ;#67C2: 12
UNPACK_BCD_AFTER_HIGH:
        ; Common path after high nibble: store low nibble
        inc     de                                             ;#67C3: 13
        ld      a,(hl)                                         ;#67C4: 7E
        and     0Fh                                            ;#67C5: E6 0F
        ld      (de),a                                         ;#67C7: 12
        inc     de                                             ;#67C8: 13
        inc     hl                                             ;#67C9: 23
UNPACK_BCD_LOOP:
        ; Loop body: unpack high+low nibbles from one BCD byte, advance DE
        ld      a,(hl)                                         ;#67CA: 7E
        rra                                                    ;#67CB: 1F
        rra                                                    ;#67CC: 1F
        rra                                                    ;#67CD: 1F
        rra                                                    ;#67CE: 1F
        and     0Fh                                            ;#67CF: E6 0F
        ld      (de),a                                         ;#67D1: 12
        inc     de                                             ;#67D2: 13
        ld      a,(hl)                                         ;#67D3: 7E
        and     0Fh                                            ;#67D4: E6 0F
        ld      (de),a                                         ;#67D6: 12
        inc     de                                             ;#67D7: 13
        inc     hl                                             ;#67D8: 23
        djnz    UNPACK_BCD_LOOP                                ;#67D9: 10 EF
        ret                                                    ;#67DB: C9

ADD_SCORE:
        ; Look up SCORE_BONUS_TABLE[A] and BCD-add it into SCORE_BCD
        ; ADD_SCORE indexes SCORE_BONUS_TABLE by A, reads the BCD value, and adds it
        ; into SCORE_BCD with daa carry propagation. Then calls CHECK_SCORE_MILESTONE
        ; which awards an extra life on milestone scores.
        push    hl                                             ;#67DC: E5
        ld      hl,SCORE_BONUS_TABLE                           ;#67DD: 21 F9 67
        add     a,l                                            ;#67E0: 85
        ld      l,a                                            ;#67E1: 6F
        jr      nc,ADD_SCORE_NO_CARRY                          ;#67E2: 30 01
        inc     h                                              ;#67E4: 24
ADD_SCORE_NO_CARRY:
        ; No carry from index offset: continue with high byte unchanged
        ld      a,(hl)                                         ;#67E5: 7E
        ld      hl,SCORE_BCD_HIGH                              ;#67E6: 21 33 E0
        ld      b,3                                            ;#67E9: 06 03
        and     a                                              ;#67EB: A7
ADD_SCORE_BCD_LOOP:
        ; Inner djnz of ADD_SCORE (3-byte BCD add)
        adc     a,(hl)                                         ;#67EC: 8E
        daa                                                    ;#67ED: 27
        ld      (hl),a                                         ;#67EE: 77
        ld      a,0                                            ;#67EF: 3E 00
        dec     hl                                             ;#67F1: 2B
        djnz    ADD_SCORE_BCD_LOOP                             ;#67F2: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#67F4: CD 23 68
        pop     hl                                             ;#67F7: E1
        ret                                                    ;#67F8: C9

SCORE_BONUS_TABLE:
        ; Points table indexed by event id; consumed by ADD_SCORE
        dh      "01020204030604080510061207140816"             ;#67F9: 01 02 02 04 03 06 04 08 05 10 06 12 07 14 08 16
        dh      "09181020"                                     ;#6809: 09 18 10 20

BCD_ADD_TO_BONUS:
        ; Opcode-overlap entry adding 10h to BONUS_BCD (see CONVENTIONS § OVERLAP_LD_A)
        ld      a,10h                                          ;#680D: 3E 10
        ld      hl,BONUS_BCD                                   ;#680F: 21 34 E0
        ld      b,4                                            ;#6812: 06 04
        and     a                                              ;#6814: A7
SCORE_BONUS_BCD_LOOP:
        ; Inner djnz inside SCORE_BONUS_TABLE area (alt entry)
        adc     a,(hl)                                         ;#6815: 8E
        daa                                                    ;#6816: 27
        ld      (hl),a                                         ;#6817: 77
        ld      a,0                                            ;#6818: 3E 00
        dec     hl                                             ;#681A: 2B
        djnz    SCORE_BONUS_BCD_LOOP                           ;#681B: 10 F8
        call    CHECK_SCORE_MILESTONE                          ;#681D: CD 23 68
        jp      UPDATE_SCORE_HUD                               ;#6820: C3 4F 67

CHECK_SCORE_MILESTONE:
        ; Inspect SCORE_BCD mid-byte for extra-life thresholds (2, 8); triggers SFX_60
        ; CHECK_SCORE_MILESTONE tests SCORE_BCD mid-byte (SCORE_BCD_MID) against 2 and 8
        ; (extra-life thresholds at every 200/800-thousand). When hit, increments LIVES,
        ; sets EXTRA_LIFE_AWARDED to prevent re-award, and triggers
        ; SFX_TRIGGER_EXTRA_LIFE for the celebratory jingle.
        ld      a,(SCORE_BCD_MID)                              ;#6823: 3A 32 E0
        cp      2                                              ;#6826: FE 02
        jr      nz,MILESTONE_CHECK_8                           ;#6828: 20 09
        ld      hl,EXTRA_LIFE_AWARDED                          ;#682A: 21 3E E0
        ld      a,(hl)                                         ;#682D: 7E
        and     a                                              ;#682E: A7
        jr      nz,UPDATE_HIGH_SCORE                           ;#682F: 20 1A
        jr      MILESTONE_AWARD_LIFE                           ;#6831: 18 0B

MILESTONE_CHECK_8:
        ; Check second milestone (8 -> 800k pts) for extra life
        cp      8                                              ;#6833: FE 08
        jr      nz,UPDATE_HIGH_SCORE                           ;#6835: 20 14
        ld      hl,EXTRA_LIFE_AWARDED                          ;#6837: 21 3E E0
        ld      a,(hl)                                         ;#683A: 7E
        dec     a                                              ;#683B: 3D
        jr      nz,UPDATE_HIGH_SCORE                           ;#683C: 20 0D
MILESTONE_AWARD_LIFE:
        ; Award extra life: set EXTRA_LIFE_AWARDED, trigger SFX, inc LIVES
        inc     (hl)                                           ;#683E: 34
        ld      a,1                                            ;#683F: 3E 01
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#6841: 32 60 E5
        ld      hl,LIVES                                       ;#6844: 21 35 E0
        inc     (hl)                                           ;#6847: 34
        call    UPDATE_LIVES_DISPLAY                           ;#6848: CD 65 68
UPDATE_HIGH_SCORE:
        ; Compare SCORE_BCD vs HIGH_SCORE_BCD; if greater, copy SCORE into HIGH_SCORE
        ; UPDATE_HIGH_SCORE compares SCORE_BCD byte-by-byte (high to low) against
        ; HIGH_SCORE_BCD. If SCORE > HIGH_SCORE at any byte position (early-exit on
        ; lower byte), copies the entire SCORE_BCD into HIGH_SCORE_BCD. Otherwise leaves
        ; HIGH_SCORE unchanged.
        ld      hl,HIGH_SCORE_BCD                              ;#684B: 21 01 E0
        ld      de,SCORE_BCD                                   ;#684E: 11 31 E0
        ld      b,4                                            ;#6851: 06 04
HIGH_SCORE_COMPARE_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (compare path)
        ld      a,(de)                                         ;#6853: 1A
        cp      (hl)                                           ;#6854: BE
        ret     c                                              ;#6855: D8
        ld      (hl),a                                         ;#6856: 77
        inc     hl                                             ;#6857: 23
        inc     de                                             ;#6858: 13
        jr      nz,HIGH_SCORE_TAIL_LOOP                        ;#6859: 20 07
        djnz    HIGH_SCORE_COMPARE_LOOP                        ;#685B: 10 F6
        ret                                                    ;#685D: C9

HIGH_SCORE_COPY_LOOP:
        ; Inner djnz of UPDATE_HIGH_SCORE (copy path)
        ld      a,(de)                                         ;#685E: 1A
        ld      (hl),a                                         ;#685F: 77
        inc     hl                                             ;#6860: 23
        inc     de                                             ;#6861: 13
HIGH_SCORE_TAIL_LOOP:
        ; Inner copy loop: SCORE_BCD bytes 2..4 over to HIGH_SCORE_BCD
        djnz    HIGH_SCORE_COPY_LOOP                           ;#6862: 10 FA
        ret                                                    ;#6864: C9

UPDATE_LIVES_DISPLAY:
        ; Draw LIVES as mini-car tiles in the HUD name-table row; indexes LIVES_ICON_TILES
        ; UPDATE_LIVES_DISPLAY reads LIVES, indexes LIVES_ICON_TILES - 2*LIVES (so
        ; LIVES_ICON_TILES_TOP extends backward to prepend N car-top tiles), and LDIRVMs
        ; the two tile rows into the HUD name-table row (06B7h/06D7h) in both banks.
        ; LIVES=0 -> blank; LIVES=1 -> 1 mini-car icon; etc. These are name-table tiles,
        ; not sprites.
        ld      a,(LIVES)                                      ;#6865: 3A 35 E0
        ld      hl,LIVES_ICON_TILES                            ;#6868: 21 AC 68
        add     a,a                                            ;#686B: 87
        jr      z,LIVES_DRAW_LOOP                              ;#686C: 28 08
        neg                                                    ;#686E: ED 44
        add     a,l                                            ;#6870: 85
        ld      l,a                                            ;#6871: 6F
        ld      a,0FFh                                         ;#6872: 3E FF
        adc     a,h                                            ;#6874: 8C
        ld      h,a                                            ;#6875: 67
LIVES_DRAW_LOOP:
        ; Per-row LDIRVM loop: two 8-byte tile rows to two name-table bank mirrors
        push    hl                                             ;#6876: E5
        LOAD_VRAM_ADDRESS de, 6B7h                             ;#6877: 11 B7 06
        ld      bc,8                                           ;#687A: 01 08 00
        call    BIOS_LDIRVM                                    ;#687D: CD 5C 00
        pop     hl                                             ;#6880: E1
        push    hl                                             ;#6881: E5
        LOAD_VRAM_ADDRESS de, 16B7h                            ;#6882: 11 B7 16
        ld      bc,8                                           ;#6885: 01 08 00
        call    BIOS_LDIRVM                                    ;#6888: CD 5C 00
        pop     hl                                             ;#688B: E1
        ld      bc,10h                                         ;#688C: 01 10 00
        add     hl,bc                                          ;#688F: 09
        push    hl                                             ;#6890: E5
        LOAD_VRAM_ADDRESS de, 6D7h                             ;#6891: 11 D7 06
        ld      bc,8                                           ;#6894: 01 08 00
        call    BIOS_LDIRVM                                    ;#6897: CD 5C 00
        pop     hl                                             ;#689A: E1
        LOAD_VRAM_ADDRESS de, 16D7h                            ;#689B: 11 D7 16
        ld      bc,8                                           ;#689E: 01 08 00
        jp      BIOS_LDIRVM                                    ;#68A1: C3 5C 00

LIVES_ICON_TILES_TOP:
        ; Top-row tiles (F8/FA) of the lives mini-car icons; prepended via negative offset
        dh      "F8FAF8FAF8FAF8FA"                             ;#68A4: F8 FA F8 FA F8 FA F8 FA

LIVES_ICON_TILES:
        ; Name-table tiles for the lives indicator (car-bottom F9/FB + blank 40h padding)
        dh      "4040404040404040F9FBF9FBF9FBF9FB"             ;#68AC: 40 40 40 40 40 40 40 40 F9 FB F9 FB F9 FB F9 FB
        dh      "4040404040404040"                             ;#68BC: 40 40 40 40 40 40 40 40

PSG_SILENCE_DEFAULTS:
        ; 14 bytes copied to PSG_MIRROR each frame before sound subsystems mix in
        dh      "00000000000000B8000000000000"                 ;#68C4: 00 00 00 00 00 00 00 B8 00 00 00 00 00 00

UPDATE_SOUND:
        ; Render PSG output from PSG_MIRROR; runs 8 sound subsystems when GAME_ACTIVE
        ; UPDATE_SOUND copies the 14-byte PSG_SILENCE_DEFAULTS into PSG_MIRROR each
        ; frame as the "silent" baseline. Then, gated by GAME_ACTIVE, runs the 8 sound-
        ; tick subroutines (3 music + 5 SFX). Each subsystem reads a "control byte"
        ; (zero = no sound on this channel, non-zero = play the addressed stream). After
        ; ticking, writes PSG_MIRROR to PSG R0..R11 sequentially, plus R12 if
        ; PSG_MIRROR[0Dh] is non-zero (envelope-shape trigger). The 8 logical voices
        ; share the 3 PSG channels via priority.
        ld      hl,PSG_SILENCE_DEFAULTS                        ;#68D2: 21 C4 68
        ld      de,PSG_MIRROR                                  ;#68D5: 11 00 E5
        ld      bc,0Eh                                         ;#68D8: 01 0E 00
        ldir                                                   ;#68DB: ED B0
        ld      a,(GAME_ACTIVE)                                ;#68DD: 3A 00 E0
        and     a                                              ;#68E0: A7
        jr      z,SOUND_WRITE_PSG                              ;#68E1: 28 18
        call    SOUND_TICK_MUSIC_THEME                         ;#68E3: CD 6B 6C
        call    SOUND_TICK_SFX_FLAG                            ;#68E6: CD 67 6A
        call    SOUND_TICK_MUSIC_OPENING                       ;#68E9: CD EA 6A
        call    SOUND_TICK_MUSIC_STAGE_CLEAR                   ;#68EC: CD 1E 6B
        call    SOUND_TICK_SFX_C_STAGE                         ;#68EF: CD 2E 69
        call    SOUND_TICK_SFX_SMOKE                           ;#68F2: CD 21 6A
        call    SOUND_TICK_SFX_BONUS                           ;#68F5: CD E5 69
        call    SOUND_TICK_SFX_BANG                            ;#68F8: CD 6C 69
SOUND_WRITE_PSG:
        ; Walk PSG_MIRROR[0..0Bh] and write each register via BIOS_WRTPSG
        ld      hl,PSG_MIRROR                                  ;#68FB: 21 00 E5
        xor     a                                              ;#68FE: AF
        ld      b,0Ch                                          ;#68FF: 06 0C
SOUND_PSG_WRITE_LOOP:
        ; Inner djnz of SOUND_WRITE_PSG (12 PSG registers)
        ld      e,(hl)                                         ;#6901: 5E
        inc     hl                                             ;#6902: 23
        call    BIOS_WRTPSG                                    ;#6903: CD 93 00
        inc     a                                              ;#6906: 3C
        djnz    SOUND_PSG_WRITE_LOOP                           ;#6907: 10 F8
        ld      a,(hl)                                         ;#6909: 7E
        and     a                                              ;#690A: A7
        ret     z                                              ;#690B: C8
        ld      e,a                                            ;#690C: 5F
        ld      a,0Ch                                          ;#690D: 3E 0C
        call    BIOS_WRTPSG                                    ;#690F: CD 93 00
        inc     hl                                             ;#6912: 23
        ld      e,(hl)                                         ;#6913: 5E
        inc     a                                              ;#6914: 3C
        jp      BIOS_WRTPSG                                    ;#6915: C3 93 00

SFX_C_STAGE_RESET:
        ; Done: clear SOUND_STATE_C_STAGE then fall into init
        xor     a                                              ;#6918: AF
        ld      (SOUND_STATE_C_STAGE),a                        ;#6919: 32 65 E5
SFX_C_STAGE_INIT_STREAM:
        ; Init SFX_C_STAGE stream pointers, counter, and volume cursor
        ld      hl,SFX_C_STAGE_STREAM                          ;#691C: 21 C6 6E
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),hl            ;#691F: 22 66 E5
        inc     hl                                             ;#6922: 23
        ld      a,(hl)                                         ;#6923: 7E
        ld      (SOUND_STATE_C_STAGE_COUNTER),a                ;#6924: 32 68 E5
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#6927: 21 55 6D
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#692A: 22 69 E5
        ret                                                    ;#692D: C9

SOUND_TICK_SFX_C_STAGE:
        ; Sound subsystem driven by state at SOUND_STATE_C_STAGE
        ld      a,(SOUND_STATE_C_STAGE)                        ;#692E: 3A 65 E5
        and     a                                              ;#6931: A7
        jr      z,SFX_C_STAGE_INIT_STREAM                      ;#6932: 28 E8
        ld      de,(SOUND_STATE_C_STAGE_STREAM_PTR)            ;#6934: ED 5B 66 E5
        ld      a,(de)                                         ;#6938: 1A
        ld      c,a                                            ;#6939: 4F
        inc     a                                              ;#693A: 3C
        jr      z,SFX_C_STAGE_RESET                            ;#693B: 28 DB
        ld      hl,(SOUND_STATE_C_STAGE_VOL_PTR)               ;#693D: 2A 69 E5
        ld      a,(hl)                                         ;#6940: 7E
        inc     hl                                             ;#6941: 23
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#6942: 22 69 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#6945: 32 0A E5
        ld      hl,SOUND_STATE_C_STAGE_COUNTER                 ;#6948: 21 68 E5
        dec     (hl)                                           ;#694B: 35
        jr      nz,SFX_C_STAGE_LOAD_PITCH                      ;#694C: 20 10
        inc     de                                             ;#694E: 13
        inc     de                                             ;#694F: 13
        inc     de                                             ;#6950: 13
        ld      a,(de)                                         ;#6951: 1A
        dec     de                                             ;#6952: 1B
        ld      (SOUND_STATE_C_STAGE_STREAM_PTR),de            ;#6953: ED 53 66 E5
        ld      (hl),a                                         ;#6957: 77
        ld      hl,SFX_C_STAGE_VOLUME_ENVELOPE                 ;#6958: 21 55 6D
        ld      (SOUND_STATE_C_STAGE_VOL_PTR),hl               ;#695B: 22 69 E5
SFX_C_STAGE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_C_STAGE channel C
        ld      b,0                                            ;#695E: 06 00
        ld      hl,NOTE_PERIOD_TABLE                           ;#6960: 21 89 70
        add     hl,bc                                          ;#6963: 09
        ld      e,(hl)                                         ;#6964: 5E
        inc     hl                                             ;#6965: 23
        ld      d,(hl)                                         ;#6966: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#6967: ED 53 04 E5
        ret                                                    ;#696B: C9

SOUND_TICK_SFX_BANG:
        ; Sound subsystem driven by state at SOUND_STATE_BANG
        ld      a,(SOUND_STATE_BANG)                           ;#696C: 3A 62 E5
        dec     a                                              ;#696F: 3D
        jr      nz,SFX_BANG_TICK_BRANCH                        ;#6970: 20 36
        xor     a                                              ;#6972: AF
        ld      (SOUND_STATE_THEME),a                          ;#6973: 32 10 E5
        ld      (SOUND_STATE_OPENING),a                        ;#6976: 32 20 E5
        ld      (SOUND_STATE_STAGE_CLEAR),a                    ;#6979: 32 30 E5
        ld      (SOUND_STATE_FLAG),a                           ;#697C: 32 40 E5
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#697F: 32 41 E5
        ld      (SOUND_STATE_SMOKE),a                          ;#6982: 32 42 E5
        ld      (SFX_TRIGGER_SMOKE),a                          ;#6985: 32 50 E5
        ld      (SOUND_STATE_BONUS),a                          ;#6988: 32 51 E5
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#698B: 32 60 E5
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#698E: 32 61 E5
        ld      a,2                                            ;#6991: 3E 02
        ld      (SOUND_STATE_BANG),a                           ;#6993: 32 62 E5
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#6996: 21 CC 69
        ld      de,PSG_MIRROR                                  ;#6999: 11 00 E5
        ld      bc,0Bh                                         ;#699C: 01 0B 00
        ldir                                                   ;#699F: ED B0
        ld      hl,SFX_BANG_VOLUME_ENVELOPE                    ;#69A1: 21 75 6D
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#69A4: 22 63 E5
        ret                                                    ;#69A7: C9

SFX_BANG_TICK_BRANCH:
        ; SFX_BANG tick branch: ldir 8 bytes from precomputed envelope into PSG_MIRROR
        inc     a                                              ;#69A8: 3C
        ret     z                                              ;#69A9: C8
        ld      hl,SFX_BANG_INIT_PSG_BLOCK                     ;#69AA: 21 CC 69
        ld      de,PSG_MIRROR                                  ;#69AD: 11 00 E5
        ld      bc,8                                           ;#69B0: 01 08 00
        ldir                                                   ;#69B3: ED B0
        ld      hl,(SOUND_STATE_BANG_STREAM_PTR)               ;#69B5: 2A 63 E5
        ld      a,(hl)                                         ;#69B8: 7E
        inc     hl                                             ;#69B9: 23
        ld      (SOUND_STATE_BANG_STREAM_PTR),hl               ;#69BA: 22 63 E5
        inc     a                                              ;#69BD: 3C
        jr      nz,SFX_BANG_WRITE_VOL                          ;#69BE: 20 03
        ld      (SOUND_STATE_BANG),a                           ;#69C0: 32 62 E5
SFX_BANG_WRITE_VOL:
        ; Write the current envelope volume to PSG_MIRROR_VOL_A/B/C
        ld      hl,PSG_MIRROR_VOL_A                            ;#69C3: 21 08 E5
        ld      (hl),a                                         ;#69C6: 77
        inc     hl                                             ;#69C7: 23
        ld      (hl),a                                         ;#69C8: 77
        inc     hl                                             ;#69C9: 23
        ld      (hl),a                                         ;#69CA: 77
        ret                                                    ;#69CB: C9

SFX_BANG_INIT_PSG_BLOCK:
        ; 11-byte PSG silence/init block; LDIR-copied to PSG_MIRROR when SFX_BANG fires
        dh      "FF0FF205FF0F1F820F0F0F"                       ;#69CC: FF 0F F2 05 FF 0F 1F 82 0F 0F 0F

SFX_BONUS_INIT_STREAM:
        ; Init SFX_BONUS stream pointer at SFX_BONUS_STREAM
        ld      de,SFX_BONUS_STREAM                            ;#69D7: 11 B5 6E
        ld      hl,SOUND_STATE_BONUS_STREAM_PTR                ;#69DA: 21 52 E5
        ld      (hl),e                                         ;#69DD: 73
        inc     hl                                             ;#69DE: 23
        ld      (hl),d                                         ;#69DF: 72
        inc     hl                                             ;#69E0: 23
        inc     de                                             ;#69E1: 13
        ld      a,(de)                                         ;#69E2: 1A
        ld      (hl),a                                         ;#69E3: 77
        ret                                                    ;#69E4: C9

SOUND_TICK_SFX_BONUS:
        ; Sound subsystem driven by state at SOUND_STATE_BONUS
        ld      hl,SOUND_STATE_BONUS                           ;#69E5: 21 51 E5
        ld      a,(hl)                                         ;#69E8: 7E
        and     a                                              ;#69E9: A7
        jr      z,SFX_BONUS_INIT_STREAM                        ;#69EA: 28 EB
        inc     hl                                             ;#69EC: 23
        ld      e,(hl)                                         ;#69ED: 5E
        inc     hl                                             ;#69EE: 23
        ld      d,(hl)                                         ;#69EF: 56
        inc     hl                                             ;#69F0: 23
        ld      a,(de)                                         ;#69F1: 1A
        ld      c,a                                            ;#69F2: 4F
        inc     a                                              ;#69F3: 3C
        jr      z,SFX_BONUS_INIT_STREAM                        ;#69F4: 28 E1
        dec     (hl)                                           ;#69F6: 35
        jr      nz,SFX_BONUS_LOAD_PITCH                        ;#69F7: 20 0A
        inc     de                                             ;#69F9: 13
        inc     de                                             ;#69FA: 13
        inc     de                                             ;#69FB: 13
        ld      a,(de)                                         ;#69FC: 1A
        ld      (hl),a                                         ;#69FD: 77
        dec     de                                             ;#69FE: 1B
        dec     hl                                             ;#69FF: 2B
        ld      (hl),d                                         ;#6A00: 72
        dec     hl                                             ;#6A01: 2B
        ld      (hl),e                                         ;#6A02: 73
SFX_BONUS_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_BONUS channel B
        ld      hl,NOTE_PERIOD_TABLE                           ;#6A03: 21 89 70
        ld      b,0                                            ;#6A06: 06 00
        add     hl,bc                                          ;#6A08: 09
        ld      e,(hl)                                         ;#6A09: 5E
        inc     hl                                             ;#6A0A: 23
        ld      d,(hl)                                         ;#6A0B: 56
        ld      (PSG_MIRROR_PITCH_B),de                        ;#6A0C: ED 53 02 E5
        ld      a,0Ch                                          ;#6A10: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#6A12: 32 09 E5
        ret                                                    ;#6A15: C9

SFX_SMOKE_RESET:
        ; Done: reset volume pointer to SFX_SMOKE_VOLUME_ENVELOPE and clear state
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#6A16: 21 45 6D
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A19: 22 47 E5
        xor     a                                              ;#6A1C: AF
        ld      (SOUND_STATE_SMOKE_VOL_PTR),a                  ;#6A1D: 32 47 E5
        ret                                                    ;#6A20: C9

SOUND_TICK_SFX_SMOKE:
        ; Sound subsystem driven by state at SOUND_STATE_SMOKE
        ld      a,(SOUND_STATE_SMOKE)                          ;#6A21: 3A 42 E5
        and     a                                              ;#6A24: A7
        jr      z,SFX_SMOKE_RESET                              ;#6A25: 28 EF
        ld      de,(SOUND_STATE_SMOKE_STREAM_PTR)              ;#6A27: ED 5B 43 E5
        ld      a,(de)                                         ;#6A2B: 1A
        cp      0FFh                                           ;#6A2C: FE FF
        jr      z,SFX_SMOKE_RESET                              ;#6A2E: 28 E6
        ld      hl,SOUND_STATE_SMOKE_COUNTER                   ;#6A30: 21 45 E5
        dec     (hl)                                           ;#6A33: 35
        jr      nz,SFX_SMOKE_LOAD_PITCH                        ;#6A34: 20 0F
        inc     hl                                             ;#6A36: 23
        ld      c,(hl)                                         ;#6A37: 4E
        dec     hl                                             ;#6A38: 2B
        ld      (hl),c                                         ;#6A39: 71
        dec     hl                                             ;#6A3A: 2B
        inc     de                                             ;#6A3B: 13
        ld      (hl),d                                         ;#6A3C: 72
        dec     hl                                             ;#6A3D: 2B
        ld      (hl),e                                         ;#6A3E: 73
        ld      hl,SFX_SMOKE_VOLUME_ENVELOPE                   ;#6A3F: 21 45 6D
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A42: 22 47 E5
SFX_SMOKE_LOAD_PITCH:
        ; Look up note period in NOTE_PERIOD_TABLE for SFX_SMOKE channel C
        ld      hl,NOTE_PERIOD_TABLE                           ;#6A45: 21 89 70
        add     a,l                                            ;#6A48: 85
        ld      l,a                                            ;#6A49: 6F
        ld      a,0                                            ;#6A4A: 3E 00
        adc     a,h                                            ;#6A4C: 8C
        ld      h,a                                            ;#6A4D: 67
        ld      e,(hl)                                         ;#6A4E: 5E
        inc     hl                                             ;#6A4F: 23
        ld      d,(hl)                                         ;#6A50: 56
        ld      (PSG_MIRROR_PITCH_C),de                        ;#6A51: ED 53 04 E5
        ld      hl,(SOUND_STATE_SMOKE_VOL_PTR)                 ;#6A55: 2A 47 E5
        ld      a,(hl)                                         ;#6A58: 7E
        inc     hl                                             ;#6A59: 23
        ld      (SOUND_STATE_SMOKE_VOL_PTR),hl                 ;#6A5A: 22 47 E5
        ld      (PSG_MIRROR_VOL_C),a                           ;#6A5D: 32 0A E5
        ld      hl,0                                           ;#6A60: 21 00 00
        ld      (PSG_MIRROR_VOL_A),hl                          ;#6A63: 22 08 E5
        ret                                                    ;#6A66: C9

SOUND_TICK_SFX_FLAG:
        ; Sound subsystem driven by state at SOUND_STATE_FLAG
        ld      a,(SOUND_STATE_FLAG)                           ;#6A67: 3A 40 E5
        and     a                                              ;#6A6A: A7
        jr      z,SFX_FLAG_CHECK_VARIANT                       ;#6A6B: 28 17
        xor     a                                              ;#6A6D: AF
        ld      (SOUND_STATE_FLAG),a                           ;#6A6E: 32 40 E5
        ld      de,SFX_FLAG_STREAM_BASE                        ;#6A71: 11 7D 6E
SFX_FLAG_INIT_SFX_SMOKE:
        ; SFX_FLAG fires variant A: seed SOUND_STATE_SMOKE with stream and durations
        ld      hl,SOUND_STATE_SMOKE                           ;#6A74: 21 42 E5
        ld      (hl),1                                         ;#6A77: 36 01
        inc     hl                                             ;#6A79: 23
        ld      (hl),e                                         ;#6A7A: 73
        inc     hl                                             ;#6A7B: 23
        ld      (hl),d                                         ;#6A7C: 72
        inc     hl                                             ;#6A7D: 23
        ld      (hl),2                                         ;#6A7E: 36 02
        inc     hl                                             ;#6A80: 23
        ld      (hl),2                                         ;#6A81: 36 02
        ret                                                    ;#6A83: C9

SFX_FLAG_CHECK_VARIANT:
        ; Check second SFX_FLAG variant flag (SOUND_STATE_FLAG_ALT)
        ld      a,(SOUND_STATE_FLAG_ALT)                       ;#6A84: 3A 41 E5
        and     a                                              ;#6A87: A7
        jr      z,SFX_FLAG_CHECK_EXTRA_LIFE                    ;#6A88: 28 0A
        xor     a                                              ;#6A8A: AF
        ld      (SOUND_STATE_FLAG_ALT),a                       ;#6A8B: 32 41 E5
        ld      de,SFX_FLAG_STREAM_FLAG_GET                    ;#6A8E: 11 6F 6E
        jp      SFX_FLAG_INIT_SFX_SMOKE                        ;#6A91: C3 74 6A

SFX_FLAG_CHECK_EXTRA_LIFE:
        ; Check SFX_TRIGGER_EXTRA_LIFE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_EXTRA_LIFE)                     ;#6A94: 3A 60 E5
        and     a                                              ;#6A97: A7
        jr      z,SFX_FLAG_CHECK_SMOKE                         ;#6A98: 28 17
        xor     a                                              ;#6A9A: AF
        ld      (SFX_TRIGGER_EXTRA_LIFE),a                     ;#6A9B: 32 60 E5
        ld      de,SFX_FLAG_STREAM_EXTRA_LIFE                  ;#6A9E: 11 91 6E
        ld      hl,SOUND_STATE_SMOKE                           ;#6AA1: 21 42 E5
        ld      (hl),1                                         ;#6AA4: 36 01
        inc     hl                                             ;#6AA6: 23
        ld      (hl),e                                         ;#6AA7: 73
        inc     hl                                             ;#6AA8: 23
        ld      (hl),d                                         ;#6AA9: 72
        inc     hl                                             ;#6AAA: 23
        ld      (hl),4                                         ;#6AAB: 36 04
        inc     hl                                             ;#6AAD: 23
        ld      (hl),4                                         ;#6AAE: 36 04
        ret                                                    ;#6AB0: C9

SFX_FLAG_CHECK_SMOKE:
        ; Check SFX_TRIGGER_SMOKE: kick the SFX_SMOKE envelope if set
        ld      a,(SFX_TRIGGER_SMOKE)                          ;#6AB1: 3A 50 E5
        and     a                                              ;#6AB4: A7
        jr      z,SFX_FLAG_CHECK_E561                          ;#6AB5: 28 17
        xor     a                                              ;#6AB7: AF
        ld      (SFX_TRIGGER_SMOKE),a                          ;#6AB8: 32 50 E5
        ld      de,SFX_SMOKE_STREAM                            ;#6ABB: 11 85 6E
        ld      hl,SOUND_STATE_SMOKE                           ;#6ABE: 21 42 E5
        ld      (hl),1                                         ;#6AC1: 36 01
        inc     hl                                             ;#6AC3: 23
        ld      (hl),e                                         ;#6AC4: 73
        inc     hl                                             ;#6AC5: 23
        ld      (hl),d                                         ;#6AC6: 72
        inc     hl                                             ;#6AC7: 23
        ld      (hl),2                                         ;#6AC8: 36 02
        inc     hl                                             ;#6ACA: 23
        ld      (hl),2                                         ;#6ACB: 36 02
        ret                                                    ;#6ACD: C9

SFX_FLAG_CHECK_E561:
        ; Check SOUND_STATE_BANG_TRIGGER (fuel-low tick): kick SFX_SMOKE if just fired
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#6ACE: 3A 61 E5
        dec     a                                              ;#6AD1: 3D
        ret     nz                                             ;#6AD2: C0
        ld      a,2                                            ;#6AD3: 3E 02
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#6AD5: 32 61 E5
        ld      hl,SFX_FLAG_STREAM_FUEL_LOW                    ;#6AD8: 21 8A 6E
        ld      (SOUND_STATE_SMOKE_STREAM_PTR),hl              ;#6ADB: 22 43 E5
        ld      hl,0F0Fh                                       ;#6ADE: 21 0F 0F
        ld      (SOUND_STATE_SMOKE_COUNTER),hl                 ;#6AE1: 22 45 E5
        ld      a,1                                            ;#6AE4: 3E 01
        ld      (SOUND_STATE_SMOKE),a                          ;#6AE6: 32 42 E5
        ret                                                    ;#6AE9: C9

SOUND_TICK_MUSIC_OPENING:
        ; Music channel B tick; state at SOUND_STATE_OPENING
        ld      hl,SOUND_STATE_OPENING                         ;#6AEA: 21 20 E5
        ld      a,(hl)                                         ;#6AED: 7E
        and     a                                              ;#6AEE: A7
        jr      z,SOUND_TICK_MUSIC_OPENING_INIT                ;#6AEF: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#6AF1: CD 52 6B
        and     a                                              ;#6AF4: A7
        ret     nz                                             ;#6AF5: C0
SOUND_TICK_MUSIC_OPENING_INIT:
        ; MUSIC_OPENING init: clear state and seed pointers for three streams
        ld      hl,SOUND_STATE_OPENING                         ;#6AF6: 21 20 E5
        xor     a                                              ;#6AF9: AF
        ld      (hl),a                                         ;#6AFA: 77
        inc     hl                                             ;#6AFB: 23
        ld      de,MUSIC_OPENING_VOICE_0                       ;#6AFC: 11 64 70
        ld      (hl),e                                         ;#6AFF: 73
        inc     hl                                             ;#6B00: 23
        ld      (hl),d                                         ;#6B01: 72
        inc     hl                                             ;#6B02: 23
        inc     de                                             ;#6B03: 13
        ld      a,(de)                                         ;#6B04: 1A
        ld      (hl),a                                         ;#6B05: 77
        inc     hl                                             ;#6B06: 23
        ld      de,MUSIC_OPENING_VOICE_1                       ;#6B07: 11 44 70
        ld      (hl),e                                         ;#6B0A: 73
        inc     hl                                             ;#6B0B: 23
        ld      (hl),d                                         ;#6B0C: 72
        inc     hl                                             ;#6B0D: 23
        inc     de                                             ;#6B0E: 13
        ld      a,(de)                                         ;#6B0F: 1A
        ld      (hl),a                                         ;#6B10: 77
        inc     hl                                             ;#6B11: 23
        ld      de,MUSIC_OPENING_VOICE_2                       ;#6B12: 11 12 70
        ld      (hl),e                                         ;#6B15: 73
        inc     hl                                             ;#6B16: 23
        ld      (hl),d                                         ;#6B17: 72
        inc     hl                                             ;#6B18: 23
        inc     de                                             ;#6B19: 13
        ld      a,(de)                                         ;#6B1A: 1A
        ld      (hl),a                                         ;#6B1B: 77
        inc     hl                                             ;#6B1C: 23
        ret                                                    ;#6B1D: C9

SOUND_TICK_MUSIC_STAGE_CLEAR:
        ; Music channel C tick; state at SOUND_STATE_STAGE_CLEAR
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#6B1E: 21 30 E5
        ld      a,(hl)                                         ;#6B21: 7E
        and     a                                              ;#6B22: A7
        jr      z,SOUND_TICK_MUSIC_STAGE_CLEAR_INIT            ;#6B23: 28 05
        call    SOUND_ADVANCE_NOTE_DURATION                    ;#6B25: CD 52 6B
        and     a                                              ;#6B28: A7
        ret     nz                                             ;#6B29: C0
SOUND_TICK_MUSIC_STAGE_CLEAR_INIT:
        ; MUSIC_STAGE_CLEAR init: clear state and seed pointers for three voices
        ld      hl,SOUND_STATE_STAGE_CLEAR                     ;#6B2A: 21 30 E5
        xor     a                                              ;#6B2D: AF
        ld      (hl),a                                         ;#6B2E: 77
        inc     hl                                             ;#6B2F: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_2            ;#6B30: 11 A2 6E
        ld      (hl),e                                         ;#6B33: 73
        inc     hl                                             ;#6B34: 23
        ld      (hl),d                                         ;#6B35: 72
        inc     hl                                             ;#6B36: 23
        inc     de                                             ;#6B37: 13
        ld      a,(de)                                         ;#6B38: 1A
        ld      (hl),a                                         ;#6B39: 77
        inc     hl                                             ;#6B3A: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_1            ;#6B3B: 11 A0 6E
        ld      (hl),e                                         ;#6B3E: 73
        inc     hl                                             ;#6B3F: 23
        ld      (hl),d                                         ;#6B40: 72
        inc     hl                                             ;#6B41: 23
        inc     de                                             ;#6B42: 13
        ld      a,(de)                                         ;#6B43: 1A
        ld      (hl),a                                         ;#6B44: 77
        inc     hl                                             ;#6B45: 23
        ld      de,MUSIC_STAGE_CLEAR_STREAM_VOICE_0            ;#6B46: 11 9E 6E
        ld      (hl),e                                         ;#6B49: 73
        inc     hl                                             ;#6B4A: 23
        ld      (hl),d                                         ;#6B4B: 72
        inc     hl                                             ;#6B4C: 23
        inc     de                                             ;#6B4D: 13
        ld      a,(de)                                         ;#6B4E: 1A
        ld      (hl),a                                         ;#6B4F: 77
        inc     hl                                             ;#6B50: 23
        ret                                                    ;#6B51: C9

SOUND_ADVANCE_NOTE_DURATION:
        ; Decrement note-duration counter; on rollover, advance to next note byte
        inc     hl                                             ;#6B52: 23
        ld      e,(hl)                                         ;#6B53: 5E
        inc     hl                                             ;#6B54: 23
        ld      d,(hl)                                         ;#6B55: 56
        inc     hl                                             ;#6B56: 23
        dec     (hl)                                           ;#6B57: 35
        jr      nz,SOUND_ADVANCE_TAIL                          ;#6B58: 20 0C
        inc     de                                             ;#6B5A: 13
        inc     de                                             ;#6B5B: 13
        inc     de                                             ;#6B5C: 13
        ld      a,(de)                                         ;#6B5D: 1A
        dec     de                                             ;#6B5E: 1B
        ld      (hl),a                                         ;#6B5F: 77
        dec     hl                                             ;#6B60: 2B
        ld      (hl),d                                         ;#6B61: 72
        dec     hl                                             ;#6B62: 2B
        ld      (hl),e                                         ;#6B63: 73
        inc     hl                                             ;#6B64: 23
        inc     hl                                             ;#6B65: 23
SOUND_ADVANCE_TAIL:
        ; Common tail of SOUND_ADVANCE_NOTE_DURATION: ret nz
        ld      a,(de)                                         ;#6B66: 1A
        inc     a                                              ;#6B67: 3C
        ret     z                                              ;#6B68: C8
        dec     a                                              ;#6B69: 3D
        ld      de,NOTE_PERIOD_TABLE                           ;#6B6A: 11 89 70
        add     a,e                                            ;#6B6D: 83
        ld      e,a                                            ;#6B6E: 5F
        ld      a,0                                            ;#6B6F: 3E 00
        adc     a,d                                            ;#6B71: 8A
        ld      d,a                                            ;#6B72: 57
        ld      a,(de)                                         ;#6B73: 1A
        ld      c,a                                            ;#6B74: 4F
        inc     de                                             ;#6B75: 13
        ld      a,(de)                                         ;#6B76: 1A
        ld      b,a                                            ;#6B77: 47
        ld      (PSG_MIRROR),bc                                ;#6B78: ED 43 00 E5
        ld      a,0Ch                                          ;#6B7C: 3E 0C
        ld      (PSG_MIRROR_VOL_A),a                           ;#6B7E: 32 08 E5
        inc     hl                                             ;#6B81: 23
        ld      e,(hl)                                         ;#6B82: 5E
        inc     hl                                             ;#6B83: 23
        ld      d,(hl)                                         ;#6B84: 56
        inc     hl                                             ;#6B85: 23
        dec     (hl)                                           ;#6B86: 35
        jr      nz,SOUND_B_LOAD_PITCH                          ;#6B87: 20 0C
        inc     de                                             ;#6B89: 13
        inc     de                                             ;#6B8A: 13
        inc     de                                             ;#6B8B: 13
        ld      a,(de)                                         ;#6B8C: 1A
        dec     de                                             ;#6B8D: 1B
        ld      (hl),a                                         ;#6B8E: 77
        dec     hl                                             ;#6B8F: 2B
        ld      (hl),d                                         ;#6B90: 72
        dec     hl                                             ;#6B91: 2B
        ld      (hl),e                                         ;#6B92: 73
        inc     hl                                             ;#6B93: 23
        inc     hl                                             ;#6B94: 23
SOUND_B_LOAD_PITCH:
        ; After advance: look up channel-B note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#6B95: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6B96: 11 89 70
        add     a,e                                            ;#6B99: 83
        ld      e,a                                            ;#6B9A: 5F
        ld      a,0                                            ;#6B9B: 3E 00
        adc     a,d                                            ;#6B9D: 8A
        ld      d,a                                            ;#6B9E: 57
        ld      a,(de)                                         ;#6B9F: 1A
        ld      c,a                                            ;#6BA0: 4F
        inc     de                                             ;#6BA1: 13
        ld      a,(de)                                         ;#6BA2: 1A
        ld      b,a                                            ;#6BA3: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#6BA4: ED 43 02 E5
        ld      a,0Ch                                          ;#6BA8: 3E 0C
        ld      (PSG_MIRROR_VOL_B),a                           ;#6BAA: 32 09 E5
        inc     hl                                             ;#6BAD: 23
        ld      e,(hl)                                         ;#6BAE: 5E
        inc     hl                                             ;#6BAF: 23
        ld      d,(hl)                                         ;#6BB0: 56
        inc     hl                                             ;#6BB1: 23
        dec     (hl)                                           ;#6BB2: 35
        jr      nz,SOUND_C_LOAD_PITCH                          ;#6BB3: 20 0C
        inc     de                                             ;#6BB5: 13
        inc     de                                             ;#6BB6: 13
        inc     de                                             ;#6BB7: 13
        ld      a,(de)                                         ;#6BB8: 1A
        dec     de                                             ;#6BB9: 1B
        ld      (hl),a                                         ;#6BBA: 77
        dec     hl                                             ;#6BBB: 2B
        ld      (hl),d                                         ;#6BBC: 72
        dec     hl                                             ;#6BBD: 2B
        ld      (hl),e                                         ;#6BBE: 73
        inc     hl                                             ;#6BBF: 23
        inc     hl                                             ;#6BC0: 23
SOUND_C_LOAD_PITCH:
        ; After advance: look up channel-C note pitch in NOTE_PERIOD_TABLE
        ld      a,(de)                                         ;#6BC1: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6BC2: 11 89 70
        add     a,e                                            ;#6BC5: 83
        ld      e,a                                            ;#6BC6: 5F
        ld      a,0                                            ;#6BC7: 3E 00
        adc     a,d                                            ;#6BC9: 8A
        ld      d,a                                            ;#6BCA: 57
        ld      a,(de)                                         ;#6BCB: 1A
        ld      c,a                                            ;#6BCC: 4F
        inc     de                                             ;#6BCD: 13
        ld      a,(de)                                         ;#6BCE: 1A
        ld      b,a                                            ;#6BCF: 47
        ld      (PSG_MIRROR_PITCH_C),bc                        ;#6BD0: ED 43 04 E5
        ld      a,0Ch                                          ;#6BD4: 3E 0C
        ld      (PSG_MIRROR_VOL_C),a                           ;#6BD6: 32 0A E5
        ret                                                    ;#6BD9: C9

MUSIC_THEME_RESTART:
        ; Stream end: bump SOUND_STATE_THEME index; restart substream 0/1/2
        ld      hl,SOUND_STATE_THEME                           ;#6BDA: 21 10 E5
        inc     hl                                             ;#6BDD: 23
        inc     (hl)                                           ;#6BDE: 34
        ld      a,(hl)                                         ;#6BDF: 7E
        cp      3                                              ;#6BE0: FE 03
        jr      z,MUSIC_THEME_REPICK                           ;#6BE2: 28 2B
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#6BE4: 11 C5 6D
        inc     hl                                             ;#6BE7: 23
        ld      (hl),e                                         ;#6BE8: 73
        inc     hl                                             ;#6BE9: 23
        ld      (hl),d                                         ;#6BEA: 72
        inc     de                                             ;#6BEB: 13
        ld      a,(de)                                         ;#6BEC: 1A
        inc     hl                                             ;#6BED: 23
        ld      (hl),a                                         ;#6BEE: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6BEF: 11 35 6D
        inc     hl                                             ;#6BF2: 23
        ld      (hl),e                                         ;#6BF3: 73
        inc     hl                                             ;#6BF4: 23
        ld      (hl),d                                         ;#6BF5: 72
        inc     hl                                             ;#6BF6: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE0_2                ;#6BF7: 11 06 6E
        ld      (hl),e                                         ;#6BFA: 73
        inc     hl                                             ;#6BFB: 23
        ld      (hl),d                                         ;#6BFC: 72
        inc     hl                                             ;#6BFD: 23
        inc     de                                             ;#6BFE: 13
        ld      a,(de)                                         ;#6BFF: 1A
        ld      (hl),a                                         ;#6C00: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C01: 11 F5 6C
        inc     hl                                             ;#6C04: 23
        ld      (hl),e                                         ;#6C05: 73
        inc     hl                                             ;#6C06: 23
        ld      (hl),d                                         ;#6C07: 72
        inc     de                                             ;#6C08: 13
        inc     hl                                             ;#6C09: 23
        ld      a,(de)                                         ;#6C0A: 1A
        ld      (hl),a                                         ;#6C0B: 77
        jp      SOUND_TICK_MUSIC_THEME                         ;#6C0C: C3 6B 6C

MUSIC_THEME_REPICK:
        ; After substream 3: call PICK_MUSIC_STREAM then re-enter SOUND_TICK_MUSIC_THEME
        call    PICK_MUSIC_STREAM                              ;#6C0F: CD 16 6C
        jp      SOUND_TICK_MUSIC_THEME                         ;#6C12: C3 6B 6C

MUSIC_THEME_REFRESH_HEAD:
        ; Substream 0 head refresh: clear state and re-seed (used after silence/start)
        inc     hl                                             ;#6C15: 23
PICK_MUSIC_STREAM:
        ; Select music data stream for SOUND_TICK_MUSIC_THEME based on STAGE_PALETTE_INDEX
        xor     a                                              ;#6C16: AF
        ld      (hl),a                                         ;#6C17: 77
        ld      a,(STAGE_PALETTE_INDEX)                        ;#6C18: 3A 30 E0
        cpl                                                    ;#6C1B: 2F
        and     3                                              ;#6C1C: E6 03
        jp      z,MUSIC_THEME_PICK_VARIANT                     ;#6C1E: CA 46 6C
        ld      de,MUSIC_THEME_VOICE0_BASELINE                 ;#6C21: 11 FB 6E
        inc     hl                                             ;#6C24: 23
        ld      (hl),e                                         ;#6C25: 73
        inc     hl                                             ;#6C26: 23
        ld      (hl),d                                         ;#6C27: 72
        inc     de                                             ;#6C28: 13
        ld      a,(de)                                         ;#6C29: 1A
        inc     hl                                             ;#6C2A: 23
        ld      (hl),a                                         ;#6C2B: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C2C: 11 35 6D
        inc     hl                                             ;#6C2F: 23
        ld      (hl),e                                         ;#6C30: 73
        inc     hl                                             ;#6C31: 23
        ld      (hl),d                                         ;#6C32: 72
        inc     hl                                             ;#6C33: 23
        ld      de,MUSIC_THEME_VOICE1_BASELINE                 ;#6C34: 11 80 6F
        ld      (hl),e                                         ;#6C37: 73
        inc     hl                                             ;#6C38: 23
        ld      (hl),d                                         ;#6C39: 72
        inc     hl                                             ;#6C3A: 23
        inc     de                                             ;#6C3B: 13
        ld      a,(de)                                         ;#6C3C: 1A
        ld      (hl),a                                         ;#6C3D: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C3E: 11 F5 6C
        inc     hl                                             ;#6C41: 23
        ld      (hl),e                                         ;#6C42: 73
        inc     hl                                             ;#6C43: 23
        ld      (hl),d                                         ;#6C44: 72
        ret                                                    ;#6C45: C9

MUSIC_THEME_PICK_VARIANT:
        ; Pick the substream variant based on STAGE_PALETTE_INDEX bits
        ld      de,MUSIC_THEME_VARIANT_VOICE0                  ;#6C46: 11 C5 6D
        inc     hl                                             ;#6C49: 23
        ld      (hl),e                                         ;#6C4A: 73
        inc     hl                                             ;#6C4B: 23
        ld      (hl),d                                         ;#6C4C: 72
        inc     de                                             ;#6C4D: 13
        ld      a,(de)                                         ;#6C4E: 1A
        inc     hl                                             ;#6C4F: 23
        ld      (hl),a                                         ;#6C50: 77
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C51: 11 35 6D
        inc     hl                                             ;#6C54: 23
        ld      (hl),e                                         ;#6C55: 73
        inc     hl                                             ;#6C56: 23
        ld      (hl),d                                         ;#6C57: 72
        inc     hl                                             ;#6C58: 23
        ld      de,MUSIC_THEME_VARIANT_VOICE1                  ;#6C59: 11 36 6E
        ld      (hl),e                                         ;#6C5C: 73
        inc     hl                                             ;#6C5D: 23
        ld      (hl),d                                         ;#6C5E: 72
        inc     hl                                             ;#6C5F: 23
        inc     de                                             ;#6C60: 13
        ld      a,(de)                                         ;#6C61: 1A
        ld      (hl),a                                         ;#6C62: 77
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6C63: 11 F5 6C
        inc     hl                                             ;#6C66: 23
        ld      (hl),e                                         ;#6C67: 73
        inc     hl                                             ;#6C68: 23
        ld      (hl),d                                         ;#6C69: 72
        ret                                                    ;#6C6A: C9

SOUND_TICK_MUSIC_THEME:
        ; Music channel A tick; state at SOUND_STATE_THEME, writes PSG R0/R1
        ld      hl,SOUND_STATE_THEME                           ;#6C6B: 21 10 E5
        ld      a,(hl)                                         ;#6C6E: 7E
        and     a                                              ;#6C6F: A7
        jp      z,MUSIC_THEME_REFRESH_HEAD                     ;#6C70: CA 15 6C
        inc     hl                                             ;#6C73: 23
        inc     hl                                             ;#6C74: 23
        ld      e,(hl)                                         ;#6C75: 5E
        inc     hl                                             ;#6C76: 23
        ld      d,(hl)                                         ;#6C77: 56
        inc     hl                                             ;#6C78: 23
        ld      a,(hl)                                         ;#6C79: 7E
        dec     (hl)                                           ;#6C7A: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH                      ;#6C7B: 20 15
        inc     de                                             ;#6C7D: 13
        inc     de                                             ;#6C7E: 13
        inc     de                                             ;#6C7F: 13
        ld      a,(de)                                         ;#6C80: 1A
        ld      (hl),a                                         ;#6C81: 77
        dec     de                                             ;#6C82: 1B
        dec     hl                                             ;#6C83: 2B
        ld      (hl),d                                         ;#6C84: 72
        dec     hl                                             ;#6C85: 2B
        ld      (hl),e                                         ;#6C86: 73
        inc     hl                                             ;#6C87: 23
        inc     hl                                             ;#6C88: 23
        ld      de,MUSIC_THEME_DURATIONS                       ;#6C89: 11 35 6D
        inc     hl                                             ;#6C8C: 23
        ld      (hl),e                                         ;#6C8D: 73
        inc     hl                                             ;#6C8E: 23
        ld      (hl),d                                         ;#6C8F: 72
        dec     hl                                             ;#6C90: 2B
        dec     hl                                             ;#6C91: 2B
MUSIC_THEME_LOAD_PITCH:
        ; MUSIC_THEME tick: look up pitch byte from current stream
        ld      a,(de)                                         ;#6C92: 1A
        cp      0FFh                                           ;#6C93: FE FF
        jp      z,MUSIC_THEME_RESTART                          ;#6C95: CA DA 6B
        ld      de,NOTE_PERIOD_TABLE                           ;#6C98: 11 89 70
        add     a,e                                            ;#6C9B: 83
        ld      e,a                                            ;#6C9C: 5F
        ld      a,0                                            ;#6C9D: 3E 00
        adc     a,d                                            ;#6C9F: 8A
        ld      d,a                                            ;#6CA0: 57
        ld      a,(de)                                         ;#6CA1: 1A
        ld      c,a                                            ;#6CA2: 4F
        inc     de                                             ;#6CA3: 13
        ld      a,(de)                                         ;#6CA4: 1A
        ld      b,a                                            ;#6CA5: 47
        ld      (PSG_MIRROR),bc                                ;#6CA6: ED 43 00 E5
        inc     hl                                             ;#6CAA: 23
        ld      e,(hl)                                         ;#6CAB: 5E
        inc     hl                                             ;#6CAC: 23
        ld      d,(hl)                                         ;#6CAD: 56
        ld      a,(de)                                         ;#6CAE: 1A
        inc     de                                             ;#6CAF: 13
        ld      (hl),d                                         ;#6CB0: 72
        dec     hl                                             ;#6CB1: 2B
        ld      (hl),e                                         ;#6CB2: 73
        ld      (PSG_MIRROR_VOL_A),a                           ;#6CB3: 32 08 E5
        inc     hl                                             ;#6CB6: 23
        inc     hl                                             ;#6CB7: 23
        ld      e,(hl)                                         ;#6CB8: 5E
        inc     hl                                             ;#6CB9: 23
        ld      d,(hl)                                         ;#6CBA: 56
        inc     hl                                             ;#6CBB: 23
        ld      a,(hl)                                         ;#6CBC: 7E
        dec     (hl)                                           ;#6CBD: 35
        jr      nz,MUSIC_THEME_LOAD_PITCH_B                    ;#6CBE: 20 15
        inc     de                                             ;#6CC0: 13
        inc     de                                             ;#6CC1: 13
        inc     de                                             ;#6CC2: 13
        ld      a,(de)                                         ;#6CC3: 1A
        ld      (hl),a                                         ;#6CC4: 77
        dec     de                                             ;#6CC5: 1B
        dec     hl                                             ;#6CC6: 2B
        ld      (hl),d                                         ;#6CC7: 72
        dec     hl                                             ;#6CC8: 2B
        ld      (hl),e                                         ;#6CC9: 73
        inc     hl                                             ;#6CCA: 23
        inc     hl                                             ;#6CCB: 23
        ld      de,SOUND_ENVELOPE_TABLE                        ;#6CCC: 11 F5 6C
        inc     hl                                             ;#6CCF: 23
        ld      (hl),e                                         ;#6CD0: 73
        inc     hl                                             ;#6CD1: 23
        ld      (hl),d                                         ;#6CD2: 72
        dec     hl                                             ;#6CD3: 2B
        dec     hl                                             ;#6CD4: 2B
MUSIC_THEME_LOAD_PITCH_B:
        ; MUSIC_THEME second-voice: look up pitch byte from second stream
        ld      a,(de)                                         ;#6CD5: 1A
        ld      de,NOTE_PERIOD_TABLE                           ;#6CD6: 11 89 70
        add     a,e                                            ;#6CD9: 83
        ld      e,a                                            ;#6CDA: 5F
        ld      a,0                                            ;#6CDB: 3E 00
        adc     a,d                                            ;#6CDD: 8A
        ld      d,a                                            ;#6CDE: 57
        ld      a,(de)                                         ;#6CDF: 1A
        ld      c,a                                            ;#6CE0: 4F
        inc     de                                             ;#6CE1: 13
        ld      a,(de)                                         ;#6CE2: 1A
        ld      b,a                                            ;#6CE3: 47
        ld      (PSG_MIRROR_PITCH_B),bc                        ;#6CE4: ED 43 02 E5
        inc     hl                                             ;#6CE8: 23
        ld      e,(hl)                                         ;#6CE9: 5E
        inc     hl                                             ;#6CEA: 23
        ld      d,(hl)                                         ;#6CEB: 56
        ld      a,(de)                                         ;#6CEC: 1A
        inc     de                                             ;#6CED: 13
        ld      (hl),d                                         ;#6CEE: 72
        dec     hl                                             ;#6CEF: 2B
        ld      (hl),e                                         ;#6CF0: 73
        ld      (PSG_MIRROR_VOL_B),a                           ;#6CF1: 32 09 E5
        ret                                                    ;#6CF4: C9

SOUND_ENVELOPE_TABLE:
        ; Initial sound envelope/volume curve
        dh      "0B0B0B0B0B0B0A0A0909080807070707"             ;#6CF5: 0B 0B 0B 0B 0B 0B 0A 0A 09 09 08 08 07 07 07 07
        dh      "07070707060605050504040404030303"             ;#6D05: 07 07 07 07 06 06 05 05 05 04 04 04 04 03 03 03
        dh      "03030202020202020101010101010101"             ;#6D15: 03 03 02 02 02 02 02 02 01 01 01 01 01 01 01 01
        dh      "01010101010101000000000000000000"             ;#6D25: 01 01 01 01 01 01 01 00 00 00 00 00 00 00 00 00

MUSIC_THEME_DURATIONS:
        ; Sound sub-table (referenced from music tick advance)
        dh      "0A0A0909070705050000000000000000"             ;#6D35: 0A 0A 09 09 07 07 05 05 00 00 00 00 00 00 00 00

SFX_SMOKE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_SMOKE)
        dh      "0C0C0C0C0C0C0C0C0C0C0C0C00000000"             ;#6D45: 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 0C 00 00 00 00

SFX_C_STAGE_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BANG/5)
        dh      "0F0D0B0A0A0A0A0A0A09080706050403"             ;#6D55: 0F 0D 0B 0A 0A 0A 0A 0A 0A 09 08 07 06 05 04 03
        dh      "02010000000000000000000000000000"             ;#6D65: 02 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00

SFX_BANG_VOLUME_ENVELOPE:
        ; Sound sub-table (referenced by SOUND_TICK_SFX_BONUS)
        dh      "080E0D0C0B0B0B0B0B0B0B0B0B0B0B0B"             ;#6D75: 08 0E 0D 0C 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B 0B
        dh      "0A0A0A0A0A0A0A0A0A0A090909090909"             ;#6D85: 0A 0A 0A 0A 0A 0A 0A 0A 0A 0A 09 09 09 09 09 09
        dh      "09090909080808080808080808080707"             ;#6D95: 09 09 09 09 08 08 08 08 08 08 08 08 08 08 07 07
        dh      "07070707070707070606060606060606"             ;#6DA5: 07 07 07 07 07 07 07 07 06 06 06 06 06 06 06 06
        dh      "060605050505050505050505040302FF"             ;#6DB5: 06 06 05 05 05 05 05 05 05 05 05 05 04 03 02 FF

MUSIC_THEME_VARIANT_VOICE0:
        ; Sound sub-table (referenced from music note advance)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#6DC5: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DC7: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DC9: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DCB: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DCD: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DCF: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DD1: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DD3: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DD5: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DD7: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DD9: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DDB: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DDD: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DDF: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DE1: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DE3: 38 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DE5: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DE7: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DE9: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DEB: 2A 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DED: 12 0C
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6DEF: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DF1: 2A 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6DF3: 2A 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DF5: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DF7: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DF9: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6DFB: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DFD: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6DFF: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E01: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E03: 38 0C
        db      0FFh    ; substream end                        ;#6E05: FF

MUSIC_THEME_VARIANT_VOICE0_2:
        ; Voice-0 2nd substream (after FF 6E05h); MUSIC_THEME_RESTART ptr
        NOTE    note=NOTE_O5_D, duration=19h                   ;#6E06: 5E 19
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E08: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6E0A: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#6E0C: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E0E: 58 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6E10: 5E 0C
        NOTE    note=NOTE_O5_E, duration=0Ch                   ;#6E12: 62 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E14: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E16: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E18: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E1A: 4A 0C
        NOTE    note=NOTE_O4_G, duration=30h                   ;#6E1C: 50 30
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E1E: 4A 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E20: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E22: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E24: 50 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E26: 58 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E28: 54 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E2A: 50 0C
        NOTE    note=NOTE_O4_A, duration=0Ch                   ;#6E2C: 54 0C
        NOTE    note=NOTE_O4_B, duration=0Ch                   ;#6E2E: 58 0C
        NOTE    note=NOTE_O4_G, duration=18h                   ;#6E30: 50 18
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6E32: 4A 0C
        NOTE    note=NOTE_O4_D, duration=30h                   ;#6E34: 46 30

MUSIC_THEME_VARIANT_VOICE1:
        ; Sound sub-table
        NOTE    note=NOTE_O4_G, duration=0Dh                   ;#6E36: 50 0D
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#6E38: 4C 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E3A: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6E3C: 50 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#6E3E: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E40: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E42: 42 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E44: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E46: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E48: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E4A: 38 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E4C: 42 0C
        NOTE    note=NOTE_O3_B, duration=0Ch                   ;#6E4E: 40 0C
        NOTE    note=NOTE_O3_G, duration=24h                   ;#6E50: 38 24
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E52: 42 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E54: 3E 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E56: 38 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#6E58: 34 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6E5A: 38 0C
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6E5C: 3E 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E5E: 42 0C
        NOTE    note=NOTE_O4_C_SHARP, duration=0Ch             ;#6E60: 44 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E62: 46 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#6E64: 4E 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6E66: 46 0C
        NOTE    note=NOTE_O4_C, duration=0Ch                   ;#6E68: 42 0C
        NOTE    note=NOTE_O3_B, duration=30h                   ;#6E6A: 40 30
        db      4,4,0Eh    ; last note pair + orphan byte (song ends via voice-0 FF) ;#6E6C: 04 04 0E

SFX_FLAG_STREAM_FLAG_GET:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_C                             ;#6E6F: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E70: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E71: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E72: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E73: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E74: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E75: 78
        SINGLE_NOTE note=NOTE_O5_C                             ;#6E76: 5A
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E77: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E78: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E79: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E7A: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E7B: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E7C: 78

SFX_FLAG_STREAM_BASE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O5_D_SHARP                       ;#6E7D: 60
        SINGLE_NOTE note=NOTE_O5_F                             ;#6E7E: 64
        SINGLE_NOTE note=NOTE_O5_G                             ;#6E7F: 68
        SINGLE_NOTE note=NOTE_O5_A_SHARP                       ;#6E80: 6E
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E81: 72
        SINGLE_NOTE note=NOTE_O6_D_SHARP                       ;#6E82: 78
        SINGLE_NOTE note=NOTE_O6_F                             ;#6E83: 7C
        db      0FFh    ; end of stream                        ;#6E84: FF

SFX_SMOKE_STREAM:
        ; Smoke SFX note stream (SFX_SMOKE); loaded by SFX_FLAG_CHECK_SMOKE at 6ABBh
        SINGLE_NOTE note=NOTE_O2_A_SHARP                       ;#6E85: 26
        SINGLE_NOTE note=NOTE_O2_B                             ;#6E86: 28
        SINGLE_NOTE note=NOTE_O3_C                             ;#6E87: 2A
        SINGLE_NOTE note=NOTE_O3_C_SHARP                       ;#6E88: 2C
        db      0FFh    ; end of stream                        ;#6E89: FF

SFX_FLAG_STREAM_FUEL_LOW:
        ; SFX sub-stream (fuel-low warning beep)
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8A: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8B: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8C: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8D: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8E: 44
        SINGLE_NOTE note=NOTE_O4_C_SHARP                       ;#6E8F: 44
        db      0FFh    ; end of stream                        ;#6E90: FF

SFX_FLAG_STREAM_EXTRA_LIFE:
        ; SFX stream (referenced by SOUND_TICK_SFX_FLAG)
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E91: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E92: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E93: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E94: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E95: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E96: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E97: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E98: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E99: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E9A: 76
        SINGLE_NOTE note=NOTE_O6_C                             ;#6E9B: 72
        SINGLE_NOTE note=NOTE_O6_D                             ;#6E9C: 76
        db      0FFh    ; end of stream                        ;#6E9D: FF

MUSIC_STAGE_CLEAR_STREAM_VOICE_0:
        ; Music channel C voice 0 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#6E9E: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_1:
        ; Music channel C voice 1 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=8                     ;#6EA0: 00 08

MUSIC_STAGE_CLEAR_STREAM_VOICE_2:
        ; Music channel C voice 2 header; loaded by MUSIC_STAGE_CLEAR_INIT
        NOTE    note=NOTE_REST, duration=9                     ;#6EA2: 00 09
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#6EA4: 56 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6EA6: 5E 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#6EA8: 64 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#6EAA: 5A 0C
        NOTE    note=NOTE_O5_D_SHARP, duration=0Ch             ;#6EAC: 60 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6EAE: 5E 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=0Ch             ;#6EB0: 6E 0C
        NOTE    note=NOTE_REST, duration=10h                   ;#6EB2: 00 10
        db      0FFh    ; substream end                        ;#6EB4: FF

SFX_BONUS_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_BONUS)
        NOTE    note=NOTE_O5_G, duration=1                     ;#6EB5: 68 01
        NOTE    note=NOTE_O5_A, duration=5                     ;#6EB7: 6C 05
        NOTE    note=NOTE_O5_B, duration=5                     ;#6EB9: 70 05
        NOTE    note=NOTE_O6_C, duration=5                     ;#6EBB: 72 05
        NOTE    note=NOTE_O6_D, duration=5                     ;#6EBD: 76 05
        NOTE    note=NOTE_O6_E, duration=5                     ;#6EBF: 7A 05
        NOTE    note=NOTE_O6_F_SHARP, duration=5               ;#6EC1: 7E 05
        NOTE    note=NOTE_O6_G, duration=5                     ;#6EC3: 80 05
        db      0FFh    ; substream end                        ;#6EC5: FF

SFX_C_STAGE_STREAM:
        ; SFX stream (referenced by SOUND_TICK_SFX_C_STAGE)
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6EC6: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#6EC8: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#6ECA: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#6ECC: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#6ECE: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6ED0: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6ED2: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6ED4: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6ED6: 34 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6ED8: 38 06
        NOTE    note=NOTE_REST, duration=6                     ;#6EDA: 00 06
        NOTE    note=NOTE_O3_A_SHARP, duration=0Ch             ;#6EDC: 3E 0C
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EDE: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6EE0: 34 06
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6EE2: 20 0C
        NOTE    note=NOTE_O2_D, duration=6                     ;#6EE4: 16 06
        NOTE    note=NOTE_O2_F, duration=6                     ;#6EE6: 1C 06
        NOTE    note=NOTE_O2_G, duration=6                     ;#6EE8: 20 06
        NOTE    note=NOTE_O2_A_SHARP, duration=6               ;#6EEA: 26 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6EEC: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6EEE: 2E 06
        NOTE    note=NOTE_O3_G, duration=6                     ;#6EF0: 38 06
        NOTE    note=NOTE_O3_F, duration=6                     ;#6EF2: 34 06
        NOTE    note=NOTE_O3_C, duration=6                     ;#6EF4: 2A 06
        NOTE    note=NOTE_O3_D, duration=6                     ;#6EF6: 2E 06
        NOTE    note=NOTE_O2_A_SHARP, duration=0Ch             ;#6EF8: 26 0C
        db      0FFh    ; substream end                        ;#6EFA: FF

MUSIC_THEME_VOICE0_BASELINE:
        ; Music data stream (channel A track)
        NOTE    note=NOTE_O2_G, duration=0Dh                   ;#6EFB: 20 0D
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6EFD: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6EFF: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F01: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F03: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F05: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F07: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F09: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F0B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F0D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F0F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F11: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F13: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F15: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F17: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F19: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F1B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F1D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F1F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F21: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F23: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F25: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F27: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F29: 38 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F2B: 16 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F2D: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F2F: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F31: 2E 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F33: 2E 0C
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F35: 16 0C
        NOTE    note=NOTE_O2_E, duration=0Ch                   ;#6F37: 1A 0C
        NOTE    note=NOTE_O2_F_SHARP, duration=0Ch             ;#6F39: 1E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F3B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F3D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F3F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F41: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F43: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F45: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F47: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F49: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F4B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F4D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F4F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F51: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F53: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F55: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F57: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F59: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F5B: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F5D: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F5F: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F61: 38 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F63: 20 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F65: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F67: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F69: 38 0C
        NOTE    note=NOTE_O2_C, duration=1                     ;#6F6B: 12 01
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#6F6D: 12 0C
        NOTE    note=NOTE_O3_C, duration=0Ch                   ;#6F6F: 2A 0C
        NOTE    note=NOTE_O2_D, duration=1                     ;#6F71: 16 01
        NOTE    note=NOTE_O2_D, duration=0Ch                   ;#6F73: 16 0C
        NOTE    note=NOTE_O3_D, duration=0Ch                   ;#6F75: 2E 0C
        NOTE    note=NOTE_O2_G, duration=0Ch                   ;#6F77: 20 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F79: 38 0C
        NOTE    note=NOTE_O3_G, duration=0Ch                   ;#6F7B: 38 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6F7D: 00 0C
        db      0FFh    ; substream end                        ;#6F7F: FF

MUSIC_THEME_VOICE1_BASELINE:
        ; Music data stream (channel A alt)
        NOTE    note=NOTE_O4_G, duration=0Bh                   ;#6F80: 50 0B
        NOTE    note=NOTE_REST, duration=2                     ;#6F82: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F84: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6F86: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6F88: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F8A: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6F8C: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#6F8E: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6F90: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6F92: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F94: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6F96: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6F98: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6F9A: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6F9C: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#6F9E: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FA0: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FA2: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FA4: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FA6: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FA8: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FAA: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#6FAC: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#6FAE: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#6FB0: 5C 0C
        NOTE    note=NOTE_O5_D, duration=0Ch                   ;#6FB2: 5E 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FB4: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FB6: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FB8: 5C 06
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FBA: 5E 06
        NOTE    note=NOTE_O5_C_SHARP, duration=6               ;#6FBC: 5C 06
        NOTE    note=NOTE_O5_D, duration=4                     ;#6FBE: 5E 04
        NOTE    note=NOTE_REST, duration=2                     ;#6FC0: 00 02
        NOTE    note=NOTE_O5_D, duration=14h                   ;#6FC2: 5E 14
        NOTE    note=NOTE_REST, duration=4                     ;#6FC4: 00 04
        NOTE    note=NOTE_O5_D, duration=6                     ;#6FC6: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#6FC8: 5A 06
        NOTE    note=NOTE_O4_B, duration=6                     ;#6FCA: 58 06
        NOTE    note=NOTE_O4_A, duration=6                     ;#6FCC: 54 06
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FCE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FD0: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FD2: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FD4: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FD6: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FD8: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6FDA: 00 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=18h             ;#6FDC: 56 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FDE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FE0: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FE2: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FE4: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FE6: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FE8: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#6FEA: 00 0C
        NOTE    note=NOTE_O4_E, duration=18h                   ;#6FEC: 4A 18
        NOTE    note=NOTE_O4_G, duration=0Ah                   ;#6FEE: 50 0A
        NOTE    note=NOTE_REST, duration=2                     ;#6FF0: 00 02
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FF2: 50 0C
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#6FF4: 4A 0C
        NOTE    note=NOTE_O4_D, duration=0Ch                   ;#6FF6: 46 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#6FF8: 50 0C
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#6FFA: 56 0C
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#6FFC: 5A 0C
        NOTE    note=NOTE_O5_C_SHARP, duration=0Ch             ;#6FFE: 5C 0C
        NOTE    note=NOTE_O5_G, duration=0Ch                   ;#7000: 68 0C
        NOTE    note=NOTE_O5_D, duration=6                     ;#7002: 5E 06
        NOTE    note=NOTE_O5_C, duration=6                     ;#7004: 5A 06
        NOTE    note=NOTE_O4_A_SHARP, duration=0Ch             ;#7006: 56 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#7008: 50 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#700A: 4C 0C
        NOTE    note=NOTE_O4_F_SHARP, duration=0Ch             ;#700C: 4E 0C
        NOTE    note=NOTE_O4_G, duration=0Ch                   ;#700E: 50 0C
        NOTE    note=NOTE_REST, duration=0Ch                   ;#7010: 00 0C

MUSIC_OPENING_VOICE_2:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=0Dh                   ;#7012: 5A 0D
        NOTE    note=NOTE_O5_D, duration=4                     ;#7014: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#7016: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#7018: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#701A: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#701C: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#701E: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#7020: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#7022: 64 0C
        NOTE    note=NOTE_O5_G_SHARP, duration=10h             ;#7024: 6A 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#7026: 64 04
        NOTE    note=NOTE_O5_D, duration=10h                   ;#7028: 5E 10
        NOTE    note=NOTE_O5_C, duration=0Ch                   ;#702A: 5A 0C
        NOTE    note=NOTE_O5_D, duration=4                     ;#702C: 5E 04
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#702E: 64 0C
        NOTE    note=NOTE_O5_A, duration=10h                   ;#7030: 6C 10
        NOTE    note=NOTE_O5_F, duration=4                     ;#7032: 64 04
        NOTE    note=NOTE_O5_A, duration=0Ch                   ;#7034: 6C 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#7036: 6E 04
        NOTE    note=NOTE_O6_C, duration=0Ch                   ;#7038: 72 0C
        NOTE    note=NOTE_O5_A_SHARP, duration=4               ;#703A: 6E 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#703C: 6A 0C
        NOTE    note=NOTE_O5_F, duration=4                     ;#703E: 64 04
        NOTE    note=NOTE_O5_G_SHARP, duration=0Ch             ;#7040: 6A 0C
        NOTE    note=NOTE_O5_F, duration=0Ch                   ;#7042: 64 0C

MUSIC_OPENING_VOICE_1:
        ; Music data stream (channel C)
        NOTE    note=NOTE_O5_C, duration=1Dh                   ;#7044: 5A 1D
        NOTE    note=NOTE_O4_A, duration=10h                   ;#7046: 54 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#7048: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#704A: 5A 1C
        NOTE    note=NOTE_O4_G_SHARP, duration=10h             ;#704C: 52 10
        NOTE    note=NOTE_O4_F, duration=14h                   ;#704E: 4C 14
        NOTE    note=NOTE_O5_C, duration=1Ch                   ;#7050: 5A 1C
        NOTE    note=NOTE_O4_A, duration=10h                   ;#7052: 54 10
        NOTE    note=NOTE_O4_F, duration=10h                   ;#7054: 4C 10
        NOTE    note=NOTE_O5_C, duration=4                     ;#7056: 5A 04
        NOTE    note=NOTE_O4_G_SHARP, duration=0Ch             ;#7058: 52 0C
        NOTE    note=NOTE_O4_F, duration=4                     ;#705A: 4C 04
        NOTE    note=NOTE_O4_D_SHARP, duration=0Ch             ;#705C: 48 0C
        NOTE    note=NOTE_O4_C, duration=4                     ;#705E: 42 04
        NOTE    note=NOTE_O4_E, duration=0Ch                   ;#7060: 4A 0C
        NOTE    note=NOTE_O4_F, duration=0Ch                   ;#7062: 4C 0C

MUSIC_OPENING_VOICE_0:
        ; Music data stream (channel B/C)
        NOTE    note=NOTE_O2_F, duration=11h                   ;#7064: 1C 11
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7066: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7068: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#706A: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#706C: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#706E: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7070: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7072: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7074: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#7076: 34 10
        NOTE    note=NOTE_O2_F, duration=10h                   ;#7078: 1C 10
        NOTE    note=NOTE_O3_F, duration=10h                   ;#707A: 34 10
        NOTE    note=NOTE_O1_A_SHARP, duration=0Ch             ;#707C: 0E 0C
        NOTE    note=NOTE_O2_A_SHARP, duration=4               ;#707E: 26 04
        NOTE    note=NOTE_O2_C, duration=0Ch                   ;#7080: 12 0C
        NOTE    note=NOTE_O3_C, duration=4                     ;#7082: 2A 04
        NOTE    note=NOTE_O2_F, duration=0Ch                   ;#7084: 1C 0C
        NOTE    note=NOTE_O3_F, duration=0Ch                   ;#7086: 34 0C
        db      0FFh    ; substream end                        ;#7088: FF

NOTE_PERIOD_TABLE:
        ; PSG tone-period entries (73 x 2 bytes) indexed by note byte
        ; NOTE_PERIOD_TABLE — 73 entries x 2 bytes (146 bytes total). Indexed by note
        ; byte from music data streams. Each 16-bit entry is a PSG tone-period value
        ; (12-bit; high 4 bits ignored by PSG). Covers ~6 octaves of musical pitch
        ; range.
        dw      0     ; rest                                   ;#7089: 00 00
        dw      0A88h  ;    41.5 Hz  O1 E                      ;#708B: 88 0A
        dw      9F0h   ;    44.0 Hz  O1 F                      ;#708D: F0 09
        dw      960h   ;    46.6 Hz  O1 F#                     ;#708F: 60 09
        dw      8DCh   ;    49.3 Hz  O1 G                      ;#7091: DC 08
        dw      85Ch   ;    52.3 Hz  O1 G#                     ;#7093: 5C 08
        dw      7E4h   ;    55.4 Hz  O1 A                      ;#7095: E4 07
        dw      770h   ;    58.8 Hz  O1 A#                     ;#7097: 70 07
        dw      708h   ;    62.1 Hz  O1 B                      ;#7099: 08 07
        dw      6A0h   ;    66.0 Hz  O2 C                      ;#709B: A0 06
        dw      644h   ;    69.7 Hz  O2 C#                     ;#709D: 44 06
        dw      5E8h   ;    74.0 Hz  O2 D                      ;#709F: E8 05
        dw      594h   ;    78.3 Hz  O2 D#                     ;#70A1: 94 05
        dw      544h   ;    83.0 Hz  O2 E                      ;#70A3: 44 05
        dw      4F8h   ;    87.9 Hz  O2 F                      ;#70A5: F8 04
        dw      4B0h   ;    93.2 Hz  O2 F#                     ;#70A7: B0 04
        dw      46Eh   ;    98.6 Hz  O2 G                      ;#70A9: 6E 04
        dw      42Eh   ;   104.5 Hz  O2 G#                     ;#70AB: 2E 04
        dw      3F2h   ;   110.8 Hz  O2 A                      ;#70AD: F2 03
        dw      3B8h   ;   117.5 Hz  O2 A#                     ;#70AF: B8 03
        dw      384h   ;   124.3 Hz  O2 B                      ;#70B1: 84 03
        dw      350h   ;   131.9 Hz  O3 C                      ;#70B3: 50 03
        dw      322h   ;   139.5 Hz  O3 C#                     ;#70B5: 22 03
        dw      2F4h   ;   148.0 Hz  O3 D                      ;#70B7: F4 02
        dw      2CAh   ;   156.7 Hz  O3 D#                     ;#70B9: CA 02
        dw      2A2h   ;   166.0 Hz  O3 E                      ;#70BB: A2 02
        dw      27Ch   ;   175.9 Hz  O3 F                      ;#70BD: 7C 02
        dw      258h   ;   186.4 Hz  O3 F#                     ;#70BF: 58 02
        dw      237h   ;   197.3 Hz  O3 G                      ;#70C1: 37 02
        dw      217h   ;   209.1 Hz  O3 G#                     ;#70C3: 17 02
        dw      1F9h   ;   221.5 Hz  O3 A                      ;#70C5: F9 01
        dw      1DCh   ;   235.0 Hz  O3 A#                     ;#70C7: DC 01
        dw      1C2h   ;   248.6 Hz  O3 B                      ;#70C9: C2 01
        dw      1A8h   ;   263.8 Hz  O4 C                      ;#70CB: A8 01
        dw      191h   ;   279.0 Hz  O4 C#                     ;#70CD: 91 01
        dw      17Ah   ;   295.9 Hz  O4 D                      ;#70CF: 7A 01
        dw      165h   ;   313.3 Hz  O4 D#                     ;#70D1: 65 01
        dw      151h   ;   331.9 Hz  O4 E                      ;#70D3: 51 01
        dw      13Eh   ;   351.8 Hz  O4 F                      ;#70D5: 3E 01
        dw      12Ch   ;   372.9 Hz  O4 F#                     ;#70D7: 2C 01
        dw      11Bh   ;   395.3 Hz  O4 G                      ;#70D9: 1B 01
        dw      10Bh   ;   419.0 Hz  O4 G#                     ;#70DB: 0B 01
        dw      0FCh   ;   443.9 Hz  O4 A                      ;#70DD: FC 00
        dw      0EEh   ;   470.0 Hz  O4 A#                     ;#70DF: EE 00
        dw      0E1h   ;   497.2 Hz  O4 B                      ;#70E1: E1 00
        dw      0D4h   ;   527.6 Hz  O5 C                      ;#70E3: D4 00
        dw      0C8h   ;   559.3 Hz  O5 C#                     ;#70E5: C8 00
        dw      0BDh   ;   591.9 Hz  O5 D                      ;#70E7: BD 00
        dw      0B2h   ;   628.4 Hz  O5 D#                     ;#70E9: B2 00
        dw      0A8h   ;   665.8 Hz  O5 E                      ;#70EB: A8 00
        dw      9Fh    ;   703.5 Hz  O5 F                      ;#70ED: 9F 00
        dw      96h    ;   745.7 Hz  O5 F#                     ;#70EF: 96 00
        dw      8Dh    ;   793.3 Hz  O5 G                      ;#70F1: 8D 00
        dw      85h    ;   841.1 Hz  O5 G#                     ;#70F3: 85 00
        dw      7Eh    ;   887.8 Hz  O5 A                      ;#70F5: 7E 00
        dw      77h    ;   940.0 Hz  O5 A#                     ;#70F7: 77 00
        dw      70h    ;   998.8 Hz  O5 B                      ;#70F9: 70 00
        dw      6Ah    ;  1055.3 Hz  O6 C                      ;#70FB: 6A 00
        dw      64h    ;  1118.6 Hz  O6 C#                     ;#70FD: 64 00
        dw      5Eh    ;  1190.0 Hz  O6 D                      ;#70FF: 5E 00
        dw      59h    ;  1256.9 Hz  O6 D#                     ;#7101: 59 00
        dw      54h    ;  1331.7 Hz  O6 E                      ;#7103: 54 00
        dw      4Fh    ;  1416.0 Hz  O6 F                      ;#7105: 4F 00
        dw      4Bh    ;  1491.5 Hz  O6 F#                     ;#7107: 4B 00
        dw      46h    ;  1598.0 Hz  O6 G                      ;#7109: 46 00
        dw      42h    ;  1694.9 Hz  O6 G#                     ;#710B: 42 00
        dw      3Fh    ;  1775.6 Hz  O6 A                      ;#710D: 3F 00
        dw      3Bh    ;  1895.9 Hz  O6 A#                     ;#710F: 3B 00
        dw      38h    ;  1997.5 Hz  O6 B                      ;#7111: 38 00
        dw      35h    ;  2110.6 Hz  O7 C                      ;#7113: 35 00
        dw      32h    ;  2237.2 Hz  O7 C#                     ;#7115: 32 00
        dw      2Fh    ;  2380.0 Hz  O7 D                      ;#7117: 2F 00
        dw      2Ch    ;  2542.3 Hz  O7 D#                     ;#7119: 2C 00

TICK_STAGE_TIMER:
        ; Dec STAGE_TIMER_INNER; at 0 reload STAGE_TIMER_RELOAD, dec STAGE_TIMER_OUTER
        ; TICK_STAGE_TIMER is the two-stage countdown: dec STAGE_TIMER_INNER
        ; (STAGE_TIMER_INNER). If non-zero, return. Else reload from STAGE_TIMER_RELOAD
        ; (STAGE_TIMER_RELOAD) and dec STAGE_TIMER_OUTER. Used as a sub-frame pacing
        ; tick by various game-flow states.
        ld      hl,STAGE_TIMER_INNER                           ;#711B: 21 37 E0
        dec     (hl)                                           ;#711E: 35
        ret     nz                                             ;#711F: C0
        ld      a,(STAGE_TIMER_RELOAD)                         ;#7120: 3A 3A E0
        ld      (hl),a                                         ;#7123: 77
TICK_FUEL_REFRESH:
        ; Dec STAGE_TIMER_OUTER (reload 0Ah); on rollover, refresh fuel gauge cells
        ; TICK_FUEL_REFRESH dec STAGE_TIMER_OUTER (the outer timer) with auto-reload to
        ; 0Ah. On rollover, refreshes the fuel gauge cells in VRAM via BIOS_WRTVRM if
        ; FUEL_LEVEL is in the low range. Called from DRAIN_FUEL_* variants during
        ; stage-clear bonus animation.
        ld      hl,STAGE_TIMER_OUTER                           ;#7124: 21 38 E0
        dec     (hl)                                           ;#7127: 35
        ret     nz                                             ;#7128: C0
        ld      (hl),0Ah                                       ;#7129: 36 0A
        inc     hl                                             ;#712B: 23
        ld      a,(hl)                                         ;#712C: 7E
        cp      0Ah                                            ;#712D: FE 0A
        jr      nc,FUEL_TICK_GATE_RUNOUT                       ;#712F: 30 2C
        and     a                                              ;#7131: A7
        ret     z                                              ;#7132: C8
        LOAD_VRAM_ADDRESS hl, 79Ch                             ;#7133: 21 9C 07
        ld      a,81h                                          ;#7136: 3E 81
        call    BIOS_WRTVRM                                    ;#7138: CD 4D 00
        LOAD_VRAM_ADDRESS hl, 79Dh                             ;#713B: 21 9D 07
        ld      a,81h                                          ;#713E: 3E 81
        call    BIOS_WRTVRM                                    ;#7140: CD 4D 00
        ld      hl,FUEL_LEVEL                                  ;#7143: 21 39 E0
        ld      a,(SOUND_STATE_BANG_TRIGGER)                   ;#7146: 3A 61 E5
        and     a                                              ;#7149: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#714A: 20 11
        ld      a,(STAGE_CLEAR_FLAG)                           ;#714C: 3A 2F E0
        and     a                                              ;#714F: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#7150: 20 0B
        ld      a,(PLAYER_DEAD_FLAG)                           ;#7152: 3A 3B E0
        and     a                                              ;#7155: A7
        jr      nz,FUEL_TICK_GATE_RUNOUT                       ;#7156: 20 05
        ld      a,1                                            ;#7158: 3E 01
        ld      (SOUND_STATE_BANG_TRIGGER),a                   ;#715A: 32 61 E5
FUEL_TICK_GATE_RUNOUT:
        ; Run-out gate: arms PLAYER_MOVE_GATE when fuel-tick timer expires
        dec     (hl)                                           ;#715D: 35
        jr      nz,UPDATE_FUEL_GAUGE                           ;#715E: 20 05
        ld      a,1                                            ;#7160: 3E 01
        ld      (PLAYER_MOVE_GATE),a                           ;#7162: 32 45 E0
UPDATE_FUEL_GAUGE:
        ; Render 8-tile fuel bar from FUEL_LEVEL; LDIRVM to VRAM 04D7h + mirror 14D7h
        ; UPDATE_FUEL_GAUGE renders the fuel bar as 8 tile codes in
        ; FUEL_GAUGE_BUFFER-E1E7h then LDIRVMs them to VRAM 04D7h (and bank-2 mirror
        ; 14D7h). Multi-segment fill: EEh = full segment, E7h = empty, the partial
        ; segment uses an intermediate tile encoding the fractional fill.
        ld      hl,FUEL_GAUGE_BUFFER                           ;#7165: 21 E0 E1
        ld      de,FUEL_GAUGE_BUFFER_TAIL                      ;#7168: 11 E1 E1
        ld      bc,7                                           ;#716B: 01 07 00
        ld      (hl),40h                                       ;#716E: 36 40
        ldir                                                   ;#7170: ED B0
        ld      a,(FUEL_LEVEL)                                 ;#7172: 3A 39 E0
        sub     7                                              ;#7175: D6 07
        jr      nc,FUEL_BAR_SET_HEAD                           ;#7177: 30 06
        add     a,0EFh                                         ;#7179: C6 EF
        ld      (hl),a                                         ;#717B: 77
        jp      FUEL_BAR_UPLOAD                                ;#717C: C3 8D 71

FUEL_BAR_SET_HEAD:
        ; Set bar head tile (EEh = full segment)
        ld      (hl),0EEh                                      ;#717F: 36 EE
FUEL_BAR_FILL_LOOP:
        ; Fill bar middle with full segments via dec hl loop
        dec     hl                                             ;#7181: 2B
        sub     8                                              ;#7182: D6 08
        jr      c,FUEL_BAR_TAIL_PARTIAL                        ;#7184: 38 04
        ld      (hl),0E7h                                      ;#7186: 36 E7
        jr      FUEL_BAR_FILL_LOOP                             ;#7188: 18 F7

FUEL_BAR_TAIL_PARTIAL:
        ; Tail partial: paint a fractional segment as the bar shrinks
        add     a,0E8h                                         ;#718A: C6 E8
        ld      (hl),a                                         ;#718C: 77
FUEL_BAR_UPLOAD:
        ; LDIRVM the 8 fuel-bar tile codes to VRAM 04D7h
        LOAD_VRAM_ADDRESS de, 4D7h                             ;#718D: 11 D7 04
        ld      hl,FUEL_GAUGE_BUFFER                           ;#7190: 21 E0 E1
        ld      bc,8                                           ;#7193: 01 08 00
        call    BIOS_LDIRVM                                    ;#7196: CD 5C 00
        ; fuel-gauge mirror → bank-B 14D7h
        ld      hl,FUEL_GAUGE_BUFFER                           ;#7199: 21 E0 E1
        LOAD_VRAM_ADDRESS de, 14D7h                            ;#719C: 11 D7 14
        ld      bc,8                                           ;#719F: 01 08 00
        jp      BIOS_LDIRVM                                    ;#71A2: C3 5C 00

LOAD_STAGE_PARAMS:
        ; Look up per-stage parameters from STAGE_PARAM_TABLE + STAGE_DIFFICULTY_TABLE
        ; LOAD_STAGE_PARAMS reads STAGE_PALETTE_INDEX, normalizes (stages >=14h wrap to
        ; 10h-13h), and indexes STAGE_PARAM_TABLE (4-byte records) to load
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD (reload), STAGE_DIFFICULTY_INDEX
        ; (subindex), and one more byte. Then uses STAGE_DIFFICULTY_INDEX to index
        ; STAGE_DIFFICULTY_TABLE (STAGE_DIFFICULTY_TABLE), offset by STAGE_DIFFICULTY (3
        ; difficulty tiers selected at thresholds 6 and 3), loading (ENEMY_STEP_SPEED) +
        ; (SCROLL_LIMIT_LO).
        ld      a,(STAGE_PALETTE_INDEX)                        ;#71A5: 3A 30 E0
        cp      14h                                            ;#71A8: FE 14
        jr      c,LOAD_STAGE_LOOKUP                            ;#71AA: 38 04
        and     3                                              ;#71AC: E6 03
        add     a,10h                                          ;#71AE: C6 10
LOAD_STAGE_LOOKUP:
        ; Lookup row: index STAGE_PARAM_TABLE by (palette*4) and read 4 fields
        dec     a                                              ;#71B0: 3D
        add     a,a                                            ;#71B1: 87
        add     a,a                                            ;#71B2: 87
        ld      c,a                                            ;#71B3: 4F
        ld      b,0                                            ;#71B4: 06 00
        ld      hl,STAGE_PARAM_TABLE                           ;#71B6: 21 02 72
        add     hl,bc                                          ;#71B9: 09
        ld      a,(hl)                                         ;#71BA: 7E
        ld      (ROCK_SPAWN_COUNT),a                           ;#71BB: 32 1C E0
        inc     hl                                             ;#71BE: 23
        ld      a,(hl)                                         ;#71BF: 7E
        ld      (STAGE_ENEMY_SEED_LEN),a                       ;#71C0: 32 40 E0
        inc     hl                                             ;#71C3: 23
        ld      a,(hl)                                         ;#71C4: 7E
        ld      (STAGE_TIMER_RELOAD),a                         ;#71C5: 32 3A E0
        inc     hl                                             ;#71C8: 23
        ld      a,(hl)                                         ;#71C9: 7E
        ld      (STAGE_DIFFICULTY_INDEX),a                     ;#71CA: 32 3F E0
LOAD_STAGE_DIFFICULTY_TIER:
        ; Choose difficulty tier based on STAGE_DIFFICULTY (>=6 / >=3 / else)
        ld      a,(STAGE_DIFFICULTY_INDEX)                     ;#71CD: 3A 3F E0
        push    hl                                             ;#71D0: E5
        ld      hl,STAGE_DIFFICULTY_TABLE                      ;#71D1: 21 4E 72
        add     a,l                                            ;#71D4: 85
        ld      l,a                                            ;#71D5: 6F
        ld      a,0                                            ;#71D6: 3E 00
        adc     a,h                                            ;#71D8: 8C
        ld      h,a                                            ;#71D9: 67
        ld      a,(STAGE_DIFFICULTY)                           ;#71DA: 3A 2E E0
        cp      6                                              ;#71DD: FE 06
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#71DF: 30 0C
        inc     hl                                             ;#71E1: 23
        inc     hl                                             ;#71E2: 23
        inc     hl                                             ;#71E3: 23
        inc     hl                                             ;#71E4: 23
        cp      3                                              ;#71E5: FE 03
        jr      nc,LOAD_STAGE_READ_PARAMS                      ;#71E7: 30 04
        inc     hl                                             ;#71E9: 23
        inc     hl                                             ;#71EA: 23
        inc     hl                                             ;#71EB: 23
        inc     hl                                             ;#71EC: 23
LOAD_STAGE_READ_PARAMS:
        ; Read 4 bytes into (ENEMY_STEP_SPEED) and (SCROLL_LIMIT_LO) as two 16-bit pairs
        ld      a,(hl)                                         ;#71ED: 7E
        ld      (ENEMY_STEP_SPEED),a                           ;#71EE: 32 41 E0
        inc     hl                                             ;#71F1: 23
        ld      a,(hl)                                         ;#71F2: 7E
        ld      (ENEMY_STEP_SPEED_HI),a                        ;#71F3: 32 42 E0
        inc     hl                                             ;#71F6: 23
        ld      a,(hl)                                         ;#71F7: 7E
        ld      (SCROLL_LIMIT_LO),a                            ;#71F8: 32 43 E0
        inc     hl                                             ;#71FB: 23
        ld      a,(hl)                                         ;#71FC: 7E
        ld      (SCROLL_LIMIT_HI),a                            ;#71FD: 32 44 E0
        pop     hl                                             ;#7200: E1
        ret                                                    ;#7201: C9

STAGE_PARAM_TABLE:
        ; Per-stage 4-byte records: stage N indexes (N-1)*4 (stages >=14h wrap to 10h-13h)
        ; STAGE_PARAM_TABLE has 19 stage records of 4 bytes each. Stage N (N=1..19)
        ; reads bytes (N-1)*4..(N-1)*4+3 → loaded into ROCK_SPAWN_ COUNT,
        ; STAGE_ENEMY_SEED_LEN, STAGE_TIMER_RELOAD, and STAGE_DIFFICULTY_INDEX. Stages
        ; 0x14h and above wrap to entries 0x10h..0x13h (4-stage cycle).
        STAGE_PARAMS rocks=0, enemies=2, reload=9, difficulty=0  ;#7202: 00 20 09 00
        STAGE_PARAMS rocks=2, enemies=3, reload=9, difficulty=1  ;#7206: 02 30 09 0C
        STAGE_PARAMS rocks=5, enemies=7, reload=7, difficulty=2  ;#720A: 05 70 07 18
        STAGE_PARAMS rocks=4, enemies=3, reload=8, difficulty=3  ;#720E: 04 30 08 24
        STAGE_PARAMS rocks=5, enemies=4, reload=8, difficulty=4  ;#7212: 05 40 08 30
        STAGE_PARAMS rocks=6, enemies=5, reload=7, difficulty=5  ;#7216: 06 50 07 3C
        STAGE_PARAMS rocks=7, enemies=7, reload=7, difficulty=6  ;#721A: 07 70 07 48
        STAGE_PARAMS rocks=5, enemies=5, reload=7, difficulty=7  ;#721E: 05 50 07 54
        STAGE_PARAMS rocks=6, enemies=5, reload=6, difficulty=8  ;#7222: 06 50 06 60
        STAGE_PARAMS rocks=7, enemies=5, reload=6, difficulty=9  ;#7226: 07 50 06 6C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#722A: 0A 70 06 78
        STAGE_PARAMS rocks=6, enemies=6, reload=6, difficulty=11  ;#722E: 06 60 06 84
        STAGE_PARAMS rocks=7, enemies=6, reload=6, difficulty=12  ;#7232: 07 60 06 90
        STAGE_PARAMS rocks=8, enemies=7, reload=6, difficulty=13  ;#7236: 08 70 06 9C
        STAGE_PARAMS rocks=10, enemies=7, reload=6, difficulty=10  ;#723A: 0A 70 06 78
        STAGE_PARAMS rocks=8, enemies=7, reload=5, difficulty=13  ;#723E: 08 70 05 9C
        STAGE_PARAMS rocks=9, enemies=7, reload=5, difficulty=14  ;#7242: 09 70 05 A8
        STAGE_PARAMS rocks=10, enemies=7, reload=5, difficulty=14  ;#7246: 0A 70 05 A8
        STAGE_PARAMS rocks=12, enemies=7, reload=5, difficulty=15  ;#724A: 0C 70 05 B4

STAGE_DIFFICULTY_TABLE:
        ; 16 records x 12 bytes (3 tiers x 4 bytes), ending just before PADDING
        ; STAGE_DIFFICULTY_TABLE has 16 stage records, each containing 3 difficulty
        ; tiers (4 bytes each = 12 bytes per record, 192 total). LOAD_STAGE_PARAMS uses
        ; STAGE_DIFFICULTY against thresholds 6 and 3 to pick the tier — enemies get
        ; faster/smarter at later stages. STAGE_DIFFICULTY_INDEX selects which record to
        ; use and ranges 0..180 in steps of 12.
        dh      "00030003200300032003000320030003"             ;#724E: 00 03 00 03 20 03 00 03 20 03 00 03 20 03 00 03
        dh      "30030003300300030000000400000004"             ;#725E: 30 03 00 03 30 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004200300034003000340030003"             ;#726E: 00 00 00 04 20 03 00 03 40 03 00 03 40 03 00 03
        dh      "40030003500300035003000350030003"             ;#727E: 40 03 00 03 50 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003600300030000000400000004"             ;#728E: 60 03 00 03 60 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#729E: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "50030003600300036003000350030003"             ;#72AE: 50 03 00 03 60 03 00 03 60 03 00 03 50 03 00 03
        dh      "70030003700300030000000400000004"             ;#72BE: 70 03 00 03 70 03 00 03 00 00 00 04 00 00 00 04
        dh      "00000004400300035003000350030003"             ;#72CE: 00 00 00 04 40 03 00 03 50 03 00 03 50 03 00 03
        dh      "60030003700300037003000370030003"             ;#72DE: 60 03 00 03 70 03 00 03 70 03 00 03 70 03 00 03
        dh      "70030003700300038003000380030003"             ;#72EE: 70 03 00 03 70 03 00 03 80 03 00 03 80 03 00 03
        dh      "80030003000000040000000400000004"             ;#72FE: 80 03 00 03 00 00 00 04 00 00 00 04 00 00 00 04

PADDING:
        ; 2290 bytes of 0FFh padding between STAGE_DIFFICULTY_TABLE and MAZE_BITMAP_0
        ds      2290,0FFh                                      ;#730E

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
