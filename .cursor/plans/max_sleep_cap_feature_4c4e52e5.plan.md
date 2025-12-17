---
name: Max Sleep Cap Feature
overview: Implement max sleep cap to limit exponential backoff duration and prevent excessive wait times.
todos:
  - id: add-flag-parsing
    content: Add -max-sleep flag parsing in case statement with both space-separated and equals-separated formats
    status: pending
  - id: add-duration-parsing
    content: Parse max-sleep duration using parse_duration() function
    status: pending
  - id: modify-sleep-calculation
    content: Modify sleep calculation to apply max-sleep cap when enabled
    status: pending
  - id: add-validation
    content: Add validation to ensure max-sleep >= sleep when both are set
    status: pending
  - id: update-usage
    content: Update usage() function to document the new flag
    status: pending
  - id: test-feature
    content: Test max sleep cap with various scenarios including backoff, jitter, and edge cases
    status: pending
---

# Max Sleep Cap Feature (`-max-sleep`)

## Overview

Cap the maximum sleep duration for exponential backoff to prevent excessive wait times. Prevents exponential backoff from growing too large.

## Specification

**Flag**: `-max-sleep DURATION` (or `-max-sleep=DURATION`)

**Behavior**:

- Sets maximum sleep duration regardless of exponential backoff multiplier
- Only applies when `-backoff` is enabled (or should apply to any sleep calculation?)
- Uses `parse_duration()` for parsing (supports s, m, h suffixes)
- Default: no cap (current behavior)
- When sleep calculation exceeds cap, use cap value instead
- Still applies jitter after capping

## Implementation Details

### Variables

- Add `max_sleep` variable (default 0 = no cap)

### Parsing

- Add flag parsing in case statement (lines 122-211):
  ```bash
  -max-sleep)
    max_sleep=${2:-}
    shift 2
    ;;
  -max-sleep=*)
    max_sleep=${1#*=}
    shift 1
    ;;
  ```


### Duration Parsing

- Parse duration using existing `parse_duration()` function (around line 232):
  ```bash
  max_sleep=$(parse_duration "${max_sleep:-0}")
  ```


### Sleep Calculation Modification

- Modify sleep calculation around line 336 in [retry.sh](retry.sh)
- Current calculation:
  ```bash
  snooze=$(awk -v base="$sleep_time" -v mult="$multiplier" -v jit="$(random_jitter "$jitter")" 'BEGIN {printf "%.6f", base * mult + jit}')
  ```

- New calculation with cap:
  ```bash
  snooze=$(awk -v base="$sleep_time" -v mult="$multiplier" -v jit="$(random_jitter "$jitter")" 'BEGIN {printf "%.6f", base * mult + jit}')
  if [[ $max_sleep != 0 ]]; then
    snooze=$(awk -v s="$snooze" -v max="$max_sleep" 'BEGIN {printf "%.6f", (s > max) ? max : s}')
  fi
  ```


### Validation

- Add validation after parsing to ensure max-sleep >= sleep (if both set):
  ```bash
  if [[ $max_sleep != 0 && $sleep_time != 0 ]] && compare_gt "$sleep_time" "$max_sleep"; then
    error "max-sleep ($max_sleep) must be greater than or equal to sleep ($sleep_time)"
    exit 1
  fi
  ```


### Documentation

- Update `usage()` function to document the flag:
  ```
  -max-sleep duration
        maximum sleep duration when using backoff (default: no limit)
  ```


## Example Usage

```bash
# Exponential backoff capped at 30 seconds
retry -backoff -max-sleep=30s curl https://api.example.com

# Cap at 1 minute
retry -backoff -max-sleep=1m -sleep=2s ./script.sh

# With jitter, cap ensures max wait is reasonable
retry -backoff -max-sleep=60s -jitter=5s -sleep=1s ./deploy.sh
```

## Integration Points

- Modify sleep calculation (line 336)
- Add flag parsing in case statement (lines 122-211)
- Add duration parsing (around line 232)
- Add validation after parsing
- Update `usage()` function (lines 6-32)

## Design Decisions

### Should max-sleep apply without backoff?

- Option A: Only apply when `-backoff` is enabled (simpler, more focused)
- Option B: Apply to all sleep calculations (more general purpose)
- **Recommendation**: Option A - max-sleep is specifically for limiting exponential backoff growth. Without backoff, sleep_time is constant, so capping is less useful.

### Jitter application order

- Current: Calculate base sleep, add jitter, then cap
- Alternative: Cap base sleep, then add jitter (could exceed cap)
- **Recommendation**: Current approach - cap the final sleep value including jitter to ensure true maximum

## Testing Considerations

- Test with exponential backoff enabled
- Test without backoff (should have no effect if we choose Option A)
- Test with various max-sleep values (smaller than, equal to, larger than base sleep)
- Test with jitter to ensure cap still applies
- Test validation: max-sleep < sleep should error
- Test edge case: max-sleep = 0 (should disable cap)
- Test backward compatibility: script works without flag

## Edge Cases

- max-sleep smaller than initial sleep_time (should validate and error)
- max-sleep exactly equal to calculated sleep (should work)
- max-sleep with very large multiplier values (should cap correctly)
- max-sleep with jitter that would exceed cap (should cap final value)

## Backward Compatibility

- Feature is opt-in (flag is optional)
- When flag is not set, behavior is identical to current implementation
- No breaking changes to existing functionality