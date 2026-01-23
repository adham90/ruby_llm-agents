# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/image_pipeline_generator"

RSpec.describe RubyLlmAgents::ImagePipelineGenerator, type: :generator do
  describe "basic image pipeline generation" do
    before { run_generator ["Product"] }

    it "creates the pipeline file with correct name" do
      expect(file_exists?("app/agents/images/product_pipeline.rb")).to be true
    end

    it "creates a class that inherits from ApplicationImagePipeline" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("class ProductPipeline < ApplicationImagePipeline")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("module Images")
    end

    it "includes default steps configuration" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("step :generate, generator: ProductGenerator")
      expect(content).to include("step :upscale, upscaler: ProductUpscaler")
    end

    it "does not include stop_on_error by default (true is implicit)" do
      content = file_content("app/agents/images/product_pipeline.rb")
      # By default, stop_on_error is true and not explicitly set
      expect(content).not_to include("stop_on_error")
    end
  end

  describe "--steps option" do
    before { run_generator ["Product", "--steps=generate,analyze,remove_background"] }

    it "includes the specified steps" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("step :generate")
      expect(content).to include("step :analyze")
      expect(content).to include("step :remove_background")
    end

    it "does not include non-specified steps" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).not_to include("step :upscale")
      expect(content).not_to include("step :transform")
    end
  end

  describe "--steps with transform" do
    before { run_generator ["Product", "--steps=generate,transform"] }

    it "includes transform step" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("step :generate")
      expect(content).to include("step :transform")
    end
  end

  describe "--no-stop-on-error option" do
    before { run_generator ["Product", "--no-stop-on-error"] }

    it "sets stop_on_error to false" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("stop_on_error false")
    end
  end

  describe "--cache option" do
    before { run_generator ["Product", "--cache=1.day"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).to include("cache_for 1.day")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Product"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/product_pipeline.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Ecommerce",
        "--steps=generate,upscale,remove_background,analyze",
        "--no-stop-on-error",
        "--cache=2.hours"
      ]
    end

    it "creates the pipeline file" do
      expect(file_exists?("app/agents/images/ecommerce_pipeline.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/ecommerce_pipeline.rb")
      expect(content).to include("class EcommercePipeline < ApplicationImagePipeline")
      expect(content).to include("step :generate")
      expect(content).to include("step :upscale")
      expect(content).to include("step :remove_background")
      expect(content).to include("step :analyze")
      expect(content).to include("stop_on_error false")
      expect(content).to include("cache_for 2.hours")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["ContentCreation"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/content_creation_pipeline.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/content_creation_pipeline.rb")
      expect(content).to include("class ContentCreationPipeline < ApplicationImagePipeline")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["social_media"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/social_media_pipeline.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/social_media_pipeline.rb")
      expect(content).to include("class SocialMediaPipeline < ApplicationImagePipeline")
    end
  end

  describe "nested namespace" do
    before { run_generator ["marketing/campaign"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/marketing/campaign_pipeline.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/marketing/campaign_pipeline.rb")
      expect(content).to include("module Marketing")
      expect(content).to include("class CampaignPipeline < ApplicationImagePipeline")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_image_pipeline.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/IMAGE_PIPELINES.md")).to be true
    end
  end

  describe "step creation hints" do
    context "with generate step" do
      before { run_generator ["Content", "--steps=generate"] }

      it "creates the pipeline with generate step" do
        content = file_content("app/agents/images/content_pipeline.rb")
        expect(content).to include("step :generate")
      end
    end

    context "with analyze step" do
      before { run_generator ["Content", "--steps=generate,analyze"] }

      it "creates the pipeline with analyze step" do
        content = file_content("app/agents/images/content_pipeline.rb")
        expect(content).to include("step :generate")
        expect(content).to include("step :analyze")
      end
    end
  end
end
