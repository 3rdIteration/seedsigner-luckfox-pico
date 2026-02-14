# GitHub Actions Workflow Architecture

## Workflow Trigger Options

### 1. Push/Pull Request (Automatic)
```
Push/PR Event
     ↓
Setup Job: Generate Matrix
  hardware_model: both
  boot_medium: both
     ↓
Creates 4 build jobs:
  [mini, microsd]
  [mini, nand]
  [max, microsd]
  [max, nand]
     ↓
All 4 jobs run in PARALLEL
     ↓
Artifacts uploaded separately
```

### 2. Manual Workflow Dispatch
```
User selects:
  - hardware_model: mini/max/both
  - boot_medium: microsd/nand/both
  - force_rebuild: true/false
     ↓
Setup Job: Generate Matrix
  (based on user selections)
     ↓
Creates N build jobs (1-4)
     ↓
Jobs run in PARALLEL
     ↓
Artifacts uploaded separately
```

## Example Scenarios

### Scenario 1: Build Only Mini MicroSD
```
Inputs:
  hardware_model: mini
  boot_medium: microsd

Matrix Generated:
  [{model: "mini", medium: "microsd"}]

Jobs: 1
  - Build mini (microsd)

Time: ~30-90 minutes
Artifacts: seedsigner-os-mini-microsd-{run_number}
```

### Scenario 2: Build Both Models for NAND
```
Inputs:
  hardware_model: both
  boot_medium: nand

Matrix Generated:
  [{model: "mini", medium: "nand"},
   {model: "max", medium: "nand"}]

Jobs: 2 (parallel)
  - Build mini (nand)
  - Build max (nand)

Time: ~30-90 minutes (parallel)
Artifacts: 
  - seedsigner-os-mini-nand-{run_number}
  - seedsigner-os-max-nand-{run_number}
```

### Scenario 3: Build Everything (Default)
```
Inputs:
  hardware_model: both
  boot_medium: both

Matrix Generated:
  [{model: "mini", medium: "microsd"},
   {model: "mini", medium: "nand"},
   {model: "max", medium: "microsd"},
   {model: "max", medium: "nand"}]

Jobs: 4 (parallel)
  - Build mini (microsd)
  - Build mini (nand)
  - Build max (microsd)
  - Build max (nand)

Time: ~1-2 hours (parallel, was 3+ hours sequential)
Artifacts: 
  - seedsigner-os-mini-microsd-{run_number}
  - seedsigner-os-mini-nand-{run_number}
  - seedsigner-os-max-microsd-{run_number}
  - seedsigner-os-max-nand-{run_number}
```

## Performance Comparison

### Old Workflow (Sequential)
```
Build mini-microsd → Build mini-nand → Build max-microsd → Build max-nand
|----60 min-----|   |----60 min----|   |----60 min-----|   |----60 min----|
Total: ~240 minutes (4 hours)
```

### New Workflow (Parallel)
```
Build mini-microsd ---|
Build mini-nand ------|--→ All complete
Build max-microsd -----|
Build max-nand -------|
|----60-90 min max----|

Total: ~60-120 minutes (1-2 hours)
Speedup: 2-4x faster!
```
