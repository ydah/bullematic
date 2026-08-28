# frozen_string_literal: true

RSpec.describe Bullematic::Middleware do
  let(:env) { { "PATH_INFO" => "/posts" } }

  before do
    allow(Bullematic).to receive(:enabled?).and_return(true)
    allow(Bullet).to receive(:notification?).and_return(true)
    allow(Bullematic::Notifier).to receive(:process_notifications)
  end

  it "captures notifications after a lazy response body closes" do
    body = ["ok"]
    response = described_class.new(->(_env) { [200, {}, body] }).call(env)

    expect(Bullematic::Notifier).not_to have_received(:process_notifications)

    response[2].close

    expect(Bullematic::Notifier).to have_received(:process_notifications).with(context_id: env.object_id).once
  end

  it "accepts a frozen Rack response triple" do
    response = described_class.new(->(_env) { [200, {}, ["ok"]].freeze }).call(env)

    expect(response.first).to eq(200)
    expect { response[2].close }.not_to raise_error
  end

  it "captures notifications when the application raises" do
    expect(Bullematic::Notifier).to receive(:process_notifications).with(context_id: env.object_id).once
    middleware = described_class.new(->(_env) { raise "boom" })

    expect { middleware.call(env) }.to raise_error("boom")
  end
end
