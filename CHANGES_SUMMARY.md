# SDK Repository Update - Summary of Changes

## Problem Statement
The GitHub Actions workflow was failing with the error:
```
ERROR: Problem encountered: gcc version is too old, libcamera requires 9.0 or newer
```

This occurred because the workflow was using the default LuckFox SDK repository (`https://github.com/lightningspore/luckfox-pico.git`) which contains an older GCC toolchain (arm-rockchip830-linux-uclibcgnueabihf).

## Solution
Updated all references to use the SDK repository with GCC 13 support:
- **Repository**: `https://github.com/3rdIteration/luckfox-pico.git`
- **Branch**: `copilot/enable-glibc-highest-version`

This SDK includes an internal buildroot toolchain with GCC 13, which satisfies the libcamera requirement for GCC 9.0 or newer.

## Files Modified

### 1. `.github/workflows/build.yml`
- Updated `luckfox_repo_url` default from `lightningspore/luckfox-pico` to `3rdIteration/luckfox-pico`
- Updated `luckfox_branch` default from empty string to `copilot/enable-glibc-highest-version`
- Updated fallback values in the clone step to match the new defaults

### 2. `buildroot/os-build.sh`
- Updated `LUCKFOX_REPO_URL` environment variable
- Added `LUCKFOX_BRANCH` environment variable
- Updated git clone command to use the branch

### 3. `buildroot/build-local.sh`
- Updated git clone command to use new repository and branch

### 4. `buildroot/docs/build.complex.sh`
- Updated repository list entry
- Updated git clone command

### 5. `buildroot/docs/validate_environment.sh`
- Updated help message with new clone command

### 6. `docs/OS-build-instructions.md`
- Updated manual build instructions (2 locations)
- Added note about GCC 13 support

### 7. `README.md`
- Updated SDK fork reference with link to specific branch
- Added mention of GCC 13 support

## Impact
These changes ensure that:
1. All GitHub Actions builds (automatic and manual) use the correct SDK with GCC 13
2. Local builds using `build-local.sh` use the correct SDK
3. Manual builds following the documentation use the correct SDK
4. Docker-based builds use the correct SDK
5. All documentation is consistent

## Verification
The branch `copilot/enable-glibc-highest-version` has been verified to exist in the `3rdIteration/luckfox-pico` repository:
```
git ls-remote --heads https://github.com/3rdIteration/luckfox-pico.git copilot/enable-glibc-highest-version
b53951a30cf7c018868697416b38c557547aa8e6	refs/heads/copilot/enable-glibc-highest-version
```

## Testing Recommendations
1. Trigger a GitHub Actions workflow run to verify the build completes successfully
2. Test local builds with `build-local.sh` to ensure compatibility
3. Verify that libcamera builds successfully with the new toolchain

## Related Issue
This fixes the build failure from workflow run: https://github.com/3rdIteration/seedsigner-luckfox-pico/actions/runs/22026142760
