# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome

function Get-DeviceConfigurationPolicyStatus() {
    <#
        .SYNOPSIS
        This function is used to get device configuration policy status from the Graph API REST interface

        .DESCRIPTION
        The function connects to the Graph API Interface and gets device configuration policy status with summary counts

        .PARAMETER id
        Enter id (guid) for the Device Configuration Policy you want to check status

        .PARAMETER Category
        Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

        .EXAMPLE
        Get-DeviceConfigurationPolicyStatus -id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"
        Returns device configuration policy status and summary statistics

        .NOTES
        NAME: Get-DeviceConfigurationPolicyStatus
        Author: Hailey Phillips
        Version: 0.0.1
        Modified: 2025-07-23

        Adapted from Intune management functions by Andrew Taylor (https://github.com/andrew-s-taylor/public).
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter id (guid) for the Device Configuration Policy you want to check status")]
        $id,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', 'ApplicationProtection', 'ConditionalAccess')]
        [string]$Category
    )

    $graphApiVersion = "Beta"

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { "deviceManagement/windowsAutopilotDeploymentProfiles" }
        'CompliancePolicies' { "deviceManagement/deviceCompliancePolicies" }
        'DeviceConfiguration' { "deviceManagement/deviceConfigurations" }
        'DeviceConfigurationSC' { "deviceManagement/configurationPolicies" }
        'ApplicationProtection' { "deviceAppManagement/managedAppPolicies" }
        'ConditionalAccess' { "identity/conditionalAccess/policies" }
        default { throw "Unknown category: $Category" }
    }

    # Handle different property names for display name
    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        # Get policy details for display name
        $policyUri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id"
        $PolicyDetails = Invoke-MgGraphRequest -Uri $policyUri -Method GET -OutputType PSObject

        # Get device statuses
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id/deviceStatuses"
        $DeviceStatuses = (Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject).value

        # Count statuses based on Intune values
        $StatusCounts = @{
            Total         = $DeviceStatuses.Count
            Succeeded     = ($DeviceStatuses | Where-Object status -EQ 'compliant').Count
            Error         = ($DeviceStatuses | Where-Object status -EQ 'error').Count
            Conflict      = ($DeviceStatuses | Where-Object status -EQ 'conflict').Count
            NotApplicable = ($DeviceStatuses | Where-Object status -EQ 'notApplicable').Count
            Pending       = ($DeviceStatuses | Where-Object { $_.status -in @('pending', 'unknown') }).Count
        }

        $SuccessRate = if ($StatusCounts.Total -gt 0) {
            [Math]::Round(($StatusCounts.Succeeded / $StatusCounts.Total) * 100, 2)
        } else { 0 }

        # Return summary object
        [PSCustomObject]@{
            PolicyId             = $id
            DisplayName          = $PolicyDetails.$displayNameProperty
            Category             = $Category
            TotalDevices         = $StatusCounts.Total
            SuccessfulDevices    = $StatusCounts.Succeeded
            ErrorDevices         = $StatusCounts.Error
            ConflictDevices      = $StatusCounts.Conflict
            NotApplicableDevices = $StatusCounts.NotApplicable
            PendingDevices       = $StatusCounts.Pending
            SuccessRate          = $SuccessRate
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
}