# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # DSL for persisting user-supplied input attachments alongside an
      # execution record, so the original files can be inspected later from
      # the dashboard.
      #
      # Opt-in per agent. When enabled, any files passed via the `with:`
      # keyword to `.call` are attached to the Execution's detail record.
      #
      # @example Enable with the Active Storage backend
      #   class DiagramImportAgent < ApplicationAgent
      #     store_attachments :active_storage
      #   end
      #
      #   DiagramImportAgent.call(with: "path/to/diagram.png")
      #   # => The file is attached to execution.detail.user_attachments
      #
      # Only `:active_storage` is supported. Agents that do not declare
      # `store_attachments` are unchanged — `with:` continues to work as
      # before, just without persistence.
      module Attachments
        SUPPORTED_BACKENDS = %i[active_storage].freeze

        # Sets or returns the attachment storage backend for this agent.
        #
        # @param backend [Symbol, nil] `:active_storage` or nil to read the current value
        # @return [Symbol, nil] The configured backend, or nil if disabled
        # @raise [ArgumentError] If an unsupported backend is given
        def store_attachments(backend = nil)
          if backend
            unless SUPPORTED_BACKENDS.include?(backend)
              raise ArgumentError,
                "Unsupported store_attachments backend #{backend.inspect}. Supported: #{SUPPORTED_BACKENDS.inspect}"
            end

            @store_attachments = backend
          end

          return @store_attachments if defined?(@store_attachments) && !@store_attachments.nil?

          inherited_store_attachments
        end

        # Whether any attachment persistence is enabled on this agent.
        #
        # @return [Boolean]
        def store_attachments_enabled?
          !store_attachments.nil?
        end

        private

        def inherited_store_attachments
          return nil unless superclass.respond_to?(:store_attachments)

          superclass.store_attachments
        end
      end
    end
  end
end
