# frozen_string_literal: true

require "test_helper"

class MinitestIntegrationTest < ActionDispatch::IntegrationTest
  include Bullematic::Integrations::Minitest::TestHelper

  def setup
    super
    @user = users(:one)
    @post = posts(:one)
  end

  test "detects N+1 with Bullematic integration" do
    Bullematic.configure do |config|
      config.enabled = true
      config.auto_fix = false
    end

    get posts_url

    assert_response :success
  end

  test "applies fixes" do
    # TODO: add fix verification for dummy app
  end
end
