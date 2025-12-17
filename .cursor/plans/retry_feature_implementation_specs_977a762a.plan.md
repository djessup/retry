---
name: Retry Feature Implementation Specs
overview: "Create detailed implementation specifications for 6 new retry features: error code filtering, log aggregation, max sleep cap, precondition check, progressive diagnostics, and Fibonacci backoff."
todos:
  - id: max-sleep-cap
    content: Implement max sleep cap feature (-max-sleep flag) to limit exponential backoff duration
    status: pending
  - id: fibonacci-backoff
    content: Implement Fibonacci backoff option (-backoff=fibonacci) as alternative to exponential backoff
    status: pending
  - id: error-code-filtering
    content: Implement error code filtering (-retry-on-codes) to retry only on specific exit codes
    status: pending
  - id: log-aggregation
    content: Implement log aggregation (-log) to capture command output to files
    status: pending
  - id: progressive-diagnostics
    content: Implement progressive diagnostics (-diagnostics) to run system checks after failures
    status: pending
  - id: precondition-check
    content: Implement precondition check (-precondition) to validate environment before task execution
    status: pending
---

# Retry Feature Implementation Specifications

This plan defines implementation specifications for 6 new features to enhance the `retry.sh` script with production-ready capabilities.

## Feature 1: Error Code Filtering (`-retry-on-codes`)

### Overview

Allow retrying only on specific exit codes, failing fast on unexpected errors. This prevents retrying on permanent failures (e.g., authentication errors) while retrying transient errors (e.g., timeouts, rate limits).

### Specification

**Flag**: `-retry-on-codes` (or `-retry-on-codes=CODE1,CODE2,...`)

**Behavior**:

- Accepts comma-separated list of exit codes (integers)
- When set, only retry if the exit code matches one of the specified codes
- If exit code doesn't match, exit immediately with that code (fail fast)
- Works with both command execution and HTTP tasks
- For HTTP tasks, map curl exit codes to standard codes (e.g., curl exit code 28 = timeout)
- If not set, maintain current behavior (retry on any non-zero)

**Implementation Details**:

- Add `retry_on_codes` variable (array or comma-separated string)
- Parse comma-separated codes into array: `IFS=',' read -ra codes <<< "$retry_on_codes"`
- After capturing `status`, check if `retry_on_codes` is set
- If set, check if `status` is in the allowed codes array
- If not in array, exit immediately with `status`
- Update `usage()` to document the flag
- Add validation to ensure codes are integers

**Example Usage**:

```bash
# Retry only on timeout (28) and rate limit (429) errors
retry -retry-on-codes=28,429 curl https://api.example.com

# Fail fast on auth errors (401), retry on timeouts
retry -retry-on-codes=28,124 command.sh
```

**Integration Points**:

- Modify status checking logic around lines 308-313 in `retry.sh`
- Add flag parsing in the case statement (lines 122-211)
- Add validation after parsing (around line 232)

---

## Feature 2: Log Aggregation (`-log`)

### Overview

Capture command output (stdout/stderr) to a log file for post-mortem analysis. Useful for debugging intermittent failures.

### Specification

**Flag**: `-log FILE` (or `-log=FILE`)

**Behavior**:

- When set, redirect both stdout and stderr to the specified file
- Append to file (don't overwrite) to preserve history across attempts
- Include attempt number and timestamp in log entries
- If file path is relative, create in current directory
- If directory doesn't exist, create it (mkdir -p)
- Continue to display output to terminal unless `-quiet` is also set
- When `-quiet` is set with `-log`, only log to file

**Implementation Details**:

- Add `log_file` variable (default empty)
- Create log file directory if needed: `mkdir -p "$(dirname "$log_file")"`
- Modify command execution to tee output:
  - Without quiet: `command | tee -a "$log_file"`
  - With quiet: redirect to log file only
- Add log entry headers: `echo "=== Attempt $runs at $(date) ===" >> "$log_file"`
- Handle HTTP tasks by capturing curl output
- Update `usage()` to document the flag

**Example Usage**:

```bash
# Log all attempts to retry.log
retry -log=retry.log -attempts=5 ./deploy.sh

# Quiet mode with logging
retry -quiet -log=/var/log/deploy.log ./deploy.sh
```

**Integration Points**:

- Modify command execution sections (lines 277-305)
- Modify HTTP task execution (lines 95-107)
- Add flag parsing in case statement
- Add log file initialization after parsing

---

## Feature 3: Max Sleep Cap (`-max-sleep`)

### Overview

Cap the maximum sleep duration for exponential backoff to prevent excessive wait times. Prevents exponential backoff from growing too large.

### Specification

**Flag**: `-max-sleep DURATION` (or `-max-sleep=DURATION`)

**Behavior**:

- Sets maximum sleep duration regardless of exponential backoff multiplier
- Only applies when `-backoff` is enabled
- Uses `parse_duration()` for parsing (supports s, m, h suffixes)
- Default: no cap (current behavior)
- When sleep calculation exceeds cap, use cap value instead
- Still applies jitter after capping

**Implementation Details**:

- Add `max_sleep` variable (default 0 = no cap)
- Parse duration using existing `parse_duration()` function
- Modify sleep calculation around line 336:
  ```bash
  snooze=$(awk -v base="$sleep_time" -v mult="$multiplier" -v jit="$(random_jitter "$jitter")" 'BEGIN {printf "%.6f", base * mult + jit}')
  if [[ $max_sleep != 0 ]]; then
    snooze=$(awk -v s="$snooze" -v max="$max_sleep" 'BEGIN {printf "%.6f", (s > max) ? max : s}')
  fi
  ```

- Update `usage()` to document the flag
- Add validation to ensure max-sleep >= sleep (if both set)

**Example Usage**:

```bash
# Exponential backoff capped at 30 seconds
retry -backoff -max-sleep=30s curl https://api.example.com

# Cap at 1 minute
retry -backoff -max-sleep=1m -sleep=2s ./script.sh
```

**Integration Points**:

- Modify sleep calculation (line 336)
- Add flag parsing in case statement
- Add validation after parsing

---

## Feature 4: Precondition Check (`-precondition`)

### Overview

Execute a precondition command before running the main task. Only proceed with main task if precondition succeeds.

### Specification

**Flag**: `-precondition COMMAND` (or `-precondition=COMMAND`)

**Behavior**:

- Before each attempt, run the precondition command
- If precondition fails, wait and retry precondition (don't run main task)
- If precondition succeeds, run main task
- Precondition is retried with same backoff/sleep logic as main task
- Precondition attempts count toward total `-attempts` limit
- Precondition can be a simple command or script

**Implementation Details**:

- Add `precondition_cmd` variable (default empty)
- Add precondition execution before main task (around line 261)
- Precondition uses same timeout/quiet/logging as main task
- Structure: precondition loop → main task → success check
- Track precondition attempts separately for better error messages
- Update `usage()` to document the flag

**Example Usage**:

```bash
# Wait for service to be ready, then deploy
retry -precondition="curl -f http://service/health" -attempts=10 ./deploy.sh

# Check database connectivity before running migration
retry -precondition="pg_isready -h localhost" ./migrate.sh
```

**Integration Points**:

- Add precondition check before main task execution (before line 261)
- Modify retry loop structure to handle precondition + main task
- Add flag parsing in case statement

---

## Feature 5: Progressive Diagnostics (`-diagnostics`)

### Overview

Run diagnostic commands after repeated failures to aid debugging. Provides system/network information when failures persist.

### Specification

**Flag**: `-diagnostics` (boolean) or `-diagnostics-after N` (run after N failures)

**Behavior**:

- When enabled, run diagnostic commands after N consecutive failures
- Default: run after 3 failures if `-diagnostics` is set
- Customizable threshold with `-diagnostics-after`
- Diagnostics run before sleep/backoff
- Output diagnostics to stderr (or log file if `-log` is set)
- Include: system info (uname), network status (ifconfig/ip), disk space (df), process info (ps)

**Implementation Details**:

- Add `diagnostics_enabled` boolean (default false)
- Add `diagnostics_after` integer (default 3)
- Create `run_diagnostics()` function:
  ```bash
  run_diagnostics() {
    echo "=== Diagnostics (after $runs failures) ===" >&2
    uname -a >&2
    command -v ip >/dev/null && ip addr show >&2 || ifconfig >&2
    df -h >&2
    ps aux | head -20 >&2
  }
  ```

- Call diagnostics before sleep when `runs >= diagnostics_after`
- Update `usage()` to document flags

**Example Usage**:

```bash
# Run diagnostics after 3 failures
retry -diagnostics -attempts=10 ./deploy.sh

# Run diagnostics after 5 failures
retry -diagnostics-after=5 ./deploy.sh
```

**Integration Points**:

- Add diagnostics function before `main()`
- Call diagnostics in retry loop after failure check (around line 327)
- Add flag parsing in case statement

---

## Feature 6: Fibonacci Backoff (`-backoff=fibonacci`)

### Overview

Alternative backoff strategy using Fibonacci sequence instead of exponential doubling. Provides smoother backoff curve.

### Specification

**Flag**: Modify `-backoff` to accept value: `-backoff=exponential` (default) or `-backoff=fibonacci`

**Behavior**:

- Keep current `-backoff` flag for backward compatibility (defaults to exponential)
- Add `-backoff=fibonacci` option for Fibonacci backoff
- Fibonacci sequence: 1, 1, 2, 3, 5, 8, 13, 21, ...
- Use Fibonacci values as multiplier instead of exponential (2^n)
- Reset to first Fibonacci value (1) on success
- Still applies base sleep time and jitter

**Implementation Details**:

- Change `backoff` from boolean to string: `exponential` (default) or `fibonacci`
- Add `fib_a` and `fib_b` variables (start at 1, 1)
- Modify backoff logic around line 345:
  ```bash
  if [[ $backoff == "exponential" && $success == false ]]; then
    multiplier=$((multiplier * 2))
  elif [[ $backoff == "fibonacci" && $success == false ]]; then
    local temp=$fib_b
    fib_b=$((fib_a + fib_b))
    fib_a=$temp
    multiplier=$fib_a
  fi
  ```

- Reset Fibonacci on success: `fib_a=1; fib_b=1`
- Update `usage()` to document options
- Maintain backward compatibility: `-backoff` alone = exponential

**Example Usage**:

```bash
# Exponential backoff (default)
retry -backoff curl https://api.example.com

# Explicit exponential
retry -backoff=exponential curl https://api.example.com

# Fibonacci backoff
retry -backoff=fibonacci curl https://api.example.com
```

**Integration Points**:

- Modify backoff flag parsing (line 132-134)
- Change `backoff` variable initialization (line 111)
- Modify backoff calculation (line 345)
- Reset Fibonacci sequence on success (line 317)

---

## Implementation Order Recommendation

1. **Max Sleep Cap** - Simplest, isolated change
2. **Fibonacci Backoff** - Modifies existing backoff logic
3. **Error Code Filtering** - Core retry logic change
4. **Log Aggregation** - Output redirection
5. **Progressive Diagnostics** - Additive feature
6. **Precondition Check** - Most complex, changes loop structure

## Testing Considerations

Each feature should be tested with:

- Basic functionality test
- Integration with existing flags
- Edge cases (empty values, invalid inputs)
- Backward compatibility (existing scripts should still work)

## Backward Compatibility

All features maintain backward compatibility:

- Existing flags work unchanged
- New flags are optional
- Default behaviors preserved
- No breaking changes to existing functionality