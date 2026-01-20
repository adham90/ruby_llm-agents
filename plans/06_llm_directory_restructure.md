# Plan: Restructure Rails App Directories Under `app/llm/`

## Overview

Group all ruby_llm-agents related directories under a single `app/llm/` directory with logical sub-groupings for image, audio, and text operations.

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
├── llm/                    # Customizable root directory (default: "llm")
│   ├── agents/
│   ├── audio/
│   │   ├── speakers/
│   │   └── transcribers/
│   ├── image/
│   │   ├── analyzers/
│   │   ├── background_removers/
│   │   ├── editors/
│   │   ├── generators/
│   │   ├── transformers/
│   │   ├── upscalers/
│   │   └── variators/
│   ├── text/
│   │   ├── embedders/
│   │   └── moderators/
│   ├── workflows/
│   └── tools/
├── controllers/
├── models/
└── ...
```

---

## Customizable Root Directory

Users can customize the root directory name (default: `llm`) to match their preferences.

### Configuration

Add to `config/initializers/ruby_llm_agents.rb`:

```ruby
RubyLLM::Agents.configure do |config|
  # Customize the root directory and namespace (default: "llm" / "Llm")
  config.root_directory = "ai"      # Creates app/ai/ instead of app/llm/
  config.root_namespace = "AI"      # Uses AI:: instead of Llm::
end
```

### Examples

| `root_directory` | `root_namespace` | Directory | Namespace |
|------------------|------------------|-----------|-----------|
| `"llm"` (default) | `"Llm"` (default) | `app/llm/agents/` | `Llm::SupportAgent` |
| `"ai"` | `"AI"` | `app/ai/agents/` | `AI::SupportAgent` |
| `"ruby_llm"` | `"RubyLlm"` | `app/ruby_llm/agents/` | `RubyLlm::SupportAgent` |
| `"ml"` | `"ML"` | `app/ml/agents/` | `ML::SupportAgent` |

### Generator Usage

```bash
# Use default (llm)
rails generate ruby_llm_agents:install

# Specify custom root directory
rails generate ruby_llm_agents:install --root=ai

# Restructure with custom root
rails generate ruby_llm_agents:restructure --root=ai
```

### Implementation Details

**Configuration class addition:**

```ruby
# lib/ruby_llm/agents/configuration.rb
module RubyLLM
  module Agents
    class Configuration
      # ... existing config ...

      # Root directory under app/ (default: "llm")
      attr_accessor :root_directory

      # Root namespace for classes (default: "Llm")
      attr_accessor :root_namespace

      def initialize
        # ... existing defaults ...
        @root_directory = "llm"
        @root_namespace = "Llm"
      end

      # Helper to get the full namespace for a category
      def namespace_for(category = nil)
        case category
        when :audio then "#{root_namespace}::Audio"
        when :image then "#{root_namespace}::Image"
        when :text then "#{root_namespace}::Text"
        else root_namespace
        end
      end

      # Helper to get the full path for a category
      def path_for(category, type)
        case category
        when :audio then "app/#{root_directory}/audio/#{type}"
        when :image then "app/#{root_directory}/image/#{type}"
        when :text then "app/#{root_directory}/text/#{type}"
        else "app/#{root_directory}/#{type}"
        end
      end
    end
  end
end
```

**Generator option:**

```ruby
# In each generator
class_option :root,
  type: :string,
  default: nil,
  desc: "Root directory name (default: uses config or 'llm')"

def root_directory
  options[:root] || RubyLLM::Agents.configuration.root_directory
end

def root_namespace
  options[:root]&.camelize || RubyLLM::Agents.configuration.root_namespace
end
```

---

## Namespace Changes

| Before | After |
|--------|-------|
| `ApplicationAgent` | `Llm::ApplicationAgent` |
| `SupportAgent` | `Llm::SupportAgent` |
| `ApplicationEmbedder` | `Llm::Text::ApplicationEmbedder` |
| `DocumentEmbedder` | `Llm::Text::DocumentEmbedder` |
| `ApplicationModerator` | `Llm::Text::ApplicationModerator` |
| `ApplicationSpeaker` | `Llm::Audio::ApplicationSpeaker` |
| `ApplicationTranscriber` | `Llm::Audio::ApplicationTranscriber` |
| `ApplicationImageGenerator` | `Llm::Image::ApplicationGenerator` |
| `ApplicationImageEditor` | `Llm::Image::ApplicationEditor` |
| `ApplicationImageAnalyzer` | `Llm::Image::ApplicationAnalyzer` |
| `ApplicationImageTransformer` | `Llm::Image::ApplicationTransformer` |
| `ApplicationImageUpscaler` | `Llm::Image::ApplicationUpscaler` |
| `ApplicationImageVariator` | `Llm::Image::ApplicationVariator` |
| `ApplicationBackgroundRemover` | `Llm::Image::ApplicationBackgroundRemover` |
| `ApplicationWorkflow` | `Llm::ApplicationWorkflow` |
| `WeatherTool` | `Llm::WeatherTool` |

## Directory Mapping

| Old Path | New Path |
|----------|----------|
| `app/agents/` | `app/llm/agents/` |
| `app/embedders/` | `app/llm/text/embedders/` |
| `app/moderators/` | `app/llm/text/moderators/` |
| `app/speakers/` | `app/llm/audio/speakers/` |
| `app/transcribers/` | `app/llm/audio/transcribers/` |
| `app/image_generators/` | `app/llm/image/generators/` |
| `app/image_editors/` | `app/llm/image/editors/` |
| `app/image_analyzers/` | `app/llm/image/analyzers/` |
| `app/image_transformers/` | `app/llm/image/transformers/` |
| `app/image_upscalers/` | `app/llm/image/upscalers/` |
| `app/image_variators/` | `app/llm/image/variators/` |
| `app/background_removers/` | `app/llm/image/background_removers/` |
| `app/workflows/` | `app/llm/workflows/` |
| `app/tools/` | `app/llm/tools/` |

---

## Implementation Tasks

### 1. Update Generators

Update all generators to create files under the new structure:

**Agents (top-level under llm):**
- [ ] `agent_generator.rb` → `app/llm/agents/`

**Audio group:**
- [ ] `speaker_generator.rb` → `app/llm/audio/speakers/`
- [ ] `transcriber_generator.rb` → `app/llm/audio/transcribers/`

**Image group:**
- [ ] `image_generator_generator.rb` → `app/llm/image/generators/`
- [ ] `image_editor_generator.rb` → `app/llm/image/editors/`
- [ ] `image_analyzer_generator.rb` → `app/llm/image/analyzers/`
- [ ] `image_transformer_generator.rb` → `app/llm/image/transformers/`
- [ ] `image_upscaler_generator.rb` → `app/llm/image/upscalers/`
- [ ] `image_variator_generator.rb` → `app/llm/image/variators/`
- [ ] `background_remover_generator.rb` → `app/llm/image/background_removers/`

**Text group:**
- [ ] `embedder_generator.rb` → `app/llm/text/embedders/`
- [ ] `moderator_generator.rb` → `app/llm/text/moderators/` (if exists)

**Changes per generator:**
- Update `destination_root` to new path
- Update templates to use nested namespace (e.g., `Llm::Image::`)
- Update `ApplicationX` base class references

### 2. Update Templates

**Agent templates (single namespace):**
```ruby
module Llm
  class <%= class_name %> < ApplicationAgent
  end
end
```

**Audio templates (nested namespace):**
```ruby
module Llm
  module Audio
    class <%= class_name %> < ApplicationSpeaker
    end
  end
end
```

**Image templates (nested namespace):**
```ruby
module Llm
  module Image
    class <%= class_name %> < ApplicationGenerator
    end
  end
end
```

**Text templates (nested namespace):**
```ruby
module Llm
  module Text
    class <%= class_name %> < ApplicationEmbedder
    end
  end
end
```

### 3. Create Upgrade Generator

Create `lib/generators/ruby_llm_agents/restructure_generator.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"

module RubyLlmAgents
  module Generators
    class RestructureGenerator < Rails::Generators::Base
      desc "Migrates ruby_llm-agents directories to new app/llm/ structure"

      # Maps old directory -> [new directory, namespace]
      DIRECTORY_MAPPING = {
        # Top-level under llm/
        "agents" => { path: "llm/agents", namespace: "Llm" },
        "workflows" => { path: "llm/workflows", namespace: "Llm" },
        "tools" => { path: "llm/tools", namespace: "Llm" },

        # Audio group
        "speakers" => { path: "llm/audio/speakers", namespace: "Llm::Audio" },
        "transcribers" => { path: "llm/audio/transcribers", namespace: "Llm::Audio" },

        # Image group
        "image_generators" => { path: "llm/image/generators", namespace: "Llm::Image" },
        "image_editors" => { path: "llm/image/editors", namespace: "Llm::Image" },
        "image_analyzers" => { path: "llm/image/analyzers", namespace: "Llm::Image" },
        "image_transformers" => { path: "llm/image/transformers", namespace: "Llm::Image" },
        "image_upscalers" => { path: "llm/image/upscalers", namespace: "Llm::Image" },
        "image_variators" => { path: "llm/image/variators", namespace: "Llm::Image" },
        "background_removers" => { path: "llm/image/background_removers", namespace: "Llm::Image" },

        # Text group
        "embedders" => { path: "llm/text/embedders", namespace: "Llm::Text" },
        "moderators" => { path: "llm/text/moderators", namespace: "Llm::Text" }
      }.freeze

      def create_directory_structure
        say_status :create, "app/llm directory structure", :green

        empty_directory "app/llm"
        empty_directory "app/llm/agents"
        empty_directory "app/llm/audio"
        empty_directory "app/llm/audio/speakers"
        empty_directory "app/llm/audio/transcribers"
        empty_directory "app/llm/image"
        empty_directory "app/llm/image/analyzers"
        empty_directory "app/llm/image/background_removers"
        empty_directory "app/llm/image/editors"
        empty_directory "app/llm/image/generators"
        empty_directory "app/llm/image/transformers"
        empty_directory "app/llm/image/upscalers"
        empty_directory "app/llm/image/variators"
        empty_directory "app/llm/text"
        empty_directory "app/llm/text/embedders"
        empty_directory "app/llm/text/moderators"
        empty_directory "app/llm/workflows"
        empty_directory "app/llm/tools"
      end

      def move_directories
        DIRECTORY_MAPPING.each do |old_dir, config|
          source = Rails.root.join("app", old_dir)
          destination = Rails.root.join("app", config[:path])

          next unless File.directory?(source)

          # Move contents, not the directory itself (since we created structure)
          Dir.glob("#{source}/*").each do |item|
            item_name = File.basename(item)
            dest_item = File.join(destination, item_name)

            say_status :moving, "#{item} -> #{dest_item}", :green
            FileUtils.mv(item, dest_item)
          end

          # Remove old empty directory
          FileUtils.rmdir(source) if Dir.empty?(source)
        end
      end

      def update_namespaces
        DIRECTORY_MAPPING.each do |old_dir, config|
          directory_path = Rails.root.join("app", config[:path])
          next unless File.directory?(directory_path)

          Dir.glob("#{directory_path}/**/*.rb").each do |file|
            update_file_namespace(file, config[:namespace])
          end
        end
      end

      def cleanup_empty_directories
        DIRECTORY_MAPPING.keys.each do |old_dir|
          path = Rails.root.join("app", old_dir)
          if File.directory?(path) && Dir.empty?(path)
            FileUtils.rmdir(path)
            say_status :removed, "empty directory app/#{old_dir}", :yellow
          end
        end
      end

      private

      def update_file_namespace(file, namespace)
        content = File.read(file)

        # Skip if already has the correct namespace
        return if content.include?("module #{namespace.split('::').first}")

        updated = add_namespace(content, namespace)
        File.write(file, updated)

        say_status :updated, file, :blue
      end

      def add_namespace(content, namespace)
        modules = namespace.split("::")
        indent = ""

        # Build opening modules
        opening = modules.map do |mod|
          line = "#{indent}module #{mod}"
          indent += "  "
          line
        end.join("\n")

        # Build closing modules
        closing = modules.map { "end" }.join("\n")

        # Indent original content
        indented_content = content.lines.map do |line|
          line.chomp.empty? ? line : ("  " * modules.size) + line
        end.join

        "#{opening}\n#{indented_content}#{closing}\n"
      end
    end
  end
end
```

### 4. Update Install Generator

Modify `install_generator.rb` to create the new structure:

```ruby
def create_directory_structure
  empty_directory "app/llm"
  empty_directory "app/llm/agents"
  empty_directory "app/llm/audio/speakers"
  empty_directory "app/llm/audio/transcribers"
  empty_directory "app/llm/image/generators"
  empty_directory "app/llm/image/editors"
  empty_directory "app/llm/image/analyzers"
  empty_directory "app/llm/image/transformers"
  empty_directory "app/llm/image/upscalers"
  empty_directory "app/llm/image/variators"
  empty_directory "app/llm/image/background_removers"
  empty_directory "app/llm/text/embedders"
  empty_directory "app/llm/text/moderators"
  empty_directory "app/llm/workflows"
  empty_directory "app/llm/tools"
end
```

### 5. Update Engine

Update autoload paths in `lib/ruby_llm/agents/engine.rb`:

```ruby
initializer "ruby_llm_agents.autoload_paths" do |app|
  llm_paths = [
    # Top-level
    "app/llm/agents",
    "app/llm/workflows",
    "app/llm/tools",
    # Audio
    "app/llm/audio/speakers",
    "app/llm/audio/transcribers",
    # Image
    "app/llm/image/analyzers",
    "app/llm/image/background_removers",
    "app/llm/image/editors",
    "app/llm/image/generators",
    "app/llm/image/transformers",
    "app/llm/image/upscalers",
    "app/llm/image/variators",
    # Text
    "app/llm/text/embedders",
    "app/llm/text/moderators"
  ].map { |dir| Rails.root.join(dir) }

  app.config.autoload_paths += llm_paths
  app.config.eager_load_paths += llm_paths
end
```

### 6. Update Example App

Restructure `example/app/` to match new structure and update all namespaces.

### 7. Update Documentation

- Update README with new directory structure
- Update wiki pages
- Add migration guide for existing users

---

## Upgrade Generator Specs

Create `spec/generators/restructure_generator_spec.rb`:

```ruby
# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "RestructureGenerator" do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:app_dir) { File.join(tmp_dir, "app") }

  before do
    FileUtils.mkdir_p(app_dir)
    setup_old_structure
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "directory structure creation" do
    before { run_generator }

    it "creates app/llm directory" do
      expect(File.directory?(File.join(app_dir, "llm"))).to be true
    end

    it "creates app/llm/agents directory" do
      expect(File.directory?(File.join(app_dir, "llm/agents"))).to be true
    end

    it "creates app/llm/audio directory structure" do
      expect(File.directory?(File.join(app_dir, "llm/audio"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/audio/speakers"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/audio/transcribers"))).to be true
    end

    it "creates app/llm/image directory structure" do
      expect(File.directory?(File.join(app_dir, "llm/image"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/generators"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/editors"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/analyzers"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/transformers"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/upscalers"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/variators"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/image/background_removers"))).to be true
    end

    it "creates app/llm/text directory structure" do
      expect(File.directory?(File.join(app_dir, "llm/text"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/text/embedders"))).to be true
      expect(File.directory?(File.join(app_dir, "llm/text/moderators"))).to be true
    end

    it "creates app/llm/workflows directory" do
      expect(File.directory?(File.join(app_dir, "llm/workflows"))).to be true
    end

    it "creates app/llm/tools directory" do
      expect(File.directory?(File.join(app_dir, "llm/tools"))).to be true
    end
  end

  describe "directory migration" do
    before { run_generator }

    it "moves agents to app/llm/agents" do
      expect(File.exist?(File.join(app_dir, "llm/agents/application_agent.rb"))).to be true
      expect(File.exist?(File.join(app_dir, "llm/agents/support_agent.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "agents"))).to be false
    end

    it "moves speakers to app/llm/audio/speakers" do
      expect(File.exist?(File.join(app_dir, "llm/audio/speakers/application_speaker.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "speakers"))).to be false
    end

    it "moves transcribers to app/llm/audio/transcribers" do
      expect(File.exist?(File.join(app_dir, "llm/audio/transcribers/application_transcriber.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "transcribers"))).to be false
    end

    it "moves image_generators to app/llm/image/generators" do
      expect(File.exist?(File.join(app_dir, "llm/image/generators/application_image_generator.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "image_generators"))).to be false
    end

    it "moves image_editors to app/llm/image/editors" do
      expect(File.exist?(File.join(app_dir, "llm/image/editors/application_image_editor.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "image_editors"))).to be false
    end

    it "moves image_analyzers to app/llm/image/analyzers" do
      expect(File.exist?(File.join(app_dir, "llm/image/analyzers/application_image_analyzer.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "image_analyzers"))).to be false
    end

    it "moves embedders to app/llm/text/embedders" do
      expect(File.exist?(File.join(app_dir, "llm/text/embedders/application_embedder.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "embedders"))).to be false
    end

    it "moves moderators to app/llm/text/moderators" do
      expect(File.exist?(File.join(app_dir, "llm/text/moderators/application_moderator.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "moderators"))).to be false
    end

    it "moves workflows to app/llm/workflows" do
      expect(File.exist?(File.join(app_dir, "llm/workflows/application_workflow.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "workflows"))).to be false
    end

    it "moves tools to app/llm/tools" do
      expect(File.exist?(File.join(app_dir, "llm/tools/weather_tool.rb"))).to be true
      expect(File.directory?(File.join(app_dir, "tools"))).to be false
    end

    it "skips directories that don't exist" do
      FileUtils.rm_rf(File.join(app_dir, "image_transformers"))
      expect { run_generator }.not_to raise_error
    end

    it "preserves nested files within directories" do
      nested_dir = File.join(app_dir, "agents/support")
      FileUtils.mkdir_p(nested_dir)
      File.write(File.join(nested_dir, "helper.rb"), "class Support::Helper; end")

      run_generator

      expect(File.exist?(File.join(app_dir, "llm/agents/support/helper.rb"))).to be true
    end
  end

  describe "namespace updates" do
    before { run_generator }

    context "top-level llm namespace (agents, workflows, tools)" do
      it "adds Llm module to agent classes" do
        content = File.read(File.join(app_dir, "llm/agents/support_agent.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("class SupportAgent")
        expect(content).not_to include("module Audio")
        expect(content).not_to include("module Image")
      end

      it "adds Llm module to application_agent" do
        content = File.read(File.join(app_dir, "llm/agents/application_agent.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("class ApplicationAgent")
      end

      it "adds Llm module to workflow classes" do
        content = File.read(File.join(app_dir, "llm/workflows/application_workflow.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("class ApplicationWorkflow")
      end

      it "adds Llm module to tool classes" do
        content = File.read(File.join(app_dir, "llm/tools/weather_tool.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("class WeatherTool")
      end
    end

    context "audio namespace" do
      it "adds Llm::Audio module to speaker classes" do
        content = File.read(File.join(app_dir, "llm/audio/speakers/application_speaker.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Audio")
        expect(content).to include("class ApplicationSpeaker")
      end

      it "adds Llm::Audio module to transcriber classes" do
        content = File.read(File.join(app_dir, "llm/audio/transcribers/application_transcriber.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Audio")
        expect(content).to include("class ApplicationTranscriber")
      end
    end

    context "image namespace" do
      it "adds Llm::Image module to generator classes" do
        content = File.read(File.join(app_dir, "llm/image/generators/application_image_generator.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageGenerator")
      end

      it "adds Llm::Image module to editor classes" do
        content = File.read(File.join(app_dir, "llm/image/editors/application_image_editor.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageEditor")
      end

      it "adds Llm::Image module to analyzer classes" do
        content = File.read(File.join(app_dir, "llm/image/analyzers/application_image_analyzer.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Image")
        expect(content).to include("class ApplicationImageAnalyzer")
      end
    end

    context "text namespace" do
      it "adds Llm::Text module to embedder classes" do
        content = File.read(File.join(app_dir, "llm/text/embedders/application_embedder.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Text")
        expect(content).to include("class ApplicationEmbedder")
      end

      it "adds Llm::Text module to moderator classes" do
        content = File.read(File.join(app_dir, "llm/text/moderators/application_moderator.rb"))
        expect(content).to include("module Llm")
        expect(content).to include("module Text")
        expect(content).to include("class ApplicationModerator")
      end
    end

    it "skips files already namespaced with Llm" do
      file_path = File.join(app_dir, "agents/support_agent.rb")
      File.write(file_path, <<~RUBY)
        module Llm
          class SupportAgent < ApplicationAgent
          end
        end
      RUBY

      run_generator

      content = File.read(File.join(app_dir, "llm/agents/support_agent.rb"))
      expect(content.scan("module Llm").count).to eq(1)
    end
  end

  describe "idempotency" do
    it "can be run multiple times safely" do
      run_generator
      expect { run_generator }.not_to raise_error
    end

    it "does not duplicate namespace on second run" do
      run_generator
      run_generator

      content = File.read(File.join(app_dir, "llm/agents/support_agent.rb"))
      expect(content.scan("module Llm").count).to eq(1)
    end

    it "does not duplicate nested namespace on second run" do
      run_generator
      run_generator

      content = File.read(File.join(app_dir, "llm/audio/speakers/application_speaker.rb"))
      expect(content.scan("module Audio").count).to eq(1)
    end
  end

  describe "edge cases" do
    it "handles empty directories" do
      FileUtils.mkdir_p(File.join(app_dir, "image_upscalers"))
      run_generator
      expect(File.directory?(File.join(app_dir, "llm/image/upscalers"))).to be true
    end

    it "handles files with syntax errors gracefully" do
      File.write(File.join(app_dir, "agents/broken.rb"), "class Broken <")
      expect { run_generator }.not_to raise_error
    end

    it "preserves file permissions" do
      file_path = File.join(app_dir, "agents/support_agent.rb")
      File.chmod(0755, file_path)

      run_generator

      new_path = File.join(app_dir, "llm/agents/support_agent.rb")
      expect(File.stat(new_path).mode & 0777).to eq(0755)
    end

    it "handles deeply nested subdirectories" do
      nested_dir = File.join(app_dir, "agents/support/utils/helpers")
      FileUtils.mkdir_p(nested_dir)
      File.write(File.join(nested_dir, "formatter.rb"), "class Formatter; end")

      run_generator

      expect(File.exist?(File.join(app_dir, "llm/agents/support/utils/helpers/formatter.rb"))).to be true
    end

    it "preserves non-ruby files" do
      File.write(File.join(app_dir, "agents/README.md"), "# Agents")

      run_generator

      expect(File.exist?(File.join(app_dir, "llm/agents/README.md"))).to be true
    end
  end

  describe "partial migrations" do
    it "handles apps with only agents directory" do
      # Remove all directories except agents
      %w[embedders speakers transcribers image_generators image_editors
         image_analyzers moderators workflows tools].each do |dir|
        FileUtils.rm_rf(File.join(app_dir, dir))
      end

      expect { run_generator }.not_to raise_error
      expect(File.exist?(File.join(app_dir, "llm/agents/application_agent.rb"))).to be true
    end

    it "handles apps with only image directories" do
      %w[agents embedders speakers transcribers moderators workflows tools].each do |dir|
        FileUtils.rm_rf(File.join(app_dir, dir))
      end

      expect { run_generator }.not_to raise_error
      expect(File.exist?(File.join(app_dir, "llm/image/generators/application_image_generator.rb"))).to be true
    end
  end

  describe "custom root directory" do
    context "with --root=ai option" do
      it "creates app/ai directory instead of app/llm" do
        run_generator(root: "ai")
        expect(File.directory?(File.join(app_dir, "ai"))).to be true
        expect(File.directory?(File.join(app_dir, "llm"))).to be false
      end

      it "creates full directory structure under app/ai" do
        run_generator(root: "ai")
        expect(File.directory?(File.join(app_dir, "ai/agents"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/audio/speakers"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/audio/transcribers"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/image/generators"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/text/embedders"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/workflows"))).to be true
        expect(File.directory?(File.join(app_dir, "ai/tools"))).to be true
      end

      it "moves files to app/ai" do
        run_generator(root: "ai")
        expect(File.exist?(File.join(app_dir, "ai/agents/application_agent.rb"))).to be true
        expect(File.exist?(File.join(app_dir, "ai/agents/support_agent.rb"))).to be true
      end

      it "uses AI namespace instead of Llm" do
        run_generator(root: "ai")
        content = File.read(File.join(app_dir, "ai/agents/support_agent.rb"))
        expect(content).to include("module AI")
        expect(content).not_to include("module Llm")
      end

      it "uses AI::Audio namespace for speakers" do
        run_generator(root: "ai")
        content = File.read(File.join(app_dir, "ai/audio/speakers/application_speaker.rb"))
        expect(content).to include("module AI")
        expect(content).to include("module Audio")
      end

      it "uses AI::Image namespace for image generators" do
        run_generator(root: "ai")
        content = File.read(File.join(app_dir, "ai/image/generators/application_image_generator.rb"))
        expect(content).to include("module AI")
        expect(content).to include("module Image")
      end

      it "uses AI::Text namespace for embedders" do
        run_generator(root: "ai")
        content = File.read(File.join(app_dir, "ai/text/embedders/application_embedder.rb"))
        expect(content).to include("module AI")
        expect(content).to include("module Text")
      end
    end

    context "with --root=ruby_llm option" do
      it "creates app/ruby_llm directory" do
        run_generator(root: "ruby_llm")
        expect(File.directory?(File.join(app_dir, "ruby_llm"))).to be true
      end

      it "uses RubyLlm namespace" do
        run_generator(root: "ruby_llm")
        content = File.read(File.join(app_dir, "ruby_llm/agents/support_agent.rb"))
        expect(content).to include("module RubyLlm")
      end
    end

    context "with --root=ml option" do
      it "creates app/ml directory" do
        run_generator(root: "ml")
        expect(File.directory?(File.join(app_dir, "ml"))).to be true
      end

      it "uses ML namespace (uppercase)" do
        run_generator(root: "ml")
        content = File.read(File.join(app_dir, "ml/agents/support_agent.rb"))
        expect(content).to include("module ML")
      end
    end

    context "custom namespace override" do
      it "allows separate namespace from directory name" do
        run_generator(root: "ai", namespace: "ArtificialIntelligence")
        content = File.read(File.join(app_dir, "ai/agents/support_agent.rb"))
        expect(content).to include("module ArtificialIntelligence")
      end
    end

    context "idempotency with custom root" do
      it "can be run multiple times with same custom root" do
        run_generator(root: "ai")
        expect { run_generator(root: "ai") }.not_to raise_error
      end

      it "does not duplicate custom namespace on second run" do
        run_generator(root: "ai")
        run_generator(root: "ai")

        content = File.read(File.join(app_dir, "ai/agents/support_agent.rb"))
        expect(content.scan("module AI").count).to eq(1)
      end
    end

    context "validation" do
      it "rejects invalid directory names with spaces" do
        expect { run_generator(root: "my llm") }.to raise_error(ArgumentError, /invalid root directory name/i)
      end

      it "rejects invalid directory names with special characters" do
        expect { run_generator(root: "llm@ai") }.to raise_error(ArgumentError, /invalid root directory name/i)
      end

      it "accepts underscores in directory names" do
        expect { run_generator(root: "ruby_llm") }.not_to raise_error
      end

      it "accepts hyphens in directory names" do
        run_generator(root: "ruby-llm")
        expect(File.directory?(File.join(app_dir, "ruby-llm"))).to be true
      end
    end
  end

  private

  def setup_old_structure
    # Create old directory structure with sample files

    # Agents
    FileUtils.mkdir_p(File.join(app_dir, "agents"))
    File.write(File.join(app_dir, "agents/application_agent.rb"), <<~RUBY)
      class ApplicationAgent < RubyLLM::Agents::Base
      end
    RUBY
    File.write(File.join(app_dir, "agents/support_agent.rb"), <<~RUBY)
      class SupportAgent < ApplicationAgent
        model "gpt-4"
      end
    RUBY

    # Speakers
    FileUtils.mkdir_p(File.join(app_dir, "speakers"))
    File.write(File.join(app_dir, "speakers/application_speaker.rb"), <<~RUBY)
      class ApplicationSpeaker < RubyLLM::Agents::Speaker
      end
    RUBY

    # Transcribers
    FileUtils.mkdir_p(File.join(app_dir, "transcribers"))
    File.write(File.join(app_dir, "transcribers/application_transcriber.rb"), <<~RUBY)
      class ApplicationTranscriber < RubyLLM::Agents::Transcriber
      end
    RUBY

    # Image generators
    FileUtils.mkdir_p(File.join(app_dir, "image_generators"))
    File.write(File.join(app_dir, "image_generators/application_image_generator.rb"), <<~RUBY)
      class ApplicationImageGenerator < RubyLLM::Agents::ImageGenerator
      end
    RUBY

    # Image editors
    FileUtils.mkdir_p(File.join(app_dir, "image_editors"))
    File.write(File.join(app_dir, "image_editors/application_image_editor.rb"), <<~RUBY)
      class ApplicationImageEditor < RubyLLM::Agents::ImageEditor
      end
    RUBY

    # Image analyzers
    FileUtils.mkdir_p(File.join(app_dir, "image_analyzers"))
    File.write(File.join(app_dir, "image_analyzers/application_image_analyzer.rb"), <<~RUBY)
      class ApplicationImageAnalyzer < RubyLLM::Agents::ImageAnalyzer
      end
    RUBY

    # Embedders
    FileUtils.mkdir_p(File.join(app_dir, "embedders"))
    File.write(File.join(app_dir, "embedders/application_embedder.rb"), <<~RUBY)
      class ApplicationEmbedder < RubyLLM::Agents::Embedder
      end
    RUBY

    # Moderators
    FileUtils.mkdir_p(File.join(app_dir, "moderators"))
    File.write(File.join(app_dir, "moderators/application_moderator.rb"), <<~RUBY)
      class ApplicationModerator < RubyLLM::Agents::Moderator
      end
    RUBY

    # Workflows
    FileUtils.mkdir_p(File.join(app_dir, "workflows"))
    File.write(File.join(app_dir, "workflows/application_workflow.rb"), <<~RUBY)
      class ApplicationWorkflow < RubyLLM::Agents::Workflow
      end
    RUBY

    # Tools
    FileUtils.mkdir_p(File.join(app_dir, "tools"))
    File.write(File.join(app_dir, "tools/weather_tool.rb"), <<~RUBY)
      class WeatherTool < RubyLLM::Tool
        def call(location:)
        end
      end
    RUBY
  end

  def run_generator(root: "llm", namespace: nil)
    # Simulate generator behavior for testing
    # In real implementation, this would invoke the actual generator

    # Validate root directory name
    validate_root_directory!(root)

    @root_dir = root
    @root_namespace = namespace || camelize(root)

    # Create directory structure
    create_directory_structure

    # Move directories
    move_directories

    # Update namespaces
    update_namespaces
  end

  def validate_root_directory!(root)
    unless root.match?(/\A[a-z][a-z0-9_-]*\z/i)
      raise ArgumentError, "Invalid root directory name: #{root}"
    end
  end

  def camelize(str)
    # Handle special cases for common abbreviations
    return "AI" if str.downcase == "ai"
    return "ML" if str.downcase == "ml"
    return "LLM" if str.downcase == "llm"

    # Standard camelization
    str.split(/[-_]/).map(&:capitalize).join
  end

  def create_directory_structure
    root = @root_dir
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/agents"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/audio/speakers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/audio/transcribers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/analyzers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/background_removers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/editors"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/generators"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/transformers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/upscalers"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/image/variators"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/text/embedders"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/text/moderators"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/workflows"))
    FileUtils.mkdir_p(File.join(app_dir, "#{root}/tools"))
  end

  def move_directories
    directory_mapping.each do |old_dir, config|
      source = File.join(app_dir, old_dir)
      destination = File.join(app_dir, config[:path])

      next unless File.directory?(source)

      Dir.glob("#{source}/**/*", File::FNM_DOTMATCH).each do |item|
        next if item.end_with?(".", "..")
        next if File.directory?(item)

        relative_path = item.sub("#{source}/", "")
        dest_item = File.join(destination, relative_path)

        FileUtils.mkdir_p(File.dirname(dest_item))
        FileUtils.mv(item, dest_item)
      end

      FileUtils.rm_rf(source)
    end
  end

  def update_namespaces
    directory_mapping.each do |_old_dir, config|
      directory_path = File.join(app_dir, config[:path])
      next unless File.directory?(directory_path)

      Dir.glob("#{directory_path}/**/*.rb").each do |file|
        update_file_namespace(file, config[:namespace])
      end
    end
  end

  def update_file_namespace(file, namespace)
    content = File.read(file)

    return if content.include?("module #{namespace.split('::').first}")

    updated = add_namespace(content, namespace)
    File.write(file, updated)
  end

  def add_namespace(content, namespace)
    modules = namespace.split("::")
    indent = ""

    opening = modules.map do |mod|
      line = "#{indent}module #{mod}"
      indent += "  "
      line
    end.join("\n")

    closing = modules.reverse.map { |_| "end" }.join("\n")

    indented_content = content.lines.map do |line|
      line.chomp.empty? ? line : ("  " * modules.size) + line
    end.join

    "#{opening}\n#{indented_content}#{closing}\n"
  end

  def directory_mapping
    root = @root_dir || "llm"
    ns = @root_namespace || "Llm"

    {
      "agents" => { path: "#{root}/agents", namespace: ns },
      "workflows" => { path: "#{root}/workflows", namespace: ns },
      "tools" => { path: "#{root}/tools", namespace: ns },
      "speakers" => { path: "#{root}/audio/speakers", namespace: "#{ns}::Audio" },
      "transcribers" => { path: "#{root}/audio/transcribers", namespace: "#{ns}::Audio" },
      "image_generators" => { path: "#{root}/image/generators", namespace: "#{ns}::Image" },
      "image_editors" => { path: "#{root}/image/editors", namespace: "#{ns}::Image" },
      "image_analyzers" => { path: "#{root}/image/analyzers", namespace: "#{ns}::Image" },
      "embedders" => { path: "#{root}/text/embedders", namespace: "#{ns}::Text" },
      "moderators" => { path: "#{root}/text/moderators", namespace: "#{ns}::Text" }
    }
  end
end
```

---

## Rollback Plan

If users need to revert:

```bash
# Manual rollback steps
cd app

# Move top-level back
mv llm/agents .
mv llm/workflows .
mv llm/tools .

# Move audio back
mv llm/audio/speakers .
mv llm/audio/transcribers .

# Move image back (restore old names)
mv llm/image/generators image_generators
mv llm/image/editors image_editors
mv llm/image/analyzers image_analyzers
mv llm/image/transformers image_transformers
mv llm/image/upscalers image_upscalers
mv llm/image/variators image_variators
mv llm/image/background_removers .

# Move text back
mv llm/text/embedders .
mv llm/text/moderators .

# Cleanup
rm -rf llm

# Then manually remove namespace wrappers from files
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

1. ~~Should we support both structures during a transition period?~~
2. ~~Should `tools/` also be under `app/llm/` or stay separate since tools are used by agents?~~ → Yes, under `app/llm/tools/`
3. ~~Alternative namespace names: `Llm::`, `AI::`, `RubyLlm::`?~~ → Configurable via `--root` option (default: `llm`/`Llm`)
4. Should image class names drop the `Image` prefix since they're already under `Llm::Image::`?
   - e.g., `Llm::Image::Generator` vs `Llm::Image::ImageGenerator`
