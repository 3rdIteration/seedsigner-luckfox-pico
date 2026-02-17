#!/bin/bash
# SeedSigner Self-Contained Build Script - No Home Directory Pollution!
# All repositories cloned inside container - completely portable

set -e

# Environment setup - everything happens inside /build
export BUILD_DIR="/build"
export REPOS_DIR="/build/repos"
export OUTPUT_DIR="/build/output"

# Repository URLs for cloning
export LUCKFOX_REPO_URL="https://github.com/3rdIteration/luckfox-pico.git"
export SEEDSIGNER_REPO_URL="https://github.com/3rdIteration/seedsigner.git"
export SEEDSIGNER_BRANCH="luckfox-staging-portability"
export SEEDSIGNER_OS_REPO_URL="https://github.com/3rdIteration/seedsigner-os.git"

# Internal paths (after cloning)
export LUCKFOX_SDK_DIR="$REPOS_DIR/luckfox-pico"
export SEEDSIGNER_CODE_DIR="$REPOS_DIR/seedsigner"
export SEEDSIGNER_OS_DIR="$REPOS_DIR/seedsigner-os"
export SEEDSIGNER_LUCKFOX_DIR="/build"

# Common paths (computed after SDK directory is determined)
export BUILDROOT_DIR="${LUCKFOX_SDK_DIR}/sysdrv/source/buildroot/buildroot-2023.02.6"
export PACKAGE_DIR="${BUILDROOT_DIR}/package"
export CONFIG_IN="${PACKAGE_DIR}/Config.in"
export PYZBAR_PATCH="${PACKAGE_DIR}/python-pyzbar/0001-PATH-fixed-by-hand.patch"
export ROOTFS_DIR="${LUCKFOX_SDK_DIR}/output/out/rootfs_uclibc_rv1106"

# Parallel build configuration
export BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
export MAKEFLAGS="-j${BUILD_JOBS}"
export BR2_JLEVEL="${BUILD_JOBS}"
export FORCE_UNSAFE_CONFIGURE=1
export BUILD_MODEL="${BUILD_MODEL:-both}"
export MINI_CMA_SIZE="${MINI_CMA_SIZE:-1M}"

# Colors for output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_step() { echo -e "\n${BLUE}[STEP] $1${NC}\n"; }
print_success() { echo -e "\n${GREEN}[SUCCESS] $1${NC}\n"; }
print_error() { echo -e "\n${RED}[ERROR] $1${NC}\n"; }
print_info() { echo -e "\n${YELLOW}[INFO] $1${NC}\n"; }

show_usage() {
    echo "SeedSigner Self-Contained Build System"
    echo "Usage: $0 [auto|auto-nand|auto-nand-only|interactive|shell|clone-only]"
    echo ""
    echo "  auto        - Run full automated SD-card image build (default)"
    echo "  auto-nand   - Run automated build + NAND-flashable image packaging"
    echo "  interactive - Clone repos + drop into interactive shell"
    echo "  shell       - Drop directly into shell (no setup)"
    echo "  clone-only  - Only clone repositories and exit"
    echo ""
    echo "Features:"
    echo "  - All repositories cloned inside container"
    echo "  - No host directory pollution"
    echo "  - Self-contained and portable"
    echo "  - SD artifacts for multiple board labels (default: mini,max)"
    echo "  - Model selector via BUILD_MODEL=mini|max|both"
    echo "  - Mini CMA override via MINI_CMA_SIZE (default: 1M)"
    echo ""
}

clone_repositories() {
    print_step "Cloning Required Repositories"
    
    mkdir -p "$REPOS_DIR"
    cd "$REPOS_DIR"
    
    # Clone luckfox-pico SDK
    if [[ ! -d "luckfox-pico" ]]; then
        print_info "Cloning luckfox-pico SDK..."
        git clone "$LUCKFOX_REPO_URL" --depth=1 --single-branch luckfox-pico
        print_success "luckfox-pico cloned"
    else
        print_info "luckfox-pico already exists"
    fi
    
    # Clone SeedSigner OS packages
    if [[ ! -d "seedsigner-os" ]]; then
        print_info "Cloning seedsigner-os packages..."
        git clone "$SEEDSIGNER_OS_REPO_URL" --depth=1 --single-branch seedsigner-os
        print_success "seedsigner-os cloned"
    else
        print_info "seedsigner-os already exists"
    fi
    
    # Clone SeedSigner code (specific branch)
    if [[ ! -d "seedsigner" ]]; then
        print_info "Cloning seedsigner code (branch: $SEEDSIGNER_BRANCH)..."
        git clone "$SEEDSIGNER_REPO_URL" --depth=1 -b "$SEEDSIGNER_BRANCH" --single-branch --recurse-submodules seedsigner
        print_success "seedsigner cloned"
    else
        print_info "seedsigner already exists"
    fi
    
    # Show repository status
    print_info "Repository Status:"
    echo "  luckfox-pico: $(du -sh luckfox-pico 2>/dev/null | cut -f1 || echo 'missing')"
    echo "  seedsigner-os: $(du -sh seedsigner-os 2>/dev/null | cut -f1 || echo 'missing')"  
    echo "  seedsigner: $(du -sh seedsigner 2>/dev/null | cut -f1 || echo 'missing')"
    echo "  Total: $(du -sh . 2>/dev/null | cut -f1 || echo 'unknown')"
    
    print_success "All repositories cloned successfully"
}

apply_sdk_patches() {
    print_step "Applying SeedSigner SDK Patches"
    
    cd "$LUCKFOX_SDK_DIR"
    
    # Show files before patching
    print_info "Checking target files..."
    if [ -f project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk ]; then
        echo "  ${GREEN}✓${NC} Mini BoardConfig found"
    else
        print_error "Mini BoardConfig NOT FOUND!"
        cd "$REPOS_DIR"
        return 1
    fi
    
    if [ -f project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk ]; then
        echo "  ${GREEN}✓${NC} Max BoardConfig found"
    else
        print_error "Max BoardConfig NOT FOUND!"
        cd "$REPOS_DIR"
        return 1
    fi
    echo ""
    
    # Apply Mini SPI-NAND partition optimization
    print_info "Applying Mini SPI-NAND partition optimization..."
    if patch -p1 --verbose < /build/buildroot/patches/luckfox-sdk/001-optimize-mini-spi-nand-partitions.patch; then
        echo "  ${GREEN}✓${NC} Mini SPI-NAND patch applied successfully"
    else
        EXIT_CODE=$?
        print_error "Failed to apply Mini SPI-NAND patch (exit code: $EXIT_CODE)"
        print_error "This may be a fatal error for SPI-NAND builds"
    fi
    echo ""
    
    # Apply Max SPI-NAND partition optimization
    print_info "Applying Max SPI-NAND partition optimization..."
    if patch -p1 --verbose < /build/buildroot/patches/luckfox-sdk/002-optimize-max-spi-nand-partitions.patch; then
        echo "  ${GREEN}✓${NC} Max SPI-NAND patch applied successfully"
    else
        EXIT_CODE=$?
        print_error "Failed to apply Max SPI-NAND patch (exit code: $EXIT_CODE)"
        print_error "This may be a fatal error for SPI-NAND builds"
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
    if echo "$MINI_PARTITION" | grep -q "0x6300000@0x1D00000(rootfs)"; then
        echo "  ${GREEN}✓${NC} Mini partition optimization VERIFIED (rootfs = 99MB)"
    else
        echo "  ${YELLOW}⚠${NC}  WARNING: Mini partition may not be optimized!"
    fi
    
    if echo "$MAX_PARTITION" | grep -q "0x6300000@0x1D00000(rootfs)"; then
        echo "  ${GREEN}✓${NC} Max partition optimization VERIFIED (rootfs = 99MB)"
    else
        echo "  ${YELLOW}⚠${NC}  WARNING: Max partition may not be optimized!"
    fi
    echo ""
    
    print_success "Partition layout optimized:"
    echo "  - OEM: 30MB → 24MB (save 6MB, provides headroom for 16.4MB usage)"
    echo "  - Userdata: 6MB → Removed (save 6MB, SeedSigner is stateless)"
    echo "  - Rootfs: 85MB → 99MB (add 14MB, total 28MB gained)"
    echo ""
    
    cd "$REPOS_DIR"
}

validate_environment() {
    print_step "Validating Build Environment"
    
    local required_dirs=(
        "$LUCKFOX_SDK_DIR"
        "$SEEDSIGNER_CODE_DIR"  
        "$SEEDSIGNER_OS_DIR"
    )
    
    local required_items=(
        "$LUCKFOX_SDK_DIR/build.sh"
        "$SEEDSIGNER_CODE_DIR/src"
        "$SEEDSIGNER_OS_DIR/opt/external-packages"
    )
    
    local missing_dirs=()
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
            echo "[ERROR] Missing: $dir"
        else
            echo "[OK] Found: $dir"
        fi
    done
    
    local missing_items=()
    for item in "${required_items[@]}"; do
        if [[ ! -e "$item" ]]; then
            missing_items+=("$item")
            echo "[ERROR] Missing: $item"
        else
            echo "[OK] Found: $item"
        fi
    done
    
    if [[ ${#missing_dirs[@]} -ne 0 || ${#missing_items[@]} -ne 0 ]]; then
        print_error "Environment validation failed"
        echo "Missing directories: ${missing_dirs[*]}"
        echo "Missing items: ${missing_items[*]}"
        echo "Try running with 'clone-only' mode first to setup repositories"
        exit 1
    fi
    
    print_success "Environment validation complete"
}

setup_sdk_environment() {
    print_step "Setting Up SDK Environment"
    
    cd "$LUCKFOX_SDK_DIR"
    
    # Initialize SDK if needed (creates .BoardConfig.mk)
    if [[ ! -f ".BoardConfig.mk" ]]; then
        print_info "Initializing SDK (first time setup)..."
        # Run the SDK init which creates the board config
        echo -e "\n\n\n" | timeout 10s ./build.sh lunch 2>/dev/null || {
            print_info "SDK lunch completed (timeout expected)"
        }
    fi
    
    # Source the toolchain environment
    local toolchain_dir="$LUCKFOX_SDK_DIR/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf"
    if [[ -f "$toolchain_dir/env_install_toolchain.sh" ]]; then
        print_info "Sourcing toolchain environment..."
        cd "$toolchain_dir"
        set +e  # Temporarily disable exit on error
        source env_install_toolchain.sh 2>/dev/null
        local source_result=$?
        set -e  # Re-enable exit on error
        
        cd "$LUCKFOX_SDK_DIR"
        print_success "Toolchain environment configured"
    else
        print_error "Toolchain environment script not found at: $toolchain_dir/env_install_toolchain.sh"
        exit 1
    fi
}



select_board_profile() {
    local board_profile="$1"
    local boot_medium="$2"

    local hw_index
    local boot_index

    case "$board_profile" in
        mini)
            hw_index=1
            ;;
        max)
            hw_index=4
            ;;
        *)
            print_error "Unsupported board profile: $board_profile (expected: mini,max)"
            exit 1
            ;;
    esac

    case "$boot_medium" in
        sd)
            boot_index=0
            ;;
        nand)
            boot_index=1
            ;;
        *)
            print_error "Unsupported boot medium: $boot_medium (expected: sd,nand)"
            exit 1
            ;;
    esac

    print_step "Selecting SDK board profile: ${board_profile} (${boot_medium})"
    printf "%s
%s
0
" "$hw_index" "$boot_index" | ./build.sh lunch
}


apply_mini_cma_profile() {
    if [[ "$board_profile" != "mini" ]]; then
        return
    fi

    print_step "Applying Mini CMA profile (${MINI_CMA_SIZE})"

    local cfg_dir="$LUCKFOX_SDK_DIR/project/cfg/BoardConfig_IPC"
    if [[ ! -d "$cfg_dir" ]]; then
        print_error "BoardConfig directory not found: $cfg_dir"
        exit 1
    fi

    local cfg_files=("$cfg_dir"/BoardConfig-*-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk)
    local found=false

    for cfg in "${cfg_files[@]}"; do
        [[ -f "$cfg" ]] || continue
        found=true
        if grep -q '^export RK_BOOTARGS_CMA_SIZE=' "$cfg"; then
            sed -i "s|^export RK_BOOTARGS_CMA_SIZE=.*|export RK_BOOTARGS_CMA_SIZE=\"${MINI_CMA_SIZE}\"|" "$cfg"
        else
            echo "export RK_BOOTARGS_CMA_SIZE=\"${MINI_CMA_SIZE}\"" >> "$cfg"
        fi
        print_info "Updated CMA size in: $cfg"
    done

    if [[ "$found" == "false" ]]; then
        print_error "No Mini board config files found under: $cfg_dir"
        exit 1
    fi
}

resolve_rootfs_dir() {
    local pattern="$LUCKFOX_SDK_DIR/output/out/rootfs_uclibc_*"
    local matches=( $pattern )

    if [[ ${#matches[@]} -eq 0 ]]; then
        print_error "Could not find rootfs output directory matching: $pattern"
        exit 1
    fi

    export ROOTFS_DIR="${matches[0]}"
    print_info "Using rootfs directory: $ROOTFS_DIR"
}

create_nand_image_artifacts() {
    local board_profile="$1"
    local ts="$2"
    local profile_medium="${3:-unknown}"

    print_step "Creating NAND-Flashable Image Artifacts (${board_profile})"

    local image_dir="$LUCKFOX_SDK_DIR/output/image"

    if [[ ! -d "$image_dir" ]]; then
        print_error "Image output directory not found: $image_dir"
        exit 1
    fi

    cd "$image_dir"

    if [[ ! -f "update.img" ]]; then
        print_error "update.img not found. Run './build.sh firmware' before NAND packaging."
        exit 1
    fi

    local nand_bundle_dir="$OUTPUT_DIR/seedsigner-luckfox-pico-${board_profile}-nand-files-${ts}"
    mkdir -p "$nand_bundle_dir"

    local required_bundle_files=(
        update.img
        download.bin
        env.img
        idblock.img
        uboot.img
        boot.img
        oem.img
        userdata.img
        rootfs.img
        sd_update.txt
        tftp_update.txt
    )

    local missing_bundle_files=()
    for file in "${required_bundle_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp -v "$file" "$nand_bundle_dir/"
        else
            missing_bundle_files+=("$file")
        fi
    done

    if [[ ${#missing_bundle_files[@]} -ne 0 ]]; then
        print_error "Missing required NAND bundle files: ${missing_bundle_files[*]}"
        exit 1
    fi

    if [[ "$profile_medium" == "nand" ]]; then
        validate_nand_oriented_output "$image_dir"
    elif ! grep -q "mtd " "$nand_bundle_dir/sd_update.txt" 2>/dev/null; then
        print_info "Bundle for ${board_profile} (${profile_medium}) does not contain SPI-NAND mtd script commands."
    fi

    cat > "$nand_bundle_dir/README.txt" << 'EOF'
SeedSigner Luckfox NAND Flash Bundle

Contains SDK-generated NAND flashing files:
- update.img / download.bin
- partition images (*.img)
- U-Boot scripts: sd_update.txt and tftp_update.txt

Flash guidance:
- Use update.img with official Luckfox/Rockchip upgrade tooling, or
- Use sd_update.txt / tftp_update.txt with U-Boot workflows.
EOF

    local nand_bundle="seedsigner-luckfox-pico-${board_profile}-nand-bundle-${ts}.tar.gz"
    tar -czf "$OUTPUT_DIR/$nand_bundle" -C "$OUTPUT_DIR" "$(basename "$nand_bundle_dir")"
    print_success "NAND bundle folder created: $nand_bundle_dir"
    print_success "NAND bundle archive created: $OUTPUT_DIR/$nand_bundle"
}


validate_nand_oriented_output() {
    local image_dir="$1"

    local sd_script="$image_dir/sd_update.txt"
    local tftp_script="$image_dir/tftp_update.txt"

    for script in "$sd_script" "$tftp_script"; do
        if [[ ! -f "$script" ]]; then
            print_error "Missing NAND validation script: $script"
            exit 1
        fi

        if grep -q "mmc write" "$script"; then
            print_error "Invalid NAND output: found 'mmc write' in $(basename "$script")"
            exit 1
        fi

        if ! grep -q "mtd " "$script"; then
            print_error "Invalid NAND output: missing 'mtd' commands in $(basename "$script")"
            exit 1
        fi
    done

    print_success "Validated NAND-oriented update scripts"
}


export_official_nand_image_dir() {
    local board_profile="$1"
    local ts="$2"
    local image_root="$LUCKFOX_SDK_DIR/IMAGE"

    if [[ ! -d "$image_root" ]]; then
        print_info "No SDK IMAGE directory found at: $image_root"
        return 0
    fi

    local latest_dir
    latest_dir=$(find "$image_root" -maxdepth 1 -type d -name 'IPC_SPI_NAND_BUILDROOT_*' | sort | tail -n 1)

    if [[ -z "$latest_dir" ]]; then
        print_info "No SPI_NAND IMAGE export directory found under: $image_root"
        return 0
    fi

    local bundle_name="seedsigner-luckfox-pico-${board_profile}-nand-sdk-images-${ts}.tar.gz"
    tar -czf "$OUTPUT_DIR/$bundle_name" -C "$image_root" "$(basename "$latest_dir")"
    print_success "Exported official SDK NAND image directory: $OUTPUT_DIR/$bundle_name"
}

ensure_buildroot_tree() {
    if [[ -d "$BUILDROOT_DIR" ]]; then
        return
    fi

    print_step "Preparing Buildroot Source Tree"
    make buildroot_create -C "$LUCKFOX_SDK_DIR/sysdrv"

    if [[ ! -d "$BUILDROOT_DIR" ]]; then
        print_error "Buildroot directory not found after buildroot_create: $BUILDROOT_DIR"
        exit 1
    fi
}

build_profile_artifacts() {
    local board_profile="$1"
    local boot_medium="$2"
    local include_nand="$3"

    cd "$LUCKFOX_SDK_DIR"
    select_board_profile "$board_profile" "$boot_medium"
    apply_mini_cma_profile

    print_step "Cleaning Previous Build (${board_profile}/${boot_medium})"
    ./build.sh clean

    # Some SDK clean paths may reset board context; force board selection again.
    select_board_profile "$board_profile" "$boot_medium"

    print_step "Preparing Buildroot Configuration (${board_profile}/${boot_medium})"
    ensure_buildroot_tree

    print_step "Installing SeedSigner Packages"
    cp -rv "$SEEDSIGNER_OS_DIR/opt/external-packages/"* "$PACKAGE_DIR/"

    print_step "Updating pyzbar Configuration"
    if [[ -f "$PYZBAR_PATCH" ]]; then
        sed -i 's|path = ".*/site-packages/zbar.so"|path = "/usr/lib/python3.11/site-packages/zbar.so"|' "$PYZBAR_PATCH"
    fi

    print_step "Adding SeedSigner Menu to Buildroot"
    if ! grep -q '^menu "SeedSigner"$' "$CONFIG_IN"; then
        cat << 'CONFIGMENU' >> "$CONFIG_IN"
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
        source "$BR2_EXTERNAL_SEEDSIGNER_PATH/package/python-pyscard/Config.in"
        source "$BR2_EXTERNAL_SEEDSIGNER_PATH/package/python-pysatochip/Config.in"
endmenu
CONFIGMENU
    fi

    print_step "Applying SeedSigner Configuration"
    if [[ -f "/build/configs/luckfox_pico_defconfig" ]]; then
        cp -v "/build/configs/luckfox_pico_defconfig" "$BUILDROOT_DIR/configs/luckfox_pico_defconfig"
        cp -v "/build/configs/luckfox_pico_defconfig" "$BUILDROOT_DIR/.config"
    else
        print_error "SeedSigner configuration file not found"
        exit 1
    fi

    print_step "Building U-Boot"
    ./build.sh uboot

    print_step "Building Kernel"
    ./build.sh kernel

    print_step "Building Rootfs"
    ./build.sh rootfs

    print_step "Building Media Support"
    ./build.sh media

    print_step "Building Applications"
    ./build.sh app

    resolve_rootfs_dir

    print_step "Installing SeedSigner Code"
    cp -rv "$SEEDSIGNER_CODE_DIR/src/" "$ROOTFS_DIR/seedsigner"
    
    print_step "Cleaning up non-essential files from rootfs"
    # Remove documentation, hardware files, git metadata, and test files
    # These are kept in the repo but shouldn't be in the final image
    rm -rf "$ROOTFS_DIR/seedsigner/../docs" 2>/dev/null || true
    rm -rf "$ROOTFS_DIR/seedsigner/../hardware-kicad" 2>/dev/null || true
    rm -rf "$ROOTFS_DIR/seedsigner/../img" 2>/dev/null || true
    rm -rf "$ROOTFS_DIR/seedsigner/../test_suite" 2>/dev/null || true
    rm -rf "$ROOTFS_DIR/seedsigner/../.git" 2>/dev/null || true
    rm -f "$ROOTFS_DIR/seedsigner/../.gitignore" 2>/dev/null || true
    rm -f "$ROOTFS_DIR/seedsigner/../.gitmodules" 2>/dev/null || true
    rm -f "$ROOTFS_DIR/seedsigner/../README.md" 2>/dev/null || true
    print_success "Cleaned up non-essential files"

    [[ -f "/build/files/luckfox.cfg" ]] && cp -v "/build/files/luckfox.cfg" "$ROOTFS_DIR/etc/luckfox.cfg"
    [[ -f "/build/files/nv12_converter" ]] && cp -v "/build/files/nv12_converter" "$ROOTFS_DIR/"
    [[ -f "/build/files/start-seedsigner.sh" ]] && cp -v "/build/files/start-seedsigner.sh" "$ROOTFS_DIR/"
    [[ -f "/build/files/S99seedsigner" ]] && cp -v "/build/files/S99seedsigner" "$ROOTFS_DIR/etc/init.d/"

    print_step "Packaging Firmware"
    ./build.sh firmware

    cd "$LUCKFOX_SDK_DIR/output/image"

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    export LAST_PROFILE_BUILD_TS="$ts"
    if [[ "$board_profile" == "mini" ]]; then
        export LAST_MINI_BUILD_TS="$ts"
    elif [[ "$board_profile" == "max" ]]; then
        export LAST_MAX_BUILD_TS="$ts"
    fi

    if [[ "$boot_medium" == "sd" ]]; then
        print_step "Creating Final SD Image (${board_profile})"

        local sd_image="seedsigner-luckfox-pico-${board_profile}-sd-${ts}.img"

        if [[ -f "/build/blkenvflash" ]]; then
            "/build/blkenvflash" "$sd_image"
        else
            print_error "blkenvflash tool not found"
            exit 1
        fi

        if [[ ! -f "$sd_image" ]]; then
            print_error "Expected SD image not created: $sd_image"
            exit 1
        fi

        cp -v "$sd_image" "$OUTPUT_DIR/"
        print_success "SD image created for ${board_profile}: $OUTPUT_DIR/$sd_image"
    fi

    if [[ "$include_nand" == "true" ]]; then
        print_step "Packaging NAND artifacts (${board_profile})"
        create_nand_image_artifacts "$board_profile" "$ts" "$boot_medium"
        export_official_nand_image_dir "$board_profile" "$ts"
    fi

    cd "$LUCKFOX_SDK_DIR"
}

run_automated_build() {
    local build_nand_image="${1:-false}"
    local build_sd_image="${2:-true}"

    print_step "Starting Automated SeedSigner Build"

    print_info "Build Configuration:"
    echo "   CPU Cores Available: $(nproc)"
    echo "   Build Jobs: $BUILD_JOBS"
    echo "   MAKEFLAGS: $MAKEFLAGS"
    echo "   Build Directory: $BUILD_DIR"
    echo "   Output Directory: $OUTPUT_DIR"

    clone_repositories
    apply_sdk_patches
    validate_environment
    setup_sdk_environment

    mkdir -p "$OUTPUT_DIR"

    cd "$LUCKFOX_SDK_DIR"

    if [[ "$build_sd_image" == "true" ]]; then
        if [[ "$BUILD_MODEL" == "mini" || "$BUILD_MODEL" == "both" ]]; then
            build_profile_artifacts "mini" "sd" "false"
        fi
        if [[ "$BUILD_MODEL" == "max" || "$BUILD_MODEL" == "both" ]]; then
            build_profile_artifacts "max" "sd" "false"
        fi
    fi

    # Build NAND/flash bundles using official SPI_NAND build flow.
    if [[ "$build_nand_image" == "true" ]]; then
        if [[ "$BUILD_MODEL" == "mini" || "$BUILD_MODEL" == "both" ]]; then
            print_step "Generating NAND-Oriented Output (mini, official flow)"
            build_profile_artifacts "mini" "nand" "true"
        fi

        if [[ "$BUILD_MODEL" == "max" || "$BUILD_MODEL" == "both" ]]; then
            print_step "Generating NAND-Oriented Output (max, official flow)"
            build_profile_artifacts "max" "nand" "true"
        fi
    fi

    print_success "Build Complete!"
    echo ""
    echo "Build artifacts:"
    ls -la "$OUTPUT_DIR/"
}

start_interactive_mode() {
    print_step "Starting Interactive Mode"
    
    clone_repositories
    apply_sdk_patches
    validate_environment
    setup_sdk_environment
    
    print_success "Environment ready!"
    echo ""
    echo "Available commands:"
    echo "  - cd $LUCKFOX_SDK_DIR && ./build.sh [command]"
    echo "  - /build/docker-automation.sh auto  # Run full build"
    echo "  - exit  # Exit interactive mode"
    echo ""
    echo "Build artifacts will be available in: $OUTPUT_DIR"
    
    # Switch to SDK directory for convenience
    cd "$LUCKFOX_SDK_DIR"
    exec /bin/bash
}

# Main entry point
main() {
    local mode="${1:-auto}"
    
    case "$mode" in
        "auto")
            print_info "Starting automated MicroSD build mode..."
            run_automated_build false true
            ;;
        "auto-nand")
            print_info "Starting automated build mode with MicroSD + NAND packaging..."
            run_automated_build true true
            ;;
        "auto-nand-only")
            print_info "Starting automated NAND-only build mode..."
            run_automated_build true false
            ;;
        "interactive")
            print_info "Starting interactive mode..."
            start_interactive_mode
            ;;
        "shell")
            print_info "Starting direct shell..."
            exec /bin/bash
            ;;
        "clone-only")
            print_info "Cloning repositories only..."
            clone_repositories
            apply_sdk_patches
            print_success "Repositories cloned and patches applied. Container exiting."
            ;;
        "help"|"-h"|"--help")
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown mode: $mode"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
