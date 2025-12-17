---
name: Feature Implementation Order Meta-Plan
overview: Define optimal implementation order for 6 new retry features to minimize friction, dependencies, and redundant effort.
todos:
  - id: phase1-max-sleep
    content: Implement Max Sleep Cap feature (-max-sleep flag)
    status: pending
  - id: phase1-fibonacci
    content: Implement Fibonacci Backoff feature (-backoff=fibonacci)
    status: pending
    dependencies:
      - phase1-max-sleep
  - id: phase2-error-codes
    content: Implement Error Code Filtering feature (-retry-on-codes)
    status: pending
  - id: phase2-log-aggregation
    content: Implement Log Aggregation feature (-log)
    status: pending
    dependencies:
      - phase2-error-codes
  - id: phase3-diagnostics
    content: Implement Progressive Diagnostics feature (-diagnostics)
    status: pending
    dependencies:
      - phase2-log-aggregation
  - id: phase3-precondition
    content: Implement Precondition Check feature (-precondition)
    status: pending
    dependencies:
      - phase2-error-codes
      - phase2-log-aggregation
      - phase3-diagnostics
---

# Feature Implementation Order Meta-Plan

This plan defines the optimal order for implementing the 6 new retry features to minimize dependencies, conflicts, and redundant work.

## Implementation Order

### Phase 1: Core Backoff Enhancements (Isolated Changes)

#### 1. Max Sleep Cap (`-max-sleep`)

**Complexity**: Low

**Dependencies**: None

**Rationale**:

- Simplest feature, isolated change to sleep calculation
- No dependencies on other features
- Low risk, good warm-up task
- Modifies single calculation point (line 336)

**Implementation Scope**:

- Add flag parsing
- Add duration parsing
- Modify sleep calculation with cap logic
- Add validation

---

#### 2. Fibonacci Backoff (`-backoff=fibonacci`)

**Complexity**: Low-Medium

**Dependencies**: None (but interacts with Max Sleep Cap)

**Rationale**:

- Modifies existing backoff logic (line 345)
- Isolated from other features
- Should be done before features that might interact with backoff
- Can test with Max Sleep Cap immediately after

**Implementation Scope**:

- Change backoff from boolean to string
- Add Fibonacci sequence tracking
- Modify backoff calculation
- Maintain backward compatibility

---

### Phase 2: Core Retry Logic (Status & Output)

#### 3. Error Code Filtering (`-retry-on-codes`)

**Complexity**: Medium

**Dependencies**: None

**Rationale**:

- Core retry logic change (status checking)
- Should be done before Precondition Check (which also checks status)
- Isolated change to status evaluation (lines 308-313)
- Foundation for fail-fast behavior

**Implementation Scope**:

- Add flag parsing
- Add status code validation
- Modify status checking logic
- Add fail-fast exit logic

---

#### 4. Log Aggregation (`-log`)

**Complexity**: Medium

**Dependencies**: None

**Rationale**:

- Output infrastructure feature
- Should be done before features that output (Diagnostics, Precondition)
- Multiple integration points but isolated functionality
- Enables better debugging for later features

**Implementation Scope**:

- Add flag parsing
- Add log file initialization
- Modify command execution (4 locations)
- Modify HTTP task execution
- Handle quiet mode integration

---

### Phase 3: Advanced Features (Build on Foundation)

#### 5. Progressive Diagnostics (`-diagnostics`)

**Complexity**: Medium

**Dependencies**: Log Aggregation (optional but beneficial)

**Rationale**:

- Uses Log Aggregation for output (if implemented)
- Additive feature, doesn't modify core logic
- Simpler than Precondition Check
- Can leverage Error Code Filtering for better error context

**Implementation Scope**:

- Add flag parsing
- Create diagnostics function
- Integrate into retry loop
- Handle log file integration

---

#### 6. Precondition Check (`-precondition`)

**Complexity**: High

**Dependencies**: Error Code Filtering, Log Aggregation

**Rationale**:

- Most complex feature, changes retry loop structure
- Benefits from Error Code Filtering (precondition status checking)
- Benefits from Log Aggregation (precondition output logging)
- Should be last to avoid conflicts with other features

**Implementation Scope**:

- Add flag parsing
- Create precondition execution function
- Modify retry loop structure significantly
- Integrate with error code filtering
- Integrate with log aggregation
- Handle attempt counting

---

## Dependency Graph

```
Max Sleep Cap (no deps)
    ↓
Fibonacci Backoff (no deps, but interacts with Max Sleep Cap)
    ↓
Error Code Filtering (no deps)
    ↓                    ↓
Log Aggregation ────────┐
    ↓                    │
Progressive Diagnostics │
    ↓                    │
Precondition Check ──────┘
```

## Implementation Strategy

### Batch 1: Backoff Features

- **Max Sleep Cap** → **Fibonacci Backoff**
- Rationale: Related functionality, can test together
- Risk: Low
- Testing: Can test backoff strategies together

### Batch 2: Core Infrastructure

- **Error Code Filtering** → **Log Aggregation**
- Rationale: Foundation for advanced features
- Risk: Medium
- Testing: Test status checking and output capture independently

### Batch 3: Advanced Features

- **Progressive Diagnostics** → **Precondition Check**
- Rationale: Build on foundation, most complex last
- Risk: Medium-High
- Testing: Can leverage previous features in testing

## Testing Strategy Per Phase

### Phase 1 Testing

- Test Max Sleep Cap with exponential backoff
- Test Fibonacci Backoff independently
- Test Max Sleep Cap + Fibonacci Backoff together
- Verify backward compatibility

### Phase 2 Testing

- Test Error Code Filtering with various exit codes
- Test Log Aggregation independently
- Test Error Code Filtering + Log Aggregation together
- Verify fail-fast behavior with logging

### Phase 3 Testing

- Test Progressive Diagnostics independently
- Test Precondition Check independently
- Test Progressive Diagnostics + Log Aggregation
- Test Precondition Check + Error Code Filtering + Log Aggregation
- Full integration testing with all features

## Risk Mitigation

### High-Risk Areas

1. **Precondition Check**: Changes retry loop structure

   - Mitigation: Implement last, test thoroughly with all previous features

2. **Log Aggregation**: Multiple integration points

   - Mitigation: Implement early, test each integration point separately

3. **Error Code Filtering**: Core logic change

   - Mitigation: Implement before complex features, extensive testing

### Conflict Prevention

- Max Sleep Cap and Fibonacci Backoff: Both modify sleep/backoff, but Max Sleep Cap applies after calculation
- Error Code Filtering and Precondition Check: Both check status, but Error Code Filtering happens first
- Log Aggregation and other features: All features benefit from logging, implement early

## Rollback Strategy

Each feature should be:

- Implemented in separate commits
- Fully tested before moving to next feature
- Documented with usage examples
- Backward compatible (can be disabled via flag absence)

If a feature causes issues:

- Can disable via flag (backward compatible)
- Can revert commit without affecting other features
- Each feature is independent enough for isolated rollback

## Success Criteria

Each phase should:

- ✅ All tests pass
- ✅ Backward compatibility maintained
- ✅ Documentation updated
- ✅ No regressions in existing functionality
- ✅ Feature works independently
- ✅ Feature integrates with previous features (where applicable)

## Notes

- Features can be implemented in parallel by different developers if needed (Phase 1 features are independent)
- Each feature should have its own test suite
- Consider feature flags if implementing incrementally in production
- Update README.md with examples for each feature as implemented