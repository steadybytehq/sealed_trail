# frozen_string_literal: true

class Invoice < ApplicationRecord
  has_sealed_trail on: %i[create destroy],
    bulk: false,
    unless: :draft?,
    meta: {
      source: "billing",
      number: :number,
      amount: ->(invoice) { invoice.amount_cents.to_i / 100.0 }
    }
end
