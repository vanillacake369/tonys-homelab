#!/usr/bin/env python3
import os
import subprocess
import sys


def main():
    # Get the project root directory
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Get the deployment target IP from environment, fallback to None
    deploy_target = os.environ.get("DEPLOY_TARGET", "")

    # Path to the Nix expression that generates the inventory
    nix_expr = f'(import {root_dir}/ansible/inventory.nix {{ deploy_target = "{deploy_target}"; }})'

    try:
        # Run nix eval to get the JSON representation of the inventory
        result = subprocess.run(
            ["nix", "eval", "--json", "--impure", "--expr", nix_expr],
            capture_output=True,
            text=True,
            check=True,
        )

        # Ansible expects a JSON output on stdout
        print(result.stdout)

    except subprocess.CalledProcessError as e:
        print(f"Error running nix eval: {e.stderr}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
