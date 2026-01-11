# RubyLLM::Agents Documentation

Welcome to the official documentation for **RubyLLM::Agents**, a production-ready Rails engine for building, managing, and monitoring LLM-powered AI agents.

## Quick Navigation

### Getting Started
- **[Getting Started](Getting-Started)** - Installation and initial setup
- **[Installation](Installation)** - Detailed installation steps
- **[Configuration](Configuration)** - Configure the initializer
- **[First Agent](First-Agent)** - Build your first AI agent

### Core Concepts
- **[Agent DSL](Agent-DSL)** - Declarative agent configuration
- **[Parameters](Parameters)** - Required and optional parameters
- **[Prompts and Schemas](Prompts-and-Schemas)** - Structure inputs and outputs
- **[Conversation History](Conversation-History)** - Multi-turn conversations
- **[Result Object](Result-Object)** - Access execution metadata

### Features
- **[Tools](Tools)** - Enable agents to call external functions
- **[Streaming](Streaming)** - Real-time response streaming
- **[Attachments](Attachments)** - Vision and multimodal support
- **[Caching](Caching)** - Response caching with TTL
- **[Execution Tracking](Execution-Tracking)** - Automatic logging and analytics

### Production Features

#### Reliability
- **[Reliability Overview](Reliability)** - Build resilient agents
- **[Automatic Retries](Automatic-Retries)** - Handle transient failures
- **[Model Fallbacks](Model-Fallbacks)** - Fallback model chains
- **[Circuit Breakers](Circuit-Breakers)** - Prevent cascading failures

#### Workflow Orchestration
- **[Workflows Overview](Workflows)** - Compose agents
- **[Pipeline Workflows](Pipeline-Workflows)** - Sequential execution
- **[Parallel Workflows](Parallel-Workflows)** - Concurrent execution
- **[Router Workflows](Router-Workflows)** - Conditional dispatch

#### Governance
- **[Budget Controls](Budget-Controls)** - Spending limits
- **[Alerts](Alerts)** - Notifications and webhooks
- **[PII Redaction](PII-Redaction)** - Data protection

### Operations
- **[Dashboard](Dashboard)** - Monitoring UI guide
- **[Production Deployment](Production-Deployment)** - Best practices
- **[Background Jobs](Background-Jobs)** - Async logging
- **[Troubleshooting](Troubleshooting)** - Common issues

### Reference
- **[API Reference](API-Reference)** - Class documentation
- **[Examples](Examples)** - Real-world use cases
- **[FAQ](FAQ)** - Common questions
- **[Contributing](Contributing)** - How to contribute

---

## About RubyLLM::Agents

RubyLLM::Agents is a Rails engine that provides:

- **Clean DSL** for defining AI agents with declarative configuration
- **Automatic tracking** of every execution with costs, tokens, and timing
- **Production reliability** with retries, fallbacks, and circuit breakers
- **Budget controls** to prevent runaway costs
- **Workflow orchestration** for complex multi-agent scenarios
- **Real-time dashboard** for monitoring and debugging

## Current Version

**v0.3.5** - See [CHANGELOG](https://github.com/adham90/ruby_llm-agents/blob/main/CHANGELOG.md) for release history.

## Supported LLM Providers

Through [RubyLLM](https://github.com/crmne/ruby_llm), RubyLLM::Agents supports:

- **OpenAI** - GPT-4, GPT-4o, GPT-4o-mini, GPT-3.5
- **Anthropic** - Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Haiku
- **Google** - Gemini 2.0 Flash, Gemini 1.5 Pro
- **And more** - Any provider supported by RubyLLM

## Need Help?

- [GitHub Issues](https://github.com/adham90/ruby_llm-agents/issues) - Report bugs
- [GitHub Discussions](https://github.com/adham90/ruby_llm-agents/discussions) - Ask questions
- [RubyLLM Documentation](https://github.com/crmne/ruby_llm) - Underlying LLM library
