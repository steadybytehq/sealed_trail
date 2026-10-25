# SealedTrail

[![CI](https://github.com/steadybytehq/sealed_trail/actions/workflows/ci.yml/badge.svg)](https://github.com/steadybytehq/sealed_trail/actions/workflows/ci.yml)

**An audit trail for Rails: who changed what, when, and from where.**

SealedTrail records every create, update and destroy on the Active Record models
you choose: the before and after values, the user (or job, or script) that made
the change, the time, the request id and the IP address. Bulk operations such
as `update_all` and `delete_all` are recorded too. Passwords, tokens, secrets,
emails, phone numbers and encrypted attributes are redacted by default.

```ruby
class Patient < ApplicationRecord
  has_sealed_trail
end

patient.update!(status: "discharged", phone: "+1 555 0100")

patient.audit_entries.last
# => #<SealedTrail::Entry event: "update",
#      object_changes: {"status" => ["admitted", "discharged"],
#                       "phone" => ["[REDACTED]", "[REDACTED]"], "updated_at" => [...]},
#      actor_type: "User", actor_id: "42", request_id: "9f1c...", remote_ip: "203.0.113.7",
#      created_at: ...>
```

> **About compliance.** SealedTrail helps you produce audit evidence (a record of
> who changed which data and when) for security reviews and audits such as
> SOC 2, HIPAA or GDPR. It does not, by itself, make an application compliant
> with any standard or law. Compliance depends on your whole system, processes
> and policies.

## Requirements

- Ruby 3.2 or newer
- Rails 7.1, 7.2, 8.0 or 8.1
- PostgreSQL, MySQL 8+ (`mysql2` or `trilogy` adapter) or SQLite

## Installation

Add the gem and run the installer:

```sh
bundle add sealed_trail
bin/rails generate sealed_trail:install
bin/rails db:migrate
```

The installer creates:

- a migration for the single `sealed_trail_entries` table (`jsonb` columns on
  PostgreSQL, `json` on MySQL and SQLite; force one with `--json-type=json|jsonb`)
- `config/initializers/sealed_trail.rb` with every setting commented out

## Usage

### Track a model

```ruby
class Invoice < ApplicationRecord
  has_sealed_trail
end
```

Each event creates one `SealedTrail::Entry`:

| event     | `object_changes`                                             |
|-----------|--------------------------------------------------------------|
| `create`  | every non-nil attribute as `[nil, value]`                    |
| `update`  | only the attributes that changed, as `[before, after]`       |
| `destroy` | every non-nil attribute as `[value, nil]` (the final state)  |

Saves that change nothing are not recorded. Entries are written in the same
database transaction as the change, so if the change rolls back, so does the
entry.

Methods that skip callbacks are recorded as well:

| method                                 | recorded as                                          |
|----------------------------------------|------------------------------------------------------|
| `update_columns`, `update_column`      | an `update` entry, `metadata["via"] = "update_columns"` |
| `delete`                               | a `destroy` entry, `metadata["via"] = "delete"`       |
| `touch`                                | a `touch` entry, only with `on: [..., :touch]`        |
| `update_all`, `delete_all`, `insert_all`, `insert_all!`, `upsert_all` (and `insert`, `upsert`, `Model.delete(id)`, counter caches) | one bulk summary entry, see [Bulk operations](#bulk-operations) |

### When an entry cannot be written

By default a failed audit write never blocks the user's save. The entry is
written inside a savepoint, so a failed INSERT does not abort the surrounding
transaction (important on PostgreSQL); the error is logged, the
`write_failed.sealed_trail` notification is instrumented, and your
`error_handler` is called:

```ruby
SealedTrail.configure do |config|
  config.on_failure = :log   # default
  config.error_handler = ->(error, payload) { Rails.error.report(error, context: payload.except(:error)) }
end

ActiveSupport::Notifications.subscribe("write_failed.sealed_trail") do |event|
  event.payload[:error]  # the exception
  event.payload[:entry]  # the attributes of the entry that was not written
end
```

Choose `config.on_failure = :raise` for strict mode: the exception propagates
and the change is rolled back rather than left unaudited. A callable
`->(error, payload) { ... }` replaces the default handling (raise from it to
block the save).

### Options

```ruby
class Patient < ApplicationRecord
  has_sealed_trail(
    ignore: [:last_seen_at],        # never record these attributes
    redact: { ssn: :mask, insurance_id: :fingerprint, diagnosis: :redact },
    meta: {                         # extra data stored with each entry
      clinic_id: :clinic_id,                    # Symbol: method on the record
      source: "patient-portal",                 # static value
      ward: ->(patient) { patient.ward&.name }  # Proc: called with the record
    }
  )
end

class Article < ApplicationRecord
  has_sealed_trail only: [:title, :body]   # record just these attributes
end

class Invoice < ApplicationRecord
  has_sealed_trail on: [:create, :destroy], unless: :draft?
end
```

| option            | meaning                                                                 |
|-------------------|-------------------------------------------------------------------------|
| `only:`           | record only these attributes                                            |
| `ignore:`         | leave these attributes out; updates touching only them record nothing  |
| `redact:`         | names/Regexps (Array), or a Hash of name/Regexp => strategy (see below) |
| `on:`             | any of `:create`, `:update`, `:destroy` (default: all three), `:touch`  |
| `meta:`           | Hash of metadata: static values, Symbols (record methods) or Procs      |
| `bulk:`           | record bulk operations on this model (default: `true`)                  |
| `if:` / `unless:` | standard Active Record callback conditions (callbacks only)            |

### Redaction

Redacted attributes still show *that* they changed, but not their value. `nil`
stays `nil`, so you can still see when a value was first set or removed.

By default SealedTrail redacts attributes whose names match:

- `password` / `passwd` (including `password_digest`)
- `token`, `secret`, `api_key`, `private_key`
- `otp_*`, `*salt`, `encrypted_*`
- `email`, `*_email`, `phone`, `*_phone`, `mobile` (and `*_address` / `*_number` forms)
- any attribute declared with Rails' `encrypts`

Strategies:

| strategy       | stored as                         | use it for                                    |
|----------------|-----------------------------------|-----------------------------------------------|
| `:redact`      | `"[REDACTED]"` (default)          | secrets                                       |
| `:fingerprint` | `"hmac:3f2a…"` (HMAC-SHA256)      | emails and identifiers you need to look up    |
| `:mask`        | `"j***@example.com"`, `"******1234"` | phone and card numbers a human must recognise |
| callable       | whatever `->(value, attribute) { }` returns | anything else                        |
| `false`        | the plain value                   | opting a model out of a global rule           |

```ruby
class Customer < ApplicationRecord
  has_sealed_trail redact: { email: :fingerprint, phone: :mask, newsletter_email: false }
end

# Global default strategy, and global rules with their own strategy:
SealedTrail.configure do |config|
  config.redaction_strategy = :redact
  config.redact_attributes += [{ national_id: :fingerprint }]
end
```

Fingerprints are keyed, so equal values produce equal fingerprints without
revealing the value. Find entries for a value with:

```ruby
SealedTrail::Entry.with_fingerprint("jane@example.com")
SealedTrail.fingerprint("jane@example.com")  # => "hmac:…"
```

The key defaults to one derived from `secret_key_base`; set
`config.fingerprint_secret` to manage it separately. Changing the key changes
all future fingerprints. Values are hashed exactly as stored, so normalise them
(e.g. downcase emails) in your model if you want case-insensitive matches.
Masking keeps the first character of an email's local part and the domain, or
the last four characters of values of 8+ characters; shorter values are fully
masked.

### Who made the change (the actor)

In controllers, SealedTrail records `current_user` automatically. The actor is
looked up lazily, the first time something is recorded in the request, so it
works even if your authentication runs in a later `before_action`. The request
id and remote IP are captured too.

Every entry gets an actor. When no user is known, SealedTrail records a label
instead, in this order:

1. the explicit actor (`SealedTrail.with_actor`, `SealedTrail::Current.actor`)
2. the request's user (`current_user`)
3. `"anonymous"` in a request with nobody signed in (`config.anonymous_actor`)
4. `"job:<JobClass>"` in an Active Job job that did not inherit an actor
5. `"rake:<task name>"` while a rake task runs, `"console"` in `rails console`
6. `"system"` otherwise (`config.default_actor`; a label, a record or a callable)

Use a different method, or customise it per controller:

```ruby
# config/initializers/sealed_trail.rb
SealedTrail.configure { |config| config.actor_method = :current_admin }

# or in a controller
class Admin::BaseController < ApplicationController
  private

  def sealed_trail_actor
    true_user || current_user  # e.g. record the real admin while impersonating
  end

  def sealed_trail_metadata
    { user_agent: request.user_agent }
  end
end
```

Outside requests you can also set the actor yourself. It can be a record or a
label:

```ruby
SealedTrail.with_actor(user) { invoice.update!(paid: true) }

class NightlyImportJob < ApplicationJob
  def perform
    SealedTrail.with_actor("nightly_import") { Importer.run }
  end
end

# or for the rest of the current request/job
SealedTrail::Current.actor = user
```

Context is stored in `ActiveSupport::CurrentAttributes`, so it is isolated per
thread (or per fiber, if you set Rails' isolation level to `:fiber`) and reset
by Rails after every request and job.

**Background jobs inherit the actor.** When an Active Job job is enqueued, the
current actor (as a GlobalID for records, or the label), request id, remote IP
and metadata are stored with the job and restored while it runs, so changes
made by a job enqueued from a request are attributed to the user who made that
request. If the actor record was deleted in the meantime, its GlobalID string
is recorded as the label. Turn this off with
`config.active_job_integration = false`. Other job systems (e.g. plain Sidekiq
workers) are not integrated; use `with_actor` in them.

### Metadata

Add metadata to everything recorded in a block, for example a reason or ticket
number:

```ruby
SealedTrail.with_metadata(reason: "Support ticket #4521") do
  patient.update!(email: new_email)
end
```

### Pausing tracking

```ruby
SealedTrail.without_tracking do
  Patient.find_each { |p| p.update!(search_index: p.compute_index) }
end
```

`SealedTrail.with_tracking { }` turns it back on inside such a block, and
`config.enabled = false` switches tracking off everywhere.

## Bulk operations

`update_all`, `delete_all`, `insert_all`, `insert_all!` and `upsert_all` on a
tracked model (including `insert`, `upsert`, `Model.delete(id)` and counter
cache updates, which use them) each record **one summary entry**:

```ruby
Patient.where(clinic_id: 7).update_all(status: "archived")

entry = SealedTrail::Entry.bulk.last
entry.event           # "bulk_update" (also "bulk_delete", "bulk_insert", "bulk_upsert")
entry.item_type       # "Patient"
entry.item_id         # "*"
entry.object_changes  # {"status" => [nil, "archived"]}, redacted like any change
entry.bulk_summary
# => {"operation" => "update_all", "row_count" => 42,
#     "ids" => ["3", "8", ...], "ids_truncated" => false,
#     "where_sql" => "`patients`.`clinic_id` = 7"}
```

- **Affected ids** are read just before an update or delete, capped by
  `config.bulk_id_limit` (default 1000, `ids_truncated` tells you when more
  matched; `row_count` is the database's total). For inserts, ids are recorded
  when the database returns them (PostgreSQL, SQLite); on MySQL they are not,
  and `row_count` is unknown, so `attempted_count` gives the number of rows sent.
- **SQL** of the WHERE clause, and of the SET clause for `update_all` with a SQL
  string, is stored with quoted string literals replaced by `'?'`
  (`config.bulk_sql = :masked`). Use `:full` to keep values or `:none` to
  store no SQL. Numeric literals are not masked.
- `update_all` with a Hash that only touches ignored attributes records nothing,
  so add counter cache columns to `ignore:` if you don't want them logged.
- Bulk entries honour `without_tracking`, the actor rules and `on_failure`.
  Turn them off with `config.track_bulk_operations = false` or per model with
  `has_sealed_trail bulk: false`.
- `SealedTrail::Entry.affecting(record)` returns a record's own entries plus the
  bulk entries whose stored ids include it.

## Querying

```ruby
patient.audit_entries                     # this record's entries, oldest first

SealedTrail::Entry.for_item(patient)      # same, as a relation
SealedTrail::Entry.for_item(Patient, 42)  # works after the record is destroyed
SealedTrail::Entry.for_item_type(Patient) # all patients
SealedTrail::Entry.for_actor(user)        # everything a user did
SealedTrail::Entry.for_actor("nightly_import")
SealedTrail::Entry.between(1.month.ago, Time.current)   # either end may be nil
SealedTrail::Entry.events(:update)                      # or events(:create, :destroy)
SealedTrail::Entry.for_request(request_id)              # everything in one request
SealedTrail::Entry.bulk                                 # bulk operation summaries
SealedTrail::Entry.affecting(patient)                   # for_item + bulk entries listing its id
SealedTrail::Entry.with_fingerprint("jane@example.com") # entries storing that fingerprint
SealedTrail::Entry.chronological / .reverse_chronological

# Scopes chain:
SealedTrail::Entry.for_item_type(Patient).events(:update).for_actor(user).between(from, to)
```

Each entry has:

```ruby
entry.event                    # "create", "update", "destroy", "touch" or "bulk_*"
entry.item                     # the record (nil once destroyed)
entry.item_type, entry.item_id # stored as strings, so UUID keys work too
entry.object_changes           # {"attribute" => [before, after]}
entry.change_for(:email)       # ["old@example.com", "new@example.com"]
entry.changed_attribute_names  # ["email", "updated_at"]
entry.actor                    # the actor record, or nil for a label
entry.actor_type, entry.actor_id  # e.g. "User", "42" or nil, "rake:db:seed"
entry.bulk?, entry.bulk_summary, entry.bulk_ids
entry.metadata, entry.request_id, entry.remote_ip, entry.created_at
```

Entries are read-only through Active Record once saved: `update` and `destroy`
raise `ActiveRecord::ReadOnlyRecord`. That prevents accidental edits from
application code, but it is not tamper evidence; anyone with database access
can still change rows.

## Configuration

All settings with their defaults:

```ruby
# config/initializers/sealed_trail.rb
SealedTrail.configure do |config|
  config.enabled = true                      # master switch

  # Redaction
  config.redact_attributes = SealedTrail::Configuration::DEFAULT_REDACT_ATTRIBUTES.dup
  config.redaction_strategy = :redact        # :redact, :fingerprint, :mask or a callable
  config.fingerprint_secret = nil            # nil: derived from secret_key_base
  config.redact_encrypted_attributes = true  # redact `encrypts` attributes
  config.ignore_attributes = []              # left out of every model's entries

  # Failures
  config.on_failure = :log                   # :log, :raise or ->(error, payload) { }
  config.error_handler = nil                 # ->(error, payload) { } in :log mode
  config.logger = nil                        # nil: Rails.logger

  # Actors
  config.actor_method = :current_user        # controller method for the actor
  config.anonymous_actor = "anonymous"       # request with nobody signed in (nil: use default_actor)
  config.default_actor = "system"            # label, record or callable
  config.detect_process_context = true       # "console" and "rake:<task>" labels
  config.active_job_integration = true       # jobs inherit the enqueuing actor
  config.auto_include_controller = true      # include SealedTrail::Controller everywhere

  # Bulk operations
  config.track_bulk_operations = true
  config.bulk_id_limit = 1000                # nil: no limit
  config.bulk_sql = :masked                  # :masked, :full or :none
end
```

With `auto_include_controller = false`, include `SealedTrail::Controller` in the
controllers you want.

## SealedTrail Pro

This gem is the free, MIT-licensed core. **SealedTrail Pro** is a commercial
add-on for teams preparing for audits and customer security reviews. It is
planned to add:

- logging of who **viewed or exported** sensitive records, not only who changed them
- a **tamper-evident hash chain**, so edits or deletions in the trail can be detected
- **retention policies** that keep entries for a set period and then delete them
- **auditor-ready reports** to support evidence for SOC 2, HIPAA, GDPR and India's DPDP rules

Details and early access: <https://steadybytehq.github.io/sealedtrail/>

## Limitations

- **Hand-written SQL is not captured.** Anything run with
  `connection.execute`, `exec_update` or similar, outside Active Record's
  model and relation methods, bypasses SealedTrail; capturing it would need
  database triggers. The same applies to changes made directly in the database.
- Bulk entries store a capped list of affected ids read just before the
  operation (not atomically with it), not per-row before/after values. Inserts
  record the columns written, not the values. `Entry.affecting` finds bulk
  entries by searching the stored ids, so it misses ids beyond
  `bulk_id_limit` and inserts on MySQL, and in rare cases can match a bulk
  entry whose metadata happens to contain the same string.
- `if:` / `unless:` apply to callbacks only, not to `update_columns`, `delete`,
  `touch` or bulk operations.
- Models with composite primary keys are not supported yet.
- For STI models, `item_type` is the base class; the subclass appears in the
  `type` attribute of create entries.
- Supported databases are PostgreSQL, MySQL 8+ and SQLite.

## Development

```sh
bundle install
bundle exec rake test                 # SQLite
DB=postgresql bundle exec rake test   # PostgreSQL (uses PGHOST/PGUSER/PGPASSWORD)
DB=mysql2 bundle exec rake test       # MySQL via mysql2 (MYSQL_HOST/MYSQL_USER/MYSQL_PASSWORD)
DB=trilogy bundle exec rake test      # MySQL via trilogy
BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle install && \
  BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle exec rake test
bundle exec rubocop
```

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Steadybyte.
