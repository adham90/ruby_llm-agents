# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_editor_generator"

RSpec.describe RubyLlmAgents::ImageEditorGenerator, type: :generator do
  describe "basic image editor generation" do
    before { run_generator ["Background"] }

    it "creates the editor file with correct name" do
      expect(file_exists?("app/agents/images/background_editor.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageEditor" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include("class BackgroundEditor < ApplicationImageEditor")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include('model "gpt-image-1"')
    end

    it "includes default size configuration" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include('size "1024x1024"')
    end
  end

  describe "--model option" do
    before { run_generator ["Background", "--model=dall-e-2"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include('model "dall-e-2"')
    end
  end

  describe "--size option" do
    before { run_generator ["Background", "--size=512x512"] }

    it "uses the specified size" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include('size "512x512"')
    end
  end

  describe "--content_policy option" do
    before { run_generator ["Background", "--content-policy=strict"] }

    it "includes content_policy configuration" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include("content_policy :strict")
    end
  end

  describe "without --content_policy option (default standard)" do
    before { run_generator ["Background"] }

    it "does not include content_policy (uses default)" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).not_to include("content_policy")
    end
  end

  describe "--cache option" do
    before { run_generator ["Background", "--cache=1.hour"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Background"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/background_editor.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Photo",
        "--model=gpt-image-1",
        "--size=1792x1024",
        "--content-policy=moderate",
        "--cache=30.minutes"
      ]
    end

    it "creates the editor file" do
      expect(file_exists?("app/agents/images/photo_editor.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/photo_editor.rb")
      expect(content).to include("class PhotoEditor < ApplicationImageEditor")
      expect(content).to include('model "gpt-image-1"')
      expect(content).to include('size "1792x1024"')
      expect(content).to include("content_policy :moderate")
      expect(content).to include("cache_for 30.minutes")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["ProductImage"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/product_image_editor.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/product_image_editor.rb")
      expect(content).to include("class ProductImageEditor < ApplicationImageEditor")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["hero_banner"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/hero_banner_editor.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/hero_banner_editor.rb")
      expect(content).to include("class HeroBannerEditor < ApplicationImageEditor")
    end
  end

  describe "nested namespace" do
    before { run_generator ["marketing/banner"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/marketing/banner_editor.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/marketing/banner_editor.rb")
      expect(content).to include("module Marketing")
      expect(content).to include("class BannerEditor < ApplicationImageEditor")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_editor.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_EDITORS.md")).to be true
    end
  end
end
