function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Verbose')]
        [string]$Level = 'Info',
        
        [string]$LogFailuresToPath
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Color mapping for console output
    $Color = switch ($Level) {
        'Info'    { 'White' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
        'Verbose' { 'Gray' }
    }
    
    # Format the log entry
    $LogEntry = "$TimeStamp - [$Level] $Message"
    
   # Console output
    Write-Host $LogEntry -ForegroundColor $Color
    
    # File logging if path is provided
    if ($LogFailuresToPath) {
        $LogEntry | Out-File -FilePath $LogFailuresToPath -Append -Encoding UTF8
    }
}
