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
  source_system VARCHAR(32) NOT NULL DEFAULT 'INTERNAL',
  cusip VARCHAR(16),
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
CREATE INDEX idx_collateral_pon_source ON collateral_positions (pon, source_system);
CREATE INDEX idx_collateral_cusip ON collateral_positions (cusip);

CREATE TABLE treasurydirect_marks (
  mark_id BIGSERIAL PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  collateral_id VARCHAR(64) NOT NULL REFERENCES collateral_positions(collateral_id),
  cusip VARCHAR(16) NOT NULL,
  as_of TIMESTAMPTZ NOT NULL,
  clean_price NUMERIC(20,10) NOT NULL,
  accrued_interest NUMERIC(20,10) NOT NULL DEFAULT 0,
  quality_status VARCHAR(16) NOT NULL,
  source_message_id VARCHAR(128) NOT NULL,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (pon, collateral_id, as_of, source_message_id)
);

CREATE INDEX idx_treasurydirect_marks_pon_asof ON treasurydirect_marks (pon, as_of DESC);
CREATE INDEX idx_treasurydirect_marks_cusip_asof ON treasurydirect_marks (cusip, as_of DESC);

CREATE TABLE baas_accounts (
  account_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  provider VARCHAR(64) NOT NULL,
  provider_account_ref VARCHAR(128) NOT NULL,
  account_type VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  currency_code CHAR(3) NOT NULL,
  velocity_limit_daily NUMERIC(30,10),
  velocity_limit_monthly NUMERIC(30,10),
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (pon, provider, provider_account_ref)
);

CREATE INDEX idx_baas_accounts_pon_status ON baas_accounts (pon, status);

CREATE TABLE baas_rail_health (
  health_id BIGSERIAL PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  provider VARCHAR(64) NOT NULL,
  rail VARCHAR(32) NOT NULL,
  health_status VARCHAR(16) NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (pon, provider, rail, observed_at)
);

CREATE INDEX idx_baas_rail_health_pon_observed ON baas_rail_health (pon, observed_at DESC);

CREATE TABLE baas_transfers (
  transfer_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  settlement_id VARCHAR(64),
  account_id VARCHAR(64) NOT NULL REFERENCES baas_accounts(account_id),
  provider VARCHAR(64) NOT NULL,
  rail VARCHAR(32) NOT NULL,
  direction VARCHAR(16) NOT NULL,
  amount NUMERIC(30,10) NOT NULL,
  currency_code CHAR(3) NOT NULL,
  status VARCHAR(32) NOT NULL,
  provider_reference VARCHAR(128),
  initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reconciled_at TIMESTAMPTZ
);

CREATE INDEX idx_baas_transfers_pon_status ON baas_transfers (pon, status);
CREATE INDEX idx_baas_transfers_settlement ON baas_transfers (settlement_id);

CREATE TABLE token_valuations (
  valuation_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  as_of TIMESTAMPTZ NOT NULL,
  collateral_effective_value NUMERIC(30,10) NOT NULL,
  fx_buffer NUMERIC(10,6) NOT NULL,
  risk_buffer NUMERIC(10,6) NOT NULL,
  valuation_basis NUMERIC(30,10) NOT NULL,
  token_price NUMERIC(30,10) NOT NULL,
  valuation_window VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (pon, as_of, valuation_window)
);

CREATE INDEX idx_token_valuations_pon_asof ON token_valuations (pon, as_of DESC);

CREATE TABLE token_mints (
  mint_id VARCHAR(64) PRIMARY KEY,
  pon VARCHAR(64) NOT NULL REFERENCES pon_programs(pon),
  valuation_id VARCHAR(64) NOT NULL REFERENCES token_valuations(valuation_id),
  minted_quantity NUMERIC(30,10) NOT NULL,
  circulating_allocated NUMERIC(30,10) NOT NULL,
  reserve_allocated NUMERIC(30,10) NOT NULL,
  status VARCHAR(32) NOT NULL,
  reason_code VARCHAR(64),
  policy_version INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (circulating_allocated >= 0),
  CHECK (reserve_allocated >= 0),
  CHECK (minted_quantity = circulating_allocated + reserve_allocated)
);

CREATE INDEX idx_token_mints_pon_created ON token_mints (pon, created_at DESC);

CREATE TABLE circulation_positions (
  pon VARCHAR(64) PRIMARY KEY REFERENCES pon_programs(pon),
  circulation_cap NUMERIC(30,10) NOT NULL,
  circulating_total NUMERIC(30,10) NOT NULL,
  reserve_total NUMERIC(30,10) NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (circulating_total >= 0),
  CHECK (reserve_total >= 0),
  CHECK (circulating_total <= circulation_cap)
);

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
