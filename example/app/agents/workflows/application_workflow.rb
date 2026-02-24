# frozen_string_literal: true

# ApplicationWorkflow - Base class for all workflows in this application
#
# All workflows inherit from this class. Configure shared settings here
# that apply to all workflows, or override them per-workflow as needed.
#
# Workflows compose multiple agents into a single callable unit with
# automatic cost aggregation, execution tracking, and error handling.
#
# ============================================================================
# DSL REFERENCE
# ============================================================================
#
# STEPS:
# ------
#   step :name, AgentClass
#   step :name, AgentClass, params: { key: "value" }
#   step :name, AgentClass, after: :previous_step
#   step :name, AgentClass, after: [:step_a, :step_b]  # fan-in
#   step :name, AgentClass, if: -> (ctx) { ctx[:flag] }
#   step :name, AgentClass, unless: -> (ctx) { ctx[:skip] }
#
# FLOW (sequential dependencies):
# --------------------------------
#   flow :a >> :b >> :c
#   flow [:a, :b, :c]
#
# DATA PASSING:
# -------------
#   pass :source, to: :target, as: { target_param: :source_output_key }
#
# DISPATCH (route to agents based on classification):
# ---------------------------------------------------
#   dispatch :router_step do |d|
#     d.on :billing,  agent: BillingAgent
#     d.on :technical, agent: TechAgent
#     d.on_default     agent: GeneralAgent
#   end
#
# SUPERVISOR (loop-based orchestration):
# --------------------------------------
#   supervisor OrchestratorAgent, max_turns: 10
#   delegate :researcher, ResearchAgent
#   delegate :writer,     WriterAgent
#
# CONFIGURATION:
# --------------
#   description "Human-readable description"
#   on_failure :stop      # Stop on first error (default)
#   on_failure :continue  # Continue despite errors
#   budget 5.00           # Max cost in USD
#
# USAGE:
# ------
#   result = MyWorkflow.call(param: "value")
#   result.success?       # => true
#   result.total_cost     # => 0.0082
#   result.step(:name)    # => Agent Result for that step
#   result.final_result   # => Last step's Result
#
class ApplicationWorkflow < RubyLLM::Agents::Workflow
  # ============================================
  # Shared Workflow Configuration
  # ============================================

  # on_failure :stop     # Stop on first error (default)
  # on_failure :continue # Continue despite errors

  # ============================================
  # Shared Helper Methods
  # ============================================

  # Example: Common metadata
  # def metadata
  #   { app_version: Rails.application.config.version }
  # end
end
