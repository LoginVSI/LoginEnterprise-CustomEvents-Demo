#Requires -Version 5.0
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplianceUrl,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiKey,
    
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[a-zA-Z0-9\-]+$')]
    [string]$SessionId,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 4096)]
    [string]$Message,
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = "v8-preview", 
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableLogging,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\LECustomEvents.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 5)]
    [int]$MaxRetries = 2,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(5, 60)]
    [int]$TimeoutSeconds = 10
)

# Script metadata
$ScriptVersion = "1.3.0"
$ErrorActionPreference = 'Continue'

# Logging function that outputs to both console and file
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Output to console with color coding
    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
        'DEBUG'   { Write-Host $logEntry -ForegroundColor Gray }
        default   { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Also write to file if logging enabled
    if ($EnableLogging) {
        try {
            Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
        } catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }
}

# Get sanitized command line for logging
function Get-SanitizedCommandLine {
    # Get the actual command line from the environment
    $fullCommandLine = [Environment]::CommandLine
    
    # If that fails, build it from PSBoundParameters
    if (-not $fullCommandLine -or $fullCommandLine -eq "") {
        $params = @()
        foreach ($key in $PSBoundParameters.Keys) {
            $value = $PSBoundParameters[$key]
            if ($key -eq 'ApiKey') {
                $params += "-$key ********"
            } elseif ($value -is [switch]) {
                if ($value) { $params += "-$key" }
            } else {
                $params += "-$key `"$value`""
            }
        }
        $fullCommandLine = "$($MyInvocation.MyCommand.Name) " + ($params -join ' ')
    } else {
        # Sanitize the API key in the full command line
        $patterns = @(
            '(-ApiKey\s+)("[^"]*")',
            "(-ApiKey\s+)('[^']*')",
            '(-ApiKey\s+)([^\s]+)'
        )
        
        foreach ($pattern in $patterns) {
            if ($fullCommandLine -match $pattern) {
                $fullCommandLine = $fullCommandLine -replace $pattern, '$1********'
                break
            }
        }
    }
    
    return $fullCommandLine
}

# Initialize logging
if ($EnableLogging) {
    try {
        $logDir = Split-Path $LogPath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value "`n========================================" -Encoding UTF8
    } catch {
        Write-Host "Warning: Could not initialize log file: $_" -ForegroundColor Yellow
        $EnableLogging = $false
    }
}

Write-Log "Send-LECustomEvent v$ScriptVersion - Starting execution" -Level INFO
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level DEBUG

# Log the actual command line
$sanitizedCmd = Get-SanitizedCommandLine
Write-Log "Command line: $sanitizedCmd" -Level INFO

try {
    # Build the full API URL
    $baseUrl = $ApplianceUrl.TrimEnd('/')
    if ($baseUrl -notmatch '^https?://') {
        throw "Invalid URL format. Must start with http:// or https://"
    }
    
    $fullUrl = "$baseUrl/publicApi/$ApiVersion/user-sessions/$SessionId/events"
    Write-Log "Target endpoint: $fullUrl" -Level INFO
    Write-Log "API Version: $ApiVersion" -Level DEBUG
    
    # Prepare request
    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Content-Type" = "application/json"
        "Accept" = "application/json"
    }
    
    $body = @{
        description = $Message
    } | ConvertTo-Json -Compress
    
    Write-Log "Message length: $($Message.Length) characters" -Level DEBUG
    Write-Log "Request body: $body" -Level DEBUG
    
    # Execute with retry logic
    $attempt = 0
    $success = $false
    $lastError = $null
    
    while ($attempt -le $MaxRetries -and -not $success) {
        if ($attempt -gt 0) {
            $waitTime = [Math]::Pow(2, $attempt - 1)  # Exponential backoff: 1, 2, 4 seconds
            Write-Log "Retry $attempt/$MaxRetries after $waitTime seconds..." -Level WARNING
            Start-Sleep -Seconds $waitTime
        }
        
        $attempt++
        
        try {
            Write-Log "Sending request (attempt $attempt)..." -Level INFO
            
            # Use Invoke-RestMethod for simplicity
            $response = Invoke-RestMethod -Uri $fullUrl `
                                         -Method Post `
                                         -Headers $headers `
                                         -Body $body `
                                         -TimeoutSec $TimeoutSeconds `
                                         -ErrorAction Stop
            
            $success = $true
            Write-Log "SUCCESS: Custom event posted to session $SessionId" -Level INFO
            
            if ($response) {
                Write-Log "Response: $($response | ConvertTo-Json -Compress)" -Level DEBUG
            }
            
        } catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message
            
            # Try to get more detail on 400 errors
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                
                # Try to read the response body for more details
                try {
                    $responseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($responseStream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Close()
                    Write-Log "Server response body: $responseBody" -Level ERROR
                } catch {
                    # Couldn't read response body
                }
                
                if ($statusCode -eq 401) {
                    Write-Log "ERROR: Authentication failed (401) - Check API key" -Level ERROR
                    break  # Don't retry auth errors
                } elseif ($statusCode -eq 404) {
                    Write-Log "ERROR: Session not found (404) - Session ID: $SessionId" -Level ERROR
                    break  # Don't retry if session doesn't exist
                } elseif ($statusCode -eq 400) {
                    Write-Log "ERROR: Bad request (400) - $errorMessage" -Level ERROR
                    Write-Log "Likely causes: Wrong API version (use v8-preview), invalid session ID, or malformed request" -Level ERROR
                    break  # Don't retry validation errors
                } elseif ($statusCode -eq 429) {
                    Write-Log "WARNING: Rate limited (429) - Will retry" -Level WARNING
                } else {
                    Write-Log "ERROR: HTTP $statusCode - $errorMessage" -Level ERROR
                }
            } else {
                Write-Log "ERROR: $errorMessage" -Level ERROR
            }
        }
    }
    
    if (-not $success) {
        throw $lastError
    }
    
    exit 0
    
} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    
    if ($_.Exception.InnerException) {
        Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level ERROR
    }
    
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    exit 1
    
} finally {
    Write-Log "Script execution completed" -Level INFO
}