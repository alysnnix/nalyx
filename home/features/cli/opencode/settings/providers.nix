# Provider definitions for opencode.
# Provider modifiers (litellm, minimax, openrouter, cc) are handled at the
# wrapper level via environment variables, not in the config file.
#
# LiteLLM models (via --litellm flag):
#   claude-opus, claude-opus-4-6, claude-opus-4-7
#   claude-sonnet, claude-sonnet-4-6
#   claude-haiku-4-5
#   minimax-m2.5, minimax-m2.7
#   zhipu-glm5, zhipu-glm5-turbo, zhipu-glm5.1
#
# Claude Code (via --cc flag):
#   Uses OAuth token from Claude Code subscription.
#   Supports all models available on your plan.
{
  providers = {
    anthropic = {
      env = [ "ANTHROPIC_API_KEY" ];
    };
  };

  model = "anthropic/claude-sonnet-4-20250514";
}
