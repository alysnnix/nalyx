{ pkgs, ... }:

{
  home.packages = with pkgs; [
    python3

    uv
    ruff
    mypy
    httpie
    bruno
    jq

    pyright
  ];

  home.sessionVariables = {
    PYTHONUNBUFFERED = "1";
    POETRY_VIRTUALENVS_IN_PROJECT = "true";
    UV_VENV_IN_PROJECT = "1";
  };
}
