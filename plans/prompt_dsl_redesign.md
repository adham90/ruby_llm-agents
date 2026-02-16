# Plan: Three-Role Prompt DSL Redesign

## Status: Draft
## Version: 1.1
## Date: 2026-02-16

---

## 1. Motivation

LLMs accept three message roles: **system**, **user**, and **assistant**. Our current DSL supports two (`system` and `prompt`), with inconsistent naming between the class-level DSL and method overrides:

| Current Class DSL | Current Method | LLM Role |
|---|---|---|
| `system` | `def system_prompt` | system |
| `prompt` | `def user_prompt` | user |
| *(not supported)* | *(not supported)* | assistant |

**Problems:**
1. No assistant prefill support (useful for forcing output format, few-shot examples)
2. `prompt` (class) vs `user_prompt` (method) naming mismatch is confusing
3. Block form (`system do ... end`) is redundant — if it's simple, use a string; if it's complex, use a method
4. Three ways to define a prompt (string, block, method) makes docs and mental model complex
5. Agents that are purely conversational (just a persona) require boilerplate `user "{message}"` wrapper

---

## 2. Proposed Design

### 2.1 Core Principle: Two Levels, Three Roles

| | Simple / Static | Dynamic / Complex |
|---|---|---|
| **How** | Class-level string or heredoc | Instance method override |
| **System** | `system "..."` | `def system_prompt` |
| **User** | `user "... {placeholder} ..."` | `def user_prompt` |
| **Assistant** | `assistant "..."` | `def assistant_prompt` |

**No block form.** Blocks are removed from the DSL. The rule is simple:
- **Static content** → class-level string/heredoc
- **Dynamic content** → method override

### 2.2 Naming Map

```
Class DSL        Method Override      LLM Role        Storage
─────────        ───────────────      ────────        ───────
system      →    system_prompt    →   system      →   @system_template
user        →    user_prompt      →   user        →   @user_template
assistant   →    assistant_prompt →   assistant   →   @assistant_template
prompt      →    (alias for user, deprecated)
```

### 2.3 Resolution Order (per role)

```
Instance method override  >  Class-level template  >  Inherited from superclass  >  Default
```

- `system_prompt`: returns `nil` if not defined (system is optional)
- `user_prompt`: raises `NotImplementedError` if not defined (user is required)
- `assistant_prompt`: returns `nil` if not defined (assistant is optional)

### 2.4 Why `_prompt` Suffix on Methods

- `def system` would shadow `Kernel#system` (executes shell commands) — **dangerous**
- `def user` conflicts with common Rails patterns (`user` model, `current_user`)
- `def assistant` is safe but inconsistent without suffix on the others
- `_prompt` suffix makes intent explicit: "this method returns a prompt string"

### 2.5 Why `user` Instead of `prompt` at Class Level

- `system` / `user` / `assistant` mirrors LLM API terminology exactly
- Three parallel names — easy to remember
- `prompt` was ambiguous — could mean any prompt, not specifically the user role
- `prompt` remains as a deprecated alias for backward compatibility

### 2.6 Two Agent Patterns: Template vs Conversational (`.call` vs `.ask`)

Agents fall into two natural categories:

| | Template Agent | Conversational Agent |
|---|---|---|
| **User input** | Structured params with `{placeholders}` | Freeform message string |
| **Defines** | `system` + `user` + `assistant` | `system` + `assistant` (no `user`) |
| **API** | `.call(**params)` | `.ask(message)` |
| **Use case** | Classifiers, extractors, formatters | Chatbots, Q&A, advisors |

**Template agents** are **functions** — structured input, structured output:

```ruby
class Classifier < ApplicationAgent
  system "You are a strict classifier."
  user "Classify: {text}"
  assistant '{"category":'
end

Classifier.call(text: "Meeting tomorrow")
```

**Conversational agents** are **assistants** — freeform input, freeform output:

```ruby
class RubyExpert < ApplicationAgent
  system "You are a senior Ruby developer."
end

RubyExpert.ask("What's the difference between proc and lambda?")
```

Without `.ask`, conversational agents require boilerplate:

```ruby
# Current — awkward boilerplate
class RubyExpert < ApplicationAgent
  system "You are a senior Ruby developer."
  user "{message}"  # ← Just wrapping a param, adds no value
end

RubyExpert.call(message: "What's the difference between proc and lambda?")
```

#### `.ask` API Design

```ruby
# Basic usage
RubyExpert.ask("What is metaprogramming?")

# With streaming
RubyExpert.ask("Explain closures") { |chunk| print chunk.content }

# Returns the same Result object as .call
result = RubyExpert.ask("What is Ruby?")
result.content       # => "Ruby is a dynamic..."
result.total_tokens  # => 150
result.total_cost    # => 0.0003
```

#### `.ask` Works on ALL Agents (Escape Hatch)

`.ask` bypasses the `user` template and sends the message directly. This works even on template agents:

```ruby
class Classifier < ApplicationAgent
  system "You are a classifier."
  user "Classify: {text}"       # Template for .call
end

# Normal structured usage:
Classifier.call(text: "hello")
# user prompt → "Classify: hello"

# Escape hatch — bypasses template:
Classifier.ask("Forget classification, just say hi")
# user prompt → "Forget classification, just say hi"
```

#### Updated Resolution Order for `user_prompt`

```
1. def user_prompt method override     → always wins (standard Ruby)
2. .ask(message) runtime message       → direct user input, bypasses template
3. user "template" class-level DSL     → interpolated with {placeholders}
4. Inherited from superclass           → parent's user config
5. None defined                        → raise NotImplementedError
```

Note: `.ask` sets the user prompt for that single execution. It does NOT modify the class-level DSL.

#### Agent Type Guidance

| Agent has... | Intended API | Can also use |
|---|---|---|
| `system` + `user` template | `.call(**params)` | `.ask(message)` as escape hatch |
| `system` only | `.ask(message)` | `.call` raises error (no user template) |
| `system` + `assistant` | `.ask(message)` | `.call` raises error (no user template) |
| All three roles defined | `.call(**params)` | `.ask(message)` as escape hatch |
| `user` template only | `.call(**params)` | `.ask(message)` as escape hatch |

---

## 3. Examples

### 3.1 Minimal Agent (One-Line Strings)

```ruby
class Classifier < ApplicationAgent
  model "claude-sonnet-4-5-20250929"

  system "You are a strict email classifier."
  user "Classify this email: {text}"
  assistant '{"category":'

  returns do
    string :category
    number :confidence
  end
end

result = Classifier.call(text: "Meeting at 3pm tomorrow")
# Model receives:
#   system:    "You are a strict email classifier."
#   user:      "Classify this email: Meeting at 3pm tomorrow"
#   assistant: "{\"category\":"
# Model continues from the assistant prefill → '{"category": "meeting", "confidence": 0.95}'
```

### 3.2 Multi-Line Static (Heredocs)

```ruby
class BlogWriter < ApplicationAgent
  model "gpt-4o"

  system <<~S
    You are a professional blog writer.
    Write engaging, SEO-friendly content.
    Use markdown formatting.
    Target audience: Ruby developers.
  S

  user <<~S
    Write a blog post about: {topic}
    Tone: {tone}
    Length: approximately {word_count} words
  S

  assistant "# "  # Forces the model to start with a markdown heading
end

result = BlogWriter.call(topic: "Rails 8", tone: "enthusiastic", word_count: 1500)
```

### 3.3 Dynamic Content (Method Overrides)

```ruby
class ContextualAssistant < ApplicationAgent
  model "claude-sonnet-4-5-20250929"
  param :question, required: true

  def system_prompt
    rules = CompanyPolicy.active.pluck(:content)

    <<~S
      You are a customer support assistant for #{company.name}.
      Today is #{Date.today}.

      Company policies:
      #{rules.map { |r| "- #{r}" }.join("\n")}
    S
  end

  def user_prompt
    context = SearchIndex.query(params[:question], limit: 5)

    <<~S
      Context:
      #{context.map(&:text).join("\n\n")}

      Question: #{params[:question]}
    S
  end

  def assistant_prompt
    "Based on our company policies, "
  end
end
```

### 3.4 Mixed (Class-Level + Method Override)

```ruby
class Translator < ApplicationAgent
  model "gpt-4o"

  # Static system instruction
  system "You are a professional translator. Preserve tone and meaning."

  # Static assistant prefill
  assistant '{"translation":'

  # Dynamic user prompt (needs runtime logic)
  def user_prompt
    source = LanguageDetector.detect(params[:text])

    <<~S
      Translate from #{source} to #{params[:target_language]}:

      #{params[:text]}
    S
  end
end
```

### 3.5 Subclass Inheritance

```ruby
class ApplicationAgent < RubyLLM::Agents::Base
  system "You are a helpful AI assistant."
end

class StrictAgent < ApplicationAgent
  # Overrides parent system prompt
  system "You are a strict, precise AI assistant. Never speculate."
end

class DynamicAgent < ApplicationAgent
  # Method override takes precedence over inherited class-level DSL
  def system_prompt
    base = "You are a helpful AI assistant."
    base += "\nDebug mode enabled." if Rails.env.development?
    base
  end
end
```

### 3.6 Assistant Prefill Use Cases

```ruby
# Force JSON output
class JsonAgent < ApplicationAgent
  system "Always respond in valid JSON."
  user "Extract entities from: {text}"
  assistant "{"  # Model continues from "{" → guaranteed JSON
end

# Force specific format
class ListAgent < ApplicationAgent
  system "List items clearly."
  user "List the benefits of {topic}"
  assistant "1. "  # Model starts with numbered list
end

# Few-shot via conversation history (NOT assistant prefill — see section 5.3)
```

### 3.7 Conversational Agent with `.ask`

```ruby
# Define just the persona — no user template needed
class RubyExpert < ApplicationAgent
  model "claude-sonnet-4-5-20250929"
  system "You are a senior Ruby developer with 20 years of experience."
end

# Ask anything
result = RubyExpert.ask("What's the difference between proc and lambda?")
puts result.content

# Stream the response
RubyExpert.ask("Explain Ruby's object model") do |chunk|
  print chunk.content
end
```

### 3.8 Conversational Agent with Prefill

```ruby
class JsonHelper < ApplicationAgent
  model "claude-sonnet-4-5-20250929"

  system "You are a helpful assistant. Always respond in valid JSON."
  assistant "{"

  returns do
    # schema varies per question
  end
end

result = JsonHelper.ask("List 3 Ruby web frameworks with descriptions")
# Model receives:
#   system:    "You are a helpful assistant. Always respond in valid JSON."
#   user:      "List 3 Ruby web frameworks with descriptions"
#   assistant: "{"
# Model continues from "{" → guaranteed JSON
```

### 3.9 Code Review Agent (Conversational with Dynamic System)

```ruby
class CodeReviewer < ApplicationAgent
  model "claude-sonnet-4-5-20250929"

  def system_prompt
    rules = team_style_guide

    <<~S
      You are a code reviewer for a Ruby on Rails project.
      Today is #{Date.today}.

      Team style guide:
      #{rules}
    S
  end

  private

  def team_style_guide
    File.read(Rails.root.join(".rubocop.yml"))
  rescue Errno::ENOENT
    "Follow standard Ruby style guidelines."
  end
end

# Usage — just pass the code to review
result = CodeReviewer.ask(<<~CODE)
  def calculate_total(items)
    total = 0
    items.each do |item|
      total = total + item.price * item.quantity
    end
    return total
  end
CODE

puts result.content  # Review feedback
```

### 3.10 `.ask` as Escape Hatch on Template Agent

```ruby
class Summarizer < ApplicationAgent
  model "gpt-4o"

  system "You are a summarization expert."
  user "Summarize in {max_words} words: {text}"
end

# Normal structured usage:
Summarizer.call(text: "Long article...", max_words: 100)

# Escape hatch — bypass template for a custom request:
Summarizer.ask("Give me a one-sentence summary of the Ruby programming language")
```

### 3.11 Backward Compatibility (`prompt` Alias)

```ruby
# These are equivalent:
class AgentA < ApplicationAgent
  user "Classify: {text}"        # New preferred syntax
end

class AgentB < ApplicationAgent
  prompt "Classify: {text}"      # Still works, deprecated
end
```

---

## 4. Implementation Details

### 4.1 Files to Modify

| File | Changes |
|---|---|
| `lib/ruby_llm/agents/dsl/base.rb` | Add `user`, `assistant`, `user_config`, `assistant_config`. Deprecate block params. Alias `prompt` → `user`. |
| `lib/ruby_llm/agents/base_agent.rb` | Add `#assistant_prompt` instance method. Add `.ask` class method. Add `@ask_message` handling in `#user_prompt`. Update resolution logic. |
| `lib/ruby_llm/agents/core/llm_interaction.rb` | Send assistant prefill in API calls (provider-specific). |
| `spec/` | Add specs for all new DSL methods, `.ask`, resolution order, integration. |

### 4.2 Changes to `dsl/base.rb`

#### Current State

```ruby
def prompt(template = nil, &block)
  if template
    @prompt_template = template
    auto_register_params_from_template(template)
  elsif block
    @prompt_block = block
  end
  @prompt_template || @prompt_block || inherited_or_default(:prompt_config, nil)
end

def system(text = nil, &block)
  if text
    @system_template = text
  elsif block
    @system_block = block
  end
  @system_template || @system_block || inherited_or_default(:system_config, nil)
end
```

#### Proposed State

```ruby
# Primary DSL method for user role
def user(template = nil)
  if template
    @user_template = template
    auto_register_params_from_template(template)
  end
  @user_template || inherited_or_default(:user_config, nil)
end

# Read-only config accessor
def user_config
  @user_template || inherited_or_default(:user_config, nil)
end

# Backward-compatible alias (deprecated)
def prompt(template = nil)
  if template
    ActiveSupport::Deprecation.warn(
      "prompt is deprecated, use user instead",
      caller
    )
  end
  user(template)
end
alias_method :prompt_config, :user_config

# System role
def system(text = nil)
  if text
    @system_template = text
  end
  @system_template || inherited_or_default(:system_config, nil)
end

def system_config
  @system_template || inherited_or_default(:system_config, nil)
end

# Assistant role (NEW)
def assistant(text = nil)
  if text
    @assistant_template = text
    auto_register_params_from_template(text)
  end
  @assistant_template || inherited_or_default(:assistant_config, nil)
end

def assistant_config
  @assistant_template || inherited_or_default(:assistant_config, nil)
end
```

**Key changes:**
- `prompt` renamed to `user`, `prompt` becomes alias with deprecation warning
- Block parameter (`&block`) removed from all three methods
- `assistant` added with same pattern as `system`/`user`
- `auto_register_params_from_template` called for both `user` and `assistant` (assistant may contain `{placeholders}` too)
- Internal storage: `@prompt_template` / `@prompt_block` → `@user_template` (keep `@prompt_template` as fallback for existing subclasses during transition)

### 4.3 Changes to `base_agent.rb`

#### Current State

```ruby
def user_prompt
  prompt_config = self.class.prompt_config
  return resolve_prompt_from_config(prompt_config) if prompt_config
  raise NotImplementedError, "#{self.class} must implement #user_prompt or use the prompt DSL"
end

def system_prompt
  system_config = self.class.system_config
  return resolve_prompt_from_config(system_config) if system_config
  nil
end
```

#### Proposed State

```ruby
def user_prompt
  config = self.class.user_config
  return interpolate_template(config) if config
  raise NotImplementedError,
    "#{self.class} must implement #user_prompt or use the `user` DSL"
end

def system_prompt
  config = self.class.system_config
  return interpolate_template(config) if config
  nil
end

def assistant_prompt
  config = self.class.assistant_config
  return interpolate_template(config) if config
  nil
end
```

**Key changes:**
- `resolve_prompt_from_config` simplified to `interpolate_template` (no more Proc handling since blocks are removed)
- `assistant_prompt` added with same pattern as `system_prompt` (returns `nil` if not defined)
- Error message updated to reference `user` DSL instead of `prompt`

#### Simplify `resolve_prompt_from_config`

Since blocks are removed, this method simplifies or can be inlined:

```ruby
# Before (handles String, Proc, other)
def resolve_prompt_from_config(config)
  case config
  when String
    interpolate_template(config)
  when Proc
    instance_eval(&config)
  else
    config.to_s
  end
end

# After (String only)
# Just use interpolate_template directly — no case statement needed
```

**Note:** Keep the Proc handling for one major version cycle (deprecated but functional) to avoid breaking existing agents that use block form.

### 4.4 Implementation of `.ask`

#### Class Method: `.ask(message, &block)`

Add to `base_agent.rb` alongside the existing `.call` and `.stream`:

```ruby
# Class method — primary API for conversational agents
def self.ask(message, **options, &block)
  if block
    # Streaming mode
    stream(**options, _ask_message: message, &block)
  else
    call(**options, _ask_message: message)
  end
end
```

`.ask` is syntactic sugar that passes the message through to `.call`/`.stream` via a special `_ask_message` key.

#### Instance Variable: `@ask_message`

In `#initialize`, extract the ask message from options:

```ruby
def initialize(model: self.class.model, temperature: self.class.temperature, **options)
  @ask_message = options.delete(:_ask_message)
  @model = model
  @temperature = temperature
  @options = options
  @tracked_tool_calls = []
  @pending_tool_call = nil
  validate_required_params! unless @ask_message  # Skip param validation for .ask
end
```

Key detail: **skip `validate_required_params!` when using `.ask`** because the agent may have `{placeholder}` params defined in its `user` template that aren't relevant when `.ask` bypasses the template.

#### Updated `#user_prompt` Resolution

```ruby
def user_prompt
  # 1. Method override always wins (standard Ruby dispatch)
  #    If subclass defines def user_prompt, this base implementation
  #    is never called — Ruby handles this automatically.

  # 2. .ask message takes precedence over template
  return @ask_message if @ask_message

  # 3. Class-level template
  config = self.class.user_config
  return interpolate_template(config) if config

  # 4. Nothing defined
  raise NotImplementedError,
    "#{self.class} must implement #user_prompt, use the `user` DSL, or call with .ask(message)"
end
```

#### Interaction with Method Overrides

If a subclass defines `def user_prompt`, it completely overrides the base implementation — including `.ask` message handling. This is standard Ruby. If someone needs both `.ask` support and custom logic, they can check `@ask_message`:

```ruby
class CustomAgent < ApplicationAgent
  system "You are helpful."

  def user_prompt
    message = @ask_message || params[:fallback_message]
    "Enhanced: #{message}"
  end
end
```

#### `.ask` with Attachments

Support the existing `with:` option for multimodal input:

```ruby
# Text + image
RubyExpert.ask("What's in this image?", with: "photo.jpg")

# Implementation: .ask passes through to .call which already handles `with:`
def self.ask(message, with: nil, **options, &block)
  if block
    stream(**options, with: with, _ask_message: message, &block)
  else
    call(**options, with: with, _ask_message: message)
  end
end
```

### 4.5 Changes to LLM Interaction (Sending Assistant Prefill)

The assistant prefill needs to be sent as the last message in the conversation with role `assistant`, **after** the user message (whether from `.call` template or `.ask` message). This is provider-specific:

**Claude (Anthropic):**
```json
{
  "system": "You are a classifier.",
  "messages": [
    {"role": "user", "content": "Classify: hello"},
    {"role": "assistant", "content": "{\"category\":"}
  ]
}
```

**OpenAI:**
OpenAI doesn't natively support assistant prefill in the same way. Options:
- Skip assistant prefill for OpenAI (log a warning)
- Use `logit_bias` or `response_format` as alternatives
- Include as a system instruction hint: "Begin your response with: ..."

**Implementation approach:**
```ruby
def build_messages
  messages = []
  messages << { role: "user", content: user_prompt }

  prefill = assistant_prompt
  if prefill
    if provider_supports_prefill?
      messages << { role: "assistant", content: prefill }
    else
      # Append hint to system prompt for providers that don't support prefill
      @system_prompt_suffix = "\nAlways begin your response with: #{prefill}"
    end
  end

  messages
end
```

### 4.5 Transition Strategy for Block Removal

Blocks won't be removed immediately. The transition:

**Phase 1 (v2.2.0):**
- Add `user`, `assistant`, `user_config`, `assistant_config`
- `prompt` becomes alias for `user` (no deprecation warning yet)
- Blocks still work but are undocumented
- Docs exclusively show string/heredoc + method override pattern

**Phase 2 (v2.3.0):**
- `prompt` emits deprecation warning
- Blocks emit deprecation warning
- Migration guide published

**Phase 3 (v3.0.0):**
- `prompt` removed (or kept as permanent alias, TBD)
- Block support removed
- `@prompt_block` / `@system_block` storage removed

---

## 5. Edge Cases & Decisions

### 5.1 Placeholder Support in Assistant Prefill

Should `assistant "Result for {query}:"` support `{placeholder}` substitution?

**Decision: Yes.** The assistant prefill may want to include dynamic values. Use the same `interpolate_template` mechanism. Example:

```ruby
class SearchAgent < ApplicationAgent
  user "Search for: {query}"
  assistant "Results for {query}:"  # Prefill includes the query
end
```

### 5.2 Interaction Between Class-Level and Method Override

If both are defined, method override wins (standard Ruby):

```ruby
class MyAgent < ApplicationAgent
  system "Class-level system prompt"

  def system_prompt
    "Method override wins"  # ← This is what gets used
  end
end
```

This works because `system_prompt` is a regular instance method. When a subclass defines `def system_prompt`, it overrides the base implementation that reads from `self.class.system_config`.

### 5.3 Assistant Prefill vs Conversation History

Assistant prefill and conversation history both use the `assistant` role but serve different purposes:

- **Prefill** (this feature): A single string appended as the last message to prime the response
- **Conversation history**: Multiple user/assistant pairs for multi-turn context

These are separate features. Conversation history is handled by `ConversationContext`. The `assistant` DSL is only for prefill.

### 5.4 Empty String vs Nil

- `assistant ""` → treated as no prefill (same as not calling `assistant` at all)
- `assistant nil` → no-op
- Only non-empty strings are sent as prefill

### 5.5 System Prompt with Placeholders

Currently `system` does NOT call `auto_register_params_from_template`. Should it?

**Decision: Yes.** If someone writes `system "You are helping {user_name}"`, the `{user_name}` should be auto-registered. Change `system` to also call `auto_register_params_from_template`.

---

## 6. Internal Storage Rename

To keep internal naming consistent with the new DSL:

| Old | New | Notes |
|---|---|---|
| `@prompt_template` | `@user_template` | Rename |
| `@prompt_block` | *(removed in v3.0)* | Deprecated |
| `@system_template` | `@system_template` | No change |
| `@system_block` | *(removed in v3.0)* | Deprecated |
| *(new)* | `@assistant_template` | New |

**Transition:** During Phase 1, `user_config` checks both `@user_template` and `@prompt_template` (fallback):

```ruby
def user_config
  @user_template || @prompt_template || @prompt_block || inherited_or_default(:user_config, nil)
end
```

This ensures existing agents that use `prompt "..."` continue to work even if internal storage changes.

---

## 7. Test Plan

### 7.1 New Specs

```ruby
# spec/dsl/base_spec.rb

describe "user DSL" do
  it "sets user template with string" do
    agent_class = Class.new(ApplicationAgent) { user "Hello {name}" }
    expect(agent_class.user_config).to eq("Hello {name}")
  end

  it "auto-registers placeholders as required params" do
    agent_class = Class.new(ApplicationAgent) { user "Search {query} in {category}" }
    expect(agent_class.params.keys).to include(:query, :category)
  end

  it "inherits from parent class" do
    parent = Class.new(ApplicationAgent) { user "Parent prompt" }
    child = Class.new(parent)
    expect(child.user_config).to eq("Parent prompt")
  end

  it "overrides parent" do
    parent = Class.new(ApplicationAgent) { user "Parent" }
    child = Class.new(parent) { user "Child" }
    expect(child.user_config).to eq("Child")
  end
end

describe "assistant DSL" do
  it "sets assistant template" do
    agent_class = Class.new(ApplicationAgent) { assistant '{"result":' }
    expect(agent_class.assistant_config).to eq('{"result":')
  end

  it "returns nil when not set" do
    agent_class = Class.new(ApplicationAgent)
    expect(agent_class.assistant_config).to be_nil
  end

  it "supports placeholders" do
    agent_class = Class.new(ApplicationAgent) { assistant "Results for {query}:" }
    expect(agent_class.params.keys).to include(:query)
  end
end

describe "prompt alias" do
  it "works as alias for user" do
    agent_class = Class.new(ApplicationAgent) { prompt "Hello {name}" }
    expect(agent_class.user_config).to eq("Hello {name}")
  end
end

describe "resolution order" do
  it "method override takes precedence over class-level DSL" do
    agent_class = Class.new(ApplicationAgent) do
      user "Class level"
      define_method(:user_prompt) { "Method level" }
    end
    result = agent_class.new.user_prompt
    expect(result).to eq("Method level")
  end
end
```

### 7.2 Specs for Instance Methods

```ruby
# spec/base_agent_spec.rb

describe "#user_prompt" do
  it "interpolates placeholders from params" do
    agent_class = Class.new(ApplicationAgent) { user "Search {query}" }
    agent = agent_class.new(query: "ruby")
    expect(agent.user_prompt).to eq("Search ruby")
  end

  it "raises NotImplementedError when not defined" do
    agent_class = Class.new(ApplicationAgent)
    expect { agent_class.new.user_prompt }.to raise_error(NotImplementedError)
  end
end

describe "#system_prompt" do
  it "returns nil when not defined" do
    agent_class = Class.new(ApplicationAgent)
    expect(agent_class.new.system_prompt).to be_nil
  end

  it "interpolates placeholders" do
    agent_class = Class.new(ApplicationAgent) do
      system "Helping {user_name}"
      param :user_name, required: true
    end
    agent = agent_class.new(user_name: "Alice")
    expect(agent.system_prompt).to eq("Helping Alice")
  end
end

describe "#assistant_prompt" do
  it "returns nil when not defined" do
    agent_class = Class.new(ApplicationAgent)
    expect(agent_class.new.assistant_prompt).to be_nil
  end

  it "returns the prefill string" do
    agent_class = Class.new(ApplicationAgent) { assistant '{"result":' }
    expect(agent_class.new.assistant_prompt).to eq('{"result":')
  end

  it "interpolates placeholders" do
    agent_class = Class.new(ApplicationAgent) { assistant "About {topic}:" }
    agent = agent_class.new(topic: "Ruby")
    expect(agent.assistant_prompt).to eq("About Ruby:")
  end
end
```

### 7.3 Specs for `.ask`

```ruby
# spec/base_agent_ask_spec.rb

describe ".ask" do
  let(:agent_class) do
    Class.new(ApplicationAgent) do
      model "gpt-4o"
      system "You are a helpful assistant."
    end
  end

  it "sends the message as user prompt" do
    expect_llm_call_with(
      messages: [{ role: "user", content: "What is Ruby?" }]
    )
    agent_class.ask("What is Ruby?")
  end

  it "returns a Result object" do
    result = agent_class.ask("What is Ruby?")
    expect(result).to be_a(RubyLLM::Agents::Result)
    expect(result.content).to be_present
  end

  it "supports streaming with a block" do
    chunks = []
    agent_class.ask("What is Ruby?") { |chunk| chunks << chunk }
    expect(chunks).not_to be_empty
  end

  it "includes assistant prefill when defined" do
    agent_with_prefill = Class.new(ApplicationAgent) do
      model "gpt-4o"
      system "Respond in JSON."
      assistant "{"
    end

    expect_llm_call_with(
      messages: [
        { role: "user", content: "List frameworks" },
        { role: "assistant", content: "{" }
      ]
    )
    agent_with_prefill.ask("List frameworks")
  end

  it "bypasses user template on template agents" do
    template_agent = Class.new(ApplicationAgent) do
      model "gpt-4o"
      system "You are a classifier."
      user "Classify: {text}"
    end

    expect_llm_call_with(
      messages: [{ role: "user", content: "Just say hello" }]
    )
    template_agent.ask("Just say hello")
  end

  it "skips param validation" do
    template_agent = Class.new(ApplicationAgent) do
      model "gpt-4o"
      user "Process {required_param}"  # required_param auto-registered
    end

    # .ask should NOT raise about missing required_param
    expect { template_agent.ask("freeform message") }.not_to raise_error
  end

  it "works with attachments via with: option" do
    result = agent_class.ask("What's in this image?", with: "test.jpg")
    expect(result).to be_a(RubyLLM::Agents::Result)
  end
end

describe ".ask with method override" do
  it "method override takes precedence over ask message" do
    agent_class = Class.new(ApplicationAgent) do
      model "gpt-4o"
      define_method(:user_prompt) { "Always this" }
    end

    expect_llm_call_with(
      messages: [{ role: "user", content: "Always this" }]
    )
    agent_class.ask("This is ignored")
  end
end
```

### 7.4 Integration Tests

```ruby
# spec/integration/three_roles_spec.rb

describe "three-role agent" do
  it "sends all three roles to the LLM via .call" do
    agent_class = Class.new(ApplicationAgent) do
      model "gpt-4o"
      system "You are a classifier."
      user "Classify: {text}"
      assistant '{"category":'
    end

    # Mock LLM call and verify message structure
    expect_llm_call_with(
      system: "You are a classifier.",
      messages: [
        { role: "user", content: "Classify: test email" },
        { role: "assistant", content: '{"category":' }
      ]
    )

    agent_class.call(text: "test email")
  end

  it "sends all three roles to the LLM via .ask" do
    agent_class = Class.new(ApplicationAgent) do
      model "gpt-4o"
      system "You are a helpful assistant."
      assistant "Based on my knowledge, "
    end

    expect_llm_call_with(
      system: "You are a helpful assistant.",
      messages: [
        { role: "user", content: "What is Ruby?" },
        { role: "assistant", content: "Based on my knowledge, " }
      ]
    )

    agent_class.ask("What is Ruby?")
  end
end
```

---

## 8. Documentation Updates

All wiki files need to be updated to reflect the new DSL. Key changes:

### 8.1 Files to Update

| File | Changes |
|---|---|
| `wiki/Agent-DSL.md` | Primary reference — add `user`, `assistant`, update all examples |
| `wiki/API-Reference.md` | Add `user`, `assistant`, `assistant_prompt` to method reference |
| `wiki/Getting-Started.md` | Update quick start example with `user` instead of `prompt` |
| `wiki/First-Agent.md` | Update tutorial examples |
| `wiki/Prompts-and-Schemas.md` | Major rewrite — three roles, two levels |
| `wiki/Examples.md` | Update all example agents |
| `wiki/Migration.md` | Add v2.2.0 migration section |
| `wiki/Best-Practices.md` | Update prompt organization guidance |
| `wiki/Testing-Agents.md` | Update test examples |
| All other wiki files | Replace `prompt` with `user` where appropriate |
| `README.md` | Update quick start |
| `LLMS.txt` | Update DSL description |

### 8.2 Documentation Pattern

Docs should show two primary agent patterns:

**Pattern 1: Template Agent (structured input via `.call`)**

```ruby
class AgentName < ApplicationAgent
  model "model-name"

  system "System instruction."
  user "User template with {placeholder}."
  assistant '{"key":'  # Optional prefill

  returns do
    # schema
  end
end

result = AgentName.call(placeholder: "value")
```

**Pattern 2: Conversational Agent (freeform input via `.ask`)**

```ruby
class AgentName < ApplicationAgent
  model "model-name"

  system "System instruction defining persona."
  assistant "Optional prefill"  # Optional
end

result = AgentName.ask("Freeform question here")
```

**Dynamic content via method overrides (works with both patterns):**

```ruby
class AgentName < ApplicationAgent
  model "model-name"

  def system_prompt
    # Dynamic system logic
  end

  def user_prompt
    # Dynamic user logic (for template agents)
  end

  def assistant_prompt
    # Dynamic prefill logic (rare)
  end
end
```

### 8.3 Migration Guide Entry

```markdown
## Upgrading to v2.2.0

### `prompt` → `user` DSL rename

The `prompt` class-level DSL has been renamed to `user` to align with
LLM API terminology. `prompt` continues to work as an alias.

**Before:**
```ruby
class MyAgent < ApplicationAgent
  system "You are helpful."
  prompt "Process {query}"
end
```

**After:**
```ruby
class MyAgent < ApplicationAgent
  system "You are helpful."
  user "Process {query}"
end
```

### New: `assistant` prefill

You can now define an assistant prefill to steer the model's response format:

```ruby
class JsonAgent < ApplicationAgent
  system "Always respond in JSON."
  user "Extract entities from: {text}"
  assistant '{"entities":['
end
```

### New: `def assistant_prompt` method override

For dynamic prefill content:

```ruby
def assistant_prompt
  '{"user_id": "#{current_user.id}", "response":'
end
```

### New: `.ask` for conversational agents

Agents without a `user` template can now accept freeform input via `.ask`:

```ruby
class RubyExpert < ApplicationAgent
  system "You are a senior Ruby developer."
end

# Freeform question — no template needed
result = RubyExpert.ask("What is metaprogramming?")

# With streaming
RubyExpert.ask("Explain closures") { |chunk| print chunk.content }

# With attachments
RubyExpert.ask("Review this code", with: "app.rb")
```

`.ask` also works on template agents as an escape hatch to bypass the `user` template.
```

---

## 9. Implementation Order

### Phase 1 (v2.2.0) — New Features, No Breaking Changes

1. **Add `user` DSL as primary, `prompt` as alias** — rename with backward compat
2. **Add `assistant` DSL and `#assistant_prompt`** — new role support
3. **Add `.ask(message)` class method** — conversational agent API
4. **Add placeholder support to `system`** — enhancement
5. **Wire assistant prefill into LLM interaction** — provider-specific API integration
6. **Update `#user_prompt` resolution** — add `@ask_message` priority level
7. **Simplify `resolve_prompt_from_config`** — inline to `interpolate_template` (keep Proc fallback)
8. **Write specs** — all new DSL methods, `.ask`, resolution order, integration
9. **Update all documentation** — wiki, README, LLMS.txt

### Phase 2 (v2.3.0) — Deprecation Warnings

10. **`prompt` emits deprecation warning** when called with arguments
11. **Block form emits deprecation warning** — `system do`, `prompt do`
12. **Migration guide published** — clear before/after examples

### Phase 3 (v3.0.0) — Cleanup

13. **Remove block support** — `@prompt_block`, `@system_block` storage removed
14. **`prompt` decision** — remove or keep as permanent alias (TBD)
15. **Remove `resolve_prompt_from_config`** — all Proc handling removed

---

## 10. Open Questions

1. **Should `prompt` ever be fully removed, or stay as a permanent alias?**
   - Leaning toward: permanent alias (many Ruby gems keep aliases forever)

2. **OpenAI prefill behavior** — OpenAI doesn't support assistant prefill natively.
   - Option A: Silently skip for OpenAI
   - Option B: Append to system prompt as hint
   - Option C: Raise an error
   - Leaning toward: Option B (best UX)

3. **Should `system` support `{placeholder}` auto-registration?**
   - Proposed: Yes (see section 5.5)
   - Risk: System prompts with literal `{curly braces}` could be misinterpreted
   - Mitigation: Only treat `{single_word}` as placeholders (current regex: `/\{(\w+)\}/`)

4. **Block deprecation timeline** — Is v2.3.0 too soon?
   - Blocks are currently in docs. If we update docs now, users won't be writing new blocks.
   - Existing agents with blocks will continue to work until v3.0.0.

5. **Should `.ask` record executions differently?**
   - Template agents log `parameters: { text: "hello" }` — structured
   - `.ask` agents log `parameters: {}` with the message only in `user_prompt`
   - Should we log `{ _ask_message: "..." }` in parameters for dashboard visibility?
   - Leaning toward: Yes, store in parameters for searchability

6. **Should `.ask` support additional params alongside the message?**
   - Example: `RubyExpert.ask("What is Ruby?", temperature: 0.9)`
   - Currently `.call` accepts `model:` and `temperature:` overrides
   - `.ask` should forward these through
   - Leaning toward: Yes, same override support as `.call`

7. **Should there be a `.ask!` variant?**
   - `.ask!` could raise on error instead of returning a failed Result
   - Matches Ruby convention (`save` vs `save!`)
   - Leaning toward: Not now, add later if requested

---

## 11. Summary: The Complete DSL at a Glance

```ruby
# ╔══════════════════════════════════════════════════════════════╗
# ║           Template Agent (structured input)                  ║
# ╠══════════════════════════════════════════════════════════════╣
# ║                                                              ║
# ║  class Classifier < ApplicationAgent                         ║
# ║    model "claude-sonnet-4-5-20250929"                        ║
# ║    temperature 0.0                                           ║
# ║                                                              ║
# ║    system "You are a strict email classifier."               ║
# ║    user "Classify this email: {text}"                        ║
# ║    assistant '{"category":'                                  ║
# ║                                                              ║
# ║    returns do                                                ║
# ║      string :category                                        ║
# ║      number :confidence                                      ║
# ║    end                                                       ║
# ║  end                                                         ║
# ║                                                              ║
# ║  Classifier.call(text: "Meeting at 3pm")                     ║
# ║                                                              ║
# ╠══════════════════════════════════════════════════════════════╣
# ║         Conversational Agent (freeform input)                ║
# ╠══════════════════════════════════════════════════════════════╣
# ║                                                              ║
# ║  class RubyExpert < ApplicationAgent                         ║
# ║    model "claude-sonnet-4-5-20250929"                        ║
# ║                                                              ║
# ║    system "You are a senior Ruby developer."                 ║
# ║  end                                                         ║
# ║                                                              ║
# ║  RubyExpert.ask("What is metaprogramming?")                  ║
# ║                                                              ║
# ╠══════════════════════════════════════════════════════════════╣
# ║                    Dynamic Agent                             ║
# ╠══════════════════════════════════════════════════════════════╣
# ║                                                              ║
# ║  class SmartAgent < ApplicationAgent                         ║
# ║    model "claude-sonnet-4-5-20250929"                        ║
# ║                                                              ║
# ║    def system_prompt                                         ║
# ║      "You are helping #{company.name}."                      ║
# ║    end                                                       ║
# ║                                                              ║
# ║    def user_prompt                                           ║
# ║      "Context: #{fetch_context}\n\n#{params[:question]}"     ║
# ║    end                                                       ║
# ║  end                                                         ║
# ║                                                              ║
# ║  SmartAgent.call(question: "How do I reset my password?")    ║
# ║                                                              ║
# ╚══════════════════════════════════════════════════════════════╝

# The Rules:
#
# 1. Three roles: system, user, assistant
# 2. Two levels: class-level string/heredoc (static) or method override (dynamic)
# 3. Two APIs: .call (template) or .ask (conversational)
# 4. Naming: class DSL uses short names, methods use _prompt suffix
# 5. Resolution: method override > .ask message > class template > inherited > default
```
