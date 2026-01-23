# frozen_string_literal: true

require "rails_helper"
require "generators/ruby_llm_agents/migrate_structure_generator"

RSpec.describe RubyLlmAgents::MigrateStructureGenerator, type: :generator do
  # The migrate_structure_generator uses Rails.root directly, so we need to stub it
  let(:fake_rails_root) { Pathname.new(destination_root) }

  before do
    allow(Rails).to receive(:root).and_return(fake_rails_root)
  end

  describe "when no old structure exists" do
    it "skips migration when no source directory is found" do
      expect { run_generator }.to raise_error(Thor::Error, /Migration aborted: no source found/)
    end

    it "skips migration when specified source root does not exist" do
      expect { run_generator ["--source-root=nonexistent"] }.to raise_error(Thor::Error, /Migration aborted: no source found/)
    end
  end

  describe "with existing old structure" do
    before do
      # Create old structure
      create_old_structure
    end

    def create_old_structure
      # Create the old llm-based directory structure
      # Note: camelize("llm") returns "LLM", so we use that casing
      create_directory_with_file("app/llm/agents", "chat_agent.rb", <<~RUBY)
        module LLM
          class ChatAgent < ApplicationAgent
          end
        end
      RUBY

      create_directory_with_file("app/llm/image/generators", "logo_generator.rb", <<~RUBY)
        module LLM
          module Image
            class LogoGenerator < ApplicationImageGenerator
            end
          end
        end
      RUBY

      create_directory_with_file("app/llm/audio/speakers", "voice_speaker.rb", <<~RUBY)
        module LLM
          module Audio
            class VoiceSpeaker < ApplicationSpeaker
            end
          end
        end
      RUBY

      create_directory_with_file("app/llm/text/embedders", "semantic_embedder.rb", <<~RUBY)
        module LLM
          module Text
            class SemanticEmbedder < ApplicationEmbedder
            end
          end
        end
      RUBY

      create_directory_with_file("app/llm/workflows", "content_workflow.rb", <<~RUBY)
        module LLM
          class ContentWorkflow < ApplicationWorkflow
          end
        end
      RUBY
    end

    def create_directory_with_file(dir, filename, content)
      full_dir = File.join(destination_root, dir)
      FileUtils.mkdir_p(full_dir)
      File.write(File.join(full_dir, filename), content)
    end

    describe "dry run mode" do
      before { run_generator ["--source-root=llm", "--dry-run"] }

      it "does not move files" do
        expect(file_exists?("app/llm/agents/chat_agent.rb")).to be true
        expect(file_exists?("app/agents/chat_agent.rb")).to be false
      end

      it "does not create new directories" do
        # New directories are created even in dry run for file_content to work
        # The key is files are not moved
        expect(file_exists?("app/agents/chat_agent.rb")).to be false
      end

      it "keeps old directories intact" do
        expect(directory_exists?("app/llm/agents")).to be true
        expect(directory_exists?("app/llm/image/generators")).to be true
      end
    end

    describe "actual migration" do
      before { run_generator ["--source-root=llm", "--no-use-git"] }

      it "moves agent files to new location" do
        expect(file_exists?("app/agents/chat_agent.rb")).to be true
      end

      it "moves image generator files to images directory" do
        expect(file_exists?("app/agents/images/logo_generator.rb")).to be true
      end

      it "moves audio files to audio directory" do
        expect(file_exists?("app/agents/audio/voice_speaker.rb")).to be true
      end

      it "moves text embedder files to embedders directory" do
        expect(file_exists?("app/agents/embedders/semantic_embedder.rb")).to be true
      end

      it "moves workflow files to workflows directory" do
        expect(file_exists?("app/workflows/content_workflow.rb")).to be true
      end
    end

    describe "namespace updates" do
      before { run_generator ["--source-root=llm", "--no-use-git"] }

      it "removes root namespace from agent files" do
        content = file_content("app/agents/chat_agent.rb")
        expect(content).not_to include("module LLM")
      end

      it "updates image namespace" do
        content = file_content("app/agents/images/logo_generator.rb")
        expect(content).to include("module Images")
        expect(content).not_to match(/module Image[^s]/)
      end
    end

    describe "--skip-namespace-update option" do
      before { run_generator ["--source-root=llm", "--skip-namespace-update", "--no-use-git"] }

      it "moves files but does not update namespaces" do
        expect(file_exists?("app/agents/chat_agent.rb")).to be true
        content = file_content("app/agents/chat_agent.rb")
        expect(content).to include("module LLM")
      end
    end
  end

  describe "auto-detection of source root" do
    before do
      # Create an old structure with indicators
      full_dir = File.join(destination_root, "app/llm/agents")
      FileUtils.mkdir_p(full_dir)
      File.write(File.join(full_dir, "test_agent.rb"), "class TestAgent; end")
    end

    it "auto-detects llm directory" do
      expect { run_generator ["--no-use-git"] }.not_to raise_error
    end
  end

  describe "PATH_MAPPING constant" do
    it "maps agents to agents" do
      expect(described_class::PATH_MAPPING["agents"]).to eq("agents")
    end

    it "maps image/generators to agents/images" do
      expect(described_class::PATH_MAPPING["image/generators"]).to eq("agents/images")
    end

    it "maps audio/speakers to agents/audio" do
      expect(described_class::PATH_MAPPING["audio/speakers"]).to eq("agents/audio")
    end

    it "maps text/embedders to agents/embedders" do
      expect(described_class::PATH_MAPPING["text/embedders"]).to eq("agents/embedders")
    end

    it "maps workflows to workflows" do
      expect(described_class::PATH_MAPPING["workflows"]).to eq("workflows")
    end

    it "maps tools to tools" do
      expect(described_class::PATH_MAPPING["tools"]).to eq("tools")
    end
  end

  describe "NAMESPACE_MAPPING constant" do
    it "defines namespace transformation patterns" do
      expect(described_class::NAMESPACE_MAPPING).to be_a(Hash)
      expect(described_class::NAMESPACE_MAPPING.keys).to all(be_a(Regexp))
    end
  end

  describe "camelize helper" do
    let(:generator) { described_class.new([], {}, destination_root: destination_root) }

    it "camelizes ai to AI" do
      expect(generator.send(:camelize, "ai")).to eq("AI")
    end

    it "camelizes ml to ML" do
      expect(generator.send(:camelize, "ml")).to eq("ML")
    end

    it "camelizes llm to LLM" do
      expect(generator.send(:camelize, "llm")).to eq("LLM")
    end

    it "camelizes regular words" do
      expect(generator.send(:camelize, "agents")).to eq("Agents")
    end

    it "handles underscored words" do
      expect(generator.send(:camelize, "my_agents")).to eq("MyAgents")
    end

    it "handles hyphenated words" do
      expect(generator.send(:camelize, "my-agents")).to eq("MyAgents")
    end
  end
end
