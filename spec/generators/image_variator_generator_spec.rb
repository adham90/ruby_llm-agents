# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_variator_generator"

RSpec.describe RubyLlmAgents::ImageVariatorGenerator, type: :generator do
  describe "basic image variator generation" do
    before { run_generator ["Logo"] }

    it "creates the variator file with correct name" do
      expect(file_exists?("app/agents/images/logo_variator.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImageVariator" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include("class LogoVariator < ApplicationImageVariator")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include('model "gpt-image-1"')
    end

    it "includes default size configuration" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include('size "1024x1024"')
    end

    it "includes default variation_strength configuration" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include("variation_strength 0.5")
    end
  end

  describe "--model option" do
    before { run_generator ["Logo", "--model=dall-e-2"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include('model "dall-e-2"')
    end
  end

  describe "--size option" do
    before { run_generator ["Logo", "--size=512x512"] }

    it "uses the specified size" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include('size "512x512"')
    end
  end

  describe "--variation_strength option" do
    before { run_generator ["Logo", "--variation-strength=0.8"] }

    it "uses the specified variation strength" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include("variation_strength 0.8")
    end
  end

  describe "--cache option" do
    before { run_generator ["Logo", "--cache=30.minutes"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).to include("cache_for 30.minutes")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Logo"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/logo_variator.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Product",
        "--model=gpt-image-1",
        "--size=1024x1024",
        "--variation-strength=0.7",
        "--cache=1.hour"
      ]
    end

    it "creates the variator file" do
      expect(file_exists?("app/agents/images/product_variator.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/product_variator.rb")
      expect(content).to include("class ProductVariator < ApplicationImageVariator")
      expect(content).to include('model "gpt-image-1"')
      expect(content).to include('size "1024x1024"')
      expect(content).to include("variation_strength 0.7")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["BrandLogo"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/brand_logo_variator.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/brand_logo_variator.rb")
      expect(content).to include("class BrandLogoVariator < ApplicationImageVariator")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["company_icon"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/company_icon_variator.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/company_icon_variator.rb")
      expect(content).to include("class CompanyIconVariator < ApplicationImageVariator")
    end
  end

  describe "nested namespace" do
    before { run_generator ["branding/icon"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/branding/icon_variator.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/branding/icon_variator.rb")
      expect(content).to include("module Branding")
      expect(content).to include("class IconVariator < ApplicationImageVariator")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_variator.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_VARIATORS.md")).to be true
    end
  end
end
