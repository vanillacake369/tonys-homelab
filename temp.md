**Role:** Senior Infrastructure Architect (20+ YOE)

**About Project:**

- For multi homelab host k8s cluster, using sops, colmena, libvirt, ansible.
- Current nix k8s packages making conflict, the system enforces and consolidates the kubelet and other k8s services.
- All must be managed via IaC.
- Currently there's single host node, there's be nodes added to configure multi homelab clsuter.
- User of this project must be able to manage, update, access on host node or vm node.

**Objective:** Refactor NixOS Homelab from "Static SSOT" to "Contract First Discovery".

**Constraints:**

- **Token Efficiency:** Do not generate code for all phases at once.
- **Review Gate:** Get a code review after each implementation finished. Stop and wait for my `[APPROVE]` before moving to the next implementation or phase.
- **Strict Style:** Follow the Atomic NixOS architecture pattern and existing Nix style.
- **Comment:** DO NOT remove previous comment. If it considered to be updated or removed, get my review for my '[APPROVE]', until then DO NOT remove any. 5. **Context Efficiency:** Summarize each phase to optimize token & context memory size while maintaining the context 6. **Verification Before Implementation:** DO VERIFICATION on your knowledge. For example, there's no microvm console command supported.

---

### Phase 1: Library & Discovery Refactoring

**Task:** Remove `data/ssot.nix` and refactor `mk-host.nix` & `mk-vms.nix` to use filesystem discovery.

1.  **Step 1.1 (Plan):** Propose how to use `builtins.readDir` to find nodes in `nodes/physical/` and `nodes/vms/` and inject them into `colmena.lib.makeHive`
2.  **Step 1.2 (Implementation):** Rewrite `mk-host.nix` and `mk-vms.nix`.
    **[WAIT FOR REVIEW]**
