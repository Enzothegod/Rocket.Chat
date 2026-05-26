# Treasury Docs and Links for SECC Auto-Charge Workflows

This reference maps Treasury source documentation and provided submission metadata into implementation inputs for SECC.

## 1) Primary source links

- FS Form 5441-3E (Auto-Charge Agreement):
  - https://www.treasurydirect.gov/forms/FS5441-3E.pdf
- TreasuryDirect Federal Investments Program forms (new customer/access + redemption-related resources):
  - https://www.treasurydirect.gov/government/federal-investments-program/new-customer-and-access-forms/

## 2) Provided applicant profile (implementation snapshot)

- Applicant legal name: `SNAPPCREDITCOM`
- Entity type: `509(a)(2) Nonprofit Organization`
- Jurisdiction: `United States`
- Authorized representative: `Jon'Lorenzo Caprelli`, `President`
- Designated depository institution: `U.S. Bank National Association`
- DI ABA routing number: `09100022`
- Treasury interface instrument: `Treasury Autocharge Agreement (FS Form 5441-3E)`

## 3) Operational clauses to encode in SECC

The following points should be modeled in rule/validation paths for Auto-Charge workflows:

1. **Instruction precedence**
   - If tender delivery instructions conflict with Auto-Charge Agreement instructions, agreement instructions supersede.
2. **DI chargeability**
   - The DI funds account at the Federal Reserve is charged for marketable Treasury securities delivered under the agreement.
3. **Agreement effectiveness**
   - Agreement is effective only after acknowledgement by an authorized Bureau of the Fiscal Service or FRBNY official.
4. **Submitter responsibility**
   - Submitter remains responsible for full payment of securities awarded, including cases where DI payment is not received in full.
5. **Termination process constraints**
   - Written notice is required.
   - Timing windows apply for DI termination actions around issue date cutoffs.
   - Submitter termination after auction and before delivery requires replacement agreement mechanics per form terms.

## 4) Data fields recommended for persistence

- `form_code` (e.g., `FS5441-3E`)
- `cfr_authority` (e.g., `31 CFR Part 356`)
- `acknowledgement_status`
- `acknowledged_by`
- `acknowledged_at`
- `effective_at`
- `di_name`
- `di_aba_routing`
- `termination_notice_by` (`DI` or `SUBMITTER`)
- `termination_notice_received_at`
- `termination_notice_acknowledged_at`
- `termination_effective_at`

## 5) Compliance note

This file is an engineering reference and is not legal advice.
Policy/legal teams should validate production wording and operational cutoffs against the latest Treasury form language and governing regulations.
