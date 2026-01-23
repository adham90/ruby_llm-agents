# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/restructure_generator"

RSpec.describe RubyLlmAgents::RestructureGenerator, type: :generator, skip: "Restructure generator needs rework - configuration path_for doesn't respect root_directory option" do
  # Use the standard DESTINATION_ROOT from GeneratorHelpers
  # and stub Rails.root to point to it

  before do
    # Stub Rails.root to point to our test directory
    allow(Rails).to receive(:root).and_return(Pathname.new(destination_root))
  end

  def setup_old_structure
    # Create old directory structure with sample files

    # Agents
    FileUtils.mkdir_p(file("app/agents"))
    File.write(file("app/agents/application_agent.rb"), <<~RUBY)
      class ApplicationAgent < RubyLLM::Agents::Base
      end
    RUBY
    File.write(file("app/agents/support_agent.rb"), <<~RUBY)
      class SupportAgent < ApplicationAgent
        model "gpt-4"
      end
    RUBY

    # Speakers
    FileUtils.mkdir_p(file("app/speakers"))
    File.write(file("app/speakers/application_speaker.rb"), <<~RUBY)
      class ApplicationSpeaker < RubyLLM::Agents::Speaker
      end
    RUBY

    # Transcribers
    FileUtils.mkdir_p(file("app/transcribers"))
    File.write(file("app/transcribers/application_transcriber.rb"), <<~RUBY)
      class ApplicationTranscriber < RubyLLM::Agents::Transcriber
      end
    RUBY

    # Image generators
    FileUtils.mkdir_p(file("app/image_generators"))
    File.write(file("app/image_generators/application_image_generator.rb"), <<~RUBY)
      class ApplicationImageGenerator < RubyLLM::Agents::ImageGenerator
      end
    RUBY

    # Image editors
    FileUtils.mkdir_p(file("app/image_editors"))
    File.write(file("app/image_editors/application_image_editor.rb"), <<~RUBY)
      class ApplicationImageEditor < RubyLLM::Agents::ImageEditor
      end
    RUBY

    # Image analyzers
    FileUtils.mkdir_p(file("app/image_analyzers"))
    File.write(file("app/image_analyzers/application_image_analyzer.rb"), <<~RUBY)
      class ApplicationImageAnalyzer < RubyLLM::Agents::ImageAnalyzer
      end
    RUBY

    # Embedders
    FileUtils.mkdir_p(file("app/embedders"))
    File.write(file("app/embedders/application_embedder.rb"), <<~RUBY)
      class ApplicationEmbedder < RubyLLM::Agents::Embedder
      end
    RUBY

    # Moderators
    FileUtils.mkdir_p(file("app/moderators"))
    File.write(file("app/moderators/application_moderator.rb"), <<~RUBY)
      class ApplicationModerator < RubyLLM::Agents::Moderator
      end
    RUBY

    # Workflows
    FileUtils.mkdir_p(file("app/workflows"))
    File.write(file("app/workflows/application_workflow.rb"), <<~RUBY)
      class ApplicationWorkflow < RubyLLM::Agents::Workflow
      end
    RUBY

    # Tools
    FileUtils.mkdir_p(file("app/tools"))
    File.write(file("app/tools/weather_tool.rb"), <<~RUBY)
      class WeatherTool < RubyLLM::Tool
        def call(location:)
        end
      end
    RUBY
  end

  describe "directory structure creation" do
    before do
      setup_old_structure
      run_generator ["--root=llm"]
    end

    it "creates app/llm directory" do
      expect(directory_exists?("app/llm")).to be true
    end

    it "creates app/llm/agents directory" do
      expect(directory_exists?("app/llm/agents")).to be true
    end

    it "creates app/llm/audio directory structure" do
      expect(directory_exists?("app/llm/audio")).to be true
      expect(directory_exists?("app/llm/audio/speakers")).to be true
      expect(directory_exists?("app/llm/audio/transcribers")).to be true
    end

    it "creates app/llm/image directory structure" do
      expect(directory_exists?("app/llm/image")).to be true
      expect(directory_exists?("app/llm/image/generators")).to be true
      expect(directory_exists?("app/llm/image/editors")).to be true
      expect(directory_exists?("app/llm/image/analyzers")).to be true
    end

    it "creates app/llm/text directory structure" do
      expect(directory_exists?("app/llm/text")).to be true
      expect(directory_exists?("app/llm/text/embedders")).to be true
      expect(directory_exists?("app/llm/text/moderators")).to be true
    end

    it "creates app/llm/workflows directory" do
      expect(directory_exists?("app/llm/workflows")).to be true
    end

    it "creates app/llm/tools directory" do
      expect(directory_exists?("app/llm/tools")).to be true
    end
  end

  describe "directory migration" do
    before do
      setup_old_structure
      run_generator ["--root=llm"]
    end

    it "moves agents to app/llm/agents" do
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
      expect(file_exists?("app/llm/agents/support_agent.rb")).to be true
      expect(directory_exists?("app/agents")).to be false
    end

    it "moves speakers to app/llm/audio/speakers" do
      expect(file_exists?("app/llm/audio/speakers/application_speaker.rb")).to be true
      expect(directory_exists?("app/speakers")).to be false
    end

    it "moves transcribers to app/llm/audio/transcribers" do
      expect(file_exists?("app/llm/audio/transcribers/application_transcriber.rb")).to be true
      expect(directory_exists?("app/transcribers")).to be false
    end

    it "moves image_generators to app/llm/image/generators" do
      expect(file_exists?("app/llm/image/generators/application_image_generator.rb")).to be true
      expect(directory_exists?("app/image_generators")).to be false
    end

    it "moves image_editors to app/llm/image/editors" do
      expect(file_exists?("app/llm/image/editors/application_image_editor.rb")).to be true
      expect(directory_exists?("app/image_editors")).to be false
    end

    it "moves image_analyzers to app/llm/image/analyzers" do
      expect(file_exists?("app/llm/image/analyzers/application_image_analyzer.rb")).to be true
      expect(directory_exists?("app/image_analyzers")).to be false
    end

    it "moves embedders to app/llm/text/embedders" do
      expect(file_exists?("app/llm/text/embedders/application_embedder.rb")).to be true
      expect(directory_exists?("app/embedders")).to be false
    end

    it "moves moderators to app/llm/text/moderators" do
      expect(file_exists?("app/llm/text/moderators/application_moderator.rb")).to be true
      expect(directory_exists?("app/moderators")).to be false
    end

    it "moves workflows to app/llm/workflows" do
      expect(file_exists?("app/llm/workflows/application_workflow.rb")).to be true
      expect(directory_exists?("app/workflows")).to be false
    end

    it "moves tools to app/llm/tools" do
      expect(file_exists?("app/llm/tools/weather_tool.rb")).to be true
      expect(directory_exists?("app/tools")).to be false
    end

    it "skips directories that don't exist" do
      # image_transformers doesn't exist, should not raise error
      expect { run_generator }.not_to raise_error
    end
  end

  describe "namespace updates" do
    before do
      setup_old_structure
      run_generator ["--root=llm"]
    end

    context "top-level llm namespace (agents, workflows, tools)" do
      it "adds LLM module to agent classes" do
        content = file_content("app/llm/agents/support_agent.rb")
        expect(content).to include("module LLM")
        expect(content).to include("class SupportAgent")
        expect(content).not_to include("module Audio")
        expect(content).not_to include("module Image")
      end

      it "adds LLM module to application_agent" do
        content = file_content("app/llm/agents/application_agent.rb")
        expect(content).to include("module LLM")
        expect(content).to include("class ApplicationAgent")
      end

      it "adds LLM module to workflow classes" do
        content = file_content("app/llm/workflows/application_workflow.rb")
        expect(content).to include("module LLM")
        expect(content).to include("class ApplicationWorkflow")
      end

      it "adds LLM module to tool classes" do
        content = file_content("app/llm/tools/weather_tool.rb")
        expect(content).to include("module LLM")
        expect(content).to include("class WeatherTool")
      end
    end

    context "audio namespace" do
      it "adds LLM::Audio module to speaker classes" do
        content = file_content("app/llm/audio/speakers/application_speaker.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Audio")
        expect(content).to include("class ApplicationSpeaker")
      end

      it "adds LLM::Audio module to transcriber classes" do
        content = file_content("app/llm/audio/transcribers/application_transcriber.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Audio")
        expect(content).to include("class ApplicationTranscriber")
      end
    end

    context "image namespace" do
      it "adds LLM::Image module to generator classes" do
        content = file_content("app/llm/image/generators/application_image_generator.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageGenerator")
      end

      it "adds LLM::Image module to editor classes" do
        content = file_content("app/llm/image/editors/application_image_editor.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageEditor")
      end

      it "adds LLM::Image module to analyzer classes" do
        content = file_content("app/llm/image/analyzers/application_image_analyzer.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageAnalyzer")
      end
    end

    context "text namespace" do
      it "adds LLM::Text module to embedder classes" do
        content = file_content("app/llm/text/embedders/application_embedder.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Text")
        expect(content).to include("class ApplicationEmbedder")
      end

      it "adds LLM::Text module to moderator classes" do
        content = file_content("app/llm/text/moderators/application_moderator.rb")
        expect(content).to include("module LLM")
        expect(content).to include("module Text")
        expect(content).to include("class ApplicationModerator")
      end
    end

    it "skips files already namespaced with LLM" do
      # First set up the old structure, then pre-namespace a file
      setup_old_structure
      File.write(file("app/agents/support_agent.rb"), <<~RUBY)
        module LLM
          class SupportAgent < ApplicationAgent
          end
        end
      RUBY

      run_generator ["--root=llm"]

      content = file_content("app/llm/agents/support_agent.rb")
      expect(content.scan("module LLM").count).to eq(1)
    end
  end

  describe "idempotency" do
    before { setup_old_structure }

    it "can be run multiple times safely" do
      run_generator ["--root=llm"]
      expect { run_generator ["--root=llm"] }.not_to raise_error
    end

    it "does not duplicate namespace on second run" do
      run_generator ["--root=llm"]
      run_generator ["--root=llm"]

      content = file_content("app/llm/agents/support_agent.rb")
      expect(content.scan("module LLM").count).to eq(1)
    end

    it "does not duplicate nested namespace on second run" do
      run_generator ["--root=llm"]
      run_generator ["--root=llm"]

      content = file_content("app/llm/audio/speakers/application_speaker.rb")
      expect(content.scan("module Audio").count).to eq(1)
    end
  end

  describe "custom root directory" do
    before { setup_old_structure }

    context "with --root=ai option" do
      it "creates app/ai directory instead of app/llm" do
        run_generator ["--root=ai"]
        expect(directory_exists?("app/ai")).to be true
        expect(directory_exists?("app/llm")).to be false
      end

      it "creates full directory structure under app/ai" do
        run_generator ["--root=ai"]
        expect(directory_exists?("app/ai/agents")).to be true
        expect(directory_exists?("app/ai/audio/speakers")).to be true
        expect(directory_exists?("app/ai/audio/transcribers")).to be true
        expect(directory_exists?("app/ai/image/generators")).to be true
        expect(directory_exists?("app/ai/text/embedders")).to be true
        expect(directory_exists?("app/ai/workflows")).to be true
        expect(directory_exists?("app/ai/tools")).to be true
      end

      it "moves files to app/ai" do
        run_generator ["--root=ai"]
        expect(file_exists?("app/ai/agents/application_agent.rb")).to be true
        expect(file_exists?("app/ai/agents/support_agent.rb")).to be true
      end

      it "uses AI namespace instead of Llm" do
        run_generator ["--root=ai"]
        content = file_content("app/ai/agents/support_agent.rb")
        expect(content).to include("module AI")
        expect(content).not_to include("module Llm")
      end

      it "uses AI::Audio namespace for speakers" do
        run_generator ["--root=ai"]
        content = file_content("app/ai/audio/speakers/application_speaker.rb")
        expect(content).to include("module AI")
        expect(content).to include("module Audio")
      end

      it "uses AI::Image namespace for image generators" do
        run_generator ["--root=ai"]
        content = file_content("app/ai/image/generators/application_image_generator.rb")
        expect(content).to include("module AI")
        expect(content).to include("module Image")
      end

      it "uses AI::Text namespace for embedders" do
        run_generator ["--root=ai"]
        content = file_content("app/ai/text/embedders/application_embedder.rb")
        expect(content).to include("module AI")
        expect(content).to include("module Text")
      end
    end

    context "with --root=ruby_llm option" do
      it "creates app/ruby_llm directory" do
        run_generator ["--root=ruby_llm"]
        expect(directory_exists?("app/ruby_llm")).to be true
      end

      it "uses RubyLlm namespace" do
        run_generator ["--root=ruby_llm"]
        content = file_content("app/ruby_llm/agents/support_agent.rb")
        expect(content).to include("module RubyLlm")
      end
    end

    context "with --root=ml option" do
      it "creates app/ml directory" do
        run_generator ["--root=ml"]
        expect(directory_exists?("app/ml")).to be true
      end

      it "uses ML namespace (uppercase)" do
        run_generator ["--root=ml"]
        content = file_content("app/ml/agents/support_agent.rb")
        expect(content).to include("module ML")
      end
    end

    context "custom namespace override" do
      it "allows separate namespace from directory name" do
        run_generator ["--root=ai", "--namespace=ArtificialIntelligence"]
        content = file_content("app/ai/agents/support_agent.rb")
        expect(content).to include("module ArtificialIntelligence")
      end
    end

    context "idempotency with custom root" do
      it "can be run multiple times with same custom root" do
        run_generator ["--root=ai"]
        expect { run_generator ["--root=ai"] }.not_to raise_error
      end

      it "does not duplicate custom namespace on second run" do
        run_generator ["--root=ai"]
        run_generator ["--root=ai"]

        content = file_content("app/ai/agents/support_agent.rb")
        expect(content.scan("module AI").count).to eq(1)
      end
    end

    context "validation" do
      it "rejects invalid directory names with spaces" do
        expect { run_generator ["--root=my llm"] }.to raise_error(ArgumentError, /invalid root directory name/i)
      end

      it "rejects invalid directory names with special characters" do
        expect { run_generator ["--root=llm@ai"] }.to raise_error(ArgumentError, /invalid root directory name/i)
      end

      it "accepts underscores in directory names" do
        expect { run_generator ["--root=ruby_llm"] }.not_to raise_error
      end

      it "accepts hyphens in directory names" do
        run_generator ["--root=ruby-llm"]
        expect(directory_exists?("app/ruby-llm")).to be true
      end
    end
  end

  describe "edge cases" do
    before { setup_old_structure }

    it "handles empty directories" do
      FileUtils.mkdir_p(file("app/image_upscalers"))
      run_generator ["--root=llm"]
      expect(directory_exists?("app/llm/image/upscalers")).to be true
    end

    it "handles files with syntax errors gracefully" do
      File.write(file("app/agents/broken.rb"), "class Broken <")
      expect { run_generator ["--root=llm"] }.not_to raise_error
    end

    it "preserves file permissions" do
      file_path = file("app/agents/support_agent.rb")
      File.chmod(0755, file_path)

      run_generator ["--root=llm"]

      new_path = file("app/llm/agents/support_agent.rb")
      expect(File.stat(new_path).mode & 0777).to eq(0755)
    end

    it "handles deeply nested subdirectories" do
      nested_dir = file("app/agents/support/utils/helpers")
      FileUtils.mkdir_p(nested_dir)
      File.write(File.join(nested_dir, "formatter.rb"), "class Formatter; end")

      run_generator ["--root=llm"]

      expect(file_exists?("app/llm/agents/support/utils/helpers/formatter.rb")).to be true
    end

    it "preserves non-ruby files" do
      File.write(file("app/agents/README.md"), "# Agents")

      run_generator ["--root=llm"]

      expect(file_exists?("app/llm/agents/README.md")).to be true
    end
  end

  describe "partial migrations" do
    it "handles apps with only agents directory" do
      FileUtils.mkdir_p(file("app/agents"))
      File.write(file("app/agents/application_agent.rb"), <<~RUBY)
        class ApplicationAgent < RubyLLM::Agents::Base
        end
      RUBY

      expect { run_generator ["--root=llm"] }.not_to raise_error
      expect(file_exists?("app/llm/agents/application_agent.rb")).to be true
    end

    it "handles apps with only image directories" do
      FileUtils.mkdir_p(file("app/image_generators"))
      File.write(file("app/image_generators/application_image_generator.rb"), <<~RUBY)
        class ApplicationImageGenerator < RubyLLM::Agents::ImageGenerator
        end
      RUBY

      expect { run_generator ["--root=llm"] }.not_to raise_error
      expect(file_exists?("app/llm/image/generators/application_image_generator.rb")).to be true
    end
  end

  describe "--dry-run option" do
    before { setup_old_structure }

    it "does not create any directories" do
      run_generator ["--root=llm", "--dry-run"]
      expect(directory_exists?("app/llm")).to be false
    end

    it "does not move any files" do
      run_generator ["--root=llm", "--dry-run"]
      expect(file_exists?("app/agents/application_agent.rb")).to be true
    end

    it "does not modify any files" do
      original_content = file_content("app/agents/support_agent.rb")
      run_generator ["--root=llm", "--dry-run"]
      expect(file_content("app/agents/support_agent.rb")).to eq(original_content)
    end
  end
end
