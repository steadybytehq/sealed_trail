# frozen_string_literal: true

require "test_helper"

class RedactionTest < ActiveSupport::TestCase
  def create_account(**attrs)
    Account.create!({
      name: "Acme",
      email: "ops@acme.test",
      password_digest: "$2a$12$abc",
      api_token: "tok_123",
      client_secret: "shh",
      encrypted_card_number: "enc",
      pin: "pin-x9",
      ssn_last4: "ssn-z7",
      notes: "private note",
      billing_email: "billing@acme.test",
      phone: "+1 555 0100",
      work_phone: "+1 555 0101",
      mobile: "+91 98765 43210",
      email_verified: true
    }.merge(attrs))
  end

  test "redacts password, token, secret and encrypted_* attributes by default" do
    create_account
    entry = last_entry

    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:password_digest)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:api_token)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:client_secret)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:encrypted_card_number)
    assert_equal [ nil, "Acme" ], entry.change_for(:name)
  end

  test "redacts email and phone-like attributes by default" do
    create_account
    entry = last_entry

    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:email)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:billing_email)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:phone)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:work_phone)
    assert_equal [ nil, "[REDACTED]" ], entry.change_for(:mobile)
    assert_equal [ nil, true ], entry.change_for(:email_verified), "only the value fields are matched"
  end

  test "redact: adds per-model attributes and patterns" do
    create_account

    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:pin)
    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:ssn_last4)
  end

  test "redacts attributes declared with encrypts" do
    create_account

    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:notes)
  end

  test "encrypted attributes can be left unredacted" do
    SealedTrail.config.redact_encrypted_attributes = false
    create_account

    assert_equal [ nil, "private note" ], last_entry.change_for(:notes)
  end

  test "records that a redacted attribute changed on update, without values" do
    account = create_account
    account.update!(api_token: "tok_456")

    assert_equal [ "[REDACTED]", "[REDACTED]" ], last_entry.change_for(:api_token)
  end

  test "keeps nil as nil so additions and removals stay visible" do
    account = create_account(api_token: nil)

    assert_nil last_entry.change_for(:api_token)

    account.update!(api_token: "new")
    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:api_token)

    account.update!(api_token: nil)
    assert_equal [ "[REDACTED]", nil ], last_entry.change_for(:api_token)
  end

  test "redacts destroyed values" do
    account = create_account
    account.destroy!

    assert_equal [ "[REDACTED]", nil ], last_entry.change_for(:password_digest)
    assert_equal [ "Acme", nil ], last_entry.change_for(:name)
  end

  test "global redaction rules are configurable" do
    SealedTrail.configure { |config| config.redact_attributes += [ :name ] }
    create_account

    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:name)
  end

  test "global redaction rules can be replaced" do
    SealedTrail.config.redact_attributes = []
    create_account

    assert_equal [ nil, "tok_123" ], last_entry.change_for(:api_token)
    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:pin), "per-model rules still apply"
  end

  test "redacted plaintext never reaches the database" do
    create_account
    raw = SealedTrail::Entry.where(id: last_entry.id).pick(:object_changes).to_json

    %w[tok_123 shh pin-x9 ssn-z7 private\ note $2a$12$abc ops@acme.test 555\ 0100 98765].each do |secret|
      assert_not_includes raw, secret
    end
  end

  test "the :fingerprint strategy stores a keyed hash that matches equal values" do
    Customer.create!(name: "A", email: "jane@example.com")
    first = last_entry.change_for(:email).last
    Customer.create!(name: "B", email: "jane@example.com")
    second = last_entry.change_for(:email).last

    assert_match(/\Ahmac:\h{64}\z/, first)
    assert_equal first, second
    assert_equal SealedTrail.fingerprint("jane@example.com"), first
    assert_not_equal SealedTrail.fingerprint("other@example.com"), first
  end

  test "Entry.with_fingerprint finds entries for a value without storing it" do
    Customer.create!(name: "A", email: "jane@example.com")
    Customer.create!(name: "B", email: "bob@example.com")

    assert_equal 1, SealedTrail::Entry.with_fingerprint("jane@example.com").count
    assert_equal 0, SealedTrail::Entry.with_fingerprint("nobody@example.com").count
  end

  test "the fingerprint secret is derived from secret_key_base and configurable" do
    derived = SealedTrail.fingerprint("x")
    SealedTrail.config.fingerprint_secret = "another-secret"

    assert_not_equal derived, SealedTrail.fingerprint("x")
    assert_equal "hmac:#{OpenSSL::HMAC.hexdigest("SHA256", "another-secret", "x")}", SealedTrail.fingerprint("x")
  end

  test "the :mask strategy keeps a hint of the value" do
    Customer.create!(name: "A", email: "jane@example.com", phone: "+1 555 0100", card_number: "4242424242424242")

    assert_equal [ nil, "*******0100" ], last_entry.change_for(:phone)
    assert_equal [ nil, "************4242" ], last_entry.change_for(:card_number)
  end

  test "mask handles emails, short values and non-strings" do
    assert_equal "j***@example.com", SealedTrail::Redactor.mask("jane@example.com")
    assert_equal "******1234", SealedTrail::Redactor.mask("9876541234")
    assert_equal "*****", SealedTrail::Redactor.mask("12345")
    assert_equal "*****6789", SealedTrail::Redactor.mask(123_456_789)
  end

  test "a callable strategy and false (opt out of a global rule) are supported" do
    Customer.create!(name: "A", nickname: "jj", mobile: "+91 98765 43210", api_token: "tok")

    assert_equal [ nil, "JJ" ], last_entry.change_for(:nickname)
    assert_equal [ nil, "+91 98765 43210" ], last_entry.change_for(:mobile)
    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:api_token)
  end

  test "nil stays nil with every strategy" do
    customer = Customer.create!(name: "A", email: "jane@example.com", phone: "+1 555 0100")
    customer.update!(email: nil, phone: nil)

    assert_nil last_entry.change_for(:email).last
    assert_nil last_entry.change_for(:phone).last
    assert_match(/\Ahmac:/, last_entry.change_for(:email).first)
  end

  test "config.redaction_strategy changes the default strategy" do
    SealedTrail.config.redaction_strategy = :mask
    create_account

    assert_equal [ nil, "o***@acme.test" ], last_entry.change_for(:email)
    assert_equal [ nil, "*******0100" ], last_entry.change_for(:phone)
  end

  test "global rules can name a strategy with a Hash" do
    SealedTrail.config.redact_attributes = [ { email: :fingerprint }, /token/ ]
    create_account

    assert_match(/\Ahmac:/, last_entry.change_for(:email).last)
    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:api_token)
    assert_equal [ nil, "+1 555 0100" ], last_entry.change_for(:phone)
  end

  test "unknown strategies are rejected when the model is declared" do
    klass = Class.new(ActiveRecord::Base) { self.table_name = "customers" }

    assert_raises(ArgumentError) { klass.has_sealed_trail(redact: { email: :scramble }) }
  end
end
