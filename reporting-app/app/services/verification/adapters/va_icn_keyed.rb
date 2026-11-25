# frozen_string_literal: true

module Verification
  module Adapters
    # Shared by mock data sources that key their outcome off the member's va_icn:
    # the source runs only when an ICN is present, and only its last character
    # matters.
    module VaIcnKeyed
      protected

      def precondition_met?(certification)
        certification.member_data&.va_icn.present?
      end

      private

      # The ICN's last digit, or nil when the last character is not a digit.
      def last_digit(va_icn)
        last = va_icn[-1]
        last.to_i if last&.match?(/\A\d\z/)
      end
    end
  end
end
