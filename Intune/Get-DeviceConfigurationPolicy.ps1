
# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome

function Get-DeviceConfigurationPolicy {
    <#
    .SYNOPSIS
    This function is used to dynamically get device configuration policy from the Graph API REST interface.

    .DESCRIPTION
    The function connects to the Graph API Interface and dynamically gets any device configuration policies.

    .PARAMETER Category
    Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, DeviceConfigurationSC).

    .PARAMETER Name
    Optional filter by policy name.

    .EXAMPLE
    Get-DeviceConfigurationPolicy -Category "DeviceConfiguration"

    .EXAMPLE
    Get-DeviceConfigurationPolicy -Category "DeviceConfigurationSC" -Name "Security Baseline"

    .NOTES
    NAME: Get-DeviceConfigurationPolicy
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'ApplicationProtection', 'ConditionalAccess', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC')]
        [string]$Category,

        [Parameter(Mandatory = $false)]
        [string]$Name
    )

    $graphApiVersion = "beta"

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
    }

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    $graphParams = @{
        Uri        = "https://graph.microsoft.com/$graphApiVersion/$DCP_resource"
        Method     = "GET"
        OutputType = "PSObject"
    }

    try {
        $result = (Invoke-MgGraphRequest @graphParams).Value

        if ($Name) {
            $result = $result | Where-Object { $_.$displayNameProperty -eq $Name }
            if ($result) {
                Write-Log -Message "Found policy: $Name" -Severity Info
            } else {
                Write-Log -Message "Policy not found: $Name" -Severity Warn
            }
        } else {
            Write-Log -Message "Found $($result.Count) $Category policies" -Severity Info
        }

        return $result

    } catch {
        Write-Log -Message "Error retrieving $Category policies" -Severity Error
        throw
    }

} # end function Get-DeviceConfigurationPolicy