# Dashboard

A real-time Turbo-powered monitoring UI for your LLM agents.

## Mounting the Dashboard

The install generator automatically adds the route, but you can customize:

```ruby
# config/routes.rb
mount RubyLLM::Agents::Engine => "/agents"

# Or custom path
mount RubyLLM::Agents::Engine => "/admin/llm-agents", as: "llm_dashboard"
```

## Dashboard Pages

### Overview (`/agents`)

- Today's execution count
- Success rate percentage
- Total cost today
- 7-day performance chart
- Top agents by usage
- Recent executions

### Executions List (`/agents/executions`)

- All execution history
- Filter by:
  - Agent type
  - Status (success/error/timeout)
  - Date range
  - Model
- Sort by:
  - Timestamp
  - Cost
  - Duration
- Search by parameters

### Execution Detail (`/agents/executions/:id`)

- System prompt
- User prompt
- LLM response
- Token breakdown (input/output/cached)
- Cost calculation
- Duration and timing
- Model info
- Error details (if failed)
- Retry/fallback attempts
- Custom metadata

## Authentication

### No Authentication (Development)

```ruby
config.dashboard_auth = ->(_) { true }
```

### Current User Admin Check

```ruby
config.dashboard_auth = ->(controller) {
  controller.current_user&.admin?
}
```

### Devise Integration

```ruby
config.dashboard_auth = ->(controller) {
  controller.authenticate_user!
  controller.current_user.admin?
}
```

### HTTP Basic Auth

```ruby
config.dashboard_auth = ->(controller) {
  controller.authenticate_or_request_with_http_basic("LLM Dashboard") do |user, pass|
    ActiveSupport::SecurityUtils.secure_compare(user, ENV['DASHBOARD_USER']) &&
    ActiveSupport::SecurityUtils.secure_compare(pass, ENV['DASHBOARD_PASS'])
  end
}
```

### IP Whitelist

```ruby
config.dashboard_auth = ->(controller) {
  allowed_ips = %w[127.0.0.1 ::1 10.0.0.0/8]

  allowed_ips.any? do |allowed|
    if allowed.include?('/')
      IPAddr.new(allowed).include?(controller.request.remote_ip)
    else
      allowed == controller.request.remote_ip
    end
  end
}
```

### Multiple Conditions

```ruby
config.dashboard_auth = ->(controller) {
  # Must be logged in
  return false unless controller.current_user

  # Must be admin OR from allowed IP
  controller.current_user.admin? ||
    %w[10.0.0.1 10.0.0.2].include?(controller.request.remote_ip)
}
```

## Parent Controller

Inherit from a custom controller:

```ruby
config.dashboard_parent_controller = "Admin::BaseController"
```

This is useful when your auth is handled by a base controller:

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  before_action :require_admin!
end

# config/initializers/ruby_llm_agents.rb
config.dashboard_parent_controller = "Admin::BaseController"
config.dashboard_auth = ->(_) { true }  # Auth handled by parent
```

## Pagination

Configure items per page:

```ruby
config.dashboard_per_page = 50  # Default: 25
config.dashboard_recent_executions = 20  # On overview page
```

## Real-Time Updates

The dashboard uses Turbo for live updates:

- New executions appear automatically
- Status changes update in real-time
- Charts refresh periodically

No additional configuration needed - it works out of the box with ActionCable.

## Charts

The dashboard uses Chartkick for visualizations:

- **Cost Over Time** - Daily spending trend
- **Executions by Agent** - Pie chart of agent usage
- **Success Rate** - Historical success percentage
- **Token Usage** - Input vs output tokens
- **Response Time** - Duration distribution

## Customization

### Custom Styles

Add custom CSS to your application:

```css
/* app/assets/stylesheets/llm_dashboard.css */
.llm-agents-dashboard {
  /* Your custom styles */
}

.llm-agents-dashboard .header {
  background-color: #your-brand-color;
}
```

### Extend Controllers

Create your own controller inheriting from the engine:

```ruby
# app/controllers/my_agents_controller.rb
class MyAgentsController < RubyLLM::Agents::ExecutionsController
  def index
    super
    # Add custom logic
  end
end
```

## API Access

Access dashboard data programmatically:

```ruby
# Today's summary
RubyLLM::Agents::Execution.daily_report

# Filter executions
RubyLLM::Agents::Execution
  .by_agent("SearchAgent")
  .today
  .successful

# Cost breakdown
RubyLLM::Agents::Execution.cost_by_agent(period: :this_week)
```

## Performance

For large execution volumes:

### Database Indexes

Ensure proper indexes exist:

```ruby
# These are created by the install generator
add_index :ruby_llm_agents_executions, :agent_type
add_index :ruby_llm_agents_executions, :status
add_index :ruby_llm_agents_executions, :created_at
add_index :ruby_llm_agents_executions, [:agent_type, :created_at]
```

### Query Optimization

The dashboard uses efficient queries:

```ruby
# Time-bounded queries
.where("created_at >= ?", 7.days.ago)

# Aggregations
.group(:agent_type).sum(:total_cost)
```

### Caching

Dashboard views are Turbo-optimized but you can add caching:

```ruby
# In production.rb
config.action_controller.perform_caching = true
```

## Troubleshooting

### Dashboard Not Loading

1. Check route is mounted:
   ```ruby
   rake routes | grep agents
   ```

2. Check authentication:
   ```ruby
   config.dashboard_auth = ->(_) { true }  # Temporarily
   ```

3. Check for JavaScript errors in browser console

### Charts Not Showing

1. Ensure Chartkick is loaded:
   ```erb
   <%= javascript_include_tag "chartkick" %>
   ```

2. Check for data:
   ```ruby
   RubyLLM::Agents::Execution.count
   ```

### Slow Performance

1. Check execution count:
   ```ruby
   RubyLLM::Agents::Execution.count
   # If > 100k, consider data cleanup
   ```

2. Add indexes if missing:
   ```bash
   rails generate ruby_llm_agents:upgrade
   rails db:migrate
   ```

3. Enable query logging to identify slow queries

## Related Pages

- [Execution Tracking](Execution-Tracking) - What gets logged
- [Configuration](Configuration) - Full settings guide
- [Production Deployment](Production-Deployment) - Production setup
