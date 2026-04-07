# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AgentsController, "override actions", type: :controller do
  routes { RubyLLM::Agents::Engine.routes }

  controller do
    def update
      super
    rescue ActionController::RoutingError
      head :ok
    end

    def reset_overrides
      super
    rescue ActionController::RoutingError
      head :ok
    end
  end

  before do
    RubyLLM::Agents::AgentOverride.delete_all
  end

  # Create a real overridable agent class for testing
  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name = "OverridableTestAgent"

      model "gpt-4o", overridable: true
      temperature 0.7, overridable: true
      timeout 30
    end
  end

  before do
    stub_const("OverridableTestAgent", agent_class)
  end

  describe "PATCH #update" do
    it "creates an override for overridable fields" do
      patch :update, params: {
        id: "OverridableTestAgent",
        override: {model: "gpt-4o-mini", temperature: "0.3"}
      }

      expect(response).to redirect_to(controller.agent_path("OverridableTestAgent"))

      override = RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")
      expect(override).to be_present
      expect(override.settings["model"]).to eq("gpt-4o-mini")
      expect(override.settings["temperature"]).to eq(0.3)
    end

    it "ignores non-overridable fields" do
      patch :update, params: {
        id: "OverridableTestAgent",
        override: {model: "gpt-4o-mini", timeout: "60"}
      }

      override = RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")
      expect(override.settings).not_to have_key("timeout")
    end

    it "updates an existing override" do
      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableTestAgent",
        settings: {"model" => "old-model"}
      )

      patch :update, params: {
        id: "OverridableTestAgent",
        override: {model: "new-model"}
      }

      override = RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")
      expect(override.settings["model"]).to eq("new-model")
    end

    it "deletes the override when all fields are empty" do
      RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableTestAgent",
        settings: {"model" => "gpt-4o-mini"}
      )

      patch :update, params: {
        id: "OverridableTestAgent",
        override: {model: "", temperature: ""}
      }

      expect(RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")).to be_nil
    end

    it "redirects with alert when agent not found" do
      patch :update, params: {
        id: "NonexistentAgent",
        override: {model: "gpt-4o-mini"}
      }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Agent not found")
    end

    it "redirects with alert when agent has no overridable fields" do
      locked_class = Class.new(RubyLLM::Agents::Base) do
        def self.name = "LockedTestAgent"

        model "gpt-4o"
      end
      stub_const("LockedTestAgent", locked_class)

      patch :update, params: {
        id: "LockedTestAgent",
        override: {model: "gpt-4o-mini"}
      }

      expect(response).to redirect_to(controller.agent_path("LockedTestAgent"))
      expect(flash[:alert]).to eq("This agent has no overridable fields")
    end

    it "coerces temperature to float" do
      patch :update, params: {
        id: "OverridableTestAgent",
        override: {temperature: "0.5"}
      }

      override = RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")
      expect(override.settings["temperature"]).to eq(0.5)
      expect(override.settings["temperature"]).to be_a(Float)
    end
  end

  describe "reset_overrides logic" do
    # The DELETE #reset_overrides member route cannot be tested with anonymous controllers.
    # We test the model-level cleanup directly to verify the behavior.

    it "deleting an AgentOverride record clears the agent's cache" do
      override = RubyLLM::Agents::AgentOverride.create!(
        agent_type: "OverridableTestAgent",
        settings: {"model" => "gpt-4o-mini"}
      )

      # Trigger the override to be cached
      agent_class.clear_override_cache!
      expect(agent_class.model).to eq("gpt-4o-mini")

      # Destroy (simulates reset_overrides)
      override.destroy

      # Cache was busted by after_destroy callback
      expect(agent_class.model).to eq("gpt-4o")
    end

    it "does not error when destroying a non-existent override" do
      expect {
        RubyLLM::Agents::AgentOverride.find_by(agent_type: "OverridableTestAgent")&.destroy
      }.not_to raise_error
    end
  end
end
