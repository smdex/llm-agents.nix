# Task for scout

Read-only discovery for request in /home/smaximov/gh/llm-agents-nix: Use smdex forks for jcode, paseo, multica; add pi-perplexity CLI package. If package exists in numtide upstream, modifications must live on chiki not main; chiki stays atop main. Read shared /home/smaximov/.config/agent-tooling/AGENTS.md and MEMORY.md, relevant skills (Nix packaging, jj, ctx as permitted). Inspect jj status/log/bookmarks/remotes and existing packages, upstream numtide package presence using remote read-only evidence, identify pi-perplexity upstream identity (avoid assuming similarly named tool). Use CodeGraph/Serena navigation as applicable; configs narrow reads fine. No changes, no fetch altering refs unless necessary report. Return exact package paths, upstream presence evidence, fork/tag/version info, current branch/revision dirty status, recommended safe jj sequence, ambiguities.

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