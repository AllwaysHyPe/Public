# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome

function Get-DeviceConfigurationPolicyAssignment() {
    <#
        .SYNOPSIS
        This function is used to dynamically get device configuration policy assignment from the Graph API REST interface

        .DESCRIPTION
        The function connects to the Graph API Interface and dynamically gets any device configuration policy assignment

        .PARAMETER id
        Enter id (guid) for the Device Configuration Policy you want to check assignment (optional - if not provided, gets all policies)

        .PARAMETER Category
        Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, SettingsCatalog, etc)

        .PARAMETER Name
        Optional filter by policy name

        .EXAMPLE
        Get-DeviceConfigurationPolicyAssignment -Category "DeviceConfiguration"
        Returns all device configuration policies and their assignments

        .EXAMPLE
        Get-DeviceConfigurationPolicyAssignment -id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"
        Returns assignments for a specific device configuration policy

        .NOTES
        NAME: Get-DeviceConfigurationPolicyAssignment
        Author: Hailey Phillips
        Version: 0.0.1
        Modified: 2025-07-23

        Adapted from Intune management functions by Andrew Taylor (https://github.com/andrew-s-taylor/public).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, HelpMessage = "Enter id (guid) for the Device Configuration Policy you want to check assignment")]
        $id,

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

    # Set assignment endpoint based on category
    $assignmentEndpoint = switch ($Category) {
        'DeviceConfiguration' { "groupAssignments" }
        default { "assignments" }
    }

    $displayNameProperty = switch ($Category) {
        'DeviceConfigurationSC' { 'name' }
        default { 'displayName' }
    }

    try {
        # If specific ID is provided, get assignments for that policy only
        if ($id) {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$id/$assignmentEndpoint"
            $PolicyAssignments = (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value
            $AssignedGroups = @()

            foreach ($Assignment in $PolicyAssignments) {
                # Handle different assignment structures based on category
                $GroupId = switch ($Category) {
                    'DeviceConfiguration' { $Assignment.targetGroupId }
                    default { $Assignment.target.groupId }
                }

                if ($GroupId) {
                    try {
                        $GroupDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -OutputType PSObject
                        $AssignedGroups += [PSCustomObject]@{
                            Id           = $GroupId
                            Name         = $GroupDetails.displayName
                            Description  = $GroupDetails.description
                            ExcludeGroup = $Assignment.excludeGroup
                        }
                        Write-Host "Policy is assigned to: $($GroupDetails.displayName)" -Level Info
                    } catch {
                        Write-Log "Unable to get details for group ID: $GroupId" -Level Warning
                    }
                }
            }
            return $AssignedGroups
        }
        # If no ID provided, get all policies of this type and their assignments
        else {
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
            $AllPolicies = (Invoke-MgGraphRequest -Uri $uri -Method Get -OutputType PSObject).Value

            $PolicyResults = @()
            foreach ($Policy in $AllPolicies) {
                # Get assignments for each policy
                $assignmentUri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)/$($Policy.id)/$assignmentEndpoint"
                try {
                    $PolicyAssignments = (Invoke-MgGraphRequest -Uri $assignmentUri -Method Get -OutputType PSObject).Value
                    $AssignedGroups = @()

                    foreach ($Assignment in $PolicyAssignments) {
                        $GroupId = switch ($Category) {
                            'DeviceConfiguration' { $Assignment.targetGroupId }
                            default { $Assignment.target.groupId }
                        }

                        if ($GroupId) {
                            try {
                                $GroupDetails = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -OutputType PSObject
                                $AssignedGroups += [PSCustomObject]@{
                                    Id          = $GroupId
                                    Name        = $GroupDetails.displayName
                                    Description = $GroupDetails.description
                                    TargetType  = $Assignment.target.'@odata.type' -or 'groupAssignmentTarget'
                                }
                                Write-Host "Policy is assigned to: $($GroupDetails.displayName)"
                            } catch {
                                Write-Log "Unable to get details for group ID: $GroupId" -Level Warning
                            }
                        }
                    }

                    $PolicyResults += [PSCustomObject]@{
                        PolicyId          = $Policy.id
                        PolicyName        = $Policy.$displayNameProperty
                        PolicyDescription = $Policy.description
                        Category          = $Category
                        AssignedGroups    = $AssignedGroups.Name
                        AssignmentCount   = $AssignedGroups.Count
                    }
                } catch {
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log "Unable to get assignments for policy: $($Policy.$displayNameProperty)" -Level Warning
                    }
                }
            }
            return $PolicyResults
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
        Write-Host
        break
    }
} # end function Get-DeviceConfigurationPolicyAssignment