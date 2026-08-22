{
  pkgs,
  vars,
  lib,
  isWsl,
  ...
}:

let
  myScripts =
    builtins.map (name: pkgs.writeShellScriptBin name (builtins.readFile ./scripts/${name}.sh))
      [
        "update-sys"
        "approve"
        "reviews"
      ];
in
{
  home = {
    packages = myScripts ++ [ pkgs.sshfs ];
    sessionPath = [ "$HOME/.local/bin" ];
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Accept autosuggestions with Ctrl+Space
      bindkey '^ ' autosuggest-accept

      # Prefix prompt with hostname on remote machines
      [[ "$(hostname)" == "homelab" ]] && PROMPT="%F{cyan}[homelab]%f $PROMPT"
      [[ "$(hostname)" == "laptop" ]] && PROMPT="%F{cyan}[laptop]%f $PROMPT"

      # Create/enter a git worktree for <branch>, always anchored at the
      # main worktree root so worktrees never nest inside other worktrees.
      wt() {
        local branch="$1"
        if [[ -z "$branch" ]]; then
          echo "usage: wt <branch>" >&2
          return 1
        fi

        local common_dir main_root wt_path
        common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
          echo "wt: not inside a git repository" >&2
          return 1
        }
        main_root="$(cd "$common_dir/.." && pwd)"
        wt_path="$main_root/.worktrees/$branch"

        if [[ -d "$wt_path" ]]; then
          cd "$wt_path"
          return 0
        fi

        local existing
        existing="$(git -C "$main_root" worktree list --porcelain | awk -v b="refs/heads/$branch" '
          /^worktree / { path = substr($0, 10) }
          /^branch /   { if (substr($0, 8) == b) print path }
        ')"
        if [[ -n "$existing" ]]; then
          echo "wt: branch '$branch' is already checked out at $existing" >&2
          return 1
        fi

        if ! grep -qx '.worktrees/' "$main_root/.gitignore" 2>/dev/null; then
          {
            echo "# worktrees created by the wt() helper, not part of the repo"
            echo ".worktrees/"
          } >> "$main_root/.gitignore"
          echo "wt: added .worktrees/ to .gitignore"
        fi

        if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
          git -C "$main_root" worktree add "$wt_path" "$branch" || return 1
        else
          git -C "$main_root" worktree add "$wt_path" -b "$branch" || return 1
        fi

        local f
        for f in .env .env.local; do
          if [[ -f "$main_root/$f" ]]; then
            cp "$main_root/$f" "$wt_path/$f"
            echo "wt: copied $f"
          fi
        done

        cd "$wt_path"
      }

      # List all worktrees of the current repo.
      wtls() {
        git worktree list
      }

      # Remove the worktree for <branch> and prune stale metadata.
      wtrm() {
        local branch="$1"
        if [[ -z "$branch" ]]; then
          echo "usage: wtrm <branch>" >&2
          return 1
        fi

        local common_dir main_root wt_path
        common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
          echo "wtrm: not inside a git repository" >&2
          return 1
        }
        main_root="$(cd "$common_dir/.." && pwd)"
        wt_path="$main_root/.worktrees/$branch"

        if [[ "$wt_path" == "$main_root" ]]; then
          echo "wtrm: refusing to remove the main worktree" >&2
          return 1
        fi
        if [[ "$PWD" == "$wt_path" || "$PWD" == "$wt_path"/* ]]; then
          echo "wtrm: cd out of $wt_path before removing it" >&2
          return 1
        fi

        git -C "$main_root" worktree remove "$wt_path" || return 1
        git -C "$main_root" worktree prune
      }
    '';

    shellAliases = {
      l = "ls -la";
      switch = "update-sys";
      pull = "git stash && git pull && git stash pop";
      nalyx = "cd ~/nalyx";
      wrk = "cd ~/wrk";
      mount-homelab = "mkdir -p ~/mnt/homelab && sshfs ${vars.user.name}@${vars.homelab.address}:/data/sync ~/mnt/homelab -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3";
      umount-homelab = "fusermount -u ~/mnt/homelab";
    }
    // lib.optionalAttrs isWsl {
      # omp-collab (WSL only): start / stop serving /collab on the tailnet.
      omp-collab-up = "sudo systemctl start omp-collab-relay nginx omp-collab-tailscale-serve";
      omp-collab-down = "sudo systemctl stop omp-collab-tailscale-serve omp-collab-relay";
    };

    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "docker"
      ];
    };
  };
}
