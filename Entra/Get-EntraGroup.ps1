
function Get-EntraGroup() {
    <#
    .SYNOPSIS
    This function is used to get Entra ID groups from the Graph API REST interface

    .DESCRIPTION
    The function connects to the Graph API Interface and gets Entra ID groups by name or returns all groups

    .PARAMETER GroupName
    Optional filter by group display name (exact match)

    .PARAMETER SearchTerm
    Optional search term to find groups containing this text

    .PARAMETER GraphApiVersion
    Graph API version to use (default: beta)

    .EXAMPLE
    Get-EntraGroup -GroupName "Intune-Dev-Users"
    Returns the specific group with exact name match

    .EXAMPLE
    Get-EntraGroup -SearchTerm "Intune"
    Returns all groups containing "Intune" in their name

    .EXAMPLE
    Get-EntraGroup
    Returns all groups (use with caution in large tenants)

    .NOTES
    NAME: Get-EntraGroup
    #>
    
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Enter group name to search for")]
        [string]$GroupName,

        [ValidateSet('beta', 'v1.0')]
        [string]$GraphApiVersion = "beta"
    )

    try {

        if ($GroupName) {
            # Search for groups starting with provided name
            $uri = "https://graph.microsoft.com/$GraphApiVersion/groups?`$filter=startswith(displayName,'$GroupName')"
        } else {
            # Get all groups (use with caution)
            $uri = "https://graph.microsoft.com/$GraphApiVersion/groups"
        }

        $result = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject

        if ($result.value -and $result.value.Count -gt 0) {
            return $result.value
        } else {
            return $null
        }

    } catch {
        $ex = $_.Exception
        $responseBody = ""

        # Check if we have a response and response stream
        if ($ex.Response -and $ex.Response.GetResponseStream) {
            try {
                $errorResponse = $ex.Response.GetResponseStream()
                if ($errorResponse) {
                    $reader = New-Object System.IO.StreamReader($errorResponse)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $responseBody = $reader.ReadToEnd()
                }
            } catch {
                $responseBody = "Unable to read error response stream"
            }
        }

        if ($responseBody) {
            Write-Host "Response content:`n$responseBody" -f Red
        }

        if ($ex.Response) {
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        } else {
            Write-Error "Request failed: $($ex.Message)"
        }

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Error getting group: $($ex.Message)" -Level Error
        } else {
            Write-Output "Error getting group: $($ex.Message)"
        }

        throw
    }
}