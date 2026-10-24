# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - Unreleased

### Added

- `has_sealed_trail` model macro recording create, update and destroy events
  with before/after values (`object_changes`), written in the same transaction
  as the change.
- Options `only:`, `ignore:`, `redact:`, `on:`, `meta:`, `if:` and `unless:`.
- Default redaction of password, token, secret, API/private key, OTP, salt and
  `encrypted_*` attributes, plus attributes declared with `encrypts`; values
  stored as `"[REDACTED]"`.
- Actor tracking (Active Record object or string label) through a controller
  concern resolved lazily per request, `SealedTrail.with_actor` and
  `SealedTrail::Current.actor`.
- Request id and remote IP captured automatically in controllers.
- `SealedTrail.without_tracking`, `SealedTrail.with_tracking` and
  `SealedTrail.with_metadata` blocks, isolated per thread/fiber via
  `ActiveSupport::CurrentAttributes`.
- `SealedTrail::Entry` query scopes: `for_actor`, `for_item`, `for_item_type`,
  `between`, `events`, `for_request`, `chronological`,
  `reverse_chronological`; `record.audit_entries`.
- `rails generate sealed_trail:install` creating the `sealed_trail_entries`
  migration (jsonb on PostgreSQL, json elsewhere) and an initializer.
- Support for Rails 7.1, 7.2, 8.0 and 8.1 on Ruby 3.2+, with PostgreSQL and
  SQLite.
