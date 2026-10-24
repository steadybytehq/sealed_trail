# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
  end

  create_table :posts, force: true do |t|
    t.string :title
    t.text :body
    t.string :status, default: "draft"
    t.integer :views_count, default: 0
    t.references :user
    t.timestamps
  end

  create_table :articles, force: true do |t|
    t.string :title
    t.text :body
    t.string :slug
    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.text :body
    t.integer :likes, default: 0
    t.timestamps
  end

  create_table :accounts, force: true do |t|
    t.string :name
    t.string :email
    t.string :password_digest
    t.string :api_token
    t.string :client_secret
    t.string :encrypted_card_number
    t.string :pin
    t.string :ssn_last4
    t.text :notes
    t.timestamps
  end

  create_table :invoices, force: true do |t|
    t.string :number
    t.integer :amount_cents
    t.boolean :draft, default: false
    t.timestamps
  end

  create_table :documents, id: :string, force: true do |t|
    t.string :title
    t.timestamps
  end

  create_table :vehicles, force: true do |t|
    t.string :type
    t.string :name
    t.timestamps
  end
end
