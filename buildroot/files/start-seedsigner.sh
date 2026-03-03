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
    # On LuckFox Pico Pi, GPIO3_D2 (KEY_LEFT) and GPIO3_D3 (KEY2) receive ghost
    # inputs because the I2C3 and PWM1 hardware controllers are left running by
    # the boot ROM / U-Boot with their output transistors still active.  Switching
    # the IOMUX to GPIO mode (iomux 3 26 0 / iomux 3 27 0) is not sufficient on
    # its own because the peripheral output drivers can bypass the IOMUX on this
    # silicon.  We must disable each controller via its control register first so
    # it releases the pad, then re-assert GPIO mode.
    #
    # GPIO3_D1 (KEY_UP / I2C3_M2_SCL): the IOMUX func-2 workaround (UART5_RTS)
    # routes that pin to an idle-HIGH output, overriding the brief SCL pulses.
    #
    # Register map (RV1106):
    #   I2C3  base 0xff460000  – CON  register at offset 0x00 → 0xff460000
    #   PWM1  channel base 0xff350010 (PWM block 0xff350000 + channel-1 * 0x10)
    #         CTRL register at channel offset 0x0C → 0xff35001C
    if ! grep -qi "luckfox.*pico.*pi" /proc/device-tree/model 2>/dev/null; then
        return 0
    fi

    log_message "Pi: resetting I2C3 and PWM1 controllers to release button pins..."

    python3 - <<'PYEOF' 2>/dev/null || true
import mmap, struct

def write32(addr, val):
    page = addr & ~0xFFF
    off  = addr &  0xFFF
    with open('/dev/mem', 'r+b', buffering=0) as f:
        m = mmap.mmap(f.fileno(), 0x1000, offset=page)
        struct.pack_into('<I', m, off, val)
        m.close()

# Disable I2C3 master to release GPIO3_D2 (I2C3_M2_SDA / KEY_LEFT).
# Writing 0 to I2C_CON clears the enable and any pending START/STOP bits,
# stopping the state machine and turning off the open-drain SDA transistor.
write32(0xff460000, 0)

# Disable PWM1 output to release GPIO3_D3 (PWM1_M2 / KEY2).
# PWM_CTRL bit-0 = timer enable, bit-3 = output enable; clearing both stops
# the PWM signal and tristates the push-pull output driver.
write32(0xff35001C, 0)
PYEOF

    # Restore GPIO mode on the now-released pads.
    iomux 3 26 0 2>/dev/null || true   # GPIO3_D2 → GPIO (KEY_LEFT)
    iomux 3 27 0 2>/dev/null || true   # GPIO3_D3 → GPIO (KEY2)

    # KEY_UP (GPIO3_D1 / I2C3_M2_SCL): route to UART5_RTS (func 2).
    # UART5 is unused so RTS idles HIGH, overriding brief I2C SCL pulses.
    iomux 3 25 2 2>/dev/null || true

    log_message "Pi: button pin reset complete"
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
