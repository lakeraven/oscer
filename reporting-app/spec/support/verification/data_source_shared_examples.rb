# frozen_string_literal: true

# Shared expectations for the +Verification::DataSource+ contract.
#
# Every verification data source result must satisfy the base invariants
# ("a verification data source result"): never nil, always a
# +Verification::DataSourceResult+, a known status, a flat Array<Symbol> of
# outcomes, and a Hash audit_data. The status-specific groups layer the
# per-status assertions on top.
#
# Host specs provide the result under test via +let(:result)+ (or +subject+),
# typically by calling the data source's +#call+ with a certification set up
# for that scenario. Example:
#
#   describe SomeSource do
#     subject(:result) { described_class.new.call(certification: certification) }
#
#     context "when the ICN is missing" do
#       let(:certification) { build(:certification) }
#       it_behaves_like "a skipped verification result"
#     end
#   end

RSpec.shared_examples "a verification data source result" do
  it "is never nil" do
    expect(result).not_to be_nil
  end

  it "is a DataSourceResult" do
    expect(result).to be_a(Verification::DataSourceResult)
  end

  it "has a known status" do
    expect(Verification::DataSourceResult::STATUSES).to include(result.status)
  end

  it "exposes outcomes as a flat Array of Symbols" do
    expect(result.outcomes).to be_an(Array)
    expect(result.outcomes).to all(be_a(Symbol))
  end

  it "always exposes audit_data as a Hash (never nil)" do
    expect(result.audit_data).to be_a(Hash)
  end
end

RSpec.shared_examples "a skipped verification result" do
  it_behaves_like "a verification data source result"

  it "has status :skipped" do
    expect(result.status).to eq(Verification::DataSourceResult::STATUS_SKIPPED)
    expect(result).to be_skipped
  end

  it "emits no outcomes" do
    expect(result.outcomes).to be_empty
  end
end

RSpec.shared_examples "a successful verification result" do
  it_behaves_like "a verification data source result"

  it "has status :success" do
    expect(result.status).to eq(Verification::DataSourceResult::STATUS_SUCCESS)
    expect(result).to be_success
  end

  it "records audit_data (present on every non-skipped call)" do
    expect(result.audit_data).to be_a(Hash)
  end
end

RSpec.shared_examples "an errored verification result" do
  it_behaves_like "a verification data source result"

  it "has status :error" do
    expect(result.status).to eq(Verification::DataSourceResult::STATUS_ERROR)
    expect(result).to be_error
  end

  it "records an error_code and error_message" do
    expect(result.error_code).to be_present
    expect(result.error_message).to be_present
  end

  it "records audit_data (present on every non-skipped call)" do
    expect(result.audit_data).to be_a(Hash)
  end
end

# Invariants that require exercising +#call+ rather than inspecting a single
# result. Host specs provide +let(:data_source)+ and +let(:certification)+,
# where the data source is configured to hit an expected integration failure.
RSpec.shared_examples "a resilient verification data source" do
  it "declares the outcomes it can emit" do
    expect(data_source.class.declared_outcomes).to all(be_a(Symbol))
  end

  it "does not raise for an expected integration failure" do
    expect { data_source.call(certification: certification) }.not_to raise_error
  end

  it "returns an :error result for an expected integration failure" do
    result = data_source.call(certification: certification)

    expect(result).to be_a(Verification::DataSourceResult)
    expect(result).to be_error
    expect(result.audit_data).to be_a(Hash)
  end
end

# Registration invariants for a shipped data source. Host specs describe the
# adapter class, so +described_class+ is the source under test.
RSpec.shared_examples "a registered verification data source" do
  it "has an entry in the data source registry" do
    adapter_classes = Rails.application.config.verification_data_sources.pluck(:adapter_class)

    expect(adapter_classes).to include(described_class.name)
  end

  it "declares only Determination reason-code mapping keys" do
    expect(described_class.declared_outcomes).to all(be_in(Determination::REASON_CODE_MAPPING.keys))
  end
end

# Runs a registered source end to end through +ExclusionDeterminationService+.
# Parameterized by +source_id+ and +reason_code+; the host provides
# +let(:confirming_member_data)+ and +let(:non_confirming_member_data)+, plus
# the service spec's +kase+, +service+ and +recorded_exclusion+, whose
# +member_data+ the examples set.
RSpec.shared_examples "a data source reaching the exclusion determination" do |source_id:, reason_code:|
  let(:entry) { Rails.application.config.verification_data_sources.find { |e| e[:id] == source_id } }

  before do
    allow(Rails.application.config).to receive(:verification_data_sources).and_return([ entry ])
  end

  context "when the source confirms the input" do
    let(:member_data) { confirming_member_data }

    it "excludes with the reason code" do
      service.determine(kase)
      expect(recorded_exclusion.reasons).to eq([ reason_code ])
    end

    it "records the source on the exclusion" do
      service.determine(kase)
      expect(recorded_exclusion.determination_data["data_source"]).to eq(source_id.to_s)
    end
  end

  context "when the source does not confirm the input" do
    let(:member_data) { non_confirming_member_data }

    it "does not exclude on the source" do
      service.determine(kase)
      expect(recorded_exclusion).to be_nil
    end
  end

  context "when the source returns an error" do
    let(:member_data) { confirming_member_data }

    before do
      error = Verification::DataSourceResult.error(
        error_code: "stubbed", error_message: "stubbed", audit_data: { source: source_id.to_s }
      )
      allow(entry[:adapter_class].constantize).to receive(:new).and_return(instance_double(Verification::DataSource, call: error))
    end

    it "pins current behavior pending navapbc/oscer#810: the member is determined not excluded" do
      service.determine(kase)
      expect(recorded_exclusion).to be_nil
    end
  end
end
