#Requires -Modules GitHub

[CmdletBinding()]
param()

$PSStyle.OutputRendering = 'Ansi'
$repo = $env:GITHUB_REPOSITORY
$runId = $env:GITHUB_RUN_ID
$testResultsFolder = New-Item -Path . -ItemType Directory -Name 'TestResults' -Force
gh run download $runId --repo $repo --pattern *-TestResults --dir TestResults
$files = Get-ChildItem -Path $testResultsFolder -Recurse -File

LogGroup 'List TestResults files' {
    $files.Name | Out-String
}

$allCases = [System.Collections.Generic.List[psobject]]::new()
$testResults = [System.Collections.Generic.List[psobject]]::new()
foreach ($file in $files) {
    $fileName = $file.BaseName
    $xmlDoc = [xml](Get-Content -Path $file.FullName)
    LogGroup $fileName {
        Get-Content -Path $file | Out-String
    }
    LogGroup "$fileName - Tests" {
        $cases = $xmlDoc.SelectNodes('//test-case') | ForEach-Object {
            [pscustomobject]@{
                Name           = $_.name
                Description    = $_.description
                Result         = $_.result
                Success        = [bool]($_.success -eq 'True')
                Time           = [float]$_.time
                Executed       = [bool]($_.executed -eq 'True')
                FailureMessage = $_.failure.message
                StackTrace     = $_.failure.'stack-trace'
            }
        }
        $cases | ForEach-Object { $allCases.Add($_) }
        $cases | Format-List | Out-String
    }
    LogGroup "$fileName - Summary" {
        $testResultXml = $xmlDoc.'test-results'
        $testResult = [pscustomobject]@{
            Name         = $testResultXml.name
            Total        = $testResultXml.total
            Errors       = $testResultXml.errors
            Failures     = $testResultXml.failures
            NotRun       = $testResultXml.'not-run'
            Inconclusive = $testResultXml.inconclusive
            Ignored      = $testResultXml.ignored
            Skipped      = $testResultXml.skipped
            Invalid      = $testResultXml.invalid
            Date         = $testResultXml.date
            Time         = $testResultXml.time
        }
        $testResults.Add($testResult)
        $testResult | Format-List | Out-String
    }
}

[pscustomobject]@{
    TotalTests        = $allCases.Count
    TotalErrors       = ($testResults | Measure-Object -Sum -Property Errors).Sum
    TotalFailures     = ($testResults | Measure-Object -Sum -Property Failures).Sum
    TotalNotRun       = ($testResults | Measure-Object -Sum -Property NotRun).Sum
    TotalInconclusive = ($testResults | Measure-Object -Sum -Property Inconclusive).Sum
    TotalIgnored      = ($testResults | Measure-Object -Sum -Property Ignored).Sum
    TotalSkipped      = ($testResults | Measure-Object -Sum -Property Skipped).Sum
    TotalInvalid      = ($testResults | Measure-Object -Sum -Property Invalid).Sum
} | Format-Table | Out-String
