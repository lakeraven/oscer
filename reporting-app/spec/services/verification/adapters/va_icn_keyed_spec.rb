# frozen_string_literal: true

require "rails_helper"

RSpec.describe Verification::Adapters::VaIcnKeyed do
  let(:source) do
    Class.new(Verification::DataSource) do
      include Verification::Adapters::VaIcnKeyed

      public :precondition_met?, :last_digit
    end.new
  end

  def certification_with(va_icn)
    build(:certification, member_data: build(:certification_member_data, va_icn: va_icn))
  end

  describe "#precondition_met?" do
    it "is true when the member has a va_icn" do
      expect(source.precondition_met?(certification_with("1012345678V123456"))).to be(true)
    end

    it "is false when the member has no va_icn" do
      expect(source.precondition_met?(certification_with(nil))).to be(false)
    end
  end

  describe "#last_digit" do
    it "returns the last character as an integer when it is a digit" do
      expect(source.last_digit("1012345678V123457")).to eq(7)
    end

    it "returns nil when the last character is not a digit" do
      expect(source.last_digit("1012345678V12345X")).to be_nil
    end
  end
end
