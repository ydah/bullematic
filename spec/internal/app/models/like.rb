# frozen_string_literal: true

class Like < ActiveRecord::Base
  belongs_to :comment
  belongs_to :user
end
