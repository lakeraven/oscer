# frozen_string_literal: true

module Verification
  module Adapters
    # Mock data source deriving a drug-treatment outcome from the last digit of
    # the member's va_icn:
    #
    #   * absent ICN                          -> :skipped
    #   * ICN not ending in a digit           -> :success, no outcomes ("no result")
    #   * last digit divisible by 3           -> :success, [:drug_treatment]        (exclusion)
    #   * last digit odd, not divisible by 3  -> :success, [:was_in_drug_treatment] (exception)
    #   * last digit even, not divisible by 3 -> :success, no outcomes              (no result)
    #
    # Outcomes: :drug_treatment (exclusion), :was_in_drug_treatment (exception).
    class MockDrugTreatment < Verification::DataSource
      include VaIcnKeyed

      SOURCE = "mock_drug_treatment"
      OUTCOME_EXCLUDED = :drug_treatment
      OUTCOME_EXCEPTED = :was_in_drug_treatment

      def self.declared_outcomes
        [ OUTCOME_EXCLUDED, OUTCOME_EXCEPTED ]
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
        return [] if digit.nil?

        if (digit % 3).zero?
          [ OUTCOME_EXCLUDED ]
        elsif digit.odd?
          [ OUTCOME_EXCEPTED ]
        else
          []
        end
      end
    end
  end
end
