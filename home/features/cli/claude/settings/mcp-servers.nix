{
  # Official Cloudflare remote MCP servers.
  # Auth via OAuth on first connection (browser flow) — no secret stored here.
  # Sources:
  #   https://github.com/cloudflare/mcp-server-cloudflare (domain-specific servers)
  #   https://github.com/cloudflare/mcp (Code Mode / general API server)
  publicMcpServers = {
    cloudflare = {
      type = "http";
      url = "https://mcp.cloudflare.com/mcp";
    };
    cloudflare-docs = {
      type = "http";
      url = "https://docs.mcp.cloudflare.com/mcp";
    };
    cloudflare-bindings = {
      type = "http";
      url = "https://bindings.mcp.cloudflare.com/mcp";
    };
    cloudflare-builds = {
      type = "http";
      url = "https://builds.mcp.cloudflare.com/mcp";
    };
    cloudflare-observability = {
      type = "http";
      url = "https://observability.mcp.cloudflare.com/mcp";
    };
    cloudflare-radar = {
      type = "http";
      url = "https://radar.mcp.cloudflare.com/mcp";
    };
    cloudflare-containers = {
      type = "http";
      url = "https://containers.mcp.cloudflare.com/mcp";
    };
    cloudflare-browser = {
      type = "http";
      url = "https://browser.mcp.cloudflare.com/mcp";
    };
    cloudflare-logpush = {
      type = "http";
      url = "https://logs.mcp.cloudflare.com/mcp";
    };
    cloudflare-ai-gateway = {
      type = "http";
      url = "https://ai-gateway.mcp.cloudflare.com/mcp";
    };
    cloudflare-auditlogs = {
      type = "http";
      url = "https://auditlogs.mcp.cloudflare.com/mcp";
    };
    cloudflare-dns-analytics = {
      type = "http";
      url = "https://dns-analytics.mcp.cloudflare.com/mcp";
    };
    cloudflare-dex = {
      type = "http";
      url = "https://dex.mcp.cloudflare.com/mcp";
    };
    cloudflare-casb = {
      type = "http";
      url = "https://casb.mcp.cloudflare.com/mcp";
    };
    cloudflare-graphql = {
      type = "http";
      url = "https://graphql.mcp.cloudflare.com/mcp";
    };
  };
}
