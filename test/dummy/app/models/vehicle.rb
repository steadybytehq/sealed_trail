# frozen_string_literal: true

class Vehicle < ApplicationRecord
  has_sealed_trail on: %i[create update destroy touch]
end
