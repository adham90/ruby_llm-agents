# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::ImageGenerator do
  let(:test_prompt) { "A beautiful sunset over the ocean" }
  let(:mock_image) { instance_double(RubyLLM::Image, url: "https://example.com/image.png", data: nil) }

  before do
    allow(RubyLLM).to receive(:paint).and_return(mock_image)
  end

  describe "class methods" do
    describe ".agent_type" do
      it "returns :image" do
        expect(described_class.agent_type).to eq(:image)
      end
    end

    describe ".model" do
      it "returns default image model from configuration" do
        expect(described_class.model).to eq(RubyLLM::Agents.configuration.default_image_model)
      end

      context "when configured" do
        before { described_class.model("custom-model") }
        after { described_class.instance_variable_set(:@model, nil) }

        it "returns configured model" do
          expect(described_class.model).to eq("custom-model")
        end
      end
    end

    describe ".size" do
      it "returns default size" do
        expect(described_class.size).to eq("1024x1024")
      end

      context "when configured" do
        before { described_class.size("1792x1024") }
        after { described_class.instance_variable_set(:@size, nil) }

        it "returns configured size" do
          expect(described_class.size).to eq("1792x1024")
        end
      end
    end

    describe ".quality" do
      it "returns default quality" do
        expect(described_class.quality).to eq("standard")
      end

      context "when configured" do
        before { described_class.quality("hd") }
        after { described_class.instance_variable_set(:@quality, nil) }

        it "returns configured quality" do
          expect(described_class.quality).to eq("hd")
        end
      end
    end

    describe ".style" do
      it "returns default style" do
        expect(described_class.style).to eq("vivid")
      end

      context "when configured" do
        before { described_class.style("natural") }
        after { described_class.instance_variable_set(:@style, nil) }

        it "returns configured style" do
          expect(described_class.style).to eq("natural")
        end
      end
    end

    describe ".negative_prompt" do
      it "returns nil by default" do
        expect(described_class.negative_prompt).to be_nil
      end

      context "when configured" do
        before { described_class.negative_prompt("blurry, low quality") }
        after { described_class.instance_variable_set(:@negative_prompt, nil) }

        it "returns configured negative_prompt" do
          expect(described_class.negative_prompt).to eq("blurry, low quality")
        end
      end
    end

    describe ".seed" do
      it "returns nil by default" do
        expect(described_class.seed).to be_nil
      end

      context "when configured" do
        before { described_class.seed(12345) }
        after { described_class.instance_variable_set(:@seed, nil) }

        it "returns configured seed" do
          expect(described_class.seed).to eq(12345)
        end
      end
    end

    describe ".guidance_scale" do
      it "returns nil by default" do
        expect(described_class.guidance_scale).to be_nil
      end

      context "when configured" do
        before { described_class.guidance_scale(7.5) }
        after { described_class.instance_variable_set(:@guidance_scale, nil) }

        it "returns configured guidance_scale" do
          expect(described_class.guidance_scale).to eq(7.5)
        end
      end
    end

    describe ".steps" do
      it "returns nil by default" do
        expect(described_class.steps).to be_nil
      end

      context "when configured" do
        before { described_class.steps(50) }
        after { described_class.instance_variable_set(:@steps, nil) }

        it "returns configured steps" do
          expect(described_class.steps).to eq(50)
        end
      end
    end

    describe ".template" do
      it "returns nil by default" do
        expect(described_class.template_string).to be_nil
      end

      context "when configured" do
        before { described_class.template("Professional photo of {prompt}") }
        after { described_class.instance_variable_set(:@template_string, nil) }

        it "returns configured template" do
          expect(described_class.template_string).to eq("Professional photo of {prompt}")
        end
      end
    end

    describe ".call" do
      it "creates instance and calls" do
        result = described_class.call(prompt: test_prompt)
        expect(result).to be_a(RubyLLM::Agents::ImageGenerationResult)
      end
    end
  end

  describe "instance methods" do
    let(:generator) { described_class.new(prompt: test_prompt) }

    describe "#initialize" do
      it "stores the prompt" do
        expect(generator.prompt).to eq(test_prompt)
      end

      it "accepts runtime options" do
        gen = described_class.new(prompt: test_prompt, size: "512x512")
        expect(gen.instance_variable_get(:@options)[:size]).to eq("512x512")
      end

      it "accepts count option" do
        gen = described_class.new(prompt: test_prompt, count: 3)
        expect(gen.instance_variable_get(:@runtime_count)).to eq(3)
      end
    end

    describe "#call" do
      it "returns ImageGenerationResult" do
        result = generator.call
        expect(result).to be_a(RubyLLM::Agents::ImageGenerationResult)
      end

      it "calls RubyLLM.paint with correct options" do
        default_model = RubyLLM::Agents.configuration.default_image_model
        expect(RubyLLM).to receive(:paint).with(
          test_prompt,
          hash_including(
            model: default_model,
            size: "1024x1024"
          )
        ).and_return(mock_image)

        generator.call
      end

      context "with multiple images" do
        let(:generator) { described_class.new(prompt: test_prompt, count: 2) }

        it "calls RubyLLM.paint multiple times" do
          expect(RubyLLM).to receive(:paint).exactly(2).times.and_return(mock_image)
          generator.call
        end
      end

      context "with custom options" do
        let(:generator) do
          described_class.new(
            prompt: test_prompt,
            size: "1792x1024",
            quality: "hd",
            style: "natural"
          )
        end

        it "passes custom options to RubyLLM.paint" do
          expect(RubyLLM).to receive(:paint).with(
            test_prompt,
            hash_including(
              size: "1792x1024",
              quality: "hd",
              style: "natural"
            )
          ).and_return(mock_image)

          generator.call
        end
      end
    end

    describe "#user_prompt" do
      it "returns the prompt" do
        expect(generator.user_prompt).to eq(test_prompt)
      end
    end

    describe "#agent_cache_key" do
      it "includes class name and prompt hash" do
        key = generator.agent_cache_key
        expect(key).to include("ruby_llm_agents")
        expect(key).to include("image_generator")
        expect(key).to include("RubyLLM::Agents::ImageGenerator")
      end

      it "varies by prompt" do
        gen1 = described_class.new(prompt: "prompt one")
        gen2 = described_class.new(prompt: "prompt two")
        expect(gen1.agent_cache_key).not_to eq(gen2.agent_cache_key)
      end
    end
  end

  describe "validation" do
    describe "prompt validation" do
      it "returns error result for nil prompt" do
        gen = described_class.new(prompt: nil)
        result = gen.call
        expect(result.error_message).to match(/Prompt cannot be blank/)
        expect(result.error_class).to eq("ArgumentError")
      end

      it "returns error result for empty prompt" do
        gen = described_class.new(prompt: "")
        result = gen.call
        expect(result.error_message).to match(/Prompt cannot be blank/)
        expect(result.error_class).to eq("ArgumentError")
      end

      it "returns error result for whitespace-only prompt" do
        gen = described_class.new(prompt: "   ")
        result = gen.call
        expect(result.error_message).to match(/Prompt cannot be blank/)
        expect(result.error_class).to eq("ArgumentError")
      end
    end
  end

  describe "result handling" do
    let(:result) { described_class.call(prompt: test_prompt) }

    it "includes prompt in result" do
      expect(result.prompt).to eq(test_prompt)
    end

    it "includes model in result" do
      expect(result.model_id).to eq(RubyLLM::Agents.configuration.default_image_model)
    end

    it "includes size in result" do
      expect(result.size).to eq("1024x1024")
    end

    it "includes quality in result" do
      expect(result.quality).to eq("standard")
    end

    it "includes style in result" do
      expect(result.style).to eq("vivid")
    end

    it "includes timing information" do
      expect(result.started_at).to be_a(Time)
      expect(result.completed_at).to be_a(Time)
    end

    it "includes generator class name" do
      expect(result.generator_class).to eq("RubyLLM::Agents::ImageGenerator")
    end
  end

  describe "error handling" do
    context "when RubyLLM.paint raises an error" do
      before do
        allow(RubyLLM).to receive(:paint).and_raise(StandardError.new("API error"))
      end

      it "returns error result" do
        result = described_class.call(prompt: test_prompt)
        expect(result.error_message).to eq("API error")
        expect(result.error_class).to eq("StandardError")
      end
    end
  end

  describe "inheritance" do
    let(:custom_generator_class) do
      Class.new(described_class) do
        model "gpt-image-1"
        size "512x512"
        quality "hd"
        style "natural"
        negative_prompt "blurry"
        seed 42
        template "Photo of {prompt}"

        def self.name
          "CustomImageGenerator"
        end
      end
    end

    it "inherits model setting" do
      expect(custom_generator_class.model).to eq("gpt-image-1")
    end

    it "inherits size setting" do
      expect(custom_generator_class.size).to eq("512x512")
    end

    it "inherits quality setting" do
      expect(custom_generator_class.quality).to eq("hd")
    end

    it "inherits style setting" do
      expect(custom_generator_class.style).to eq("natural")
    end

    it "inherits negative_prompt setting" do
      expect(custom_generator_class.negative_prompt).to eq("blurry")
    end

    it "inherits seed setting" do
      expect(custom_generator_class.seed).to eq(42)
    end

    it "inherits template setting" do
      expect(custom_generator_class.template_string).to eq("Photo of {prompt}")
    end

    it "returns :image agent_type" do
      expect(custom_generator_class.agent_type).to eq(:image)
    end

    context "when calling custom generator" do
      it "uses custom settings" do
        expect(RubyLLM).to receive(:paint).with(
          "Photo of #{test_prompt}",
          hash_including(
            model: "gpt-image-1",
            size: "512x512",
            quality: "hd",
            style: "natural",
            negative_prompt: "blurry",
            seed: 42
          )
        ).and_return(mock_image)

        custom_generator_class.call(prompt: test_prompt)
      end
    end
  end

  describe "template application" do
    let(:templated_class) do
      Class.new(described_class) do
        template "Professional photograph of {prompt}, 8k resolution"

        def self.name
          "TemplatedGenerator"
        end
      end
    end

    it "applies template to prompt" do
      expect(RubyLLM).to receive(:paint).with(
        "Professional photograph of #{test_prompt}, 8k resolution",
        anything
      ).and_return(mock_image)

      templated_class.call(prompt: test_prompt)
    end
  end

  describe "middleware pipeline integration" do
    it "executes through pipeline" do
      expect(RubyLLM::Agents::Pipeline::Executor).to receive(:execute).and_call_original
      described_class.call(prompt: test_prompt)
    end
  end
end
