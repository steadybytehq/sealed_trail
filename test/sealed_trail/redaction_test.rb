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
      notes: "private note"
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
    assert_equal [ nil, "ops@acme.test" ], entry.change_for(:email)
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
    SealedTrail.configure { |config| config.redact_attributes += [ :email ] }
    create_account

    assert_equal [ nil, "[REDACTED]" ], last_entry.change_for(:email)
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

    %w[tok_123 shh pin-x9 ssn-z7 private\ note $2a$12$abc].each do |secret|
      assert_not_includes raw, secret
    end
  end
end
