# frozen_string_literal: true

class Account < ApplicationRecord
  encrypts :notes

  has_sealed_trail redact: [ :pin, /\Assn/ ]
end
