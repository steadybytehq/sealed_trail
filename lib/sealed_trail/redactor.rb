# frozen_string_literal: true

require "openssl"

module SealedTrail
  # Decides whether an attribute is redacted, and how.
  #
  # Rules are attribute names (exact match), Regexps, or Hashes mapping either
  # to a strategy. A strategy of +false+ means "do not redact", which lets a
  # model opt out of a global rule. Earlier rule sets win.
  class Redactor
    STRATEGIES = %i[redact fingerprint mask].freeze

    def self.validate_rules!(rules)
      normalize(rules).each do |_, strategy|
        next if strategy.nil? || strategy == false || STRATEGIES.include?(strategy) || strategy.respond_to?(:call)

        raise ArgumentError, "Unknown redaction strategy: #{strategy.inspect} (use #{STRATEGIES.map(&:inspect).join(", ")}, false or a callable)"
      end
    end

    def self.normalize(rules)
      case rules
      when Hash then rules.to_a
      when nil then []
      else Array(rules).flat_map { |rule| rule.is_a?(Hash) ? rule.to_a : [ [ rule, nil ] ] }
      end
    end

    def initialize(*rule_sets)
      @rules = rule_sets.flat_map { |rules| self.class.normalize(rules) }
    end

    # The strategy for +name+, or nil when it is not redacted.
    def strategy_for(name)
      name = name.to_s
      rule = @rules.find { |matcher, _| matches?(matcher, name) }
      return nil if rule.nil? || rule.last == false

      rule.last || SealedTrail.config.redaction_strategy
    end

    def redact?(name)
      !strategy_for(name).nil?
    end

    # The value to store for +name+.
    def apply(name, value)
      strategy = strategy_for(name)
      strategy ? self.class.transform(strategy, value, name) : value
    end

    def self.transform(strategy, value, name = nil)
      return nil if value.nil?

      case strategy
      when :redact then REDACTED
      when :fingerprint then SealedTrail.fingerprint(value)
      when :mask then mask(value)
      else
        raise ArgumentError, "Unknown redaction strategy: #{strategy.inspect}" unless strategy.respond_to?(:call)

        strategy.arity == 1 ? strategy.call(value) : strategy.call(value, name.to_s)
      end
    end

    EMAIL = /\A([^@\s]+)@([^@\s]+)\z/

    # "jane@example.com" => "j***@example.com"; "+1 555 0100" => "*******0100";
    # values shorter than 8 characters are fully masked.
    def self.mask(value)
      string = stringify(value)
      if (match = EMAIL.match(string))
        "#{match[1][0]}***@#{match[2]}"
      elsif string.length < 8
        "*" * string.length
      else
        ("*" * (string.length - 4)) + string[-4..]
      end
    end

    def self.stringify(value)
      value.is_a?(String) ? value : value.to_json
    end

    private

    def matches?(matcher, name)
      matcher.is_a?(Regexp) ? matcher.match?(name) : matcher.to_s == name
    end
  end
end
