# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/upgrade_generator"

RSpec.describe RubyLlmAgents::UpgradeGenerator, type: :generator do
  # The upgrade generator checks for existing columns in the database
  # We need to mock the column_exists? method to test different scenarios

  # Stub Rails.root for file migration tests
  before do
    allow(Rails).to receive(:root).and_return(Pathname.new(destination_root))
  end

  describe "when table does not exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(false)

      run_generator
    end

    it "creates all upgrade migrations" do
      # When table doesn't exist, column_exists? returns false, so all migrations are created
      expect(Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")]).not_to be_empty
    end
  end

  describe "when all columns already exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)

      # Mock all columns as existing
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)

      run_generator
    end

    it "creates no migration files" do
      migration_files = Dir[file("db/migrate/*.rb")]
      expect(migration_files).to be_empty
    end
  end

  describe "when only some columns exist" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)

      # Mock specific columns as existing/missing
      allow(ActiveRecord::Base.connection).to receive(:column_exists?) do |table, column|
        # Simulate: prompts and attempts exist, but streaming and others don't
        existing_columns = [:system_prompt, :attempts]
        existing_columns.include?(column)
      end

      run_generator
    end

    it "skips migrations for existing columns" do
      expect(Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")]).to be_empty
      expect(Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")]).to be_empty
    end

    it "creates migrations for missing columns" do
      expect(Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")]).not_to be_empty
      expect(Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")]).not_to be_empty
    end
  end

  describe "migration content" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(false)

      run_generator
    end

    it "add_prompts migration adds system_prompt and user_prompt columns" do
      migration_file = Dir[file("db/migrate/*_add_prompts_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("system_prompt")
      expect(content).to include("user_prompt")
    end

    it "add_attempts migration adds attempts column" do
      migration_file = Dir[file("db/migrate/*_add_attempts_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("attempts")
    end

    it "add_streaming migration adds streaming column" do
      migration_file = Dir[file("db/migrate/*_add_streaming_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("streaming")
    end

    it "add_tracing migration adds trace_id column" do
      migration_file = Dir[file("db/migrate/*_add_tracing_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("trace_id")
    end

    it "add_routing migration adds fallback_reason column" do
      migration_file = Dir[file("db/migrate/*_add_routing_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("fallback_reason")
    end

    it "add_finish_reason migration adds finish_reason column" do
      migration_file = Dir[file("db/migrate/*_add_finish_reason_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("finish_reason")
    end

    it "add_caching migration adds cache_hit column" do
      migration_file = Dir[file("db/migrate/*_add_caching_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("cache_hit")
    end

    it "add_tool_calls migration adds tool_calls column" do
      migration_file = Dir[file("db/migrate/*_add_tool_calls_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("tool_calls")
    end

    it "add_execution_type migration adds execution_type column" do
      migration_file = Dir[file("db/migrate/*_add_execution_type_to_ruby_llm_agents_executions.rb")].first
      content = File.read(migration_file)
      expect(content).to include("execution_type")
    end
  end

  # ============================================
  # Agent and Tool Migration Tests
  # ============================================

  describe "agent migration" do
    before do
      # Mock database checks to avoid migration template issues
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)
    end

    def setup_old_agents
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/application_agent.rb"), <<~RUBY)
        class ApplicationAgent < RubyLLM::Agents::Base
        end
      RUBY
      File.write(file("app/agents/support_agent.rb"), <<~RUBY)
        class SupportAgent < ApplicationAgent
          model "gpt-4"
        end
      RUBY
    end

    context "when app/agents exists with files" do
      before do
        setup_old_agents
        run_generator
      end

      it "moves agents to app/llm/agents" do
        expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
        expect(file_exists?("app/llm/agents/support_agent.rb")).to be true
      end

      it "removes the old agents directory" do
        expect(directory_exists?("app/agents")).to be false
      end

      it "wraps classes in Llm namespace" do
        content = file_content("app/llm/agents/support_agent.rb")
        expect(content).to include("module Llm")
        expect(content).to include("class SupportAgent")
      end

      it "preserves original class content" do
        content = file_content("app/llm/agents/support_agent.rb")
        expect(content).to include('model "gpt-4"')
      end
    end

    context "when app/agents does not exist" do
      it "skips gracefully without error" do
        expect { run_generator }.not_to raise_error
      end

      it "does not create app/llm/agents" do
        run_generator
        # Directory may be created empty by other means, but should have no files
        if directory_exists?("app/llm/agents")
          expect(Dir.glob(file("app/llm/agents/*.rb"))).to be_empty
        end
      end
    end

    context "when app/agents is empty" do
      before do
        FileUtils.mkdir_p(file("app/agents"))
      end

      it "skips gracefully without error" do
        expect { run_generator }.not_to raise_error
      end
    end

    context "with nested subdirectories" do
      before do
        FileUtils.mkdir_p(file("app/agents/support/helpers"))
        File.write(file("app/agents/support/helpers/formatter.rb"), <<~RUBY)
          class Formatter
            def format(text)
              text.strip
            end
          end
        RUBY
        run_generator
      end

      it "preserves nested directory structure" do
        expect(file_exists?("app/llm/agents/support/helpers/formatter.rb")).to be true
      end

      it "wraps nested files in namespace" do
        content = file_content("app/llm/agents/support/helpers/formatter.rb")
        expect(content).to include("module Llm")
        expect(content).to include("class Formatter")
      end
    end
  end

  describe "tools migration" do
    before do
      # Mock database checks to avoid migration template issues
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)
    end

    def setup_old_tools
      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/weather_tool.rb"), <<~RUBY)
        class WeatherTool < RubyLLM::Tool
          def call(location:)
            # Get weather
          end
        end
      RUBY
      File.write(file("app/tools/calculator_tool.rb"), <<~RUBY)
        class CalculatorTool < RubyLLM::Tool
          def call(expression:)
            eval(expression)
          end
        end
      RUBY
    end

    context "when app/tools exists with files" do
      before do
        setup_old_tools
        run_generator
      end

      it "moves tools to app/llm/tools" do
        expect(file_exists?("app/llm/tools/weather_tool.rb")).to be true
        expect(file_exists?("app/llm/tools/calculator_tool.rb")).to be true
      end

      it "removes the old tools directory" do
        expect(directory_exists?("app/tools")).to be false
      end

      it "wraps classes in Llm namespace" do
        content = file_content("app/llm/tools/weather_tool.rb")
        expect(content).to include("module Llm")
        expect(content).to include("class WeatherTool")
      end
    end

    context "when app/tools does not exist" do
      it "skips gracefully without error" do
        expect { run_generator }.not_to raise_error
      end
    end
  end

  describe "conflict handling" do
    before do
      # Mock database checks
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)
    end

    context "when destination file already exists" do
      before do
        # Create source file
        FileUtils.mkdir_p(file("app/agents"))
        File.write(file("app/agents/conflicting_agent.rb"), <<~RUBY)
          class ConflictingAgent
            # Old version
          end
        RUBY

        # Create conflicting destination file
        FileUtils.mkdir_p(file("app/llm/agents"))
        File.write(file("app/llm/agents/conflicting_agent.rb"), <<~RUBY)
          module Llm
            class ConflictingAgent
              # New version - should be preserved
            end
          end
        RUBY

        run_generator
      end

      it "preserves the existing destination file" do
        content = file_content("app/llm/agents/conflicting_agent.rb")
        expect(content).to include("# New version - should be preserved")
      end

      it "does not move the conflicting source file" do
        # Source file should still exist since it wasn't moved
        expect(file_exists?("app/agents/conflicting_agent.rb")).to be true
      end
    end

    context "with mix of conflicting and non-conflicting files" do
      before do
        # Create source files
        FileUtils.mkdir_p(file("app/agents"))
        File.write(file("app/agents/conflicting_agent.rb"), "class ConflictingAgent\n  # SOURCE VERSION\nend")
        File.write(file("app/agents/new_agent.rb"), "class NewAgent; end")

        # Create conflicting destination
        FileUtils.mkdir_p(file("app/llm/agents"))
        File.write(file("app/llm/agents/conflicting_agent.rb"), "module Llm\n  class ConflictingAgent\n    # DESTINATION VERSION - should be preserved\n  end\nend")

        run_generator
      end

      it "migrates non-conflicting files" do
        expect(file_exists?("app/llm/agents/new_agent.rb")).to be true
      end

      it "preserves the existing destination file" do
        content = file_content("app/llm/agents/conflicting_agent.rb")
        # Should still have the original content from destination, not source
        expect(content).to include("DESTINATION VERSION - should be preserved")
        expect(content).not_to include("SOURCE VERSION")
      end
    end
  end

  describe "namespace wrapping idempotency" do
    before do
      # Mock database checks
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)
    end

    context "when file is already namespaced" do
      before do
        FileUtils.mkdir_p(file("app/agents"))
        File.write(file("app/agents/already_namespaced_agent.rb"), <<~RUBY)
          module Llm
            class AlreadyNamespacedAgent < RubyLLM::Agents::Base
            end
          end
        RUBY
        run_generator
      end

      it "does not double-wrap the namespace" do
        content = file_content("app/llm/agents/already_namespaced_agent.rb")
        expect(content.scan("module Llm").count).to eq(1)
      end
    end
  end

  describe "pretend mode (dry run)" do
    before do
      # Mock database checks
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)

      # Create source files
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/test_agent.rb"), "class TestAgent; end")

      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/test_tool.rb"), "class TestTool; end")
    end

    it "does not move agent files" do
      run_generator ["--pretend"]
      expect(file_exists?("app/agents/test_agent.rb")).to be true
      expect(file_exists?("app/llm/agents/test_agent.rb")).to be false
    end

    it "does not move tool files" do
      run_generator ["--pretend"]
      expect(file_exists?("app/tools/test_tool.rb")).to be true
      expect(file_exists?("app/llm/tools/test_tool.rb")).to be false
    end

    it "does not modify source files" do
      original_content = file_content("app/agents/test_agent.rb")
      run_generator ["--pretend"]
      expect(file_content("app/agents/test_agent.rb")).to eq(original_content)
    end
  end

  describe "full migration run idempotency" do
    before do
      # Mock database checks
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)

      # Create source files
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/my_agent.rb"), "class MyAgent; end")

      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/my_tool.rb"), "class MyTool; end")
    end

    it "can be run multiple times safely" do
      run_generator
      expect { run_generator }.not_to raise_error
    end

    it "does not duplicate namespace on second run" do
      run_generator
      run_generator

      content = file_content("app/llm/agents/my_agent.rb")
      expect(content.scan("module Llm").count).to eq(1)
    end
  end

  describe "combined agents and tools migration" do
    before do
      # Mock database checks
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)
        .with(:ruby_llm_agents_executions)
        .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:column_exists?).and_return(true)

      # Create both agents and tools
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/chat_agent.rb"), <<~RUBY)
        class ChatAgent < RubyLLM::Agents::Base
          tool :weather_tool
        end
      RUBY

      FileUtils.mkdir_p(file("app/tools"))
      File.write(file("app/tools/weather_tool.rb"), <<~RUBY)
        class WeatherTool < RubyLLM::Tool
          def call(city:)
            "Sunny in \#{city}"
          end
        end
      RUBY

      run_generator
    end

    it "migrates both agents and tools" do
      expect(file_exists?("app/llm/agents/chat_agent.rb")).to be true
      expect(file_exists?("app/llm/tools/weather_tool.rb")).to be true
    end

    it "removes both old directories" do
      expect(directory_exists?("app/agents")).to be false
      expect(directory_exists?("app/tools")).to be false
    end

    it "namespaces both agents and tools consistently" do
      agent_content = file_content("app/llm/agents/chat_agent.rb")
      tool_content = file_content("app/llm/tools/weather_tool.rb")

      expect(agent_content).to include("module Llm")
      expect(tool_content).to include("module Llm")
    end
  end
end
