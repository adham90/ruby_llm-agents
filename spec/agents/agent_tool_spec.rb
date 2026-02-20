# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::AgentTool do
  # Real test agent classes — no mocks per CLAUDE.md
  let(:research_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "ResearchAgent"
      end

      description "Search and gather information on a topic"
      model "gpt-4o-mini"
      param :query, required: true, desc: "The research query"
      param :limit, default: 10, type: Integer, desc: "Max results"
    end
  end

  let(:code_review_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "CodeReviewAgent"
      end

      description "Review code for bugs and style issues"
      param :code, required: true, desc: "Code to review"
    end
  end

  let(:no_desc_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "PlainAgent"
      end

      param :input, required: true
    end
  end

  let(:no_params_agent) do
    Class.new(RubyLLM::Agents::BaseAgent) do
      def self.name
        "SimpleAgent"
      end

      description "A simple agent with no params"
    end
  end

  describe ".derive_tool_name" do
    it "strips Agent suffix and snake_cases" do
      expect(described_class.derive_tool_name(research_agent)).to eq("research")
    end

    it "handles multi-word names" do
      expect(described_class.derive_tool_name(code_review_agent)).to eq("code_review")
    end

    it "handles names without Agent suffix" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "Summarizer"
        end
      end
      expect(described_class.derive_tool_name(klass)).to eq("summarizer")
    end

    it "handles namespaced class names" do
      klass = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "MyApp::Agents::DataAnalysisAgent"
        end
      end
      expect(described_class.derive_tool_name(klass)).to eq("data_analysis")
    end
  end

  describe ".map_type" do
    it "maps Integer to :integer" do
      expect(described_class.map_type(Integer)).to eq(:integer)
    end

    it "maps :integer to :integer" do
      expect(described_class.map_type(:integer)).to eq(:integer)
    end

    it "maps Float to :number" do
      expect(described_class.map_type(Float)).to eq(:number)
    end

    it "maps :number to :number" do
      expect(described_class.map_type(:number)).to eq(:number)
    end

    it "maps :boolean to :boolean" do
      expect(described_class.map_type(:boolean)).to eq(:boolean)
    end

    it "maps Array to :array" do
      expect(described_class.map_type(Array)).to eq(:array)
    end

    it "maps Hash to :object" do
      expect(described_class.map_type(Hash)).to eq(:object)
    end

    it "defaults nil to :string" do
      expect(described_class.map_type(nil)).to eq(:string)
    end

    it "defaults String to :string" do
      expect(described_class.map_type(String)).to eq(:string)
    end
  end

  describe ".for" do
    it "returns a class that inherits from RubyLLM::Tool" do
      tool_class = described_class.for(research_agent)
      expect(tool_class).to be < RubyLLM::Tool
    end

    it "remembers the original agent class" do
      tool_class = described_class.for(research_agent)
      expect(tool_class.agent_class).to eq(research_agent)
    end

    it "derives the correct tool name" do
      tool_class = described_class.for(research_agent)
      expect(tool_class.tool_name).to eq("research")
    end

    it "sets description from the agent" do
      tool_class = described_class.for(research_agent)
      expect(tool_class.description).to eq("Search and gather information on a topic")
    end

    it "maps agent params to tool parameters" do
      tool_class = described_class.for(research_agent)
      params = tool_class.parameters

      expect(params[:query]).to be_a(RubyLLM::Parameter)
      expect(params[:query].required).to be true
      expect(params[:query].description).to eq("The research query")

      expect(params[:limit]).to be_a(RubyLLM::Parameter)
      expect(params[:limit].required).to be false
      expect(params[:limit].type).to eq(:integer)
    end

    it "skips internal params starting with _" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "InternalParamAgent"
        end

        param :query, required: true, desc: "Query"
        param :_internal, default: nil
      end

      tool_class = described_class.for(agent)
      expect(tool_class.parameters.keys).to eq([:query])
    end

    it "works with agents that have no params" do
      tool_class = described_class.for(no_params_agent)
      expect(tool_class.parameters).to be_empty
    end

    it "works with agents that have no description" do
      tool_class = described_class.for(no_desc_agent)
      expect(tool_class.description).to be_nil
    end

    describe "instance behavior" do
      it "returns the derived tool name from #name" do
        tool_class = described_class.for(research_agent)
        tool_instance = tool_class.new
        expect(tool_instance.name).to eq("research")
      end
    end
  end

  describe "tool execution" do
    it "calls the agent and returns string content" do
      # Set up a simple agent that returns a known result
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "EchoAgent"
        end

        description "Echoes input"
        param :message, required: true, desc: "Message to echo"

        def user_prompt
          message
        end
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      # Mock only the LLM boundary (per CLAUDE.md)
      result = RubyLLM::Agents::Result.new(content: "Echo: hello")
      allow(agent).to receive(:call).and_return(result)

      output = tool_instance.execute(message: "hello")
      expect(output).to eq("Echo: hello")
    end

    it "converts hash content to JSON" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "HashAgent"
        end

        description "Returns hash"
        param :input, required: true, desc: "Input"
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      result = RubyLLM::Agents::Result.new(content: {key: "value"})
      allow(agent).to receive(:call).and_return(result)

      output = tool_instance.execute(input: "test")
      expect(output).to eq({key: "value"}.to_json)
    end

    it "returns '(no response)' for nil content" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "NilAgent"
        end

        description "Returns nil"
        param :input, required: true, desc: "Input"
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      result = RubyLLM::Agents::Result.new(content: nil)
      allow(agent).to receive(:call).and_return(result)

      output = tool_instance.execute(input: "test")
      expect(output).to eq("(no response)")
    end

    it "catches errors and returns error message" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "ErrorAgent"
        end

        description "Errors out"
        param :input, required: true, desc: "Input"
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      allow(agent).to receive(:call).and_raise(RuntimeError, "Something went wrong")

      output = tool_instance.execute(input: "test")
      expect(output).to include("Error calling ErrorAgent")
      expect(output).to include("Something went wrong")
    end
  end

  describe "depth guard" do
    it "raises when max depth is exceeded" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "DeepAgent"
        end

        description "Goes deep"
        param :input, required: true, desc: "Input"
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      # Simulate being already at max depth
      Thread.current[:ruby_llm_agents_tool_depth] = RubyLLM::Agents::AgentTool::MAX_AGENT_TOOL_DEPTH

      output = tool_instance.execute(input: "test")
      expect(output).to include("depth exceeded")
    ensure
      Thread.current[:ruby_llm_agents_tool_depth] = nil
    end

    it "increments and decrements depth correctly" do
      agent = Class.new(RubyLLM::Agents::BaseAgent) do
        def self.name
          "DepthAgent"
        end

        description "Tracks depth"
        param :input, required: true, desc: "Input"
      end

      tool_class = described_class.for(agent)
      tool_instance = tool_class.new

      result = RubyLLM::Agents::Result.new(content: "ok")
      allow(agent).to receive(:call).and_return(result)

      expect(Thread.current[:ruby_llm_agents_tool_depth]).to be_nil
      tool_instance.execute(input: "test")
      expect(Thread.current[:ruby_llm_agents_tool_depth]).to eq(0)
    ensure
      Thread.current[:ruby_llm_agents_tool_depth] = nil
    end
  end
end
