# shellcheck shell=sh
# `orchestra init` — scaffold orchestra into any project directory:
#   1. detect the stack (package.json, pyproject.toml, go.mod, ...)
#   2. copy templates/docs/ -> ./docs/
#   3. copy templates/orchestra.config.json, pre-filled with the guessed stack
#   4. copy commands/ -> ./.claude/commands/
#   5. create .bus/ and add .bus/ and .worktrees/ to .gitignore
#   6. print the next step ("orchestra design")

# init_project — run the steps above in the current directory.
init_project() { not_implemented init; }

# init_detect_stack — print a JSON object {language, build, test, typecheck}.
init_detect_stack() { not_implemented init_detect_stack; }
