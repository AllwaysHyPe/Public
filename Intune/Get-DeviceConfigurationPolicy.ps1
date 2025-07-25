
# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome

function Get-DeviceConfigurationPolicy {
    <#
        .SYNOPSIS
        This function is used to dynamically get device configuration policy from the Graph API REST interface

        .DESCRIPTION
        The function connects to the Graph API Interface and dynamically gets any device configuration policies

        .PARAMETER Category
        Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

        .PARAMETER Name
        Optional filter by policy name

        .EXAMPLE
        Get-DeviceConfigurationPolicy -Category "DeviceConfiguration"
        Returns any device configuration policies configured in Intune

        .EXAMPLE
        Get-DeviceConfigurationPolicy -Category "DeviceConfigurationSC" -name "Security Baseline"
        Returns Settings Catalog policies with the specified name
        
        .NOTES
        NAME: Get-DeviceConfigurationPolicy
        Author: Hailey Phillips
        Version: 0.0.1
        Modified: 2025-07-23

        Adapted from Intune management functions by Andrew Taylor (https://github.com/andrew-s-taylor/public).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'ApplicationProtection', 'ConditionalAccess', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', '*')]
        [string]$Category

    )

    $graphApiVersion = "beta"

    # Dynamically setting Graph resource path based off of category
    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        default { throw "Unknown category: $Category" }
    }

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        if ($Name) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)?`$filter=$displayNameProperty eq '$name'"
            (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
        } else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
            (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
        }
    } catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        Write-Host
        break
    }

} # end function et-DeviceConfigurationPolicy
