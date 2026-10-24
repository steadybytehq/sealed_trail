# frozen_string_literal: true

class Post < ApplicationRecord
  belongs_to :user, optional: true

  has_sealed_trail
end
