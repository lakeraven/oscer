# frozen_string_literal: true

# Shared expectations any AI/AN verification data source must satisfy, mock or real.
#
# The host provides +let(:adapter_for)+: a callable taking an authority response Hash and
# returning a data source whose backing authority answers exactly that. Response keys:
#
#   status:                :confirmed, :not_eligible or :lead
#   route:                 "447.51(1)".."447.51(4)"          (confirmed only)
#   asserter_type:         tribe, person, state_tribe, interior, itu_provider,
#                          alaska_native_org                 (confirmed only)
#   evidence_type:         String                            (confirmed only)
#   asserted_on:           Date                              (confirmed only)
#   asserter_out_of_state: Boolean                           (confirmed only)
#   asserter_name:         String, optional; the asserting authority's name
#
# Example:
#
#   let(:adapter_for) { ->(response) { described_class.new(authority: ->(_cert) { response }) } }
#   it_behaves_like "an AI/AN verification data source"
RSpec.shared_examples "an AI/AN verification data source" do
  let(:certification) do
    build(:certification, member_data: build(:certification_member_data, account_email: "member@example.com"))
  end
  let(:asserted_on) { Date.new(2025, 3, 14) }

  def confirmed(route:, asserter_type:, **extra)
    {
      status: :confirmed, route: route, asserter_type: asserter_type, evidence_type: "enrollment_record",
      asserted_on: Date.new(2025, 3, 14), asserter_out_of_state: false
    }.merge(extra)
  end

  def run(response)
    adapter_for.call(response).call(certification: certification)
  end

  it "declares the existing AI/AN outcome" do
    expect(adapter_for.call({ status: :lead }).class.declared_outcomes).to eq([ :is_american_indian_or_alaska_native ])
  end

  # oscer-fork/01, "The shared examples accept every 447.51 route"
  [
    [ "447.51(1)", "tribe" ],
    [ "447.51(2)", "person" ],
    [ "447.51(2)", "state_tribe" ],
    [ "447.51(3)", "interior" ],
    [ "447.51(4)", "itu_provider" ],
    [ "447.51(4)", "alaska_native_org" ]
  ].each do |route, asserter_type|
    context "when route #{route} is confirmed from asserter type #{asserter_type}" do
      subject(:result) { run(confirmed(route: route, asserter_type: asserter_type)) }

      it "emits the AI/AN outcome" do
        expect(result).to be_success
        expect(result.outcomes).to eq([ :is_american_indian_or_alaska_native ])
      end

      it "records the route, asserter type, evidence type and asserted_on date" do
        expect(result.audit_data).to include(
          route: route, asserter_type: asserter_type, evidence_type: "enrollment_record",
          asserted_on: "2025-03-14", asserter_out_of_state: false
        )
        expect(result.audit_data).to have_key(:source)
      end
    end
  end

  # oscer-fork/01, "The shared examples reject a tribe allow-list"
  context "when the confirmation comes from a tribe the adapter has never seen" do
    it "emits the AI/AN outcome" do
      result = run(confirmed(route: "447.51(1)", asserter_type: "tribe", asserter_name: "Never Seen Example Tribe"))

      expect(result.outcomes).to eq([ :is_american_indian_or_alaska_native ])
    end
  end

  # oscer-fork/01, "An out-of-state asserter counts the same as an in-state one"
  context "when the asserter is out of state" do
    it "emits the outcome and records it" do
      result = run(confirmed(route: "447.51(1)", asserter_type: "tribe", asserter_out_of_state: true))

      expect(result.outcomes).to eq([ :is_american_indian_or_alaska_native ])
      expect(result.audit_data[:asserter_out_of_state]).to be(true)
    end
  end

  # oscer-fork/01, "The shared examples treat an explicit not eligible as no outcome"
  context "when the asserting authority answers not eligible" do
    subject(:result) { run({ status: :not_eligible }) }

    it "emits no outcome and records basis not_confirmed" do
      expect(result).to be_success
      expect(result.outcomes).to be_empty
      expect(result.audit_data).to include(basis: "not_confirmed")
    end
  end

  # oscer-fork/01, "The shared examples reject excluding on a lead"
  context "when only a lead is found" do
    subject(:result) { run({ status: :lead }) }

    it "emits no outcome and records basis lead_only" do
      expect(result).to be_success
      expect(result.outcomes).to be_empty
      expect(result.audit_data).to include(basis: "lead_only")
    end
  end

  it "keeps member identifiers out of audit_data" do
    result = run(confirmed(route: "447.51(1)", asserter_type: "tribe"))
    flat = result.audit_data.values.join(" ")

    expect(flat).not_to include(certification.member_account_email)
    expect(result.audit_data.keys).to all(be_in(
      %i[source route asserter_type evidence_type asserted_on asserter_out_of_state basis]
    ))
  end
end
