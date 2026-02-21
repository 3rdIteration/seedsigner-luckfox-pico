#!/bin/bash
# SeedSigner Local Build Script (No Docker)
# Automates the complete build process for Ubuntu 22.04
# Mirrors the GitHub Actions workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(dirname "$SCRIPT_DIR")"

# Default Python version for buildroot (used if detection fails)
DEFAULT_PYTHON_VERSION="3.12"
DISABLE_UART2_CONSOLE_DEBUG="${DISABLE_UART2_CONSOLE_DEBUG:-1}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
print_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
print_error() { echo -e "${RED}[ERROR] $1${NC}"; }
print_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

debug_uart_bootargs_file() {
    local file_path="$1"
    local label="$2"
    print_info "UART bootargs debug (${label}): $file_path"
    if [ -f "$file_path" ]; then
        grep -nE 'ttyFIQ0|console=|earlycon=|user_debug=|CMDLINE|BOOTARGS' "$file_path" || echo "  (no matching bootarg tokens)"
    else
        echo "  (file not found)"
    fi
}

debug_uart_bootargs_outputs() {
    local image_dir="$WORK_DIR/luckfox-pico/output/image"
    print_info "UART bootargs debug (output image files): $image_dir"
    if [ ! -d "$image_dir" ]; then
        echo "  (output image directory not found)"
        return 0
    fi

    local found=false
    local f
    for f in "$image_dir"/*.txt "$image_dir"/*.cfg "$image_dir"/*.ini "$image_dir"/parameter*; do
        if [ ! -e "$f" ]; then
            continue
        fi
        found=true
        echo "  checking: $(basename "$f")"
        grep -nE 'ttyFIQ0|console=|earlycon=|user_debug=|CMDLINE|BOOTARGS' "$f" || echo "    (no matching bootarg tokens)"
    done

    if [ "$found" != "true" ]; then
        echo "  (no text-like image metadata files found)"
    fi
}

resolve_dts_path_for_hardware() {
    local hardware="$1"
    local dts_dir="$WORK_DIR/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts"
    local dts_file=""

    case "$hardware" in
        mini)
            dts_file="$dts_dir/rv1103g-luckfox-pico-mini.dts"
            ;;
        max)
            dts_file="$dts_dir/rv1106g-luckfox-pico-pro-max.dts"
            ;;
        *)
            print_error "Unknown hardware type for DTS patch: $hardware"
            exit 1
            ;;
    esac

    if [ ! -f "$dts_file" ]; then
        print_error "DTS file not found for UART2 console patch: $dts_file"
        exit 1
    fi

    echo "$dts_file"
}

resolve_dtsi_path_for_hardware() {
    local hardware="$1"
    local dts_dir="$WORK_DIR/luckfox-pico/sysdrv/source/kernel/arch/arm/boot/dts"
    local dtsi_file=""

    case "$hardware" in
        mini)
            dtsi_file="$dts_dir/rv1103-luckfox-pico-ipc.dtsi"
            ;;
        max)
            dtsi_file="$dts_dir/rv1106-luckfox-pico-pro-max-ipc.dtsi"
            ;;
        *)
            print_error "Unknown hardware type for DTSI patch: $hardware"
            exit 1
            ;;
    esac

    if [ ! -f "$dtsi_file" ]; then
        print_error "DTSI file not found for UART2 console patch: $dtsi_file"
        exit 1
    fi

    echo "$dtsi_file"
}

show_usage() {
    cat << 'USAGE'
SeedSigner Local Build System (No Docker)
Tested on Ubuntu 22.04

Usage: ./build-local.sh [options]

Options:
  --hardware TYPE    - Hardware type: mini|max|pi (default: mini)
  --boot MEDIUM      - Boot medium: sd|nand|emmc (default: sd)
  --enable-uart2-console - Keep UART2 console/debug enabled (default: disabled)
  --check-deps       - Check and install missing dependencies
  --clone-only       - Only clone repositories and exit
  --clean            - Clean previous build artifacts
  --help, -h         - Show this help

Examples:
  ./build-local.sh                              # Build Mini with SD card
  ./build-local.sh --hardware max --boot sd     # Build Max with SD card
  ./build-local.sh --hardware mini --boot nand  # Build Mini with NAND
  ./build-local.sh --hardware pi --boot emmc    # Build Pico Pi with eMMC
  ./build-local.sh --check-deps                 # Install dependencies
  ./build-local.sh --clone-only                 # Only clone repos

Build Process:
  1. Check/install dependencies (Ubuntu 22.04 required)
  2. Clone required repositories
  3. Set up toolchain environment
  4. Configure board (hardware + boot medium)
  5. Build U-Boot, kernel, rootfs, media, apps
  6. Install SeedSigner application
  7. Package firmware and create flashable images

Output:
  - SD images: luckfox-pico/output/image/*.img
  - NAND bundles: luckfox-pico/output/image/*.tar.gz
  - eMMC bundles: luckfox-pico/output/image/*.tar.gz

Repository Locations:
  - luckfox-pico: $WORK_DIR/luckfox-pico
  - seedsigner: $WORK_DIR/seedsigner
  - seedsigner-os: $WORK_DIR/seedsigner-os

Performance:
  First build: 60-120 minutes
  Subsequent builds: 30-60 minutes
USAGE
}

check_ubuntu_version() {
    print_header "Checking Ubuntu Version"
    
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        print_warning "This script is tested on Ubuntu 22.04"
        print_warning "Detected OS: $ID $VERSION_ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    elif [ "$VERSION_ID" != "22.04" ]; then
        print_warning "This script is tested on Ubuntu 22.04"
        print_warning "Detected version: $VERSION_ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Ubuntu 22.04 detected"
    fi
}

check_and_install_dependencies() {
    print_header "Checking Dependencies"
    
    local packages=(
        git ssh make gcc gcc-multilib g++-multilib
        module-assistant expect g++ gawk texinfo
        libssl-dev bison flex fakeroot cmake unzip
        gperf autoconf device-tree-compiler
        libncurses5-dev pkg-config bc python-is-python3
        passwd openssl openssh-server openssh-client
        vim file cpio rsync
    )
    
    local missing_packages=()
    
    for pkg in "${packages[@]}"; do
        # Use dpkg-query for reliable package detection
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing_packages+=("$pkg")
        fi
    done
    
    if [ ${#missing_packages[@]} -eq 0 ]; then
        print_success "All dependencies installed"
        return 0
    fi
    
    print_warning "Missing packages: ${missing_packages[*]}"
    
    if [ "$1" == "auto" ]; then
        print_info "Installing missing packages..."
        sudo apt-get update
        sudo apt-get install -y "${missing_packages[@]}"
        print_success "Dependencies installed"
    else
        echo "Run with --check-deps to install missing packages"
        exit 1
    fi
}

clone_repositories() {
    print_header "Cloning Required Repositories"
    
    cd "$WORK_DIR"
    
    # Clone luckfox-pico SDK
    if [ ! -d "luckfox-pico" ]; then
        print_info "Cloning luckfox-pico SDK..."
        git clone https://github.com/3rdIteration/luckfox-pico.git --depth=1 --single-branch
        print_success "luckfox-pico cloned"
    else
        print_info "luckfox-pico already exists"
    fi
    
    # Clone SeedSigner OS packages
    if [ ! -d "seedsigner-os" ]; then
        print_info "Cloning seedsigner-os packages..."
        git clone https://github.com/3rdIteration/seedsigner-os.git --depth=1 --single-branch
        print_success "seedsigner-os cloned"
    else
        print_info "seedsigner-os already exists"
    fi
    
    # Clone SeedSigner application code
    if [ ! -d "seedsigner" ]; then
        print_info "Cloning seedsigner application..."
        git clone https://github.com/3rdIteration/seedsigner.git --depth=1 -b luckfox-staging-portability --single-branch --recurse-submodules
        print_success "seedsigner cloned"
    else
        print_info "seedsigner already exists"
    fi
    
    print_success "All repositories available"
}

apply_sdk_patches() {
    print_header "Applying SeedSigner SDK Patches"
    
    cd "$WORK_DIR/luckfox-pico"
    
    # Show files before patching
    print_info "Checking target files..."
    if [ -f project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk ]; then
        print_success "Mini BoardConfig found"
    else
        print_error "Mini BoardConfig NOT FOUND!"
        cd "$WORK_DIR"
        return 1
    fi
    
    if [ -f project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk ]; then
        print_success "Max BoardConfig found"
    else
        print_error "Max BoardConfig NOT FOUND!"
        cd "$WORK_DIR"
        return 1
    fi
    echo ""
    
    # Apply Mini SPI-NAND partition optimization using sed (more reliable than patches)
    print_info "Applying Mini SPI-NAND partition optimization..."
    MINI_FILE="project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk"
    # Remove userdata from partition table and shrink OEM, expand rootfs
    sed -i 's/30M(oem),6M(userdata),85M(rootfs)/20M(oem),99M(rootfs)/' "$MINI_FILE"
    # Remove userdata from filesystem config
    sed -i 's/,userdata@\/userdata@ubifs//' "$MINI_FILE"
    print_success "Mini SPI-NAND partition modified (sed)"
    echo ""
    
    # Apply Max SPI-NAND partition optimization using sed
    print_info "Applying Max SPI-NAND partition optimization..."
    MAX_FILE="project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk"
    # Remove userdata from partition table and shrink OEM, expand rootfs
    sed -i 's/30M(oem),10M(userdata),210M(rootfs)/20M(oem),227M(rootfs)/' "$MAX_FILE"
    # Remove userdata from filesystem config
    sed -i 's/,userdata@\/userdata@ubifs//' "$MAX_FILE"
    print_success "Max SPI-NAND partition modified (sed)"
    echo ""
    
    # Apply Pi eMMC partition update to remove userdata.img expectation
    print_info "Applying Pi eMMC partition update..."
    PI_FILE="project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk"
    if [ -f "$PI_FILE" ]; then
        sed -i 's/,256M(userdata),/,/' "$PI_FILE"
        sed -i 's/,userdata@\/userdata@ext4//' "$PI_FILE"
        print_success "Pi eMMC userdata removed from partition/fs config (sed)"
    else
        print_warning "Pi eMMC BoardConfig not found, skipping"
    fi
    echo ""

    # Verify patches were applied by checking partition sizes
    print_info "Verifying patches..."
    MINI_PARTITION=$(grep "RK_PARTITION_CMD_IN_ENV=" project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk | head -1)
    MAX_PARTITION=$(grep "RK_PARTITION_CMD_IN_ENV=" project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk | head -1)
    
    echo "  Mini partition table:"
    echo "    $MINI_PARTITION"
    echo ""
    echo "  Max partition table:"
    echo "    $MAX_PARTITION"
    echo ""
    
    # Check if patches actually modified the files
    if echo "$MINI_PARTITION" | grep -q "99M(rootfs)"; then
        print_success "Mini partition optimization VERIFIED (rootfs = 103MB)"
    else
        print_warning "WARNING: Mini partition may not be optimized!"
    fi
    
    if echo "$MAX_PARTITION" | grep -q "227M(rootfs)"; then
        print_success "Max partition optimization VERIFIED (rootfs = 103MB)"
    else
        print_warning "WARNING: Max partition may not be optimized!"
    fi
    echo ""
    
    print_success "Partition layout optimized:"
    echo "  - OEM: 30MB → 20MB (save 10MB, 16.4MB used + 3.6MB headroom)"
    echo "  - Userdata: 6MB → Removed (save 6MB, SeedSigner is stateless)"
    echo "  - Rootfs: 85MB → 103MB (add 18MB, total 34MB gained)"
    echo ""
    
    # Show partition summary
    print_info "SPI-NAND Partition Summary (128MB flash):"
    echo "  ┌─────────────┬──────────┬────────────┬─────────────┐"
    echo "  │ Partition   │ Size     │ Offset     │ Purpose     │"
    echo "  ├─────────────┼──────────┼────────────┼─────────────┤"
    echo "  │ env         │   256 KB │ 0x00000    │ Environment │"
    echo "  │ idblock     │   256 KB │ 0x40000    │ Boot ID     │"
    echo "  │ uboot       │   512 KB │ 0x80000    │ U-Boot      │"
    echo "  │ boot        │     4 MB │ 0x100000   │ Kernel+DTB  │"
    echo "  │ oem         │    20 MB │ 0x500000   │ OEM data    │"
    echo "  │ rootfs      │   103 MB │ 0x1900000  │ Root FS     │"
    echo "  └─────────────┴──────────┴────────────┴─────────────┘"
    echo "  Total allocated: ~128 MB (fits 128MB SPI-NAND)"
    echo ""
    
    cd "$WORK_DIR"
}

setup_toolchain() {
    print_header "Setting Up Toolchain Environment"
    
    cd "$WORK_DIR/luckfox-pico"
    
    local toolchain_dir="tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf"
    
    if [ ! -f "$toolchain_dir/env_install_toolchain.sh" ]; then
        print_error "Toolchain environment script not found"
        exit 1
    fi
    
    print_info "Sourcing toolchain environment..."
    cd "$toolchain_dir"
    source env_install_toolchain.sh
    cd "$WORK_DIR/luckfox-pico"
    
    # Verify toolchain
    if ! which arm-rockchip830-linux-uclibcgnueabihf-gcc > /dev/null 2>&1; then
        print_error "Toolchain not found in PATH"
        exit 1
    fi
    
    print_success "Toolchain configured"
}

configure_board() {
    local hardware="$1"
    local boot_medium="$2"
    
    print_header "Configuring Board: $hardware with $boot_medium"
    
    cd "$WORK_DIR/luckfox-pico"
    
    local hw_index
    case "$hardware" in
        mini)
            hw_index=1
            ;;
        max)
            hw_index=4
            ;;
        pi)
            hw_index=7
            ;;
        *)
            print_error "Unknown hardware type: $hardware"
            exit 1
            ;;
    esac
    
    local boot_index
    case "$boot_medium" in
        sd)
            boot_index=0
            ;;
        nand)
            boot_index=1
            ;;
        emmc)
            boot_index=0
            ;;
        *)
            print_error "Unknown boot medium: $boot_medium"
            exit 1
            ;;
    esac
    
    print_info "Running SDK board configuration..."
    printf "%s\n%s\n%s\n" "$hw_index" "$boot_index" "0" | ./build.sh lunch
    
    if [ ! -f ".BoardConfig.mk" ]; then
        print_error "Board config file not created"
        exit 1
    fi
    
    print_success "Board configured"
}

apply_mini_cma_config() {
    local hardware="$1"
    local boot_medium="$2"
    
    if [ "$hardware" != "mini" ]; then
        return 0
    fi
    
    print_header "Applying CMA Memory Configuration for Mini"
    
    cd "$WORK_DIR/luckfox-pico"
    
    # Map hardware and boot medium to SDK naming convention (matching GitHub Actions)
    local sdk_hardware
    case "$hardware" in
        mini)
            sdk_hardware="RV1103_Luckfox_Pico_Mini"
            ;;
        max)
            sdk_hardware="RV1106_Luckfox_Pico_Pro_Max"
            ;;
        *)
            print_error "Unknown hardware type: $hardware"
            exit 1
            ;;
    esac
    
    local sdk_boot_medium
    case "$boot_medium" in
        sd)
            sdk_boot_medium="SD_CARD"
            ;;
        nand)
            sdk_boot_medium="SPI_NAND"
            ;;
        emmc)
            sdk_boot_medium="EMMC"
            ;;
        *)
            print_error "Unknown boot medium: $boot_medium"
            exit 1
            ;;
    esac
    
    # Construct board config path matching GitHub Actions workflow
    local board_config="project/cfg/BoardConfig_IPC/BoardConfig-${sdk_boot_medium}-Buildroot-${sdk_hardware}-IPC.mk"
    
    if [ ! -f "$board_config" ]; then
        print_error "Board config file not found: $board_config"
        exit 1
    fi
    
    print_info "Using board config: $board_config"
    
    local cma_size="1M"
    
    if grep -q '^export RK_BOOTARGS_CMA_SIZE=' "$board_config"; then
        sed -i "s|^export RK_BOOTARGS_CMA_SIZE=.*|export RK_BOOTARGS_CMA_SIZE=\"${cma_size}\"|" "$board_config"
        print_info "Updated existing CMA size in: $board_config"
    else
        echo "export RK_BOOTARGS_CMA_SIZE=\"${cma_size}\"" >> "$board_config"
        print_info "Added CMA size to: $board_config"
    fi
    
    # Verify the change
    print_info "Current CMA configuration:"
    grep 'RK_BOOTARGS_CMA_SIZE' "$board_config" || print_warning "No CMA configuration found (will use default)"
    
    print_success "CMA size set to $cma_size"
}

apply_uart2_console_config() {
    local hardware="$1"
    local boot_medium="$2"

    if [ "$DISABLE_UART2_CONSOLE_DEBUG" != "1" ]; then
        print_info "UART2 console debug left enabled (DISABLE_UART2_CONSOLE_DEBUG=${DISABLE_UART2_CONSOLE_DEBUG})"
        return 0
    fi

    print_header "Disabling UART2 Console Debug"

    cd "$WORK_DIR/luckfox-pico"

    local sdk_hardware
    case "$hardware" in
        mini)
            sdk_hardware="RV1103_Luckfox_Pico_Mini"
            ;;
        max)
            sdk_hardware="RV1106_Luckfox_Pico_Pro_Max"
            ;;
        *)
            print_error "Unknown hardware type: $hardware"
            exit 1
            ;;
    esac

    local sdk_boot_medium
    case "$boot_medium" in
        sd)
            sdk_boot_medium="SD_CARD"
            ;;
        nand)
            sdk_boot_medium="SPI_NAND"
            ;;
        *)
            print_error "Unknown boot medium: $boot_medium"
            exit 1
            ;;
    esac

    local board_config="project/cfg/BoardConfig_IPC/BoardConfig-${sdk_boot_medium}-Buildroot-${sdk_hardware}-IPC.mk"

    if [ ! -f "$board_config" ] && [ -L ".BoardConfig.mk" ]; then
        board_config="$(readlink -f .BoardConfig.mk)"
    fi

    if [ ! -f "$board_config" ]; then
        print_error "Board config file not found for UART2 console config: $board_config"
        exit 1
    fi

    print_info "Updating board config: $board_config"
    debug_uart_bootargs_file "$board_config" "before patch"
    sed -i 's/\<console=ttyFIQ0[^ "]*\>//g; s/\<earlycon=uart8250,[^ "]*\>//g; s/\<user_debug=[^ "]*\>//g' "$board_config"
    debug_uart_bootargs_file "$board_config" "after patch"

    if grep -Eq '(^|[[:space:]])console=ttyFIQ0([^[:space:]]*)?([[:space:]]|$)' "$board_config"; then
        print_error "UART2 console debug removal verification failed: console=ttyFIQ0 still present in $board_config"
        exit 1
    fi

    print_success "UART2 console debug disabled in $board_config"
}

apply_uart2_console_dts_patch() {
    local hardware="$1"

    if [ "$DISABLE_UART2_CONSOLE_DEBUG" != "1" ]; then
        return 0
    fi

    print_header "Disabling UART2 Console Debug in DTS"

    local dts_file dtsi_file target
    dts_file="$(resolve_dts_path_for_hardware "$hardware")"
    dtsi_file="$(resolve_dtsi_path_for_hardware "$hardware")"
    for target in "$dts_file" "$dtsi_file"; do
        debug_uart_bootargs_file "$target" "dts source before patch"
        sed -i 's/\<console=ttyFIQ0[^ "]*\>//g; s/\<earlycon=uart8250,[^ "]*\>//g; s/\<user_debug=[^ "]*\>//g' "$target"
        debug_uart_bootargs_file "$target" "dts source after patch"

        if grep -Eq '(^|[[:space:]])console=ttyFIQ0([^[:space:]]*)?([[:space:]]|$)' "$target"; then
            print_error "UART2 console debug removal verification failed in DTS source: $target"
            exit 1
        fi
    done

    print_success "UART2 console debug disabled in DTS sources: $dts_file, $dtsi_file"
}

prepare_buildroot() {
    print_header "Preparing Buildroot Source Tree"
    
    cd "$WORK_DIR/luckfox-pico"
    
    make buildroot_create -C sysdrv
    
    print_success "Buildroot source tree prepared"
}

install_seedsigner_packages() {
    print_header "Installing SeedSigner Packages"
    
    cd "$WORK_DIR/luckfox-pico"
    
    # Auto-detect buildroot directory
    local buildroot_dir=$(find sysdrv/source/buildroot -maxdepth 1 -type d -name 'buildroot-*' | sort | tail -n 1)
    
    if [ -z "$buildroot_dir" ] || [ ! -d "$buildroot_dir" ]; then
        print_error "Buildroot directory not found"
        exit 1
    fi
    
    print_info "Using buildroot: $buildroot_dir"
    
    local package_dir="${buildroot_dir}/package"
    
    # Copy SeedSigner packages
    print_info "Copying SeedSigner packages from seedsigner-os..."
    cp -rv "$WORK_DIR/seedsigner-os/opt/external-packages/"* "$package_dir/"
    
    # Also copy packages from this repository's external-packages directory
    if [ -d "$SCRIPT_DIR/external-packages" ]; then
        print_info "Copying additional SeedSigner packages from this repository..."
        cp -rv "$SCRIPT_DIR/external-packages/"* "$package_dir/"
    fi
    
    # Add SeedSigner menu to Config.in
    local config_in="${package_dir}/Config.in"
    
    if ! grep -q '^menu "SeedSigner"$' "$config_in"; then
        print_info "Adding SeedSigner menu to buildroot..."
        cat >> "$config_in" << 'EOF'
menu "SeedSigner"
	source "package/python-urtypes/Config.in"
	source "package/python-pyzbar/Config.in"
	source "package/python-mock/Config.in"
	source "package/python-embit/Config.in"
	source "package/python-mnemonic/Config.in"
	source "package/python-shamir-mnemonic/Config.in"
	source "package/python-pillow/Config.in"
	source "package/zbar/Config.in"
	source "package/jpeg-turbo/Config.in.options"
	source "package/jpeg/Config.in"
	source "package/python-qrcode/Config.in"
	source "package/python-pyqrcode/Config.in"
	source "package/python-pyscard/Config.in"
	source "package/python-pysatochip/Config.in"
endmenu
EOF
    fi
    
    print_success "SeedSigner packages installed"
}

apply_seedsigner_config() {
    print_header "Applying SeedSigner Buildroot Configuration"
    
    cd "$WORK_DIR/luckfox-pico"
    
    local buildroot_dir=$(find sysdrv/source/buildroot -maxdepth 1 -type d -name 'buildroot-*' | sort | tail -n 1)
    
    # Copy SeedSigner defconfig
    cp -v "$SCRIPT_DIR/configs/luckfox_pico_defconfig" "$buildroot_dir/configs/luckfox_pico_defconfig"
    # Also copy as luckfox_pico_w_defconfig so the Pi board (RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig)
    # loads our clean config instead of the SDK's WiFi/BT-enabled config
    cp -v "$SCRIPT_DIR/configs/luckfox_pico_defconfig" "$buildroot_dir/configs/luckfox_pico_w_defconfig"
    cp -v "$SCRIPT_DIR/configs/luckfox_pico_defconfig" "$buildroot_dir/.config"
    
    # Update pyzbar patch
    local pyzbar_patch="${buildroot_dir}/package/python-pyzbar/0001-PATH-fixed-by-hand.patch"
    if [ -f "$pyzbar_patch" ] && [ -f "$buildroot_dir/.config" ]; then
        local python_ver=$(grep -oP 'BR2_PACKAGE_PYTHON3_VERSION="\K[^"]+' "$buildroot_dir/.config" 2>/dev/null || echo "")
        
        if [ -z "$python_ver" ]; then
            python_ver="$DEFAULT_PYTHON_VERSION"
            print_warning "Could not detect Python version from buildroot config, using default: $DEFAULT_PYTHON_VERSION"
        else
            print_info "Detected Python version from buildroot config: $python_ver"
        fi
        
        sed -i "s|path = \"/usr/lib/python.*/site-packages/zbar.so\"|path = \"/usr/lib/python${python_ver}/site-packages/zbar.so\"|" "$pyzbar_patch"
        print_info "Updated pyzbar patch for Python $python_ver"
    fi
    
    print_success "SeedSigner configuration applied"
}

build_system() {
    print_header "Building System Components"
    
    cd "$WORK_DIR/luckfox-pico"
    
    print_info "Building U-Boot..."
    ./build.sh uboot
    
    print_info "Building Kernel..."
    ./build.sh kernel
    
    print_info "Building Rootfs..."
    ./build.sh rootfs
    
    print_info "Building Media..."
    ./build.sh media
    
    # Keep vendor RkLunch.sh camera bring-up behavior on all builds.
    print_info "Keeping RkLunch.sh rkipc autostart enabled"
    
    print_info "Building Applications..."
    ./build.sh app
    
    print_success "System build complete"
}

install_seedsigner_app() {
    local hardware="$1"
    
    print_header "Installing SeedSigner Application"
    
    cd "$WORK_DIR/luckfox-pico"
    
    # Find rootfs directory
    local rootfs_dir=$(find output/out -maxdepth 1 -type d -name "rootfs_uclibc_*" | head -n 1)
    
    if [ -z "$rootfs_dir" ]; then
        print_error "Rootfs directory not found"
        exit 1
    fi
    
    print_info "Using rootfs: $rootfs_dir"
    
    # Copy SeedSigner code
    print_info "Copying SeedSigner application..."
    cp -rv "$WORK_DIR/seedsigner/src/" "$rootfs_dir/seedsigner"
    
    # Clean up non-essential files from rootfs
    print_info "Cleaning up non-essential files from rootfs..."
    rm -rf "$rootfs_dir/seedsigner/../docs" 2>/dev/null || true
    rm -rf "$rootfs_dir/seedsigner/../hardware-kicad" 2>/dev/null || true
    rm -rf "$rootfs_dir/seedsigner/../img" 2>/dev/null || true
    rm -rf "$rootfs_dir/seedsigner/../test_suite" 2>/dev/null || true
    rm -rf "$rootfs_dir/seedsigner/../.git" 2>/dev/null || true
    rm -f "$rootfs_dir/seedsigner/../.gitignore" 2>/dev/null || true
    rm -f "$rootfs_dir/seedsigner/../.gitmodules" 2>/dev/null || true
    rm -f "$rootfs_dir/seedsigner/../README.md" 2>/dev/null || true
    print_success "Cleaned up non-essential files"
    
    # Patch settings.json for Mini hardware
    if [ "$hardware" == "mini" ]; then
        local settings_json="$rootfs_dir/seedsigner/settings.json"
        if [ -f "$settings_json" ]; then
            print_info "Patching settings.json for Mini hardware (FOX_22)..."
            sed -i 's/"hardware_config":[[:space:]]*"FOX_40"/"hardware_config": "FOX_22"/g' "$settings_json"
        fi
    fi
    
    # Fix pyzbar library path
    local python_version=$(ls "$rootfs_dir/usr/lib/" | grep -E '^python3\.[0-9]+$' | head -n 1)
    if [ -n "$python_version" ]; then
        print_info "Detected Python version in rootfs: $python_version"
        local site_packages="$rootfs_dir/usr/lib/$python_version/site-packages"
        if [ -f "$site_packages/zbar.so" ]; then
            print_info "Creating zbar.so symlink..."
            ln -sf "$python_version/site-packages/zbar.so" "$rootfs_dir/usr/lib/zbar.so"
        else
            print_warning "zbar.so not found at $site_packages/zbar.so"
        fi
    else
        print_warning "Could not detect Python version in rootfs at $rootfs_dir/usr/lib/"
    fi
    
    # Copy configuration files
    print_info "Copying configuration files..."
    cp -v "$SCRIPT_DIR/files/luckfox.cfg" "$rootfs_dir/etc/luckfox.cfg"
    cp -v "$SCRIPT_DIR/files/nv12_converter" "$rootfs_dir/"
    cp -v "$SCRIPT_DIR/files/start-seedsigner.sh" "$rootfs_dir/"
    cp -v "$SCRIPT_DIR/files/S99seedsigner" "$rootfs_dir/etc/init.d/"
    
    # Install rkaiq camera ISP service script (manual start only, no boot autostart)
    if [[ -f "$SCRIPT_DIR/files/rkaiq-service" ]]; then
        print_info "Installing rkaiq service script..."
        cp -v "$SCRIPT_DIR/files/rkaiq-service" "$rootfs_dir/usr/bin/rkaiq-service"
        chmod +x "$rootfs_dir/usr/bin/rkaiq-service"
        print_success "Installed rkaiq-service to /usr/bin/"
    else
        print_warning "rkaiq-service not found, rkaiq-service will not be available"
    fi
    
    print_success "SeedSigner application installed"
}

package_firmware() {
    print_header "Packaging Firmware"
    
    cd "$WORK_DIR/luckfox-pico"
    
    ./build.sh firmware
    debug_uart_bootargs_outputs
    
    print_success "Firmware packaged"
}

create_sd_image() {
    local hardware="$1"
    
    print_header "Creating SD Card Image"
    
    cd "$WORK_DIR/luckfox-pico/output/image"
    
    local board_label
    case "$hardware" in
        mini) board_label="mini" ;;
        max) board_label="max" ;;
        *) board_label="unknown" ;;
    esac
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local image_name="seedsigner-luckfox-pico-${board_label}-sd-${timestamp}.img"
    
    print_info "Creating image: $image_name"
    
    "$SCRIPT_DIR/blkenvflash" "$image_name"
    
    if [ -f "$image_name" ]; then
        print_success "SD image created: $(pwd)/$image_name"
        ls -lh "$image_name"
    else
        print_error "Failed to create SD image"
        exit 1
    fi
}

create_nand_bundle() {
    local hardware="$1"
    
    print_header "Creating NAND Flash Bundle"
    
    cd "$WORK_DIR/luckfox-pico/output/image"
    
    if [ ! -f "update.img" ]; then
        print_error "update.img not found"
        exit 1
    fi
    
    local board_label
    case "$hardware" in
        mini) board_label="mini" ;;
        max) board_label="max" ;;
        *) board_label="unknown" ;;
    esac
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local nand_bundle_dir="seedsigner-luckfox-pico-${board_label}-nand-files-${timestamp}"
    
    mkdir -p "$nand_bundle_dir"
    
    # Copy required files
    local required_files=(
        update.img download.bin env.img idblock.img
        uboot.img boot.img oem.img
        rootfs.img sd_update.txt tftp_update.txt
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            cp -v "$file" "$nand_bundle_dir/"
        else
            print_warning "Missing file: $file"
        fi
    done
    
    # Create README
    cat > "$nand_bundle_dir/README.txt" << 'EOF'
SeedSigner Luckfox NAND Flash Bundle

Contains SDK-generated NAND flashing files:
- update.img / download.bin
- partition images (*.img)
- U-Boot scripts: sd_update.txt and tftp_update.txt

Flash guidance:
- Use update.img with official Luckfox/Rockchip upgrade tooling, or
- Use sd_update.txt / tftp_update.txt with U-Boot workflows.

For detailed instructions, see:
https://wiki.luckfox.com/Luckfox-Pico/Linux-MacOS-Burn-Image/
EOF
    
    # Create tar.gz archive
    local bundle_name="seedsigner-luckfox-pico-${board_label}-nand-bundle-${timestamp}.tar.gz"
    tar -czf "$bundle_name" "$nand_bundle_dir"
    
    print_success "NAND bundle created: $(pwd)/$bundle_name"
    ls -lh "$bundle_name"
}

create_emmc_bundle() {
    local hardware="$1"
    
    print_header "Creating eMMC Flash Bundle"
    
    cd "$WORK_DIR/luckfox-pico/output/image"
    
    if [ ! -f "update.img" ]; then
        print_error "update.img not found"
        exit 1
    fi
    
    local board_label
    case "$hardware" in
        pi) board_label="pi" ;;
        *) board_label="unknown" ;;
    esac
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local emmc_bundle_dir="seedsigner-luckfox-pico-${board_label}-emmc-files-${timestamp}"
    
    mkdir -p "$emmc_bundle_dir"
    
    # Copy available files to bundle
    local emmc_files=(
        update.img download.bin env.img idblock.img
        uboot.img boot.img oem.img rootfs.img
    )
    
    for file in "${emmc_files[@]}"; do
        if [ -f "$file" ]; then
            cp -v "$file" "$emmc_bundle_dir/"
        else
            print_info "Optional file not found, skipping: $file"
        fi
    done
    
    # Create README
    cat > "$emmc_bundle_dir/README.txt" << 'EOF'
SeedSigner Luckfox eMMC Flash Bundle

Contains SDK-generated eMMC flashing files:
- update.img / download.bin
- partition images (*.img)

Flash guidance:
- Use update.img with official Luckfox SocToolKit (Windows) or rkdeveloptool (Linux/Mac)
- Connect the board in MASKROM mode (hold BOOT button while connecting USB)

For detailed instructions, see:
https://wiki.luckfox.com/Luckfox-Pico-Plus-Mini/Flash-image
EOF
    
    # Create tar.gz archive
    local bundle_name="seedsigner-luckfox-pico-${board_label}-emmc-bundle-${timestamp}.tar.gz"
    tar -czf "$bundle_name" "$emmc_bundle_dir"
    
    print_success "eMMC bundle created: $(pwd)/$bundle_name"
    ls -lh "$bundle_name"
}

clean_build() {
    print_header "Cleaning Build Artifacts"
    
    if [ -d "$WORK_DIR/luckfox-pico" ]; then
        print_info "Cleaning luckfox-pico build..."
        cd "$WORK_DIR/luckfox-pico"
        ./build.sh clean || true
    fi
    
    print_success "Build artifacts cleaned"
}

# Main execution
main() {
    local hardware="mini"
    local boot_medium="sd"
    local check_deps_only=false
    local clone_only=false
    local clean_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hardware)
                if [[ -n "$2" && "$2" =~ ^(mini|max|pi)$ ]]; then
                    hardware="$2"
                    shift 2
                else
                    print_error "Invalid hardware type. Use: mini|max|pi"
                    exit 1
                fi
                ;;
            --boot)
                if [[ -n "$2" && "$2" =~ ^(sd|nand|emmc)$ ]]; then
                    boot_medium="$2"
                    shift 2
                else
                    print_error "Invalid boot medium. Use: sd|nand|emmc"
                    exit 1
                fi
                ;;
            --check-deps)
                check_deps_only=true
                shift
                ;;
            --enable-uart2-console)
                DISABLE_UART2_CONSOLE_DEBUG=0
                shift
                ;;
            --clone-only)
                clone_only=true
                shift
                ;;
            --clean)
                clean_only=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_header "SeedSigner Local Build System"
    print_info "Hardware: $hardware"
    print_info "Boot Medium: $boot_medium"
    print_info "Disable UART2 Console Debug: $DISABLE_UART2_CONSOLE_DEBUG"
    print_info "Working Directory: $WORK_DIR"
    
    # Handle special modes
    if [ "$clean_only" == "true" ]; then
        clean_build
        exit 0
    fi
    
    # Check Ubuntu version
    check_ubuntu_version
    
    # Check/install dependencies
    if [ "$check_deps_only" == "true" ]; then
        check_and_install_dependencies "auto"
        print_success "Dependencies check complete"
        exit 0
    else
        check_and_install_dependencies "check"
    fi
    
    # Clone repositories
    clone_repositories
    
    # Apply SDK patches for SPI-NAND optimization
    apply_sdk_patches
    
    if [ "$clone_only" == "true" ]; then
        print_success "Repositories cloned and patches applied. Exiting."
        exit 0
    fi
    
    # Full build process
    setup_toolchain
    configure_board "$hardware" "$boot_medium"
    apply_uart2_console_config "$hardware" "$boot_medium"
    apply_uart2_console_dts_patch "$hardware"
    apply_mini_cma_config "$hardware" "$boot_medium"
    prepare_buildroot
    install_seedsigner_packages
    apply_seedsigner_config
    
    print_info "Starting build process (this may take 60-120 minutes)..."
    build_system
    
    install_seedsigner_app "$hardware"
    package_firmware
    
    # Create output based on boot medium
    if [ "$boot_medium" == "sd" ]; then
        create_sd_image "$hardware"
    elif [ "$boot_medium" == "emmc" ]; then
        create_emmc_bundle "$hardware"
    else
        create_nand_bundle "$hardware"
    fi
    
    print_header "Build Complete!"
    print_success "Hardware: $hardware"
    print_success "Boot Medium: $boot_medium"
    print_success "Output location: $WORK_DIR/luckfox-pico/output/image/"
    
    echo ""
    print_info "Next steps:"
    if [ "$boot_medium" == "sd" ]; then
        echo "  1. Flash the .img file to an SD card"
        echo "  2. Insert SD card into LuckFox Pico device"
        echo "  3. Power on and enjoy SeedSigner!"
    elif [ "$boot_medium" == "emmc" ]; then
        echo "  1. Extract the eMMC bundle (.tar.gz)"
        echo "  2. Flash using official LuckFox SocToolKit or rkdeveloptool"
        echo "  3. See: https://wiki.luckfox.com/Luckfox-Pico-Plus-Mini/Flash-image"
    else
        echo "  1. Extract the NAND bundle (.tar.gz)"
        echo "  2. Flash using official LuckFox tools"
        echo "  3. See: https://wiki.luckfox.com/Luckfox-Pico/Linux-MacOS-Burn-Image/"
    fi
}

# Run main with all arguments
main "$@"
