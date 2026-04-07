# frozen_string_literal: true

module RubyLLM
  module Agents
    module DSL
      # Knowledge DSL for declaring domain knowledge to inject into system prompts.
      #
      # Supports two modes:
      # - Static: `knows :name` loads from a file resolved via `knowledge_path`
      # - Dynamic: `knows(:name) { ... }` evaluates a block at call time via instance_exec
      #
      # Optional `if:` condition gates inclusion without forcing static content into blocks.
      #
      # @example Static knowledge from files
      #   class MyAgent < RubyLLM::Agents::Base
      #     knowledge_path "knowledge"
      #     knows :refund_policy
      #     knows :pricing
      #   end
      #
      # @example Dynamic knowledge
      #   class MyAgent < RubyLLM::Agents::Base
      #     knows :recent_tickets do
      #       Ticket.recent.pluck(:summary)
      #     end
      #   end
      #
      # @example Conditional knowledge
      #   class MyAgent < RubyLLM::Agents::Base
      #     param :region, required: true
      #     knows :hipaa, if: -> { region == "us" }
      #   end
      #
      module Knowledge
        # Registers one or more knowledge entries.
        #
        # @overload knows(name, **options, &block)
        #   Register a single entry (static or dynamic)
        #   @param name [Symbol] Identifier for this knowledge entry
        #   @param options [Hash] Options including `if:` condition lambda
        #   @param block [Proc] Optional block for dynamic knowledge (evaluated via instance_exec)
        #
        # @overload knows(name, *more_names)
        #   Register multiple static entries at once
        #   @param name [Symbol] First entry name
        #   @param more_names [Array<Symbol>] Additional entry names
        def knows(name, *more_names, **options, &block)
          if more_names.any?
            # Multi-arg form: knows :a, :b, :c — all static, no block/options
            [name, *more_names].each do |n|
              knowledge_entries.reject! { |e| e[:name] == n }
              knowledge_entries << {name: n, loader: nil, options: {}}
            end
          else
            knowledge_entries.reject! { |e| e[:name] == name }
            knowledge_entries << {
              name: name,
              loader: block,
              options: options
            }
          end
        end

        # Sets or returns the base path for static knowledge files.
        #
        # @param path [String, nil] Path to set, or nil to read
        # @return [String, nil] The resolved knowledge path
        def knowledge_path(path = nil)
          if path
            @knowledge_path = path
          else
            @knowledge_path ||
              inherited_or_default(:knowledge_path, nil) ||
              RubyLLM::Agents.configuration.knowledge_path
          end
        end

        # Returns the list of registered knowledge entries, inheriting from superclass.
        #
        # @return [Array<Hash>] Knowledge entries
        def knowledge_entries
          @knowledge_entries ||= if superclass.respond_to?(:knowledge_entries)
            superclass.knowledge_entries.dup
          else
            []
          end
        end

        # Instance methods mixed into agent instances via include.
        module InstanceMethods
          # Compiles all knowledge entries into a single string with headings and separators.
          #
          # @return [String] Compiled knowledge (empty string if no entries resolve)
          def compiled_knowledge
            self.class.knowledge_entries.filter_map { |entry|
              content = resolve_knowledge(entry)
              next if content.blank?

              heading = entry[:name].to_s.tr("_", " ").gsub(/\b\w/, &:upcase)
              "## #{heading}\n\n#{content}"
            }.join("\n\n---\n\n")
          end

          private

          def resolve_knowledge(entry)
            if (condition = entry[:options][:if])
              return nil unless instance_exec(&condition)
            end

            if entry[:loader]
              resolve_dynamic_knowledge(entry)
            else
              resolve_static_knowledge(entry)
            end
          end

          def resolve_dynamic_knowledge(entry)
            result = instance_exec(&entry[:loader])
            case result
            when Array
              result.map { |r| "- #{r}" }.join("\n")
            when String
              result
            when nil
              nil
            else
              result.to_s
            end
          end

          def resolve_static_knowledge(entry)
            path = find_knowledge_file(entry[:name])
            return nil unless path && File.exist?(path)
            File.read(path)
          end

          def find_knowledge_file(name)
            base_path = self.class.knowledge_path
            return nil unless base_path

            candidates = [
              File.join(base_path, "#{name}.md"),
              File.join(base_path, name.to_s)
            ]

            if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
              candidates.map! { |c| Rails.root.join(c).to_s }
            end

            candidates.find { |c| File.exist?(c) }
          end
        end
      end
    end
  end
end
