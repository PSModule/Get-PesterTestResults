#Requires -Modules GitHub

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Outputs to GitHub Actions logs.'
)]
[CmdletBinding()]
param()

$owner = $env:GITHUB_REPOSITORY_OWNER
$repo = $env:GITHUB_REPOSITORY_NAME
$runId = $env:GITHUB_RUN_ID

$files = Get-GitHubArtifact -Owner $owner -Repository $repo -WorkflowRunID $runId -Name '*-TestResults' |
    Save-GitHubArtifact -Path 'TestResults' -Force -Expand -PassThru | Get-ChildItem -Recurse -Filter *.json | Sort-Object Name -Unique

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

    $expectedTestSuites = $expectedTestSuites | Sort-Object Category, Name
    $expectedTestSuites | Format-Table | Out-String
}
$isFailure = $false

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

    # Determine if there’s any failure for this single test file
    $testFailure = (
        $result.Result -ne 'Passed' -or
        $result.Executed -ne $true -or
        $result.ResultFilePresent -eq $false -or
        $result.Tests -eq 0 -or
        $result.Passed -eq 0 -or
        $result.Failed -gt 0 -or
        $result.Inconclusive -gt 0
    )

    if ($testFailure) {
        $conclusion = 'Failed'
        $color = $PSStyle.Foreground.Red
        $isFailure = $true
    } else {
        $conclusion = 'Passed'
        $color = $PSStyle.Foreground.Green
    }
    $result | Add-Member -NotePropertyName 'Conclusion' -NotePropertyValue $conclusion

    $reset = $PSStyle.Reset
    $logGroupName = $expected.Name -replace '-TestResult-Report.*', ''

    LogGroup " - $color$logGroupName$reset" {
        if ($result.Executed -eq $false) {
            $unexecutedTests.Add($expected.Name)
            Write-GitHubError "Test was not executed as reported in file: $($expected.Name)"
            $totalErrors++
        } elseif ($result.Result -eq 'Failed') {
            $failedTests.Add($expected.Name)
            Write-GitHubError "Test result explicitly marked as Failed in file: $($expected.Name)"
            $totalErrors++
        }
        $result | Format-Table | Out-String
    }

    if ($result.ResultFilePresent) {
        $testResults.Add($result)
    }
}

Write-Output ('─' * 50)
$total = [pscustomobject]@{
    Tests        = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Tests).Sum))
    Passed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Passed).Sum))
    Failed       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Failed).Sum))
    NotRun       = [int]([math]::Round(($testResults | Measure-Object -Sum -Property NotRun).Sum))
    Inconclusive = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Inconclusive).Sum))
    Skipped      = [int]([math]::Round(($testResults | Measure-Object -Sum -Property Skipped).Sum))
}


$color = if ($isFailure) { $PSStyle.Foreground.Red } else { $PSStyle.Foreground.Green }
$reset = $PSStyle.Reset
LogGroup " - $color`Summary$reset" {
    $total | Format-Table | Out-String
    if ($total.Failed -gt 0) {
        Write-GitHubError "There are $($total.Failed) failed tests of $($total.Tests) tests"
        $totalErrors += $total.Failed
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
