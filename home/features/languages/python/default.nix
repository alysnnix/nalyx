{
  pkgs,
  lib,
  # See home/features/cli/default.nix for why this is read from a config
  # position only, never from `imports`.
  terminalOnly ? false,
  ...
}:

{
  home.packages =
    with pkgs;
    [
      python3

      uv
      ruff
      mypy
      httpie
      jq

      pyright
    ]
    # Bruno is an Electron API client, not a python tool, so it is the one entry
    # here that puts a window on screen. Terminal-only hosts skip it; `httpie`
    # above already covers the same job from the shell.
    ++ lib.optionals (!terminalOnly) [
      bruno
    ];

  home.sessionVariables = {
    PYTHONUNBUFFERED = "1";
    POETRY_VIRTUALENVS_IN_PROJECT = "true";
    UV_VENV_IN_PROJECT = "1";
  };
}
