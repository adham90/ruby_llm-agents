# frozen_string_literal: true

# Configure acronym for Rails inflector (used in routes)
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "LLM"
end

# Configure Zeitwerk inflection when autoloaders are available
ActiveSupport.on_load(:before_configuration) do
  Rails.autoloaders.each do |autoloader|
    autoloader.inflector.inflect("ruby_llm" => "RubyLLM")
  end
end
