-- Core relational schema for PON-scoped SECC tracking.

CREATE TABLE pon_programs (
  pon VARCHAR(64) PRIMARY KEY,
  policy_version INTEGER NOT NULL,
  status VARCHAR(16) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE entitlements (
  entitlement_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  user_id VARCHAR(64) NOT NULL,
  asset_class VARCHAR(64) NOT NULL,
  quantity NUMERIC(30,10) NOT NULL,
  status VARCHAR(16) NOT NULL,
  compliance_state VARCHAR(16) NOT NULL,
  version BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entitlements_pon_user ON entitlements (pon, user_id);
CREATE INDEX idx_entitlements_pon_status ON entitlements (pon, status);

CREATE TABLE collateral_positions (
  collateral_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  collateral_type VARCHAR(64) NOT NULL,
  market_value NUMERIC(30,10) NOT NULL,
  liquidity_score NUMERIC(10,6) NOT NULL,
  haircut NUMERIC(10,6) NOT NULL,
  effective_value NUMERIC(30,10) NOT NULL,
  version BIGINT NOT NULL DEFAULT 1,
  valuation_time TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_collateral_pon ON collateral_positions (pon);

CREATE TABLE settlements (
  settlement_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  event_type VARCHAR(32) NOT NULL,
  amount NUMERIC(30,10) NOT NULL,
  state VARCHAR(32) NOT NULL,
  reason_code VARCHAR(64),
  request_id VARCHAR(128) NOT NULL,
  idempotency_key VARCHAR(128) NOT NULL,
  version BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (pon, idempotency_key)
);

CREATE INDEX idx_settlements_pon_state ON settlements (pon, state);

CREATE TABLE decision_events (
  event_id BIGSERIAL PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  request_id VARCHAR(128) NOT NULL,
  settlement_id VARCHAR(64),
  policy_version INTEGER NOT NULL,
  rule_ids TEXT[] NOT NULL,
  decision VARCHAR(32) NOT NULL,
  reason_code VARCHAR(64),
  payload_hash VARCHAR(128) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_decision_events_pon_created ON decision_events (pon, created_at DESC);
