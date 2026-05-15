# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome
function Get-DeviceConfigurationPolicyStatus {
    <#
    .SYNOPSIS
    This function is used to get device configuration policy status from the Graph API REST interface.

    .DESCRIPTION
    The function connects to the Graph API Interface and gets device configuration policy status
    with summary counts, using Graph batch requests for performance.

    .PARAMETER Id
    Enter id (guid) for the Device Configuration Policy you want to check status.

    .PARAMETER Category
    Category of policy (AutopilotProfile, CompliancePolicies, DeviceConfiguration, DeviceConfigurationSC, ApplicationProtection, ConditionalAccess).

    .EXAMPLE
    Get-DeviceConfigurationPolicyStatus -Id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"

    .NOTES
    NAME: Get-DeviceConfigurationPolicyStatus
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC', 'ApplicationProtection', 'ConditionalAccess')]
        [string]$Category,
        [string]$graphApiVersion = 'beta'
    )

    $DCP_resource = switch ($Category) {
        'AutopilotProfile' { 'deviceManagement/windowsAutopilotDeploymentProfiles' }
        'CompliancePolicies' { 'deviceManagement/deviceCompliancePolicies' }
        'DeviceConfiguration' { 'deviceManagement/deviceConfigurations' }
        'DeviceConfigurationSC' { 'deviceManagement/configurationPolicies' }
        'ApplicationProtection' { 'deviceAppManagement/managedAppPolicies' }
        'ConditionalAccess' { 'identity/conditionalAccess/policies' }
    }

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    # Batch policy details and device statuses into a single request
    $batchParams = @{
        Uri         = "https://graph.microsoft.com/$graphApiVersion/`$batch"
        Method      = 'POST'
        ContentType = 'application/json'
        OutputType  = 'PSObject'
        Body        = (@{
                requests = @(
                    @{
                        id     = '1'
                        method = 'GET'
                        url    = "/$DCP_resource/$Id"
                    },
                    @{
                        id     = '2'
                        method = 'GET'
                        url    = "/$DCP_resource/$Id/deviceStatuses"
                    }
                )
            } | ConvertTo-Json -Depth 5)
    }

    try {
        $batchResponse = Invoke-MgGraphRequest @batchParams

        $policyResponse = $batchResponse.responses | Where-Object id -EQ '1'
        $statusResponse = $batchResponse.responses | Where-Object id -EQ '2'

        if ($policyResponse.status -ne 200) {
            Write-Log -Message "Failed to retrieve policy details for '$Id' (status $($policyResponse.status))" -Severity Warn
            return $null
        }

        if ($statusResponse.status -ne 200) {
            Write-Log -Message "Failed to retrieve device statuses for '$Id' (status $($statusResponse.status))" -Severity Warn
            return $null
        }

        $PolicyDetails = $policyResponse.body
        $DeviceStatuses = $statusResponse.body.value

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

        Write-Log -Message "Policy '$($PolicyDetails.$displayNameProperty)' ($Category) — $($StatusCounts.Total) devices, $SuccessRate% success" -Severity Info

        [PSCustomObject]@{
            PolicyId             = $Id
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
        Write-Log -Message "Error retrieving $Category policy status" -Severity Error
        throw
    }
}