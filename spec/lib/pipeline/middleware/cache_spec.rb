# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pipeline::Middleware::Cache do
  let(:agent_class) do
    Class.new do
      def self.name
        "TestAgent"
      end

      def self.agent_type
        :embedding
      end

      def self.model
        "test-model"
      end

      def self.cache_enabled?
        true
      end

      def self.cache_ttl
        3600
      end
    end
  end

  let(:app) { double("app") }
  let(:middleware) { described_class.new(app, agent_class) }
  let(:config) { instance_double(RubyLLM::Agents::Configuration) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  def build_context(options = {})
    RubyLLM::Agents::Pipeline::Context.new(
      input: "test input",
      agent_class: agent_class,
      **options
    )
  end

  before do
    allow(RubyLLM::Agents).to receive(:configuration).and_return(config)
    allow(config).to receive(:cache_store).and_return(cache_store)
  end

  describe "#call" do
    context "when caching is disabled" do
      let(:agent_class_no_cache) do
        Class.new do
          def self.name
            "NoCacheAgent"
          end

          def self.cache_enabled?
            false
          end
        end
      end

      let(:middleware) { described_class.new(app, agent_class_no_cache) }

      it "passes through to the next middleware" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: "test",
          agent_class: agent_class_no_cache
        )
        expect(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)
        expect(result).to eq(context)
      end
    end

    context "when cache store is not configured" do
      before do
        allow(config).to receive(:cache_store).and_return(nil)
      end

      it "passes through to the next middleware" do
        context = build_context
        expect(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)
        expect(result).to eq(context)
      end
    end

    context "when caching is enabled" do
      it "returns cached result on cache hit" do
        context = build_context
        cached_output = { embedding: [0.1, 0.2, 0.3] }

        # Pre-populate cache
        cache_key = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('test input')}"
        cache_store.write(cache_key, cached_output)

        # Should not call the next middleware on cache hit
        expect(app).not_to receive(:call)

        result = middleware.call(context)

        expect(result.output).to eq(cached_output)
        expect(result.cached).to be true
      end

      it "executes and caches on cache miss" do
        context = build_context
        expected_output = { embedding: [0.4, 0.5, 0.6] }

        expect(app).to receive(:call) do |ctx|
          ctx.output = expected_output
          ctx
        end

        result = middleware.call(context)

        expect(result.output).to eq(expected_output)
        expect(result.cached).to be_falsey

        # Verify it was cached
        cache_key = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('test input')}"
        expect(cache_store.read(cache_key)).to eq(expected_output)
      end

      it "does not cache failed results" do
        context = build_context

        allow(app).to receive(:call) do |ctx|
          ctx.error = StandardError.new("Failed")
          ctx
        end

        result = middleware.call(context)

        # Verify it was not cached
        cache_key = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('test input')}"
        expect(cache_store.read(cache_key)).to be_nil
      end

      it "uses cache TTL from agent class" do
        context = build_context
        expected_output = { embedding: [0.4, 0.5, 0.6] }

        allow(app).to receive(:call) do |ctx|
          ctx.output = expected_output
          ctx
        end

        expect(cache_store).to receive(:write).with(
          anything,
          expected_output,
          hash_including(expires_in: 3600)
        )

        middleware.call(context)
      end
    end

    context "cache key generation" do
      it "includes agent type in cache key" do
        context = build_context
        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        middleware.call(context)

        cache_key = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('test input')}"
        expect(cache_store.exist?(cache_key)).to be true
      end

      it "generates different keys for different inputs" do
        context1 = build_context(input: "input one")
        context2 = RubyLLM::Agents::Pipeline::Context.new(
          input: "input two",
          agent_class: agent_class
        )

        allow(app).to receive(:call) do |ctx|
          ctx.output = "result for #{ctx.input}"
          ctx
        end

        middleware.call(context1)
        middleware.call(context2)

        key1 = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('input one')}"
        key2 = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('input two')}"

        expect(cache_store.read(key1)).to eq("result for input one")
        expect(cache_store.read(key2)).to eq("result for input two")
      end

      it "handles array inputs" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: %w[text1 text2],
          agent_class: agent_class
        )

        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        # Should not raise
        expect { middleware.call(context) }.not_to raise_error
      end

      it "handles hash inputs" do
        context = RubyLLM::Agents::Pipeline::Context.new(
          input: { text: "hello", options: { format: "json" } },
          agent_class: agent_class
        )

        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        # Should not raise
        expect { middleware.call(context) }.not_to raise_error
      end

      it "handles complex objects that fail to_json" do
        # Create an object that will fail JSON serialization
        complex_object = Object.new
        def complex_object.to_json
          raise "Cannot serialize"
        end

        def complex_object.to_s
          "fallback_string"
        end

        context = RubyLLM::Agents::Pipeline::Context.new(
          input: complex_object,
          agent_class: agent_class
        )

        allow(app).to receive(:call) { |ctx| ctx.output = "result"; ctx }

        # Should not raise, falls back to to_s
        expect { middleware.call(context) }.not_to raise_error
      end
    end

    context "error handling" do
      it "continues execution when cache read fails" do
        context = build_context
        expected_output = { embedding: [0.4, 0.5, 0.6] }

        # Make cache read fail
        allow(cache_store).to receive(:read).and_raise(StandardError.new("Read failed"))

        expect(app).to receive(:call) do |ctx|
          ctx.output = expected_output
          ctx
        end

        result = middleware.call(context)
        expect(result.output).to eq(expected_output)
      end

      it "continues execution when cache write fails" do
        context = build_context
        expected_output = { embedding: [0.4, 0.5, 0.6] }

        # Allow read but fail write
        allow(cache_store).to receive(:read).and_return(nil)
        allow(cache_store).to receive(:write).and_raise(StandardError.new("Write failed"))

        expect(app).to receive(:call) do |ctx|
          ctx.output = expected_output
          ctx
        end

        result = middleware.call(context)
        expect(result.output).to eq(expected_output)
      end

      it "passes through when cache_store raises an error" do
        context = build_context

        # Make configuration fail when accessing cache_store
        allow(config).to receive(:cache_store).and_raise(StandardError.new("Config error"))

        expect(app).to receive(:call).with(context).and_return(context)

        result = middleware.call(context)
        expect(result).to eq(context)
      end
    end

    context "with skip_cache option" do
      it "skips cache read but still writes when skip_cache is true" do
        context = build_context(skip_cache: true)
        cached_output = { embedding: [0.1, 0.2, 0.3] }
        new_output = { embedding: [0.4, 0.5, 0.6] }

        # Pre-populate cache
        cache_key = "ruby_llm_agents/embedding/TestAgent/test-model/#{Digest::SHA256.hexdigest('test input')}"
        cache_store.write(cache_key, cached_output)

        # Should call the next middleware even though cache has a value
        expect(app).to receive(:call) do |ctx|
          ctx.output = new_output
          ctx
        end

        result = middleware.call(context)

        # Should get the fresh result, not cached
        expect(result.output).to eq(new_output)
        expect(result.cached).to be_falsey
      end
    end
  end
end
