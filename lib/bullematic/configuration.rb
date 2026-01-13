# rbs_inline: enabled
# frozen_string_literal: true

require "logger"

module Bullematic
  class Configuration
    # @rbs skip: to avoid empty array warning
    DEFAULTS = { #: Hash[Symbol, untyped]
      enabled: true,
      auto_fix: true,
      target_paths: %w[app/controllers app/models app/services],
      skip_paths: [],
      dry_run: false,
      backup: false,
      fix_strategy: :includes,
      logger: nil,
      debug: false
    }.freeze

    # @rbs @enabled: bool
    # @rbs @auto_fix: bool
    # @rbs @target_paths: Array[String]
    # @rbs @skip_paths: Array[String]
    # @rbs @dry_run: bool
    # @rbs @backup: bool
    # @rbs @fix_strategy: Symbol
    # @rbs @debug: bool
    # @rbs @logger: Logger?

    # @rbs!
    #   attr_accessor enabled: bool
    #   attr_accessor auto_fix: bool
    #   attr_accessor target_paths: Array[String]
    #   attr_accessor skip_paths: Array[String]
    #   attr_accessor dry_run: bool
    #   attr_accessor backup: bool
    #   attr_accessor fix_strategy: Symbol
    #   attr_accessor debug: bool
    #   attr_writer logger: Logger?
    attr_accessor :enabled, :auto_fix, :target_paths, :skip_paths,
                  :dry_run, :backup, :fix_strategy, :debug
    attr_writer :logger

    #: () -> void
    def initialize
      DEFAULTS.each { |key, value| public_send(:"#{key}=", value.dup) }
    end

    #: () -> Logger
    def logger
      @logger ||= default_logger
    end

    private

    #: () -> Logger
    def default_logger
      if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
        ::Logger.new(Rails.root.join("log", "bullematic.log"))
      else
        ::Logger.new($stdout)
      end
    end
  end
end
