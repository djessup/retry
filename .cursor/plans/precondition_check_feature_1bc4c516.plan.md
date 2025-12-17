---
name: Precondition Check Feature
overview: Implement precondition check to validate environment readiness before executing the main task.
todos:
  - id: add-flag-parsing
    content: Add -precondition flag parsing in case statement with both space-separated and equals-separated formats
    status: pending
  - id: create-precondition-function
    content: Create run_precondition() function to execute precondition command with proper timeout/quiet/logging support
    status: pending
  - id: modify-retry-loop
    content: Modify retry loop to check precondition before main task execution
    status: pending
  - id: handle-precondition-failure
    content: Implement precondition failure handling with retry logic and attempt counting
    status: pending
  - id: integrate-error-codes
    content: Integrate precondition with error code filtering if implemented
    status: pending
  - id: update-usage
    content: Update usage() function to document the new flag
    status: pending
  - id: test-feature
    content: Test precondition check with various scenarios including failures, timeouts, and integration with other flags
    status: pending
---

# Precondition Check Feature (`-precondition`)

## Overview

Execute a precondition command before running the main task. Only proceed with main task if precondition succeeds. Useful for waiting for services to be ready, checking database connectivity, or validating environment state.

## Specification

**Flag**: `-precondition COMMAND` (or `-precondition=COMMAND`)

**Behavior**:

- Before each attempt, run the precondition command
- If precondition fails, wait and retry precondition (don't run main task)
- If precondition succeeds, run main task
- Precondition is retried with same backoff/sleep logic as main task
- Precondition attempts count toward total `-attempts` limit
- Precondition can be a simple command or script
- Precondition uses same timeout/quiet/logging settings as main task

## Implementation Details

### Variables

- Add `precondition_cmd` variable (default empty)

### Parsing

- Add flag parsing in case statement (lines 122-211):
  ```bash
  -precondition)
    precondition_cmd=${2:-}
    shift 2
    ;;
  -precondition=*)
    precondition_cmd=${1#*=}
    shift 1
    ;;
  ```


### Precondition Execution Function

- Create a function to execute precondition (before `main()` function):
  ```bash
  run_precondition() {
    local cmd=$1
    local task_time=$2
    local quiet=$3
    local log_file=${4:-}
    
    if [[ -z ${cmd:-} ]]; then
      return 0  # No precondition, always pass
    fi
    
    # Parse command into executable and args
    local pre_command pre_args
    IFS=' ' read -r pre_command pre_args <<< "$cmd"
    local pre_args_array=($pre_args)
    
    local status=0
    if [[ $task_time != 0 ]]; then
      if [[ -n ${log_file:-} ]]; then
        {
          echo "=== Precondition check at $(date) ==="
          timeout --foreground "$task_time" "$pre_command" "${pre_args_array[@]}"
        } | tee -a "$log_file"
        status=$?
      elif [[ $quiet == true ]]; then
        if timeout --foreground "$task_time" "$pre_command" "${pre_args_array[@]}" >/dev/null 2>&1; then
          status=0
        else
          status=$?
        fi
      else
        if timeout --foreground "$task_time" "$pre_command" "${pre_args_array[@]}"; then
          status=0
        else
          status=$?
        fi
      fi
    else
      if [[ -n ${log_file:-} ]]; then
        {
          echo "=== Precondition check at $(date) ==="
          "$pre_command" "${pre_args_array[@]}"
        } | tee -a "$log_file"
        status=$?
      elif [[ $quiet == true ]]; then
        if "$pre_command" "${pre_args_array[@]}" >/dev/null 2>&1; then
          status=0
        else
          status=$?
        fi
      else
        if "$pre_command" "${pre_args_array[@]}"; then
          status=0
        else
          status=$?
        fi
      fi
    fi
    
    return $status
  }
  ```


### Retry Loop Modification

- Modify retry loop structure in `main()` function (around line 255)
- Current structure: command execution → success check → sleep
- New structure: precondition check → command execution → success check → sleep

- Insert precondition check before main task execution (before line 261):
  ```bash
  # Check precondition before running main task
  if [[ -n ${precondition_cmd:-} ]]; then
    if ! run_precondition "$precondition_cmd" "$task_time" "$quiet" "${log_file:-}"; then
      # Precondition failed, treat as failure and retry
      local success=false
      if [[ $invert == true ]]; then
        [[ $status -ne 0 ]] && success=true
      else
        [[ $status -eq 0 ]] && success=true
      fi
      
      # Precondition failures reset consecutive successes
      if [[ $success == false ]]; then
        successes=0
      fi
      
      runs=$((runs + 1))
      if [[ $attempts -ne 0 && $runs -ge $attempts ]]; then
        error "maximum attempts exceeded (precondition failed)"
        exit 1
      fi
      
      # Sleep and continue to retry precondition
      local snooze
      snooze=$(awk -v base="$sleep_time" -v mult="$multiplier" -v jit="$(random_jitter "$jitter")" 'BEGIN {printf "%.6f", base * mult + jit}')
      if [[ $max_sleep != 0 ]]; then
        snooze=$(awk -v s="$snooze" -v max="$max_sleep" 'BEGIN {printf "%.6f", (s > max) ? max : s}')
      fi
      
      if [[ $total_time != 0 ]] && compare_gt "$(awk -v e="$(elapsed "$start")" -v s="$snooze" 'BEGIN {printf "%.6f", e + s}')" "$total_time"; then
        error "maximum time exceeded"
        exit 1
      fi
      
      sleep "$snooze"
      
      if [[ $backoff == true && $success == false ]]; then
        multiplier=$((multiplier * 2))
      fi
      
      set -- "$command" "${args[@]}"
      continue
    fi
  fi
  ```


### Error Code Filtering Integration

- If `-retry-on-codes` is set, precondition failures should also respect it
- Check precondition exit code against retry-on-codes list
- If precondition fails with non-retryable code, exit immediately

### Documentation

- Update `usage()` function to document the flag:
  ```
  -precondition command
        run command before each attempt; retry if precondition fails
  ```


## Example Usage

```bash
# Wait for service to be ready, then deploy
retry -precondition="curl -f http://service/health" -attempts=10 ./deploy.sh

# Check database connectivity before running migration
retry -precondition="pg_isready -h localhost" ./migrate.sh

# Precondition with backoff and logging
retry -precondition="kubectl wait --for=condition=ready pod/myapp" \
      -backoff -log=deploy.log ./deploy.sh

# Precondition with timeout
retry -precondition="nc -z localhost 5432" -task-time=5s ./app.sh
```

## Integration Points

- Add precondition check before main task execution (before line 261)
- Modify retry loop structure to handle precondition + main task
- Add flag parsing in case statement (lines 122-211)
- Create `run_precondition()` function (before `main()`)
- Integrate with error code filtering if implemented
- Update `usage()` function (lines 6-32)

## Design Decisions

### Precondition attempt counting

- **Decision**: Precondition attempts count toward total `-attempts` limit
- **Rationale**: Prevents infinite loops if precondition never succeeds
- **Alternative**: Separate attempt counter for precondition (more complex)

### Precondition retry logic

- **Decision**: Use same backoff/sleep logic as main task
- **Rationale**: Consistent behavior, simpler implementation
- **Alternative**: Separate sleep/backoff for precondition (more flexible but complex)

### Precondition with invert flag

- **Decision**: Precondition always succeeds on exit code 0, fails otherwise
- **Rationale**: Precondition is about readiness, not failure detection
- **Note**: `-invert` only applies to main task, not precondition

## Testing Considerations

- Test precondition success → main task execution
- Test precondition failure → retry precondition (not main task)
- Test precondition with `-attempts` limit
- Test precondition with `-backoff` and `-max-time`
- Test precondition with `-quiet` and `-log`
- Test precondition with `-task-time` timeout
- Test precondition with `-retry-on-codes` (if implemented)
- Test backward compatibility: script works without flag
- Test edge case: empty precondition command

## Edge Cases

- Precondition command with spaces in arguments
- Precondition that takes longer than `-task-time`
- Precondition that succeeds but main task fails immediately
- Precondition with special characters or shell metacharacters
- Precondition that changes environment (should not affect main task)

## Backward Compatibility

- Feature is opt-in (flag is optional)
- When flag is not set, behavior is identical to current implementation
- No breaking changes to existing functionality