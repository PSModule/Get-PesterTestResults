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
    $content = Get-Content -Path $file
    $object = $content | ConvertFrom-Json
    $testResults.Add($object)

    # LogGroup $fileName {
    #     $content | Out-String
    # }

    LogGroup "$fileName" {
        $result = [pscustomobject]@{
            Tests        = [int]([math]::Round(($object | Measure-Object -Sum -Property TotalCount).Sum))
            Passed       = [int]([math]::Round(($object | Measure-Object -Sum -Property PassedCount).Sum))
            Failed       = [int]([math]::Round(($object | Measure-Object -Sum -Property FailedCount).Sum))
            NotRun       = [int]([math]::Round(($object | Measure-Object -Sum -Property NotRunCount).Sum))
            Inconclusive = [int]([math]::Round(($object | Measure-Object -Sum -Property InconclusiveCount).Sum))
            Skipped      = [int]([math]::Round(($object | Measure-Object -Sum -Property SkippedCount).Sum))
        }
        $result | Format-Table | Out-String
    }
}

LogGroup 'TestResult - Summary' {
    $total = [pscustomobject]@{
        Tests        = [int]([math]::Round(($testResults | Measure-Object -Sum -Property TotalCount).Sum))
        Passed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property PassedCount).Sum))
        Failed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property FailedCount).Sum))
        NotRun       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property NotRunCount).Sum))
        Inconclusive = [int]([math]::Round(($testResults | Measure-Object -Sum -Property InconclusiveCount).Sum))
        Skipped      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property SkippedCount).Sum))
    }
    $total | Format-Table | Out-String
}

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
