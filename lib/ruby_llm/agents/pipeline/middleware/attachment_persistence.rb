# frozen_string_literal: true

module RubyLLM
  module Agents
    module Pipeline
      module Middleware
        # Persists input attachments (files passed via `with:`) to the
        # execution's detail record using the configured storage backend.
        #
        # Activates when the agent opts in with `store_attachments :active_storage`
        # and the call includes a `with:` argument. Runs after Instrumentation
        # so an Execution record already exists.
        #
        # Attachment is performed after the downstream call succeeds. On
        # failure, attachments are not persisted (keeps the dashboard
        # record focused on what the LLM actually saw for a completed run).
        # Any error during attachment is logged and swallowed so it never
        # breaks the agent call.
        class AttachmentPersistence < Base
          def call(context)
            result = @app.call(context)
            persist_attachments(context) if should_persist?(context)
            result
          end

          private

          def should_persist?(context)
            return false unless @agent_class.respond_to?(:store_attachments_enabled?)
            return false unless @agent_class.store_attachments_enabled?
            return false unless @agent_class.store_attachments == :active_storage
            return false if context.failed?
            return false if context.execution_id.nil?

            attachment_inputs(context).any?
          end

          def persist_attachments(context)
            execution = RubyLLM::Agents::Execution.find_by(id: context.execution_id)
            return unless execution

            detail = execution.detail || execution.create_detail!

            attachment_inputs(context).each do |input|
              attach(detail, input)
            end
          rescue => e
            error("Failed to persist user attachments: #{e.message}", context)
          end

          def attachment_inputs(context)
            Array(context.options[:with]).compact
          end

          def attach(detail, input)
            payload = build_attachment_payload(input)
            return unless payload

            detail.user_attachments.attach(payload)
          end

          # Normalises a `with:` entry into a Hash suitable for
          # ActiveStorage::Attached#attach, handling the common input types.
          #
          # Skips URLs (strings that parse as http/https) since they are not
          # local files — the LLM fetches them directly.
          def build_attachment_payload(input)
            case input
            when String
              return nil if url?(input)

              file_payload(input)
            when Pathname
              file_payload(input.to_s)
            when File, Tempfile
              {io: File.open(input.path), filename: File.basename(input.path), content_type: detect_content_type(input.path)}
            else
              return input if uploaded_file?(input)

              nil
            end
          end

          def file_payload(path)
            return nil unless File.exist?(path)

            {io: File.open(path), filename: File.basename(path), content_type: detect_content_type(path)}
          end

          def uploaded_file?(input)
            defined?(ActionDispatch::Http::UploadedFile) && input.is_a?(ActionDispatch::Http::UploadedFile)
          end

          def url?(string)
            string.start_with?("http://", "https://")
          end

          def detect_content_type(path)
            Marcel::MimeType.for(Pathname.new(path))
          rescue
            "application/octet-stream"
          end
        end
      end
    end
  end
end
