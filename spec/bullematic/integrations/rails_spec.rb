# frozen_string_literal: true

RSpec.describe Bullematic::Middleware do
  let(:env) { { "PATH_INFO" => "/posts" } }

  before do
    allow(Bullematic).to receive(:enabled?).and_return(true)
    allow(Bullematic::EvidenceStore).to receive(:recording?).and_return(true)
    allow(Bullet).to receive(:notification?).and_return(true)
    allow(Bullematic::Notifier).to receive(:process_notifications)
  end

  it "captures notifications before returning control to Bullet middleware" do
    body = ["ok"]
    response = described_class.new(->(_env) { [200, {}, body] }).call(env)

    expect(Bullematic::Notifier).to have_received(:process_notifications).with(context_id: env.object_id).once
    expect(response).to eq([200, {}, body])
  end

  it "accepts a frozen Rack response triple" do
    response = described_class.new(->(_env) { [200, {}, ["ok"]].freeze }).call(env)

    expect(response.first).to eq(200)
    expect(response[2]).to eq(["ok"])
  end

  it "captures notifications when the application raises" do
    expect(Bullematic::Notifier).to receive(:process_notifications).with(context_id: env.object_id).once
    middleware = described_class.new(->(_env) { raise "boom" })

    expect { middleware.call(env) }.to raise_error("boom")
  end

  it "preserves the application error when notification capture fails" do
    allow(Bullematic::Notifier).to receive(:process_notifications).and_call_original
    allow(Bullet).to receive(:notification?).and_raise("collector failed")
    middleware = described_class.new(->(_env) { raise "application failed" })

    expect { middleware.call(env) }.to raise_error("application failed")
  end

  it "does not retain request detections without a recording sink" do
    allow(Bullematic::EvidenceStore).to receive(:recording?).and_return(false)
    described_class.new(->(_env) { [200, {}, ["ok"]] }).call(env)

    expect(Bullematic::Notifier).not_to have_received(:process_notifications)
  end

  it "runs before Bullet clears its request collector" do
    events = []
    allow(Bullet).to receive(:enable?).and_return(true)
    allow(Bullet).to receive(:start_request)
    allow(Bullet).to receive(:notification?).and_return(false)
    allow(Bullet).to receive(:always_append_html_body).and_return(false) if Bullet.respond_to?(:always_append_html_body)
    allow(Bullet).to receive(:end_request) { events << :bullet_end }
    allow(Bullematic::Notifier).to receive(:process_notifications) { events << :capture }
    stack = Bullet::Rack.new(described_class.new(->(_env) { [200, {}, ["ok"]] }))

    stack.call(env)

    expect(events).to eq(%i[capture bullet_end])
  end

  it "is inserted after Bullet in the Rails middleware stack" do
    initializer = Bullematic::Integrations::Railtie.initializers.find do |item|
      item.name == "bullematic.middleware"
    end
    middleware = double
    app = double(middleware: middleware)
    allow(Rails.env).to receive(:development?).and_return(true)
    expect(middleware).to receive(:insert_after).with(Bullet::Rack, Bullematic::Middleware)

    bullet_initializer = Bullet::BulletRailtie.initializers.find { |item| item.name.start_with?("bullet.") }
    expect(initializer.after).to eq(bullet_initializer.name)
    initializer.run(app)
  end
end
