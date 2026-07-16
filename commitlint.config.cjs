module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "type-enum": [
      2,
      "always",
      ["feat", "fix", "refactor", "docs", "test", "chore", "build", "ci"]
    ],
    "scope-enum": [
      2,
      "always",
      [
        "ansible",
        "bookorbit",
        "ci",
        "cni",
        "deps",
        "docs",
        "flux",
        "gitops",
        "hooks",
        "just",
        "k8s",
        "nix",
        "platform",
        "policy",
        "registry",
        "secrets",
        "ssh",
        "storage",
        "topology",
        "users"
      ]
    ],
    "scope-empty": [2, "never"],
    "subject-case": [0]
  }
};
