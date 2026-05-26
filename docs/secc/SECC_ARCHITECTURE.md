# SECC (SnapAiFi Entitlement & Collateral Control Engine)

This document translates the SECC concept into an implementation-ready architecture for an institutional-grade internal rules engine.

## 1) Scope and boundary

SECC is an internal deterministic policy engine. It evaluates program state and emits decisions. It **does not** custody assets, provide legal enforcement, or act as an external regulator.

Within each PON namespace, SECC governs:

- entitlement validity
- collateral sufficiency
- TreasuryDirect-backed collateral eligibility and valuation ingest
- BaaS rail eligibility and payout account controls
- Merrill custody account eligibility and broker sweep settlement controls
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
- **TreasuryDirect Feed Adapter**: ingests TreasuryDirect security reference/price data for eligible collateral marks.
- **BaaS Integration Adapter**: validates bank-account eligibility, funding limits, and payout rail health.
- **Merrill Custody Adapter**: validates brokerage custody positions and sweep transfer instructions.
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
- `pon.{id}.collateral.treasurydirect.ingested`
- `pon.{id}.collateral.treasurydirect.quality_checked`
- `pon.{id}.baas.account.verified`
- `pon.{id}.baas.rail.health_checked`
- `pon.{id}.baas.transfer.initiated`
- `pon.{id}.baas.transfer.reconciled`
- `pon.{id}.merrill.account.verified`
- `pon.{id}.merrill.position.reconciled`
- `pon.{id}.merrill.sweep.initiated`
- `pon.{id}.merrill.sweep.reconciled`
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
  "collateral_type": "TREASURYDIRECT_TREASURY_BOND",
  "source_system": "TREASURYDIRECT",
  "cusip": "91282CJZ5",
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

### BaaS transfer

```json
{
  "transfer_id": "BT-551",
  "pon": "PON-1984",
  "settlement_id": "S-9001",
  "provider": "BAAS_PROVIDER_X",
  "rail": "ACH",
  "direction": "OUTBOUND",
  "amount": "10000.00",
  "status": "IN_FLIGHT",
  "provider_reference": "TRX-992112"
}
```

### Merrill sweep transfer

```json
{
  "sweep_id": "MS-210",
  "pon": "PON-1984",
  "settlement_id": "S-9001",
  "custody_account_id": "MA-1107",
  "direction": "BROKERAGE_TO_BANK",
  "amount": "250000.00",
  "status": "PENDING_RECONCILIATION",
  "broker_reference": "ML-REF-443981"
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
3. Ingest and quality-check TreasuryDirect valuation marks (if applicable)
4. Validate BaaS account and rail readiness (if cash settlement requested)
5. Validate Merrill custody account/position and sweep readiness (if brokerage leg requested)
6. Compute collateral effective value
7. Compute valuation basis and token unit value
8. Evaluate tokenization policy and mint eligibility
9. Compute risk-adjusted capacity
10. Compare required exposure + circulation constraints
11. Emit allow/deny/hold decision
12. Advance settlement state machine
13. Persist ledger transition
```

### Rule definitions

- **R1 Entitlement validity**
  - reject when `entitlement.status != ACTIVE`
  - reject when compliance state is not `PASS`
- **R2 Collateral sufficiency**
  - if `effective_collateral < required_exposure`: emit `COLLATERAL_SHORTFALL`
- **R2a TreasuryDirect mark validation**
  - for TreasuryDirect-backed collateral, require valid CUSIP and non-stale mark timestamp
  - reject marks older than `treasurydirect.max_mark_age`
  - reject missing feed quality status `PASS`
- **R3 Risk adjusted capacity**
  - `capacity = market_value * liquidity_score * SNAP_factor`
- **R4 Settlement gate**
  - allow settlement only if entitlement valid, collateral sufficient, and compliance pass
- **R4a BaaS settlement gate**
  - if settlement rail is BaaS-backed, require account status `VERIFIED`
  - require rail health `UP` and amount within provider/account limits
  - emit `BAAS_RAIL_UNAVAILABLE` or `BAAS_ACCOUNT_RESTRICTED` on failure
- **R4b Merrill custody/sweep gate**
  - if settlement uses Merrill custody, require custody account status `VERIFIED`
  - require reconciled position quantity/value at or above requested transfer amount
  - require sweep instruction status `READY`
  - emit `MERRILL_POSITION_MISMATCH` or `MERRILL_SWEEP_BLOCKED` on failure
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
- `TREASURYDIRECT_MARK_STALE`
- `TREASURYDIRECT_MARK_INVALID`
- `BAAS_RAIL_UNAVAILABLE`
- `BAAS_ACCOUNT_RESTRICTED`
- `MERRILL_POSITION_MISMATCH`
- `MERRILL_SWEEP_BLOCKED`
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
- TreasuryDirect mark freshness lag
- TreasuryDirect ingest failure rate
- BaaS account verification failure rate
- BaaS transfer reconciliation lag
- Merrill position reconciliation mismatch rate
- Merrill sweep settlement lag
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
- `POST /pons/{pon}/collateral/treasurydirect/ingest` -> ingest and validate TreasuryDirect marks
- `GET /pons/{pon}/collateral/treasurydirect/status` -> source freshness and quality status
- `POST /pons/{pon}/baas/accounts/verify` -> verify payout/funding account eligibility
- `GET /pons/{pon}/baas/rails/health` -> current BaaS rail availability
- `POST /pons/{pon}/baas/transfers` -> initiate BaaS transfer for settlement leg
- `GET /pons/{pon}/baas/transfers/{id}` -> transfer status and reconciliation data
- `POST /pons/{pon}/merrill/accounts/verify` -> verify Merrill custody account eligibility
- `POST /pons/{pon}/merrill/positions/reconcile` -> reconcile Merrill custody positions
- `POST /pons/{pon}/merrill/sweeps` -> initiate Merrill sweep transfer for settlement leg
- `GET /pons/{pon}/merrill/sweeps/{id}` -> sweep status and reconciliation details
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
