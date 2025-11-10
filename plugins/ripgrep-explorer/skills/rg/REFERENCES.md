# Ripgrep References

## Official
- Repository (BurntSushi/ripgrep): https://github.com/BurntSushi/ripgrep
- ripgrep user guide (GUIDE.md): https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md
- Manual (rg.1): https://manpages.debian.org/rg or https://man7.org/linux/man-pages/man1/rg.1.html

## Key Topics for This Skill
- `--json` output format (JSON Lines events: begin/match/context/summary)
- `--no-config` to ignore RIPGREP_CONFIG_PATH for reproducibility
- Smart case `-S`, literal mode `-F`, PCRE2 `-P` (if compiled with PCRE2)
- Globbing with `-g` / `--iglob`; language filters with `-t`
- Common excludes: `.git`, `node_modules`, `.venv`, build outputs
- JSON-incompatible flags to avoid with `--json`: `--files`, `-l`, `--count*`

Refer to the manual and GUIDE for the precise semantics and edge cases.

