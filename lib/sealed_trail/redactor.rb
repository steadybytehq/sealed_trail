# frozen_string_literal: true

module SealedTrail
  # Decides which attribute names are redacted.
  class Redactor
    def initialize(rules)
      @strings = []
      @patterns = []
      Array(rules).flatten.each do |rule|
        rule.is_a?(Regexp) ? @patterns << rule : @strings << rule.to_s
      end
    end

    def redact?(name)
      name = name.to_s
      @strings.include?(name) || @patterns.any? { |pattern| pattern.match?(name) }
    end

    def self.mask(value)
      value.nil? ? nil : REDACTED
    end
  end
end
