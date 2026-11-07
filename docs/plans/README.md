# Work plans

Everything in this folder but this file is gitignored, and that is the point.

A plan is a session draft: what is about to be done, written down before the
coding starts, and kept up to date as the steps are ticked off. It lives in the
repository rather than in a temporary directory so it survives a reboot as well
as a crash, and it is ignored because it is not history.

- `plan.md` is the live one. Its header carries `status: in-progress` or
  `status: complete`, which is what tells a resumed session whether there is
  work to pick up.
- `AAAA-MM-JJ-HHMM-slug.md` are finished plans, archived as they stood and
  read-only from then on.
- `sumup.md` is a finished batch waiting for a commit, in the format of prel's
  `plan-summary` skill.
