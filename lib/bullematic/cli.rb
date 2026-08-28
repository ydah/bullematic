# rbs_inline: enabled
# frozen_string_literal: true

require "json"
require "tempfile"

module Bullematic
  class CLI
    class << self
      # @rbs argv: Array[String]
      # @rbs return: Integer
      def run(argv)
        command = argv.shift
        case command
        when "record" then record(command_args(argv))
        when "plan" then apply(dry_run: true)
        when "apply" then apply(dry_run: false)
        when "verify" then verify(command_args(argv))
        when "fix" then fix(argv)
        when "doctor" then doctor
        else
          warn "Usage: bullematic record -- COMMAND | plan | apply | verify [-- COMMAND] | fix [--verify] -- COMMAND | doctor"
          1
        end
      rescue Error, SystemCallError, JSON::ParserError => error
        warn "bullematic: #{error.message}"
        1
      end

      private

      # @rbs argv: Array[String]
      # @rbs return: Array[String]
      def command_args(argv)
        argv = argv.dup
        argv.shift if argv.first == "--"
        argv
      end

      # @rbs command: Array[String]
      # @rbs return: Integer
      def record(command)
        raise Error, "record requires a command" if command.empty?

        evidence_path = EvidenceStore.path
        EvidenceStore.clear(evidence_path)
        write_command(evidence_path, command)
        run_command(command, evidence_path)
      end

      # @rbs dry_run: bool
      # @rbs return: Integer
      def apply(dry_run:)
        load_application
        configure(dry_run)
        detections = EvidenceStore.read.select { |detection| detection.type == :n_plus_one }
        raise Error, "no recorded evidence in #{EvidenceStore.path}" if detections.empty?

        record_file = ENV.delete(EvidenceStore::ENV_KEY)
        begin
          detections.each { |detection| Fixer.queue(detection) }
        ensure
          ENV[EvidenceStore::ENV_KEY] = record_file if record_file
        end
        Fixer.apply_fixes
        0
      end

      # @rbs argv: Array[String]
      # @rbs return: Integer
      def fix(argv)
        verify_after = argv.delete("--verify")
        command = command_args(argv)
        status = record(command)
        return status unless status.zero?

        status = apply(dry_run: false)
        return status unless status.zero? && verify_after

        verify(command)
      end

      # @rbs command: Array[String]
      # @rbs return: Integer
      def verify(command)
        load_application
        configure(true)
        original = EvidenceStore.read
        raise Error, "no recorded evidence in #{EvidenceStore.path}" if original.empty?

        command = read_command(EvidenceStore.path) if command.empty?
        raise Error, "verify requires a recorded command" if command.empty?

        Tempfile.create(["bullematic-verify", ".jsonl"]) do |file|
          file.close
          status = run_command(command, file.path)
          return status unless status.zero?

          remaining = EvidenceStore.read(file.path)
          raise Error, "#{remaining.size} Bullet warning(s) remain" unless remaining.empty?
        end

        puts "Bullematic verification passed"
        0
      end

      #: () -> Integer
      def doctor
        require "bullet"
        require "prism"
        raise Error, "unsupported Bullet notification API" unless Notifier.compatible?

        bullet_spec = Gem.loaded_specs.fetch("bullet") #: untyped
        prism_spec = Gem.loaded_specs.fetch("prism") #: untyped
        bullet_version = bullet_spec.version
        prism_version = prism_spec.version
        puts "Bullematic #{VERSION}; Bullet #{bullet_version}; Prism #{prism_version}: compatible"
        0
      end

      # @rbs command: Array[String]
      # @rbs evidence_path: String
      # @rbs return: Integer
      def run_command(command, evidence_path)
        environment = { "BULLEMATIC" => "1", EvidenceStore::ENV_KEY => evidence_path }
        system(environment, *command) ? 0 : ($?&.exitstatus || 1)
      end

      #: () -> void
      def load_application
        environment = File.expand_path("config/environment.rb")
        require environment if File.file?(environment)
      end

      # @rbs dry_run: bool
      # @rbs return: void
      def configure(dry_run)
        Bullematic.configure do |config|
          config.auto_fix = true
          config.dry_run = dry_run
          config.backup = true
        end
      end

      # @rbs evidence_path: String
      # @rbs command: Array[String]
      # @rbs return: void
      def write_command(evidence_path, command)
        File.binwrite("#{evidence_path}.command.json", JSON.generate(command))
      end

      # @rbs evidence_path: String
      # @rbs return: Array[String]
      def read_command(evidence_path)
        path = "#{evidence_path}.command.json"
        return [] unless File.file?(path)

        value = JSON.parse(File.binread(path))
        value.is_a?(Array) && value.all?(String) ? value : []
      end

    end
  end
end
