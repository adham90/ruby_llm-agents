# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_analyzer_generator"

RSpec.describe RubyLlmAgents::ImageAnalyzerGenerator, type: :generator do
  describe "basic image analyzer generation" do
    before { run_generator ["Product"] }

    it "creates the analyzer file with correct name" do
      expect(file_exists?("app/agents/images/product_analyzer.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageAnalyzer" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("class ProductAnalyzer < ApplicationImageAnalyzer")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include('model "gpt-4o"')
    end

    it "includes default analysis_type configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("analysis_type :detailed")
    end
  end

  describe "--model option" do
    before { run_generator ["Product", "--model=gpt-4-vision-preview"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include('model "gpt-4-vision-preview"')
    end
  end

  describe "--analysis_type option" do
    before { run_generator ["Product", "--analysis-type=all"] }

    it "uses the specified analysis type" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("analysis_type :all")
    end
  end

  describe "--extract_colors option" do
    before { run_generator ["Product", "--extract-colors"] }

    it "includes extract_colors configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("extract_colors true")
    end
  end

  describe "--detect_objects option" do
    before { run_generator ["Product", "--detect-objects"] }

    it "includes detect_objects configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("detect_objects true")
    end
  end

  describe "--extract_text option" do
    before { run_generator ["Product", "--extract-text"] }

    it "includes extract_text configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("extract_text true")
    end
  end

  describe "--max_tags option" do
    before { run_generator ["Product", "--max-tags=20"] }

    it "includes max_tags configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("max_tags 20")
    end
  end

  describe "--cache option" do
    before { run_generator ["Product", "--cache=1.hour"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Product"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/product_analyzer.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Photo",
        "--model=gpt-4o",
        "--analysis-type=all",
        "--extract-colors",
        "--detect-objects",
        "--extract-text",
        "--max-tags=15",
        "--cache=1.day"
      ]
    end

    it "creates the analyzer file" do
      expect(file_exists?("app/agents/images/photo_analyzer.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/photo_analyzer.rb")
      expect(content).to include("class PhotoAnalyzer < ApplicationImageAnalyzer")
      expect(content).to include('model "gpt-4o"')
      expect(content).to include("analysis_type :all")
      expect(content).to include("extract_colors true")
      expect(content).to include("detect_objects true")
      expect(content).to include("extract_text true")
      expect(content).to include("max_tags 15")
      expect(content).to include("cache_for 1.day")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["ProductPhoto"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/product_photo_analyzer.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/product_photo_analyzer.rb")
      expect(content).to include("class ProductPhotoAnalyzer < ApplicationImageAnalyzer")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["hero_image"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/hero_image_analyzer.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/hero_image_analyzer.rb")
      expect(content).to include("class HeroImageAnalyzer < ApplicationImageAnalyzer")
    end
  end

  describe "nested namespace" do
    before { run_generator ["marketing/banner"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/marketing/banner_analyzer.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/marketing/banner_analyzer.rb")
      expect(content).to include("module Marketing")
      expect(content).to include("class BannerAnalyzer < ApplicationImageAnalyzer")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_analyzer.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_ANALYZERS.md")).to be true
    end
  end
end
