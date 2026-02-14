# How to Use the Parallel Build Workflow

## Method 1: Automatic Builds (Push/Pull Request)

When you push code or create a pull request, the workflow automatically:
1. Detects the event type (push/PR)
2. Sets up a build matrix for all combinations (mini+max, microsd+nand)
3. Runs 4 parallel build jobs
4. Uploads 4 separate artifacts

**No user action required** - just push your code!

## Method 2: Manual Builds (Workflow Dispatch)

To manually trigger a build with custom options:

### Step 1: Navigate to Actions Tab
1. Go to your GitHub repository
2. Click on the "Actions" tab at the top
3. Select "Build SeedSigner OS" workflow from the left sidebar

### Step 2: Run Workflow
1. Click the "Run workflow" button (top right)
2. Select the branch you want to build from

### Step 3: Choose Build Options

**Hardware Model:**
- `mini` - Build only for LuckFox Pico Mini
- `max` - Build only for LuckFox Pico Max
- `both` - Build for both models (default)

**Boot Medium:**
- `microsd` - Build MicroSD card images only
- `nand` - Build NAND flash images only  
- `both` - Build for both media types (default)

**Force Rebuild:**
- `false` - Use cached Docker image (faster)
- `true` - Force rebuild Docker image (slower, use for debugging)

### Step 4: Click "Run workflow"

The setup job will generate the build matrix, and the appropriate number of build jobs will run in parallel.

## Downloading Artifacts

After the build completes:

1. Go to the workflow run page
2. Scroll down to the "Artifacts" section
3. Download the artifact(s) you need:
   - `seedsigner-os-mini-microsd-{run_number}`
   - `seedsigner-os-mini-nand-{run_number}`
   - `seedsigner-os-max-microsd-{run_number}`
   - `seedsigner-os-max-nand-{run_number}`

Each artifact is a ZIP file containing the build outputs for that specific configuration.

## Build Matrix Examples

### Example 1: Quick Test Build
**Configuration:**
- Hardware: `mini`
- Medium: `microsd`

**Result:**
- Jobs: 1
- Time: ~60-90 minutes
- Artifacts: 1 (mini-microsd)

**Use case:** Testing changes quickly on a single configuration

### Example 2: NAND Flash Only
**Configuration:**
- Hardware: `both`
- Medium: `nand`

**Result:**
- Jobs: 2 (parallel)
- Time: ~60-90 minutes
- Artifacts: 2 (mini-nand, max-nand)

**Use case:** Building NAND flash images for both hardware models

### Example 3: Complete Release Build
**Configuration:**
- Hardware: `both`
- Medium: `both`

**Result:**
- Jobs: 4 (parallel)
- Time: ~1-2 hours
- Artifacts: 4 (all combinations)

**Use case:** Creating a complete release with all variants

## Monitoring Build Progress

Each parallel job shows up as a separate item in the workflow run:
- ✅ Build mini (microsd) - Success
- ✅ Build mini (nand) - Success
- ✅ Build max (microsd) - Success
- ✅ Build max (nand) - Success

You can:
- Click on any job to see its detailed logs
- Monitor progress of all jobs simultaneously
- Download artifacts as soon as each job completes (don't need to wait for all)

## Troubleshooting

**Q: Why is my build failing?**
A: Check the individual job logs for error messages. Common issues:
- Docker image build failures (try `force_rebuild: true`)
- Build timeout (jobs have 120 minute limit)
- Insufficient GitHub Actions runner resources

**Q: Can I cancel individual jobs?**
A: Yes! Click on the job and use the "Cancel job" button. Other parallel jobs will continue.

**Q: Why don't I see the "Run workflow" button?**
A: Make sure you have write access to the repository and are viewing the Actions tab.

**Q: How long are artifacts kept?**
A: Artifacts are retained for 30 days by default.

## Advanced: Build Matrix Logic

The setup job creates a matrix based on your selections:

```python
if hardware == "both":
    models = ["mini", "max"]
else:
    models = [hardware]

if medium == "both":
    media = ["microsd", "nand"]
else:
    media = [medium]

# Create all combinations
matrix = [
    {"model": m, "medium": med}
    for m in models
    for med in media
]
```

This generates:
- 1 job: single hardware + single medium
- 2 jobs: both hardware + single medium OR single hardware + both media
- 4 jobs: both hardware + both media
