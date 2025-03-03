#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$testResultsFolder = New-Item -Path . -ItemType Directory -Name 'TestResults' -Force
gh run download $runId --repo $repo --pattern *-TestResults --dir TestResults
$files = Get-ChildItem -Path $testResultsFolder -Recurse -File -Filter *.json

LogGroup 'List TestResults files' {
    $files.Name | Out-String
}

$testResults = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    LogGroup $fileName {
        $content = Get-Content -Path $file
        $content | Out-String
    }
    LogGroup "$fileName - Summary" {
        $object = $content | ConvertFrom-Json
        $object | Format-Table | Out-String
        $testResults.Add($object)
    }
}

$total = [pscustomobject]@{
    Tests        = [int]([math]::Round(($testResults | Measure-Object -Sum -Property TotalCount).Sum))
    Passed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property PassedCount).Sum))
    Failed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property FailedCount).Sum))
    NotRun       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property NotRunCount).Sum))
    Inconclusive = [int]([math]::Round(($testResults | Measure-Object -Sum -Property InconclusiveCount).Sum))
    Skipped      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property SkippedCount).Sum))
}
$total | Format-Table | Out-String

$totalErrors = 0
if ($total.Failed -gt 0) {
    Write-GitHubError "There are $($total.Failed) failed tests of $($total.Tests) tests"
    $totalErrors += $total.Failed
}

if ($total.NotRun -gt 0) {
    Write-GitHubError "There are $($total.NotRun) test not run of $($total.Tests) tests"
    $totalErrors += $_.NotRun
}

if ($total.Inconclusive -gt 0) {
    Write-GitHubError "There are $($total.Inconclusive) inconclusive tests of $($total.Tests) tests"
    $totalErrors += $_.Inconclusive
}

exit $totalErrors
