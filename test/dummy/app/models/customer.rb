# frozen_string_literal: true

class Customer < ApplicationRecord
  has_sealed_trail redact: {
    email: :fingerprint,
    phone: :mask,
    card_number: :mask,
    nickname: ->(value) { value.upcase },
    mobile: false
  }
end
