# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-25

### Added

- `has_sealed_trail` model macro recording create, update and destroy events
  with before/after values (`object_changes`), written in the same transaction
  as the change.
- Options `only:`, `ignore:`, `redact:`, `on:` (including opt-in `:touch`),
  `meta:`, `bulk:`, `if:` and `unless:`.
- Failure handling: `config.on_failure` = `:log` (default; the entry is written
  in a savepoint, failures are logged, instrumented as
  `write_failed.sealed_trail` and passed to `config.error_handler`, and the
  user's save succeeds), `:raise` (strict) or a callable.
- Redaction by default of password, token, secret, API/private key, OTP, salt,
  `encrypted_*`, email, `*_email`, phone, `*_phone` and mobile attributes, plus
  attributes declared with `encrypts`.
- Redaction strategies `:redact` (`"[REDACTED]"`), `:fingerprint` (keyed
  HMAC-SHA256, `"hmac:<hex>"`), `:mask` (`"j***@example.com"`,
  `"******1234"`), callables, and `false` to opt out of a global rule; set per
  attribute (`redact: { email: :fingerprint }`) or globally
  (`config.redaction_strategy`). `SealedTrail.fingerprint` and
  `Entry.with_fingerprint` look values up.
- Actor tracking (Active Record object or label) through a controller concern
  resolved lazily per request, `SealedTrail.with_actor` and
  `SealedTrail::Current.actor`, with fallbacks: `"anonymous"` in requests,
  `"job:<JobClass>"`, `"rake:<task>"`, `"console"`, then
  `config.default_actor` (`"system"`).
- Active Job integration: jobs inherit the enqueuing actor (GlobalID or
  label), request id, remote IP and metadata.
- Request id and remote IP captured automatically in controllers.
- Recording of callback-skipping methods: `update_columns`/`update_column` and
  `delete` per record; `update_all`, `delete_all`, `insert_all`, `insert_all!`
  and `upsert_all` as one bulk summary entry each, with affected ids (capped by
  `config.bulk_id_limit`), row count and masked WHERE/SET SQL.
- `SealedTrail.without_tracking`, `SealedTrail.with_tracking` and
  `SealedTrail.with_metadata` blocks, isolated per thread/fiber via
  `ActiveSupport::CurrentAttributes`.
- `SealedTrail::Entry` query scopes: `for_actor`, `for_item`, `affecting`,
  `for_item_type`, `between`, `events`, `bulk`, `for_request`,
  `with_fingerprint`, `chronological`, `reverse_chronological`;
  `record.audit_entries`.
- `rails generate sealed_trail:install` creating the `sealed_trail_entries`
  migration (jsonb on PostgreSQL, json on MySQL and SQLite) and a documented
  initializer.
- Support for Rails 7.1, 7.2, 8.0 and 8.1 on Ruby 3.2+, with PostgreSQL,
  MySQL 8+ (`mysql2` and `trilogy`) and SQLite.

[Unreleased]: https://github.com/steadybytehq/sealed_trail/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/steadybytehq/sealed_trail/releases/tag/v0.1.0
