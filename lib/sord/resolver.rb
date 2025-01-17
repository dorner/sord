# typed: false
require 'stringio'

module Sord
  module Resolver
    # @return [void]
    def self.prepare
      # Construct a hash of class names to full paths
      @@names_to_paths ||= YARD::Registry.all(:class)
        .group_by(&:name)
        .map { |k, v| [k.to_s, v.map(&:path)] }
        .to_h
        .merge(builtin_classes.map { |x| [x, [x]] }.to_h) do |k, a, b|
          a | b
        end
    end

    # @return [void]
    def self.clear
      @@names_to_paths = nil
    end

    # @param [String] name
    # @return [Array<String>]
    def self.paths_for(name)
      prepare

      # If the name starts with ::, then we've been given an explicit path from root - just use that
      return [name] if name.start_with?('::')

      (@@names_to_paths[name.split('::').last] || [])
        .select { |x| x.end_with?(name) }
    end

    # @param [String] name
    # @return [String, nil]
    def self.path_for(name)
      paths_for(name).one? ? paths_for(name).first : nil
    end

    # @return [Array<String>]
    def self.builtin_classes
      # This prints some deprecation warnings, so suppress them
      prev_stderr = $stderr
      $stderr = StringIO.new
      
      major = RUBY_VERSION.split('.').first.to_i
      sorted_set_removed = major >= 3 

      Object.constants
        .reject { |x| sorted_set_removed && x == :SortedSet }
        .select { |x| Object.const_get(x).is_a?(Class) }
        .map(&:to_s)
    ensure
      $stderr = prev_stderr
    end

    # @param [String] name
    # @param [Object] item
    # @return [Boolean]
    def self.resolvable?(name, item)
      current_context = item
      current_context = current_context.parent \
        until current_context.is_a?(YARD::CodeObjects::NamespaceObject)

      # If there is any matching object directly in the heirarchy, this is
      # always true. Ruby can do the resolution.
      unless name.include?('::')
        return true if current_context.path.split('::').include?(name)
      end

      name_parts = name.split('::')

      matching_paths = []

      loop do
        # Try to find that class in this context
        path_followed_context = current_context
        name_parts.each do |name_part|
          path_followed_context = path_followed_context&.child(
            name: name_part, type: [:class, :method, :module]
          )
        end

        # Return true if we found the constant we're looking for here
        matching_paths |= [path_followed_context.path] if path_followed_context

        # Move up one context
        break if current_context.root?
        current_context = current_context.parent
      end

      return (builtin_classes.include?(name) && matching_paths.empty?) ||
        (matching_paths.one? && !builtin_classes.include?(name))
    end
  end
end
