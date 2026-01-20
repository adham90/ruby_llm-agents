# Plan: Restructure Rails App Directories Under `app/llm/`

## Overview

Group all ruby_llm-agents related directories under a single `app/llm/` directory to reduce clutter in the Rails `app/` folder.

## Current Structure

```
app/
├── agents/
├── embedders/
├── image_generators/
├── image_editors/
├── image_transformers/
├── image_upscalers/
├── image_variators/
├── image_analyzers/
├── background_removers/
├── moderators/
├── speakers/
├── transcribers/
├── workflows/
├── tools/
├── controllers/
├── models/
└── ...
```

## Target Structure

```
app/
├── llm/
│   ├── agents/
│   ├── embedders/
│   ├── image_generators/
│   ├── image_editors/
│   ├── image_transformers/
│   ├── image_upscalers/
│   ├── image_variators/
│   ├── image_analyzers/
│   ├── background_removers/
│   ├── moderators/
│   ├── speakers/
│   ├── transcribers/
│   ├── workflows/
│   └── tools/
├── controllers/
├── models/
└── ...
```

## Namespace Changes

| Before | After |
|--------|-------|
| `ApplicationAgent` | `Llm::ApplicationAgent` |
| `SupportAgent` | `Llm::SupportAgent` |
| `ApplicationEmbedder` | `Llm::ApplicationEmbedder` |
| `ApplicationSpeaker` | `Llm::ApplicationSpeaker` |
| `ApplicationTranscriber` | `Llm::ApplicationTranscriber` |
| `ApplicationImageGenerator` | `Llm::ApplicationImageGenerator` |
| etc. | etc. |

---

## Implementation Tasks

### 1. Update Generators

Update all generators to create files under `app/llm/` with the `Llm::` namespace:

- [ ] `agent_generator.rb`
- [ ] `embedder_generator.rb`
- [ ] `speaker_generator.rb`
- [ ] `transcriber_generator.rb`
- [ ] `image_generator_generator.rb`
- [ ] `image_editor_generator.rb`
- [ ] `image_transformer_generator.rb`
- [ ] `image_upscaler_generator.rb`
- [ ] `image_variator_generator.rb`
- [ ] `image_analyzer_generator.rb`
- [ ] `background_remover_generator.rb`

**Changes per generator:**
- Update `destination_root` to `app/llm/<type>/`
- Update templates to use `Llm::` namespace
- Update `ApplicationX` base class references to `Llm::ApplicationX`

### 2. Update Templates

Update all template files to include the `Llm::` module wrapper:

**Before:**
```ruby
class <%= class_name %> < ApplicationAgent
end
```

**After:**
```ruby
module Llm
  class <%= class_name %> < ApplicationAgent
  end
end
```

### 3. Create Upgrade Generator

Create `lib/generators/ruby_llm_agents/restructure_generator.rb` to migrate existing apps:

```ruby
module RubyLlmAgents
  module Generators
    class RestructureGenerator < Rails::Generators::Base
      desc "Migrates ruby_llm-agents directories under app/llm/"

      DIRECTORIES = %w[
        agents
        embedders
        speakers
        transcribers
        image_generators
        image_editors
        image_transformers
        image_upscalers
        image_variators
        image_analyzers
        background_removers
        moderators
        workflows
        tools
      ].freeze

      def create_llm_directory
        empty_directory "app/llm"
      end

      def move_directories
        DIRECTORIES.each do |dir|
          source = "app/#{dir}"
          destination = "app/llm/#{dir}"

          if File.directory?(source)
            say_status :moving, "#{source} -> #{destination}", :green
            FileUtils.mv(source, destination)
          end
        end
      end

      def update_namespaces
        # Update all Ruby files to add Llm:: namespace
        DIRECTORIES.each do |dir|
          directory_path = "app/llm/#{dir}"
          next unless File.directory?(directory_path)

          Dir.glob("#{directory_path}/**/*.rb").each do |file|
            update_file_namespace(file)
          end
        end
      end

      private

      def update_file_namespace(file)
        content = File.read(file)

        # Skip if already namespaced
        return if content.include?("module Llm")

        # Add Llm module wrapper
        updated = add_llm_namespace(content)
        File.write(file, updated)

        say_status :updated, file, :blue
      end

      def add_llm_namespace(content)
        # Implementation details...
      end
    end
  end
end
```

### 4. Update Install Generator

Modify `install_generator.rb` to:
- Create `app/llm/` directory structure
- Generate base classes with `Llm::` namespace

### 5. Update Engine

Ensure autoload paths include `app/llm` subdirectories:

```ruby
# lib/ruby_llm/agents/engine.rb
initializer "ruby_llm_agents.autoload_paths" do |app|
  llm_paths = %w[
    agents embedders speakers transcribers
    image_generators image_editors image_transformers
    image_upscalers image_variators image_analyzers
    background_removers moderators workflows tools
  ].map { |dir| Rails.root.join("app/llm/#{dir}") }

  app.config.autoload_paths += llm_paths
  app.config.eager_load_paths += llm_paths
end
```

### 6. Update Example App

Restructure `example/app/` to match new structure:
- Move all directories under `example/app/llm/`
- Update all class definitions with `Llm::` namespace

### 7. Update Documentation

- Update README with new directory structure
- Update wiki pages
- Add migration guide for existing users

---

## Upgrade Generator Specs

Create `spec/generators/restructure_generator_spec.rb`:

```ruby
require "spec_helper"
require "generators/ruby_llm_agents/restructure_generator"
require "fileutils"

RSpec.describe RubyLlmAgents::Generators::RestructureGenerator, type: :generator do
  destination File.expand_path("../../tmp", __dir__)

  before do
    prepare_destination
    setup_old_structure
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "directory migration" do
    it "creates app/llm directory" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm"))).to be true
    end

    it "moves agents directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/agents"))).to be true
      expect(File.directory?(File.join(destination_root, "app/agents"))).to be false
    end

    it "moves embedders directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/embedders"))).to be true
      expect(File.directory?(File.join(destination_root, "app/embedders"))).to be false
    end

    it "moves speakers directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/speakers"))).to be true
      expect(File.directory?(File.join(destination_root, "app/speakers"))).to be false
    end

    it "moves transcribers directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/transcribers"))).to be true
      expect(File.directory?(File.join(destination_root, "app/transcribers"))).to be false
    end

    it "moves image_generators directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/image_generators"))).to be true
      expect(File.directory?(File.join(destination_root, "app/image_generators"))).to be false
    end

    it "moves moderators directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/moderators"))).to be true
      expect(File.directory?(File.join(destination_root, "app/moderators"))).to be false
    end

    it "moves workflows directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/workflows"))).to be true
      expect(File.directory?(File.join(destination_root, "app/workflows"))).to be false
    end

    it "moves tools directory under app/llm" do
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/tools"))).to be true
      expect(File.directory?(File.join(destination_root, "app/tools"))).to be false
    end

    it "skips directories that don't exist" do
      FileUtils.rm_rf(File.join(destination_root, "app/tools"))
      expect { run_generator }.not_to raise_error
    end

    it "preserves files within moved directories" do
      run_generator
      expect(File.exist?(File.join(destination_root, "app/llm/agents/application_agent.rb"))).to be true
      expect(File.exist?(File.join(destination_root, "app/llm/agents/support_agent.rb"))).to be true
    end
  end

  describe "namespace updates" do
    it "adds Llm module to agent classes" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/agents/support_agent.rb"))
      expect(content).to include("module Llm")
      expect(content).to include("class SupportAgent < ApplicationAgent")
    end

    it "adds Llm module to application_agent" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/agents/application_agent.rb"))
      expect(content).to include("module Llm")
      expect(content).to include("class ApplicationAgent < RubyLLM::Agents::Base")
    end

    it "adds Llm module to embedder classes" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/embedders/application_embedder.rb"))
      expect(content).to include("module Llm")
    end

    it "adds Llm module to speaker classes" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/speakers/application_speaker.rb"))
      expect(content).to include("module Llm")
    end

    it "adds Llm module to transcriber classes" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/transcribers/application_transcriber.rb"))
      expect(content).to include("module Llm")
    end

    it "skips files already namespaced with Llm" do
      # Pre-namespace a file
      file_path = File.join(destination_root, "app/agents/support_agent.rb")
      File.write(file_path, <<~RUBY)
        module Llm
          class SupportAgent < ApplicationAgent
          end
        end
      RUBY

      run_generator

      content = File.read(File.join(destination_root, "app/llm/agents/support_agent.rb"))
      expect(content.scan("module Llm").count).to eq(1)
    end

    it "handles nested classes correctly" do
      # Create a nested class file
      nested_dir = File.join(destination_root, "app/agents/support")
      FileUtils.mkdir_p(nested_dir)
      File.write(File.join(nested_dir, "helper.rb"), <<~RUBY)
        class Support::Helper
          def help
          end
        end
      RUBY

      run_generator

      content = File.read(File.join(destination_root, "app/llm/agents/support/helper.rb"))
      expect(content).to include("module Llm")
    end

    it "updates tool classes" do
      run_generator
      content = File.read(File.join(destination_root, "app/llm/tools/weather_tool.rb"))
      expect(content).to include("module Llm")
    end
  end

  describe "idempotency" do
    it "can be run multiple times safely" do
      run_generator
      expect { run_generator }.not_to raise_error
    end

    it "does not duplicate Llm namespace on second run" do
      run_generator
      run_generator

      content = File.read(File.join(destination_root, "app/llm/agents/support_agent.rb"))
      expect(content.scan("module Llm").count).to eq(1)
    end
  end

  describe "edge cases" do
    it "handles empty directories" do
      FileUtils.mkdir_p(File.join(destination_root, "app/image_editors"))
      run_generator
      expect(File.directory?(File.join(destination_root, "app/llm/image_editors"))).to be true
    end

    it "handles files with syntax errors gracefully" do
      File.write(File.join(destination_root, "app/agents/broken.rb"), "class Broken <")
      expect { run_generator }.not_to raise_error
    end

    it "preserves file permissions" do
      file_path = File.join(destination_root, "app/agents/support_agent.rb")
      File.chmod(0755, file_path)

      run_generator

      new_path = File.join(destination_root, "app/llm/agents/support_agent.rb")
      expect(File.stat(new_path).mode & 0777).to eq(0755)
    end
  end

  private

  def setup_old_structure
    # Create old directory structure
    %w[agents embedders speakers transcribers image_generators moderators workflows tools].each do |dir|
      FileUtils.mkdir_p(File.join(destination_root, "app/#{dir}"))
    end

    # Create sample files
    File.write(File.join(destination_root, "app/agents/application_agent.rb"), <<~RUBY)
      class ApplicationAgent < RubyLLM::Agents::Base
      end
    RUBY

    File.write(File.join(destination_root, "app/agents/support_agent.rb"), <<~RUBY)
      class SupportAgent < ApplicationAgent
        model "gpt-4"
      end
    RUBY

    File.write(File.join(destination_root, "app/embedders/application_embedder.rb"), <<~RUBY)
      class ApplicationEmbedder < RubyLLM::Agents::Embedder
      end
    RUBY

    File.write(File.join(destination_root, "app/speakers/application_speaker.rb"), <<~RUBY)
      class ApplicationSpeaker < RubyLLM::Agents::Speaker
      end
    RUBY

    File.write(File.join(destination_root, "app/transcribers/application_transcriber.rb"), <<~RUBY)
      class ApplicationTranscriber < RubyLLM::Agents::Transcriber
      end
    RUBY

    File.write(File.join(destination_root, "app/tools/weather_tool.rb"), <<~RUBY)
      class WeatherTool < RubyLLM::Tool
        def call(location:)
        end
      end
    RUBY
  end
end
```

---

## Rollback Plan

If users need to revert:

```bash
# Manual rollback steps
cd app
mv llm/agents .
mv llm/embedders .
mv llm/speakers .
mv llm/transcribers .
mv llm/image_generators .
mv llm/moderators .
mv llm/workflows .
mv llm/tools .
rmdir llm

# Then manually remove "module Llm" wrapper from files
```

Consider creating a `restructure:rollback` generator for automated rollback.

---

## Version Considerations

- This is a **breaking change** for existing users
- Should be released as a **major version** (e.g., v1.0.0 or v0.5.0)
- Provide clear upgrade guide in CHANGELOG
- Consider deprecation warnings in previous version

---

## Open Questions

1. Should we support both structures during a transition period?
2. Should `tools/` also be under `app/llm/` or stay separate since tools are used by agents?
3. Alternative namespace names: `Llm::`, `AI::`, `RubyLlm::`?
