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
        reject_symlink!(filepath)
        open_evidence(filepath, File::WRONLY | File::CREAT | File::APPEND) do |file|
          file.flock(File::LOCK_EX)
          file.puts(JSON.generate(detection.to_h))
        end
      end

      # @rbs filepath: String
      # @rbs return: void
      def clear(filepath = path)
        FileUtils.mkdir_p(File.dirname(filepath))
        reject_symlink!(filepath)
        open_evidence(filepath, File::WRONLY | File::CREAT | File::TRUNC) {}
      end

      # @rbs filepath: String
      # @rbs return: Array[Detection]
      def read(filepath = path)
        reject_symlink!(filepath)
        return [] unless File.file?(filepath)

        detections = open_evidence(filepath, File::RDONLY) do |file|
          file.each_line.filter_map do |line|
            next if line.strip.empty?

            Detection.from_h(JSON.parse(line))
          end
        end
        detections.uniq(&:fingerprint)
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
        raise Error, "invalid evidence file #{filepath}: #{error.message}"
      end

      private

      # @rbs filepath: String
      # @rbs return: void
      def reject_symlink!(filepath)
        raise Error, "symlink evidence files are unsupported" if File.symlink?(filepath)
      end

      #: (String, Integer) { (File) -> untyped } -> untyped
      def open_evidence(filepath, flags, &block)
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(filepath, flags, 0o600, &block)
      rescue Errno::ELOOP
        raise Error, "symlink evidence files are unsupported"
      end
    end
  end
end
