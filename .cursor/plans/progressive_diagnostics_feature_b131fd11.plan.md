---
name: Progressive Diagnostics Feature
overview: Implement progressive diagnostics to run system checks after repeated failures for debugging assistance.
todos:
  - id: add-flag-parsing
    content: Add -diagnostics and -diagnostics-after flag parsing in case statement
    status: pending
  - id: add-validation
    content: Add validation to ensure diagnostics-after is a positive integer
    status: pending
  - id: create-diagnostics-function
    content: Create run_diagnostics() function with system/network/disk/process checks
    status: pending
  - id: integrate-retry-loop
    content: Integrate diagnostics call in retry loop after failure detection
    status: pending
  - id: handle-log-integration
    content: Ensure diagnostics output goes to log file when -log is set
    status: pending
  - id: update-usage
    content: Update usage() function to document the new flags
    status: pending
  - id: test-feature
    content: Test progressive diagnostics with various scenarios and system configurations
    status: pending
---

# Progressive Diagnostics Feature (`-diagnostics`)

## Overview

Run diagnostic commands after repeated failures to aid debugging. Provides system/network information when failures persist. Useful for debugging failing CI/CD jobs and production issues.

## Specification

**Flags**:

- `-diagnostics` (boolean) - enable diagnostics, run after 3 failures (default threshold)
- `-diagnostics-after N` (integer) - run diagnostics after N consecutive failures

**Behavior**:

- When enabled, run diagnostic commands after N consecutive failures
- Default: run after 3 failures if `-diagnostics` is set
- Customizable threshold with `-diagnostics-after`
- Diagnostics run before sleep/backoff (after failure detection)
- Output diagnostics to stderr (or log file if `-log` is set)
- Include: system info (uname), network status (ifconfig/ip), disk space (df), process info (ps)
- Diagnostics don't count as attempts or affect retry logic

## Implementation Details

### Variables

- Add `diagnostics_enabled` boolean (default false)
- Add `diagnostics_after` integer (default 3)

### Parsing

- Add flag parsing in case statement (lines 122-211):
  ```bash
  -diagnostics)
    diagnostics_enabled=true
    shift 1
    ;;
  -diagnostics-after)
    diagnostics_enabled=true
    diagnostics_after=${2:-3}
    shift 2
    ;;
  -diagnostics-after=*)
    diagnostics_enabled=true
    diagnostics_after=${1#*=}
    shift 1
    ;;
  ```


### Validation

- After parsing (around line 232), validate diagnostics_after is positive integer:
  ```bash
  if [[ $diagnostics_enabled == true ]]; then
    diagnostics_after=${diagnostics_after:-3}
    if ! [[ $diagnostics_after =~ ^[1-9][0-9]*$ ]]; then
      error "diagnostics-after must be a positive integer"
      exit 1
    fi
  fi
  ```


### Diagnostics Function

- Create `run_diagnostics()` function before `main()` function:
  ```bash
  run_diagnostics() {
    local attempt_num=$1
    local log_file=${2:-}
    
    local output_target=">&2"
    if [[ -n ${log_file:-} ]]; then
      output_target=">> \"$log_file\""
    fi
    
    eval "echo '=== Diagnostics (after $attempt_num failures) ===' $output_target"
    eval "echo '--- System Info ---' $output_target"
    eval "uname -a $output_target"
    
    eval "echo '--- Network Status ---' $output_target"
    if command -v ip >/dev/null 2>&1; then
      eval "ip addr show $output_target"
    elif command -v ifconfig >/dev/null 2>&1; then
      eval "ifconfig $output_target"
    else
      eval "echo 'No network diagnostic tool available' $output_target"
    fi
    
    eval "echo '--- Disk Space ---' $output_target"
    if command -v df >/dev/null 2>&1; then
      eval "df -h $output_target"
    else
      eval "echo 'df command not available' $output_target"
    fi
    
    eval "echo '--- Process List (top 20) ---' $output_target"
    if command -v ps >/dev/null 2>&1; then
      eval "ps aux 2>/dev/null | head -20 $output_target || ps -ef 2>/dev/null | head -20 $output_target"
    else
      eval "echo 'ps command not available' $output_target"
    fi
    
    eval "echo '--- Environment Variables ---' $output_target"
    eval "env | grep -E '^(PATH|HOME|USER|SHELL|PWD|LANG|LC_)' | sort $output_target"
    
    eval "echo '--- End Diagnostics ===' $output_target"
  }
  ```


### Retry Loop Integration

- Call diagnostics in retry loop after failure check (around line 327)
- Insert after `successes=0` reset and before `runs` increment:
  ```bash
  if [[ $success == false ]]; then
    successes=0
    
    # Run diagnostics if enabled and threshold reached
    if [[ $diagnostics_enabled == true && $runs -ge $diagnostics_after ]]; then
      # Only run diagnostics once per threshold (check if we've already run for this run count)
      if [[ $runs -eq $diagnostics_after ]] || [[ $((runs % diagnostics_after)) -eq 0 ]]; then
        run_diagnostics "$runs" "${log_file:-}"
      fi
    fi
  fi
  ```


### Log File Integration

- If `-log` is set, diagnostics output goes to log file
- If `-log` is not set, diagnostics output goes to stderr
- Diagnostics are clearly marked in log file with headers

### Documentation

- Update `usage()` function to document the flags:
  ```
  -diagnostics
        run system diagnostics after 3 consecutive failures
  -diagnostics-after int
        run diagnostics after N consecutive failures (default 3)
  ```


## Example Usage

```bash
# Run diagnostics after 3 failures (default)
retry -diagnostics -attempts=10 ./deploy.sh

# Run diagnostics after 5 failures
retry -diagnostics-after=5 ./deploy.sh

# Diagnostics with logging
retry -diagnostics -log=debug.log -backoff curl https://api.example.com

# Diagnostics with quiet mode (still outputs diagnostics to stderr)
retry -quiet -diagnostics ./script.sh
```

## Integration Points

- Add diagnostics function before `main()` function
- Call diagnostics in retry loop after failure check (around line 327)
- Add flag parsing in case statement (lines 122-211)
- Add validation after parsing (around line 232)
- Integrate with log file if `-log` is set
- Update `usage()` function (lines 6-32)

## Design Decisions

### When to run diagnostics

- **Decision**: Run after N consecutive failures, then every N failures
- **Rationale**: Provides diagnostics when problems persist, not on first failure
- **Alternative**: Run after every failure (too verbose)

### Diagnostics output location

- **Decision**: stderr by default, log file if `-log` is set
- **Rationale**: Diagnostics are debugging info, not normal output
- **Note**: Even with `-quiet`, diagnostics still output (they're important for debugging)

### What diagnostics to include

- **Decision**: System info, network, disk, processes, key env vars
- **Rationale**: Common debugging needs without being too verbose
- **Alternative**: Configurable diagnostic commands (more complex)

### Diagnostics frequency

- **Decision**: Run once when threshold reached, then every N failures
- **Rationale**: Balance between useful info and not flooding output
- **Implementation**: Check if `runs % diagnostics_after == 0`

## Testing Considerations

- Test diagnostics enabled with default threshold (3 failures)
- Test diagnostics with custom threshold
- Test diagnostics output to stderr (without `-log`)
- Test diagnostics output to log file (with `-log`)
- Test diagnostics with `-quiet` flag (should still output)
- Test diagnostics don't affect retry logic
- Test diagnostics on systems without all commands (ip, df, ps)
- Test backward compatibility: script works without flag

## Edge Cases

- System without `ip` or `ifconfig` command
- System without `df` or `ps` command
- Diagnostics threshold larger than total attempts
- Diagnostics with very long output (should still work)
- Diagnostics on read-only filesystem (should handle gracefully)

## Extensibility

Future enhancements could include:

- `-diagnostics-command` to run custom diagnostic commands
- `-diagnostics-once` to run diagnostics only once (not periodically)
- More diagnostic categories (DNS, load average, memory, etc.)

## Backward Compatibility

- Feature is opt-in (flag is optional)
- When flag is not set, behavior is identical to current implementation
- No breaking changes to existing functionality