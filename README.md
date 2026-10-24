# SealedTrail

[![CI](https://github.com/steadybytehq/sealed_trail/actions/workflows/ci.yml/badge.svg)](https://github.com/steadybytehq/sealed_trail/actions/workflows/ci.yml)

**An audit trail for Rails: who changed what, when, and from where.**

SealedTrail records every create, update and destroy on the Active Record models
you choose: the before and after values, the user (or job, or script) that made
the change, the time, the request id and the IP address. Passwords, tokens,
secrets and encrypted attributes are redacted by default.

```ruby
class Patient < ApplicationRecord
  has_sealed_trail
end

patient.update!(phone: "+1 555 0100")

patient.audit_entries.last
# => #<SealedTrail::Entry event: "update",
#      object_changes: {"phone" => ["+1 555 0199", "+1 555 0100"], "updated_at" => [...]},
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
- PostgreSQL or SQLite

## Installation

Add the gem and run the installer:

```sh
bundle add sealed_trail
bin/rails generate sealed_trail:install
bin/rails db:migrate
```

The installer creates:

- a migration for the single `sealed_trail_entries` table (`jsonb` columns on
  PostgreSQL, `json` elsewhere; force one with `--json-type=json|jsonb`)
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
database transaction as the change: if the change rolls back, so does the
entry, and if the entry cannot be written, the change is rolled back rather
than left unaudited.

### Options

```ruby
class Patient < ApplicationRecord
  has_sealed_trail(
    ignore: [:last_seen_at],        # never record these attributes
    redact: [:ssn, /\Adiagnosis/],  # record that they changed, hide the values
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
| `redact:`         | attribute names or Regexps whose values are stored as `"[REDACTED]"`    |
| `on:`             | any of `:create`, `:update`, `:destroy` (default: all three)            |
| `meta:`           | Hash of metadata: static values, Symbols (record methods) or Procs      |
| `if:` / `unless:` | standard Active Record callback conditions                              |

### Redaction

Values are replaced with `"[REDACTED]"`, so the trail still shows *that* a
sensitive attribute changed, but not its value. `nil` stays `nil`, so you can
still see when a value was first set or removed.

By default SealedTrail redacts attributes whose names match:

- `password` / `passwd` (including `password_digest`)
- `token`, `secret`, `api_key`, `private_key`
- `otp_*`, `*salt`, `encrypted_*`
- any attribute declared with Rails' `encrypts`

### Who made the change (the actor)

In controllers, SealedTrail records `current_user` automatically. The actor is
looked up lazily, the first time something is recorded in the request, so it
works even if your authentication runs in a later `before_action`. The request
id and remote IP are captured too.

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

Outside requests (jobs, rake tasks, the console), set the actor yourself. It can
be a record or a label:

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
by Rails after every request and job. It is **not** copied into background jobs
automatically; pass the actor to the job and use `with_actor`.

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
SealedTrail::Entry.chronological / .reverse_chronological

# Scopes chain:
SealedTrail::Entry.for_item_type(Patient).events(:update).for_actor(user).between(from, to)
```

Each entry has:

```ruby
entry.event                    # "create", "update" or "destroy"
entry.item                     # the record (nil once destroyed)
entry.item_type, entry.item_id # stored as strings, so UUID keys work too
entry.object_changes           # {"attribute" => [before, after]}
entry.change_for(:email)       # ["old@example.com", "new@example.com"]
entry.changed_attribute_names  # ["email", "updated_at"]
entry.actor                    # the actor record, or nil for a label
entry.actor_type, entry.actor_id
entry.metadata, entry.request_id, entry.remote_ip, entry.created_at
```

Entries are read-only through Active Record once saved: `update` and `destroy`
raise `ActiveRecord::ReadOnlyRecord`. That prevents accidental edits from
application code, but it is not tamper evidence; anyone with database access
can still change rows.

## Configuration

```ruby
# config/initializers/sealed_trail.rb
SealedTrail.configure do |config|
  config.enabled = true                          # master switch
  config.redact_attributes += [:ssn, /\Aiban/]   # Strings match exactly, Regexps anywhere
  config.redact_encrypted_attributes = true      # redact `encrypts` attributes
  config.ignore_attributes = [:updated_at]       # left out of every model's entries
  config.actor_method = :current_user            # controller method for the actor
  config.auto_include_controller = true          # include SealedTrail::Controller everywhere
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

- Records changes made through Active Record callbacks. `update_all`,
  `delete_all`, `update_column(s)`, `insert_all`/`upsert_all` and raw SQL are not
  recorded, and `touch` is not recorded.
- Models with composite primary keys are not supported yet.
- For STI models, `item_type` is the base class; the subclass appears in the
  `type` attribute of create entries.
- Tested on PostgreSQL and SQLite only.

## Development

```sh
bundle install
bundle exec rake test                 # SQLite
DB=postgresql bundle exec rake test   # PostgreSQL (uses PGHOST/PGUSER/PGPASSWORD)
BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle install && \
  BUNDLE_GEMFILE=gemfiles/rails_7_1.gemfile bundle exec rake test
bundle exec rubocop
```

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Steadybyte.
