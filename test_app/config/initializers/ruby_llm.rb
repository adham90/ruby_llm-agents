 RubyLLM.configure do |config|

   config.openai_api_key = ENV["OPENAI_KEY"]

    # or for Claude:
    # config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  end
