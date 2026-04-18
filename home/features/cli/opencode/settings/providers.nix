# Default provider definitions for opencode.
# Provider modifiers (litellm, minimax, openrouter) are handled at the
# wrapper level via environment variables, not in the config file.
# opencode picks up ANTHROPIC_API_KEY from the environment automatically.
{
  providers = {
    anthropic = {
      env = [ "ANTHROPIC_API_KEY" ];
    };
  };

  model = "anthropic/claude-sonnet-4-20250514";
}
