# rbs_inline: enabled
# frozen_string_literal: true

require "bullet"

require_relative "bullematic/version"
require_relative "bullematic/configuration"
require_relative "bullematic/logger"
require_relative "bullematic/detection"
require_relative "bullematic/evidence_store"
require_relative "bullematic/ast/parser"
require_relative "bullematic/ast/finder"
require_relative "bullematic/ast/rewriter"
require_relative "bullematic/fixer"
require_relative "bullematic/notifier"

module Bullematic
  class Error < StandardError; end
  class ParseError < Error; end
  class FixError < Error; end

  # @rbs @configuration: Configuration?

  class << self
    #: () -> Configuration?
    def configuration
      @configuration
    end

    #: (Configuration?) -> Configuration?
    def configuration=(configuration)
      @configuration = configuration
    end

    #: () { (Configuration) -> void } -> void
    def configure
      self.configuration ||= Configuration.new
      config = configuration
      yield(config) if block_given? && config
    end

    #: () -> void
    def setup_bullet_hook
      return unless defined?(Bullet)

      Notifier.setup
    end

    #: () -> bool
    def enabled?
      configuration&.enabled == true && ENV["BULLEMATIC"] == "1"
    end

    #: () -> void
    def reset!
      @configuration = nil
      Fixer.clear
    end
  end
end

require_relative "bullematic/integrations/rails" if defined?(Rails::Railtie)
