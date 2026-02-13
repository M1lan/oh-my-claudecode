<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# verification

## Purpose
Verification tier selection — maps task size and complexity metadata to an appropriate verification model tier. Used by execution modes (ralph, autopilot, ultrapilot) to scale verification effort proportionally: small changes use `haiku` for cost efficiency, large or security-sensitive changes escalate to `opus` for thoroughness.

## Key Files
| File | Description |
|------|-------------|
| `tier-selector.ts` | `selectVerificationTier()` — takes `ChangeMetadata` and returns a `VerificationAgent` with model and required evidence list |
| `tier-selector.test.ts` | Unit tests for tier selection logic covering all boundary conditions |

## For AI Agents

### Working In This Directory
- `ChangeMetadata` is the input shape: `filesChanged`, `linesChanged`, `hasArchitecturalChanges`, `hasSecurityImplications`, `testCoverage`.
- Three tiers: `LIGHT` (haiku, diagnostics only), `STANDARD` (sonnet, diagnostics + build), `THOROUGH` (opus, full architect review + all tests).
- Security implications or architectural changes always escalate to `THOROUGH` regardless of size.
- The `evidenceRequired` array in the returned `VerificationAgent` tells the caller what proof to collect before claiming verification passed.
- This module has no side effects — it is a pure function mapping inputs to outputs.

### Common Patterns
- Call pattern: `const agent = selectVerificationTier(metadata)` then spawn verifier with `agent.model`.
- Thresholds for LIGHT/STANDARD/THOROUGH are defined as constants inside `tier-selector.ts` — adjust there if calibration is needed.

## Dependencies

### Internal
None — pure logic module with no internal imports.

### External
None — no external dependencies.

<!-- MANUAL: -->
