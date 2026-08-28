# rbs_inline: enabled
# frozen_string_literal: true

require "fileutils"
require "json"

module Bullematic
  class EvidenceStore
    ENV_KEY = "BULLEMATIC_RECORD_FILE"
    DEFAULT_PATH = ".bullematic/evidence.jsonl"

    class << self
      #: () -> bool
      def recording?
        !ENV[ENV_KEY].to_s.empty?
      end

      #: () -> String
      def path
        File.expand_path(ENV.fetch(ENV_KEY, DEFAULT_PATH))
      end

      # @rbs detection: Detection
      # @rbs filepath: String
      # @rbs return: void
      def append(detection, filepath = path)
        FileUtils.mkdir_p(File.dirname(filepath))
        File.open(filepath, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
          file.flock(File::LOCK_EX)
          file.puts(JSON.generate(detection.to_h))
        end
      end

      # @rbs filepath: String
      # @rbs return: void
      def clear(filepath = path)
        FileUtils.mkdir_p(File.dirname(filepath))
        File.open(filepath, File::WRONLY | File::CREAT | File::TRUNC, 0o600) {}
      end

      # @rbs filepath: String
      # @rbs return: Array[Detection]
      def read(filepath = path)
        return [] unless File.file?(filepath)

        detections = File.foreach(filepath).filter_map do |line|
          next if line.strip.empty?

          Detection.from_h(JSON.parse(line))
        end
        detections.uniq(&:fingerprint)
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
        raise Error, "invalid evidence file #{filepath}: #{error.message}"
      end
    end
  end
end
