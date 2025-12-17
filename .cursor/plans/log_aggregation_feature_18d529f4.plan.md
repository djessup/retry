---
name: Log Aggregation Feature
overview: Implement log aggregation to capture command output to files for post-mortem analysis.
todos:
  - id: add-flag-parsing
    content: Add -log flag parsing in case statement with both space-separated and equals-separated formats
    status: pending
  - id: add-log-init
    content: Add log file initialization with directory creation and header writing
    status: pending
  - id: modify-command-exec
    content: Modify command execution sections to tee output to log file when logging enabled
    status: pending
  - id: modify-http-task
    content: Modify run_http_task function to support logging with proper output capture
    status: pending
  - id: handle-quiet-mode
    content: Ensure quiet mode with logging redirects to log file only, not terminal
    status: pending
  - id: update-usage
    content: Update usage() function to document the new flag
    status: pending
  - id: test-feature
    content: Test log aggregation with various scenarios including quiet mode, HTTP tasks, and multiple attempts
    status: pending
---

# Log Aggregation Feature (`-log`)

## Overview

Capture command output (stdout/stderr) to a log file for post-mortem analysis. Useful for debugging intermittent failures.

## Specification

**Flag**: `-log FILE` (or `-log=FILE`)

**Behavior**:

- When set, redirect both stdout and stderr to the specified file
- Append to file (don't overwrite) to preserve history across attempts
- Include attempt number and timestamp in log entries
- If file path is relative, create in current directory
- If directory doesn't exist, create it (mkdir -p)
- Continue to display output to terminal unless `-quiet` is also set
- When `-quiet` is set with `-log`, only log to file

## Implementation Details

### Variables

- Add `log_file` variable (default empty)

### Parsing

- Add flag parsing in case statement (lines 122-211):
  ```bash
  -log)
    log_file=${2:-}
    shift 2
    ;;
  -log=*)
    log_file=${1#*=}
    shift 1
    ;;
  ```


### Log File Initialization

- After parsing (around line 232), initialize log file:
  ```bash
  if [[ -n ${log_file:-} ]]; then
    # Create directory if needed
    mkdir -p "$(dirname "$log_file")" || {
      error "failed to create log directory"
      exit 1
    }
    # Initialize log file with header
    echo "=== Retry session started at $(date) ===" >> "$log_file"
  fi
  ```


### Command Execution Modification

- Modify command execution sections (lines 277-305) to handle logging
- For commands without timeout and without quiet:
  ```bash
  if [[ -n ${log_file:-} ]]; then
    {
      echo "=== Attempt $runs at $(date) ==="
      "$command" "${args[@]}"
    } | tee -a "$log_file"
    status=$?
  else
    if "$command" "${args[@]}"; then
      status=0
    else
      status=$?
    fi
  fi
  ```

- For commands with timeout and without quiet:
  ```bash
  if [[ -n ${log_file:-} ]]; then
    {
      echo "=== Attempt $runs at $(date) ==="
      timeout --foreground "$task_time" "$command" "${args[@]}"
    } | tee -a "$log_file"
    status=$?
  else
    if timeout --foreground "$task_time" "$command" "${args[@]}"; then
      status=0
    else
      status=$?
    fi
  fi
  ```

- For quiet mode with logging, redirect to log file only:
  ```bash
  if [[ -n ${log_file:-} ]]; then
    {
      echo "=== Attempt $runs at $(date) ==="
      "$command" "${args[@]}"
    } >> "$log_file" 2>&1
    status=$?
  else
    # existing quiet mode logic
  fi
  ```


### HTTP Task Modification

- Modify `run_http_task()` function (lines 95-107) to support logging
- Add log_file parameter to function signature
- Capture curl output when logging:
  ```bash
  run_http_task() {
    local url=$1 task_time=$2 quiet=$3 log_file=${4:-}
    local curl_cmd=(curl --fail --silent --show-error --location "$url")
    
    if [[ $task_time != 0 ]]; then
      curl_cmd+=(--max-time "$task_time")
    fi
    
    if [[ -n ${log_file:-} ]]; then
      {
        echo "=== Attempt $runs at $(date) ==="
        "${curl_cmd[@]}"
      } >> "$log_file" 2>&1
      return $?
    elif [[ $quiet == true ]]; then
      curl_cmd+=(--output /dev/null)
      "${curl_cmd[@]}" >/dev/null 2>&1
    else
      curl_cmd+=(--output /dev/null)
      "${curl_cmd[@]}"
    fi
  }
  ```

- Update call site (line 271) to pass log_file:
  ```bash
  if run_http_task "$command" "$task_time" "$quiet" "${log_file:-}"; then
  ```


### Documentation

- Update `usage()` function to document the flag:
  ```
  -log file
        capture command output to file (appends across attempts)
  ```


## Example Usage

```bash
# Log all attempts to retry.log
retry -log=retry.log -attempts=5 ./deploy.sh

# Quiet mode with logging
retry -quiet -log=/var/log/deploy.log ./deploy.sh

# Log with timestamps for debugging
retry -log=debug.log -backoff curl https://api.example.com
```

## Integration Points

- Modify command execution sections (lines 277-305)
- Modify HTTP task execution (lines 95-107)
- Add flag parsing in case statement (lines 122-211)
- Add log file initialization after parsing (around line 232)
- Update `usage()` function (lines 6-32)

## Testing Considerations

- Test log file creation in non-existent directory
- Test appending to existing log file
- Test with `-quiet` flag (output only to log)
- Test without `-quiet` flag (output to both terminal and log)
- Test with HTTP tasks
- Test log file permissions and error handling
- Test with multiple attempts (verify all attempts logged)
- Test backward compatibility: script works without flag

## Edge Cases

- Log file in read-only directory (should error gracefully)
- Log file path with spaces (ensure proper quoting)
- Relative vs absolute paths
- Log file on different filesystem (NFS, etc.)

## Backward Compatibility

- Feature is opt-in (flag is optional)
- When flag is not set, behavior is identical to current implementation
- No breaking changes to existing functionality