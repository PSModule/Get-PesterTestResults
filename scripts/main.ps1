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

LogGroup 'Expected test suites' {
    $sourceCodeTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_SourceCodeTestSuites | ConvertFrom-Json
    $psModuleTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_PSModuleTestSuites | ConvertFrom-Json
    $moduleTestSuites = $env:PSMODULE_GET_PESTERTESTRESULTS_INPUT_ModuleTestSuites | ConvertFrom-Json

# Build an array of expected test suite objects
$expectedTestSuites = @()

# SourceCodeTestSuites: expected file names start with "SourceCode-"
foreach ($suite in $sourceCodeTestSuites) {
    $expectedTestSuites += [pscustomobject]@{
        FileName = "SourceCode-$($suite.OSName)-TestResult-Report.json"
        Category = 'SourceCode'
        OSName   = $suite.OSName
        TestName = $null
    }
}

# PSModuleTestSuites: expected file names start with "Module-"
foreach ($suite in $psModuleTestSuites) {
    $expectedTestSuites += [pscustomobject]@{
        FileName = "Module-$($suite.OSName)-TestResult-Report.json"
        Category = 'PSModuleTest'
        OSName   = $suite.OSName
        TestName = $null
    }
}

# ModuleTestSuites: expected file names use the TestName as prefix
foreach ($suite in $moduleTestSuites) {
    $expectedTestSuites += [pscustomobject]@{
        FileName = "$($suite.TestName)-$($suite.OSName)-TestResult-Report.json"
        Category = 'ModuleTest'
        OSName   = $suite.OSName
        TestName = $suite.TestName
    }
}

# Remove duplicates if any
$expectedTestSuites = $expectedTestSuites | Select-Object -Unique

    $expectedTestSuites | Format-Table | Out-String
}

$testResults = [System.Collections.Generic.List[psobject]]::new()
$failedTests = [System.Collections.Generic.List[psobject]]::new()
$unexecutedTests = [System.Collections.Generic.List[psobject]]::new()
$totalErrors = 0

foreach ($expected in $expectedTestSuites) {
    $filePath = Join-Path $testResultsFolder.FullName $expected.FileName
    if (Test-Path $filePath) {
        $content = Get-Content -Path $filePath
        $object = $content | ConvertFrom-Json
        $result = [pscustomobject]@{
            Tests             = [int]([math]::Round(($object | Measure-Object -Sum -Property TotalCount).Sum))
            Passed            = [int]([math]::Round(($object | Measure-Object -Sum -Property PassedCount).Sum))
            Failed            = [int]([math]::Round(($object | Measure-Object -Sum -Property FailedCount).Sum))
            NotRun            = [int]([math]::Round(($object | Measure-Object -Sum -Property NotRunCount).Sum))
            Inconclusive      = [int]([math]::Round(($object | Measure-Object -Sum -Property InconclusiveCount).Sum))
            Skipped           = [int]([math]::Round(($object | Measure-Object -Sum -Property SkippedCount).Sum))
            ResultFilePresent = $true
        }
    } else {
        $result = [pscustomobject]@{
            Tests             = $null
            Passed            = $null
            Failed            = $null
            NotRun            = $null
            Inconclusive      = $null
            Skipped           = $null
            ResultFilePresent = $false
        }
        Write-GitHubError "Missing expected test result file: $($expected.FileName)"
        $totalErrors++
    }

    # Determine if there’s any failure: missing file or non-successful test counts
    $isFailure = ($result.ResultFilePresent -eq $false) -or
                 ($result.Failed -gt 0) -or
                 ($result.NotRun -gt 0) -or
                 ($result.Inconclusive -gt 0)
    $color = $isFailure ? $PSStyle.Foreground.Red : $PSStyle.Foreground.Green
    $reset = $PSStyle.Reset
    $logGroupName = $expected.FileName -replace '-TestResult-Report', ''

    LogGroup " - $color$logGroupName$reset" {
        if ($result.ResultFilePresent) {
            # Output detailed results from the file.
            $object | Format-List | Out-String
            if ($object.Executed -eq $false) {
                $unexecutedTests.Add($expected.FileName)
                Write-GitHubError "Test was not executed as reported in file: $($expected.FileName)"
                $totalErrors++
            } elseif ($object.Result -eq 'Failed') {
                $failedTests.Add($expected.FileName)
                Write-GitHubError "Test result explicitly marked as Failed in file: $($expected.FileName)"
                $totalErrors++
            }
            $result | Format-Table | Out-String
        } else {
            Write-Host "Test result file not found for: $($expected.FileName)"
        }
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
