# Multi-Source Pricing

RubyLLM::Agents uses a **multi-source pricing cascade** to automatically resolve costs for all model types (text LLM, transcription, TTS, image, embedding). The system queries multiple free public pricing APIs and falls back gracefully when any source is unavailable.

## How It Works

When calculating costs, the system cascades through pricing sources in priority order, stopping at the first match:

```
1. User config          (instant, always wins)
2. RubyLLM gem          (local, no HTTP, already a dependency)
3. LiteLLM              (bulk JSON, ~2000+ models)
4. Portkey AI           (per-model query, 3000+ models)
5. OpenRouter           (bulk JSON, 400+ text models)
6. Helicone             (bulk JSON, 172 text models)
7. LLM Pricing AI       (per-model, ~79 models, last resort)
```

This lazy cascade means if LiteLLM has the price, no other API is ever called.

## Coverage Matrix

| Source | Text LLM | Transcription | TTS | Image | Embedding | Fetch Style |
|--------|:-:|:-:|:-:|:-:|:-:|-------------|
| User config | all | all | all | all | all | Instant |
| RubyLLM gem | ++ | + | - | - | + | Local |
| LiteLLM | ++ | ++ | + | + | + | Bulk (1 call) |
| Portkey AI | ++ | + | + | + | + | Per-model |
| OpenRouter | ++ | - | - | - | - | Bulk (1 call) |
| Helicone | + | - | - | - | - | Bulk (1 call) |
| LLM Pricing AI | ~ | - | - | - | - | Per-model |

`++` = excellent, `+` = some coverage, `-` = none, `~` = minimal

## Caching

All API responses are cached with a two-layer strategy:

- **Layer 1: In-memory** (per-process, instant) - Avoids redundant HTTP calls within the same process
- **Layer 2: Rails.cache** (cross-process, survives restarts) - Shares data between web workers

Default cache TTL is **24 hours**. Configure via:

```ruby
RubyLLM::Agents.configure do |c|
  c.pricing_cache_ttl = 86_400  # 24 hours (default)
end
```

Force refresh all cached pricing data:

```ruby
RubyLLM::Agents::Pricing::DataStore.refresh!           # all sources
RubyLLM::Agents::Pricing::DataStore.refresh!(:litellm)  # just LiteLLM
RubyLLM::Agents::Pricing::DataStore.refresh!(:portkey)   # all Portkey entries
```

## Configuration

### User-Defined Pricing Overrides

User config always takes highest priority. Set per-model prices for any model type:

```ruby
RubyLLM::Agents.configure do |c|
  # Transcription pricing (per minute)
  c.transcription_model_pricing = {
    "whisper-1" => 0.006,
    "gpt-4o-transcribe" => 0.01,
    "custom-model" => 0.05
  }

  # TTS pricing (per 1K characters)
  c.tts_model_pricing = {
    "tts-1" => 0.015,
    "eleven_v3" => 0.24
  }

  # Image pricing (per image or Hash for size/quality)
  c.image_model_pricing = {
    "dall-e-3" => { standard: 0.04, hd: 0.08 },
    "flux-pro" => 0.05
  }
end
```

### Enabling/Disabling Sources

Each external source can be individually enabled or disabled:

```ruby
RubyLLM::Agents.configure do |c|
  c.portkey_pricing_enabled = true     # default: true
  c.openrouter_pricing_enabled = true  # default: true
  c.helicone_pricing_enabled = true    # default: true
  c.llmpricing_enabled = true          # default: true
end
```

### Custom URLs

Override source endpoints (useful for self-hosted mirrors or proxies):

```ruby
RubyLLM::Agents.configure do |c|
  c.litellm_pricing_url = "https://my-mirror.example.com/litellm.json"
  c.portkey_pricing_url = "https://my-proxy.example.com/portkey"
  c.openrouter_pricing_url = "https://my-proxy.example.com/openrouter"
  c.helicone_pricing_url = "https://my-proxy.example.com/helicone"
  c.llmpricing_url = "https://my-proxy.example.com/llmpricing"
end
```

## Pricing Sources Detail

### RubyLLM Gem (Local)

The `ruby_llm` gem includes a built-in model registry with pricing data. This is checked first after user config because it requires zero HTTP calls.

```ruby
# Internally uses:
RubyLLM::Models.find("gpt-4o").pricing.text_tokens.input  # => price per million
```

### LiteLLM (Primary External Source)

Fetches the community-maintained [model_prices_and_context_window.json](https://github.com/BerriAI/litellm) from GitHub. Covers 2000+ models across all types.

Pricing fields used:
- `input_cost_per_token` / `output_cost_per_token` (text LLM, embedding)
- `input_cost_per_second` (transcription: whisper-1, etc.)
- `input_cost_per_audio_token` (transcription: gpt-4o-transcribe)
- `input_cost_per_character` (TTS)
- `input_cost_per_image` / `input_cost_per_pixel` (image generation)

### Portkey AI (Per-Model Fallback)

Queries `https://api.portkey.ai/model-configs/pricing/{provider}/{model}` for individual models. Broadest catalog (3000+ models across 40+ providers). Prices are in **cents per token** and automatically converted to USD.

### OpenRouter (Text LLM Focus)

Fetches the full model list from `https://openrouter.ai/api/v1/models`. 400+ text LLM models with pricing as string values (automatically converted to Float).

### Helicone (Text LLM Focus)

Fetches from `https://www.helicone.ai/api/llm-costs`. 172 text LLM models with prices per 1M tokens.

### LLM Pricing AI (Last Resort)

Queries `https://llmpricing.ai/api/prices` per model. Only ~79 models across 4 providers (OpenAI, Anthropic, Groq, Mistral). Returns calculated costs which are converted to per-token rates.

## Debugging

### View All Pricing Data

```ruby
# Transcription pricing from all sources
RubyLLM::Agents::Audio::TranscriptionPricing.all_pricing
# => { ruby_llm: {}, litellm: { "whisper-1" => {...} }, portkey: {}, ... }

# Check cache statistics
RubyLLM::Agents::Pricing::DataStore.cache_stats
# => { litellm: { cached: true, size: 2100 }, portkey: { cached_models: 3 }, ... }
```

### Check Pricing for a Specific Model

```ruby
# Transcription
RubyLLM::Agents::Audio::TranscriptionPricing.cost_per_minute("whisper-1")
# => 0.006

RubyLLM::Agents::Audio::TranscriptionPricing.pricing_found?("whisper-1")
# => true
```

### Use Individual Adapters

```ruby
# Query a specific source directly
RubyLLM::Agents::Pricing::LiteLLMAdapter.find_model("gpt-4o")
# => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :litellm }

RubyLLM::Agents::Pricing::PortkeyAdapter.find_model("gpt-4o")
# => { input_cost_per_token: 0.0000025, output_cost_per_token: 0.00001, source: :portkey }
```

## When No Pricing is Found

If no source has pricing for a model:
- `cost_per_minute` / `cost_per_image` / etc. returns `nil`
- `calculate_cost` returns `nil` (or `0` for transcription with a warning)
- A `pricing_warning` is stored in the execution's metadata
- A `Rails.logger.warn` is emitted with a configuration example

The warning message includes actionable instructions:

```
[RubyLLM::Agents] No pricing found for transcription model 'custom-whisper'.
Add it to your config:
  RubyLLM::Agents.configure do |c|
    c.transcription_model_pricing = { "custom-whisper" => 0.006 }
  end
```

## Integration Testing

Integration tests that hit real pricing APIs are available but excluded from the default test run:

```bash
# Run integration tests (hits real APIs)
RUN_INTEGRATION=1 bundle exec rspec --tag integration

# Run only pricing integration tests
RUN_INTEGRATION=1 bundle exec rspec spec/lib/pricing/ --tag integration
```
