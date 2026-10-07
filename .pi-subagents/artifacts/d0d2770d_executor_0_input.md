# Task for executor

Implement user's request in /home/smaximov/gh/llm-agents-nix safely using jj: smdex forks for jcode,paseo,multica; add pi-perplexity CLI package (pplx v0.1.0 from https://github.com/smdex/pi-perplexity cli/ workspace, NOT npm extension). Existing numtide upstream package edits must be on chiki only; keep chiki atop main. Discovery: upstream GitHub packages jcode,multica exist; paseo,pi-perplexity absent. Local clean @ empty; main at oowpx, chiki at sklpp/e98368a9 diverged from main, duplicate jcode updater commits on each side. main jcode package upstream 1jehuang but update.py tracks fork incorrectly; relocate fork-specific updater changes to chiki (main should track upstream). chiki already pins smdex/jcode rev 1b434d4ceed0ff93265153cf2012a24cd214025a and smdex/paseo rev 36767d553263c8111a8b2d7d8d5972a20050273f version 0.11.0-beta.5 incl paseo-desktop edits. Move paseo fork-specific changes to main since absent upstream; jcode and multica fork changes chiki only. Preserve unrelated history/user changes, no push. Read shared AGENTS/MEMORY and appropriate Nix, jj, pi-jj-auto, ponytail skills before changes. Inspect actual history before rebase; explicit rebase full chiki-only stack onto final main, not only tip. Existing main fork-specific jcode updater should be corrected/moved with smallest safe history adjustment (new commits acceptable, don't rewrite public ancestors unnecessarily). Fetch permitted to inspect remotes but don't merge latest upstream main unless needed for user task. Inspect smdex/pi-perplexity upstream Nix derivation and adapt repository pattern; proper metadata/category/updater, bin pplx, package attr pi-perplexity (optional pplx alias only if repo pattern). Pin fork source branches to commits when no useful tags; fork tip/version avoid mismatching upstream tagged versions. Verify fork hashes/deps/builds, updater behavior relevant, nix fmt, relevant checks; flake check if practical report limitation honestly. Keep chiki atop main, finish working copy on chiki descendant and bookmarks updated. Report changes per branch, exact jj ancestry evidence, tests and blockers. Sole writer. No global config/profile modifications. Durable nonsecret user branch policy note shared memory under stable flock if appropriate.

## Acceptance Contract
Acceptance level: attested
Completion is not accepted from prose alone. End with a structured acceptance report.

Criteria:
- criterion-1: Return concrete findings with file paths and severity when applicable

Required evidence: review-findings, residual-risks

Finish with a fenced JSON block tagged `acceptance-report` in this shape:
Use empty arrays when no items apply; array fields contain strings unless object entries are shown.
```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "specific proof"
    }
  ],
  "changedFiles": [
    "src/file.ts"
  ],
  "testsAddedOrUpdated": [
    "test/file.test.ts"
  ],
  "commandsRun": [
    {
      "command": "command",
      "result": "passed",
      "summary": "short result"
    }
  ],
  "validationOutput": [
    "validation output or concise summary"
  ],
  "residualRisks": [
    "none"
  ],
  "noStagedFiles": true,
  "diffSummary": "short description of the diff",
  "reviewFindings": [
    "blocker: file.ts:12 - issue found, or no blockers"
  ],
  "manualNotes": "anything else the parent should know"
}
```