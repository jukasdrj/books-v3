# Git Workflows (v2.0.62)

Auto-loaded when user mentions: "commit", "git", "pull request", "pr", "attribution"

## Git Safety Protocol

**NEVER:**
- Update git config
- Run destructive commands (push --force, hard reset) unless explicitly requested
- Skip hooks (--no-verify, --no-gpg-sign) unless explicitly requested
- Use interactive commands (git -i)

## Attribution (v2.0.62)

Configured via `attribution` setting in `.claude/settings.json`:
- Commit footer: "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
- Commit trailer: "Co-Authored-By: Claude <noreply@anthropic.com>"
- PR footer: "🤖 Generated with [Claude Code](https://claude.com/claude-code)"

**Deprecated:** `includeCoAuthoredBy` setting

## Commit Workflow (Only when user explicitly asks)

1. **Parallel commands:**
   ```bash
   git status    # See untracked files
   git diff      # See changes
   git log       # See recent commits for style
   ```

2. **Draft message:** Focus on "why" not "what"

3. **Execute with HEREDOC:**
   ```bash
   git commit -m "$(cat <<'EOF'
   Message here.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

## PR Workflow

1. **Check branch state:** git status, git diff, git log [base]...HEAD
2. **Analyze ALL commits** (not just latest)
3. **Create with gh:** Use HEREDOC for body formatting

**Include in PR:** Summary bullets, test plan checklist, attribution footer