# Import module
Import-Module Microsoft.Graph.Authentication

# Connect to Graph
Connect-MgGraph -NoWelcome

function Get-DeviceConfigurationPolicyAssignment {
    <#
    .SYNOPSIS
    This function is used to dynamically get device configuration policy assignment from the Graph API REST interface.

    .DESCRIPTION
    The function connects to the Graph API Interface and dynamically gets any device configuration policy assignment.
    Uses Get-EntraGroup to resolve group details and Graph batch requests for performance.

    .PARAMETER Id
    Enter id (guid) for the Device Configuration Policy you want to check assignment.

    .PARAMETER Category
    Category of policy (AutopilotProfile, ApplicationProtection, ConditionalAccess, CompliancePolicies, DeviceConfiguration, DeviceConfigurationSC).

    .EXAMPLE
    Get-DeviceConfigurationPolicyAssignment -Category "DeviceConfiguration"

    .EXAMPLE
    Get-DeviceConfigurationPolicyAssignment -Id "12345678-1234-1234-1234-123456789012" -Category "DeviceConfiguration"

    .NOTES
    NAME: Get-DeviceConfigurationPolicyAssignment
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('AutopilotProfile', 'ApplicationProtection', 'ConditionalAccess', 'CompliancePolicies', 'DeviceConfiguration', 'DeviceConfigurationSC')]
        [string]$Category,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ $_ -match '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$' })]
        [string]$Id
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

    try {
        if ($Id) {
            $graphParams = @{
                Uri        = "https://graph.microsoft.com/$graphApiVersion/$DCP_resource/$Id/assignments"
                Method     = "GET"
                OutputType = "PSObject"
            }

            $PolicyAssignments = (Invoke-MgGraphRequest @graphParams).Value

            # Build group lookup table upfront from unique group IDs
            $GroupTable = @{}
            foreach ($Assignment in $PolicyAssignments) {
                $GroupId = $Assignment.target.groupId
                if ($GroupId -and -not $GroupTable.ContainsKey($GroupId)) {
                    try {
                        $GroupTable[$GroupId] = Get-EntraGroup -GroupId $GroupId
                    } catch {
                        Write-Log -Message "Group '$GroupId' not found — may have been deleted" -Severity Warn
                        $GroupTable[$GroupId] = $null
                    }
                }
            }

            Write-Log -Message "Resolved $($GroupTable.Count) unique group(s) for $Category policy" -Severity Info

            # Build assignments using the group lookup table
            $AssignedGroups = [ordered]@{}
            foreach ($Assignment in $PolicyAssignments) {
                $GroupId = $Assignment.target.groupId

                if ($GroupId -and -not $AssignedGroups.Contains($GroupId)) {
                    $GroupDetails = $GroupTable[$GroupId]

                    $AssignmentType = switch ($Assignment.target.'@odata.type') {
                        '#microsoft.graph.exclusionGroupAssignmentTarget' { "Exclude" }
                        default { "Include" }
                    }

                    $AssignedGroups[$GroupId] = [PSCustomObject]@{
                        Id             = $GroupId
                        Name           = if ($GroupDetails) { $GroupDetails.displayName } else { "Deleted Group" }
                        Description    = if ($GroupDetails) { $GroupDetails.description } else { $null }
                        AssignmentType = $AssignmentType
                        Intent         = $Assignment.intent
                        Source         = $Assignment.source
                        SourceId       = $Assignment.sourceId
                        FilterId       = $Assignment.target.deviceAndAppManagementAssignmentFilterId
                        FilterType     = $Assignment.target.deviceAndAppManagementAssignmentFilterType
                    }
                }
            }

            return $AssignedGroups.Values

        } else {
            $graphParams = @{
                Uri        = "https://graph.microsoft.com/$graphApiVersion/$DCP_resource"
                Method     = "GET"
                OutputType = "PSObject"
            }

            $AllPolicies = (Invoke-MgGraphRequest @graphParams).Value
            Write-Log -Message "Retrieving assignments for $($AllPolicies.Count) $Category policies" -Severity Info

            # Build batch requests
            $batches = [System.Collections.Generic.List[object]]::new()
            $batchRequests = [System.Collections.Generic.List[object]]::new()
            $batchIndex = 1

            foreach ($Policy in $AllPolicies) {
                $batchRequests.Add(@{
                        id     = "$batchIndex"
                        method = "GET"
                        url    = "/$DCP_resource/$($Policy.id)/assignments"
                    })

                if ($batchRequests.Count -eq 20) {
                    $batches.Add($batchRequests.ToArray())
                    $batchRequests = [System.Collections.Generic.List[object]]::new()
                }

                $batchIndex++
            }

            if ($batchRequests.Count -gt 0) {
                $batches.Add($batchRequests.ToArray())
            }

            # Execute batch requests
            $allResponses = [System.Collections.Generic.List[object]]::new()
            foreach ($batch in $batches) {
                $batchParams = @{
                    Uri         = "https://graph.microsoft.com/$graphApiVersion/`$batch"
                    Method      = "POST"
                    Body        = (@{ requests = $batch } | ConvertTo-Json -Depth 5)
                    ContentType = "application/json"
                    OutputType  = "PSObject"
                }
                $batchResponse = Invoke-MgGraphRequest @batchParams
                $allResponses.AddRange($batchResponse.responses)
            }

            # Build group lookup table upfront from all unique group IDs across all policies
            $GroupTable = @{}
            foreach ($response in $allResponses) {
                if ($response.status -eq 200) {
                    foreach ($Assignment in $response.body.value) {
                        $GroupId = $Assignment.target.groupId
                        if ($GroupId -and -not $GroupTable.ContainsKey($GroupId)) {
                            try {
                                $GroupTable[$GroupId] = Get-EntraGroup -GroupId $GroupId
                            } catch {
                                Write-Log -Message "Group '$GroupId' not found — may have been deleted" -Severity Warn
                                $GroupTable[$GroupId] = $null
                            }
                        }
                    }
                }
            }

            Write-Log -Message "Resolved $($GroupTable.Count) unique group(s) across all $Category policies" -Severity Info

            # Map responses back to policies using the group lookup table
            $PolicyResults = [ordered]@{}
            for ($i = 0; $i -lt $AllPolicies.Count; $i++) {
                $Policy = $AllPolicies[$i]
                $response = $allResponses | Where-Object id -EQ "$($i + 1)"

                $AssignedGroups = [ordered]@{}

                if ($response.status -eq 200) {
                    foreach ($Assignment in $response.body.value) {
                        $GroupId = $Assignment.target.groupId

                        if ($GroupId -and -not $AssignedGroups.Contains($GroupId)) {
                            $GroupDetails = $GroupTable[$GroupId]

                            $AssignmentType = switch ($Assignment.target.'@odata.type') {
                                '#microsoft.graph.exclusionGroupAssignmentTarget' { "Exclude" }
                                default { "Include" }
                            }

                            $AssignedGroups[$GroupId] = [PSCustomObject]@{
                                Id             = $GroupId
                                Name           = if ($GroupDetails) { $GroupDetails.displayName } else { "Deleted Group" }
                                Description    = if ($GroupDetails) { $GroupDetails.description } else { $null }
                                AssignmentType = $AssignmentType
                                Intent         = $Assignment.intent
                                Source         = $Assignment.source
                                SourceId       = $Assignment.sourceId
                                FilterId       = $Assignment.target.deviceAndAppManagementAssignmentFilterId
                                FilterType     = $Assignment.target.deviceAndAppManagementAssignmentFilterType
                            }
                        }
                    }
                } else {
                    Write-Log -Message "Failed to retrieve assignments for policy: $($Policy.$displayNameProperty)" -Severity Warn
                }

                $PolicyResults[$Policy.id] = [PSCustomObject]@{
                    PolicyId          = $Policy.id
                    PolicyName        = $Policy.$displayNameProperty
                    PolicyDescription = $Policy.description
                    Category          = $Category
                    AssignedGroups    = $AssignedGroups.Values
                    AssignmentCount   = $AssignedGroups.Count
                }
            }

            Write-Log -Message "Retrieved assignments for $($PolicyResults.Count) $Category policies" -Severity Info
            return $PolicyResults.Values
        }

    } catch {
        Write-Log -Message "Error retrieving $Category policy assignments" -Severity Error
        throw
    }
}   # end function Get-DeviceConfigurationPolicyAssignment