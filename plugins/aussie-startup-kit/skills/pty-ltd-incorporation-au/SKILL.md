---
name: pty-ltd-incorporation-au
description: Set up an Australian proprietary company (Pty Ltd) from scratch so it gets an ACN and ABN. Use whenever the user wants to incorporate or register a company in Australia, get an ACN or ABN for a new company, draft a company constitution, ASIC Form 201 data sheet, consents to act as director, application for shares, share certificates or statutory registers, or plan the tasks to incorporate. It runs an onboarding questionnaire, generates placeholder-safe document drafts, saves them to Google Drive, builds a Linear project with milestones and blocking links, and posts a brief to Slack. Trigger even if the user only says "incorporate", "register a company", "ACN", "ABN" or "company constitution".
---

# Australian Pty Ltd incorporation (ACN and ABN)

Turns an incorporation request into: (1) completed document drafts, (2) a Drive folder of copies, (3) a Linear project with
every task, statuses and blocking links, and (4) a Slack brief. These are general drafts, not legal advice. Always tell the
user a lawyer or compliance team should review the constitution and packs before use.

## What Claude can and cannot do
Can: draft documents, research current fees and process, create Drive files, create and update Linear issues, post to Slack.
Cannot (the user must do these): apply for Director IDs (each director applies personally via ABRS), sign documents, log in to
ASIC or the ABR, pay fees, lodge Form 201, or apply for the ABN. Never enter credentials, payment details, TFNs or government IDs
into any site. Never put Director IDs, dates of birth, TFNs or bank details in Slack or Linear.

## Step 1: Onboarding (ask only what is missing)
Check the conversation first. Then ask the user, grouped, using tappable options where available:

1. Structure: directors (full legal names; at least one must ordinarily reside in Australia); secretary yes/no; shareholders and
   whether each holds personally, via a company (need its ACN, registered office and authorised signatory) or as nominee/trustee;
   share class, number of shares per holder, issue price per share, fully paid or not, any non-cash issue.
2. Name: proposed name and any fallback; any name reservation.
3. Addresses: registered office (physical street address, not a PO box), whether the company or someone else occupies it
   (occupier's consent needed if not the company), principal place of business.
4. Governance: pre-emption on new issues; anti-dilution protection for founders; shotgun (buy-sell) clause; whether all
   shareholders must be directors; ordinary-resolution threshold (percentage of all votes); maximum directors; any option
   over new shares for a third party (holder, number of shares, expiry, price formula).
5. Lodgement: self-lodge or registered agent/accountant; who pays the ASIC fee; contact details.
6. Personal details for the ASIC data sheet (dates and places of birth, residential addresses): only use values the user
   types in themselves. If they decline, leave clear [PLACEHOLDERS] for each person to complete privately.
7. Workspace: Drive folder to save into, Linear team, Slack channel and people to tag, preferred file format.

Flag any gaps as "open items" instead of guessing (issue price, ACNs, Director IDs, legal full names and former names).
Point out consequences the founders may not have noticed, for example: two equal holders with a threshold above 50% means both
must agree (deadlock), so the shotgun clause matters; an option for a third party must be sized (an option over half the
existing shares gives the holder one third) and its price formula defined.

## Step 2: Build the documents
Write a config JSON (schema: see `assets/example_config.json`, every missing field renders as a [PLACEHOLDER]) and run:

    python scripts/build_pack.py config.json OUTDIR [--post-registration]

This writes HTML and DOCX for the Constitution, the Incorporation Pack (registration information sheet, director consents,
share applications, occupier's consent) and optionally the Post-Registration Pack (first directors' resolution, public officer
forms, share certificates, registers). Run it first with `assets/example_config.json` if the user just wants blank templates
(`assets/placeholder_output/` already has them). Document properties (title, author, dates, app stats, custom properties) are stripped automatically; confirm the
files open and render. Render to PDF and check pages before saving. Keep the user's real config out
of this skill folder.

The post-registration pack needs the ACN and registration date, so only finalise it after ASIC registers the company.
Clause meanings and sizing notes are in `references/clause_library.md`.

## Step 3: Save to Google Drive
Save copies, never overwrite the user's templates. Upload the generated HTML with `create_file` using
`contentMimeType: text/html` and `textContent`, which converts it into an editable Google Doc (export to Word or PDF from Drive).
Put `border="1"` on tables first. Say that formatting is regenerated, not edited in place.

## Step 4: Linear
Follow `references/linear_blueprint.md`. Check existing teams, projects and issues first. Mark finished work Done, partly
finished work In Progress with a comment stating exactly what is missing, and leave the rest Backlog. Add new issues for
anything discovered during onboarding (for example a shareholders' agreement or option deed, company shareholder details,
issue price decision).

## Step 5: Slack
Use `references/slack_brief_template.md`. Only post when the user has asked for it, to the channel and people they named.

## Step 6: Report back
Summarise what is done, what only the user can do, and the open items. Mention fees and process details came from sources
that must be confirmed on the ASIC and ABR sites at lodgement time (ASIC fees change each 1 July). Do not claim the company
is registered or that an ACN or ABN exists until the user confirms it.
