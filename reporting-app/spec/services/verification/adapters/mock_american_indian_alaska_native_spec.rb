# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/verification/aian_data_source_shared_examples"

RSpec.describe Verification::Adapters::MockAmericanIndianAlaskaNative do
  subject(:result) { described_class.new.call(certification: certification) }

  let(:certification) do
    build(:certification, member_data: build(:certification_member_data, account_email: email))
  end
  let(:source) { "mock_american_indian_alaska_native" }

  # oscer-fork/01, "The adapter declares the existing AI/AN outcome"
  describe ".declared_outcomes" do
    it "declares the existing AI/AN exclusion outcome" do
      expect(described_class.declared_outcomes).to eq([ :is_american_indian_or_alaska_native ])
    end

    it "declares only Determination reason-code mapping keys" do
      expect(described_class.declared_outcomes).to all(be_in(Determination::REASON_CODE_MAPPING.keys))
    end

    it "is registered in the booted registry and enabled" do
      entry = Rails.application.config.verification_data_sources.find { |e| e[:id] == :mock_american_indian_alaska_native }

      expect(entry).to include(enabled: true, adapter_class: described_class.name)
    end
  end

  # oscer-fork/01, "The shared examples accept every 447.51 route" (and the rest of the contract)
  it_behaves_like "an AI/AN verification data source" do
    let(:adapter_for) { ->(response) { described_class.new(authority: ->(_cert) { response }) } }
  end

  describe "#call keyed off the email tag" do
    # oscer-fork/01, "A confirmed status excludes, and the basis is recorded"
    {
      "aian-tribe" => [ "447.51(1)", "tribe", false ],
      "aian-itu" => [ "447.51(4)", "itu_provider", false ],
      "aian-outofstate" => [ "447.51(1)", "tribe", true ]
    }.each do |tag, (route, asserter_type, out_of_state)|
      context "when the email carries #{tag}" do
        let(:email) { "Member+#{tag.upcase}@example.com" }

        it_behaves_like "a successful verification result"

        it "emits the outcome with the route, asserter type, evidence type and ISO asserted_on" do
          expect(result.outcomes).to eq([ :is_american_indian_or_alaska_native ])
          expect(result.audit_data).to include(
            source: source, route: route, asserter_type: asserter_type, asserter_out_of_state: out_of_state,
            asserted_on: Date.current.iso8601
          )
          expect(result.audit_data[:evidence_type]).to be_present
        end

        it "holds no member identifier" do
          expect(result.audit_data.values.join(" ")).not_to include("example.com")
        end
      end
    end

    # oscer-fork/01, "A lead alone emits no outcome"
    context "when the email carries aian-lead" do
      let(:email) { "member+aian-lead@example.com" }

      it "succeeds with no outcomes and basis lead_only" do
        expect(result).to be_success
        expect(result.outcomes).to eq([])
        expect(result.audit_data).to eq(source: source, basis: "lead_only")
      end
    end

    # oscer-fork/01, "Not confirmed emits no outcome"
    context "when the email carries aian-no" do
      let(:email) { "member+aian-no@example.com" }

      it "succeeds with no outcomes and basis not_confirmed" do
        expect(result).to be_success
        expect(result.outcomes).to eq([])
        expect(result.audit_data).to eq(source: source, basis: "not_confirmed")
      end
    end

    # oscer-fork/01, "A source error is an error result, not a no"
    context "when the email carries aian-error" do
      let(:email) { "member+aian-error@example.com" }

      it_behaves_like "an errored verification result"

      it "is an error result with no outcomes" do
        expect(result.status).to eq(:error)
        expect(result.outcomes).to eq([])
      end
    end

    # oscer-fork/01, "No tag means the source is skipped"
    context "when the email carries no AI/AN tag" do
      let(:email) { "member@example.com" }

      it_behaves_like "a skipped verification result"
    end

    context "when the member has no email" do
      let(:email) { nil }

      it_behaves_like "a skipped verification result"
    end
  end
end
