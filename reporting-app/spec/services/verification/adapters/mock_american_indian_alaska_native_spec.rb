# frozen_string_literal: true

require "rails_helper"

RSpec.describe Verification::Adapters::MockAmericanIndianAlaskaNative do
  subject(:result) { described_class.new.call(certification: certification) }

  let(:certification) do
    build(:certification, member_data: build(:certification_member_data, account_email: email))
  end
  let(:email) { "member@example.com" }
  let(:outcome) { :is_american_indian_or_alaska_native }

  it_behaves_like "a registered verification data source"

  it "declares the existing AI/AN exclusion outcome" do
    expect(described_class.declared_outcomes).to eq([ outcome ])
  end

  {
    "aian-tribe" => [ "447.51(1)", false ], "aian-urban" => [ "447.51(2)", false ],
    "aian-interior" => [ "447.51(3)", false ], "aian-itu" => [ "447.51(4)", false ],
    "aian-outofstate" => [ "447.51(1)", true ]
  }.each do |tag, (route, out_of_state)|
    context "when the email carries #{tag}" do
      let(:email) { "Member+#{tag.upcase}@example.com" }

      it_behaves_like "a successful verification result"

      it "emits the outcome and records the route without a member identifier" do
        expect(result.outcomes).to eq([ outcome ])
        expect(result.audit_data).to eq(source: described_class::SOURCE, route: route, asserter_out_of_state: out_of_state)
        expect(result.audit_data.values.join(" ")).not_to include("example.com")
      end
    end
  end

  %w[aian-lead aian-no].each do |tag|
    context "when the email carries #{tag}" do
      let(:email) { "member+#{tag}@example.com" }

      it "succeeds with no outcome" do
        expect(result).to be_success
        expect(result.outcomes).to be_empty
      end
    end
  end

  context "when the email carries aian-error" do
    let(:email) { "member+aian-error@example.com" }

    it_behaves_like "an errored verification result"
  end

  context "when the email carries no AI/AN tag" do
    it_behaves_like "a skipped verification result"
  end

  context "when only the race field says american_indian_or_alaska_native" do
    let(:certification) do
      build(:certification, member_data: build(:certification_member_data, race_ethnicity: "american_indian_or_alaska_native"))
    end

    it_behaves_like "a skipped verification result"
  end
end
