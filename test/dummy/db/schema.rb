# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.string :title
    t.text :body
    t.references :user, foreign_key: true
    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.text :body
    t.references :post, foreign_key: true
    t.references :user, foreign_key: true
    t.timestamps
  end
end
