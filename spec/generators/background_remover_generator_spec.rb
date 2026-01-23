# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/background_remover_generator"

RSpec.describe RubyLlmAgents::BackgroundRemoverGenerator, type: :generator do
  describe "basic background remover generation" do
    before { run_generator ["Product"] }

    it "creates the remover file with correct name" do
      expect(file_exists?("app/agents/images/product_background_remover.rb")).to be true
    end

    it "creates a class that inherits from ApplicationBackgroundRemover" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("class ProductBackgroundRemover < ApplicationBackgroundRemover")
    end

    it "wraps the class in Images namespace" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("module Images")
    end

    it "includes default model configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include('model "rembg"')
    end

    it "includes default output_format configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("output_format :png")
    end
  end

  describe "--model option" do
    before { run_generator ["Product", "--model=segment-anything"] }

    it "uses the specified model" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include('model "segment-anything"')
    end
  end

  describe "--output_format option" do
    before { run_generator ["Product", "--output-format=webp"] }

    it "uses the specified output format" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("output_format :webp")
    end
  end

  describe "--refine_edges option" do
    before { run_generator ["Product", "--refine-edges"] }

    it "includes refine_edges configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("refine_edges true")
    end
  end

  describe "without --refine_edges option" do
    before { run_generator ["Product"] }

    it "does not include refine_edges by default" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).not_to include("refine_edges true")
    end
  end

  describe "--alpha_matting option" do
    before { run_generator ["Product", "--alpha-matting"] }

    it "includes alpha_matting configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("alpha_matting true")
    end
  end

  describe "without --alpha_matting option" do
    before { run_generator ["Product"] }

    it "does not include alpha_matting by default" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).not_to include("alpha_matting true")
    end
  end

  describe "--return_mask option" do
    before { run_generator ["Product", "--return-mask"] }

    it "includes return_mask configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("return_mask true")
    end
  end

  describe "without --return_mask option" do
    before { run_generator ["Product"] }

    it "does not include return_mask by default" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).not_to include("return_mask true")
    end
  end

  describe "--cache option" do
    before { run_generator ["Product", "--cache=1.hour"] }

    it "includes cache configuration" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).to include("cache_for 1.hour")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Product"] }

    it "does not include caching by default" do
      content = file_content("app/agents/images/product_background_remover.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Portrait",
        "--model=segment-anything",
        "--output-format=webp",
        "--refine-edges",
        "--alpha-matting",
        "--return-mask",
        "--cache=2.hours"
      ]
    end

    it "creates the remover file" do
      expect(file_exists?("app/agents/images/portrait_background_remover.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/agents/images/portrait_background_remover.rb")
      expect(content).to include("class PortraitBackgroundRemover < ApplicationBackgroundRemover")
      expect(content).to include('model "segment-anything"')
      expect(content).to include("output_format :webp")
      expect(content).to include("refine_edges true")
      expect(content).to include("alpha_matting true")
      expect(content).to include("return_mask true")
      expect(content).to include("cache_for 2.hours")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["PersonPhoto"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/agents/images/person_photo_background_remover.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/person_photo_background_remover.rb")
      expect(content).to include("class PersonPhotoBackgroundRemover < ApplicationBackgroundRemover")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["item_shot"] }

    it "creates file with correct name" do
      expect(file_exists?("app/agents/images/item_shot_background_remover.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/agents/images/item_shot_background_remover.rb")
      expect(content).to include("class ItemShotBackgroundRemover < ApplicationBackgroundRemover")
    end
  end

  describe "nested namespace" do
    before { run_generator ["ecommerce/product"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/agents/images/ecommerce/product_background_remover.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/agents/images/ecommerce/product_background_remover.rb")
      expect(content).to include("module Ecommerce")
      expect(content).to include("class ProductBackgroundRemover < ApplicationBackgroundRemover")
    end
  end

  describe "base class and skill file creation" do
    before { run_generator ["Test"] }

    it "creates the application base class" do
      expect(file_exists?("app/agents/images/application_background_remover.rb")).to be true
    end

    it "creates the skill file" do
      expect(file_exists?("app/agents/images/BACKGROUND_REMOVERS.md")).to be true
    end
  end
end
