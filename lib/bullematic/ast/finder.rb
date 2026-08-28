# rbs_inline: enabled
# frozen_string_literal: true

require "set"

module Bullematic
  module AST
    class Finder
      QUERY_METHODS = %i[all where find find_by first last order limit offset].freeze #: Array[Symbol]

      # @rbs!
      #   type query_location = { node: untyped, location: untyped, receiver: untyped, method_name: Symbol }

      QueryLocation = Struct.new(:node, :location, :receiver, :method_name, keyword_init: true)

      # @rbs @parse_result: untyped

      # @rbs!
      #   attr_reader parse_result: untyped
      attr_reader :parse_result

      # @rbs parse_result: untyped
      # @rbs return: void
      def initialize(parse_result)
        @parse_result = parse_result
      end

      # @rbs model_class_name: String
      # @rbs line_number: Integer?
      # @rbs return: Array[QueryLocation]
      def find_model_queries(model_class_name, line_number: nil)
        queries = [] #: Array[QueryLocation]
        visit_node(parse_result.value, queries, model_class_name, line_number)
        queries
      end

      # @rbs line_number: Integer
      # @rbs return: QueryLocation?
      def find_query_at_line(line_number)
        queries = [] #: Array[QueryLocation]
        visit_all_queries(parse_result.value, queries, line_number)
        queries.one? ? queries.first : nil
      end

      # @rbs line_number: Integer
      # @rbs return: String?
      def find_method_name_at_line(line_number)
        find_method_for_line(parse_result.value, line_number)
      end

      # @rbs model_class_name: String
      # @rbs method_name: String?
      # @rbs return: Array[QueryLocation]
      def find_model_queries_in_method(model_class_name, method_name)
        return [] unless method_name

        queries = [] #: Array[QueryLocation]
        visit_method_node(parse_result.value, queries, model_class_name, method_name)
        queries
      end

      private

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs skip_nodes: Set[Integer]
      # @rbs return: void
      def visit_node(node, queries, model_class_name, target_line, skip_nodes = Set.new)
        return unless node.respond_to?(:child_nodes)
        return if skip_nodes.include?(node.object_id)

        case node
        when Prism::InstanceVariableWriteNode
          if check_assignment_node(node, queries, model_class_name, target_line)
            mark_descendant_calls(node.value, skip_nodes)
          end
        when Prism::CallNode
          check_call_node(node, queries, model_class_name, target_line)
        end

        node.child_nodes.compact.each do |child|
          visit_node(child, queries, model_class_name, target_line, skip_nodes)
        end
      end

      # @rbs node: untyped
      # @rbs skip_nodes: Set[Integer]
      # @rbs return: void
      def mark_descendant_calls(node, skip_nodes)
        return unless node.respond_to?(:child_nodes)

        skip_nodes.add(node.object_id) if node.is_a?(Prism::CallNode)

        node.child_nodes.compact.each do |child|
          mark_descendant_calls(child, skip_nodes)
        end
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs target_line: Integer?
      # @rbs return: void
      def visit_all_queries(node, queries, target_line)
        return unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && query_method?(node.name)
          node_line = node.location.start_line
          if target_line.nil? || node_line == target_line
            queries << QueryLocation.new(
              node: node,
              location: node.location,
              receiver: find_root_receiver(node),
              method_name: node.name
            )
          end
        end

        node.child_nodes.compact.each do |child|
          visit_all_queries(child, queries, target_line)
        end
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs return: void
      def check_call_node(node, queries, model_class_name, target_line)
        return unless query_method?(node.name)
        return if target_line && node.location.start_line != target_line

        root_receiver = find_root_receiver(node)
        return unless model_constant?(root_receiver, model_class_name)

        queries << QueryLocation.new(
          node: node,
          location: node.location,
          receiver: root_receiver,
          method_name: node.name
        )
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs target_line: Integer?
      # @rbs return: bool
      def check_assignment_node(node, queries, model_class_name, target_line)
        return false if target_line && node.location.start_line != target_line

        value = node.value
        return false unless value.is_a?(Prism::CallNode)
        return false unless query_method?(value.name)

        root_receiver = find_root_receiver(value)
        return false unless model_constant?(root_receiver, model_class_name)

        queries << QueryLocation.new(
          node: value,
          location: value.location,
          receiver: root_receiver,
          method_name: value.name
        )
        true
      end

      # @rbs node: untyped
      # @rbs queries: Array[QueryLocation]
      # @rbs model_class_name: String
      # @rbs method_name: String
      # @rbs return: void
      def visit_method_node(node, queries, model_class_name, method_name)
        return unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::DefNode) && node.name.to_s == method_name
          visit_node(node.body, queries, model_class_name, nil) if node.body
          return
        end

        node.child_nodes.compact.each do |child|
          visit_method_node(child, queries, model_class_name, method_name)
        end
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs return: String?
      def find_method_for_line(node, line_number)
        return nil unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::DefNode)
          start_line = node.location.start_line
          end_line = node.location.end_line
          return node.name.to_s if line_number >= start_line && line_number <= end_line
        end

        node.child_nodes.compact.each do |child|
          found = find_method_for_line(child, line_number)
          return found if found
        end

        nil
      end

      # @rbs node: untyped
      # @rbs return: untyped
      def find_root_receiver(node)
        current = node
        current = current.receiver while current.is_a?(Prism::CallNode) && current.receiver
        current
      end

      # @rbs node: untyped
      # @rbs model_class_name: String
      # @rbs return: bool
      def model_constant?(node, model_class_name)
        return false unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

        node.full_name.delete_prefix("::") == model_class_name.delete_prefix("::")
      end

      # @rbs method_name: Symbol
      # @rbs return: bool
      def query_method?(method_name)
        QUERY_METHODS.include?(method_name)
      end
    end
  end
end
