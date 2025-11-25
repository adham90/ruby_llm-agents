// Entry point for RubyLLM::Agents Stimulus controllers
// Import and register controllers with your Stimulus application

import FilterController from "./filter_controller"
import RefreshController from "./refresh_controller"

export { FilterController, RefreshController }

export function registerControllers(application) {
  application.register("filter", FilterController)
  application.register("refresh", RefreshController)
}
