# Rally-X

Complete disassembly of the MSX game by Namcot, 1984.

These sources produce bit-perfect binaries of three known official releases. 

Compile using [sjasmplus](https://github.com/z00m128/sjasmplus).

## Files

| File            | ROM variant     | MD5        |
| --------------- | --------------- | ---------- |
| `rallyx_v1.asm` | First release   | `901c8a84` |
| `rallyx_v2.asm` | Second release  | `679f1d3a` |
| `rallyx_v3.asm` | Third release   | `3e5900c0` |

## What's in here

The source has symbolic names for all routines and data. I tried to add
semantic information using macros, in order to explain most magic numbers.

## Differences between releases

### First release

- ID string: "newRALLYX"
- Namco mapper (first 8kb mapped to 4000h, last 8kb mapped to 8000h)
- Display garbage during boot.
- Stack at F000h

### Second release

- ID string: "newRALLYX"
- Regular, linear addressing 4000-7FFF
- Disable screen before writing VRAM during boot.
- Stack at FFFFh (may not work in expanded slots).

### Third release

- ID string: "newRALLYXfor MSX II"
- Regular, linear addressing 4000-7FFF
- Disable screen before writing VRAM during boot.
- Stack at F380h.

## Credits

Disassembly and annotations by Ricardo Bittencourt
(<bluepenguin@gmail.com>).

Presented for historic purposes only, if you are the owner of the IP please contact me.
