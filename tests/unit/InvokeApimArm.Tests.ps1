$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repoRoot 'ApimAssessment.psd1') -Force

AfterAll {
    Remove-Module -Name ApimAssessment -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-ApimArm safety and transport behavior' {
    InModuleScope ApimAssessment {
        BeforeEach {
            Mock Invoke-ApimArmRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{}'
                }
            }
            Mock Start-Sleep
        }

        It 'rejects non-GET methods before invoking the transport' {
            {
                Invoke-ApimArm -Uri '/subscriptions/example/resourceGroups/example' `
                    -Method DELETE
            } | Should -Throw '*method*prohibited*'

            Should -Invoke Invoke-ApimArmRequest -Times 0 -Exactly
        }

        It 'allows POST only for the Cost Management query endpoint' {
            $uri = '/subscriptions/00000000-0000-0000-0000-000000000001/providers/' +
                'Microsoft.CostManagement/query?api-version=2023-11-01'

            {
                Invoke-ApimArm -Uri $uri -Method POST -Body @{ type = 'ActualCost' }
            } | Should -Not -Throw

            Should -Invoke Invoke-ApimArmRequest -Times 1 -Exactly `
                -ParameterFilter {
                    $Method -eq 'POST' -and $Body -match 'ActualCost'
                }
        }

        It 'rejects POST when the Cost Management path appears only in a query value' {
            $uri = '/subscriptions/example/providers/Microsoft.Example/widgets' +
                '?redirect=/providers/Microsoft.CostManagement/query'

            { Invoke-ApimArm -Uri $uri -Method POST } |
                Should -Throw '*method*prohibited*'
            Should -Invoke Invoke-ApimArmRequest -Times 0 -Exactly
        }

        It 'rejects prohibited URL patterns including encoded forms' -TestCases @(
            @{ Uri = '/providers/Microsoft.ApiManagement/listSecrets' }
            @{ Uri = '/providers/Microsoft.ApiManagement/listValue' }
            @{ Uri = '/providers/Microsoft.ApiManagement/listKeys' }
            @{ Uri = '/providers/Microsoft.KeyVault/vaults/example/secrets/item' }
            @{ Uri = '/providers/example/regenerate?api-version=1' }
            @{ Uri = '/providers/example/items?token=value' }
            @{ Uri = '/providers/example/list%53ecrets' }
        ) {
            { Invoke-ApimArm -Uri $Uri } | Should -Throw '*URL*prohibited*'
            Should -Invoke Invoke-ApimArmRequest -Times 0 -Exactly
        }

        It 'rejects non-HTTPS and non-ARM absolute endpoints' -TestCases @(
            @{
                Uri = 'http://management.azure.com/subscriptions/example'
                Expected = '*approved Azure Resource Manager endpoint*'
            }
            @{
                Uri = 'https://example.invalid/subscriptions/example'
                Expected = '*approved Azure Resource Manager endpoint*'
            }
            @{
                Uri = 'relative/without/leading/slash'
                Expected = '*relative ARM path*'
            }
            @{
                Uri = '//example.invalid/subscriptions/example'
                Expected = '*relative ARM path*'
            }
            @{
                Uri = 'https://management.azure.com:444/subscriptions/example'
                Expected = '*approved Azure Resource Manager endpoint*'
            }
            @{
                Uri = 'https://user@management.azure.com/subscriptions/example'
                Expected = '*approved Azure Resource Manager endpoint*'
            }
        ) {
            { Invoke-ApimArm -Uri $Uri } | Should -Throw $Expected
            Should -Invoke Invoke-ApimArmRequest -Times 0 -Exactly
        }

        It 'allows an approved absolute Azure Resource Manager endpoint' {
            {
                Invoke-ApimArm -Uri (
                    'https://management.azure.com/subscriptions/example' +
                    '?api-version=2024-01-01'
                )
            } | Should -Not -Throw
            Should -Invoke Invoke-ApimArmRequest -Times 1 -Exactly
        }

        It 'follows nextLink and combines collection values in order' {
            Mock Invoke-ApimArmRequest {
                if ($Uri -eq '/first') {
                    return [pscustomobject]@{
                        StatusCode = 200
                        Headers    = @{}
                        Content    = '{"value":[{"id":"one"}],"nextLink":"/second"}'
                    }
                }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{"value":[{"id":"two"}]}'
                }
            }

            $result = Invoke-ApimArm -Uri '/first'

            $result.value.Count | Should -Be 2
            $result.value[0].id | Should -Be 'one'
            $result.value[1].id | Should -Be 'two'
            Should -Invoke Invoke-ApimArmRequest -Times 2 -Exactly
        }

        It 'validates every nextLink before invoking it' {
            Mock Invoke-ApimArmRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{"value":[],"nextLink":"/next?token=secret"}'
                }
            }

            { Invoke-ApimArm -Uri '/first' } | Should -Throw '*URL*prohibited*'
            Should -Invoke Invoke-ApimArmRequest -Times 1 -Exactly
        }

        It 'retries 429 responses and honors Retry-After' {
            $script:attempt = 0
            Mock Invoke-ApimArmRequest {
                $script:attempt++
                if ($script:attempt -eq 1) {
                    return [pscustomobject]@{
                        StatusCode = 429
                        Headers    = @{ 'Retry-After' = '7' }
                        Content    = '{"error":{"code":"TooManyRequests"}}'
                    }
                }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{"ok":true}'
                }
            }

            $result = Invoke-ApimArm -Uri '/retry'

            $result.ok | Should -BeTrue
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 7
            }
            Should -Invoke Invoke-ApimArmRequest -Times 2 -Exactly
        }

        It 'retries HTTP failures returned as transport exceptions' {
            $script:attempt = 0
            Mock Invoke-ApimArmRequest {
                $script:attempt++
                if ($script:attempt -eq 1) {
                    $exception = [System.Exception]::new('synthetic transport failure')
                    $exception | Add-Member -MemberType NoteProperty -Name Response `
                        -Value ([pscustomobject]@{
                            StatusCode = 503
                            Headers    = @{ 'Retry-After' = '1' }
                        })
                    throw $exception
                }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{"ok":true}'
                }
            }

            $result = Invoke-ApimArm -Uri '/retry'

            $result.ok | Should -BeTrue
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 1
            }
        }

        It 'does not expose transport exception text when no status is available' {
            Mock Invoke-ApimArmRequest {
                throw [System.Exception]::new(
                    'customer-host.example.invalid contained a private identifier'
                )
            }

            {
                Invoke-ApimArm -Uri '/failure'
            } | Should -Throw '*before a usable response was received*'
        }

        It 'honors Cost Management retry headers' {
            $script:attempt = 0
            Mock Invoke-ApimArmRequest {
                $script:attempt++
                if ($script:attempt -eq 1) {
                    return [pscustomobject]@{
                        StatusCode = 429
                        Headers    = @{
                            'x-ms-ratelimit-microsoft.costmanagement-entity-retry-after' = '9'
                        }
                        Content    = '{}'
                    }
                }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{}'
                }
            }

            Invoke-ApimArm -Uri (
                '/subscriptions/id/providers/Microsoft.CostManagement/' +
                'query?api-version=2023-11-01'
            ) -Method POST -Body '{}' | Out-Null

            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 9
            }
        }

        It 'uses exponential fallback for retryable server errors' {
            $script:attempt = 0
            Mock Invoke-ApimArmRequest {
                $script:attempt++
                if ($script:attempt -lt 3) {
                    return [pscustomobject]@{
                        StatusCode = 503
                        Headers    = @{}
                        Content    = '{}'
                    }
                }
                return [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{}'
                }
            }

            Invoke-ApimArm -Uri '/retry' -InitialDelaySeconds 2 | Out-Null

            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 2
            }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                $Seconds -eq 4
            }
        }

        It 'does not retry a non-retryable response' {
            Mock Invoke-ApimArmRequest {
                [pscustomobject]@{
                    StatusCode = 400
                    Headers    = @{}
                    Content    = '{"error":{"code":"BadRequest"}}'
                }
            }

            {
                Invoke-ApimArm -Uri '/bad'
            } | Should -Throw '*HTTP status 400 after 1 attempt*'
            Should -Invoke Start-Sleep -Times 0 -Exactly
            Should -Invoke Invoke-ApimArmRequest -Times 1 -Exactly
        }

        It 'stops after the configured maximum attempts' {
            Mock Invoke-ApimArmRequest {
                [pscustomobject]@{
                    StatusCode = 500
                    Headers    = @{}
                    Content    = '{}'
                }
            }

            {
                Invoke-ApimArm -Uri '/failing' -MaxAttempts 3 `
                    -InitialDelaySeconds 0
            } | Should -Throw '*HTTP status 500 after 3 attempt*'
            Should -Invoke Invoke-ApimArmRequest -Times 3 -Exactly
        }

        It 'fails explicitly when a successful response is not valid JSON' {
            Mock Invoke-ApimArmRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{}
                    Content    = '{not-json'
                }
            }

            {
                Invoke-ApimArm -Uri '/malformed'
            } | Should -Throw '*not valid JSON*'
        }
    }
}
