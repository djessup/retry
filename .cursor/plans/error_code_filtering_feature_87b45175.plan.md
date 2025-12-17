---
name: Error Code Filtering Feature
overview: Implement error code filtering to retry only on specific exit codes, failing fast on unexpected errors.
todos:
  - id: add-flag-parsing
    content: Add -retry-on-codes flag parsing in case statement with both space-separated and equals-separated formats
    status: pending
  - id: add-validation
    content: Add validation to ensure retry-on-codes values are valid integers
    status: pending
  - id: implement-status-check
    content: Implement status code checking logic after command execution to fail fast on non-matching codes
    status: pending
  - id: update-usage
    content: Update usage() function to document the new flag
    status: pending
  - id: test-feature
    content: Test error code filtering with various exit codes and scenarios
    status: pending
---

# Error Code Filtering Feature (`-retry-on-codes`)

## Overview

Allow retrying only on specific exit codes, failing fast on unexpected errors. This prevents retrying on permanent failures (e.g., authentication errors) while retrying transient errors (e.g., timeouts, rate limits).

## Specification

**Flag**: `-retry-on-codes` (or `-retry-on-codes=CODE1,CODE2,...`)

**Behavior**:

- Accepts comma-separated list of exit codes (integers)
- When set, only retry if the exit code matches one of the specified codes
- If exit code doesn't match, exit immediately with that code (fail fast)
- Works with both command execution and HTTP tasks
- For HTTP tasks, map curl exit codes to standard codes (e.g., curl exit code 28 = timeout)
- If not set, maintain current behavior (retry on any non-zero)

## Implementation Details

### Variables

- Add `retry_on_codes` variable (comma-separated string, default empty)

### Parsing

- Parse comma-separated codes into array: `IFS=',' read -ra codes <<< "$retry_on_codes"`
- Add flag parsing in case statement (lines 122-211):
  ```bash
  -retry-on-codes)
    retry_on_codes=${2:-}
    shift 2
    ;;
  -retry-on-codes=*)
    retry_on_codes=${1#*=}
    shift 1
    ;;
  ```


### Validation

- After parsing (around line 232), validate codes are integers
- Check format: each code should match `^[0-9]+$`

### Status Checking Logic

- Modify status checking logic around lines 308-313 in [retry.sh](retry.sh)
- After capturing `status`, check if `retry_on_codes` is set
- If set, check if `status` is in the allowed codes array:
  ```bash
  if [[ -n ${retry_on_codes:-} ]]; then
    IFS=',' read -ra allowed_codes <<< "$retry_on_codes"
    local found=false
    for code in "${allowed_codes[@]}"; do
      if [[ $status -eq $code ]]; then
        found=true
        break
      fi
    done
    if [[ $found == false ]]; then
      error "exit code $status not in retry-on-codes list; failing fast"
      exit $status
    fi
  fi
  ```


### HTTP Task Mapping

- For HTTP tasks, ensure curl exit codes are properly captured
- Common curl exit codes: 28 (timeout), 6 (couldn't resolve host), 7 (failed to connect)
- These should work as-is since status is already captured

### Documentation

- Update `usage()` function to document the flag:
  ```
  -retry-on-codes codes
        comma-separated list of exit codes to retry on (default: all non-zero)
  ```


## Example Usage

```bash
# Retry only on timeout (28) and rate limit (429) errors
retry -retry-on-codes=28,429 curl https://api.example.com

# Fail fast on auth errors (401), retry on timeouts
retry -retry-on-codes=28,124 command.sh

# Retry on network errors but not permission errors
retry -retry-on-codes=6,7,28 ./network-check.sh
```

## Integration Points

- Modify status checking logic around lines 308-313 in [retry.sh](retry.sh)
- Add flag parsing in the case statement (lines 122-211)
- Add validation after parsing (around line 232)
- Update `usage()` function (lines 6-32)

## Testing Considerations

- Test with single code: `-retry-on-codes=28`
- Test with multiple codes: `-retry-on-codes=28,429,124`
- Test fail-fast behavior: command exits with code not in list
- Test retry behavior: command exits with code in list
- Test with HTTP tasks
- Test with `-invert` flag (should still respect retry-on-codes)
- Test backward compatibility: script works without flag

## Backward Compatibility

- Feature is opt-in (flag is optional)
- When flag is not set, behavior is identical to current implementation
- No breaking changes to existing functionality