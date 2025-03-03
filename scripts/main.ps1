#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$testResultsFolder = New-Item -Path . -ItemType Directory -Name 'TestResults' -Force
gh run download $runId --repo $repo --pattern *-TestResults --dir TestResults
$files = Get-ChildItem -Path $testResultsFolder -Recurse -File -Filter *.json | Sort-Object Name

LogGroup 'List files' {
    $files.Name | Out-String
}

$testResults = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    $content = Get-Content -Path $file
    $object = $content | ConvertFrom-Json
    $testResults.Add($object)

    $result = [pscustomobject]@{
        Tests        = [int]([math]::Round(($object | Measure-Object -Sum -Property TotalCount).Sum))
        Passed       = [int]([math]::Round(($object | Measure-Object -Sum -Property PassedCount).Sum))
        Failed       = [int]([math]::Round(($object | Measure-Object -Sum -Property FailedCount).Sum))
        NotRun       = [int]([math]::Round(($object | Measure-Object -Sum -Property NotRunCount).Sum))
        Inconclusive = [int]([math]::Round(($object | Measure-Object -Sum -Property InconclusiveCount).Sum))
        Skipped      = [int]([math]::Round(($object | Measure-Object -Sum -Property SkippedCount).Sum))
    }
    $failed = ($result.Failed -gt 0) -or ($result.NotRun -gt 0) -or ($result.Inconclusive -gt 0)
    $color = $failed ? $PSStyle.Foreground.Red : $PSStyle.Foreground.Green
    $reset = $PSStyle.Reset
    $logGroupName = $fileName.Replace('-TestResult-Report', '')
    LogGroup " - $color$logGroupName$reset" {
        $result | Format-Table | Out-String
    }
}
Write-Output ('─' * 50)
$total = [pscustomobject]@{
    Tests        = [int]([math]::Round(($testResults | Measure-Object -Sum -Property TotalCount).Sum))
    Passed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property PassedCount).Sum))
    Failed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property FailedCount).Sum))
    NotRun       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property NotRunCount).Sum))
    Inconclusive = [int]([math]::Round(($testResults | Measure-Object -Sum -Property InconclusiveCount).Sum))
    Skipped      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property SkippedCount).Sum))
}
$failed = ($result.Failed -gt 0) -or ($result.NotRun -gt 0) -or ($result.Inconclusive -gt 0)
$color = $failed ? $PSStyle.Foreground.Red : $PSStyle.Foreground.Green
$reset = $PSStyle.Reset
LogGroup " - $color`Summary$reset" {
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
