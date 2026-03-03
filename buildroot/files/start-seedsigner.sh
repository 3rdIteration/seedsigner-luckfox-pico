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
    # On LuckFox Pico Pi, U-Boot leaves GPIO3_D2 (KEY_LEFT) in I2C3_M2_SDA mode
    # (IOMUX func 3) and GPIO3_D3 (KEY2) in PWM1_M2 mode (IOMUX func 2).  Both
    # i2c3 and pwm1 have status="disabled" in the compiled DTB, so the kernel
    # never probes them and never resets their pinctrl.  U-Boot's IOMUX settings
    # therefore persist: the pads remain connected to peripheral output drivers
    # that pull them LOW, causing ghost button presses regardless of pull-ups.
    #
    # Fix: write to the RV1106 IOC IOMUX register for the GPIO3_D pin group to
    # switch GPIO3_D2 and GPIO3_D3 to GPIO mode (function 0), then clear the
    # GPIO bank direction bits so the lines are sampled as inputs.
    #
    # Register layout (confirmed from pinctrl-rockchip.c and rv1106.dtsi):
    #   IOC base (rockchip,grf = <&ioc>): 0xff538000
    #     reg = <0xff538000 0x40000>
    #   GPIO3 IOMUX group-D register (IOMUX_WIDTH_4BIT offset 0x20058):
    #     Address : 0xff558058
    #     Format  : write-with-mask — bits[31:16] = enable-mask, bits[15:0] = value
    #     GPIO3_D2 field: bits[11:8]   mask 0x0F00  → func 0 = GPIO
    #     GPIO3_D3 field: bits[15:12]  mask 0xF000  → func 0 = GPIO
    #     Combined write: 0xFF000000  (mask 0xFF00, value 0x0000)
    #   GPIO3 bank base: 0xff550000
    #   GPIO3 direction register (GPIO_SWPORT_DDR): 0xff550004
    #     Bit 26 = GPIO3_D2, bit 27 = GPIO3_D3; 0 = input, 1 = output
    if ! grep -qi "luckfox.*pico.*pi" /proc/device-tree/model 2>/dev/null; then
        return 0
    fi

    log_message "Pi: switching GPIO3_D2 (KEY_LEFT) and GPIO3_D3 (KEY2) to GPIO input mode..."

    python3 - 2>>"${LOG_FILE:-/tmp/startup.log}" <<'PYEOF'
import mmap, struct

def devmem_read32(addr):
    page_base = addr & ~0xFFF
    page_off  = addr &  0xFFF
    with open('/dev/mem', 'rb', buffering=0) as fd:
        m = mmap.mmap(fd.fileno(), 0x1000, offset=page_base, access=mmap.ACCESS_READ)
        val = struct.unpack_from('<I', m, page_off)[0]
        m.close()
    return val

def devmem_write32(addr, val):
    page_base = addr & ~0xFFF
    page_off  = addr &  0xFFF
    with open('/dev/mem', 'r+b', buffering=0) as fd:
        m = mmap.mmap(fd.fileno(), 0x1000, offset=page_base)
        struct.pack_into('<I', m, page_off, val)
        m.close()

# Step 1: Set GPIO3_D2 and GPIO3_D3 to GPIO function (func 0) via the IOC
# IOMUX register.  The write-with-mask format means the upper 16 bits select
# which bits to update; writing 0xFF000000 enables the D2 (bits[11:8]) and
# D3 (bits[15:12]) fields and sets them both to 0 (GPIO mode).
devmem_write32(0xff558058, 0xFF000000)

# Step 2: Ensure GPIO3_D2 (bit 26) and GPIO3_D3 (bit 27) are configured as
# inputs in the GPIO bank direction register.  Read-modify-write so we do not
# disturb other GPIO3 lines.
ddr = devmem_read32(0xff550004)
ddr &= ~((1 << 26) | (1 << 27))
devmem_write32(0xff550004, ddr)
PYEOF

    local rc=$?
    if [ "$rc" -eq 0 ]; then
        log_message "Pi: button pin GPIO mode reset succeeded"
    else
        log_message "Pi: Warning: /dev/mem write failed (exit $rc) — button pins may still be stuck"
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
