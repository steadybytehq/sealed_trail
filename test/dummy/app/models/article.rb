# frozen_string_literal: true

class Article < ApplicationRecord
  has_sealed_trail only: %i[title body]
end
