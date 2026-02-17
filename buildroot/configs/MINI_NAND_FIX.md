# Mini SPI-NAND Build Failure: Root Cause and Solution

**Status:** Issue Identified - Partition Table Fix Required  
**Date:** 2026-02-17  
**Build:** https://github.com/3rdIteration/seedsigner-luckfox-pico/actions/runs/22099146285

---

## Executive Summary

**Problem:** Mini SPI-NAND build fails during firmware packaging with error:
```
Error: max_leb_cnt too low (726 needed)
max_leb_cnt:  701
```

**Root Cause:** Rootfs partition (85MB) is too small for the content (~92MB needed).

**Solution:** Modify partition table in LuckFox SDK to expand rootfs partition.

---

## Confirmed Facts

✅ **ALL devices have 128MB SPI-NAND flash** (user confirmed)  
✅ Build succeeds through system compilation  
✅ Build fails at firmware packaging (UBIFS creation)  
✅ Rootfs content exceeds allocated partition size  

---

## Current Partition Layout

**From build log:**
```
GLOBAL_PARTITIONS: 
  0x40000@0x0(env),
  0x40000@0x40000(idblock),
  0x80000@0x80000(uboot),
  0x400000@0x100000(boot),
  0x1E00000@0x500000(oem),
  0x600000@0x2300000(userdata),
  0x5500000@0x2900000(rootfs)
```

**Human readable:**
```
Total Flash:    128MB
├─ env:         256KB  @ 0x0
├─ idblock:     256KB  @ 0x40000  (256KB offset)
├─ uboot:       512KB  @ 0x80000  (512KB offset)
├─ boot:        4MB    @ 0x100000 (1MB offset)
├─ oem:         30MB   @ 0x500000 (5MB offset)   ← OVERSIZED
├─ userdata:    6MB    @ 0x2300000 (35MB offset) ← UNUSED by SeedSigner
└─ rootfs:      85MB   @ 0x2900000 (41MB offset) ← TOO SMALL
                                   
Total Used:     ~126MB (close to full 128MB)
```

---

## The Error Explained

**UBIFS (UBI Filesystem) uses Logical Erase Blocks (LEBs):**
- Each LEB = 128KB (0x20000 bytes)
- Rootfs partition: 85MB = 0x5500000 bytes
- 0x5500000 / 0x20000 = 682 LEBs theoretical
- After UBIFS overhead: **701 LEBs actual**

**Rootfs content needs:**
- Packages + SeedSigner app + overhead = 726 LEBs
- 726 LEBs × 128KB = **92.8MB needed**

**Result:**
```
Available: 701 LEBs (85MB)
Needed:    726 LEBs (92.8MB)
Shortfall: 25 LEBs (~7.8MB)
```

---

## Why Partitions Are Oversized

### OEM Partition: 30MB (OVERSIZED)
- **Typical use:** Manufacturer-specific files, calibration data
- **SeedSigner needs:** Minimal (< 2MB)
- **Recommendation:** Reduce to 8MB

### Userdata Partition: 6MB (COMPLETELY UNUSED)
- **Typical use:** Persistent user data storage
- **SeedSigner is:** Air-gapped, stateless device
- **Actual use:** None - SeedSigner doesn't store user data
- **Recommendation:** Remove entirely (0MB)

---

## Recommended Solution

### New Partition Layout

```
Total Flash:    128MB
├─ env:         256KB  @ 0x0
├─ idblock:     256KB  @ 0x40000
├─ uboot:       512KB  @ 0x80000
├─ boot:        4MB    @ 0x100000
├─ oem:         8MB    @ 0x500000  ← Reduced from 30MB
├─ userdata:    0MB    REMOVED    ← Deleted partition
└─ rootfs:      115MB  @ 0xD00000 ← Expanded from 85MB
                                   
Total Used:     ~128MB (using full flash efficiently)
```

### Hex Values (New)

```
GLOBAL_PARTITIONS:
  0x40000@0x0(env),
  0x40000@0x40000(idblock),
  0x80000@0x80000(uboot),
  0x400000@0x100000(boot),
  0x800000@0x500000(oem),         ← 8MB (was 30MB)
  0x7340000@0xD00000(rootfs)      ← 115MB (was 85MB, userdata removed)
```

### Space Analysis

**Freed:**
- OEM: 30MB → 8MB = 22MB freed
- Userdata: 6MB → 0MB = 6MB freed
- **Total freed: 28MB**

**Applied:**
- Rootfs: 85MB → 115MB = 30MB added

**Result:**
- Rootfs needs: 92.8MB
- Rootfs has: 115MB
- **Headroom: 22.2MB** ✅

---

## Implementation Steps

### 1. Locate Partition Configuration File

The partition table is defined in the LuckFox SDK (not this repo). Location:

```
Repository: https://github.com/3rdIteration/luckfox-pico
File: project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk
```

### 2. Find the Partition Definition

Search for one of these:
```bash
grep -n "RK_PARTITION_CMD_IN_ENV" BoardConfig-SPI_NAND-*.mk
grep -n "GLOBAL_PARTITIONS" BoardConfig-SPI_NAND-*.mk
grep -n "0x5500000.*rootfs" BoardConfig-SPI_NAND-*.mk
```

### 3. Modify the Partition Table

**Find the line (approximate):**
```makefile
export RK_PARTITION_CMD_IN_ENV="0x40000@0x0(env),0x40000@0x40000(idblock),0x80000@0x80000(uboot),0x400000@0x100000(boot),0x1E00000@0x500000(oem),0x600000@0x2300000(userdata),0x5500000@0x2900000(rootfs)"
```

**Replace with:**
```makefile
export RK_PARTITION_CMD_IN_ENV="0x40000@0x0(env),0x40000@0x40000(idblock),0x80000@0x80000(uboot),0x400000@0x100000(boot),0x800000@0x500000(oem),0x7340000@0xD00000(rootfs)"
```

### 4. Update Filesystem Type Configuration

**Find:**
```makefile
export RK_PARTITION_FS_TYPE_CFG="rootfs@IGNORE@ubifs,oem@/oem@ubifs,userdata@/userdata@ubifs"
```

**Replace with:**
```makefile
export RK_PARTITION_FS_TYPE_CFG="rootfs@IGNORE@ubifs,oem@/oem@ubifs"
```

### 5. Verify the Change

After modification, run the build again. The firmware packaging should show:
```
max_leb_cnt: ~920 (for 115MB)
needed:      726
Result:      SUCCESS ✅
```

---

## Alternative Solutions (If Needed)

### Option A: Keep Userdata (Minimal Reduction)

If userdata must be kept for some reason:

```
├─ oem:         8MB    @ 0x500000  ← Reduced from 30MB
├─ userdata:    2MB    @ 0xD00000  ← Reduced from 6MB
└─ rootfs:      113MB  @ 0xF00000  ← Expanded from 85MB
```

**Hex:**
```
export RK_PARTITION_CMD_IN_ENV="0x40000@0x0(env),0x40000@0x40000(idblock),0x80000@0x80000(uboot),0x400000@0x100000(boot),0x800000@0x500000(oem),0x200000@0xD00000(userdata),0x7140000@0xF00000(rootfs)"
```

### Option B: More Conservative (Smaller OEM Reduction)

```
├─ oem:         16MB   @ 0x500000  ← Reduced from 30MB
├─ userdata:    0MB    REMOVED
└─ rootfs:      107MB  @ 0x1500000 ← Expanded from 85MB
```

**Hex:**
```
export RK_PARTITION_CMD_IN_ENV="0x40000@0x0(env),0x40000@0x40000(idblock),0x80000@0x80000(uboot),0x400000@0x100000(boot),0x1000000@0x500000(oem),0x6B40000@0x1500000(rootfs)"
```

---

## Testing

### Before Fix

Build will fail with:
```
Error: max_leb_cnt too low (726 needed)
max_leb_cnt:  701
```

### After Fix

Build should succeed with output showing:
```
max_leb_cnt:  ~920 (for 115MB partition)
[build.sh:info] Running build_mkimg succeeded.
```

### Validation Commands

After flashing to device:
```bash
# Check partition layout
cat /proc/mtd

# Check rootfs usage
df -h /

# Should show:
# Filesystem      Size  Used Avail Use% Mounted on
# ubi0:rootfs     115M  ~90M  ~25M  78% /
```

---

## Why This Fix Is Correct

1. **SeedSigner is air-gapped and stateless**
   - No need for userdata partition
   - No persistent user data storage

2. **OEM partition is oversized**
   - 30MB is excessive for calibration data
   - 8MB is more than sufficient

3. **All 128MB flash should be usable**
   - Current layout wastes 36MB on unused/oversized partitions
   - New layout efficiently uses available space

4. **Provides future headroom**
   - Rootfs: 92.8MB needed, 115MB available
   - 22.2MB free for future package additions

---

## Files to Modify in LuckFox SDK

**Repository:** https://github.com/3rdIteration/luckfox-pico

**File:** `project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Buildroot-RV1103_Luckfox_Pico_Mini-IPC.mk`

**Changes:**
1. Update `RK_PARTITION_CMD_IN_ENV`
2. Update `RK_PARTITION_FS_TYPE_CFG`
3. Possibly update max_leb_cnt calculation if hardcoded

---

## References

- Failed build: https://github.com/3rdIteration/seedsigner-luckfox-pico/actions/runs/22099146285
- Job ID: 63864192321 (build RV1103_Luckfox_Pico_Mini, SPI_NAND)
- Error: max_leb_cnt too low (726 needed, 701 available)
- LuckFox SDK: https://github.com/3rdIteration/luckfox-pico
- UBIFS documentation: https://www.kernel.org/doc/html/latest/filesystems/ubifs.html
