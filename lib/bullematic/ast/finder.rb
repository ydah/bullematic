# rbs_inline: enabled
# frozen_string_literal: true

require "set"

module Bullematic
  module AST
    class Finder
      QUERY_METHODS = %i[all where find find_by first last order limit offset].freeze #: Array[Symbol]

      # @rbs!
      #   type query_location = { node: untyped, location: untyped, receiver: untyped, method_name: Symbol, target_name: Symbol? }

      QueryLocation = Struct.new(:node, :location, :receiver, :method_name, :target_name, keyword_init: true)

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

      # @rbs model_class_name: String
      # @rbs line_number: Integer
      # @rbs return: Array[QueryLocation]
      def find_model_queries_for_variables_at_line(model_class_name, line_number)
        names = variable_names_at_line(parse_result.value, line_number)
        add_block_receiver_names(parse_result.value, line_number, names)
        find_model_queries(model_class_name).select do |query|
          query.target_name && names.include?(query.target_name)
        end
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
        when Prism::InstanceVariableWriteNode, Prism::LocalVariableWriteNode
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
          method_name: value.name,
          target_name: node.name
        )
        true
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs return: Array[Symbol]
      def variable_names_at_line(node, line_number)
        return [] unless node.respond_to?(:child_nodes)

        names = [] #: Array[Symbol]
        if (node.is_a?(Prism::InstanceVariableReadNode) || node.is_a?(Prism::LocalVariableReadNode)) &&
           node.location.start_line == line_number
          names << node.name
        end
        node.child_nodes.compact.each { |child| names.concat(variable_names_at_line(child, line_number)) }
        names.uniq
      end

      # @rbs node: untyped
      # @rbs line_number: Integer
      # @rbs names: Array[Symbol]
      # @rbs return: void
      def add_block_receiver_names(node, line_number, names)
        return unless node.respond_to?(:child_nodes)

        if node.is_a?(Prism::CallNode) && node.block &&
           line_number.between?(node.block.location.start_line, node.block.location.end_line)
          parameters = node.block.parameters&.parameters&.requireds || []
          receiver = node.receiver
          if parameters.any? { |parameter| names.include?(parameter.name) } &&
             (receiver.is_a?(Prism::InstanceVariableReadNode) || receiver.is_a?(Prism::LocalVariableReadNode))
            names << receiver.name
          end
        end

        node.child_nodes.compact.each { |child| add_block_receiver_names(child, line_number, names) }
        names.uniq!
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
