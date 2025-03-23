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

$sourceCodeTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_SourceCodeTestSuites | ConvertFrom-Json
$psModuleTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_PSModuleTestSuites | ConvertFrom-Json
$moduleTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_ModuleTestSuites | ConvertFrom-Json

LogGroup 'Expected test suites' {

    # Build an array of expected test suite objects
    $expectedTestSuites = @()

    # SourceCodeTestSuites: expected file names start with "SourceCode-"
    foreach ($suite in $sourceCodeTestSuites) {
        $expectedTestSuites += [pscustomobject]@{
            Name     = "PSModuleTest-SourceCode-$($suite.OSName)-TestResult-Report"
            Category = 'SourceCode'
            OSName   = $suite.OSName
            TestName = $null
        }
        $expectedTestSuites += [pscustomobject]@{
            Name     = "PSModuleLint-SourceCode-$($suite.OSName)-TestResult-Report"
            Category = 'SourceCode'
            OSName   = $suite.OSName
            TestName = $null
        }
    }

    # PSModuleTestSuites: expected file names start with "Module-"
    foreach ($suite in $psModuleTestSuites) {
        $expectedTestSuites += [pscustomobject]@{
            Name     = "PSModuleTest-Module-$($suite.OSName)-TestResult-Report"
            Category = 'PSModuleTest'
            OSName   = $suite.OSName
            TestName = $null
        }
        $expectedTestSuites += [pscustomobject]@{
            Name     = "PSModuleLint-Module-$($suite.OSName)-TestResult-Report"
            Category = 'PSModuleTest'
            OSName   = $suite.OSName
            TestName = $null
        }
    }

    # ModuleTestSuites: expected file names use the TestName as prefix
    foreach ($suite in $moduleTestSuites) {
        $expectedTestSuites += [pscustomobject]@{
            Name     = "$($suite.TestName)-$($suite.OSName)-TestResult-Report"
            Category = 'ModuleTest'
            OSName   = $suite.OSName
            TestName = $suite.TestName
        }
    }

    $expectedTestSuites = $expectedTestSuites | Sort-Object Name
    $expectedTestSuites | Format-Table | Out-String
}

$testResults = [System.Collections.Generic.List[psobject]]::new()
$failedTests = [System.Collections.Generic.List[psobject]]::new()
$unexecutedTests = [System.Collections.Generic.List[psobject]]::new()
$totalErrors = 0

foreach ($expected in $expectedTestSuites) {
    $file = $files | Where-Object { $_.BaseName -eq $expected.Name }
    $result = if ($file) {
        $object = $file | Get-Content | ConvertFrom-Json
        [pscustomobject]@{
            Result            = $object.Result
            Executed          = $object.Executed
            ResultFilePresent = $true
            Tests             = [int]([math]::Round(($object | Measure-Object -Sum -Property TotalCount).Sum))
            Passed            = [int]([math]::Round(($object | Measure-Object -Sum -Property PassedCount).Sum))
            Failed            = [int]([math]::Round(($object | Measure-Object -Sum -Property FailedCount).Sum))
            NotRun            = [int]([math]::Round(($object | Measure-Object -Sum -Property NotRunCount).Sum))
            Inconclusive      = [int]([math]::Round(($object | Measure-Object -Sum -Property InconclusiveCount).Sum))
            Skipped           = [int]([math]::Round(($object | Measure-Object -Sum -Property SkippedCount).Sum))
        }
    } else {
        [pscustomobject]@{
            Result            = $null
            Executed          = $null
            ResultFilePresent = $false
            Tests             = $null
            Passed            = $null
            Failed            = $null
            NotRun            = $null
            Inconclusive      = $null
            Skipped           = $null
        }
    }

    # Determine if there’s any failure: missing file or non-successful test counts
    $isFailure = (
        $result.Result -ne 'Passed' -or
        $result.Executed -ne $true -or
        $result.ResultFilePresent -eq $false -or
        $result.Tests -eq 0 -or
        $result.Passed -eq 0 -or
        $result.Failed -gt 0 -or
        $result.NotRun -gt 0 -or
        $result.Inconclusive -gt 0
    )
    $color = $isFailure ? $PSStyle.Foreground.Red : $PSStyle.Foreground.Green
    $reset = $PSStyle.Reset
    $logGroupName = $expected.Name -replace '-TestResult-Report.*', ''

    LogGroup " - $color$logGroupName$reset" {
        if ($object.Executed -eq $false) {
            $unexecutedTests.Add($expected.Name)
            Write-GitHubError "Test was not executed as reported in file: $($expected.Name)"
            $totalErrors++
        } elseif ($object.Result -eq 'Failed') {
            $failedTests.Add($expected.Name)
            Write-GitHubError "Test result explicitly marked as Failed in file: $($expected.Name)"
            $totalErrors++
        }
        $result | Format-Table | Out-String
    }

    if ($result.ResultFilePresent) {
        $testResults.Add($object)
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

$overallFailure = ($total.Failed -gt 0) -or ($total.NotRun -gt 0) -or ($total.Inconclusive -gt 0) -or ($totalErrors -gt 0)
$color = $overallFailure ? $PSStyle.Foreground.Red : $PSStyle.Foreground.Green
$reset = $PSStyle.Reset
LogGroup " - $color`Summary$reset" {
    $total | Format-Table | Out-String
    if ($total.Failed -gt 0) {
        Write-GitHubError "There are $($total.Failed) failed tests of $($total.Tests) tests"
        $totalErrors += $total.Failed
    }
    if ($total.NotRun -gt 0) {
        Write-GitHubError "There are $($total.NotRun) tests not run of $($total.Tests) tests"
        $totalErrors += $total.NotRun
    }
    if ($total.Inconclusive -gt 0) {
        Write-GitHubError "There are $($total.Inconclusive) inconclusive tests of $($total.Tests) tests"
        $totalErrors += $total.Inconclusive
    }
    if ($failedTests.Count -gt 0) {
        Write-Host 'Failed Test Files'
        $failedTests | ForEach-Object { Write-Host " - $_" }
    }
    if ($unexecutedTests.Count -gt 0) {
        Write-Host 'Unexecuted Test Files'
        $unexecutedTests | ForEach-Object { Write-Host " - $_" }
    }
}

exit $totalErrors
