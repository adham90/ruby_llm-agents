# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/embedder_generator"

RSpec.describe RubyLlmAgents::EmbedderGenerator, type: :generator do
  describe "basic embedder generation" do
    before { run_generator ["Document"] }

    it "creates the embedder file with correct name" do
      expect(file_exists?("app/llm/text/embedders/document_embedder.rb")).to be true
    end

    it "creates a class that inherits from ApplicationEmbedder" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("class DocumentEmbedder < ApplicationEmbedder")
    end

    it "wraps the class in LLM::Text namespace" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("module LLM")
      expect(content).to include("module Text")
    end

    it "includes default model configuration" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include('model "text-embedding-3-small"')
    end
  end

  describe "--model option" do
    before { run_generator ["Document", "--model=text-embedding-3-large"] }

    it "uses the specified model" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include('model "text-embedding-3-large"')
    end
  end

  describe "--dimensions option" do
    before { run_generator ["Document", "--dimensions=512"] }

    it "includes dimensions configuration" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("dimensions 512")
    end
  end

  describe "without --dimensions option" do
    before { run_generator ["Document"] }

    it "does not include dimensions" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).not_to include("dimensions")
    end
  end

  describe "--batch_size option" do
    before { run_generator ["Document", "--batch-size=50"] }

    it "includes batch_size configuration" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("batch_size 50")
    end
  end

  describe "without --batch_size option (default 100)" do
    before { run_generator ["Document"] }

    it "does not include batch_size (uses default)" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).not_to include("batch_size")
    end
  end

  describe "--cache option" do
    before { run_generator ["Document", "--cache=1.week"] }

    it "includes cache configuration" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("cache_for 1.week")
    end
  end

  describe "without --cache option" do
    before { run_generator ["Document"] }

    it "does not include caching by default" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).not_to include("cache_for")
    end
  end

  describe "combined options" do
    before do
      run_generator [
        "Search",
        "--model=text-embedding-3-large",
        "--dimensions=256",
        "--batch-size=25",
        "--cache=1.day"
      ]
    end

    it "creates the embedder file" do
      expect(file_exists?("app/llm/text/embedders/search_embedder.rb")).to be true
    end

    it "applies all options correctly" do
      content = file_content("app/llm/text/embedders/search_embedder.rb")
      expect(content).to include("class SearchEmbedder < ApplicationEmbedder")
      expect(content).to include('model "text-embedding-3-large"')
      expect(content).to include("dimensions 256")
      expect(content).to include("batch_size 25")
      expect(content).to include("cache_for 1.day")
    end
  end

  describe "camelCase name handling" do
    before { run_generator ["MyDocument"] }

    it "creates file with underscored name" do
      expect(file_exists?("app/llm/text/embedders/my_document_embedder.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/text/embedders/my_document_embedder.rb")
      expect(content).to include("class MyDocumentEmbedder < ApplicationEmbedder")
    end
  end

  describe "snake_case name handling" do
    before { run_generator ["knowledge_base"] }

    it "creates file with correct name" do
      expect(file_exists?("app/llm/text/embedders/knowledge_base_embedder.rb")).to be true
    end

    it "uses the correct class name" do
      content = file_content("app/llm/text/embedders/knowledge_base_embedder.rb")
      expect(content).to include("class KnowledgeBaseEmbedder < ApplicationEmbedder")
    end
  end

  describe "nested namespace" do
    before { run_generator ["search/document"] }

    it "creates file in nested directory" do
      expect(file_exists?("app/llm/text/embedders/search/document_embedder.rb")).to be true
    end

    it "uses namespaced class name" do
      content = file_content("app/llm/text/embedders/search/document_embedder.rb")
      expect(content).to include("module Search")
      expect(content).to include("class DocumentEmbedder < ApplicationEmbedder")
    end
  end

  describe "preprocess comment" do
    before { run_generator ["Document"] }

    it "includes commented preprocess method" do
      content = file_content("app/llm/text/embedders/document_embedder.rb")
      expect(content).to include("# def preprocess(text)")
    end
  end

  describe "--root option" do
    before { run_generator ["Document", "--root=ai"] }

    it "creates the embedder in the ai directory" do
      expect(file_exists?("app/ai/text/embedders/document_embedder.rb")).to be true
    end

    it "uses the AI::Text namespace" do
      content = file_content("app/ai/text/embedders/document_embedder.rb")
      expect(content).to include("module AI")
      expect(content).to include("module Text")
    end
  end
end
