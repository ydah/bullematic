# frozen_string_literal: true

RSpec.describe Bullematic::Notifier do
  before { Bullematic::Fixer.clear }
  after { Bullematic.reset! }

  it "matches Bullet's N+1 notification constructor contract" do
    parameters = Bullet::Notification::NPlusOneQuery.instance_method(:initialize).parameters

    expect(parameters.first(3)).to eq([[:req, :callers], [:req, :base_class], [:req, :associations]])
  end

  it "fails closed when Bullet's private collector API is unavailable" do
    allow(Bullet).to receive(:respond_to?).and_call_original
    allow(Bullet).to receive(:respond_to?).with(:notification_collector, true).and_return(false)

    expect(described_class.compatible?).to be false
    expect { described_class.process_notifications }.not_to raise_error
  end

  it "fails closed when Bullet's collector shape changes" do
    collector = Struct.new(:collection).new({ unexpected: Object.new })
    allow(Bullet).to receive(:notification?).and_return(true)
    allow(Bullet).to receive(:notification_collector).and_return(collector)

    expect { described_class.process_notifications }.not_to raise_error
  end

  it "fails closed when Bullet's collector raises" do
    Bullematic.configure
    allow(Bullet).to receive(:notification?).and_raise("collector failed")

    expect(Bullematic.configuration.logger).to receive(:warn).with(
      "[Bullematic] Failed to process Bullet notifications: collector failed"
    )
    expect { described_class.process_notifications }.not_to raise_error
  end

  it "fails closed when reporting a collector failure also raises" do
    logger = instance_double(Logger)
    Bullematic.configure { |config| config.logger = logger }
    allow(Bullet).to receive(:notification?).and_raise("collector failed")
    allow(logger).to receive(:warn).and_raise("logger failed")

    expect { described_class.process_notifications }.not_to raise_error
  end

  it "captures the notification fields without shifting arguments" do
    Dir.mktmpdir do |directory|
      filepath = File.join(directory, "posts.rb")
      FileUtils.touch(filepath)
      Bullematic.configure { |config| config.target_paths = [directory] }
      notification = Bullet::Notification::NPlusOneQuery.new(
        ["#{filepath}:1:in 'index'"],
        "Post",
        [:comments]
      )

      described_class.send(:process_n_plus_one, notification, "example")

      detection = Bullematic::Fixer.detection_queue.fetch(0)
      expect([detection.model_class_name, detection.associations, detection.method_name]).to eq(
        ["Post", [:comments], "index"]
      )
    end
  end

  it "does not guess callers from an unrelated Bullet registry entry" do
    Dir.mktmpdir do |directory|
      filepath = File.join(directory, "posts.rb")
      FileUtils.touch(filepath)
      Bullematic.configure { |config| config.target_paths = [directory] }
      notification = Bullet::Notification::NPlusOneQuery.allocate
      allow(notification).to receive(:base_class).and_return("Post")
      allow(notification).to receive(:associations).and_return([:comments])
      call_stacks = Struct.new(:registry).new({ unrelated: ["#{filepath}:1:in 'index'"] })
      allow(Bullet::Detector::Association).to receive(:send).and_call_original
      allow(Bullet::Detector::Association).to receive(:send).with(:call_stacks).and_return(call_stacks)

      described_class.send(:process_n_plus_one, notification, "example")

      expect(Bullematic::Fixer.detection_queue).to be_empty
    end
  end
end
