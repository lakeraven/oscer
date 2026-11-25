# frozen_string_literal: true

module Verification
  module Adapters
    # Mock data source demonstrating the ordered non-exclusion pass in
    # Verification::DataSourceOrchestrator (OSCER-805). Like MockDrugTreatment, it
    # derives its outcome from the last digit of the member's va_icn:
    #
    #   * absent ICN                -> :skipped
    #   * ICN not ending in a digit -> :success, no outcomes ("no result")
    #   * last digit even           -> :success, [:resides_in_declared_emergency_county]
    #   * last digit odd            -> :success, no outcomes ("no result")
    #
    # va_icn is an unrelated identity field, chosen (as in MockDrugTreatment) so the
    # outcome is a deterministic function of a single always-present scalar, letting
    # specs drive every branch. Keying off an unrelated field also keeps the demo
    # honest: it does NOT re-read the declared_emergency_county exemption, the in-hand
    # data ExceptionDeterminationService already evaluates, so it stands in for an
    # *external* source rather than duplicating the in-hand check.
    #
    # Outcome: :resides_in_declared_emergency_county (a non-exclusion exception key).
    # Because it declares no exclusion outcome, this source is order-bearing and is
    # consulted only by the orchestrator, never by ExclusionDeterminationService.
    class MockEmergencyCounty < Verification::DataSource
      include VaIcnKeyed

      SOURCE = "mock_emergency_county"
      OUTCOME_EXCEPTED = :resides_in_declared_emergency_county

      def self.declared_outcomes
        [ OUTCOME_EXCEPTED ]
      end

      protected

      def perform(certification:)
        success_result(
          outcomes: outcomes_for(certification.member_data.va_icn),
          audit_data: { source: SOURCE }
        )
      end

      private

      # A non-digit last character is "no result".
      def outcomes_for(va_icn)
        digit = last_digit(va_icn)
        digit&.even? ? [ OUTCOME_EXCEPTED ] : []
      end
    end
  end
end
