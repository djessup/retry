# AGENTS.md

This document guides LLM agents working in this repository to achieve better performance in project comprehension, context efficiency, conventions, and output quality.

## Project Overview & Purpose

### System Purpose & Constraints

This repository is a **bash port** of the `retry` CLI tool (originally written in Go). The primary purpose is to provide a pure bash implementation that can rerun commands until they succeed or fail, with configurable retry logic including exponential backoff, jitter, time limits, and consecutive success requirements.

**Primary users**: DevOps engineers, CI/CD pipeline authors, system administrators who need reliable retry logic in bash environments without requiring Go tooling.

**Top use cases**:
1. Health checking services until they become ready (e.g., `retry.sh -consecutive=3 curl http://service/health`)
2. Retrying flaky network operations with exponential backoff
3. Waiting for resources to become available with timeout protection
4. Retrying commands until they fail (using `-invert` flag)
5. CI/CD pipeline steps that need resilience to transient failures

**Key constraints**:
- Must work in POSIX-compliant bash environments (bash 4.0+)
- No external dependencies beyond standard Unix utilities (`awk`, `date`, `sleep`, `timeout`, `curl`)
- Must maintain feature parity with the original Go implementation (for reference)
- Performance: Should handle sub-second retry intervals efficiently
- Portability: Must work on Linux, macOS, and other Unix-like systems

### Critical Invariants

- **Exit codes**: Script must exit with 0 on success, non-zero on failure. Exit code 1 = retry limit exceeded, Exit code 2 = system requirement missing (e.g., curl unavailable)
- **Error propagation**: Command exit codes are preserved when using `-retry-on-codes` (if implemented), otherwise retry logic applies
- **Time precision**: All time calculations use floating-point seconds with 6 decimal precision (via `awk`)
- **State management**: Variables are local-scoped within functions; no global state mutations except within `main()`
- **Side effects**: Script does not modify filesystem except for log files (if `-log` is used)
- **Concurrency**: Script is single-threaded; no parallel execution of retry attempts

### Key Dependencies

**Internal components**:
- `retry.sh` (main script) → `parse_duration()`, `now()`, `elapsed()`, `compare_gt()`, `random_jitter()`, `run_http_task()`, `main()`
- `test/retry.bats` → Tests the main script functionality

**External dependencies**:
- `awk`: Required for floating-point arithmetic and duration parsing
- `date`: Required for timestamp generation (`date +%s.%N`)
- `sleep`: Required for delays between attempts
- `timeout`: Optional but recommended for `-task-time` feature
- `curl`: Required for HTTP/HTTPS URL handling

**Reference only (DO NOT MODIFY)**:
- `main.go`, `retry/retry.go`, `retry/task.go`, `retry/retry_test.go`: Original Go implementation for reference only
- `go.mod`, `go.sum`: Go dependency files (ignore)

### Domain Glossary

- **Attempt**: A single execution of the command being retried
- **Backoff**: Increasing delay between retry attempts (exponential: doubles each time)
- **Jitter**: Random variance added to sleep duration to prevent thundering herd
- **Consecutive successes**: Number of successful attempts required in a row before overall success
- **Task time**: Maximum duration for a single attempt execution
- **Max time**: Maximum total wall-clock time for all retries combined
- **Invert**: Flip success/failure semantics (useful for waiting until something fails)

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    retry.sh (Main Entry)                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Flag Parsing │→ │ Validation   │→ │ Retry Loop   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         │                   │                  │         │
│         ↓                   ↓                  ↓         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Utility Functions                        │  │
│  │  parse_duration()  now()  elapsed()              │  │
│  │  compare_gt()  random_jitter()  run_http_task() │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │
         ↓
┌─────────────────────────────────────────────────────────┐
│              test/retry.bats (Test Suite)               │
└─────────────────────────────────────────────────────────┘
```

## Repository Structure & Navigation

### Repository Map

**Root directory** (`/`):
- `retry.sh`: Main bash script implementation (354 lines)
- `README.md`: User documentation and usage examples
- `LICENSE.txt`: MIT license file
- `AGENTS.md`: This file (agent guidance)

**`test/` directory**:
- `retry.bats`: BATS test suite for bash script
- **Role**: Contains all automated tests for the bash implementation
- **Entry points**: `bats test/retry.bats` (run all tests)

**`.github/workflows/` directory**:
- `bash.yaml`: CI/CD pipeline for bash script (shellcheck linting, bats testing)
- `build.yaml`: CI/CD for Go code (IGNORE - for reference only)
- `golangci-lint.yaml`: Go linting (IGNORE - for reference only)
- `commitlint.yaml`: Commit message linting
- `release.yaml`: Release automation

**`.cursor/plans/` directory**:
- Feature implementation plans (meta-plans and individual feature specs)
- **Role**: Contains detailed implementation specifications for planned features
- **Entry points**: See individual plan files for feature details

**`retry/` directory** (IGNORE - Go code for reference only):
- `retry.go`: Original Go retry logic
- `task.go`: Original Go task abstraction
- `retry_test.go`: Original Go tests
- **DO NOT MODIFY**: These files are kept for reference to understand original behavior

**Root Go files** (IGNORE - for reference only):
- `main.go`: Original Go CLI entry point
- `go.mod`, `go.sum`: Go module files

### Golden Path Trace

**Example: Retry a command with exponential backoff**

1. **Entry**: `retry.sh` line 353: `main "$@"`
2. **Flag parsing**: `retry.sh` lines 122-212: Parse `-attempts`, `-backoff`, `-sleep`, etc.
3. **Validation**: `retry.sh` lines 228-237: Parse durations, validate dependencies
4. **Initial delay**: `retry.sh` lines 242-248: Apply `-delay` if set
5. **Retry loop**: `retry.sh` lines 255-350:
   - Check max-time: line 256
   - Execute command: lines 266-306 (HTTP vs regular command)
   - Evaluate success: lines 308-313
   - Check consecutive successes: lines 315-324
   - Calculate sleep with backoff: lines 335-336
   - Apply sleep: line 343
   - Update backoff multiplier: lines 345-347
6. **Exit**: Success (line 323) or failure (lines 258, 321, 332, 340)

### Task→Location Routing Table

| If you need to... | Start in (paths) | Usually touch (paths) |
|------------------|------------------|----------------------|
| Add a new flag | `retry.sh` lines 122-212 (flag parsing) | `retry.sh` (usage function, validation, logic), `test/retry.bats` |
| Modify retry logic | `retry.sh` lines 255-350 (main loop) | `retry.sh` (utility functions if needed), `test/retry.bats` |
| Add a utility function | `retry.sh` lines 38-107 (utility section) | `retry.sh` (call sites), `test/retry.bats` |
| Fix duration parsing | `retry.sh` lines 38-68 (`parse_duration`) | `test/retry.bats` (duration tests) |
| Add HTTP handling | `retry.sh` lines 95-107 (`run_http_task`) | `retry.sh` (HTTP detection logic line 266), `test/retry.bats` |
| Add a test case | `test/retry.bats` | `retry.sh` (if new functionality needed) |
| Review original Go behavior | `retry/retry.go`, `main.go` | None (reference only) |

### Do-Not-Open List

**DO NOT MODIFY** (reference only):
- `main.go` - Original Go CLI entry point
- `retry/retry.go` - Original Go retry logic
- `retry/task.go` - Original Go task abstraction
- `retry/retry_test.go` - Original Go tests
- `go.mod`, `go.sum` - Go dependency files
- `.github/workflows/build.yaml` - Go build CI (unless updating bash CI)
- `.github/workflows/golangci-lint.yaml` - Go linting CI

**DO NOT CREATE**:
- Go source files (`.go`)
- Go test files (`*_test.go` outside of `retry/` directory)
- Go module files (`go.mod`, `go.sum`)

**Only open Go files when**:
- You need to understand the original implementation behavior
- You need to verify feature parity
- You need to understand edge cases from the original code

### Entry Point Index

**Bash script entry points**:
- `retry.sh`: Main executable script (line 353: `main "$@"`)
- `test/retry.bats`: Test suite entry point (`bats test/retry.bats`)

**CI/CD entry points**:
- `.github/workflows/bash.yaml`: Bash linting and testing
- `.github/workflows/commitlint.yaml`: Commit message validation

### When to Use Retrieval vs Direct Inspection

**Use codebase search when**:
- You don't know which function handles a specific feature
- You need to find all usages of a function or variable
- You're looking for patterns or conventions across the codebase
- You need to understand how a feature is implemented

**Use direct file view when**:
- You have the exact file path and line numbers
- You're reading a specific function implementation
- You're reviewing test cases in `test/retry.bats`
- You're checking flag parsing logic (known location: `retry.sh` lines 122-212)

**Use symbol search when**:
- Looking for function definitions (e.g., `parse_duration`, `run_http_task`)
- Finding where a variable is set or used
- Locating test cases for specific features

**Use regex search when**:
- Finding all flag definitions (pattern: `-flag-name`)
- Finding error message strings
- Finding specific patterns in duration parsing

### Component Boundaries

**`retry.sh` responsibilities**:
- Command-line argument parsing
- Duration string parsing and validation
- Retry loop orchestration
- Command execution (regular and HTTP)
- Time tracking and limits
- Backoff and jitter calculations
- Success/failure evaluation

**`retry.sh` does NOT**:
- Manage external dependencies (assumes they exist)
- Provide installation or packaging logic
- Handle signal trapping (relies on `set -euo pipefail`)
- Provide configuration file parsing (flags only)

**`test/retry.bats` responsibilities**:
- Unit tests for all flags and features
- Integration tests for retry logic
- Edge case validation
- Error condition testing

### Minimal Working Sets

**For adding a new flag**:
1. `retry.sh` (flag parsing, usage, validation, logic)
2. `test/retry.bats` (test cases)

**For modifying retry logic**:
1. `retry.sh` (main loop: lines 255-350)
2. `test/retry.bats` (affected test cases)

**For utility function changes**:
1. `retry.sh` (function definition, call sites)
2. `test/retry.bats` (tests for affected features)

### Saved Search Recipes

```bash
# Find all flag definitions
grep -E '^\s+-[a-z-]+\)' retry.sh

# Find all error messages
grep -E 'error "' retry.sh

# Find all function definitions
grep -E '^[a-z_]+\(\)' retry.sh

# Find duration parsing usage
grep -E 'parse_duration' retry.sh

# Find test cases for a specific flag
grep -E '@test.*flag-name' test/retry.bats
```

## Conventions, Patterns & Standards

### Enforced Style & Lint Rules

**ShellCheck** (required):
```bash
shellcheck retry.sh
```
- Run before committing: `.github/workflows/bash.yaml` enforces this
- Fix all warnings before submitting changes
- Common issues: quote variables, use `[[ ]]` for tests, avoid `$?` in conditionals

**BATS tests** (required):
```bash
bats test/retry.bats
```
- All new features must have test coverage
- Tests use BATS framework conventions (`@test`, `run`, `[ "$status" -eq 0 ]`)

**Bash style**:
- Use `set -euo pipefail` at script start (already present)
- Use `local` for all function variables
- Use `[[ ]]` for conditionals, not `[ ]`
- Quote all variable expansions: `"$variable"`
- Use `$(command)` for command substitution, not backticks

### Naming Conventions

**Functions** (2-3 examples):
- `parse_duration()` - lowercase with underscores, verb-noun pattern
- `run_http_task()` - verb-noun pattern, descriptive action
- `random_jitter()` - adjective-noun pattern for utility functions

**Variables** (examples from code):
- `sleep_time` - lowercase with underscores, descriptive
- `total_time` - lowercase with underscores, clear purpose
- `required_consecutive` - lowercase with underscores, descriptive

**Files**:
- `retry.sh` - lowercase, descriptive, `.sh` extension
- `retry.bats` - lowercase, matches script name, `.bats` extension

**Tests**:
- `@test "prints version"` - descriptive string in quotes, lowercase
- `@test "errors when no command is provided"` - describes expected behavior

**Flags**:
- `-attempts` - lowercase, hyphenated, singular noun
- `-max-time` - lowercase, hyphenated, descriptive
- `-retry-on-codes` - lowercase, hyphenated, action-descriptive

### Existing Utilities Index

**Duration parsing**:
- `parse_duration(value)` in `retry.sh` lines 38-68
- Converts duration strings (e.g., "5s", "1m", "2h") to seconds (float)
- Usage: `sleep_time=$(parse_duration "$sleep_time")`
- Supports: integers, floats, suffixes (s, m, h)

**Time utilities**:
- `now()` in `retry.sh` lines 70-72: Returns current timestamp as float seconds
- `elapsed(start)` in `retry.sh` lines 74-79: Calculates elapsed time since start
- Usage: `start=$(now)` then `elapsed_time=$(elapsed "$start")`

**Comparison utilities**:
- `compare_gt(a, b)` in `retry.sh` lines 81-84: Returns true if a > b (floating point)
- Usage: `if compare_gt "$(elapsed "$start")" "$total_time"; then`

**Random utilities**:
- `random_jitter(variance)` in `retry.sh` lines 86-93: Returns random float 0..variance
- Usage: `jitter=$(random_jitter "$jitter")`

**HTTP utilities**:
- `run_http_task(url, task_time, quiet)` in `retry.sh` lines 95-107: Executes HTTP GET request
- Usage: `run_http_task "$command" "$task_time" "$quiet"`
- Handles curl command construction, timeout, quiet mode

**Error utilities**:
- `error(message)` in `retry.sh` lines 34-36: Prints error to stderr with "retry: " prefix
- Usage: `error "maximum attempts exceeded"`

**Usage display**:
- `usage()` in `retry.sh` lines 6-32: Prints help text to stderr
- Usage: `usage` (called on `-h` flag or invalid flags)

### Modify vs Extend vs Create Decision Rules

1. **DO NOT modify Go files** (`*.go`, `go.mod`, `go.sum`) - they are reference only
2. **Extend existing functions** when adding similar functionality (e.g., add new flag parsing case to existing switch)
3. **Create new utility functions** when introducing orthogonal functionality (e.g., `run_diagnostics()` for new diagnostics feature)
4. **Modify `main()` retry loop** when changing core retry behavior (e.g., adding precondition checks)
5. **Extend `usage()` function** when adding new flags (add to help text)
6. **Create new test cases** in `test/retry.bats` for each new feature (don't modify existing tests unless fixing bugs)
7. **Extend existing test patterns** when testing similar features (follow existing `@test` structure)
8. **DO NOT create wrapper scripts** - all functionality should be in `retry.sh`

### Anti-Patterns & Deprecated Approaches

**❌ DON'T: Use `[ ]` for conditionals**
```bash
if [ $status -eq 0 ]; then  # WRONG
```
**✅ DO: Use `[[ ]]` for conditionals**
```bash
if [[ $status -eq 0 ]]; then  # CORRECT
```
See: `retry.sh` lines 309-313

**❌ DON'T: Unquoted variable expansions**
```bash
if [[ $value =~ pattern ]]; then  # WRONG if value might be empty
```
**✅ DO: Quote variable expansions**
```bash
if [[ ${value:-} =~ pattern ]]; then  # CORRECT
```
See: `retry.sh` line 42, 47

**❌ DON'T: Use `$?` directly in conditionals**
```bash
command; if [ $? -eq 0 ]; then  # WRONG
```
**✅ DO: Use command directly in conditional**
```bash
if command; then  # CORRECT
```
See: `retry.sh` lines 271-275, 279-304

**❌ DON'T: Modify Go files for bash port**
```bash
# Any changes to *.go files  # WRONG
```
**✅ DO: Only modify bash script**
```bash
# Changes only in retry.sh  # CORRECT
```

**❌ DON'T: Global variables in functions**
```bash
function example() {
  counter=0  # WRONG - pollutes global scope
}
```
**✅ DO: Use local variables**
```bash
function example() {
  local counter=0  # CORRECT
}
```
See: `retry.sh` lines 40-41, 70-71, 75-76, etc.

**❌ DON'T: Hardcode error messages**
```bash
echo "Error occurred"  # WRONG - inconsistent formatting
```
**✅ DO: Use error() function**
```bash
error "maximum attempts exceeded"  # CORRECT - consistent format
```
See: `retry.sh` lines 257, 268, 331, etc.

### Architectural Principles

**Layering** (from outer to inner):
1. **CLI Interface** (`main()` function): Parses flags, validates input, orchestrates retry
2. **Retry Logic** (main loop): Manages attempts, timing, success tracking
3. **Command Execution** (`run_http_task()` or direct execution): Executes the actual command
4. **Utilities** (`parse_duration()`, `now()`, etc.): Pure functions for calculations

**Dependency direction**: CLI → Retry Logic → Command Execution → Utilities (utilities have no dependencies on higher layers)

**Example violation and fix**:
- ❌ **Violation**: `parse_duration()` calling `error()` directly (mixing utility with I/O)
- ✅ **Fix**: `parse_duration()` returns error via exit code, caller handles `error()` call (see `retry.sh` lines 60, 67)

### Performance Patterns

**Floating-point arithmetic**: Use `awk` for all floating-point calculations (bash doesn't support floats natively)
- Pattern: `awk -v var="$value" 'BEGIN {printf "%.6f", calculation}'`
- See: `retry.sh` lines 56-58, 78, 83, 92, 336, 338

**Time precision**: Use `date +%s.%N` for sub-second precision (line 71)

**Command execution**: Minimize subprocess calls in hot loops
- Prefer built-in bash features (`[[ ]]`, arithmetic `$(( ))`) over external commands
- Use arrays for command construction: `curl_cmd=(curl ...)` then `"${curl_cmd[@]}"` (line 97)

**Sleep calculation**: Calculate once per iteration, not multiple times (line 336)

## Quality Standards & Completeness Requirements

### Definition of Done Checklist

Every change must ensure:

- [ ] **Tests updated/added**: New test cases in `test/retry.bats` for new features, existing tests pass
- [ ] **ShellCheck passes**: Run `shellcheck retry.sh` and fix all warnings
- [ ] **BATS tests pass**: Run `bats test/retry.bats` and verify all tests pass
- [ ] **Error handling**: Use `error()` function for all error messages, proper exit codes
- [ ] **Documentation**: Update `usage()` function if adding flags, update `README.md` if behavior changes
- [ ] **Backward compatibility**: Existing flags and behaviors work unchanged (unless intentional breaking change)
- [ ] **Local variables**: All function variables use `local` keyword
- [ ] **Quoting**: All variable expansions are properly quoted
- [ ] **No Go file changes**: Verify no `.go` files were modified (they're reference only)

### How to Run Tests Quickly

**Single test file**:
```bash
bats test/retry.bats
```

**Single test case** (using BATS filter):
```bash
bats -f "prints version" test/retry.bats
```

**With verbose output**:
```bash
bats -t test/retry.bats
```

**ShellCheck only**:
```bash
shellcheck retry.sh
```

**Both lint and test** (CI simulation):
```bash
shellcheck retry.sh && bats test/retry.bats
```

### Security & Compliance Guardrails

**Input validation**:
- Validate all duration strings via `parse_duration()` (rejects invalid formats)
- Validate flag values are non-negative integers where required (e.g., `-attempts`)
- Check for required external commands before use (`command -v curl`, `command -v timeout`)

**Secrets handling**:
- Script does not handle secrets (commands are passed as arguments, user's responsibility)
- No credential storage or transmission

**Safe command execution**:
- Use arrays for command construction to prevent injection: `cmd=(command "$arg")` then `"${cmd[@]}"`
- Never use `eval` with user input
- Quote all variable expansions in command arguments

**Dependency constraints**:
- Script checks for required commands (`curl`, `timeout`) and exits gracefully if missing
- No external package dependencies (uses only standard Unix utilities)

**Example from code**:
```bash
# Safe: Array construction prevents injection
local curl_cmd=(curl --fail --silent --show-error --location "$url")
"${curl_cmd[@]}"  # Safe expansion

# Unsafe: Would allow injection (NOT USED)
# eval "curl $url"  # NEVER DO THIS
```

### Performance/Footprint Budgets

**Avoid N+1 patterns**:
- Calculate sleep duration once per iteration (line 336), not multiple times
- Cache parsed durations (parse once, reuse)

**Avoid synchronous I/O in hot paths**:
- `error()` calls are acceptable (only on errors, not in success path)
- Avoid file I/O in retry loop (except for `-log` feature if implemented)

**Minimize subprocess calls**:
- Use bash built-ins (`[[ ]]`, `$(( ))`) instead of external commands where possible
- Prefer `awk` for floating-point math (single subprocess) over multiple `bc` calls

**Memory footprint**:
- Use local variables, avoid global state
- Arrays are small (command arguments), acceptable

**Detection commands**:
```bash
# Count subprocess calls in retry loop (should be minimal)
grep -n '$(.*)' retry.sh | grep -A5 -B5 "while true"

# Check for eval usage (should be zero)
grep -n 'eval' retry.sh
```

### API/Schema Change Impact Checklist

When changing flags or behavior:

- [ ] **Update `usage()` function**: Add new flags to help text (`retry.sh` lines 6-32)
- [ ] **Update flag parsing**: Add cases to switch statement (`retry.sh` lines 122-212)
- [ ] **Update validation**: Add validation logic after parsing (around line 232)
- [ ] **Update `README.md`**: Add usage examples for new flags
- [ ] **Add test cases**: Create `@test` cases in `test/retry.bats`
- [ ] **Maintain backward compatibility**: Existing flags work unchanged
- [ ] **Update feature plans**: If implementing planned feature, update `.cursor/plans/` files

**Breaking changes** (avoid if possible):
- If breaking change is necessary, document in commit message and `README.md`
- Consider deprecation period for flag changes
- Update version in script if versioning is added

### Observability Standards

**Error messages**:
- Use `error()` function for consistency: `error "descriptive message"`
- Include context: `error "maximum attempts exceeded"` not just `error "failed"`
- Exit with appropriate codes: 1 = retry failure, 2 = system error

**Logging** (if `-log` feature implemented):
- Log attempt numbers and timestamps
- Log command being executed
- Log sleep durations and backoff multipliers

**Example error pattern**:
```bash
error "maximum attempts exceeded"  # Clear, actionable
exit 1  # Consistent exit code
```

### Required Artifacts

**For new flags**:
- Flag parsing code in `retry.sh`
- Help text in `usage()` function
- Test cases in `test/retry.bats`
- Documentation in `README.md`

**For new features**:
- Implementation in `retry.sh`
- Test coverage in `test/retry.bats`
- Usage examples in `README.md`
- Feature plan in `.cursor/plans/` (if planned feature)

**Code comments**:
- Function-level comments for all new functions (see `parse_duration()` line 38-39)
- Inline comments for complex logic (see duration parsing regex line 47, 52)
- No comments needed for obvious code (e.g., `local var=$1`)

## Go Code Reference Guidelines

**When to reference Go code**:
- Understanding original behavior for feature parity
- Debugging edge cases not obvious from bash implementation
- Verifying expected behavior for complex features

**How to reference Go code**:
- Read `retry/retry.go` for core retry logic
- Read `retry/task.go` for task abstraction patterns
- Read `main.go` for CLI flag handling patterns
- **DO NOT** copy Go patterns directly - adapt to bash idioms

**Key differences**:
- Go uses context cancellation for timeouts; bash uses `timeout` command
- Go uses channels/goroutines; bash is single-threaded
- Go has structured error types; bash uses exit codes
- Go uses time.Duration; bash uses float seconds

## Quick Reference

**Most common tasks**:
- Add flag: `retry.sh` lines 122-212 (parsing), 6-32 (usage), `test/retry.bats` (tests)
- Fix bug: Identify location via error message or test failure, fix in `retry.sh`, verify with `bats test/retry.bats`
- Add utility: `retry.sh` lines 38-107 (utility section), add tests in `test/retry.bats`

**Essential commands**:
```bash
# Lint
shellcheck retry.sh

# Test
bats test/retry.bats

# Both
shellcheck retry.sh && bats test/retry.bats
```

**File locations**:
- Main script: `retry.sh`
- Tests: `test/retry.bats`
- CI config: `.github/workflows/bash.yaml`
- Plans: `.cursor/plans/*.plan.md`

