# GitHub Actions Build Failure Fix

## Problem
GitHub Actions builds were failing at different stages with toolchain-related errors.

### Error 1: Missing External Toolchain (Makefile.param)
```
/bin/bash: line 1: arm-rockchip830-linux-uclibcgnueabihf-gcc: command not found
```

### Error 2: Wrong Toolchain Name
```
/bin/bash: line 1: arm-buildroot-linux-gnueabihf-gcc: command not found
```

### Error 3: Stub Used for U-Boot Compilation (First Occurrence)
```
Warning: Stub toolchain called for compilation - buildroot should use internal toolchain
make[2]: *** [scripts/Makefile.autoconf:79: u-boot.cfg] Error 1
```

### Error 4: Missing Toolchain in build.sh
```
[build.sh:error] Not found toolchain arm-buildroot-linux-gnueabihf-gcc for [rv1106] !!!
```

### Error 5: Stub Still Used for U-Boot Compilation (Final Issue)
```
Warning: Stub toolchain called for compilation - buildroot should use internal toolchain
make[2]: *** [scripts/Makefile.autoconf:79: u-boot.cfg] Error 1
```

## Root Cause

The SDK's build system has **multiple toolchain checks** at different stages, and buildroot's internal toolchain is only created **during the rootfs build**:

1. **Makefile.param check**: `sysdrv/Makefile.param` checks before buildroot_create
2. **build.sh check**: `build.sh` checks before starting uboot/kernel/rootfs builds
3. **Toolchain creation timing**: Buildroot creates its internal GCC 13 toolchain **during `./build.sh rootfs`**
4. **Build order issue**: Building uboot/kernel before rootfs meant no internal toolchain existed yet
5. **Different toolchain names**: New SDK uses `arm-buildroot-linux-gnueabihf-gcc`

## Solution Evolution

### Attempt 1 (Commit d5c8240)
Created stub for `arm-rockchip830-linux-uclibcgnueabihf-gcc`
- ✅ Passed Makefile.param check
- ❌ Wrong toolchain name for new SDK

### Attempt 2 (Commit bb4c0e7)
Added stub for `arm-buildroot-linux-gnueabihf-gcc`
- ✅ Passed Makefile.param check
- ❌ Stub persisted globally

### Attempt 3 (Commit 4dc4464)
Limited stub PATH scope to buildroot_create step
- ✅ Stub scoped properly
- ❌ build.sh also needed toolchain check to pass

### Attempt 4 (Commit a13d7d7)
Added stub to PATH in "Build system" step
- ✅ build.sh validation passed
- ❌ Stub used during uboot compilation (toolchain didn't exist yet)

### Final Solution (Commit 67ce84d)
**Changed build order: rootfs FIRST, then remove stub, then uboot/kernel**

## Implementation

### Stub Creation (One-time)
Creates two stub scripts in `/tmp/stub-toolchain/`:

1. **arm-buildroot-linux-gnueabihf-gcc** (new SDK)
2. **arm-rockchip830-linux-uclibcgnueabihf-gcc** (legacy)

Each stub:
```bash
#!/bin/bash
if [ "$1" = "--version" ] || [ "$1" = "-v" ]; then
  echo "arm-buildroot-linux-gnueabihf-gcc (stub for buildroot) 13.0.0"
  exit 0
fi
echo "Warning: Stub toolchain called for compilation - buildroot should use internal toolchain" >&2
exit 1
```

### PATH Management

**Step 1: Prepare buildroot source tree**
```yaml
- name: Prepare buildroot source tree
  run: |
    cd luckfox-pico
    export PATH="/tmp/stub-toolchain:$PATH"
    make buildroot_create -C sysdrv
```

**Step 2: Build system (CRITICAL ORDER)**
```yaml
- name: Build system
  run: |
    cd luckfox-pico
    
    # Stub in PATH for build.sh validation
    export PATH="/tmp/stub-toolchain:$PATH"
    
    # Build rootfs FIRST - creates buildroot's internal toolchain
    ./build.sh rootfs
    
    # Remove stub from PATH - no longer needed
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/tmp/stub-toolchain" | tr '\n' ':' | sed 's/:$//')
    
    # Build uboot/kernel using buildroot's internal toolchain
    ./build.sh uboot
    ./build.sh kernel
    ./build.sh media
    ./build.sh app
```

## Benefits
- ✅ Passes SDK's Makefile.param toolchain check
- ✅ Passes SDK's build.sh toolchain check
- ✅ Supports both old and new SDK toolchain names
- ✅ Buildroot creates internal GCC 13 toolchain during rootfs build
- ✅ Stub removed before uboot/kernel builds (prevents accidental use)
- ✅ All compilation uses buildroot's internal GCC 13 toolchain

## Verification
Expected workflow:
1. "Create stub toolchain" - Creates stub scripts
2. "Prepare buildroot source tree" - Stub in PATH passes Makefile.param check, buildroot source prepared
3. "Build system":
   - Stub in PATH for build.sh validation
   - `./build.sh rootfs` - Buildroot compiles internal GCC 13 toolchain
   - Remove stub from PATH
   - `./build.sh uboot` - Uses buildroot's internal toolchain (not stub)
   - `./build.sh kernel` - Uses buildroot's internal toolchain
   - `./build.sh media` - Uses buildroot's internal toolchain
   - `./build.sh app` - Uses buildroot's internal toolchain
4. Build completes successfully

## Technical Notes

### Why Build Rootfs First?
Buildroot only creates its internal toolchain when building the root filesystem. The toolchain is located at:
```
luckfox-pico/sysdrv/source/buildroot/buildroot-2024.11.4/output/host/bin/
```

This toolchain is not available until after the rootfs build completes. Building uboot/kernel first would mean they'd try to use the stub (which errors) or fail to find a toolchain at all.

### PATH Manipulation
The command to remove the stub from PATH:
```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/tmp/stub-toolchain" | tr '\n' ':' | sed 's/:$//')
```
- Splits PATH on colons
- Filters out the stub toolchain directory
- Rejoins with colons
- Removes trailing colon

### Why the Stub Errors on Compilation?
The stub is designed to error immediately if called for compilation. This ensures we catch any issues where it's accidentally being used instead of buildroot's toolchain. The error message helps with debugging.

## Related Files
- `.github/workflows/build.yml` - Stub creation, scoped PATH, build order
- Affected SDK files:
  - `luckfox-pico/sysdrv/Makefile.param` (line 42)
  - `luckfox-pico/build.sh` (toolchain check)
  - `luckfox-pico/sysdrv/source/buildroot/buildroot-2024.11.4/` (toolchain build)

## Commit History
1. **351a53c**: Removed external toolchain setup
2. **d5c8240**: Added stub for `arm-rockchip830-linux-uclibcgnueabihf-gcc`
3. **bb4c0e7**: Added stub for `arm-buildroot-linux-gnueabihf-gcc`
4. **4dc4464**: Limited stub PATH scope to buildroot_create
5. **a13d7d7**: Added stub to PATH in "Build system" step
6. **67ce84d**: Changed build order - rootfs first, then remove stub, then uboot/kernel
