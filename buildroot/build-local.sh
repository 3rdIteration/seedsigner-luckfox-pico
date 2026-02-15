#!/bin/bash
# SeedSigner Local Build Script (No Docker)
# Automates the complete build process for Ubuntu 22.04
# Mirrors the GitHub Actions workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(dirname "$SCRIPT_DIR")"

# Default Python version for buildroot (matches GitHub Actions workflow)
DEFAULT_PYTHON_VERSION="3.11"
DEFAULT_LUCKFOX_REPO_URL="https://github.com/3rdIteration/luckfox-pico.git"
DEFAULT_LUCKFOX_REPO_BRANCH="copilot/enable-glibc-highest-version"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_header() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }
print_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
print_error() { echo -e "${RED}[ERROR] $1${NC}"; }
print_info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

show_usage() {
    cat << 'USAGE'
SeedSigner Local Build System (No Docker)
Tested on Ubuntu 22.04

Usage: ./build-local.sh [options]

Options:
  --hardware TYPE    - Hardware type: mini|max (default: mini)
  --boot MEDIUM      - Boot medium: sd|nand (default: sd)
  --check-deps       - Check and install missing dependencies
  --clone-only       - Only clone repositories and exit
  --clean            - Clean previous build artifacts
  --help, -h         - Show this help

Examples:
  ./build-local.sh                              # Build Mini with SD card
  ./build-local.sh --hardware max --boot sd     # Build Max with SD card
  ./build-local.sh --hardware mini --boot nand  # Build Mini with NAND
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
        git clone "$DEFAULT_LUCKFOX_REPO_URL" --depth=1 -b "$DEFAULT_LUCKFOX_REPO_BRANCH" --single-branch
        print_success "luckfox-pico cloned"
    else
        print_info "luckfox-pico already exists"
    fi
    
    # Clone SeedSigner OS packages
    if [ ! -d "seedsigner-os" ]; then
        print_info "Cloning seedsigner-os packages..."
        git clone https://github.com/seedsigner/seedsigner-os.git --depth=1 --single-branch
        print_success "seedsigner-os cloned"
    else
        print_info "seedsigner-os already exists"
    fi
    
    # Clone SeedSigner application code
    if [ ! -d "seedsigner" ]; then
        print_info "Cloning seedsigner application..."
        git clone https://github.com/lightningspore/seedsigner.git --depth=1 -b upstream-luckfox-staging-1 --single-branch --recurse-submodules
        print_success "seedsigner cloned"
    else
        print_info "seedsigner already exists"
    fi
    
    print_success "All repositories available"
}

setup_toolchain() {
    print_header "Setting Up Toolchain Environment"
    
    cd "$WORK_DIR/luckfox-pico"
    
    local toolchain_dir
    toolchain_dir=$(find tools/linux/toolchain -mindepth 1 -maxdepth 1 -type d \( -name '*glibc*' -o -name '*gnueabihf*' \) | head -n 1)
    if [ -z "$toolchain_dir" ]; then
        toolchain_dir=$(find tools/linux/toolchain -mindepth 1 -maxdepth 1 -type d | head -n 1)
    fi
    
    if [ ! -f "$toolchain_dir/env_install_toolchain.sh" ]; then
        print_error "Toolchain environment script not found"
        exit 1
    fi
    
    print_info "Sourcing toolchain environment..."
    cd "$toolchain_dir"
    source env_install_toolchain.sh
    cd "$WORK_DIR/luckfox-pico"
    
    # Verify toolchain
    local cc_bin="${CROSS_COMPILE}gcc"
    if ! which "$cc_bin" > /dev/null 2>&1; then
        print_error "Toolchain compiler not found in PATH: $cc_bin"
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
    print_info "Copying SeedSigner packages..."
    cp -rv "$WORK_DIR/seedsigner-os/opt/external-packages/"* "$package_dir/"
    
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
	source "package/python-pillow/Config.in"
	source "package/zbar/Config.in"
	source "package/jpeg-turbo/Config.in.options"
	source "package/jpeg/Config.in"
	source "package/python-qrcode/Config.in"
	source "package/python-pyqrcode/Config.in"
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
    
    print_info "Building Applications..."
    ./build.sh app
    
    print_success "System build complete"
}

install_seedsigner_app() {
    local hardware="$1"
    
    print_header "Installing SeedSigner Application"
    
    cd "$WORK_DIR/luckfox-pico"
    
    # Find rootfs directory
    local rootfs_dir=$(find output/out -maxdepth 1 -type d -name "rootfs_glibc_*" | head -n 1)
    if [ -z "$rootfs_dir" ]; then
        rootfs_dir=$(find output/out -maxdepth 1 -type d -name "rootfs_*" | head -n 1)
    fi
    
    if [ -z "$rootfs_dir" ]; then
        print_error "Rootfs directory not found"
        exit 1
    fi
    
    print_info "Using rootfs: $rootfs_dir"
    
    # Copy SeedSigner code
    print_info "Copying SeedSigner application..."
    cp -rv "$WORK_DIR/seedsigner/src/" "$rootfs_dir/seedsigner"
    
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
    
    print_success "SeedSigner application installed"
}

package_firmware() {
    print_header "Packaging Firmware"
    
    cd "$WORK_DIR/luckfox-pico"
    
    ./build.sh firmware
    
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
        uboot.img boot.img oem.img userdata.img
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
                if [[ -n "$2" && "$2" =~ ^(mini|max)$ ]]; then
                    hardware="$2"
                    shift 2
                else
                    print_error "Invalid hardware type. Use: mini|max"
                    exit 1
                fi
                ;;
            --boot)
                if [[ -n "$2" && "$2" =~ ^(sd|nand)$ ]]; then
                    boot_medium="$2"
                    shift 2
                else
                    print_error "Invalid boot medium. Use: sd|nand"
                    exit 1
                fi
                ;;
            --check-deps)
                check_deps_only=true
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
    
    if [ "$clone_only" == "true" ]; then
        print_success "Repositories cloned. Exiting."
        exit 0
    fi
    
    # Full build process
    setup_toolchain
    configure_board "$hardware" "$boot_medium"
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
    else
        echo "  1. Extract the NAND bundle (.tar.gz)"
        echo "  2. Flash using official LuckFox tools"
        echo "  3. See: https://wiki.luckfox.com/Luckfox-Pico/Linux-MacOS-Burn-Image/"
    fi
}

# Run main with all arguments
main "$@"
