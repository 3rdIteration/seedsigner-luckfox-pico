# AGENTS.md - Guidelines for AI Agents

This file contains critical guidelines, learnings, and best practices for AI agents working on the seedsigner-luckfox-pico repository.

---

## ⚠️ CRITICAL RULES - READ FIRST ⚠️

These rules must **NEVER** be violated unless explicitly instructed by the user:

### 1. NEVER Remove Buildroot Packages

**DO NOT:**
- Remove packages from `buildroot/configs/luckfox_pico_defconfig` to fix size issues
- Disable packages to make builds fit
- Suggest removing packages as a solution to build problems
- Delete package configurations from build scripts

**WHY:**
- This is a development image with intentionally included packages
- Size issues should be solved by partition layout optimization, not package removal
- Packages are carefully selected and may have dependencies
- Removing packages can break functionality

**INSTEAD:**
- Optimize partition layouts
- Analyze actual space usage
- Suggest specific packages IF user asks what could be removed
- Never make the decision to remove packages yourself

### 2. NEVER Change Upstream Repositories or Branches

**DO NOT change these repositories or branches unless explicitly instructed:**

- **seedsigner repository:** `https://github.com/3rdIteration/seedsigner`
  - Branch: `luckfox-staging-portability`
  - This is a carefully selected version with specific patches

- **seedsigner-os repository:** `https://github.com/3rdIteration/seedsigner-os`
  - Contains "known good" external package configurations
  - Reference point for all package integrations

- **luckfox-pico SDK repository:** `https://github.com/3rdIteration/luckfox-pico`
  - This fork contains necessary modifications
  - Don't switch to upstream LuckFox repository

**WHY:**
- These are specifically chosen versions with required modifications
- Changing repos can break builds completely
- Branches contain specific patches not in main branches
- User has tested these specific combinations

---

## External Package Integration - KEY LEARNING

**This was the major lesson from the python-pyscard/pysatochip integration:**

### The Problem

**LuckFox SDK ≠ Standard Buildroot**

The LuckFox Pico SDK uses a custom build system that wraps standard buildroot. This means:

1. **BR2_EXTERNAL doesn't work** like in standard buildroot
2. **Variables don't expand** in Config.in context
3. **Packages must be copied** to SDK's package directory
4. **Standard paths must be used** (no BR2_EXTERNAL_* variables)

### The Wrong Approach (DON'T DO THIS)

```bash
# ❌ WRONG - This doesn't work in LuckFox SDK
source "$BR2_EXTERNAL_SEEDSIGNER_PATH/package/python-pyscard/Config.in"
```

**Why it fails:**
- LuckFox SDK doesn't set up BR2_EXTERNAL_SEEDSIGNER_PATH
- Variables aren't expanded when buildroot reads Config.in
- Results in "can't open file" errors

### The Correct Approach (DO THIS)

**Step 1: Place package in this repository**
```
buildroot/external-packages/python-yourpackage/
├── Config.in
├── python-yourpackage.mk
├── python-yourpackage.hash
└── patches/ (if needed)
```

**Step 2: Copy to SDK during build**

In all build scripts (os-build.sh, build-local.sh, build.yml):
```bash
# Copy this repo's external packages to SDK
if [ -d "buildroot/external-packages" ]; then
    echo "📦 Copying local external packages to SDK..."
    cp -rv buildroot/external-packages/* "$PACKAGE_DIR/" || true
fi
```

**Step 3: Reference as standard buildroot package**

```makefile
# ✅ CORRECT - Standard buildroot path
source "package/python-yourpackage/Config.in"
```

**Step 4: Enable in defconfig**
```
BR2_PACKAGE_PYTHON_YOURPACKAGE=y
```

### Integration Checklist

When adding a new external package:

- [ ] Check if package exists in seedsigner-os (use their version if available)
- [ ] Place package files in `buildroot/external-packages/packagename/`
- [ ] Update all 3 build scripts to copy external packages to SDK
- [ ] Add menu entry using `source "package/packagename/Config.in"`
- [ ] Enable in `buildroot/configs/luckfox_pico_defconfig`
- [ ] Test build on all hardware variants
- [ ] Document in buildroot/external-packages/README.md or similar

---

## Build System Architecture

### LuckFox SDK Structure

```
luckfox-pico/                          # SDK repository
├── sysdrv/
│   └── source/
│       └── buildroot/
│           └── buildroot-*/           # Standard buildroot
│               └── package/           # Where packages must be
│                   ├── python-urtypes/
│                   ├── python-pyscard/    # Copied here during build
│                   └── python-pysatochip/ # Copied here during build
└── project/
    └── cfg/
        └── BoardConfig_IPC/
            ├── BoardConfig-SPI_NAND-*-Mini-*.mk
            └── BoardConfig-SPI_NAND-*-Max-*.mk
```

### Package Source Locations

**This Repository:**
```
buildroot/external-packages/
├── python-pyscard/
└── python-pysatochip/
```

**seedsigner-os Repository:**
```
opt/external-packages/
├── python-embit/
├── python-mnemonic/
├── python-urtypes/
├── python-pyzbar/
└── ... (many more)
```

**During Build:**
1. Copy from seedsigner-os → SDK package/
2. Copy from this repo → SDK package/
3. Add menu entries to SDK's package/Config.in
4. Build proceeds with standard buildroot

---

## Common Pitfalls

### ❌ Pitfall 1: Assuming BR2_EXTERNAL Works

**Mistake:**
```bash
source "$BR2_EXTERNAL_SEEDSIGNER_PATH/package/mypackage/Config.in"
```

**Why it fails:**
- LuckFox SDK doesn't use BR2_EXTERNAL system
- Variable isn't set or expanded

**Solution:**
Copy packages to SDK and use standard paths

### ❌ Pitfall 2: Not Copying Packages to SDK

**Mistake:**
Placing packages in buildroot/external-packages/ but not copying them during build.

**Why it fails:**
Buildroot can't find the package files.

**Solution:**
Add copy step in all build scripts (see External Package Integration section)

### ❌ Pitfall 3: Removing Packages to Fix Size Issues

**Mistake:**
"The build is too big, let me remove git, pip, wget to save space."

**Why it's wrong:**
- This is explicitly forbidden (see CRITICAL RULES)
- It's a development image, packages are intentional
- User wants all tools available

**Solution:**
Optimize partition layouts, don't remove packages

### ❌ Pitfall 4: Not Comparing with seedsigner-os

**Mistake:**
Creating packages from scratch without checking seedsigner-os.

**Why it's suboptimal:**
- seedsigner-os has "known good" configurations
- Packages are already tested and working
- No need to reinvent the wheel

**Solution:**
Always check seedsigner-os first, copy their package configurations

---

## Best Practices

### 1. Always Compare with seedsigner-os

When adding packages or debugging:
1. Check if package exists in seedsigner-os repository
2. Review their implementation
3. Copy their approach (adapted for LuckFox SDK)
4. Use their version numbers and patches

### 2. Test Thoroughly

Before committing package changes:
- [ ] Test SD card build (Mini and Max)
- [ ] Test SPI-NAND build (Mini and Max)
- [ ] Verify packages install to rootfs
- [ ] Check for dependency issues
- [ ] Review build logs for warnings

### 3. Document Everything

When making changes:
- Update buildroot/configs/enabled_packages_analysis.txt
- Create/update documentation in buildroot/configs/
- Add comments in build scripts explaining why
- Update AGENTS.md if new patterns emerge

### 4. Use Existing Patterns

Look at how existing packages are handled:
- python-urtypes
- python-embit
- python-pyzbar
- python-mnemonic

Follow the same pattern for consistency.

### 5. Add Comprehensive Error Handling

In build scripts:
```bash
# Check if source exists
if [ ! -d "buildroot/external-packages" ]; then
    echo "⚠️  No external packages directory"
fi

# Copy with error handling
cp -rv buildroot/external-packages/* "$PACKAGE_DIR/" || {
    echo "❌ Failed to copy external packages"
    exit 1
}

# Verify copy succeeded
if [ -d "$PACKAGE_DIR/python-pyscard" ]; then
    echo "✅ python-pyscard copied successfully"
fi
```

---

## Partition Optimization Lessons

### Key Principles

1. **Check actual device usage before assuming sizes**
   - Example: OEM partition shows 16.4MB used, don't allocate just 8MB

2. **Account for UBIFS overhead (15-20%)**
   - Raw partition size ≠ usable space
   - Formula: `Usable = Raw × 0.82` (approximate)

3. **Verify patches actually apply**
   - Don't trust "success" status without verification
   - Check actual partition sizes in build output
   - Add post-patch verification steps

4. **Add debugging output**
   - Show what's being patched
   - Display partition tables after patching
   - Warn if verification fails

5. **Test verification logic**
   - Grep for expected values
   - Show warnings if not found
   - Don't silently fail

### Example: Mini SPI-NAND Partition Optimization

**Problem:** Rootfs needed 93MB, only had 85MB

**Wrong approach:** Remove packages to fit in 85MB

**Correct approach:**
1. Analyze actual OEM usage (16.4MB)
2. Remove unused userdata partition (6MB)
3. Reduce oversized OEM from 30MB to 24MB
4. Expand rootfs to 99MB
5. Verify with device df output
6. Create patches to automate the change

---

## Quick Reference

### External Package Directory
```
buildroot/external-packages/
```

### SDK Package Directory (destination during build)
```
$SDK_DIR/sysdrv/source/buildroot/buildroot-*/package/
```

### Build Scripts
- GitHub Actions: `.github/workflows/build.yml`
- Docker build: `buildroot/os-build.sh`
- Native build: `buildroot/build-local.sh`

### Configuration
- Main defconfig: `buildroot/configs/luckfox_pico_defconfig`
- Package analysis: `buildroot/configs/enabled_packages_analysis.txt`

### Common Commands

**Check what's enabled:**
```bash
grep "BR2_PACKAGE_.*=y" buildroot/configs/luckfox_pico_defconfig
```

**Analyze package sizes:**
```bash
./buildroot/scripts/analyze_packages.sh
```

**Verify external packages:**
```bash
ls -l buildroot/external-packages/
```

---

## Additional Resources

### Detailed Documentation

All detailed documentation is in `buildroot/configs/`:

- `SMARTCARD_BUILD_FIX.md` - External package integration fix
- `SMARTCARD_PACKAGES.md` - Smartcard package details
- `PATCH_FIX_SUMMARY.md` - Partition patch debugging
- `NAND_INVESTIGATION_REPORT.md` - SPI-NAND size analysis
- `OEM_SPACE_REQUIREMENTS.md` - OEM partition sizing
- `MINI_NAND_FIX.md` - Mini SPI-NAND partition fix
- `MINI_NAND_BUILD_FAILURE_ANALYSIS.md` - Build failure investigation
- `IMPLEMENTATION_SUMMARY.md` - Patch system overview
- `enabled_packages_analysis.txt` - Current package list with sizes

### External Package Examples

Look in `buildroot/external-packages/` for examples:
- python-pyscard/ - PC/SC smartcard wrapper
- python-pysatochip/ - Satochip hardware wallet API

### Related Repositories

- **seedsigner:** https://github.com/3rdIteration/seedsigner/tree/luckfox-staging-portability
- **seedsigner-os:** https://github.com/3rdIteration/seedsigner-os
- **luckfox-pico:** https://github.com/3rdIteration/luckfox-pico

---

## Summary for AI Agents

### Before Starting Work

1. **Read this file (AGENTS.md) completely**
2. **Check the CRITICAL RULES section**
3. **Review relevant detailed documentation**
4. **Compare with seedsigner-os if adding packages**

### When Adding Packages

1. Check if it exists in seedsigner-os ✓
2. Copy to buildroot/external-packages/ ✓
3. Update all 3 build scripts to copy to SDK ✓
4. Use standard package/.../Config.in paths ✓
5. Enable in defconfig ✓
6. Test thoroughly ✓
7. Document the addition ✓

### When Debugging

1. Never remove packages as a first resort ✓
2. Never change upstream repos/branches ✓
3. Compare with seedsigner-os for patterns ✓
4. Check detailed documentation in buildroot/configs/ ✓
5. Add comprehensive debugging output ✓
6. Test verification logic ✓

### Remember

- **LuckFox SDK ≠ Standard Buildroot**
- **Copy packages, don't use BR2_EXTERNAL**
- **Standard paths only: package/.../Config.in**
- **seedsigner-os has "known good" configs**
- **Never remove packages**
- **Never change repos**
- **Test thoroughly**
- **Document everything**

---

*This file was created from learnings during extensive work on external package integration, partition optimization, and build system debugging. It represents real-world solutions to real problems encountered.*

*Last updated: 2026-02-17*
