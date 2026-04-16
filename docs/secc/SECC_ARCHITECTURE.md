# SECC (SnapAiFi Entitlement & Collateral Control Engine)

This document translates the SECC concept into an implementation-ready architecture for an institutional-grade internal rules engine.

## 1) Scope and boundary

SECC is an internal deterministic policy engine. It evaluates program state and emits decisions. It **does not** custody assets, provide legal enforcement, or act as an external regulator.

Within each PON namespace, SECC governs:

- entitlement validity
- collateral sufficiency
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
- **Settlement Orchestrator**: finite state machine for settlement execution.
- **Ledger Writer**: commits immutable state transitions and event hashes.

## 3) Event bus topology

Suggested topics (partitioned by `pon`):

- `pon.{id}.request.received`
- `pon.{id}.entitlement.evaluated`
- `pon.{id}.collateral.evaluated`
- `pon.{id}.risk.scored`
- `pon.{id}.decision.emitted`
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

## 5) Deterministic rule pipeline

```text
1. Validate entitlement
2. Validate compliance flags
3. Compute collateral effective value
4. Compute risk-adjusted capacity
5. Compare required exposure
6. Emit allow/deny/hold decision
7. Advance settlement state machine
8. Persist ledger transition
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

## 6) Settlement finite state machine

```text
INITIATED -> VALIDATED -> COLLATERAL_CONFIRMED -> QUEUED_FOR_CLEARING -> SETTLED -> FINALIZED
```

Failure states:

- `REJECTED`
- `COLLATERAL_INSUFFICIENT`
- `ON_HOLD`
- `REVERSED`

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
- `GET /pons/{pon}/settlements/{id}` -> settlement state and history
- `POST /pons/{pon}/replay` -> deterministic replay verification job

## 10) Implementation notes

- Use decimal math (never float) for financial amounts.
- Keep rule execution pure (no side effects) and emit action intents.
- Execute side effects in orchestrators using idempotent command handlers.
- Persist append-only events before mutable read-model updates.
- Version all policy changes and require dual control approval.
