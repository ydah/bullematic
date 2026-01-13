# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  class Notifier
    class << self
      #: () -> void
      def setup
        return unless defined?(Bullet)

        setup_notification_hook
      end

      #: () -> void
      def process_notifications
        return unless defined?(Bullet) && Bullet.notification?

        notifications = Bullet.send(:notification_collector)&.collection

        case notifications
        when Hash
          notifications.each_value do |notification_set|
            notification_set.each do |notification|
              if notification.is_a?(Bullet::Notification::NPlusOneQuery)
                process_n_plus_one(notification)
              elsif notification.is_a?(Bullet::Notification::UnusedEagerLoading)
                process_unused_eager_loading(notification)
              end
            end
          end
        when Enumerable
          notifications.each do |notification|
            if notification.is_a?(Bullet::Notification::NPlusOneQuery)
              process_n_plus_one(notification)
            elsif notification.is_a?(Bullet::Notification::UnusedEagerLoading)
              process_unused_eager_loading(notification)
            end
          end
        end
      end

      private

      #: () -> void
      def setup_notification_hook
        Bullet::Notification::NPlusOneQuery.prepend(NotificationHook)
      end

      # @rbs notification: untyped
      # @rbs return: void
      def process_n_plus_one(notification)
        detection = Detection.new(
          type: :n_plus_one,
          base_class: notification.base_class,
          associations: notification.associations,
          call_stack: extract_call_stack(notification)
        )

        config = Bullematic.configuration
        if config&.logger && config.debug
          config.logger.debug "[Bullematic] N+1 Detection created:"
          config.logger.debug "  Base class: #{notification.base_class}"
          config.logger.debug "  Associations: #{notification.associations.inspect}"
          config.logger.debug "  Source file: #{detection.source_file}"
          config.logger.debug "  Line number: #{detection.line_number}"
          config.logger.debug "  Fixable: #{detection.fixable?}"
          config.logger.debug "  Queue size before: #{Fixer.detection_queue.size}"
        end

        if detection.fixable?
          Fixer.queue(detection)
          if config&.logger && config.debug
            config.logger.debug "  Queue size after: #{Fixer.detection_queue.size}"
          end
        end
      end

      # @rbs notification: untyped
      # @rbs return: void
      def process_unused_eager_loading(notification)
        # UnusedEagerLoadingは「使われていないアソシエーション」の警告
        # これをログに記録して、後で分析できるようにする
        config = Bullematic.configuration
        return unless config

        if config.logger && config.debug
          config.logger.debug "[Bullematic] UnusedEagerLoading detected:"
          config.logger.debug "  Base class: #{notification.base_class}"
          config.logger.debug "  Unused associations: #{notification.associations.inspect}"
        end

        # 将来的に、不要なincludesを削除する機能を追加する可能性がある
        # 現時点では、情報を記録するのみ
      end

      # @rbs notification: untyped
      # @rbs return: Array[String]
      def extract_call_stack(notification)
        callers = notification.instance_variable_get(:@callers)
        return callers if callers && !callers.empty?

        config = Bullematic.configuration
        return caller unless config

        call_stacks = Bullet::Detector::Association.send(:call_stacks) if defined?(Bullet::Detector::Association)
        stacks =
          if call_stacks&.respond_to?(:registry)
            call_stacks.registry.values
          else
            []
          end

        matching = stacks.find do |stack|
          Array(stack).any? do |frame|
            config.target_paths.any? { |path| frame.is_a?(String) && frame.include?(path) }
          end
        end

        matching || caller
      end
    end

    module NotificationHook
      # @rbs base_class: untyped
      # @rbs associations: untyped
      # @rbs path: untyped
      # @rbs return: void
      def initialize(base_class, associations, path = nil)
        super
        return unless Bullematic.enabled?

        detection = Detection.new(
          type: :n_plus_one,
          base_class: base_class,
          associations: associations,
          call_stack: caller
        )

        config = Bullematic.configuration
        if config&.logger && config.debug
          config.logger.debug "[Bullematic] N+1 Detection created (via hook):"
          config.logger.debug "  Base class: #{base_class}"
          config.logger.debug "  Associations: #{associations.inspect}"
          config.logger.debug "  Source file: #{detection.source_file}"
          config.logger.debug "  Line number: #{detection.line_number}"
          config.logger.debug "  Fixable: #{detection.fixable?}"
          config.logger.debug "  Queue size before: #{Fixer.detection_queue.size}"
        end

        if detection.fixable?
          Fixer.queue(detection)
          if config&.logger && config.debug
            config.logger.debug "  Queue size after: #{Fixer.detection_queue.size}"
          end
        end
      end
    end
  end
end
