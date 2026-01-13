# frozen_string_literal: true

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments, dependent: :destroy
end
