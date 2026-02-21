# GitHub Actions Workflow Triggers

## Current Configuration

The build workflow (`.github/workflows/build.yml`) is configured to trigger on:

```yaml
on:
  push:
    branches: [ main, develop, master ]
  pull_request:
    branches: [ main, develop, master ]
  workflow_dispatch:
```

## Trigger Behavior

### Pull Requests
- **When:** A PR is opened or updated targeting `main`, `develop`, or `master`
- **Triggers:** Only the `pull_request` event
- **Result:** Single workflow run per PR update ✅

### Direct Pushes to Protected Branches
- **When:** Code is pushed directly to `main`, `develop`, or `master`
- **Triggers:** The `push` event
- **Result:** Single workflow run per push ✅

### Pushes to Feature Branches
- **When:** Code is pushed to any other branch (e.g., `feature/xyz`)
- **Triggers:** Nothing (unless there's an open PR)
- **Result:** No workflow run (saves CI resources)

### Manual Trigger
- **When:** Manually dispatched from GitHub Actions UI
- **Triggers:** The `workflow_dispatch` event
- **Result:** On-demand workflow run with custom parameters ✅

## Why This Configuration?

### Avoids Duplicate Runs
Previously, the `push` trigger had no branch filter, causing:
- **Push to PR branch** → Triggered `push` event
- **PR update** → Triggered `pull_request` event
- **Result:** 2 identical runs (wasteful!)

Now, with branch filters:
- **Push to PR branch** → No trigger (not a protected branch)
- **PR update** → Triggered `pull_request` event
- **Result:** 1 run (efficient!)

### Protects Important Branches
Direct pushes to `main`, `develop`, and `master` still trigger CI, ensuring:
- Code quality checks on protected branches
- Automatic builds when changes are merged
- Fast feedback on direct commits

### Saves CI Resources
By only running on:
- Pull requests to protected branches
- Direct pushes to protected branches
- Manual triggers

We avoid unnecessary workflow runs on:
- Feature branch development (unless there's a PR)
- Experimental branches
- Personal forks

## Testing the Configuration

### Expected Behavior

| Action | Branch | Expected Trigger | Workflow Runs |
|--------|--------|------------------|---------------|
| Create PR | `feature/xyz` → `main` | `pull_request` | 1 |
| Update PR | `feature/xyz` → `main` | `pull_request` | 1 |
| Push to main | Direct push to `main` | `push` | 1 |
| Push to feature | Direct push to `feature/xyz` (no PR) | None | 0 |
| Manual dispatch | Any branch | `workflow_dispatch` | 1 |

### How to Verify

1. **Create a test PR** from a feature branch
   - Check GitHub Actions tab
   - Should see exactly **1 workflow run**

2. **Push to the PR branch**
   - Check GitHub Actions tab
   - Should see exactly **1 new workflow run**

3. **Push directly to main** (if you have permissions)
   - Check GitHub Actions tab
   - Should see exactly **1 workflow run**

## Further Optimization

If you want to optimize further, consider:

### Option 1: PR-Only Builds
```yaml
on:
  pull_request:
    branches: [ main, develop, master ]
  workflow_dispatch:
```
- Only runs on PRs and manual triggers
- No automatic builds on direct pushes to main
- Good if all changes go through PRs

### Option 2: Main-Only Pushes
```yaml
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
```
- Only targets the main branch
- Good for simpler branching strategies

### Option 3: Path Filters
```yaml
on:
  push:
    branches: [ main, develop, master ]
    paths:
      - 'buildroot/**'
      - '.github/workflows/**'
  pull_request:
    branches: [ main, develop, master ]
```
- Only runs when specific files change
- Good for monorepos or documentation-heavy projects

## Current Choice: Balanced Approach

The current configuration balances:
- ✅ No duplicate runs on PRs
- ✅ CI protection for main branches
- ✅ Manual trigger flexibility
- ✅ Resource efficiency

This is the recommended configuration for most projects.
