#!/usr/bin/env bash
set -euo pipefail

VERSION=${RETRY_VERSION:-development}

usage() {
  cat <<'USAGE' >&2
Usage: retry [flags] command|url
  -attempts int
        maximum number of attempts (default 3)
  -backoff
        use exponential backoff when sleeping
  -consecutive int
        required number of back to back successes
  -delay duration
        initial delay period before tasks are run
  -invert
        wait for task to fail rather than succeed
  -jitter duration
        time range randomly added to sleep
  -max-time duration
        maximum total time (default 1m0s)
  -quiet
        silence all output
  -sleep duration
        time to sleep between attempts (default 5s)
  -task-time duration
        maximum time for a single attempt
  -version
        print the version and exit
USAGE
}

error() {
  echo "retry: $*" >&2
}

# parse_duration converts simple duration strings into seconds.
# Supports integers or floating numbers optionally suffixed with s, m, or h.
parse_duration() {
  local value=$1
  if [[ -z ${value:-} ]]; then
    echo 0
    return 0
  fi

  if [[ $value =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$value"
    return 0
  fi

  if [[ $value =~ ^([0-9]+(\.[0-9]+)?)([smh])$ ]]; then
    local number=${BASH_REMATCH[1]}
    local unit=${BASH_REMATCH[3]}
    case "$unit" in
      s) awk -v n="$number" 'BEGIN {printf "%.6f", n}' ;;
      m) awk -v n="$number" 'BEGIN {printf "%.6f", n * 60}' ;;
      h) awk -v n="$number" 'BEGIN {printf "%.6f", n * 3600}' ;;
      *)
        error "unsupported duration unit: $unit"
        return 1
        ;;
    esac
    return 0
  fi

  error "unable to parse duration: $value" && return 1
}

now() {
  date +%s.%N
}

elapsed() {
  local start=$1
  local current
  current=$(now)
  awk -v s="$start" -v c="$current" 'BEGIN {printf "%.6f", c - s}'
}

compare_gt() {
  local a=$1 b=$2
  awk -v a="$a" -v b="$b" 'BEGIN {exit !(a > b)}'
}

random_jitter() {
  local variance=${1:-0}
  if [[ $variance == 0 ]]; then
    echo 0
    return 0
  fi
  awk -v v="$variance" 'BEGIN {srand(); printf "%.6f", rand() * v}'
}

run_http_task() {
  local url=$1 task_time=$2 quiet=$3
  local curl_cmd=(curl --fail --silent --show-error --location --output /dev/null "$url")
  if [[ $task_time != 0 ]]; then
    curl_cmd+=(--max-time "$task_time")
  fi

  if [[ $quiet == true ]]; then
    "${curl_cmd[@]}" >/dev/null 2>&1
  else
    "${curl_cmd[@]}"
  fi
}

main() {
  local attempts=3
  local backoff=false
  local consecutive=0
  local delay=0
  local invert=false
  local jitter=0
  local total_time=60
  local quiet=false
  local sleep_time=5
  local task_time=0
  local show_version=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -attempts)
        attempts=${2:-}
        shift 2
        ;;
      -attempts=*)
        attempts=${1#*=}
        shift 1
        ;;
      -backoff)
        backoff=true
        shift 1
        ;;
      -consecutive)
        consecutive=${2:-}
        shift 2
        ;;
      -consecutive=*)
        consecutive=${1#*=}
        shift 1
        ;;
      -delay)
        delay=${2:-}
        shift 2
        ;;
      -delay=*)
        delay=${1#*=}
        shift 1
        ;;
      -invert)
        invert=true
        shift 1
        ;;
      -jitter)
        jitter=${2:-}
        shift 2
        ;;
      -jitter=*)
        jitter=${1#*=}
        shift 1
        ;;
      -max-time)
        total_time=${2:-}
        shift 2
        ;;
      -max-time=*)
        total_time=${1#*=}
        shift 1
        ;;
      -quiet)
        quiet=true
        shift 1
        ;;
      -sleep)
        sleep_time=${2:-}
        shift 2
        ;;
      -sleep=*)
        sleep_time=${1#*=}
        shift 1
        ;;
      -task-time)
        task_time=${2:-}
        shift 2
        ;;
      -task-time=*)
        task_time=${1#*=}
        shift 1
        ;;
      -version)
        show_version=true
        shift 1
        ;;
      -h|--help|-help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $show_version == true ]]; then
    echo "$VERSION"
    exit 0
  fi

  if [[ $# -eq 0 ]]; then
    error "no command given"
    usage
    exit 1
  fi

  attempts=${attempts:-0}
  consecutive=${consecutive:-0}

  delay=$(parse_duration "$delay")
  sleep_time=$(parse_duration "$sleep_time")
  jitter=$(parse_duration "$jitter")
  total_time=$(parse_duration "$total_time")
  task_time=$(parse_duration "$task_time")

  if [[ $task_time != 0 ]] && ! command -v timeout >/dev/null 2>&1; then
    error "task-time requested but the timeout command is unavailable; feature not supported yet"
    task_time=0
  fi

  local start
  start=$(now)

  if [[ $delay != 0 ]]; then
    if [[ $total_time != 0 ]] && compare_gt "$delay" "$total_time"; then
      error "initial delay exceeds maximum total time"
      exit 1
    fi
    sleep "$delay"
  fi

  local multiplier=1
  local successes=0
  local runs=0
  local required_consecutive=$(( consecutive > 0 ? consecutive : 1 ))

  while true; do
    if [[ $total_time != 0 ]] && compare_gt "$(elapsed "$start")" "$total_time"; then
      error "maximum time exceeded"
      exit 1
    fi

    local command=$1
    shift 1
    local args=("$@")

    local status=0
    if [[ $command == http://* || $command == https://* ]]; then
      if ! command -v curl >/dev/null 2>&1; then
        error "HTTP checks require curl; feature not supported yet on this system"
        exit 2
      fi
      if run_http_task "$command" "$task_time" "$quiet"; then
        status=0
      else
        status=$?
      fi
    else
      if [[ $task_time != 0 ]]; then
        if [[ $quiet == true ]]; then
          if timeout --foreground "$task_time" "$command" "${args[@]}" >/dev/null 2>&1; then
            status=0
          else
            status=$?
          fi
        else
          if timeout --foreground "$task_time" "$command" "${args[@]}"; then
            status=0
          else
            status=$?
          fi
        fi
      else
        if [[ $quiet == true ]]; then
          if "$command" "${args[@]}" >/dev/null 2>&1; then
            status=0
          else
            status=$?
          fi
        else
          if "$command" "${args[@]}"; then
            status=0
          else
            status=$?
          fi
        fi
      fi
    fi

    local success=false
    if [[ $invert == true ]]; then
      [[ $status -ne 0 ]] && success=true
    else
      [[ $status -eq 0 ]] && success=true
    fi

    if [[ $success == true ]]; then
      successes=$((successes + 1))
      multiplier=1
      if [[ $successes -ge $required_consecutive ]]; then
        exit 0
      fi
    else
      successes=0
    fi

    runs=$((runs + 1))
    if [[ $attempts -ne 0 && $runs -ge $attempts ]]; then
      error "maximum attempts exceeded"
      exit 1
    fi

    local snooze
    snooze=$(awk -v base="$sleep_time" -v mult="$multiplier" -v jit="$(random_jitter "$jitter")" 'BEGIN {printf "%.6f", base * mult + jit}')

    if [[ $total_time != 0 ]] && compare_gt "$(awk -v e="$(elapsed "$start")" -v s="$snooze" 'BEGIN {printf "%.6f", e + s}')" "$total_time"; then
      error "maximum time exceeded"
      exit 1
    fi

    sleep "$snooze"

    if [[ $backoff == true && $success == false ]]; then
      multiplier=$((multiplier * 2))
    fi

    set -- "$command" "${args[@]}"
  done
}

main "$@"
