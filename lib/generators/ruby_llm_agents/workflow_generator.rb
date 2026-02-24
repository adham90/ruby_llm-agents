# frozen_string_literal: true

require "rails/generators"

module RubyLlmAgents
  # Workflow generator for creating new agent workflows
  #
  # Usage:
  #   rails generate ruby_llm_agents:workflow Content
  #   rails generate ruby_llm_agents:workflow Content --steps research,draft,edit
  #
  # This will create:
  #   - app/agents/application_workflow.rb (if not present)
  #   - app/agents/content_workflow.rb
  #
  class WorkflowGenerator < ::Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)

    class_option :steps, type: :string, default: "",
      desc: "Workflow steps (comma-separated, e.g., 'research,draft,edit')"

    def ensure_base_class
      base_class_path = "app/agents/application_workflow.rb"
      unless File.exist?(File.join(destination_root, base_class_path))
        template "application_workflow.rb.tt", base_class_path
      end
    end

    def create_workflow_file
      @steps = parse_steps
      workflow_path = name.underscore
      template "workflow.rb.tt", "app/agents/#{workflow_path}_workflow.rb"
    end

    def show_usage
      workflow_class = "#{name.camelize}Workflow"
      say ""
      say "Workflow #{workflow_class} created!", :green
      say ""
      say "Usage:"
      say "  result = #{workflow_class}.call(topic: 'AI safety')"
      say "  result.success?    # => true"
      say "  result.total_cost  # => Combined cost of all steps"
      say "  result.step(:name) # => Access specific step result"
      say ""

      if @steps.any?
        say "Steps defined: #{@steps.join(" >> ")}"
        @steps.each do |step|
          say "  Note: Create #{step.to_s.camelize}Agent if it doesn't exist", :yellow
        end
      else
        say "Add steps to your workflow in app/agents/#{name.underscore}_workflow.rb"
      end
      say ""
    end

    private

    def parse_steps
      options[:steps].to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_sym)
    end
  end
end
