# frozen_string_literal: true

# SupportRouter::Eval - Quality checks for the support message router
#
# Verifies that the router correctly classifies common support messages
# into the right categories. Run with:
#
#   RUN_EVAL=1 bundle exec rspec spec/evals/support_router_eval_spec.rb
#
# Or programmatically:
#
#   run = Evals::SupportRouterEval.run!
#   puts run.summary
#
module Evals
  class SupportRouterEval < RubyLLM::Agents::Eval::EvalSuite
    agent Routers::SupportRouter

    # --- Billing ---
    test_case "billing: double charge",
      input: {message: "I was charged twice for my subscription"},
      expected: "billing"

    test_case "billing: refund request",
      input: {message: "I need a refund for last month's payment"},
      expected: "billing"

    test_case "billing: invoice",
      input: {message: "Can you send me an invoice for tax purposes?"},
      expected: "billing"

    # --- Technical ---
    test_case "technical: 500 error",
      input: {message: "I keep getting a 500 error when I try to save"},
      expected: "technical"

    test_case "technical: app crash",
      input: {message: "The mobile app crashes every time I open settings"},
      expected: "technical"

    test_case "technical: slow performance",
      input: {message: "Page load times have been terrible since the last update"},
      expected: "technical"

    # --- Sales ---
    test_case "sales: pricing",
      input: {message: "What's the price difference between Pro and Enterprise?"},
      expected: "sales"

    test_case "sales: upgrade",
      input: {message: "I'd like to upgrade my team to the business plan"},
      expected: "sales"

    # --- Account ---
    test_case "account: password reset",
      input: {message: "I forgot my password and need to reset it"},
      expected: "account"

    test_case "account: profile update",
      input: {message: "How do I change my email address on my profile?"},
      expected: "account"

    # --- General (default route) ---
    test_case "general: greeting",
      input: {message: "Hello, I have a question"},
      expected: "general"

    test_case "general: thanks",
      input: {message: "Thanks for your help!"},
      expected: "general"
  end
end
