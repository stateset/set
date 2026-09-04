# Repository Enforcement

The default branch is `master`. The security and devnet workflows listen to both `master` and
`main` so a future rename cannot silently disable push validation.

Configure these GitHub branch-protection settings on `master` after the first green run establishes
the check names:

- require a pull request and at least one approval;
- dismiss stale approvals when new commits are pushed;
- require conversation resolution;
- require the Devnet Smoke and every Security Analysis job;
- require branches to be current before merging;
- block force pushes and branch deletion;
- include administrators, with a documented emergency bypass procedure;
- allow no bypass actors unless they are named in the incident-response runbook.

These settings are intentionally not changed by repository scripts. Enabling or changing merge
policy is an administrative action and requires an explicit maintainer decision.
