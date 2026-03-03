#!/usr/bin/env python3
"""
pi_gpio_debug.py — LuckFox Pico Pi GPIO pull-up diagnostic tool

Run this directly on the Pi to diagnose why internal pull-ups are not working.

Usage:
    python3 /seedsigner/test_suite/pi_gpio_debug.py

What it checks:
    1. Model string (verifies the model guard in start-seedsigner.sh would fire)
    2. All 8 button pin IOC register states BEFORE any fix:
       - IOMUX (which peripheral function)
       - Input buffer enable
       - Pull configuration
       - Direction
    3. Applies the /dev/mem fix (writes); reports individual write failures
       without crashing — hardware-protected registers (e.g. TrustZone IOC
       blocks) return OSError rather than SIGBUS with the file-based approach
    4. Reads all registers back to show post-fix state
    4b. For any pin whose IOMUX write failed, tries gpioget to ask the kernel
        pinctrl to set IOMUX to GPIO mode, then re-reads IOMUX
    5. Reads actual hardware pin level via GPIO EXT_PORT register
    6. Reads pin levels via gpioget (libgpiod CLI tool)
    7. Opens lines with python-periphery then re-reads registers to detect
       whether the kernel pinctrl re-muxes pins when a line is claimed
    8. Prints a per-pin PASS/FAIL verdict

NOTE: write32 uses os.lseek + os.write rather than mmap + struct.pack_into.
    mmap writes to hardware-protected physical addresses cause a hardware
    data-abort that the kernel delivers as SIGBUS, which crashes the process
    with no Python exception.  The file-based path goes through the kernel's
    write_mem() handler which returns an errno (converted to OSError), so
    individual failures can be caught and reported while the rest continue.

All 8 Pi button pins (from io_config.md FOX_PI profile):
    KEY_RIGHT = GPIO0_A0  gpiochip0/0
    KEY_DOWN  = GPIO0_A1  gpiochip0/1
    KEY_PRESS = GPIO1_C4  gpiochip1/20
    KEY3      = GPIO1_C7  gpiochip1/23
    KEY_UP    = GPIO3_D1  gpiochip3/25
    KEY_LEFT  = GPIO3_D2  gpiochip3/26
    KEY2      = GPIO3_D3  gpiochip3/27
    KEY1      = GPIO4_C1  gpiochip4/17

Register addresses from docs/RV1106_GPIO_User_Manual.txt
(extracted from Rockchip_RV1106_User_Manual_GPIO.pdf).

NOTE: All IOC and GPIO bank registers use Rockchip write-with-mask format:
    bits[31:16] = write-enable mask for bits[15:0]
    bits[15:0]  = value to write
Reading a register returns bits[15:0] only (mask field reads as 0).
This means a read-modify-write silently does nothing.
"""

import mmap
import re
import struct
import subprocess
import sys
import os

# ─────────────────────────────────────────────────────────────────────────────
# Register access helpers
# ─────────────────────────────────────────────────────────────────────────────

def read32(addr):
    """Read a 32-bit register value from /dev/mem."""
    page_base = addr & ~0xFFF
    page_off  = addr &  0xFFF
    with open('/dev/mem', 'r+b', buffering=0) as fd:
        m = mmap.mmap(fd.fileno(), 0x1000, offset=page_base)
        val = struct.unpack_from('<I', m, page_off)[0]
        m.close()
    return val

def write32(addr, val):
    """Write a 32-bit Rockchip write-with-mask value to /dev/mem.

    Uses os.lseek + os.write rather than mmap + struct.pack_into.  When a
    physical address is write-protected by hardware (e.g. a TrustZone-guarded
    IOC block), a mmap write causes a hardware data-abort that the kernel
    converts to SIGBUS — an unrecoverable crash with no Python exception path.
    The file-based write goes through the kernel's write_mem() handler, which
    returns a normal errno (OSError) so callers can catch and handle it.
    """
    fd = None
    try:
        fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        os.lseek(fd, addr, os.SEEK_SET)
        os.write(fd, struct.pack('<I', val))
    except OSError:
        raise
    finally:
        if fd is not None:
            os.close(fd)

def get_field(reg_val, hi, lo):
    """Extract bit field [hi:lo] from a register read value."""
    mask = (1 << (hi - lo + 1)) - 1
    return (reg_val >> lo) & mask


# ─────────────────────────────────────────────────────────────────────────────
# Pin definitions
# ─────────────────────────────────────────────────────────────────────────────

# Each entry:
#   name, chip, line,
#   iomux_reg, iomux_hi, iomux_lo,
#   inctrl_reg, inctrl_bit,
#   pull_reg, pull_hi, pull_lo, pull_encoding,
#   ddr_reg, ddr_bit,
#   ext_port_reg, ext_port_bit
#
# pull_encoding: 'std' (0=none,1=up,2=down) or 'gpio4hd' (0=none,1=down,3=up)
# ext_port_reg: GPIO_EXT_PORT_L (offset 0x70) or _H (offset 0x74) from bank base.
#   Bank bases: GPIO0=0xFF380000, GPIO1=0xFF530000, GPIO3=0xFF550000, GPIO4=0xFF560000

PINS = [
    # name        chip  line  iomux_reg   hi lo  inctrl_reg  bit  pull_reg    hi lo  enc       ddr_reg     bit  ext_reg     bit
    ("KEY_RIGHT", 0,  0,   0xFF388000,  2, 0,  0xFF388030,  0,  0xFF388038,  1, 0, 'std',   0xFF380008,  0,  0xFF380070,  0),
    ("KEY_DOWN",  0,  1,   0xFF388000,  6, 4,  0xFF388030,  1,  0xFF388038,  3, 2, 'std',   0xFF380008,  1,  0xFF380070,  1),
    ("KEY_PRESS", 1, 20,   0xFF538014,  2, 0,  0xFF538188,  4,  0xFF5381C8,  9, 8, 'std',   0xFF53000C,  4,  0xFF530074,  4),
    ("KEY3",      1, 23,   0xFF538014, 14,12,  0xFF538188,  7,  0xFF5381C8, 15,14, 'std',   0xFF53000C,  7,  0xFF530074,  7),
    ("KEY_UP",    3, 25,   0xFF558058,  6, 4,  0xFF5581AC,  1,  0xFF5581EC,  3, 2, 'std',   0xFF55000C,  9,  0xFF550074,  9),
    ("KEY_LEFT",  3, 26,   0xFF558058, 10, 8,  0xFF5581AC,  2,  0xFF5581EC,  5, 4, 'std',   0xFF55000C, 10,  0xFF550074, 10),
    ("KEY2",      3, 27,   0xFF558058, 14,12,  0xFF5581AC,  3,  0xFF5581EC,  7, 6, 'std',   0xFF55000C, 11,  0xFF550074, 11),
    ("KEY1",      4, 17,   0xFF568010,  6, 4,  0xFF5680C0,  3,  0xFF5680C0, 14,13, 'gpio4hd', 0xFF56000C, 1, 0xFF560074,  1),
]


# ─────────────────────────────────────────────────────────────────────────────
# Decoding helpers
# ─────────────────────────────────────────────────────────────────────────────

PULL_STD    = {0: 'none', 1: 'pull-UP ✓', 2: 'pull-down'}
PULL_GPIO4  = {0: 'none', 1: 'pull-down', 2: '?', 3: 'pull-UP ✓'}

def decode_pull(val, enc):
    lut = PULL_GPIO4 if enc == 'gpio4hd' else PULL_STD
    return lut.get(val, f'unknown({val})')

def iomux_ok(pin):
    """Return True if the IOMUX field reads 0 (GPIO mode)."""
    name, chip, line, iomux_reg, iomux_hi, iomux_lo, *_ = pin
    rv = read32(iomux_reg)
    return get_field(rv, iomux_hi, iomux_lo) == 0

def read_pin_state(pin):
    """Return dict of all decoded register fields for this pin."""
    (name, chip, line,
     iomux_reg, iomux_hi, iomux_lo,
     inctrl_reg, inctrl_bit,
     pull_reg, pull_hi, pull_lo, pull_enc,
     ddr_reg, ddr_bit,
     ext_reg, ext_bit) = pin

    iomux_raw  = read32(iomux_reg)
    inctrl_raw = read32(inctrl_reg)
    pull_raw   = read32(pull_reg)
    ddr_raw    = read32(ddr_reg)

    iomux_val  = get_field(iomux_raw,  iomux_hi,  iomux_lo)
    inctrl_val = get_field(inctrl_raw, inctrl_bit, inctrl_bit)
    pull_val   = get_field(pull_raw,   pull_hi,    pull_lo)
    ddr_val    = get_field(ddr_raw,    ddr_bit,    ddr_bit)

    # Hardware level via EXT_PORT (read-only, actual pad state)
    try:
        ext_raw   = read32(ext_reg)
        ext_level = get_field(ext_raw, ext_bit, ext_bit)
        ext_str   = 'HIGH' if ext_level else 'LOW'
    except Exception as e:
        ext_str   = f'ERR({e})'

    return {
        'iomux':  iomux_val,
        'inctrl': inctrl_val,
        'pull':   pull_val,
        'dir':    ddr_val,
        'level':  ext_str,
        'pull_enc': pull_enc,
        # raw for display
        'iomux_reg':  iomux_reg,
        'pull_reg':   pull_reg,
        'inctrl_reg': inctrl_reg,
        'ddr_reg':    ddr_reg,
        'ext_reg':    ext_reg,
    }

def is_configured_ok(state):
    """Return True if all fields look correct for a GPIO input with pull-up."""
    pull_ok = (state['pull'] == 1) if state['pull_enc'] == 'std' else (state['pull'] == 3)
    return (state['iomux']  == 0 and   # GPIO mode
            state['inctrl'] == 1 and   # input buffer enabled
            pull_ok                and  # pull-up active
            state['dir']    == 0)       # input direction


# ─────────────────────────────────────────────────────────────────────────────
# Display helpers
# ─────────────────────────────────────────────────────────────────────────────

SEP = '─' * 72

def print_pin_state(pin, state, label=''):
    name = pin[0]
    chip = pin[1]
    line = pin[2]
    pull_str = decode_pull(state['pull'], state['pull_enc'])
    dir_str  = 'input ✓' if state['dir'] == 0 else 'OUTPUT ✗'
    mux_str  = 'GPIO ✓' if state['iomux'] == 0 else f'peripheral func {state["iomux"]} ✗'
    ib_str   = 'enabled ✓' if state['inctrl'] == 1 else 'DISABLED ✗'
    ok       = is_configured_ok(state)
    verdict  = '✓ OK' if ok else '✗ NEEDS FIX'

    hdr = f"  {name} (gpiochip{chip} line {line})"
    if label:
        hdr += f'  [{label}]'
    print(hdr)
    print(f"    IOMUX      {state['iomux_reg']:#010x}  → {mux_str}")
    print(f"    InputCtrl  {state['inctrl_reg']:#010x}  → {ib_str}")
    print(f"    Pull       {state['pull_reg']:#010x}  → {pull_str}")
    print(f"    Direction  {state['ddr_reg']:#010x}  → {dir_str}")
    print(f"    HW level   {state['ext_reg']:#010x}  → {state['level']}")
    print(f"    Verdict:   {verdict}")


# ─────────────────────────────────────────────────────────────────────────────
# Apply the /dev/mem fix (same writes as start-seedsigner.sh)
# ─────────────────────────────────────────────────────────────────────────────

def apply_fix():
    """Apply the /dev/mem register fix.

    Each write is attempted independently; if a write is blocked by the
    hardware (e.g. TrustZone-protected IOC region), OSError is caught and
    recorded instead of crashing the process.

    Returns a list of (addr, val, description, error_string) for every write
    that failed.  An empty list means all writes succeeded.
    """
    writes = [
        # GPIO0: KEY_RIGHT (A0) + KEY_DOWN (A1)
        (0xFF388000, 0x00770000, 'GPIO0 IOMUX → GPIO'),
        (0xFF388030, 0x00030003, 'GPIO0 input buffer enable'),
        (0xFF388038, 0x000F0005, 'GPIO0 pull-up'),
        (0xFF380008, 0x00030000, 'GPIO0 direction → input'),
        # GPIO1: KEY_PRESS (C4) + KEY3 (C7)
        (0xFF538014, 0x70070000, 'GPIO1 IOMUX → GPIO'),
        (0xFF538188, 0x00900090, 'GPIO1 input buffer enable'),
        (0xFF5381C8, 0xC3004100, 'GPIO1 pull-up'),
        (0xFF53000C, 0x00900000, 'GPIO1 direction → input'),
        # GPIO3: KEY_UP (D1) + KEY_LEFT (D2) + KEY2 (D3)
        (0xFF558058, 0x77700000, 'GPIO3 IOMUX → GPIO'),
        (0xFF5581AC, 0x000E000E, 'GPIO3 input buffer enable'),
        (0xFF5581EC, 0x00FC0054, 'GPIO3 pull-up'),
        (0xFF55000C, 0x0E000000, 'GPIO3 direction → input'),
        # GPIO4: KEY1 (C1) — high-drive pad, pull encoding: 3=pullup
        (0xFF568010, 0x00700000, 'GPIO4 IOMUX → GPIO'),
        (0xFF5680C0, 0x60086008, 'GPIO4 pull-up + input buffer enable'),
        (0xFF56000C, 0x00020000, 'GPIO4 direction → input'),
    ]
    failures = []
    for addr, val, desc in writes:
        try:
            write32(addr, val)
        except OSError as e:
            failures.append((addr, val, desc, str(e)))
    return failures


# ─────────────────────────────────────────────────────────────────────────────
# gpioget via subprocess
# ─────────────────────────────────────────────────────────────────────────────

_GPIOGET_NOT_FOUND = 'gpioget not available'


def _gpioget_run(chip, line, timeout=2):
    """Run gpioget for a single chip/line.  Tries libgpiod v2 syntax first
    (gpioget -c gpiochipN offset), then v1 (gpioget gpiochipN offset).
    Returns (returncode, stdout, stderr).
    """
    # libgpiod v2: -c/--chip selects the chip; line is a numeric offset.
    # libgpiod v1: positional chip-name then offset.
    cmds = [
        ['gpioget', '-c', f'gpiochip{chip}', str(line)],  # v2
        ['gpioget', f'gpiochip{chip}', str(line)],          # v1
    ]
    last_rc, last_out, last_err = 1, '', _GPIOGET_NOT_FOUND
    for cmd in cmds:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            last_rc, last_out, last_err = r.returncode, r.stdout, r.stderr
            if r.returncode == 0:
                return r.returncode, r.stdout, r.stderr
            err = r.stderr.strip() or r.stdout.strip()
            # v2 "unknown option" → try v1 syntax
            if any(k in err.lower() for k in ('unknown option', 'unrecognized', 'invalid option')):
                continue
            # Any other error (e.g. "device busy") is definitive — stop trying
            return r.returncode, r.stdout, r.stderr
        except FileNotFoundError:
            return 1, '', _GPIOGET_NOT_FOUND
        except Exception as e:
            return 1, '', f'gpioget exception: {e}'
    return last_rc, last_out, last_err


def gpioget_level(chip, line):
    """Read a GPIO line via the gpioget CLI tool (libgpiod v1 and v2).
    Returns 'HIGH', 'LOW', or an error string."""
    rc, out, err = _gpioget_run(chip, line)
    if rc == 0:
        val = out.strip()
        if val == '1':
            return 'HIGH'
        elif val == '0':
            return 'LOW'
        else:
            return f'gpioget error: unexpected output: {val!r}'
    return f'gpioget error: {err.strip() or out.strip()}'


# ─────────────────────────────────────────────────────────────────────────────
# python-periphery read
# ─────────────────────────────────────────────────────────────────────────────

def periphery_levels():
    """Open all 8 lines with python-periphery and read their levels.
    Returns dict: name → level string."""
    results = {}
    try:
        from periphery import GPIO
    except ImportError:
        return {p[0]: 'periphery not installed' for p in PINS}

    handles = {}
    for pin in PINS:
        name, chip, line = pin[0], pin[1], pin[2]
        try:
            g = GPIO(f'/dev/gpiochip{chip}', line, 'in')
            handles[name] = g
        except Exception as e:
            results[name] = f'open error: {e}'

    # Read all opened lines
    for name, g in handles.items():
        try:
            v = g.read()
            results[name] = 'HIGH' if v else 'LOW'
        except Exception as e:
            results[name] = f'read error: {e}'
        finally:
            try:
                g.close()
            except Exception:
                pass

    for pin in PINS:
        if pin[0] not in results:
            results[pin[0]] = 'not opened'

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    print()
    print('=' * 72)
    print('  LuckFox Pico Pi GPIO Pull-up Diagnostic')
    print('  Register addresses from docs/RV1106_GPIO_User_Manual.txt')
    print('=' * 72)

    # ── 0. Check /dev/mem access ──────────────────────────────────────────────
    try:
        read32(0xFF388000)
    except PermissionError:
        print('\n✗ Cannot open /dev/mem — run as root:  sudo python3 pi_gpio_debug.py')
        sys.exit(1)
    except Exception as e:
        print(f'\n✗ /dev/mem access failed: {e}')
        sys.exit(1)

    # ── 1. Model string check ─────────────────────────────────────────────────
    print('\n── 1. Device model string ──────────────────────────────────────────────')
    try:
        with open('/proc/device-tree/model', 'r') as f:
            model = f.read().rstrip('\x00')
        print(f'  /proc/device-tree/model = "{model}"')
        # Use the same pattern as the grep in start-seedsigner.sh
        if re.search(r'luckfox.*pico.*pi', model, re.IGNORECASE):
            print('  ✓ Model matches "luckfox.*pico.*pi" — startup fix would fire')
        else:
            print('  ✗ Model does NOT match "luckfox.*pico.*pi"')
            print('    The guard in reset_pi_stuck_gpio_pins() would SKIP the fix!')
            print('    Check /proc/device-tree/model and update the grep pattern.')
    except Exception as e:
        print(f'  Could not read model: {e}')

    # ── 2. Register state BEFORE fix ─────────────────────────────────────────
    print('\n── 2. IOC register state BEFORE applying /dev/mem fix ──────────────────')
    before = {}
    for pin in PINS:
        before[pin[0]] = read_pin_state(pin)
        print()
        print_pin_state(pin, before[pin[0]], 'BEFORE')

    # ── 3. Apply fix ─────────────────────────────────────────────────────────
    print(f'\n── 3. Applying /dev/mem fix ────────────────────────────────────────────')
    print('  (Using os.lseek+os.write — failed writes return OSError, not SIGBUS)')
    write_failures = apply_fix()
    if not write_failures:
        print('  All writes succeeded')
    else:
        print(f'  {len(write_failures)} write(s) blocked by hardware (OSError):')
        for addr, val, desc, err in write_failures:
            print(f'    ✗ {addr:#010x} = {val:#010x}  ({desc})')
            print(f'               error: {err}')
        failed_regions = set()
        for addr, val, desc, err in write_failures:
            if 'GPIO0' in desc:  failed_regions.add('GPIO0 IOC (0xFF388xxx)')
            if 'GPIO1' in desc:  failed_regions.add('GPIO1 IOC (0xFF538xxx)')
            if 'GPIO3' in desc:  failed_regions.add('GPIO3 IOC (0xFF558xxx)')
            if 'GPIO4' in desc:  failed_regions.add('GPIO4 IOC (0xFF568xxx)')
        if failed_regions:
            print(f'  Blocked region(s): {", ".join(sorted(failed_regions))}')
            print('  These IOC regions appear to be TrustZone/hardware write-protected.')
            print('  Reads still work; only writes are blocked.')
            print('  Step 4b will try the kernel GPIO subsystem as a fallback for IOMUX.')

    # ── 4. Register state AFTER fix ──────────────────────────────────────────
    print('\n── 4. IOC register state AFTER applying /dev/mem fix ───────────────────')
    after_fix = {}
    for pin in PINS:
        after_fix[pin[0]] = read_pin_state(pin)
        print()
        print_pin_state(pin, after_fix[pin[0]], 'AFTER FIX')

    # ── 4b. Fallback: use gpioget to trigger kernel pinctrl IOMUX for pins ────
    #        whose IOMUX write failed or whose IOMUX is still not in GPIO mode.
    print('\n── 4b. Kernel GPIO subsystem IOMUX fallback ────────────────────────────')
    print('  For pins still in peripheral mode, gpioget asks the kernel pinctrl to')
    print('  set IOMUX → GPIO (the kernel driver has the hardware access we lack).')
    print('  If "device busy" appears, another kernel driver still owns that pin.')
    iomux_fallback_needed = [p for p in PINS if after_fix[p[0]]['iomux'] != 0]
    if not iomux_fallback_needed:
        print('  All pins already in GPIO mode — no fallback needed')
    else:
        for pin in iomux_fallback_needed:
            name, chip, line = pin[0], pin[1], pin[2]
            rc, out, err = _gpioget_run(chip, line, timeout=3)
            # Re-read IOMUX to see if gpioget helped
            post_state = read_pin_state(pin)
            iomux_now = post_state['iomux']
            if rc == 0 and iomux_now == 0:
                print(f'  {name:12s}  ✓ IOMUX now GPIO after gpioget')
                after_fix[name] = post_state  # update for subsequent sections
            elif rc != 0:
                err_msg = err.strip() or out.strip()
                print(f'  {name:12s}  ✗ gpioget failed ({err_msg})')
                if 'busy' in err_msg.lower() or 'device' in err_msg.lower():
                    print(f'               → pin is owned by a kernel driver (I2C/PWM/UART)')
                    print(f'               → DTB fix (apply_pi_i2c_pinctrl_fix) did not run')
            else:
                print(f'  {name:12s}  ✗ gpioget ran but IOMUX still func {iomux_now}')

    # ── 5. Summary: did the writes take effect? ───────────────────────────────
    print('\n── 5. /dev/mem write verification ──────────────────────────────────────')
    all_wrote_ok = True
    for pin in PINS:
        name = pin[0]
        s = after_fix[name]
        ok = is_configured_ok(s)
        status = '✓ configured correctly' if ok else '✗ still needs fix'
        if not ok:
            all_wrote_ok = False
        print(f'  {name:12s}  {status}')
        if not ok:
            # Print which field is wrong
            pull_ok = (s['pull'] == 1) if s['pull_enc'] == 'std' else (s['pull'] == 3)
            if s['iomux'] != 0:
                print(f'               → IOMUX still set to func {s["iomux"]} (expected 0=GPIO)')
            if s['inctrl'] != 1:
                print(f'               → Input buffer still DISABLED (expected 1)')
            if not pull_ok:
                print(f'               → Pull = {s["pull"]} ({decode_pull(s["pull"], s["pull_enc"])}) (expected pull-up)')
            if s['dir'] != 0:
                print(f'               → Direction = OUTPUT (expected input)')

    # ── 6. gpioget pin levels ─────────────────────────────────────────────────
    print('\n── 6. Pin levels via gpioget (libgpiod CLI) ────────────────────────────')
    print('  (With buttons unpressed, a working pull-up should read HIGH)')
    for pin in PINS:
        name, chip, line = pin[0], pin[1], pin[2]
        level = gpioget_level(chip, line)
        ok = '✓' if level == 'HIGH' else ('✗' if level == 'LOW' else '?')
        print(f'  {name:12s}  gpiochip{chip} line {line:2d}  →  {level}  {ok}')

    # ── 7. python-periphery pin levels ───────────────────────────────────────
    print('\n── 7. Pin levels via python-periphery ──────────────────────────────────')
    print('  (Opens each line as "in"; pull_up request is sent but silently ignored')
    print('   on RV1106 — pull state comes only from the /dev/mem writes above)')
    periph_levels = periphery_levels()
    for pin in PINS:
        name = pin[0]
        level = periph_levels.get(name, '?')
        ok = '✓' if level == 'HIGH' else ('✗' if level == 'LOW' else '?')
        print(f'  {name:12s}  →  {level}  {ok}')

    # ── 8. Re-read registers AFTER periphery opened the lines ────────────────
    print('\n── 8. IOC register state AFTER python-periphery opened lines ───────────')
    print('  (If any field changed, the kernel pinctrl is re-muxing on line claim)')
    after_periph = {}
    any_remuxed = False
    for pin in PINS:
        after_periph[pin[0]] = read_pin_state(pin)

    for pin in PINS:
        name = pin[0]
        a = after_fix[name]
        b = after_periph[name]
        changed = []
        if a['iomux']  != b['iomux']:  changed.append(f'IOMUX {a["iomux"]}→{b["iomux"]}')
        if a['inctrl'] != b['inctrl']: changed.append(f'InCtrl {a["inctrl"]}→{b["inctrl"]}')
        if a['pull']   != b['pull']:   changed.append(f'Pull {a["pull"]}→{b["pull"]}')
        if a['dir']    != b['dir']:    changed.append(f'Dir {a["dir"]}→{b["dir"]}')
        if changed:
            any_remuxed = True
            print(f'  {name:12s}  ✗ CHANGED after periphery: {", ".join(changed)}')
        else:
            print(f'  {name:12s}  ✓ unchanged')

    if any_remuxed:
        print()
        print('  !! Kernel is re-muxing pins when they are claimed via gpiochip.')
        print('     This means the DTB still has conflicting pinctrl entries.')
        print('     Check that apply_pi_i2c_pinctrl_fix() ran during the build.')
        print('     Look for i2c3m2_xfer, pwm1m1_pins, pwm1m2_pins, uart0m0_xfer,')
        print('     pwm2m0_pins still present in the Pi DTSI.')

    # ── 9. Final verdict ──────────────────────────────────────────────────────
    print('\n── 9. Final verdict ────────────────────────────────────────────────────')
    # A level is "readable" if periphery could open and read the line.
    # Only HIGH/LOW are valid GPIO readings; anything else is an error/skip.
    readable_levels = {name: v for name, v in periph_levels.items()
                       if v in ('HIGH', 'LOW')}
    levels_ok = bool(readable_levels) and all(v == 'HIGH' for v in readable_levels.values())

    if all_wrote_ok and not any_remuxed and levels_ok:
        print('  ✓ All checks passed — pull-ups appear to be working correctly.')
    else:
        print('  ✗ Problems detected:')
        if not all_wrote_ok:
            print('    • Some pins are still not fully configured.')
            if write_failures:
                print('      /dev/mem writes were blocked by hardware (TrustZone/MPU).')
                print('      If gpioget succeeded in step 4b, IOMUX is now GPIO mode.')
                print('      Pull configuration requires the /dev/mem writes to work.')
        if any_remuxed:
            print('    • Kernel re-muxed pins after periphery opened lines.')
            print('      The DTB pinctrl fix (apply_pi_i2c_pinctrl_fix) may not')
            print('      have run, or the image was not rebuilt after that fix.')
        if not levels_ok:
            pins_low = [name for name, v in readable_levels.items() if v == 'LOW']
            print(f'    • These pins read LOW with no button pressed: {pins_low}')
            print('      If IOMUX is GPIO, direction is input, and external pull-ups')
            print('      are installed, but pins still read LOW, check for:')
            print('        - Another kernel driver actively driving the pin (I2C, UART)')
            print('        - A short to GND in the button circuit')
            print('        - The internal pull-down fighting a weak external pull-up')

    print()
    print('── Tips for further debugging ──────────────────────────────────────────')
    print()
    print('  Test whether /dev/mem WRITES work for a specific IOC region:')
    print('    python3 -c "import os,struct; fd=os.open(\'/dev/mem\',os.O_RDWR|os.O_SYNC); \\')
    print('      os.lseek(fd,0xFF558058,0); os.write(fd,struct.pack(\'<I\',0x77700000)); \\')
    print('      os.close(fd); print(\'GPIO3 IOMUX write succeeded\')"')
    print()
    print('  Quick register read with the io tool (if available):')
    print('    io -4 0xFF388038   # GPIO0_A0/A1 pull register')
    print('    io -4 0xFF5381C8   # GPIO1_C4/C7 pull register')
    print('    io -4 0xFF5581EC   # GPIO3_D1/D2/D3 pull register')
    print('    io -4 0xFF5680C0   # GPIO4_C1 pull+inputctrl register')
    print()
    print('  Expected pull register values after fix (bits[15:0] of read):')
    print('    0xFF388038 → bits[3:0] = 0b0101 (A0=01=up, A1=01=up) → 0x0005')
    print('    0xFF5381C8 → bits[15:8] = 0b01000001 (C4=01=up, C7=01=up) → 0x4100')
    print('    0xFF5581EC → bits[7:2] = 0b010101 (D1=01, D2=01, D3=01) → 0x0054')
    print('    0xFF5680C0 → bits[14:13] = 0b11=3=up, bit[3]=1 → 0x6008')
    print()
    print('  Check startup log for the fix result:')
    print('    cat /tmp/startup.log | grep -i "pull\\|gpio\\|pin\\|sigbus\\|bus error\\|efault"')
    print()
    print('  List all GPIO lines with kernel state:')
    print('    gpioinfo')
    print()
    print('  Read a single GPIO line (libgpiod v2 syntax; v1 omits -c):')
    print('    gpioget -c gpiochip0 0   # KEY_RIGHT')
    print('    gpioget -c gpiochip0 1   # KEY_DOWN')
    print('    gpioget -c gpiochip1 20  # KEY_PRESS')
    print('    gpioget -c gpiochip1 23  # KEY3')
    print('    gpioget -c gpiochip3 25  # KEY_UP')
    print('    gpioget -c gpiochip3 26  # KEY_LEFT')
    print('    gpioget -c gpiochip3 27  # KEY2')
    print('    gpioget -c gpiochip4 17  # KEY1')
    print()
    print('  Force IOMUX → GPIO for all button pins via kernel pinctrl:')
    print('    gpioget -c gpiochip0 0 1')
    print('    gpioget -c gpiochip1 20 23')
    print('    gpioget -c gpiochip3 25 26 27')
    print('    gpioget -c gpiochip4 17')
    print()
    print('  If /dev/mem writes return EFAULT (errno 14) the kernel blocks I/O region')
    print('  writes from userspace (CONFIG_STRICT_DEVMEM or similar). Reads still work.')
    print('  The gpioget approach above sets IOMUX via the kernel pinctrl driver which')
    print('  has direct ioremap access. Pull-up configuration still requires /dev/mem.')
    print()
    print('  Check DTB for leftover conflicting pinctrl (should return no output):')
    print('    fdtget /proc/device-tree/i2c3 pinctrl-0 2>/dev/null')
    print('    fdtget /proc/device-tree/pwm1 pinctrl-0 2>/dev/null')
    print('    fdtget /proc/device-tree/uart0 pinctrl-0 2>/dev/null')
    print()
    print('  Check pinctrl debug sysfs to see which driver owns each pin:')
    print('    cat /sys/kernel/debug/pinctrl/pinctrl-rockchip/pinmux-pins 2>/dev/null \\')
    print('      | grep -E "GPIO3_D[123]|GPIO0_A[01]|GPIO1_C[47]|GPIO4_C1"')
    print()


if __name__ == '__main__':
    main()
