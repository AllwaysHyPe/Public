function Write-Log {
    <#
    .SYNOPSIS
    Writes a structured log entry to a JSON log file and the console.

    .DESCRIPTION
    Logs timestamped, severity-tagged messages with caller context to a structured
    JSON log file. Error entries additionally capture full exception detail and a
    call stack dump for debugging.

    .PARAMETER Severity
    Severity level of the log entry. Defaults to 'Info'.

    .PARAMETER Message
    The message to log. Required.

    .PARAMETER LogDirectory
    Directory to write the log file into. Defaults to '$PWD/Logs'.
    Created automatically if it does not exist.

    .PARAMETER LastException
    Accepts an ErrorRecord. Defaults to $_ so it auto-captures inside a catch block.
    Only used when Severity is Error.

    .EXAMPLE
    Write-Log -Message "Connecting to Graph API" -Severity Start

    .NOTES
    Adapted from Write-PSULog https://blog.ironmansoftware.com/write-psulog/
    #>
    param (
        [ValidateSet('Info', 'Warn', 'Error', 'Start', 'End', IgnoreCase = $false)]
        [string]$Severity = "Info",
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$logDirectory = "$PWD/Logs",
        [System.Management.Automation.ErrorRecord]$LastException = $_
    )

    $CallStackDepth = 0
    $fullCallStack = Get-PSCallStack
    $CallingFunction = $fullCallStack[1].FunctionName

    if ($env:GitHub_Actions) {
        $Metadata = [PSCustomObject]@{
            Invoking_User = $env:GITHUB_WORKFLOW
            RunId         = $env:GITHUB_RUN_ID
            Ref           = $env:GITHUB_REF_NAME
        }
    } else {
        $Metadata = [PSCustomObject]@{
            Invoking_User = ($HOME | Split-Path -Leaf)
        }
    }


    $LogObject = [PSCustomObject]@{
        Timestamp       = (Get-Date).ToString()
        Severity        = $Severity
        CallingFunction = $CallingFunction
        Message         = $Message
        Metadata        = $Metadata
    }

    if ($Severity -eq "Error") {
        if ($LastException.ErrorRecord) {
            # PSCore Error
            $LastException.ErrorRecord
        } else {
            # PS 5.1 Error
            $LastError = $LastException
        }

        if ($LastException.InvocationInfo.MyCommand.Version) {
            $version = $LastError.InvocationInfo.MyCommand.Version.ToString()
        }

        $LastErrorObject = @{
            'ExceptionMessage'    = $LastError.Exception.Message
            'ExceptionSource'     = $LastError.Exception.Source
            'ExceptionStackTrace' = $LastError.Exception.StackTrace
            'PositionMessage'     = $LastError.InvocationInfo.PositionMessage
            'InvocationName'      = $LastError.InvocationInfo.InvocationName
            'MyCommandVersion'    = $version
            'ScriptName'          = $LastError.InvocationInfo.ScriptName
        }

        $LogObject | Add-Member -MemberType NoteProperty -Name LastError -Value $LastErrorObject

        $FullCallStackWithoutLogFunction = $fullCallStack | ForEach-Object {
            if ($CallStackDepth -gt 0) {
                [PSCustomObject]@{
                    CallStackDepth   = $CallStackDepth
                    ScriptLineNumber = $_.ScriptLineNumber
                    FunctionName     = $_.FunctionName
                    ScriptName       = $_.ScriptName
                    Location         = $_.Location
                    Command          = $_.Command
                    Arguments        = $_.Arguments
                }
            }
            $CallStackDepth++
        }

        $LogObject | Add-Member -MemberType NoteProperty -Name fullCallStackDump -Value $FullCallStackWithoutLogFunction

        $WriteHostColor = @{ ForegroundColor = "Red" }
    }

    if (-not (Test-Path $LogDirectory)) {
        $null = New-Item -ItemType Directory -Path $LogDirectory -Force
    }

    $LogFilePath = Join-Path "$LogDirectory" "intunestack.log"
    $LogObject | ConvertTo-Json -Depth 2 | Out-File -FilePath $LogFilePath -Append -Encoding utf8


    Write-Host "$($LogObject.Timestamp) Sev=$($LogObject.Severity) CallingFunction=$($LogObject.CallingFunction) `n   $($LogObject.Message)" @WriteHostColor
    if ($Severity -eq "Error") { throw $LastException }
}