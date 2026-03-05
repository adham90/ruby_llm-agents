# Mercury (Inception Labs) Provider Support — Detailed Implementation Plan

## Overview

Add first-class support for [Inception Labs' Mercury](https://www.inceptionlabs.ai/) diffusion LLM (dLLM) models to the `ruby_llm` gem, which will automatically enable Mercury support in `ruby_llm-agents`.

Mercury models are **OpenAI API-compatible**, so the implementation follows the same pattern used by DeepSeek, xAI, Perplexity, and other OpenAI-compatible providers already in the gem.

---

## Mercury Models Reference

| Model ID | Type | Context Window | Max Output | Input $/1M | Output $/1M | Capabilities |
|---|---|---|---|---|---|---|
| `mercury-2` | Chat/Reasoning | 128K | 32K | $0.25 | $0.75 | streaming, function_calling, structured_output, reasoning |
| `mercury` | Chat | 128K | 32K | $0.25 | $0.75 | streaming, function_calling, structured_output |
| `mercury-coder-small` | Code | 128K | 32K | $0.25 | $1.00 | streaming |
| `mercury-edit` | Code/FIM | 128K | 32K | $0.25 | $1.00 | streaming, fim |

### API Details

- **Base URL:** `https://api.inceptionlabs.ai/v1`
- **Auth:** `Authorization: Bearer $INCEPTION_API_KEY`
- **Endpoints:**
  - `/chat/completions` — standard chat (OpenAI-compatible)
  - `/fim/completions` — fill-in-the-middle (code completion)
  - `/models` — list available models
- **Special Parameters:**
  - `diffusing: true` — enables diffusion process visualization during streaming
- **Supported:** streaming, tools/function calling, structured output, response_format
- **Not Supported:** vision, audio, images, embeddings

---

## Architecture Decision

**Approach: Add as a native provider in the `ruby_llm` gem** (like DeepSeek, xAI, etc.)

Since Mercury's API is OpenAI-compatible, the new provider class inherits from `RubyLLM::Providers::OpenAI` and only overrides what's different (base URL, auth headers, capabilities, model parsing). This is the exact same pattern used by DeepSeek, xAI, Perplexity, and GPUStack.

Once added to `ruby_llm`, the `ruby_llm-agents` gem gains full Mercury support automatically — agents can use `model "mercury-2"` with zero additional code.

---

## Implementation Steps

### Phase 1: Core Provider (in `ruby_llm` gem)

#### Step 1.1: Add Configuration Attribute

**File:** `lib/ruby_llm/configuration.rb`

Add `inception_api_key` to the `attr_accessor` list:

```ruby
attr_accessor :openai_api_key,
              # ... existing keys ...
              :inception_api_key,  # <-- ADD
              :mistral_api_key,
              # ...
```

#### Step 1.2: Create Provider Class

**File:** `lib/ruby_llm/providers/inception.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Providers
    # Inception Labs Mercury API integration (OpenAI-compatible).
    # https://docs.inceptionlabs.ai/
    class Inception < OpenAI
      include Inception::Chat
      include Inception::Models

      def api_base
        'https://api.inceptionlabs.ai/v1'
      end

      def headers
        {
          'Authorization' => "Bearer #{@config.inception_api_key}"
        }
      end

      class << self
        def capabilities
          Inception::Capabilities
        end

        def configuration_requirements
          %i[inception_api_key]
        end
      end
    end
  end
end
```

#### Step 1.3: Create Capabilities Module

**File:** `lib/ruby_llm/providers/inception/capabilities.rb`

Defines pricing, context windows, and feature support for each Mercury model:

```ruby
# frozen_string_literal: true

module RubyLLM
  module Providers
    class Inception
      # Determines capabilities and pricing for Inception Mercury models
      module Capabilities
        module_function

        REASONING_MODELS = %w[mercury-2].freeze
        CODER_MODELS = %w[mercury-coder-small mercury-edit].freeze

        def context_window_for(_model_id)
          128_000
        end

        def max_tokens_for(_model_id)
          32_000
        end

        def input_price_for(_model_id)
          0.25
        end

        def output_price_for(model_id)
          case model_id
          when /mercury-coder|mercury-edit/ then 1.00
          else 0.75
          end
        end

        def supports_vision?(_model_id)
          false
        end

        def supports_functions?(model_id)
          !CODER_MODELS.include?(model_id)
        end

        def supports_json_mode?(model_id)
          !CODER_MODELS.include?(model_id)
        end

        def format_display_name(model_id)
          case model_id
          when 'mercury-2' then 'Mercury 2'
          when 'mercury' then 'Mercury'
          when 'mercury-coder-small' then 'Mercury Coder Small'
          when 'mercury-edit' then 'Mercury Edit'
          else
            model_id.split('-').map(&:capitalize).join(' ')
          end
        end

        def model_type(model_id)
          CODER_MODELS.include?(model_id) ? 'code' : 'chat'
        end

        def model_family(_model_id)
          :mercury
        end

        def modalities_for(_model_id)
          { input: ['text'], output: ['text'] }
        end

        def capabilities_for(model_id)
          caps = ['streaming']
          unless CODER_MODELS.include?(model_id)
            caps << 'function_calling'
            caps << 'structured_output'
          end
          caps << 'reasoning' if REASONING_MODELS.include?(model_id)
          caps
        end

        def pricing_for(model_id)
          {
            text_tokens: {
              standard: {
                input_per_million: input_price_for(model_id),
                output_per_million: output_price_for(model_id)
              }
            }
          }
        end
      end
    end
  end
end
```

#### Step 1.4: Create Chat Module

**File:** `lib/ruby_llm/providers/inception/chat.rb`

Minimal — Mercury uses standard OpenAI chat format:

```ruby
# frozen_string_literal: true

module RubyLLM
  module Providers
    class Inception
      # Chat methods for Inception Mercury API
      module Chat
        def format_role(role)
          role.to_s
        end
      end
    end
  end
end
```

#### Step 1.5: Create Models Module

**File:** `lib/ruby_llm/providers/inception/models.rb`

Parses the `/models` endpoint response (OpenAI-compatible format):

```ruby
# frozen_string_literal: true

module RubyLLM
  module Providers
    class Inception
      # Models metadata for Inception Mercury models
      module Models
        module_function

        def parse_list_models_response(response, slug, capabilities)
          Array(response.body['data']).map do |model_data|
            model_id = model_data['id']

            Model::Info.new(
              id: model_id,
              name: capabilities.format_display_name(model_id),
              provider: slug,
              family: 'mercury',
              created_at: model_data['created'] ? Time.at(model_data['created']) : nil,
              context_window: capabilities.context_window_for(model_id),
              max_output_tokens: capabilities.max_tokens_for(model_id),
              modalities: capabilities.modalities_for(model_id),
              capabilities: capabilities.capabilities_for(model_id),
              pricing: capabilities.pricing_for(model_id),
              metadata: {
                object: model_data['object'],
                owned_by: model_data['owned_by']
              }.compact
            )
          end
        end
      end
    end
  end
end
```

#### Step 1.6: Register Provider

**File:** `lib/ruby_llm.rb`

Add Zeitwerk inflection and provider registration:

```ruby
# In the inflector block:
loader.inflector.inflect(
  # ... existing ...
  'inception' => 'Inception',
)

# At the bottom with other registrations:
RubyLLM::Provider.register :inception, RubyLLM::Providers::Inception
```

#### Step 1.7: Update models.json Registry (Optional)

**File:** `lib/ruby_llm/models.json`

Add Mercury model entries so they're available without calling the API's `/models` endpoint:

```json
{
  "mercury-2": {
    "id": "mercury-2",
    "name": "Mercury 2",
    "provider": "inception",
    "family": "mercury",
    "context_window": 128000,
    "max_output_tokens": 32000,
    "modalities": { "input": ["text"], "output": ["text"] },
    "capabilities": ["streaming", "function_calling", "structured_output", "reasoning"],
    "pricing": {
      "text_tokens": {
        "standard": { "input_per_million": 0.25, "output_per_million": 0.75 }
      }
    }
  },
  "mercury": {
    "id": "mercury",
    "name": "Mercury",
    "provider": "inception",
    "family": "mercury",
    "context_window": 128000,
    "max_output_tokens": 32000,
    "modalities": { "input": ["text"], "output": ["text"] },
    "capabilities": ["streaming", "function_calling", "structured_output"],
    "pricing": {
      "text_tokens": {
        "standard": { "input_per_million": 0.25, "output_per_million": 0.75 }
      }
    }
  },
  "mercury-coder-small": {
    "id": "mercury-coder-small",
    "name": "Mercury Coder Small",
    "provider": "inception",
    "family": "mercury",
    "context_window": 128000,
    "max_output_tokens": 32000,
    "modalities": { "input": ["text"], "output": ["text"] },
    "capabilities": ["streaming"],
    "pricing": {
      "text_tokens": {
        "standard": { "input_per_million": 0.25, "output_per_million": 1.00 }
      }
    }
  },
  "mercury-edit": {
    "id": "mercury-edit",
    "name": "Mercury Edit",
    "provider": "inception",
    "family": "mercury",
    "context_window": 128000,
    "max_output_tokens": 32000,
    "modalities": { "input": ["text"], "output": ["text"] },
    "capabilities": ["streaming"],
    "pricing": {
      "text_tokens": {
        "standard": { "input_per_million": 0.25, "output_per_million": 1.00 }
      }
    }
  }
}
```

---

### Phase 2: FIM (Fill-in-the-Middle) Support

Mercury's `mercury-coder-small` and `mercury-edit` models support FIM via a dedicated `/fim/completions` endpoint. This is a **new capability** not currently in `ruby_llm`.

#### Step 2.1: Add FIM Endpoint Method to Provider

**File:** `lib/ruby_llm/providers/inception.rb` (update)

```ruby
def fim_completion_url
  '/fim/completions'
end

def fim_complete(prefix:, suffix:, model:, temperature: nil, max_tokens: nil)
  payload = {
    model: model.id,
    prompt: prefix,
    suffix: suffix,
    temperature: temperature,
    max_tokens: max_tokens
  }.compact

  response = @connection.post(fim_completion_url, payload)
  parse_fim_response(response)
end
```

#### Step 2.2: Create FIM Response Parser

**File:** `lib/ruby_llm/providers/inception/fim.rb`

```ruby
# frozen_string_literal: true

module RubyLLM
  module Providers
    class Inception
      # Fill-in-the-middle completion support for Mercury code models
      module FIM
        def parse_fim_response(response)
          data = response.body
          choice = data['choices']&.first
          {
            text: choice&.dig('text') || choice&.dig('message', 'content'),
            model: data['model'],
            usage: {
              input_tokens: data.dig('usage', 'prompt_tokens'),
              output_tokens: data.dig('usage', 'completion_tokens')
            }
          }
        end
      end
    end
  end
end
```

---

### Phase 3: Diffusion Visualization Support (Optional/Future)

Mercury supports a `diffusing: true` parameter that shows intermediate refinement steps during streaming. This is a unique feature to diffusion LLMs.

#### Step 3.1: Add `diffusing` Parameter Support

Extend the chat module to pass through `diffusing` when requested via `params`:

```ruby
# Users would call:
RubyLLM.chat(model: 'mercury-2').ask("Hello", params: { diffusing: true })

# Or in an agent:
class MyAgent < ApplicationAgent
  model "mercury-2"

  def execute(context)
    context.params = { diffusing: true }
    super
  end
end
```

Since `params` are already merged into the payload via `Utils.deep_merge` in `Provider#complete`, this works automatically with **no code changes** — just documentation.

---

### Phase 4: ruby_llm-agents Integration

Since `ruby_llm-agents` delegates all provider logic to `ruby_llm`, most of this is **automatic**. However, a few touchpoints need attention:

#### Step 4.1: Pricing Adapter Update

**File:** `lib/ruby_llm/agents/pricing/ruby_llm_adapter.rb`

No changes needed — the adapter reads from `RubyLLM::Models.find(model_id)` which will automatically include Mercury models once registered.

#### Step 4.2: Example Agent

**File:** `example/app/agents/mercury_agent.rb`

```ruby
class MercuryAgent < ApplicationAgent
  model "mercury-2"
  temperature 0.7

  system "You are a helpful assistant powered by Mercury, a diffusion LLM."
  user "{question}"
end
```

#### Step 4.3: Example Coder Agent

**File:** `example/app/agents/mercury_coder_agent.rb`

```ruby
class MercuryCoderAgent < ApplicationAgent
  model "mercury-coder-small"
  temperature 0.0

  system "You are an expert programmer. Write clean, efficient code."
  user "{task}"
end
```

#### Step 4.4: Configuration Documentation

**File:** `example/config/initializers/ruby_llm.rb` (update)

```ruby
RubyLLM.configure do |config|
  # ... existing config ...
  config.inception_api_key = ENV['INCEPTION_API_KEY']
end
```

#### Step 4.5: Dashboard Model Display

No changes needed — the dashboard reads model names from execution records, which will automatically show Mercury model names.

---

### Phase 5: Tests

#### Step 5.1: Provider Unit Tests (in `ruby_llm` gem)

**File:** `spec/ruby_llm/providers/inception_spec.rb`

```ruby
RSpec.describe RubyLLM::Providers::Inception do
  describe '.slug' do
    it { expect(described_class.slug).to eq('inception') }
  end

  describe '.configuration_requirements' do
    it { expect(described_class.configuration_requirements).to eq(%i[inception_api_key]) }
  end

  describe '#api_base' do
    let(:config) { instance_double(RubyLLM::Configuration, inception_api_key: 'test-key') }
    let(:provider) { described_class.new(config) }

    it 'returns inception API base URL' do
      expect(provider.api_base).to eq('https://api.inceptionlabs.ai/v1')
    end
  end

  describe '#headers' do
    let(:config) { instance_double(RubyLLM::Configuration, inception_api_key: 'test-key') }
    let(:provider) { described_class.new(config) }

    it 'includes bearer auth header' do
      expect(provider.headers).to eq({ 'Authorization' => 'Bearer test-key' })
    end
  end
end
```

#### Step 5.2: Capabilities Tests

**File:** `spec/ruby_llm/providers/inception/capabilities_spec.rb`

Test pricing, context windows, feature flags for each model variant.

#### Step 5.3: Models Tests

**File:** `spec/ruby_llm/providers/inception/models_spec.rb`

Test `parse_list_models_response` with sample API response data.

#### Step 5.4: Integration Tests (in `ruby_llm-agents`)

**File:** `spec/agents/mercury_integration_spec.rb`

```ruby
RSpec.describe 'Mercury agent integration', :integration do
  before do
    skip 'Set RUN_INTEGRATION=1' unless ENV['RUN_INTEGRATION']
    RubyLLM.configure { |c| c.inception_api_key = ENV['INCEPTION_API_KEY'] }
  end

  it 'executes a Mercury agent' do
    agent_class = Class.new(RubyLLM::Agents::Base) do
      model 'mercury-2'
      system 'You are helpful.'
      user '{question}'
    end

    result = agent_class.call(question: 'Say hello')
    expect(result).to be_success
    expect(result.content).to be_present
  end
end
```

---

### Phase 6: FIM Agent Type (Optional Extension for `ruby_llm-agents`)

If FIM support (Phase 2) is implemented, create a specialized agent type:

#### Step 6.1: FIM Agent Base Class

**File:** `lib/ruby_llm/agents/code/fim_agent.rb`

```ruby
module RubyLLM
  module Agents
    module Code
      class FIMAgent < BaseAgent
        class << self
          def default_model
            'mercury-coder-small'
          end
        end

        private

        def execute(context)
          provider = build_provider(context)
          result = provider.fim_complete(
            prefix: context.params[:prefix],
            suffix: context.params[:suffix],
            model: effective_model(context),
            temperature: effective_temperature(context),
            max_tokens: context.params[:max_tokens]
          )
          context.response = result
          context
        end
      end
    end
  end
end
```

---

## File Summary

### New Files (in `ruby_llm` gem)

| File | Purpose |
|---|---|
| `lib/ruby_llm/providers/inception.rb` | Provider class (inherits OpenAI) |
| `lib/ruby_llm/providers/inception/capabilities.rb` | Model pricing, features, context windows |
| `lib/ruby_llm/providers/inception/chat.rb` | Chat format (minimal, OpenAI-compatible) |
| `lib/ruby_llm/providers/inception/models.rb` | Parse `/models` API response |
| `lib/ruby_llm/providers/inception/fim.rb` | FIM endpoint support (Phase 2) |
| `spec/ruby_llm/providers/inception_spec.rb` | Provider tests |
| `spec/ruby_llm/providers/inception/capabilities_spec.rb` | Capabilities tests |
| `spec/ruby_llm/providers/inception/models_spec.rb` | Models parsing tests |

### Modified Files (in `ruby_llm` gem)

| File | Change |
|---|---|
| `lib/ruby_llm/configuration.rb` | Add `inception_api_key` accessor |
| `lib/ruby_llm.rb` | Add Zeitwerk inflection + `Provider.register :inception` |
| `lib/ruby_llm/models.json` | Add Mercury model entries (optional) |

### New Files (in `ruby_llm-agents`)

| File | Purpose |
|---|---|
| `example/app/agents/mercury_agent.rb` | Example chat agent |
| `example/app/agents/mercury_coder_agent.rb` | Example coder agent |
| `spec/agents/mercury_integration_spec.rb` | Integration tests |
| `lib/ruby_llm/agents/code/fim_agent.rb` | FIM agent type (Phase 6, optional) |

### Modified Files (in `ruby_llm-agents`)

| File | Change |
|---|---|
| `example/config/initializers/ruby_llm.rb` | Add `inception_api_key` config |

---

## Implementation Order & Dependencies

```
Phase 1 (Core Provider) ← REQUIRED, do this first
  ├── Step 1.1: Configuration attribute
  ├── Step 1.2: Provider class
  ├── Step 1.3: Capabilities module
  ├── Step 1.4: Chat module
  ├── Step 1.5: Models module
  ├── Step 1.6: Register provider
  └── Step 1.7: models.json (optional)

Phase 4 (Agents Integration) ← Automatic after Phase 1
  ├── Step 4.2: Example agents
  ├── Step 4.4: Config documentation
  └── Step 4.5: Dashboard (no changes needed)

Phase 5 (Tests) ← Can run in parallel with Phase 4
  ├── Step 5.1: Provider unit tests
  ├── Step 5.2: Capabilities tests
  ├── Step 5.3: Models tests
  └── Step 5.4: Integration tests

Phase 2 (FIM Support) ← Optional, independent
  ├── Step 2.1: FIM endpoint
  └── Step 2.2: FIM response parser

Phase 3 (Diffusion Viz) ← Optional, no code changes needed
  └── Documentation only (params passthrough)

Phase 6 (FIM Agent) ← Optional, depends on Phase 2
  └── Step 6.1: FIM agent base class
```

---

## Risks & Considerations

1. **API Stability:** Mercury API is relatively new (launched mid-2025). Model IDs and pricing may change. The capabilities module should be easy to update.

2. **Tool/Function Calling:** OpenRouter lists tool support for `mercury`, but Mastra docs say it's not supported. Need to verify with actual API testing. The capabilities module can be toggled easily.

3. **Reasoning Support:** Mercury 2 has reasoning capabilities similar to DeepSeek R1. May need `thinking` parameter support if Inception implements extended thinking. Currently treated as standard chat.

4. **FIM Endpoint:** The `/fim/completions` endpoint is non-standard (not part of OpenAI's API). Phase 2 adds this as a new capability, but it requires a new method on the provider since `ruby_llm` doesn't have FIM support yet.

5. **Diffusion Streaming:** The `diffusing` parameter changes how streaming works — tokens are refined in parallel rather than appended sequentially. The existing streaming infrastructure should handle this, but may need testing to confirm the SSE format is compatible.

6. **Version Dependency:** Changes to `ruby_llm` gem need to be released before `ruby_llm-agents` can use them. Consider whether to:
   - Fork/PR `ruby_llm` upstream (preferred — benefits the whole ecosystem)
   - Monkey-patch locally as a temporary measure
   - Use `assume_model_exists: true` with `:openai` provider as a quick workaround

---

## Quick Workaround (No Gem Changes)

If you need Mercury support **immediately** without modifying the `ruby_llm` gem, you can use the OpenAI-compatible mode:

```ruby
RubyLLM.configure do |config|
  config.openai_api_key = ENV['INCEPTION_API_KEY']
  config.openai_api_base = 'https://api.inceptionlabs.ai/v1'
end

# Then in your agent:
class MercuryAgent < ApplicationAgent
  model "mercury-2"
  # ... works because it hits Inception's API via OpenAI-compatible client
end

# Or directly:
chat = RubyLLM.chat(model: 'mercury-2', assume_model_exists: true)
chat.ask("Hello!")
```

**Limitation:** This overrides the OpenAI API base globally, so you can't use OpenAI and Inception simultaneously. The proper provider approach (Phase 1) solves this.

---

## Sources

- [Inception Labs](https://www.inceptionlabs.ai/)
- [Inception API Docs](https://docs.inceptionlabs.ai/get-started/get-started)
- [Mercury Models & Pricing](https://docs.inceptionlabs.ai/get-started/models)
- [Mercury 2 Blog Post](https://www.inceptionlabs.ai/blog/introducing-mercury-2)
- [Mercury on OpenRouter](https://openrouter.ai/inception/mercury)
- [Mercury 2 Analysis](https://artificialanalysis.ai/models/mercury-2)
- [Mastra Inception Integration](https://mastra.ai/models/providers/inception)
- [ruby_llm gem](https://github.com/crmne/ruby_llm)
