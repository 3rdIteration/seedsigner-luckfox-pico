#!/bin/sh
#
# configure-gpio.sh — Configure GPIO pins for SeedSigner buttons on LuckFox Pico
#
# This script auto-detects the LuckFox Pico variant and uses the busybox `io`
# utility to write the correct RV1106 IOC / GPIO registers so that every button
# pin is set to: GPIO function, input direction, pull-up bias, input buffer
# enabled.
#
# Register values are derived from:
#   docs/Rockchip_RV1106_User_Manual_GPIO.pdf
#   (https://github.com/user-attachments/files/16725839/Rockchip_RV1106_User_Manual_GPIO.pdf)
#
# Pin assignments come from the Seedsigner io_config.json profiles:
#   FOX_22  = "luckfox pico mini"     (22-pin connector)
#   FOX_40  = "luckfox pico pro max"  (40-pin connector)
#   FOX_PI  = "luckfox pico pi"       (Pi-style 40-pin connector)
#
# Usage:  configure-gpio.sh
#   Exits 0 on success, 1 if the variant is unknown.

set -e

LOG_TAG="configure-gpio"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$LOG_TAG] $1"
}

# ---------------------------------------------------------------------------
# Helper: write a 32-bit value via the busybox io utility.
# Silently skip if the io command is not available.
# ---------------------------------------------------------------------------
io_write() {
    io -4 "$1" "$2" 2>/dev/null || log_msg "WARN: io write failed: io -4 $1 $2"
}

# ---------------------------------------------------------------------------
# Per-pin configuration functions
# Each function applies four register writes:
#   1. IOMUX  → GPIO function  (value 0 in the mux field)
#   2. Pull   → pull-up        (Rockchip write-mask format)
#   3. Dir    → input           (DDR bit = 0)
#   4. IE     → enable          (input buffer on)
#
# Register addresses and values are taken directly from the RV1106 GPIO manual.
# ---------------------------------------------------------------------------

configure_GPIO0_A0() {
    log_msg "  GPIO0_A0 (gpiochip0 line 0)"
    io_write 0xFF388000 0x00070000    # IOMUX = GPIO
    io_write 0xFF388038 0x00030001    # Pull  = pull-up
    io_write 0xFF380008 0x00010000    # Dir   = input
    io_write 0xFF388030 0x00010001    # IE    = enable
}

configure_GPIO0_A1() {
    log_msg "  GPIO0_A1 (gpiochip0 line 1)"
    io_write 0xFF388000 0x00700000    # IOMUX = GPIO
    io_write 0xFF388038 0x000C0004    # Pull  = pull-up
    io_write 0xFF380008 0x00020000    # Dir   = input
    io_write 0xFF388030 0x00020002    # IE    = enable
}

configure_GPIO0_A4() {
    log_msg "  GPIO0_A4 (gpiochip0 line 4)"
    io_write 0xFF388004 0x00070000    # IOMUX = GPIO
    io_write 0xFF388038 0x03000100    # Pull  = pull-up
    io_write 0xFF380008 0x00100000    # Dir   = input
    io_write 0xFF388030 0x00100010    # IE    = enable
}

configure_GPIO1_B2() {
    log_msg "  GPIO1_B2 (gpiochip1 line 10)"
    io_write 0xFF538008 0x07000000    # IOMUX = GPIO
    io_write 0xFF5381C4 0x00300010    # Pull  = pull-up
    io_write 0xFF530008 0x04000000    # Dir   = input
    io_write 0xFF538184 0x00040004    # IE    = enable
}

configure_GPIO1_B3() {
    log_msg "  GPIO1_B3 (gpiochip1 line 11)"
    io_write 0xFF538008 0x70000000    # IOMUX = GPIO
    io_write 0xFF5381C4 0x00C00040    # Pull  = pull-up
    io_write 0xFF530008 0x08000000    # Dir   = input
    io_write 0xFF538184 0x00080008    # IE    = enable
}

configure_GPIO1_C4() {
    log_msg "  GPIO1_C4 (gpiochip1 line 20)"
    io_write 0xFF538014 0x00070000    # IOMUX = GPIO
    io_write 0xFF5381C8 0x03000100    # Pull  = pull-up
    io_write 0xFF53000C 0x00100000    # Dir   = input
    io_write 0xFF538188 0x00100010    # IE    = enable
}

configure_GPIO1_C5() {
    log_msg "  GPIO1_C5 (gpiochip1 line 21)"
    io_write 0xFF538014 0x00700000    # IOMUX = GPIO
    io_write 0xFF5381C8 0x0C000400    # Pull  = pull-up
    io_write 0xFF53000C 0x00200000    # Dir   = input
    io_write 0xFF538188 0x00200020    # IE    = enable
}

configure_GPIO1_C6() {
    log_msg "  GPIO1_C6 (gpiochip1 line 22)"
    io_write 0xFF538014 0x07000000    # IOMUX = GPIO
    io_write 0xFF5381C8 0x30001000    # Pull  = pull-up
    io_write 0xFF53000C 0x00400000    # Dir   = input
    io_write 0xFF538188 0x00400040    # IE    = enable
}

configure_GPIO1_C7() {
    log_msg "  GPIO1_C7 (gpiochip1 line 23)"
    io_write 0xFF538014 0x70000000    # IOMUX = GPIO
    io_write 0xFF5381C8 0xC0004000    # Pull  = pull-up
    io_write 0xFF53000C 0x00800000    # Dir   = input
    io_write 0xFF538188 0x00800080    # IE    = enable
}

configure_GPIO1_D0() {
    log_msg "  GPIO1_D0 (gpiochip1 line 24)"
    io_write 0xFF538018 0x00070000    # IOMUX = GPIO
    io_write 0xFF5381CC 0x00030001    # Pull  = pull-up
    io_write 0xFF53000C 0x01000000    # Dir   = input
    io_write 0xFF53818C 0x00010001    # IE    = enable
}

configure_GPIO1_D1() {
    log_msg "  GPIO1_D1 (gpiochip1 line 25)"
    io_write 0xFF538018 0x00700000    # IOMUX = GPIO
    io_write 0xFF5381CC 0x000C0004    # Pull  = pull-up
    io_write 0xFF53000C 0x02000000    # Dir   = input
    io_write 0xFF53818C 0x00020002    # IE    = enable
}

configure_GPIO1_D2() {
    log_msg "  GPIO1_D2 (gpiochip1 line 26)"
    io_write 0xFF538018 0x07000000    # IOMUX = GPIO
    io_write 0xFF5381CC 0x00300010    # Pull  = pull-up
    io_write 0xFF53000C 0x04000000    # Dir   = input
    io_write 0xFF53818C 0x00040004    # IE    = enable
}

configure_GPIO1_D3() {
    log_msg "  GPIO1_D3 (gpiochip1 line 27)"
    io_write 0xFF538018 0x70000000    # IOMUX = GPIO
    io_write 0xFF5381CC 0x00C00040    # Pull  = pull-up
    io_write 0xFF53000C 0x08000000    # Dir   = input
    io_write 0xFF53818C 0x00080008    # IE    = enable
}

configure_GPIO3_D1() {
    log_msg "  GPIO3_D1 (gpiochip3 line 25)"
    io_write 0xFF558058 0x00700000    # IOMUX = GPIO
    io_write 0xFF5581EC 0x000C0004    # Pull  = pull-up
    io_write 0xFF55000C 0x02000000    # Dir   = input
    io_write 0xFF5581AC 0x00020002    # IE    = enable
}

configure_GPIO3_D2() {
    log_msg "  GPIO3_D2 (gpiochip3 line 26)"
    io_write 0xFF558058 0x07000000    # IOMUX = GPIO
    io_write 0xFF5581EC 0x00300010    # Pull  = pull-up
    io_write 0xFF55000C 0x04000000    # Dir   = input
    io_write 0xFF5581AC 0x00040004    # IE    = enable
}

configure_GPIO3_D3() {
    log_msg "  GPIO3_D3 (gpiochip3 line 27)"
    io_write 0xFF558058 0x70000000    # IOMUX = GPIO
    io_write 0xFF5581EC 0x00C00040    # Pull  = pull-up
    io_write 0xFF55000C 0x08000000    # Dir   = input
    io_write 0xFF5581AC 0x00080008    # IE    = enable
}

configure_GPIO4_C1() {
    # GPIO4 is in the VCCIO6 domain with a different IOC layout.
    # Pull encoding: 0=normal, 1=pull-down, 3=pull-up  (differs from GPIO0-3).
    # Pull and IE share register 0xFF5680C0 at different bit fields.
    # Pull bits [13:14] are shared between C0 and C1 in this IOC block.
    log_msg "  GPIO4_C1 (gpiochip4 line 17)"
    io_write 0xFF568010 0x00700000    # IOMUX = GPIO
    io_write 0xFF5680C0 0x60006000    # Pull  = pull-up  (bits[13:14]=11)
    io_write 0xFF56000C 0x00020000    # Dir   = input
    io_write 0xFF5680C0 0x00080008    # IE    = enable   (bit 3)
}

# ---------------------------------------------------------------------------
# Variant-specific configuration
# Pin-to-button mapping from Seedsigner io_config.json
# ---------------------------------------------------------------------------

configure_fox_22() {
    # FOX_22 — Luckfox Pico Mini (22-pin)
    log_msg "Configuring buttons for Luckfox Pico Mini (FOX_22)..."
    configure_GPIO1_D1    # KEY_UP     (gpiochip1 line 25)
    configure_GPIO1_D3    # KEY_DOWN   (gpiochip1 line 27)
    configure_GPIO1_D0    # KEY_LEFT   (gpiochip1 line 24)
    configure_GPIO1_C6    # KEY_RIGHT  (gpiochip1 line 22)
    configure_GPIO1_D2    # KEY_PRESS  (gpiochip1 line 26)
    configure_GPIO1_C7    # KEY1       (gpiochip1 line 23)
    configure_GPIO0_A4    # KEY2       (gpiochip0 line 4)
    configure_GPIO1_C5    # KEY3       (gpiochip1 line 21)
}

configure_fox_40() {
    # FOX_40 — Luckfox Pico Pro Max (40-pin)
    log_msg "Configuring buttons for Luckfox Pico Pro Max (FOX_40)..."
    configure_GPIO1_D2    # KEY_UP     (gpiochip1 line 26)
    configure_GPIO1_C5    # KEY_DOWN   (gpiochip1 line 21)
    configure_GPIO1_D3    # KEY_LEFT   (gpiochip1 line 27)
    configure_GPIO1_C6    # KEY_RIGHT  (gpiochip1 line 22)
    configure_GPIO1_C4    # KEY_PRESS  (gpiochip1 line 20)
    configure_GPIO1_C7    # KEY1       (gpiochip1 line 23)
    configure_GPIO1_B3    # KEY2       (gpiochip1 line 11)
    configure_GPIO1_B2    # KEY3       (gpiochip1 line 10)
}

configure_fox_pi() {
    # FOX_PI — Luckfox Pico Pi
    log_msg "Configuring buttons for Luckfox Pico Pi (FOX_PI)..."
    configure_GPIO3_D1    # KEY_UP     (gpiochip3 line 25)
    configure_GPIO0_A1    # KEY_DOWN   (gpiochip0 line 1)
    configure_GPIO3_D2    # KEY_LEFT   (gpiochip3 line 26)
    configure_GPIO0_A0    # KEY_RIGHT  (gpiochip0 line 0)
    configure_GPIO1_C4    # KEY_PRESS  (gpiochip1 line 20)
    configure_GPIO4_C1    # KEY1       (gpiochip4 line 17)
    configure_GPIO3_D3    # KEY2       (gpiochip3 line 27)
    configure_GPIO1_C7    # KEY3       (gpiochip1 line 23)
}

# ---------------------------------------------------------------------------
# Auto-detect variant from /proc/device-tree/model
# ---------------------------------------------------------------------------

detect_variant() {
    if [ ! -f /proc/device-tree/model ]; then
        echo "unknown"
        return
    fi

    model=$(tr -d '\0' < /proc/device-tree/model | tr '[:upper:]' '[:lower:]')

    case "$model" in
        *"luckfox pico mini"*)
            echo "fox_22"
            ;;
        *"luckfox pico pro max"*)
            echo "fox_40"
            ;;
        *"luckfox pico pi"*)
            echo "fox_pi"
            ;;
        *"luckfox pico pro"*)
            # "pro" without "max" — use FOX_40 layout (same 40-pin connector)
            echo "fox_40"
            ;;
        *"luckfox pico plus"*)
            # "plus" variant — use FOX_40 layout (same 40-pin connector)
            echo "fox_40"
            ;;
        *"luckfox pico max"*)
            # "max" without "pro" — use FOX_40 layout
            echo "fox_40"
            ;;
        *"luckfox pico"*)
            # Base "luckfox pico" without qualifier — use FOX_22 layout
            echo "fox_22"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if ! command -v io >/dev/null 2>&1; then
    log_msg "ERROR: 'io' command not found (busybox io utility required)"
    exit 1
fi

variant=$(detect_variant)
log_msg "Detected variant: $variant"

case "$variant" in
    fox_22)
        configure_fox_22
        ;;
    fox_40)
        configure_fox_40
        ;;
    fox_pi)
        configure_fox_pi
        ;;
    *)
        log_msg "ERROR: Unknown LuckFox Pico variant — GPIO not configured"
        exit 1
        ;;
esac

log_msg "GPIO button configuration complete."
