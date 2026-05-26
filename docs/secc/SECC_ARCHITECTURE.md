# SECC (SnapAiFi Entitlement & Collateral Control Engine)

This document translates the SECC concept into an implementation-ready architecture for an institutional-grade internal rules engine.

## 1) Scope and boundary

SECC is an internal deterministic policy engine. It evaluates program state and emits decisions. It **does not** custody assets, provide legal enforcement, or act as an external regulator.

Within each PON namespace, SECC governs:

- entitlement validity
- collateral sufficiency
- TreasuryDirect-backed collateral eligibility and valuation ingest
- US Treasury auction security eligibility list management for Auto Charge Agreements
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
- **US Treasury Auction List Service**: maintains the eligible auction-security list used by Auto Charge Agreement logic.
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
- `pon.{id}.treasury_auction.security_list.updated`
- `pon.{id}.auto_charge.agreement.evaluated`
- `pon.{id}.auto_charge.executed`
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

### Auto Charge Agreement

```json
{
  "agreement_id": "ACA-301",
  "pon": "PON-1984",
  "user_id": "U123",
  "status": "ACTIVE",
  "charge_target_amount": "50000.00",
  "currency_code": "USD",
  "eligible_security_list_version": 12,
  "rebalance_frequency": "DAILY"
}
```

### US Treasury auction security (eligible list entry)

```json
{
  "security_id": "UST-AUC-20260415-01",
  "cusip": "91282CLH2",
  "security_type": "NOTE",
  "tenor": "2Y",
  "auction_date": "2026-04-15",
  "issue_date": "2026-04-30",
  "maturity_date": "2028-04-30",
  "eligible_for_auto_charge": true,
  "list_version": 12
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
4. Validate US Treasury auction security eligibility list for Auto Charge Agreements
5. Validate BaaS account and rail readiness (if cash settlement requested)
6. Validate Merrill custody account/position and sweep readiness (if brokerage leg requested)
7. Compute collateral effective value
8. Compute valuation basis and token unit value
9. Evaluate tokenization policy and mint eligibility
10. Compute risk-adjusted capacity
11. Compare required exposure + circulation constraints
12. Emit allow/deny/hold decision
13. Advance settlement state machine
14. Persist ledger transition
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
- **R2b US Treasury auction list + Auto Charge Agreement**
  - Auto Charge Agreements may allocate only securities from the active eligible auction list version
  - require `eligible_for_auto_charge = true` on selected security
  - reject if auction security is not active for the agreement evaluation window
  - emit `AUTO_CHARGE_SECURITY_INELIGIBLE` on failure
- **R2c FS Form 5441-3E precedence + DI chargeability**
  - when delivery instructions in a tender conflict with instructions in the Auto Charge Agreement, agreement instructions supersede
  - require a valid designated depository institution (DI) with a Federal Reserve funds account
  - require Treasury/BFS acknowledgement state `ACKNOWLEDGED` before agreement is active
  - emit `AUTO_CHARGE_AGREEMENT_INACTIVE` if not acknowledged/effective
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
- `AUTO_CHARGE_SECURITY_INELIGIBLE`
- `AUTO_CHARGE_AGREEMENT_BLOCKED`
- `AUTO_CHARGE_AGREEMENT_INACTIVE`
- `AUTO_CHARGE_TERMINATION_WINDOW_VIOLATION`
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
- auction-list version publish latency
- Auto Charge Agreement execution success rate
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
- `POST /pons/{pon}/treasury-auctions/security-list/publish` -> publish eligible US Treasury auction securities list
- `GET /pons/{pon}/treasury-auctions/security-list` -> retrieve active eligible list for Auto Charge Agreements
- `POST /pons/{pon}/auto-charge/agreements` -> create/update Auto Charge Agreement
- `POST /pons/{pon}/auto-charge/execute` -> evaluate and execute Auto Charge cycle
- `POST /pons/{pon}/auto-charge/termination-notices` -> submit DI/submitter termination notice and validate timing window
- `GET /pons/{pon}/auto-charge/agreements/{id}/effective-status` -> agreement effective/acknowledgement status
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

## 10) Treasury docs and links (source references)

- TreasuryDirect FS Form 5441-3E PDF (Auto-Charge Agreement): `https://www.treasurydirect.gov/forms/FS5441-3E.pdf`
- TreasuryDirect Federal Investments Program forms (includes redemption/new customer access forms): `https://www.treasurydirect.gov/government/federal-investments-program/new-customer-and-access-forms/`

Operational notes reflected in SECC rules:

- Auto-Charge Agreement delivery instructions supersede conflicting tender instructions.
- DI funds account is charged for marketable Treasury securities delivered under agreement.
- Agreement effectiveness requires acknowledgement by authorized Bureau of the Fiscal Service or FRBNY official.
- Termination requires written notice and timing-window compliance tied to issue-date cutoffs.

## 11) Implementation notes

- Use decimal math (never float) for financial amounts.
- Keep rule execution pure (no side effects) and emit action intents.
- Execute side effects in orchestrators using idempotent command handlers.
- Persist append-only events before mutable read-model updates.
- Version all policy changes and require dual control approval.

## 12) Launch plan (SECC production rollout)

### Phase 0 — pre-launch readiness

- freeze `policy_version` candidate and run deterministic replay backtests against historical sample flows
- validate Treasury/BaaS/Merrill adapter connectivity and fallback behavior
- run schema migration dry-run and rollback rehearsal for all new SECC tables
- confirm on-call ownership, escalation paths, and runbook publication

### Phase 1 — shadow launch

- mirror production requests into SECC in read-only shadow mode
- compare shadow decisions against incumbent decision path and measure divergence
- require divergence rate under threshold for a sustained observation window before promotion

### Phase 2 — controlled launch

- enable SECC decision authority for a bounded canary cohort (`pon` allowlist)
- enforce hard limits for:
  - max single settlement amount
  - max daily mint allocation
  - max auto-charge execution count per window
- auto-failover to safe hold-state on critical dependency outage

### Phase 3 — full launch

- incrementally expand from canary PONs to full coverage
- keep heightened monitoring until error budget and replay divergence remain within SLO
- complete post-launch review with policy/risk/compliance sign-off

### Launch gates (must pass)

- **Gate A**: deterministic replay parity passed
- **Gate B**: dependency health checks green (TreasuryDirect, BaaS, Merrill adapters)
- **Gate C**: runbook + incident simulation complete
- **Gate D**: audit logging completeness validated for all critical decisions

### Day-1 launch dashboard

- settlement success rate
- replay divergence count/rate
- auto-charge success rate and termination-window violations
- collateral shortfall events
- BaaS and Merrill reconciliation lag

## 13) Continue plan (post-launch execution backlog)

### 0-30 days

- implement policy simulation harness for nightly replay of prior-day production traffic
- add automated drift alerts when decision distribution changes beyond configured threshold
- finalize SLOs and error budgets per critical SECC workflow (settlement, auto-charge, minting)

### 31-60 days

- introduce policy-change approval workflow with dual control and immutable approver attestations
- add per-rule latency/impact telemetry to identify hot rules and frequent failure paths
- implement automated rollback to prior `policy_version` with safety guards

### 61-90 days

- add active-active disaster recovery rehearsal for ledger/event replay
- complete independent model/rule audit and remediation of findings
- publish quarterly controls report for risk/compliance stakeholders

### Exit criteria

- replay divergence sustained below target threshold for 30 consecutive days
- zero unresolved high-severity audit findings related to SECC controls
- all launch gates remain green after at least one full quarterly cycle

## 14) Codex → SECC integration boundary (formal execution bridge)

### Structural role

Define Codex integration as an externalized execution morphism:

- `K : C_SECC^[i] -> C_SECC^[i]` on the presentation/execution layer
- `K` is **not** a member of the internal ω-continuous SECC core endofunctor
- `S_hat : (S, E, V) -> (S, E, V)` remains the internal deterministic fixed-point generator

Operational interpretation:

1. SECC defines semantic truth (`lfp(S_hat)`).
2. Codex constructs candidate artifacts.
3. SECC admits artifacts only through a verification gate.

### Role separation

- **SECC core (`S_hat`)**
  - deterministic
  - ω-continuous
  - closed/fixed-point
  - proof-carrying
- **Codex executor (`K`)**
  - internally non-deterministic
  - tool-using/sandboxed
  - side-effect capable (repos, CI, APIs, filesystem) outside semantic core

### Construction oracle contract

Codex is a construction oracle, not a semantics authority:

- `K(P) = candidate_artifact`

Candidate artifacts may include:

- SECC-ISA program drafts
- patch sets
- proof skeletons
- invariant suggestions

No candidate artifact is admissible directly into SECC core.

### Verification gate

Introduce an admission gate:

- `V_gate(K(x)) => admissible`
- `not V_gate(K(x)) => reject_or_rerun`

The gate must validate:

- structural well-formedness
- rule compatibility with active `policy_version`
- invariant preservation
- proof obligations and audit trace completeness

### Unified composition

The integrated system is represented as:

- `SECC_plus_Codex = lfp(S_hat) o V_gate o K`

Execution flow:

1. Codex proposes.
2. Gate verifies.
3. SECC absorbs validated structures into the fixed-point domain.

### Categorical classification

- SECC: terminal semantic object (closed fixed-point category)
- `S_hat`: internal fixpoint generator
- `K` (Codex): external morphism generator
- `V_gate`: reflection/admission functor into SECC core

### Non-leakage invariant (mandatory)

Codex non-leakage axiom:

- `K(x) notin SECC_core` unless `V_gate(K(x)) = true`

Implication:

- Codex cannot mutate the fixed point directly.
- Codex can only propose candidates for gated inclusion.

### Three-layer reduction

1. **SECC truth layer**: deterministic, proof-carrying, ω-fixed point
2. **Codex construction layer**: agentic, stochastic, tool-using executor
3. **Verification layer (`V_gate`)**: type/proof validator and semantic stabilizer

### Optional next refinement

Define `V_gate` as a dependent type system so Codex outputs are admitted as typed inhabitants of SECC programs rather than untyped external artifacts.
