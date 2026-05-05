$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scratch = Join-Path $Root 'scratch'
if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$BashExe = 'C:\Program Files\Git\bin\bash.exe'
$Hook = '/c/Users/exrov/.claude/hooks/on-prompt-submit.sh'
$HelperSrc = 'C:\Users\exrov\.claude\scripts\lib-helpers.sh'

function New-Scenario {
  param(
    [string]$Name,
    [string]$Phase = 'BUILD',
    [int]$Sprint = 20,
    [int]$Writes = 0,
    [switch]$Watcher,
    [switch]$Contract,
    [switch]$MustDo,
    [string]$Evidence = '',
    [string]$Strategy = '',
    [int]$PreflightWriteCount = 1,
    [string]$PreflightStep = 'Step 1: BUILD ? implement packet'
  )
  $Project = Join-Path $Scratch $Name
  $HomeDir = Join-Path $Project 'home'
  New-Item -ItemType Directory -Force -Path "$Project\.claude\state", "$Project\.claude\contracts", "$Project\.claude\pre-flight", "$HomeDir\.claude\scripts", "$HomeDir\.openclaw\watchers" | Out-Null
  Copy-Item -LiteralPath $HelperSrc -Destination "$HomeDir\.claude\scripts\lib-helpers.sh"
  "{`"phase`":`"$Phase`",`"sprint`":$Sprint,`"iteration`":0}" | Set-Content -LiteralPath "$Project\.claude\state\current-phase.json" -Encoding ASCII
  "$Writes" | Set-Content -LiteralPath "$Project\.claude\state\write-count.txt" -Encoding ASCII
  if ($Contract) { '# contract' | Set-Content -LiteralPath "$Project\.claude\contracts\sprint-$Sprint-contract.md" -Encoding ASCII }
  if ($MustDo) {
    New-Item -ItemType Directory -Force -Path "$Project\docs\must-do" | Out-Null
    'docs/must-do/guide.md' | Set-Content -LiteralPath "$Project\docs\must-do\must-do.md" -Encoding ASCII
    'guide' | Set-Content -LiteralPath "$Project\docs\must-do\guide.md" -Encoding ASCII
  }
  $ProjectFwd = $Project.Replace('\','/')
  if ($Watcher) {
    "{`"version`":`"1.0.0`",`"watchers`": [{`"slot`":1,`"status`":`"active`",`"claimed_by`":`"Test`",`"project`":`"$ProjectFwd`",`"cron_job_id`":`"cron1`",`"cron_interval`":`"*/3 * * * *`"}]}" | Set-Content -LiteralPath "$HomeDir\.openclaw\watchers\REGISTRY.json" -Encoding ASCII
    @(
      '# Watcher Slot 1',
      '',
      '## SCOPE',
      '- Build packet.',
      '',
      '## MISTAKES TO AVOID',
      '- Do not touch gates.',
      '',
      '## TO-DO',
      '- [ ] Step 1: BUILD ? implement packet',
      '',
      '## COMPLETION CRITERIA',
      '- Packet tests pass',
      '- Gates unchanged'
    ) | Set-Content -LiteralPath "$HomeDir\.openclaw\watchers\slot-1.md" -Encoding ASCII
    "{`"write_count`":$PreflightWriteCount,`"last_step`":`"$PreflightStep`"}" | Set-Content -LiteralPath "$Project\.claude\pre-flight\gate-counter.json" -Encoding ASCII
  } else {
    '{"version":"1.0.0","watchers":[]}' | Set-Content -LiteralPath "$HomeDir\.openclaw\watchers\REGISTRY.json" -Encoding ASCII
  }
  if ($Evidence) {
    '{"status":"pending"}' | Set-Content -LiteralPath "$Project\.claude\state\evidence-checkpoint.json" -Encoding ASCII
    if ($Evidence -in @('fail-no-remediation','fail-remediation')) {
      '{"verdict":"FAIL"}' | Set-Content -LiteralPath "$Project\.claude\state\evidence-verdict.json" -Encoding ASCII
    }
    if ($Evidence -eq 'fail-remediation') {
      ('x' * 220) | Set-Content -LiteralPath "$Project\.claude\state\evidence-remediation.md" -Encoding ASCII
    }
  }
  if ($Strategy) {
    '{"nudge_count":0,"last_nudge_ts":"","last_output_fingerprint":"","last_churn_files":[],"blocked":false}' | Set-Content -LiteralPath "$Project\.claude\state\strategy-loop-state.json" -Encoding ASCII
    $Code = if ($Strategy -eq 'nudge') { 'exit 1' } else { 'exit 2' }
    "#!/bin/bash`n$Code`n" | Set-Content -LiteralPath "$HomeDir\.claude\scripts\detect-strategy-loop.sh" -Encoding ASCII
  }
  @{ Project = $Project; HomeDir = $HomeDir }
}

function Invoke-Packet($Scenario) {
  $ProjectBash = $Scenario.Project.Replace('G:\','/g/').Replace('\','/')
  $HomeBash = $Scenario.HomeDir.Replace('G:\','/g/').Replace('\','/')
  $Lines = & $BashExe -lc "cd '$ProjectBash' && HOME='$HomeBash' HARNESS_STATE_DIR='.claude/state' '$Hook'"
  ($Lines -join "`n")
}

$Cases = @(
  @{Name='steady-watcher'; Scenario={ New-Scenario 'steady-watcher' -Phase BUILD -Writes 3 -Watcher -Contract }; Pred={ param($o) $o -match 'READ FIRST' -and $o -match 'DONE WHEN' -and $o.Length -lt 600 -and $o -notmatch 'BLOCKED BY' -and $o -notmatch 'ACTIONS BEFORE CODE' }},
  @{Name='fresh-locked'; Scenario={ New-Scenario 'fresh-locked' -Phase BUILD -Writes 3 -Contract }; Pred={ param($o) $o -match 'Claim watcher' -and $o -match 'Start reminder' -and $o -match 'ALWAYS WRITABLE' -and $o.IndexOf('Claim watcher') -lt $o.IndexOf('Start reminder') }},
  @{Name='negotiate-missing-contract'; Scenario={ New-Scenario 'negotiate-missing-contract' -Phase NEGOTIATE -Writes 0 -Watcher }; Pred={ param($o) $o -match 'Write contract' -and $o -match 'WRITES LOCKED: Phase is NEGOTIATE' -and $o -match 'ALWAYS WRITABLE' }},
  @{Name='build-missing-contract'; Scenario={ New-Scenario 'build-missing-contract' -Phase BUILD -Writes 0 -Watcher }; Pred={ param($o) $o -match 'Write contract' -and $o -notmatch 'WRITES LOCKED: Phase is BUILD' }},
  @{Name='mcq-due'; Scenario={ New-Scenario 'mcq-due' -Phase BUILD -Writes 1 -Watcher -Contract -PreflightWriteCount 4 }; Pred={ param($o) $o -match 'MCQ gate fires' }},
  @{Name='mustdo'; Scenario={ New-Scenario 'mustdo' -Phase BUILD -Writes 1 -Watcher -Contract -MustDo }; Pred={ param($o) $o -match 'READ FIRST' -and $o -match 'must-do' -and $o -match 'Write must-do summary' }},
  @{Name='evidence-none'; Scenario={ New-Scenario 'evidence-none' -Phase BUILD -Writes 1 -Watcher -Contract -Evidence 'none' }; Pred={ param($o) $o -match 'evidence checkpoint' -and $o -match 'spawn verifier' -and $o -match 'ALWAYS WRITABLE' }},
  @{Name='evidence-fail-no-remediation'; Scenario={ New-Scenario 'evidence-fail-no-remediation' -Phase BUILD -Writes 1 -Watcher -Contract -Evidence 'fail-no-remediation' }; Pred={ param($o) $o -match 'evidence FAIL' -and $o -match 'evidence-remediation' -and $o -match 'ALWAYS WRITABLE' }},
  @{Name='evidence-fail-remediation'; Scenario={ New-Scenario 'evidence-fail-remediation' -Phase BUILD -Writes 1 -Watcher -Contract -Evidence 'fail-remediation' }; Pred={ param($o) $o -match 'produce evidence' -and $o -match 'delete evidence-verdict' -and $o -match 'ALWAYS WRITABLE' }},
  @{Name='strategy-nudge'; Scenario={ New-Scenario 'strategy-nudge' -Phase BUILD -Writes 1 -Watcher -Contract -Strategy 'nudge' }; Pred={ param($o) $o -match 'STRATEGY NUDGE' -and $o -notmatch 'strategy loop — write' }},
  @{Name='strategy-block'; Scenario={ New-Scenario 'strategy-block' -Phase BUILD -Writes 1 -Watcher -Contract -Strategy 'block' }; Pred={ param($o) $o -match 'BLOCKED BY' -and $o -match 'strategy loop' -and $o -match 'ALWAYS WRITABLE' }},
  @{Name='worst-budget'; Scenario={ New-Scenario 'worst-budget' -Phase NEGOTIATE -Writes 3 -MustDo -Evidence 'fail-no-remediation' }; Pred={ param($o) $o.Length -lt 1500 -and $o -match 'ALWAYS WRITABLE' -and $o -match 'evidence FAIL' -and $o -match 'Write contract' }}
)
$Results = foreach ($Case in $Cases) {
  $Scenario = & $Case.Scenario
  $Output = Invoke-Packet $Scenario
  $Pass = & $Case.Pred $Output
  [pscustomobject]@{ Name=$Case.Name; Pass=$Pass; Len=$Output.Length; Output=$Output }
}

$Results | Select-Object Name,Pass,Len | Format-Table -AutoSize
$Failed = $Results | Where-Object { -not $_.Pass }
if ($Failed) {
  $Failed | ForEach-Object { "--- FAILED $($_.Name) len=$($_.Len)"; $_.Output }
  exit 1
}
$Max = ($Results | Measure-Object Len -Maximum).Maximum
"All scenario tests passed. MaxLen=$Max"


