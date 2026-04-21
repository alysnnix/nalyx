{
  providers = {
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
