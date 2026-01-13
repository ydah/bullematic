# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
  end

  factory :post do
    sequence(:title) { |n| "Post #{n}" }
    body { "This is the post body" }
    published { true }
    association :user
  end

  factory :comment do
    body { "This is a comment" }
    association :post
    association :user
  end

  factory :like do
    association :comment
    association :user
  end

  factory :tag do
    sequence(:name) { |n| "Tag #{n}" }
  end

  factory :tagging do
    association :post
    association :tag
  end
end
