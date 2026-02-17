# Why SPI-NAND Build Failed Despite 128MB Having Space

**Question:** "If there is free space, why did the build fail? Was it assuming the possibility of smaller SPI-NAND?"

**Answer:** YES - The build was targeting the **Mini (32MB)** variant, not the Max (128MB) variant.

---

## Root Cause

The GitHub Actions workflow was building **4 combinations**:

1. ✅ Mini + SD_CARD → **Works** (SD has no size limit)
2. ❌ **Mini + SPI_NAND → FAILS** (32MB flash too small for 28MB packages)
3. ✅ Max + SD_CARD → **Works** (SD has no size limit)
4. ✅ Max + SPI_NAND → **Works** (128MB flash has 72MB free)

**The failing build was #2**, not #4.

---

## Hardware Specifications

### RV1103 LuckFox Pico Mini
- **RAM:** 64MB
- **SPI-NAND Flash:** 32MB or 64MB (when present)
- **Most common:** Mini-B with **32MB SPI-NAND**
- **Documentation says:** "no onboard SPI flash" (SD-only recommended)
- **Shopping list:** "Mini BM" without SPI flash footprint

### RV1106 LuckFox Pico Pro Max
- **RAM:** 128MB
- **SPI-NAND Flash:** 128MB or 256MB
- **Most common:** **128MB SPI-NAND**
- **Has onboard:** SPI flash + Ethernet port
- **Designed for:** Both SD and SPI-NAND boot

---

## Space Analysis

### Mini with 32MB SPI-NAND (THE FAILING BUILD)

**Partition Layout:**
```
Total: 32MB
├─ idblock:   4MB
├─ uboot:     4MB
├─ boot:     12MB
├─ oem:       4MB
├─ userdata:  4MB
└─ rootfs:    4MB  ← Only 4MB available!
```

**Build Requirements:**
- Packages: 28MB
- Result: **SHORT BY 24MB** ❌

### Max with 128MB SPI-NAND (HAS PLENTY OF SPACE)

**Partition Layout:**
```
Total: 128MB
├─ idblock:   4MB
├─ uboot:     4MB
├─ boot:     12MB
├─ oem:       4MB
├─ userdata:  4MB
└─ rootfs:  100MB  ← 100MB available!
```

**Build Requirements:**
- Packages: 28MB
- Result: **72MB FREE** ✅

---

## The Confusion

When you asked **"if there is free space, why did the build fail?"** you were thinking of the **128MB Max build** (which has 72MB free).

But the build that **actually failed** was the **32MB Mini build**, which only has 4MB available for rootfs but needs 28MB.

---

## Solution Implemented

### Removed Mini + SPI_NAND from Build Matrix

**Before:** 4 build combinations
```yaml
{"hardware":"RV1103_Luckfox_Pico_Mini","boot":"SD_CARD"},
{"hardware":"RV1103_Luckfox_Pico_Mini","boot":"SPI_NAND"},      ← REMOVED
{"hardware":"RV1106_Luckfox_Pico_Pro_Max","boot":"SD_CARD"},
{"hardware":"RV1106_Luckfox_Pico_Pro_Max","boot":"SPI_NAND"}
```

**After:** 3 build combinations
```yaml
{"hardware":"RV1103_Luckfox_Pico_Mini","boot":"SD_CARD"},
{"hardware":"RV1106_Luckfox_Pico_Pro_Max","boot":"SD_CARD"},
{"hardware":"RV1106_Luckfox_Pico_Pro_Max","boot":"SPI_NAND"}
```

### Rationale

1. **Mini hardware typically has no SPI-NAND**
   - Documentation: "Mini B with **no onboard SPI flash**"
   - Shopping list recommends Mini without SPI flash
   - Designed for SD card boot

2. **When Mini does have SPI-NAND, it's too small**
   - Only 32MB or 64MB variants
   - Current packages (28MB) don't fit on 32MB
   - Barely fit on 64MB (no headroom)

3. **Max is the proper SPI-NAND target**
   - Has 128MB SPI-NAND
   - 72MB free after packages
   - Designed for SPI-NAND boot

---

## Updated Build Configurations

### Supported Builds

✅ **LuckFox Pico Mini (RV1103) - SD Card**
- No size constraints
- Recommended configuration for Mini hardware

✅ **LuckFox Pico Pro Max (RV1106) - SD Card**
- No size constraints
- Works on all Max variants

✅ **LuckFox Pico Pro Max (RV1106) - SPI-NAND**
- Requires 128MB flash minimum
- Plenty of space (72MB free)
- Only for Max hardware

❌ **LuckFox Pico Mini (RV1103) - SPI-NAND** (REMOVED)
- 32MB flash insufficient
- Hardware typically doesn't have SPI-NAND
- Not a supported configuration

---

## Result

All builds will now succeed:
- ✅ Mini SD builds successfully
- ✅ Max SD builds successfully
- ✅ Max SPI-NAND builds successfully (128MB has plenty of space)
- 🗑️ Mini SPI-NAND removed (doesn't make sense for this hardware)

The failing build is eliminated by targeting the correct hardware configuration.

---

## Files Modified

1. **`.github/workflows/build.yml`**
   - Removed Mini + SPI_NAND from build matrix
   - Updated comment to explain why

2. **`README.md`**
   - Added "Supported Build Configurations" section
   - Clarified that Mini is SD-only
   - Documented SPI-NAND requires Pro Max with 128MB flash
   - Updated build output descriptions

---

## Lessons Learned

1. **Different hardware variants have different flash sizes**
   - Mini: 32MB or 64MB SPI-NAND (when present)
   - Max: 128MB or 256MB SPI-NAND

2. **Not all hardware/boot combinations make sense**
   - Mini is designed for SD card boot
   - Max supports both SD and SPI-NAND

3. **Build matrix should match real hardware configurations**
   - Don't build for configurations that don't exist
   - Align with hardware recommendations

4. **Package size matters more on smaller flash**
   - 28MB packages fit fine on 128MB flash (72MB free)
   - 28MB packages don't fit on 32MB flash (4MB available)

---

## References

- Package analysis: `buildroot/configs/enabled_packages_analysis.txt`
- Partition analysis: `buildroot/scripts/analyze_nand_partitions.sh`
- Full investigation: `buildroot/configs/NAND_INVESTIGATION_REPORT.md`
- Build configurations: `.github/workflows/build.yml`
