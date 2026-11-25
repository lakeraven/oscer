# Registering Verification Data Sources

This guide explains how to add an external verification data source and register it so exclusion, exception and community engagement determinations consult it. For HTTP clients and authentication, see [Adding Third Party Data Integrations](adding-third-party-data-integrations.md); this guide covers the layer above it, which turns an integration's answer into outcomes.

## Step 1: Create a Data Source

A data source inherits from `Verification::DataSource` and lives under `app/services/verification/adapters/`. It implements three things:

- `.declared_outcomes`: the full list of outcome symbols (`Array<Symbol>`) the source may emit.
- `precondition_met?(certification)`: whether the source has what it needs to run. When it returns false, `#call` returns a `:skipped` result without calling `perform`.
- `perform(certification:)`: calls the backing integration and returns a `Verification::DataSourceResult`.

```ruby
# app/services/verification/adapters/mock_example_source.rb
module Verification
  module Adapters
    class MockExampleSource < Verification::DataSource
      SOURCE = "mock_example_source"

      def self.declared_outcomes
        [ :resides_in_declared_emergency_county ]
      end

      protected

      def precondition_met?(certification)
        certification.member_data&.va_icn.present?
      end

      def perform(certification:)
        success_result(outcomes: [], audit_data: { source: SOURCE })
      end
    end
  end
end
```

Callers use the public `#call(certification:)`, which never returns `nil` and raises `Verification::DataSource::ContractError` if `perform` returns anything other than a `DataSourceResult`.

### Results

`Verification::DataSourceResult` has three statuses:

- `:success`: the source was called. `outcomes` may be empty, which means "called, no matching outcome".
- `:skipped`: a precondition was missing. This is distinct from a `:success` with empty outcomes.
- `:error`: the source failed for an expected integration reason. Override `expected_error_classes` to list those error classes; `#call` catches them and returns an `:error` result with an `error_code` and `error_message`. Any other exception propagates.

Build results with the `success_result`, `skipped_result` and `error_result` helpers. `audit_data` is always a Hash and must be redacted before it reaches the result. The `ExclusionDeterminationService` records `audit_data[:source]` as the data source of a determination, so set it.

`ExclusionDeterminationService` does not branch on result status, and an `:error` result carries no outcomes by default; see [navapbc/oscer#810](https://github.com/navapbc/oscer/issues/810).

## Step 2: Register the Source

Add an entry to `reporting-app/config/custom/verification_data_sources.yml`, keyed by source id:

```yaml
mock_example_source:
  enabled: true
  adapter_class: "Verification::Adapters::MockExampleSource"
  order: 30
```

- `id`: the entry key. The data source check step records it as the data source of a determination.
- `adapter_class`: required. Must be a `Verification::DataSource` subclass that implements `.declared_outcomes`.
- `enabled`: required, `true` or `false`. A disabled source is not consulted. An enabled source must declare at least one outcome.
- `order`: an Integer or `null`. Orders must be distinct across sources.

Outcomes are declared on the class, not in the YAML. At boot the loader (`VerificationDataSourcesLoader`) raises a `ConfigurationError` naming the entry if any of these fail: a missing required key, an `adapter_class` that does not constantize or is not a `Verification::DataSource` subclass, a missing or malformed `.declared_outcomes`, an outcome that is not a `Determination::REASON_CODE_MAPPING` key, a non-Integer `order`, or a duplicate `order`.

## How Outcomes Reach the Rules

Where a source is consulted depends on the outcomes it declares and its `order`:

- **Exclusion outcomes: use `order: null`.** `ExclusionDeterminationService` consults enabled sources that declare an exclusion outcome, best-ranked first, and ranks the outcomes by `Exclusion.priority_order` (`config/custom/exclusion_types.yml`). A source's own `order` does not rank exclusions. Other outcomes such as exceptions emitted by these sources are recorded as an exception when no exclusion applies.
- **Exception or community-engagement outcomes: set an `order`.** `DataSourceOrchestrator` consults enabled sources that have an `order`, in ascending `order`, at the data source check step (`DataSourceCheckService`). The first `:success` result with at least one outcome wins. Skipped results, errors and successes with no outcomes do not stop the pass; if none produces an outcome, the member is recorded as not meeting the requirement.

An order-bearing source should declare only exception outcomes (`Determination::EXCEPTION_OUTCOME_KEYS`) or community-engagement outcomes (`Determination::CE_OUTCOME_KEYS`); the loader rejects any outcome that is neither of those nor an exclusion id. `DataSourceCheckService` raises `UnsupportedOutcomeError` when the winning result carries an outcome outside those two sets, such as an exclusion, so give a source that declares exclusion outcomes `order: null`.

## Mock Sources

The shipped mock sources are registered in `config/custom/verification_data_sources.yml`, the deployment-owned override file; `VerificationDataSourcesLoader::DEFAULTS` is empty. The file's comments say the order-bearing mocks exercise the data source check step while no real non-exclusion source exists, and `mock_drug_treatment` (`order: null`) is consulted by `ExclusionDeterminationService`. A deployment can turn a shipped source off with `enabled: false`.

## Step 3: Add Tests

Use the shared examples in `spec/support/verification/data_source_shared_examples.rb`:

- `"a skipped verification result"`, `"a successful verification result"` and `"an errored verification result"` each check a result provided by `let(:result)`.
- `"a resilient verification data source"` checks that an expected integration failure becomes an `:error` result rather than raising. It needs `let(:data_source)` and `let(:certification)`.
- `"a registered verification data source"` checks that the described class has a registry entry and declares only `Determination::REASON_CODE_MAPPING` keys.

```ruby
RSpec.describe Verification::Adapters::MockExampleSource do
  it_behaves_like "a registered verification data source"
end
```
