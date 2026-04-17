# SECC (SnapAiFi Entitlement & Collateral Control Engine)

This document translates the SECC concept into an implementation-ready architecture for an institutional-grade internal rules engine.

## 1) Scope and boundary

SECC is an internal deterministic policy engine. It evaluates program state and emits decisions. It **does not** custody assets, provide legal enforcement, or act as an external regulator.

Within each PON namespace, SECC governs:

- entitlement validity
- collateral sufficiency
- token valuation and tokenization limits
- mint authorization and circulation allocation
- settlement transitions
- risk-triggered controls

## 2) Microservices layout

```text
[API Gateway]
   -> [Request Intake Service]
   -> [Entitlement Service]
   -> [Collateral Service]
   -> [Risk Scoring Service]
   -> [SECC Decision Service]
   -> [Settlement Orchestrator]
   -> [Ledger Writer]

Cross-cutting:
- Compliance Service
- Audit Service
- Event Bus (append-only topics)
- Policy Registry (versioned rulesets per PON)
```

### Service responsibilities

- **Request Intake Service**: validates request schema and assigns idempotency key.
- **Entitlement Service**: reads/writes entitlement objects and lock states.
- **Collateral Service**: computes adjusted collateral using haircut/liquidity inputs.
- **Risk Scoring Service**: computes SNAP factor and dynamic thresholds.
- **SECC Decision Service**: deterministic rule evaluation and action emission.
- **Tokenization Service**: computes mint quantity from valuation policy and applies circulation caps.
- **Settlement Orchestrator**: finite state machine for settlement execution.
- **Ledger Writer**: commits immutable state transitions and event hashes.

## 3) Event bus topology

Suggested topics (partitioned by `pon`):

- `pon.{id}.request.received`
- `pon.{id}.entitlement.evaluated`
- `pon.{id}.collateral.evaluated`
- `pon.{id}.risk.scored`
- `pon.{id}.decision.emitted`
- `pon.{id}.token.valuation.computed`
- `pon.{id}.token.mint.authorized`
- `pon.{id}.token.circulation.allocated`
- `pon.{id}.settlement.transitioned`
- `pon.{id}.ledger.committed`
- `pon.{id}.alert.raised`

### Contract guarantees

- at-least-once delivery + idempotent consumers
- monotonic event version per `pon`
- deterministic replay from ledger + event log

## 4) Canonical state models

### Entitlement

```json
{
  "entitlement_id": "E-001",
  "user_id": "U123",
  "pon": "PON-1984",
  "asset_class": "NAV_TOKEN",
  "quantity": "1000.0000",
  "status": "ACTIVE",
  "compliance_state": "PASS",
  "version": 17
}
```

### Collateral

```json
{
  "collateral_id": "C-778",
  "pon": "PON-1984",
  "collateral_type": "TREASURY_BOND",
  "market_value": "500000.00",
  "liquidity_score": "0.92",
  "haircut": "0.05",
  "effective_value": "475000.00",
  "version": 41
}
```

### Settlement

```json
{
  "settlement_id": "S-9001",
  "pon": "PON-1984",
  "event_type": "REDEMPTION",
  "amount": "10000.00",
  "state": "QUEUED_FOR_CLEARING",
  "reason_code": null,
  "version": 9
}
```

### Token valuation

```json
{
  "pon": "PON-1984",
  "valuation_id": "TV-2201",
  "as_of": "2026-04-16T00:00:00Z",
  "collateral_effective_value": "475000.00",
  "fx_buffer": "0.99",
  "risk_buffer": "0.97",
  "valuation_basis": "460332.50",
  "token_price": "1.00"
}
```

### Token mint allocation

```json
{
  "mint_id": "M-712",
  "pon": "PON-1984",
  "valuation_id": "TV-2201",
  "minted_quantity": "120000.00",
  "circulating_allocated": "100000.00",
  "reserve_allocated": "20000.00",
  "status": "AUTHORIZED",
  "version": 3
}
```

## 5) Deterministic rule pipeline

```text
1. Validate entitlement
2. Validate compliance flags
3. Compute collateral effective value
4. Compute valuation basis and token unit value
5. Evaluate tokenization policy and mint eligibility
6. Compute risk-adjusted capacity
7. Compare required exposure + circulation constraints
8. Emit allow/deny/hold decision
9. Advance settlement state machine
10. Persist ledger transition
```

### Rule definitions

- **R1 Entitlement validity**
  - reject when `entitlement.status != ACTIVE`
  - reject when compliance state is not `PASS`
- **R2 Collateral sufficiency**
  - if `effective_collateral < required_exposure`: emit `COLLATERAL_SHORTFALL`
- **R3 Risk adjusted capacity**
  - `capacity = market_value * liquidity_score * SNAP_factor`
- **R4 Settlement gate**
  - allow settlement only if entitlement valid, collateral sufficient, and compliance pass
- **R5 Token valuation**
  - `valuation_basis = effective_collateral * fx_buffer * risk_buffer`
  - `token_price = valuation_basis / token_supply_reference`
- **R6 Minting authorization**
  - authorize mint only when `valuation_basis` exists for the current valuation window
  - `minted_quantity <= mint_policy.max_mint_per_window`
- **R7 Circulation allocation**
  - `circulating_allocated <= minted_quantity`
  - `circulating_total <= circulation_cap`
  - excess moves to reserve bucket (non-circulating)

## 6) Settlement finite state machine

```text
INITIATED -> VALIDATED -> COLLATERAL_CONFIRMED -> QUEUED_FOR_CLEARING -> SETTLED -> FINALIZED
```

Failure states:

- `REJECTED`
- `COLLATERAL_INSUFFICIENT`
- `ON_HOLD`
- `REVERSED`
- `MINT_BLOCKED`
- `CIRCULATION_CAP_EXCEEDED`

Invariant examples:

- transition to `SETTLED` requires prior `QUEUED_FOR_CLEARING`
- transition to `FINALIZED` requires immutable ledger write success
- any failure state requires `reason_code`

## 7) PON isolation model

Each PON is isolated by namespace and policy version:

```text
PON-1984
 ├── Policy Registry (SECC vN)
 ├── Collateral Pools
 ├── Entitlement Ledger
 ├── Settlement Queue
 └── Audit Stream
```

Rules are evaluated against the active `policy_version` to preserve deterministic replay for historical transactions.

## 8) Observability and controls

Required metrics:

- settlement transition latency p50/p95/p99
- collateral coverage ratio
- token valuation drift ratio
- minted-to-collateral coverage ratio
- circulating supply utilization
- shortfall trigger count
- on-hold queue depth
- replay divergence count

Required audit fields on every decision:

- `pon`, `policy_version`, `request_id`, `idempotency_key`
- input object hashes
- evaluated rule ids
- output decision and reason code
- timestamp + signer/service identity

## 9) Minimal API surface

- `POST /pons/{pon}/requests` -> submit issuance/redemption/transfer request
- `GET /pons/{pon}/entitlements/{id}` -> entitlement snapshot
- `GET /pons/{pon}/collateral/coverage` -> current coverage/shortfall
- `POST /pons/{pon}/token-valuation` -> compute and persist valuation snapshot
- `POST /pons/{pon}/mint` -> run mint authorization and allocation logic
- `GET /pons/{pon}/circulation` -> circulating vs reserve supply positions
- `GET /pons/{pon}/settlements/{id}` -> settlement state and history
- `POST /pons/{pon}/replay` -> deterministic replay verification job

## 10) Implementation notes

- Use decimal math (never float) for financial amounts.
- Keep rule execution pure (no side effects) and emit action intents.
- Execute side effects in orchestrators using idempotent command handlers.
- Persist append-only events before mutable read-model updates.
- Version all policy changes and require dual control approval.
