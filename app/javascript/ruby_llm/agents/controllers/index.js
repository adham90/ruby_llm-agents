// Entry point for RubyLLM::Agents Stimulus controllers
// Import and register controllers with your Stimulus application

import FilterController from "./filter_controller"

export { FilterController }

export function registerControllers(application) {
  application.register("filter", FilterController)
}
