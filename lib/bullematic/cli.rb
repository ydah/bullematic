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
        raise Error, "no recorded N+1 evidence in #{EvidenceStore.path}" if detections.empty?

        record_file = ENV.delete(EvidenceStore::ENV_KEY)
        begin
          detections.each { |detection| Fixer.queue(detection) }
        ensure
          ENV[EvidenceStore::ENV_KEY] = record_file if record_file
        end
        stats = Fixer.apply_fixes
        operation = dry_run ? :planned : :fixed
        raise Error, "#{stats[:errors]} error(s) while applying fixes" if stats[:errors].positive?
        raise Error, "no safe fixes were #{operation}" if stats[operation].zero?

        0
      end

      # @rbs argv: Array[String]
      # @rbs return: Integer
      def fix(argv)
        separator = argv.index("--") || argv.length
        verify_index = argv.first(separator).index("--verify")
        verify_after = argv.delete_at(verify_index) if verify_index
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
        original = EvidenceStore.read.select { |detection| detection.type == :n_plus_one }
        raise Error, "no recorded N+1 evidence in #{EvidenceStore.path}" if original.empty?

        command = read_command(EvidenceStore.path) if command.empty?
        raise Error, "verify requires a recorded command" if command.empty?

        Tempfile.create(["bullematic-verify", ".jsonl"]) do |file|
          file.close
          status = run_command(command, file.path)
          return status unless status.zero?

          remaining = EvidenceStore.read(file.path).count { |detection| detection.type == :n_plus_one }
          raise Error, "#{remaining} N+1 warning(s) remain" unless remaining.zero?
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
        path = "#{evidence_path}.command.json"
        raise Error, "symlink command files are unsupported" if File.symlink?(path)

        open_command(path, File::WRONLY | File::CREAT | File::TRUNC) do |file|
          file.chmod(0o600)
          file.write(JSON.generate(command))
        end
      end

      # @rbs evidence_path: String
      # @rbs return: Array[String]
      def read_command(evidence_path)
        path = "#{evidence_path}.command.json"
        raise Error, "symlink command files are unsupported" if File.symlink?(path)
        return [] unless File.file?(path)

        value = open_command(path, File::RDONLY) { |file| JSON.parse(file.read) }
        value.is_a?(Array) && value.all?(String) ? value : []
      end

      #: (String, Integer) { (File) -> untyped } -> untyped
      def open_command(path, flags, &block)
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags, 0o600, &block)
      rescue Errno::ELOOP
        raise Error, "symlink command files are unsupported"
      end

    end
  end
end
