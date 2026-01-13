# frozen_string_literal: true

class Tagging < ActiveRecord::Base
  belongs_to :post
  belongs_to :tag
end
