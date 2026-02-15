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

### Error 3: Stub Used for U-Boot Compilation (First)
```
Warning: Stub toolchain called for compilation - buildroot should use internal toolchain
make[2]: *** [scripts/Makefile.autoconf:79: u-boot.cfg] Error 1
```

### Error 4: Missing Toolchain in build.sh
```
[build.sh:error] Not found toolchain arm-buildroot-linux-gnueabihf-gcc for [rv1106] !!!
```

### Error 5: Stub Still Used for U-Boot Compilation (Second)
```
Warning: Stub toolchain called for compilation - buildroot should use internal toolchain
make[2]: *** [scripts/Makefile.autoconf:79: u-boot.cfg] Error 1
```

### Error 6: Missing Runtime Libraries (Final Issue)
```
Error: No runtime libraries found at /tmp/runtime_lib
Please build buildroot with: make buildroot
```

## Root Cause

The SDK's build system has complex requirements:

1. **Makefile.param check**: `sysdrv/Makefile.param` checks before buildroot_create
2. **build.sh check**: `build.sh` checks before starting uboot/kernel/rootfs builds
3. **Buildroot compilation**: Must use `make buildroot` (not `./build.sh rootfs`) to properly build toolchain
4. **Runtime libraries**: Created at `/tmp/runtime_lib` during buildroot build
5. **Build order**: Buildroot must be built FIRST before any components
6. **Different toolchain names**: New SDK uses `arm-buildroot-linux-gnueabihf-gcc`

## Solution Evolution

### Attempt 1-5 (See previous documentation)
[Various attempts to handle toolchain validation and PATH scoping]

### Final Solution (Commit 20df3bf)
**Use `make buildroot` instead of `./build.sh rootfs` to properly build toolchain and libraries**

The key insight: `./build.sh rootfs` expects buildroot to already be compiled, while `make buildroot` does the actual compilation.

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

### PATH Management and Build Order

**Step 1: Prepare buildroot source tree**
```yaml
- name: Prepare buildroot source tree
  run: |
    cd luckfox-pico
    export PATH="/tmp/stub-toolchain:$PATH"
    make buildroot_create -C sysdrv
```

**Step 2: Build system (CRITICAL - Use make buildroot)**
```yaml
- name: Build system
  run: |
    cd luckfox-pico
    
    # Stub in PATH for SDK validation
    export PATH="/tmp/stub-toolchain:$PATH"
    
    # Build buildroot - creates toolchain AND runtime libraries
    make buildroot -C sysdrv
    
    # Remove stub from PATH - no longer needed
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/tmp/stub-toolchain" | tr '\n' ':' | sed 's/:$//')
    
    # Build components using buildroot's internal toolchain
    ./build.sh uboot
    ./build.sh kernel
    ./build.sh rootfs
    ./build.sh media
    ./build.sh app
```

## Benefits
- ✅ Passes SDK's Makefile.param toolchain check
- ✅ Passes SDK's build.sh toolchain check
- ✅ Supports both old and new SDK toolchain names
- ✅ Properly builds buildroot's internal GCC 13 toolchain
- ✅ Creates runtime libraries at /tmp/runtime_lib
- ✅ Stub removed before component builds (prevents accidental use)
- ✅ All compilation uses buildroot's internal GCC 13 toolchain

## Verification
Expected workflow:
1. "Create stub toolchain" - Creates stub scripts
2. "Prepare buildroot source tree" - Stub in PATH passes Makefile.param check
3. "Build system":
   - Stub in PATH for validation
   - `make buildroot -C sysdrv` - Compiles buildroot, creates toolchain and runtime libs
   - Remove stub from PATH
   - `./build.sh uboot` - Uses buildroot's internal toolchain
   - `./build.sh kernel` - Uses buildroot's internal toolchain
   - `./build.sh rootfs` - Uses buildroot's internal toolchain (libraries now exist)
   - `./build.sh media` - Uses buildroot's internal toolchain
   - `./build.sh app` - Uses buildroot's internal toolchain
4. Build completes successfully

## Technical Notes

### Why `make buildroot` Instead of `./build.sh rootfs`?

The SDK has two different commands:
- **`make buildroot`**: Compiles buildroot from source, creates toolchain and runtime libraries
- **`./build.sh rootfs`**: Uses already-compiled buildroot to create the root filesystem

The error "No runtime libraries found at /tmp/runtime_lib" occurs because `./build.sh rootfs` expects buildroot to already be compiled. We must use `make buildroot` first.

### Runtime Libraries Location
Buildroot creates runtime libraries at `/tmp/runtime_lib` during compilation. These are required by subsequent build steps. The libraries include:
- glibc runtime libraries
- Other system libraries needed for the root filesystem

### PATH Manipulation
The command to remove the stub from PATH:
```bash
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "/tmp/stub-toolchain" | tr '\n' ':' | sed 's/:$//')
```

### Why the Stub Errors on Compilation?
The stub is designed to error immediately if called for compilation. This ensures we catch any issues where it's accidentally being used instead of buildroot's toolchain.

## Related Files
- `.github/workflows/build.yml` - Stub creation, scoped PATH, build order
- Affected SDK files:
  - `luckfox-pico/sysdrv/Makefile.param` (line 42)
  - `luckfox-pico/sysdrv/Makefile` (buildroot and rootfs targets)
  - `luckfox-pico/build.sh` (toolchain check)

## Commit History
1. **351a53c**: Removed external toolchain setup
2. **d5c8240**: Added stub for `arm-rockchip830-linux-uclibcgnueabihf-gcc`
3. **bb4c0e7**: Added stub for `arm-buildroot-linux-gnueabihf-gcc`
4. **4dc4464**: Limited stub PATH scope to buildroot_create
5. **a13d7d7**: Added stub to PATH in "Build system" step
6. **67ce84d**: Changed build order - rootfs first attempt
7. **20df3bf**: Use `make buildroot` instead of `./build.sh rootfs` - FINAL FIX
