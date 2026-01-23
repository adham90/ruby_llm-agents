# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_upscaler_generator"

RSpec.describe RubyLlmAgents::ImageUpscalerGenerator, type: :generator do
  describe "basic image upscaler generation" do
    before { run_generator ["Photo"] }

    it "creates the upscaler file with correct name" do
      expect(file_exists?("app/agents/images/photo_upscaler.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageUpscaler" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("class PhotoUpscaler < ApplicationImageUpscaler")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include('model "real-esrgan"')
    end

    it "includes default scale configuration" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("scale 4")
    end
  end

  describe "--model option" do
    before { run_generator ["Photo", "--model=esrgan-plus"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include('model "esrgan-plus"')
    end
  end

  describe "--scale option" do
    before { run_generator ["Photo", "--scale=8"] }

    it "uses the specified scale" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("scale 8")
    end
  end

  describe "--face_enhance option" do
    before { run_generator ["Photo", "--face-enhance"] }

    it "includes face_enhance configuration" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("face_enhance true")
    end
  end

  describe "without --face_enhance option" do
    before { run_generator ["Photo"] }

    it "does not include face_enhance by default" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).not_to include("face_enhance true")
    end
  end

  describe "--cache option" do
    before { run_generator ["Photo", "--cache=2.hours"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).to include("cache_for 2.hours")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Photo"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/photo_upscaler.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Portrait",
        "--model=real-esrgan",
        "--scale=4",
        "--face-enhance",
        "--cache=1.day"
      ]
    end

    it "creates the upscaler file" do
      expect(file_exists?("app/agents/images/portrait_upscaler.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/portrait_upscaler.rb")
      expect(content).to include("class PortraitUpscaler < ApplicationImageUpscaler")
      expect(content).to include('model "real-esrgan"')
      expect(content).to include("scale 4")
      expect(content).to include("face_enhance true")
      expect(content).to include("cache_for 1.day")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["LowRes"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/low_res_upscaler.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/low_res_upscaler.rb")
      expect(content).to include("class LowResUpscaler < ApplicationImageUpscaler")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["small_image"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/small_image_upscaler.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/small_image_upscaler.rb")
      expect(content).to include("class SmallImageUpscaler < ApplicationImageUpscaler")
    end
  end

  describe "nested namespace" do
    before { run_generator ["enhancement/quality"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/enhancement/quality_upscaler.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/enhancement/quality_upscaler.rb")
      expect(content).to include("module Enhancement")
      expect(content).to include("class QualityUpscaler < ApplicationImageUpscaler")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_upscaler.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_UPSCALERS.md")).to be true
    end
  end
end
