# frozen_string_literal: true

module FileHelpers
  def with_temp_file(content, filename: "test.rb")
    Dir.mktmpdir do |dir|
      filepath = File.join(dir, filename)
      File.write(filepath, content)
      yield filepath
    end
  end

  def read_fixture(name)
    File.read(File.join(__dir__, "..", "fixtures", name))
  end

  def compare_source(actual, expected)
    normalize(actual) == normalize(expected)
  end

  private

  def normalize(source)
    source.gsub(/\s+/, " ").strip
  end
end

RSpec.configure do |config|
  config.include FileHelpers
end
