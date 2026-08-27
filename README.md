# test-workflows

A scratch repository. It exists to answer questions about GitHub that no local
test can answer, before the real change goes to `ml-explore/mlx-swift-lm`.

It builds nothing. The CI here is a stand-in whose jobs pass or fail on command,
so a full cycle takes under a minute instead of forty.

Throw this repository away when the real change has merged.

## What is being tested

`ml-explore/mlx-swift-lm` is gaining a workflow that writes its own state labels
on a pull request. The rules live in one tested file, `.github/scripts/ci-state.js`.
Two workflows call it: `ci-state.yml` labels a pull request while its CI run is
in progress and again when the run finishes, and `reset-ci-state.yml` puts a
pull request back in the queue when a new commit arrives.

Those three files are copied here byte for byte, except that the repository
guard in the two workflows names this repository instead. `verify.sh` checks
that substitution, because a guard naming the wrong repository makes every job
skip in silence and the test would prove nothing.

## Set up, in this order

1. Create a **public** repository `thechriswebb/test-workflows`.

   Public matters. The whole premise is that GitHub gives a read-only token to
   a workflow triggered by a fork's pull request in a public repository. On a
   private repository that policy is configurable, so a private scratch
   repository proves the wrong thing.

2. Add the remote and run the checks:

       git remote add origin git@github.com:thechriswebb/test-workflows.git
       ./verify.sh

   Fix anything it reports before pushing.

3. Push.

4. In Settings, Actions, General, set **Require approval for all external
   contributors**. This is what holds a run so the approval path can be tested.

5. Create these eight labels. Colours do not matter.

       ci-running  needs-ci  needs-lint  needs-changes
       needs-review  approved  ready-to-merge  cat-misc

   Create them before the first run. Adding a label to a pull request is a
   different operation from creating one, and it can be refused, so nothing
   here should depend on a label appearing by itself.

6. Fork the repository to `conspirator`.

   Do **not** add `conspirator` as a collaborator on `thechriswebb/test-workflows`.
   A collaborator's runs are not held for approval, and proof 2 below could not
   happen.

## How to drive an outcome

`ci-fake/outcomes.env` decides what each fake job does:

    LINT=pass
    BUILD=pass
    INFRA=pass

Set one to `fail`. Commit. That single commit both flips the outcome and pushes
a new commit, so it exercises the requeue path at the same time.

A fork's pull request runs the fork's copy of that file, so flip it on the
`conspirator` side when acting as a contributor.

| Set | Expected label |
|---|---|
| all `pass` | `needs-review` |
| all `pass`, with `approved` already on the pull request | `ready-to-merge` |
| `LINT=fail` | `needs-lint` |
| `BUILD=fail` | `needs-changes` |
| `INFRA=fail` | `needs-ci` |
| `INFRA=fail` and `BUILD=fail` | `needs-changes` |
| run cancelled by hand | `needs-ci` |

`LINT=fail` skips `mac_build_and_test`, because it declares `needs: lint`. That
is the real workflow's shape, and it is why a lint failure can never appear
beside a build failure.

## What to prove, and what each answer means

Open one pull request from `conspirator` and work through these. Record the
result of each, including the ones that come out differently from the
expectation, because those are the reason this repository exists.

1. **A held run gets no label.** Open the pull request. Confirm the run waits
   for approval and that no `ci-running` label appears while it waits.
   If a label appears here, the workflow is watching the wrong event.

2. **Approving the run labels it.** Approve. Confirm `ci-running` appears.
   This proves two things at once: that GitHub fires the in-progress event on
   approval, and that a `workflow_run` job holds a write token for a fork's
   pull request. If nothing happens, the whole design does not work.

3. **The pull request was found from the commit.** Read the `mark_running` log
   for the line `workflow_run.pull_requests carried N entries`. Record N. The
   code never trusts that array and looks the number up from the head commit,
   so it should work whatever N is.

4. **A push during a run discards the old result.** While a run is in progress,
   push another commit. Confirm `ci-running` clears and `needs-ci` appears, and
   that the old run's completion logs `Discarding this run's result`.

5. **An unscanned pull request is not queued.** Add `cat-misc`, push, and
   confirm `needs-ci` appears. Then remove every `cat-*` label, push again, and
   confirm `needs-ci` does **not** appear while the stale labels still clear.
   Put `cat-misc` back afterwards.

6. **Each outcome writes the right label.** Work through the table above.

7. **Nothing else appears under the pull request's head commit.** Query
   `/repos/thechriswebb/test-workflows/actions/runs?head_sha=<the pull request head>`
   and confirm it lists only `Build and Test`. The maintainer tooling reads
   every run for the head commit and takes the newest with no filter on name,
   so a `CI state` run indexed there would make it read the wrong run.

8. **Renaming the workflow.** In the fork's copy, change
   `name: Build and Test` to anything else, and push. Confirm whether
   `ci-state.yml` still runs. This settles an open question: whether the
   `workflows:` filter matches the name in the fork's copy or the workflow's
   identity in the base repository. If it matches the fork's copy, a
   contributor can silence all labelling by renaming the workflow. Change the
   name back afterwards.

9. **Deleting the real job.** In the fork's copy, delete the
   `mac_build_and_test` job, leave `lint` passing, and push. Confirm the pull
   request receives `needs-review` with nothing built. This is the false green.
   It is expected, and it is why a change under `.github` must always reach a
   human. Restore the job afterwards.

10. **What the reset checkout takes.** In the `requeue` job log, read the
    checked-out commit and compare it against this repository's default branch
    head. This settles whether a `pull_request_target` event gives the default
    branch or the pull request's base branch. Both are repository-owned code,
    so the security property holds either way, and only the wording of a
    comment depends on the answer.

Edit 2
Edit 2b
