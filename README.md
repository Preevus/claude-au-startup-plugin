# claude-au-startup-plugin

A [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugins) for founders starting a business in Australia. It contains one plugin, `aussie-startup-kit`, which bundles Claude skills for the early setup work. It holds one skill today, and more will be added over time.

> **Not legal advice.** The output is general draft documents for Australian proprietary companies. It is not legal advice, and every draft needs review by a qualified Australian lawyer before you sign it, lodge it or rely on it.

## Included skills

<!-- skills-table:start -->
| Skill name | What it does |
| --- | --- |
| `pty-ltd-incorporation-au` | Guides a founder through registering an Australian Pty Ltd to obtain an ACN and ABN: onboarding questions, a document generator (constitution, incorporation pack, post-registration pack) with placeholder-only templates, and Google Drive, Linear and Slack workflows. General drafts only, not legal advice. |
<!-- skills-table:end -->

## Install

In a Claude Code session, add the marketplace, then install the plugin:

```text
/plugin marketplace add rorymullan99git/claude-au-startup-plugin
/plugin install aussie-startup-kit@claude-au-startup-marketplace
```

Or run the same steps from your shell:

```bash
claude plugin marketplace add rorymullan99git/claude-au-startup-plugin
```

```bash
claude plugin install aussie-startup-kit@claude-au-startup-marketplace
```

Start a new session, or run `/reload-plugins`, to load the skills.

To get new skills later, refresh the marketplace and update the plugin:

```bash
claude plugin marketplace update claude-au-startup-marketplace
```

```bash
claude plugin update aussie-startup-kit@claude-au-startup-marketplace
```

## Use the skill

Ask Claude in plain language. It loads the skill when your request matches, for example:

> I'm starting a software company in Australia with one co-founder. Help me register a Pty Ltd so we get an ACN and an ABN, then draft the constitution and the incorporation pack.

You can also start the skill directly:

```text
/aussie-startup-kit:pty-ltd-incorporation-au
```

The skill works in three stages:

1. **Onboarding questions** about the company and the people involved, such as the proposed name, directors, shareholders and share structure.
2. **Draft documents** generated from placeholder-only templates as Word and HTML files: a constitution, an incorporation pack and a post-registration pack. The generator needs Python 3 and [pandoc](https://pandoc.org); python-docx is optional and adds page breaks.
3. **Optional workflows** that file the drafts in Google Drive, track the steps in Linear and post updates to Slack. These need the matching connectors or MCP servers in your Claude Code setup.

Your answers stay in your own session and in the files you generate. If you keep your details in a config file, do not commit it: the `.gitignore` here blocks real config files, `out/`, PDFs and generated HTML for that reason.

The templates, and every document the generator writes, carry no metadata: no author, dates, revision IDs, thumbnails or real file timestamps. Word adds your name and dates again when you save an edited copy, so run Inspect Document (File, Info, Check for Issues) before you share one.

## Repository layout

```text
.claude-plugin/marketplace.json                        marketplace catalog that lists the plugin
plugins/aussie-startup-kit/.claude-plugin/plugin.json  plugin manifest: name, version, description
plugins/aussie-startup-kit/skills/<skill-name>/        one folder per skill, holding SKILL.md
scripts/check_repo.sh                                  checks to run before every commit and push
scripts/add_skill.sh                                   adds a skill and updates every listing
scripts/strip_office_metadata.py                       removes all metadata from Office files
.github/workflows/check.yml                            runs the checks on GitHub
```

Each skill's folder name equals the `name` in its `SKILL.md` frontmatter, because plugin skills are discovered by folder.

## Add a skill

```bash
scripts/add_skill.sh path/to/new_skill.skill "One line on what the skill does"
```

The script unpacks the `.skill` file (a zip) into a new temporary folder, flattens a single top folder, strips all metadata from its Office files, names the skill folder after the `name` in its frontmatter, adds a row to the table above, updates the skill list in `plugin.json` and `marketplace.json`, bumps the plugin's minor version and runs the checks. It never commits or pushes, so review `git status` and `git diff` first.

To clean an Office file you changed by hand, run `python3 scripts/strip_office_metadata.py path/to/file.docx` (a folder works too).

## Checks

`scripts/check_repo.sh` must report zero findings before any commit or push, and the GitHub workflow runs it on every push to `main` and on every pull request. It checks:

- the layout, both manifests and every skill's frontmatter
- that the README table, `plugin.json` and `marketplace.json` list exactly the skills that exist
- `claude plugin validate --strict` for the marketplace, the plugin and its skills
- that no real config files, env files, `out/`, PDFs, generated HTML, archives or `.DS_Store` files would be committed
- every file that would be committed, including the text inside Word documents, the file names and the git history, for personal information and secrets: emails, phone numbers, ABN, ACN and TFN numbers, Director IDs, dates of birth, street addresses, names in form fields, API keys, workspace links and local file paths
- that Office files carry no metadata at all: no document properties, revision IDs, thumbnails, comment authors, real zip timestamps or zip extra fields
- that no file contains an em dash, and that `LICENSE` names its copyright holder
- that the shell and Python scripts parse

To also search for words that must never appear, such as your own name or street, list them one per line in `.check-repo-private-terms`. Git ignores that file, so the terms are never published.

## Versioning

`plugin.json` sets `version`, and installed copies update only when it changes. Bump it with every release; `scripts/add_skill.sh` bumps the minor version for you.

## License

MIT. See [LICENSE](LICENSE).
