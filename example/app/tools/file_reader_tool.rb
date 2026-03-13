# frozen_string_literal: true

# Sample tool using RubyLLM::Agents::Tool base class
#
# Demonstrates:
# - Inheriting from RubyLLM::Agents::Tool (instead of RubyLLM::Tool)
# - Using `context` to access agent params
# - Per-tool timeout
# - Automatic error handling (errors become strings for the LLM)
#
# @example Usage via CodingAgent
#   CodingAgent.call(query: "Read config.yml", workspace_path: "/app")
#   # → FileReaderTool receives context.workspace_path == "/app"
#
class FileReaderTool < RubyLLM::Agents::Tool
  description "Read the contents of a file. Returns the file content as text."
  timeout 10

  param :path, desc: "Relative path to the file to read", required: true

  def execute(path:)
    workspace = context&.workspace_path || "."
    full_path = File.join(workspace, path)

    unless File.exist?(full_path)
      return "File not found: #{path}"
    end

    content = File.read(full_path)
    "Contents of #{path}:\n#{content}"
  end
end
