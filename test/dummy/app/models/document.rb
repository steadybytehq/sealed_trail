# frozen_string_literal: true

class Document < ApplicationRecord
  before_create { self.id ||= SecureRandom.uuid }

  has_sealed_trail
end
