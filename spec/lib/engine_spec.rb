# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Engine do
  describe "engine configuration" do
    it "isolates namespace to RubyLLM::Agents" do
      expect(described_class.isolated?).to be true
    end

    it "has the correct engine name" do
      expect(described_class.engine_name).to eq("ruby_llm_agents")
    end

    it "is a Rails::Engine" do
      expect(described_class.superclass).to eq(Rails::Engine)
    end
  end

  describe "generator configuration" do
    it "configures rspec as the test framework" do
      expect(described_class.config.generators.options[:rails][:test_framework]).to eq(:rspec)
    end

    it "configures factory_bot for fixtures" do
      expect(described_class.config.generators.options[:rails][:fixture_replacement]).to eq(:factory_bot)
    end

    it "sets factory_bot directory to spec/factories" do
      expect(described_class.config.generators.options[:factory_bot][:dir]).to eq("spec/factories")
    end
  end

  describe "autoload_agents initializer" do
    it "has the autoload_agents initializer" do
      initializer = described_class.initializers.find { |i| i.name == "ruby_llm_agents.autoload_agents" }
      expect(initializer).not_to be_nil
    end

    it "runs before set_autoload_paths" do
      initializer = described_class.initializers.find { |i| i.name == "ruby_llm_agents.autoload_agents" }
      expect(initializer.before).to eq(:set_autoload_paths)
    end
  end

  describe ".namespace_for_path" do
    let(:config) { RubyLLM::Agents.configuration }

    context "with default namespace (Llm)" do
      before do
        allow(config).to receive(:root_namespace).and_return("Llm")
      end

      it "returns Llm module for agents path" do
        result = described_class.namespace_for_path("app/llm/agents", config)
        expect(result).to eq(Llm)
      end

      it "returns Llm module for tools path" do
        result = described_class.namespace_for_path("app/llm/tools", config)
        expect(result).to eq(Llm)
      end

      it "returns Llm module for workflows path" do
        result = described_class.namespace_for_path("app/llm/workflows", config)
        expect(result).to eq(Llm)
      end

      it "returns Llm::Audio module for audio speakers path" do
        result = described_class.namespace_for_path("app/llm/audio/speakers", config)
        expect(result.name).to eq("Llm::Audio")
      end

      it "returns Llm::Audio module for audio transcribers path" do
        result = described_class.namespace_for_path("app/llm/audio/transcribers", config)
        expect(result.name).to eq("Llm::Audio")
      end

      it "returns Llm::Image module for image generators path" do
        result = described_class.namespace_for_path("app/llm/image/generators", config)
        expect(result.name).to eq("Llm::Image")
      end

      it "returns Llm::Image module for image analyzers path" do
        result = described_class.namespace_for_path("app/llm/image/analyzers", config)
        expect(result.name).to eq("Llm::Image")
      end

      it "returns Llm::Text module for text embedders path" do
        result = described_class.namespace_for_path("app/llm/text/embedders", config)
        expect(result.name).to eq("Llm::Text")
      end

      it "returns Llm::Text module for text moderators path" do
        result = described_class.namespace_for_path("app/llm/text/moderators", config)
        expect(result.name).to eq("Llm::Text")
      end
    end

    context "with no namespace (nil)" do
      before do
        allow(config).to receive(:root_namespace).and_return(nil)
      end

      it "returns nil for agents path" do
        result = described_class.namespace_for_path("app/llm/agents", config)
        expect(result).to be_nil
      end

      it "returns nil for tools path" do
        result = described_class.namespace_for_path("app/llm/tools", config)
        expect(result).to be_nil
      end

      it "returns nil for workflows path" do
        result = described_class.namespace_for_path("app/llm/workflows", config)
        expect(result).to be_nil
      end

      it "returns Audio module for audio speakers path" do
        result = described_class.namespace_for_path("app/llm/audio/speakers", config)
        expect(result).to be_a(Module)
        expect(result.name).to eq("Audio")
      end

      it "returns Image module for image generators path" do
        result = described_class.namespace_for_path("app/llm/image/generators", config)
        expect(result).to be_a(Module)
        expect(result.name).to eq("Image")
      end

      it "returns Text module for text embedders path" do
        result = described_class.namespace_for_path("app/llm/text/embedders", config)
        expect(result).to be_a(Module)
        expect(result.name).to eq("Text")
      end
    end

    context "with empty string namespace" do
      before do
        allow(config).to receive(:root_namespace).and_return("")
      end

      it "returns nil for agents path" do
        result = described_class.namespace_for_path("app/llm/agents", config)
        expect(result).to be_nil
      end

      it "returns Audio module for audio path" do
        result = described_class.namespace_for_path("app/llm/audio/speakers", config)
        expect(result).to be_a(Module)
        expect(result.name).to eq("Audio")
      end
    end

    context "with custom namespace (AI)" do
      before do
        allow(config).to receive(:root_namespace).and_return("AI")
      end

      it "returns AI module for agents path" do
        # Ensure the AI module exists for the test
        Object.const_set(:AI, Module.new) unless Object.const_defined?(:AI)
        result = described_class.namespace_for_path("app/llm/agents", config)
        expect(result).to eq(AI)
      end

      it "returns AI::Image module for image generators path" do
        # Ensure the AI::Image module exists for the test
        Object.const_set(:AI, Module.new) unless Object.const_defined?(:AI)
        AI.const_set(:Image, Module.new) unless AI.const_defined?(:Image)
        result = described_class.namespace_for_path("app/llm/image/generators", config)
        expect(result.name).to eq("AI::Image")
      end
    end

    context "with invalid paths" do
      before do
        allow(config).to receive(:root_namespace).and_return("Llm")
      end

      it "returns nil for paths with fewer than 3 parts" do
        result = described_class.namespace_for_path("app/llm", config)
        expect(result).to be_nil
      end

      it "returns nil for paths with only 2 parts" do
        result = described_class.namespace_for_path("app", config)
        expect(result).to be_nil
      end
    end
  end

  describe "ApplicationController" do
    # The ApplicationController is dynamically created by the engine
    let(:controller_class) { RubyLLM::Agents::ApplicationController }

    it "exists after engine initialization" do
      expect(RubyLLM::Agents.const_defined?(:ApplicationController)).to be true
    end

    it "inherits from the configured parent controller" do
      # Default is ActionController::Base
      parent = RubyLLM::Agents.configuration.dashboard_parent_controller.constantize
      expect(controller_class.superclass).to eq(parent)
    end

    it "uses the engine layout" do
      expect(controller_class._layout).to eq("ruby_llm/agents/application")
    end

    it "includes ApplicationHelper" do
      expect(controller_class._helpers.ancestors).to include(RubyLLM::Agents::ApplicationHelper)
    end

    it "has authenticate_dashboard! as a before_action" do
      before_actions = controller_class._process_action_callbacks.select { |c| c.kind == :before }
      filter_names = before_actions.map { |c| c.filter.to_s }
      expect(filter_names).to include("authenticate_dashboard!")
    end
  end

  describe "authentication methods" do
    let(:controller_class) { RubyLLM::Agents::ApplicationController }
    let(:controller) { controller_class.new }

    before do
      # Set up request and response for controller
      allow(controller).to receive(:request).and_return(double("Request"))
      allow(controller).to receive(:render)
    end

    describe "#basic_auth_configured?" do
      context "when username and password are both set" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return("admin")
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return("secret")
        end

        it "returns true" do
          expect(controller.send(:basic_auth_configured?)).to be true
        end
      end

      context "when only username is set" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return("admin")
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return(nil)
        end

        it "returns false" do
          expect(controller.send(:basic_auth_configured?)).to be false
        end
      end

      context "when only password is set" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return(nil)
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return("secret")
        end

        it "returns false" do
          expect(controller.send(:basic_auth_configured?)).to be false
        end
      end

      context "when neither is set" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return(nil)
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return(nil)
        end

        it "returns false" do
          expect(controller.send(:basic_auth_configured?)).to be false
        end
      end

      context "when values are empty strings" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return("")
          allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return("")
        end

        it "returns false" do
          expect(controller.send(:basic_auth_configured?)).to be false
        end
      end
    end

    describe "#authenticate_dashboard!" do
      context "when basic auth is configured" do
        before do
          allow(controller).to receive(:basic_auth_configured?).and_return(true)
          allow(controller).to receive(:authenticate_with_http_basic_auth)
        end

        it "uses HTTP basic auth" do
          expect(controller).to receive(:authenticate_with_http_basic_auth)
          controller.send(:authenticate_dashboard!)
        end
      end

      context "when basic auth is not configured" do
        let(:auth_proc) { ->(ctrl) { true } }

        before do
          allow(controller).to receive(:basic_auth_configured?).and_return(false)
          allow(RubyLLM::Agents.configuration).to receive(:dashboard_auth).and_return(auth_proc)
        end

        context "and custom auth succeeds" do
          it "allows access" do
            expect(controller).not_to receive(:render)
            controller.send(:authenticate_dashboard!)
          end
        end

        context "and custom auth fails" do
          let(:auth_proc) { ->(ctrl) { false } }

          it "renders unauthorized" do
            expect(controller).to receive(:render).with(plain: "Unauthorized", status: :unauthorized)
            controller.send(:authenticate_dashboard!)
          end
        end
      end
    end

    describe "#authenticate_with_http_basic_auth" do
      before do
        allow(RubyLLM::Agents.configuration).to receive(:basic_auth_username).and_return("admin")
        allow(RubyLLM::Agents.configuration).to receive(:basic_auth_password).and_return("secret")
        allow(controller).to receive(:authenticate_or_request_with_http_basic).and_yield("admin", "secret")
      end

      it "calls authenticate_or_request_with_http_basic with realm" do
        expect(controller).to receive(:authenticate_or_request_with_http_basic).with("RubyLLM Agents")
        controller.send(:authenticate_with_http_basic_auth)
      end

      it "uses secure_compare for timing-safe comparison" do
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).with("admin", "admin").and_return(true)
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).with("secret", "secret").and_return(true)

        controller.send(:authenticate_with_http_basic_auth)
      end
    end
  end

  describe "multi-tenancy helper methods" do
    let(:controller_class) { RubyLLM::Agents::ApplicationController }
    let(:controller) { controller_class.new }

    before do
      allow(controller).to receive(:params).and_return({})
    end

    describe "#tenant_filter_enabled?" do
      context "when multi-tenancy is enabled" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(true)
        end

        it "returns true" do
          expect(controller.send(:tenant_filter_enabled?)).to be true
        end
      end

      context "when multi-tenancy is disabled" do
        before do
          allow(RubyLLM::Agents.configuration).to receive(:multi_tenancy_enabled?).and_return(false)
        end

        it "returns false" do
          expect(controller.send(:tenant_filter_enabled?)).to be false
        end
      end

      it "is exposed as a helper method" do
        expect(controller_class._helper_methods).to include(:tenant_filter_enabled?)
      end
    end

    describe "#current_tenant_id" do
      context "when tenant_id param is present" do
        before do
          allow(controller).to receive(:params).and_return({ tenant_id: "tenant-abc" })
        end

        it "returns the param value" do
          expect(controller.send(:current_tenant_id)).to eq("tenant-abc")
        end

        it "does not call tenant_resolver" do
          expect(RubyLLM::Agents.configuration).not_to receive(:current_tenant_id)
          controller.send(:current_tenant_id)
        end
      end

      context "when tenant_id param is not present" do
        before do
          allow(controller).to receive(:params).and_return({})
          allow(RubyLLM::Agents.configuration).to receive(:current_tenant_id).and_return("resolved-tenant")
        end

        it "returns the resolved tenant ID" do
          expect(controller.send(:current_tenant_id)).to eq("resolved-tenant")
        end
      end

      it "memoizes the result" do
        allow(controller).to receive(:params).and_return({ tenant_id: "tenant-1" })
        controller.send(:current_tenant_id)
        allow(controller).to receive(:params).and_return({ tenant_id: "tenant-2" })

        expect(controller.send(:current_tenant_id)).to eq("tenant-1")
      end

      it "is exposed as a helper method" do
        expect(controller_class._helper_methods).to include(:current_tenant_id)
      end
    end

    describe "#tenant_scoped_executions" do
      let(:mock_relation) { double("ActiveRecord::Relation") }
      let(:filtered_relation) { double("Filtered ActiveRecord::Relation") }

      before do
        allow(RubyLLM::Agents::Execution).to receive(:all).and_return(mock_relation)
        allow(RubyLLM::Agents::Execution).to receive(:by_tenant).and_return(filtered_relation)
      end

      context "when multi-tenancy is enabled and tenant is selected" do
        before do
          allow(controller).to receive(:tenant_filter_enabled?).and_return(true)
          allow(controller).to receive(:current_tenant_id).and_return("tenant-abc")
        end

        it "returns tenant-filtered executions" do
          expect(RubyLLM::Agents::Execution).to receive(:by_tenant).with("tenant-abc")
          controller.send(:tenant_scoped_executions)
        end
      end

      context "when multi-tenancy is enabled but no tenant selected" do
        before do
          allow(controller).to receive(:tenant_filter_enabled?).and_return(true)
          allow(controller).to receive(:current_tenant_id).and_return(nil)
        end

        it "returns all executions" do
          expect(RubyLLM::Agents::Execution).to receive(:all)
          controller.send(:tenant_scoped_executions)
        end
      end

      context "when multi-tenancy is disabled" do
        before do
          allow(controller).to receive(:tenant_filter_enabled?).and_return(false)
          allow(controller).to receive(:current_tenant_id).and_return("tenant-abc")
        end

        it "returns all executions" do
          expect(RubyLLM::Agents::Execution).to receive(:all)
          controller.send(:tenant_scoped_executions)
        end
      end

      it "is exposed as a helper method" do
        expect(controller_class._helper_methods).to include(:tenant_scoped_executions)
      end
    end

    describe "#available_tenants" do
      let(:mock_query) { double("ActiveRecord::Relation") }
      let(:distinct_query) { double("Distinct Query") }

      before do
        allow(RubyLLM::Agents::Execution).to receive(:where).and_return(mock_query)
        allow(mock_query).to receive(:not).and_return(mock_query)
        allow(mock_query).to receive(:distinct).and_return(distinct_query)
        allow(distinct_query).to receive(:pluck).with(:tenant_id).and_return(["tenant-b", "tenant-a", "tenant-c"])
      end

      it "returns sorted unique tenant IDs" do
        result = controller.send(:available_tenants)
        expect(result).to eq(["tenant-a", "tenant-b", "tenant-c"])
      end

      it "excludes nil tenant IDs" do
        expect(RubyLLM::Agents::Execution).to receive(:where).and_return(mock_query)
        expect(mock_query).to receive(:not).with(tenant_id: nil)
        controller.send(:available_tenants)
      end

      it "memoizes the result" do
        controller.send(:available_tenants)
        expect(RubyLLM::Agents::Execution).not_to receive(:where)
        controller.send(:available_tenants)
      end

      it "is exposed as a helper method" do
        expect(controller_class._helper_methods).to include(:available_tenants)
      end
    end
  end

  describe "view configuration" do
    it "prepends engine view path" do
      view_paths = RubyLLM::Agents::ApplicationController.view_paths.paths.map(&:to_s)
      engine_views_path = RubyLLM::Agents::Engine.root.join("app/views").to_s

      expect(view_paths).to include(engine_views_path)
    end
  end

  describe "engine routes" do
    it "defines routes" do
      expect(described_class.routes).to be_a(ActionDispatch::Routing::RouteSet)
    end
  end
end
