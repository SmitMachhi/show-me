# How code in show-me is styled and refactored.
# Adapted from Joseph Suarez's hand-written PufferLib guide:
# https://github.com/PufferAI/PufferLib/blob/5.0/SKILL_ISSUES.md
# Read it before you write or refactor anything here, human or model.

# Objective
Reduce source code length without golfing while preserving behavior and performance. Speed, memory and token usage are measured, so preserve the numbers too. AGENTS.md sets the size limits: files under 200 lines, functions under 50. Where this guide and AGENTS.md disagree, AGENTS.md wins.

# The Refactoring Algorithm
1. Inline every function that is only used once and tighten former call sites, unless the caller would pass 50 lines
2. Eliminate defensive checks on internal state. Replace complex error handling with plain asserts.
3. Reduce deeply nested code by merging and inverting conditionals
4. Co-optimize multi-consumer functions with their callers
5. Apply syntax and style guide as a final pass

# What step 2 does not touch
show-me runs on other people's machines and serves files to a browser. These checks are the product, not defense. Never remove them:
- Host header check and Origin check on every request that writes
- File paths confined to the artifact folder after resolving symlinks
- Loopback-only bind
- Size limits on anything read from the network
- Input from the CLI user: a bad argument gets one clear message that says what to do, not an assert

Everything else that cannot happen gets an assert, not a fallback.

# Syntax & Style (General)
- One idea, one file. Split only when the file would pass 200 lines, and split by idea, not by size.
- No implicit state machines. If code has states, name them in one type and switch on it in one place.
- Soft 80-col / hard 100-col limit
- Do not one-line loops or conditionals
- 4-space indents. Do NOT match opening parens
- Next line continuations indent 4 extra spaces instead of matching parens
- Apply semantic vertical spacing between blocks of code sparingly
- Tests are important but their length and code quality is not counted
- Do not add source complexity or shims for ease of testing
- Do not block off comments with --- or ### etc.
- No dependency for what the standard library or a few lines can do

# Engine (language section)
Pending: the engine language is not chosen yet. Rust, Go, Zig and C are being measured. This section gets that language's rules once the numbers are in. Until then these hold in any of them:
- Preallocate at start by default and let the OS free it on exit
- Runtime allocations should be rare and freed in the same scope
- Avoid forward declarations. Define functions as close as possible to first use.
- Avoid keyword bloat: no redundant qualifiers, wrappers or setters
- Platform differences (Windows, Linux, macOS) live in one place, not scattered through the code

# Browser code (ui.html, inject.js)
- Plain JS, HTML and CSS. No framework, no build step, no CDN.
- Native elements first: dialog, details, form controls
- One script, read top to bottom. No modules, no classes for one instance.
- The artifact page is the author's. Add one script tag and nothing else.

# Skill text (SKILL.md, rules, playbooks)
- Every line the agent reads costs tokens on every run. Cut any line that does not change what the agent does.
- If the engine can enforce it in code, enforce it there and delete the sentence.
