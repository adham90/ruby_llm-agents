# frozen_string_literal: true

# Inflection configuration for Rails autoloading
#
# Configures Rails and Zeitwerk to properly handle the "LLM" acronym
# and the "ruby_llm" directory naming convention.
#
# This ensures:
# - "LLM" is recognized as an acronym (not "Llm")
# - "ruby_llm" directory maps to "RubyLLM" module
#
# @api private

# Register "LLM" as an acronym for ActiveSupport inflector
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "LLM"
end

# Configure Zeitwerk to map directory names correctly
ActiveSupport.on_load(:before_configuration) do
  Rails.autoloaders.each do |autoloader|
    autoloader.inflector.inflect("ruby_llm" => "RubyLLM")
  end
end
