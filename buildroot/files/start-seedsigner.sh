#!/bin/bash

# Configuration
MAX_RETRIES=5
RETRY_DELAY=10  # seconds
CAMERA_START_TIMEOUT=20  # max seconds to wait for app init signal
CAMERA_POLL_INTERVAL=1   # seconds
CAMERA_POST_SPI_DELAY=10  # seconds to wait after SPI init detection
LOG_FILE="/tmp/startup.log"
APP_PID=""
CAMERA_HELPER_PID=""

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to cleanup on exit
cleanup() {
    log_message "Stopping SeedSigner..."
    if [ -n "$CAMERA_HELPER_PID" ]; then
        kill "$CAMERA_HELPER_PID" 2>/dev/null || true
    fi
    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    killall rkipc 2>/dev/null
    exit 0
}

start_camera_service() {
    local camera_service="/usr/bin/rkaiq-service"
    if [ ! -x "$camera_service" ]; then
        log_message "rkaiq service script not found at $camera_service; continuing"
        return 0
    fi

    log_message "Starting camera ISP service (rkaiq-service)..."
    "$camera_service" start >/dev/null 2>&1 || "$camera_service" restart >/dev/null 2>&1 || true
    sleep 2
}

stop_camera_service() {
    local camera_service="/usr/bin/rkaiq-service"
    if [ ! -x "$camera_service" ]; then
        log_message "rkaiq service script not found at $camera_service; continuing"
        return 0
    fi

    log_message "Stopping camera ISP service (rkaiq-service)..."
    "$camera_service" stop >/dev/null 2>&1 || true
    sleep 1
}

release_conflicting_gpio_lines() {
    # Release legacy sysfs-exported lines that conflict with libgpiod/periphery.
    # On Luckfox Pico Mini, KEY2 uses global line 4 (gpiochip0 line 4).
    for line in 4; do
        if [ -d "/sys/class/gpio/gpio${line}" ]; then
            echo "${line}" > /sys/class/gpio/unexport 2>/dev/null || true
            if [ -d "/sys/class/gpio/gpio${line}" ]; then
                log_message "GPIO line ${line} still exported via sysfs"
            else
                log_message "Unexported sysfs GPIO line ${line}"
            fi
        fi
    done
}

reset_pi_stuck_gpio_pins() {
    # python-periphery requests pull_up via GPIO_V2_LINE_FLAG_BIAS_PULL_UP, but
    # the RV1106 pinctrl driver does not implement gpio_set_config for bias so
    # the kernel request is silently ignored for every pin.  Additionally, U-Boot
    # leaves several button pins muxed to peripheral functions (UART, I2C, PWM)
    # whose output drivers actively pull the pad LOW, causing ghost presses.
    #
    # Fix: write IOMUX, input-buffer-enable, pull-up, and direction directly to
    # the IOC and GPIO bank registers via /dev/mem for all 8 button pins.
    # Register addresses from docs/RV1106_GPIO_User_Manual.txt (extracted from
    # Rockchip_RV1106_User_Manual_GPIO.pdf).
    #
    # All IOC and GPIO bank registers use Rockchip write-with-mask format:
    #   bits[31:16] = write-enable mask for bits[15:0]
    #   bits[15:0]  = value to write
    # A raw read-modify-write SILENTLY FAILS: reading returns bits[15:0] with
    # the mask field as 0; writing back sets mask=0 so nothing changes.
    #
    # Pin map (from io_config.md in the seedsigner repo):
    #   KEY_RIGHT = GPIO0_A0  gpiochip0 line  0   IOC base 0xFF388000  bank base 0xFF380000
    #   KEY_DOWN  = GPIO0_A1  gpiochip0 line  1   IOC base 0xFF388000  bank base 0xFF380000
    #   KEY_PRESS = GPIO1_C4  gpiochip1 line 20   IOC base 0xFF538000  bank base 0xFF530000
    #   KEY3      = GPIO1_C7  gpiochip1 line 23   IOC base 0xFF538000  bank base 0xFF530000
    #   KEY_UP    = GPIO3_D1  gpiochip3 line 25   IOC base 0xFF558000  bank base 0xFF550000
    #   KEY_LEFT  = GPIO3_D2  gpiochip3 line 26   IOC base 0xFF558000  bank base 0xFF550000
    #   KEY2      = GPIO3_D3  gpiochip3 line 27   IOC base 0xFF558000  bank base 0xFF550000
    #   KEY1      = GPIO4_C1  gpiochip4 line 17   IOC base 0xFF568000  bank base 0xFF560000
    if ! grep -qi "luckfox.*pico.*pi" /proc/device-tree/model 2>/dev/null; then
        return 0
    fi

    log_message "Pi: setting GPIO mode, input buffers, pull-ups for all 8 button pins..."

    python3 - 2>>"${LOG_FILE:-/tmp/startup.log}" <<'PYEOF'
import os, struct, sys

_write_failures = []

def write32(addr, val):
    """Write a 32-bit Rockchip write-with-mask value to /dev/mem.

    Uses os.lseek+os.write instead of mmap+struct.pack_into.  When a physical
    address is write-protected by hardware (e.g. a TrustZone-guarded IOC
    block), a mmap write triggers a hardware data-abort that the kernel
    delivers as SIGBUS — an unrecoverable crash with no Python exception path.
    The file-based write goes through the kernel write_mem() handler which
    returns a normal errno, so OSError can be caught per-write.
    """
    global _write_failures
    fd = None
    try:
        fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        os.lseek(fd, addr, os.SEEK_SET)
        os.write(fd, struct.pack('<I', val))
    except OSError as e:
        _write_failures.append(f'{addr:#010x}={val:#010x}: {e}')
    finally:
        if fd is not None:
            os.close(fd)

# All writes use Rockchip write-with-mask: bits[31:16]=mask, bits[15:0]=value.

# ── GPIO0: KEY_RIGHT (A0, gpiochip0/0) + KEY_DOWN (A1, gpiochip0/1) ──────────
# U-Boot may leave A0/A1 in UART0 RX/TX mode; TX actively drives LOW.
# IOC GPIO0 base: 0xFF388000   GPIO0 bank base: 0xFF380000

# IOMUX → GPIO: A0 bits[2:0], A1 bits[6:4]  mask=0x0077 value=0x0000
write32(0xFF388000, 0x00770000)
# Input buffer enable: A0 bit[0], A1 bit[1]  mask=0x0003 value=0x0003
write32(0xFF388030, 0x00030003)
# Pull-up: A0 bits[1:0]=01, A1 bits[3:2]=01  mask=0x000F value=0x0005
write32(0xFF388038, 0x000F0005)
# Direction → input (GPIO0_DDR_L): A0 bit[0], A1 bit[1]  mask=0x0003 value=0x0000
write32(0xFF380008, 0x00030000)

# ── GPIO1: KEY_PRESS (C4, gpiochip1/20) + KEY3 (C7, gpiochip1/23) ────────────
# IOC GPIO1 base: 0xFF538000   GPIO1 bank base: 0xFF530000

# IOMUX → GPIO: C4 bits[2:0] of reg 0xFF538014, C7 bits[14:12]  mask=0x7007 value=0x0000
write32(0xFF538014, 0x70070000)
# Input buffer enable: C4 bit[4], C7 bit[7]  mask=0x0090 value=0x0090
write32(0xFF538188, 0x00900090)
# Pull-up: C4 bits[9:8]=01, C7 bits[15:14]=01  mask=0xC300 value=0x4100
write32(0xFF5381C8, 0xC3004100)
# Direction → input (GPIO1_DDR_H): C4 bit[4], C7 bit[7]  mask=0x0090 value=0x0000
write32(0xFF53000C, 0x00900000)

# ── GPIO3: KEY_UP (D1, gpiochip3/25), KEY_LEFT (D2, /26), KEY2 (D3, /27) ─────
# U-Boot leaves D1 in I2C3_M2_SCL, D2 in I2C3_M2_SDA, D3 in PWM1_M2 — all
# peripheral output drivers that pull the pad LOW.
# IOC GPIO3 base: 0xFF558000   GPIO3 bank base: 0xFF550000

# IOMUX → GPIO: D1 bits[6:4], D2 bits[10:8], D3 bits[14:12]  mask=0x7770 value=0x0000
write32(0xFF558058, 0x77700000)
# Input buffer enable: D1 bit[1], D2 bit[2], D3 bit[3]  mask=0x000E value=0x000E
write32(0xFF5581AC, 0x000E000E)
# Pull-up: D1 bits[3:2]=01, D2 bits[5:4]=01, D3 bits[7:6]=01  mask=0x00FC value=0x0054
write32(0xFF5581EC, 0x00FC0054)
# Direction → input (GPIO3_DDR_H): D1 bit[9], D2 bit[10], D3 bit[11]  mask=0x0E00 value=0x0000
write32(0xFF55000C, 0x0E000000)

# ── GPIO4: KEY1 (C1, gpiochip4/17) ───────────────────────────────────────────
# GPIO4 uses high-drive pads with a different pull encoding: 0=none 1=down 3=up.
# U-Boot may leave C1 in PWM1_M1 push-pull output mode.
# IOC GPIO4 base: 0xFF568000   GPIO4 bank base: 0xFF560000

# IOMUX → GPIO: C1 bits[6:4] of reg 0xFF568010  mask=0x0070 value=0x0000
write32(0xFF568010, 0x00700000)
# Pull-up (bits[14:13]=11=3) + input buffer enable (bit[3]=1) on same reg 0xFF5680C0
# mask=0x6008 value=0x6008
write32(0xFF5680C0, 0x60086008)
# Direction → input (GPIO4_DDR_H): C1 bit[1]  mask=0x0002 value=0x0000
write32(0xFF56000C, 0x00020000)

if _write_failures:
    print(f"Pi: {len(_write_failures)} IOC write(s) blocked (TrustZone/hardware protected):",
          file=sys.stderr)
    for f in _write_failures:
        print(f"Pi:   {f}", file=sys.stderr)
    sys.exit(2)  # partial failure — gpioget fallback will run
PYEOF

    local rc=$?
    if [ "$rc" -eq 0 ]; then
        log_message "Pi: button pin pull-up configuration succeeded"
    elif [ "$rc" -eq 2 ]; then
        # Some /dev/mem writes were blocked (TrustZone / hardware write protection).
        # Fall back to the kernel GPIO subsystem for IOMUX: opening each GPIO line
        # for input forces the kernel pinctrl to set IOMUX → GPIO mode, which is
        # the kernel driver's privileged write path.  Pull-up config requires
        # /dev/mem; with external pull-up resistors fitted this is not needed.
        log_message "Pi: Some IOC writes blocked — using gpioget fallback for IOMUX"
        local _chip _line
        # chip/line pairs: KEY_RIGHT KEY_DOWN KEY_PRESS KEY3 KEY_UP KEY_LEFT KEY2 KEY1
        for _chip_line in "0 0" "0 1" "1 20" "1 23" "3 25" "3 26" "3 27" "4 17"; do
            _chip="${_chip_line% *}"
            _line="${_chip_line#* }"
            gpioget gpiochip${_chip} ${_line} >/dev/null 2>&1 || \
                log_message "Pi: gpioget gpiochip${_chip} ${_line} failed (pin may be busy)"
        done
        log_message "Pi: gpioget IOMUX fallback complete"
    else
        log_message "Pi: Warning: /dev/mem write failed (exit $rc) — button pull-ups may not be set"
    fi
}

start_camera_service_later() {
    local target_pid="$1"
    local post_spi_delay="$2"
    (
        local waited=0
        while [ "$waited" -lt "$CAMERA_START_TIMEOUT" ]; do
            if ! kill -0 "$target_pid" 2>/dev/null; then
                return 0
            fi

            # Wait for SeedSigner to initialize the SPI display first.
            if ls -l "/proc/$target_pid/fd" 2>/dev/null | grep -q 'spidev'; then
                log_message "Detected SeedSigner SPI device init; waiting ${post_spi_delay}s before starting camera service"
                sleep "$post_spi_delay"
                if kill -0 "$target_pid" 2>/dev/null; then
                    start_camera_service
                fi
                return 0
            fi

            sleep "$CAMERA_POLL_INTERVAL"
            waited=$((waited + CAMERA_POLL_INTERVAL))
        done

        if kill -0 "$target_pid" 2>/dev/null; then
            log_message "SeedSigner init signal not detected after ${CAMERA_START_TIMEOUT}s; starting camera service anyway"
            start_camera_service
        fi
    ) &
    CAMERA_HELPER_PID="$!"
}

bootstrap_camera_graph() {
    # Some builds only create a usable ISP graph after rkipc performs early init.
    if ls /dev/v4l-subdev* >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v rkipc >/dev/null 2>&1; then
        log_message "rkipc not found; skipping camera graph bootstrap"
        return 0
    fi

    log_message "Bootstrapping camera graph via temporary rkipc start..."
    if [ -d "/oem/usr/share/iqfiles" ]; then
        rkipc -a /oem/usr/share/iqfiles >/tmp/rkipc-bootstrap.log 2>&1 &
    else
        rkipc >/tmp/rkipc-bootstrap.log 2>&1 &
    fi
    sleep 3
    killall rkipc 2>/dev/null || true
    sleep 1
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Kill any existing rkipc processes
killall rkipc 2>/dev/null
bootstrap_camera_graph

# Change to SeedSigner directory
cd /seedsigner

# Retry loop
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    camera_post_spi_delay=$((CAMERA_POST_SPI_DELAY + retry_count))

    log_message "Starting SeedSigner (attempt $((retry_count + 1))/$MAX_RETRIES)"

    # Always clear camera-related processes before launching the app.
    killall rkipc 2>/dev/null || true
    stop_camera_service
    release_conflicting_gpio_lines
    reset_pi_stuck_gpio_pins
    
    # Start SeedSigner first. On Mini, camera ISP start before display init can
    # exhaust memory and cause SPI open failures.
    python main.py &
    APP_PID="$!"
    start_camera_service_later "$APP_PID" "$camera_post_spi_delay"

    wait "$APP_PID"
    exit_code=$?
    APP_PID=""
    if [ -n "$CAMERA_HELPER_PID" ]; then
        wait "$CAMERA_HELPER_PID" 2>/dev/null || true
        CAMERA_HELPER_PID=""
    fi

    if [ $exit_code -eq 0 ]; then
        log_message "SeedSigner exited successfully"
        exit 0
    else
        retry_count=$((retry_count + 1))
        log_message "SeedSigner failed with exit code $exit_code"
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            log_message "Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        else
            log_message "Maximum retries reached. SeedSigner failed to start."
            exit 1
        fi
    fi
done
