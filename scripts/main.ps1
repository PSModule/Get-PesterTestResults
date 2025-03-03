#Requires -Modules GitHub

[CmdletBinding()]
param()

begin {
    $scriptName = $MyInvocation.MyCommand.Name
    Write-Debug "[$scriptName] - Start"
}

process {
    try {
        Write-Output "Hello, $Subject!"
    } catch {
        throw $_
    }
}

end {
    Write-Debug "[$scriptName] - End"
}
