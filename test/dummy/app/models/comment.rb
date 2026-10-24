# frozen_string_literal: true

class Comment < ApplicationRecord
  has_sealed_trail ignore: %i[likes updated_at]
end
