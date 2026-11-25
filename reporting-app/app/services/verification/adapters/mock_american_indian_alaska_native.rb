# frozen_string_literal: true

module Verification
  module Adapters
    # Mock AI/AN verification data source. Reads a tag in the member's account_email,
    # mirroring MockCommunityEngagement, and on a confirmation under 42 CFR 447.51 emits
    # the existing :is_american_indian_or_alaska_native exclusion outcome.
    #
    #   tag in email      result
    #   -------------------------------------------------------------------------
    #   (none)            :skipped
    #   aian-tribe        outcome, route 447.51(1)
    #   aian-urban        outcome, route 447.51(2)
    #   aian-interior     outcome, route 447.51(3)
    #   aian-itu          outcome, route 447.51(4)
    #   aian-outofstate   outcome, route 447.51(1), asserter_out_of_state true
    #   aian-lead         no outcome (a lead alone never excludes)
    #   aian-no           no outcome (not eligible)
    #   aian-error        :error
    #
    # audit_data never carries a member identifier. A real source must NOT copy the
    # email-keyed trigger; it should ask the authority that actually confirms status.
    class MockAmericanIndianAlaskaNative < Verification::DataSource
      SOURCE = "mock_american_indian_alaska_native"
      OUTCOME_AIAN = :is_american_indian_or_alaska_native

      # The authority failed (the mock's stand-in for a timeout or 5xx).
      class AuthorityError < StandardError; end

      TAG_ROUTES = {
        "aian-tribe" => "447.51(1)", "aian-urban" => "447.51(2)", "aian-interior" => "447.51(3)",
        "aian-itu" => "447.51(4)", "aian-outofstate" => "447.51(1)"
      }.freeze
      NO_OUTCOME_TAGS = %w[aian-lead aian-no].freeze

      def self.declared_outcomes
        [ OUTCOME_AIAN ]
      end

      protected

      def precondition_met?(certification)
        !tag_for(certification).nil?
      end

      def perform(certification:)
        tag = tag_for(certification)
        raise AuthorityError, "AI/AN authority unavailable" if tag == "aian-error"
        return success_result(audit_data: { source: SOURCE }) if NO_OUTCOME_TAGS.include?(tag)

        success_result(
          outcomes: [ OUTCOME_AIAN ],
          audit_data: { source: SOURCE, route: TAG_ROUTES.fetch(tag), asserter_out_of_state: tag == "aian-outofstate" }
        )
      end

      def expected_error_classes
        [ AuthorityError ]
      end

      private

      def tag_for(certification)
        email = certification.member_account_email.to_s.downcase
        (TAG_ROUTES.keys + NO_OUTCOME_TAGS + [ "aian-error" ]).find { |tag| email.include?(tag) }
      end
    end
  end
end
