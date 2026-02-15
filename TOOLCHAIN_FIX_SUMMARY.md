# Toolchain Fix Summary

## Problem
GitHub Actions builds were using the old external `arm-rockchip830-linux-uclibcgnueabihf` toolchain instead of the SDK's internal buildroot toolchain with GCC 13 support. This caused build failures with the error:

```
ERROR: Problem encountered: gcc version is too old, libcamera requires 9.0 or newer
```

## Root Cause
The GitHub Actions workflow had a "Set up build environment" step that explicitly:
1. Changed directory to `tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf`
2. Sourced `env_install_toolchain.sh` to set up the old external toolchain
3. Exported the toolchain's PATH to GITHUB_ENV, making it persist across workflow steps
4. This prevented the SDK's internal buildroot toolchain from being used

## Solution
**Removed the entire "Set up build environment" step** from `.github/workflows/build.yml`

This allows the SDK's `build.sh` script to automatically use its internal buildroot toolchain, which:
- Includes GCC 13 (satisfies libcamera's requirement for GCC 9.0+)
- Is built as part of the buildroot process
- Matches the toolchain used when building directly from the SDK

## Changes Made

### File: `.github/workflows/build.yml`
**Removed lines 160-182**: The "Set up build environment" step that set up the old external toolchain

### Before:
```yaml
- name: Set up build environment
  run: |
    cd luckfox-pico
    
    # Source the toolchain environment and export to GITHUB_ENV
    cd tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf
    
    # Source the environment script
    source env_install_toolchain.sh
    
    # Export PATH to GITHUB_ENV so it persists to next steps
    echo "PATH=$PATH" >> $GITHUB_ENV
    
    # Also export the CROSS_COMPILE variable if it exists
    if [ -n "$CROSS_COMPILE" ]; then
      echo "CROSS_COMPILE=$CROSS_COMPILE" >> $GITHUB_ENV
    fi
    
    cd ../../../..
    
    # Verify toolchain is accessible
    which arm-rockchip830-linux-uclibcgnueabihf-gcc || echo "WARNING: Toolchain not in PATH yet, but will be in next step"
```

### After:
The step is completely removed. The workflow now flows from "Clone required repositories" directly to "Configure board", allowing the SDK's build system to use its internal toolchain.

## Verification
When the workflow runs now:
1. The SDK is cloned from `https://github.com/3rdIteration/luckfox-pico.git` (branch `copilot/enable-glibc-highest-version`)
2. No external toolchain is set up
3. When `./build.sh` runs, it automatically uses the internal buildroot toolchain
4. The buildroot build process compiles the toolchain with GCC 13
5. libcamera and other packages build successfully with the modern toolchain

## Impact
- ✅ Builds now use the same toolchain as direct SDK builds
- ✅ GCC 13 satisfies libcamera's minimum requirement
- ✅ Consistent behavior across CI and local development
- ✅ No need to maintain separate external toolchain setup

## Testing
The fix will be verified by GitHub Actions when it runs the build workflow. Expected outcome:
- All 4 build matrix combinations should succeed:
  - RV1103_Luckfox_Pico_Mini + SD_CARD
  - RV1103_Luckfox_Pico_Mini + SPI_NAND
  - RV1106_Luckfox_Pico_Pro_Max + SD_CARD
  - RV1106_Luckfox_Pico_Pro_Max + SPI_NAND

## Related Issues
- Original SDK change: https://github.com/3rdIteration/luckfox-pico/tree/copilot/enable-glibc-highest-version
- Previous build failure: https://github.com/3rdIteration/seedsigner-luckfox-pico/actions/runs/22026786378
