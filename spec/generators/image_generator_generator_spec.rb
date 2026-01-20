# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_generator_generator"

RSpec.describe RubyLlmAgents::ImageGeneratorGenerator, type: :generator do
  describe "basic image generator generation" do
    before { run_generator ["Logo"] }

    it "creates the generator file with correct name" do
      expect(file_exists?("app/llm/image/generators/logo_generator.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageGenerator" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include("class LogoGenerator < ApplicationImageGenerator")
    end

    it "wraps the class in LLM::Image namespace" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include("module LLM")
      expect(content).to include("module Image")
    end

    it "includes default model configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('model "gpt-image-1"')
    end

    it "includes default size configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('size "1024x1024"')
    end

    it "includes default quality configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('quality "standard"')
    end

    it "includes default style configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('style "vivid"')
    end
  end

  describe "--model option" do
    before { run_generator ["Logo", "--model=dall-e-3"] }

    it "uses the specified model" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('model "dall-e-3"')
    end
  end

  describe "--size option" do
    before { run_generator ["Logo", "--size=1792x1024"] }

    it "uses the specified size" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('size "1792x1024"')
    end
  end

  describe "--quality option" do
    before { run_generator ["Logo", "--quality=hd"] }

    it "uses the specified quality" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('quality "hd"')
    end
  end

  describe "--style option" do
    before { run_generator ["Logo", "--style=natural"] }

    it "uses the specified style" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include('style "natural"')
    end
  end

  describe "--content_policy option" do
    before { run_generator ["Logo", "--content-policy=strict"] }

    it "includes content_policy configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include("content_policy :strict")
    end
  end

  describe "without --content_policy option (default standard)" do
    before { run_generator ["Logo"] }

    it "does not include content_policy (uses default)" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).not_to include("content_policy")
    end
  end

  describe "--cache option" do
    before { run_generator ["Logo", "--cache=1.day"] }

    it "includes cache configuration" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include("cache_for 1.day")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Logo"] }

    it "does not include caching by default" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Product",
        "--model=dall-e-3",
        "--size=1792x1024",
        "--quality=hd",
        "--style=natural",
        "--content-policy=moderate",
        "--cache=1.hour"
      ]
    end

    it "creates the generator file" do
      expect(file_exists?("app/llm/image/generators/product_generator.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/llm/image/generators/product_generator.rb")
      expect(content).to include("class ProductGenerator < ApplicationImageGenerator")
      expect(content).to include('model "dall-e-3"')
      expect(content).to include('size "1792x1024"')
      expect(content).to include('quality "hd"')
      expect(content).to include('style "natural"')
      expect(content).to include("content_policy :moderate")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["HeroImage"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/llm/image/generators/hero_image_generator.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/image/generators/hero_image_generator.rb")
      expect(content).to include("class HeroImageGenerator < ApplicationImageGenerator")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["product_shot"] }

    it "creates file with correct name" do
      expect(file_exists?("app/llm/image/generators/product_shot_generator.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/image/generators/product_shot_generator.rb")
      expect(content).to include("class ProductShotGenerator < ApplicationImageGenerator")
    end
  end

  describe "nested namespace" do
    before { run_generator ["marketing/banner"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/llm/image/generators/marketing/banner_generator.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/llm/image/generators/marketing/banner_generator.rb")
      expect(content).to include("module Marketing")
      expect(content).to include("class BannerGenerator < ApplicationImageGenerator")
    end
  end

  describe "preprocess_prompt comment" do
    before { run_generator ["Logo"] }

    it "includes commented preprocess_prompt method" do
      content = file_content("app/llm/image/generators/logo_generator.rb")
      expect(content).to include("# def preprocess_prompt(prompt)")
    end
  end

  describe "--root option" do
    before { run_generator ["Logo", "--root=ai"] }

    it "creates the generator in the ai directory" do
      expect(file_exists?("app/ai/image/generators/logo_generator.rb")).to be true
    end

    it "uses the AI::Image namespace" do
      content = file_content("app/ai/image/generators/logo_generator.rb")
      expect(content).to include("module AI")
      expect(content).to include("module Image")
    end
  end
end
