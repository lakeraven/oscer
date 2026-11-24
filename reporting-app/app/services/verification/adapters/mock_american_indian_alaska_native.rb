# frozen_string_literal: true

module Verification
  module Adapters
    # Mock AI/AN verification data source. Asks an "authority" whether the member's
    # AI/AN status is confirmed under 42 CFR 447.51 and, only on a confirmation,
    # emits the existing :is_american_indian_or_alaska_native exclusion outcome.
    #
    # The authority is a callable taking the certification and returning a response
    # Hash. By default it reads a tag in the member's account_email, mirroring
    # MockCommunityEngagement:
    #
    #   tag in email      result
    #   -------------------------------------------------------------------------
    #   (none)            :skipped
    #   aian-tribe        outcome, route 447.51(1), asserter_type tribe
    #   aian-itu          outcome, route 447.51(4), asserter_type itu_provider
    #   aian-outofstate   outcome, route 447.51(1), tribe, asserter_out_of_state true
    #   aian-lead         no outcome, basis lead_only
    #   aian-no           no outcome, basis not_confirmed
    #   aian-error        :error
    #
    # Response keys: :status (:confirmed, :not_eligible or :lead) and, for :confirmed,
    # :route, :asserter_type, :evidence_type, :asserted_on and :asserter_out_of_state.
    # Tests inject their own authority to exercise every route and asserter type.
    #
    # audit_data never carries a member identifier. A real source must NOT copy the
    # email-keyed trigger (see MockCommunityEngagement); it should ask the authority
    # that actually confirms status.
    class MockAmericanIndianAlaskaNative < Verification::DataSource
      SOURCE = "mock_american_indian_alaska_native"
      OUTCOME_AIAN = :is_american_indian_or_alaska_native

      BASIS_LEAD_ONLY = "lead_only"
      BASIS_NOT_CONFIRMED = "not_confirmed"

      # The authority failed (the mock's stand-in for a timeout or 5xx).
      class AuthorityError < StandardError; end

      TAG_RESPONSES = {
        "aian-error" => :error,
        "aian-lead" => { status: :lead },
        "aian-no" => { status: :not_eligible },
        "aian-itu" => {
          status: :confirmed, route: "447.51(4)", asserter_type: "itu_provider",
          evidence_type: "provider_attestation", asserter_out_of_state: false
        },
        "aian-outofstate" => {
          status: :confirmed, route: "447.51(1)", asserter_type: "tribe",
          evidence_type: "enrollment_record", asserter_out_of_state: true
        },
        "aian-tribe" => {
          status: :confirmed, route: "447.51(1)", asserter_type: "tribe",
          evidence_type: "enrollment_record", asserter_out_of_state: false
        }
      }.freeze

      def self.declared_outcomes
        [ OUTCOME_AIAN ]
      end

      # @param authority [#call, nil] certification -> response Hash or nil
      def initialize(authority: nil)
        super()
        @injected = !authority.nil?
        @authority = authority || method(:response_from_email_tag)
      end

      protected

      def precondition_met?(certification)
        @injected || !tag_for(certification).nil?
      end

      def perform(certification:)
        response = @authority.call(certification)

        if response[:status] == :confirmed
          success_result(outcomes: [ OUTCOME_AIAN ], audit_data: confirmed_audit_data(response))
        else
          success_result(audit_data: { source: SOURCE, basis: basis_for(response) })
        end
      end

      def expected_error_classes
        [ AuthorityError ]
      end

      private

      def response_from_email_tag(certification)
        response = TAG_RESPONSES.fetch(tag_for(certification))
        raise AuthorityError, "AI/AN authority unavailable" if response == :error

        response.merge(asserted_on: Date.current)
      end

      def tag_for(certification)
        email = certification.member_account_email.to_s.downcase
        TAG_RESPONSES.keys.find { |key| email.include?(key) }
      end

      def confirmed_audit_data(response)
        {
          source: SOURCE,
          route: response.fetch(:route),
          asserter_type: response.fetch(:asserter_type),
          evidence_type: response.fetch(:evidence_type),
          asserted_on: response.fetch(:asserted_on).to_date.iso8601,
          asserter_out_of_state: response.fetch(:asserter_out_of_state, false)
        }
      end

      # Only an explicit "not eligible" is not_confirmed; anything short of a
      # confirmation, including a lead, never excludes.
      def basis_for(response)
        response[:status] == :not_eligible ? BASIS_NOT_CONFIRMED : BASIS_LEAD_ONLY
      end
    end
  end
end
