# Provider definitions for opencode.
#
# LiteLLM is configured as a custom provider with all available models.
# The API key placeholder is replaced at activation time from sops.
#
# Claude Code (--cc flag) writes the OAuth token to opencode's auth.json
# to enable the built-in anthropic provider.
{
  providers = {
    anthropic = {
      env = [ "ANTHROPIC_API_KEY" ];
    };
    litellm = {
      npm = "@ai-sdk/openai-compatible";
      name = "LiteLLM";
      options = {
        baseURL = "https://hub.seazone.dev/v1";
        apiKey = "__LITELLM_API_KEY_PLACEHOLDER__";
      };
      models = {
        "minimax-m2.7" = {
          name = "MiniMax M2.7";
          limit = {
            context = 1000000;
            output = 65536;
          };
        };
        "minimax-m2.5" = {
          name = "MiniMax M2.5";
          limit = {
            context = 1000000;
            output = 65536;
          };
        };
        zhipu-glm5 = {
          name = "GLM-5";
          limit = {
            context = 128000;
            output = 16384;
          };
        };
        "zhipu-glm5-turbo" = {
          name = "GLM-5 Turbo";
          limit = {
            context = 128000;
            output = 16384;
          };
        };
        "zhipu-glm5.1" = {
          name = "GLM-5.1";
          limit = {
            context = 128000;
            output = 16384;
          };
        };
      };
    };
    claude-code = {
      npm = "@ai-sdk/anthropic";
      name = "Claude Code";
      options = {
        apiKey = "bearer-auth-used";
        headers = {
          Authorization = "Bearer __CC_OAUTH_TOKEN_PLACEHOLDER__";
        };
      };
      models = {
        claude-opus-4-7 = {
          name = "Claude Opus 4.7";
          limit = {
            context = 200000;
            output = 65536;
          };
        };
        claude-opus-4-6 = {
          name = "Claude Opus 4.6";
          limit = {
            context = 200000;
            output = 65536;
          };
        };
        claude-sonnet-4-6 = {
          name = "Claude Sonnet 4.6";
          limit = {
            context = 200000;
            output = 65536;
          };
        };
        claude-haiku-4-5 = {
          name = "Claude Haiku 4.5";
          limit = {
            context = 200000;
            output = 65536;
          };
        };
      };
    };
  };

  model = "claude-code/claude-sonnet-4-6";
}
