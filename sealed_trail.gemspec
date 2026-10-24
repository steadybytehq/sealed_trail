# frozen_string_literal: true

require_relative "lib/sealed_trail/version"

Gem::Specification.new do |spec|
  spec.name = "sealed_trail"
  spec.version = SealedTrail::VERSION
  spec.authors = [ "Steadybyte" ]
  spec.email = [ "steadybyte.hq@gmail.com" ]

  spec.summary = "Audit trail of who changed what, when, for Rails models."
  spec.description = <<~DESC.tr("\n", " ").strip
    SealedTrail records create, update and destroy events on Active Record models
    with before/after values, the acting user, request id and IP address, and
    redacts sensitive attributes by default. It helps Rails teams produce audit
    evidence for security reviews.
  DESC
  spec.homepage = "https://steadybytehq.github.io/sealedtrail/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/steadybytehq/sealed_trail",
    "changelog_uri" => "https://github.com/steadybytehq/sealed_trail/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/steadybytehq/sealed_trail/issues",
    "documentation_uri" => "https://github.com/steadybytehq/sealed_trail#readme",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activerecord", ">= 7.1", "< 9"
  spec.add_dependency "activesupport", ">= 7.1", "< 9"
end
