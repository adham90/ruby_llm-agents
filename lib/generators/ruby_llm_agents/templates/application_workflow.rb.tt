# frozen_string_literal: true

# ApplicationWorkflow - Base class for all workflows in this application
#
# All workflows inherit from this class. Configure shared settings here
# that apply to all workflows, or override them per-workflow as needed.
#
# Workflows compose multiple agents into pipelines, parallel executions,
# or conditional routing flows.
#
# Example:
#   class ContentPipelineWorkflow < ApplicationWorkflow
#     description "Process and publish content"
#
#     step :moderate, agent: Moderators::ContentModerator
#     step :generate_image, agent: Images::ProductGenerator
#     step :embed, agent: Embedders::SemanticEmbedder
#   end
#
# Usage:
#   ContentPipelineWorkflow.call(content: "...")
#
class ApplicationWorkflow < RubyLLM::Agents::Workflow::Orchestrator
  # ============================================
  # Shared Workflow Configuration
  # ============================================

  # Default timeout for entire workflow
  # total_timeout 120

  # Budget tracking
  # budget_limit 1.0  # Maximum spend in dollars

  # ============================================
  # Shared Helper Methods
  # ============================================

  # Example: Common error handling
  # def on_step_error(step_name, error)
  #   Rails.logger.error "Workflow step #{step_name} failed: #{error.message}"
  #   # Optionally notify monitoring
  # end

  # Example: Common success callback
  # def on_complete(result)
  #   Rails.logger.info "Workflow completed successfully"
  # end
end
