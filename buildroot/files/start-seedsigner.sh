#!/bin/bash

# Configuration
MAX_RETRIES=5
RETRY_DELAY=10  # seconds
CAMERA_START_TIMEOUT=20  # max seconds to wait for app init signal
CAMERA_POLL_INTERVAL=1   # seconds
CAMERA_POST_SPI_DELAY=5  # seconds to wait after SPI init detection
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

start_camera_service_later() {
    local target_pid="$1"
    (
        local waited=0
        while [ "$waited" -lt "$CAMERA_START_TIMEOUT" ]; do
            if ! kill -0 "$target_pid" 2>/dev/null; then
                return 0
            fi

            # Wait for SeedSigner to initialize the SPI display first.
            if ls -l "/proc/$target_pid/fd" 2>/dev/null | grep -q 'spidev'; then
                log_message "Detected SeedSigner SPI device init; waiting ${CAMERA_POST_SPI_DELAY}s before starting camera service"
                sleep "$CAMERA_POST_SPI_DELAY"
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
    log_message "Starting SeedSigner (attempt $((retry_count + 1))/$MAX_RETRIES)"
    
    # Start SeedSigner first. On Mini, camera ISP start before display init can
    # exhaust memory and cause SPI open failures.
    python main.py &
    APP_PID="$!"
    start_camera_service_later "$APP_PID"

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
