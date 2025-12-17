#!/usr/bin/env bats

setup() {
  RETRY_SCRIPT="${BATS_TEST_DIRNAME}/../retry.sh"
}

@test "prints version" {
  run "$RETRY_SCRIPT" -version
  [ "$status" -eq 0 ]
  [[ "$output" =~ development ]]
}

@test "errors when no command is provided" {
  run "$RETRY_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "no command" ]]
}

@test "succeeds when command exits zero" {
  run "$RETRY_SCRIPT" -sleep=0s true
  [ "$status" -eq 0 ]
}

@test "respects attempts limit" {
  tmpfile=$(mktemp)
  run "$RETRY_SCRIPT" -attempts=2 -sleep=0s bash -c 'echo run >> "$1"; exit 1' _ "$tmpfile"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$tmpfile")" -eq 2 ]
}

@test "requires consecutive successes" {
  counter=$(mktemp)
  echo 0 > "$counter"
  run "$RETRY_SCRIPT" -sleep=0s -consecutive=2 bash -c '
    count=$(cat "$1")
    count=$((count+1))
    echo "$count" > "$1"
    if [[ $count -eq 1 ]]; then
      exit 1
    else
      exit 0
    fi
  ' _ "$counter"
  [ "$status" -eq 0 ]
  [ "$(cat "$counter")" -eq 3 ]
}

@test "invert flag treats failures as success" {
  run "$RETRY_SCRIPT" -invert -attempts=1 false
  [ "$status" -eq 0 ]
}

@test "task time limits long-running commands" {
  run "$RETRY_SCRIPT" -task-time=0.1s -attempts=1 -sleep=0s bash -c 'sleep 1'
  [ "$status" -eq 1 ]
  [[ "$output" =~ "maximum attempts exceeded" ]]
}

@test "max time stops retries" {
  run "$RETRY_SCRIPT" -max-time=0.2s -sleep=0.15s false
  [ "$status" -eq 1 ]
  [[ "$output" =~ "maximum time exceeded" ]]
}
