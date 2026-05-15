function Get-EntraGroup {
    <#
    .SYNOPSIS
    This function is used to get Entra ID groups from the Graph API REST interface.

    .DESCRIPTION
    The function connects to the Graph API Interface and gets Entra ID groups by
    exact name, group ID, search term, or returns all groups.

    .PARAMETER GroupName
    Filter by group display name (exact match).

    .PARAMETER GroupId
    Filter by group ID (exact match).

    .PARAMETER SearchTerm
    Search term to find groups whose display name contains this text.

    .PARAMETER GraphApiVersion
    Graph API version to use. Defaults to beta.

    .EXAMPLE
    Get-EntraGroup -GroupName "Dev-Workstations"

    .EXAMPLE
    Get-EntraGroup -GroupId "12345678-1234-1234-1234-123456789012"

    .EXAMPLE
    Get-EntraGroup -SearchTerm "Dev"

    .EXAMPLE
    Get-EntraGroup

    .NOTES
    NAME: Get-EntraGroup
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$GroupName,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$GroupId,

        [Parameter(Mandatory = $false)]
        [string]$SearchTerm,

        [Parameter(Mandatory = $false)]
        [ValidateSet('beta', 'v1.0')]
        [string]$GraphApiVersion = "beta"
    )

    $uri = switch ($true) {
        { $GroupId } { "https://graph.microsoft.com/$GraphApiVersion/groups/$GroupId" }

        { $GroupName } { "https://graph.microsoft.com/$GraphApiVersion/groups?`$filter=displayName eq '$GroupName'&`$select=id,displayName,description" }

        { $SearchTerm } { "https://graph.microsoft.com/$GraphApiVersion/groups?`$search=`"displayName:$SearchTerm`"&`$select=id,displayName,description" }

        default { "https://graph.microsoft.com/$GraphApiVersion/groups?`$select=id,displayName,description" }
    }

    $graphParams = @{
        Uri        = $uri
        Method     = "GET"
        OutputType = "PSObject"
    }

    if ($SearchTerm) {
        $graphParams["Headers"] = @{ ConsistencyLevel = "eventual" }
    }

    try {
        $result = Invoke-MgGraphRequest @graphParams

        if ($GroupId) {
            # Direct resource lookup returns the object directly, not wrapped in value
            if ($result) {
                Write-Log -Message "Found group: $($result.displayName)" -Severity Info
                return $result
            } else {
                Write-Log -Message "Group not found: $GroupId" -Severity Warn
                return $null
            }
        } elseif ($GroupName) {
            if ($result.value -and $result.value.Count -gt 0) {
                Write-Log -Message "Found group: $GroupName" -Severity Info
                return $result.value[0]
            } else {
                Write-Log -Message "Group not found: $GroupName" -Severity Warn
                return $null
            }
        } else {
            Write-Log -Message "Found $($result.value.Count) groups" -Severity Info
            return $result.value
        }

    } catch {
        if ($_.Exception.Message -like "*NotFound*") {
            Write-Log -Message "Group not found — may have been deleted" -Severity Warn
        } else {
            Write-Log -Message "Error getting Entra group" -Severity Error
        }
        throw
    }
}