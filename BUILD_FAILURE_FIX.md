# GitHub Actions Build Failure Fix

## Problem
GitHub Actions builds were failing at different stages with toolchain-related errors.

### Error 1: Missing External Toolchain (Initial)
```
/bin/bash: line 1: arm-rockchip830-linux-uclibcgnueabihf-gcc: command not found
************************************************************************
Not found tool arm-rockchip830-linux-uclibcgnueabihf-gcc, please install first !!!
************************************************************************
```

### Error 2: Wrong Toolchain Name (After First Fix)
```
/bin/bash: line 1: arm-buildroot-linux-gnueabihf-gcc: command not found
************************************************************************
Not found tool arm-buildroot-linux-gnueabihf-gcc, please install first !!!
************************************************************************
```

### Error 3: Stub Used for Compilation (After Second Fix)
```
Warning: Stub toolchain called for compilation - buildroot should use internal toolchain
make[2]: *** [scripts/Makefile.autoconf:79: u-boot.cfg] Error 1
```

## Root Cause

The SDK's build system has multiple toolchain-related checks and phases:

1. **Makefile.param check**: The SDK's `sysdrv/Makefile.param` checks for external toolchain existence before allowing buildroot to proceed
2. **Different toolchain names**: The new SDK branch uses `arm-buildroot-linux-gnueabihf-gcc` instead of `arm-rockchip830-linux-uclibcgnueabihf-gcc`
3. **Actual compilation**: After passing the Makefile check, the build needs to use buildroot's internal toolchain (GCC 13) for actual compilation

The challenge was that:
- We needed to pass the Makefile check without the external toolchain
- The stub had to exist but not interfere with actual compilation
- PATH management across GitHub Actions steps was causing the stub to persist

## Solution Evolution

### First Attempt (Commit d5c8240)
Created stub for `arm-rockchip830-linux-uclibcgnueabihf-gcc`
- ✅ Passed Makefile check
- ❌ Wrong toolchain name for new SDK

### Second Attempt (Commit bb4c0e7)
Added stub for `arm-buildroot-linux-gnueabihf-gcc`
- ✅ Passed Makefile check with correct name
- ❌ Stub persisted in PATH and was used for compilation

### Final Solution (Commit 4dc4464)
**Limited stub PATH scope to only the buildroot_create step**

Key changes:
- Removed `echo "/tmp/stub-toolchain" >> $GITHUB_PATH` (global persistence)
- Added `export PATH="/tmp/stub-toolchain:$PATH"` only within the "Prepare buildroot source tree" step
- This ensures the stub is only in PATH during the Makefile.param check
- Subsequent build steps use buildroot's internal toolchain

## Implementation

### Stub Creation
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
```yaml
- name: Prepare buildroot source tree
  run: |
    cd luckfox-pico
    # Add stub to PATH only for this step (Makefile check)
    export PATH="/tmp/stub-toolchain:$PATH"
    make buildroot_create -C sysdrv
```

The `export` only affects this step, not subsequent steps.

## Benefits
- ✅ Passes SDK's Makefile.param toolchain existence check
- ✅ Supports both old and new SDK toolchain names
- ✅ Stub only available during Makefile check, not during compilation
- ✅ Buildroot's internal GCC 13 toolchain used for all actual compilation
- ✅ Clean separation of concerns between validation and compilation

## Verification
Expected workflow:
1. "Create stub toolchain" - Creates stub scripts
2. "Prepare buildroot source tree" - Stub in PATH passes Makefile check
3. "Install SeedSigner packages" onwards - Stub NOT in PATH, buildroot's toolchain used
4. Build completes successfully with internal GCC 13 toolchain

## Technical Notes

### Why Not Just Skip the Check?
Modifying the SDK's Makefile.param would require:
- Forking the SDK repository
- Maintaining patches
- Dealing with upstream merge conflicts

The stub approach works within the existing SDK structure without modifications.

### GitHub Actions PATH Behavior
- `$GITHUB_PATH`: Persists across all subsequent steps in a job
- `export PATH=...`: Only affects current step and its child processes
- This is why we changed from `$GITHUB_PATH` to `export PATH`

## Related Files
- `.github/workflows/build.yml` - Stub creation and scoped PATH export
- Affected SDK file: `luckfox-pico/sysdrv/Makefile.param` (line 42)

## Commit History
1. **351a53c**: Removed external toolchain setup to use SDK's internal buildroot toolchain
2. **d5c8240**: Added stub for `arm-rockchip830-linux-uclibcgnueabihf-gcc`
3. **bb4c0e7**: Added stub for `arm-buildroot-linux-gnueabihf-gcc` (new SDK name)
4. **4dc4464**: Limited stub PATH scope to prevent interference with compilation
