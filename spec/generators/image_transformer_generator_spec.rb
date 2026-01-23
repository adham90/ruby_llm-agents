# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_transformer_generator"

RSpec.describe RubyLlmAgents::ImageTransformerGenerator, type: :generator do
  describe "basic image transformer generation" do
    before { run_generator ["Anime"] }

    it "creates the transformer file with correct name" do
      expect(file_exists?("app/agents/images/anime_transformer.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageTransformer" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("class AnimeTransformer < ApplicationImageTransformer")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include('model "sdxl"')
    end

    it "includes default size configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include('size "1024x1024"')
    end

    it "includes default strength configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("strength 0.75")
    end
  end

  describe "--model option" do
    before { run_generator ["Anime", "--model=stable-diffusion-xl"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include('model "stable-diffusion-xl"')
    end
  end

  describe "--size option" do
    before { run_generator ["Anime", "--size=768x768"] }

    it "uses the specified size" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include('size "768x768"')
    end
  end

  describe "--strength option" do
    before { run_generator ["Anime", "--strength=0.9"] }

    it "uses the specified strength" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("strength 0.9")
    end
  end

  describe "--template option" do
    before { run_generator ["Anime", "--template=anime style, {prompt}"] }

    it "includes template configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("template")
      expect(content).to include("anime style, {prompt}")
    end
  end

  describe "--content_policy option" do
    before { run_generator ["Anime", "--content-policy=strict"] }

    it "includes content_policy configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("content_policy :strict")
    end
  end

  describe "without --content_policy option (default standard)" do
    before { run_generator ["Anime"] }

    it "does not include content_policy (uses default)" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).not_to include("content_policy")
    end
  end

  describe "--cache option" do
    before { run_generator ["Anime", "--cache=2.hours"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).to include("cache_for 2.hours")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Anime"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/anime_transformer.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Watercolor",
        "--model=sdxl",
        "--size=1024x1024",
        "--strength=0.8",
        "--content-policy=moderate",
        "--cache=1.hour"
      ]
    end

    it "creates the transformer file" do
      expect(file_exists?("app/agents/images/watercolor_transformer.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/watercolor_transformer.rb")
      expect(content).to include("class WatercolorTransformer < ApplicationImageTransformer")
      expect(content).to include('model "sdxl"')
      expect(content).to include('size "1024x1024"')
      expect(content).to include("strength 0.8")
      expect(content).to include("content_policy :moderate")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["OilPainting"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/oil_painting_transformer.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/oil_painting_transformer.rb")
      expect(content).to include("class OilPaintingTransformer < ApplicationImageTransformer")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["pencil_sketch"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/pencil_sketch_transformer.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/pencil_sketch_transformer.rb")
      expect(content).to include("class PencilSketchTransformer < ApplicationImageTransformer")
    end
  end

  describe "nested namespace" do
    before { run_generator ["styles/vintage"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/styles/vintage_transformer.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/styles/vintage_transformer.rb")
      expect(content).to include("module Styles")
      expect(content).to include("class VintageTransformer < ApplicationImageTransformer")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_transformer.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_TRANSFORMERS.md")).to be true
    end
  end
end
