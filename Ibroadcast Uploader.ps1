param(

  [string]$loginToken = $null

)

function Login {
  try {
    Write-Host "Logging in..."

    $userdetails = @{
      mode = "login_token"
      type = "account"
      app_id = 1007
      login_token = $loginToken
    } | ConvertTo-Json

    $response = Invoke-WebRequest -Uri "$API_ENDPOINT" -Method POST -Headers @{
      "Content-Type" = $JSON_CONTENT_TYPE
      "User-Agent" = $USER_AGENT
    } -Body $userdetails

    if ($response.StatusCode -ne 200) {
      Write-Host "$($MyInvocation.MyCommand.Name) failed."
      Write-Host "response.Code: $($response.StatusCode)"
      Write-Host "response.StatusDescription: $($response.StatusDescription)"
      return
    }

    $ResponseContent = $response.Content | ConvertFrom-Json

    if (-not $ResponseContent.result) {
      Write-Host $ResponseContent.message
      return
    }

    $script:userId = $ResponseContent.user.id
    $script:userToken = $ResponseContent.user.token

    Write-Host "Login: Token was vaild, login successful"
  }
  catch {
    Write-Host "$($MyInvocation.MyCommand.Name) failed. Please check your authentication token. Exception: $($_.Exception.Message)"
  }
}

function Status {
  try {
    Write-Host "Getting Status ..."

    $userdetails = @{
      mode = "status"
      user_id = $userId
      token = $userToken
      version = $VERSION
      client = $CLIENT
      "user-agent" = $USER_AGENT
      supported_types = 1
    } | ConvertTo-Json

    $response = Invoke-WebRequest -Uri "$API_ENDPOINT" -Method POST -Headers @{
      "Content-Type" = $JSON_CONTENT_TYPE
      "User-Agent" = $USER_AGENT
    } -Body $userdetails

    if ($response.StatusCode -ne 200) {
      Write-Host "$($MyInvocation.MyCommand.Name) failed."
      Write-Host "response.Code: $($response.StatusCode)"
      Write-Host "response.StatusDescription: $($response.StatusDescription)"
      return
    }

    $ResponseContent = $response.Content | ConvertFrom-Json

    if (-not $ResponseContent.result) {
      Write-Host $ResponseContent.message
      return
    }

    $supported = $ResponseContent.supported
    foreach ($jObj in $supported) {
      $ext = $jObj.Extension
      if ($script:extensions -notcontains $ext) {
        $script:extensions += $ext
      }
    }

    Write-Host "Status: Uploader connected to account: $($ResponseContent.user.email_address)"
  }
  catch {
    Write-Host "$($MyInvocation.MyCommand.Name) failed. Exception: $($_.Exception.Message)"
  }
}

function GetMD5 {
  try {
    $response = Invoke-WebRequest -Uri "$SYNC_ENDPOINT" -Method POST -Headers @{
      "Content-Type" = $URL_CONTENT_TYPE
      "User-Agent" = $USER_AGENT
    } -Body @{
      user_id = $userId
      token = $userToken
    }

    if ($response.StatusCode -ne 200) {
      Write-Host "$($MyInvocation.MyCommand.Name) failed."
      Write-Host "response.Code: $($response.StatusCode)"
      Write-Host "response.StatusDescription: $($response.StatusDescription)"
      return
    }

    $ResponseContent = $response.Content | ConvertFrom-Json

    if (-not $ResponseContent.result) {
      Write-Host $ResponseContent.message
      return
    }

    $script:md5s = $ResponseContent.md5
  }
  catch {
    Write-Host "$($MyInvocation.MyCommand.Name) failed. Exception: $($_.Exception.Message)"
  }
}

function loadMediaFilesQ {
  param(
    [string]$dir
  )

  $mediaFiles = @()
  try {
    $mediaFiles = Get-ChildItem -Path $dir -File -Recurse | Where-Object { $extensions -contains $_.Extension.ToLower() }
  }
  catch {
    Write-Host "$($MyInvocation.MyCommand.Name) failed. Exception: $($_.Exception.Message)"
  }

  return $mediaFiles
}

function ExecuteOptions {
  try {
    Write-Host "`nFound $($mediaFilesQ.Count) files. Press 'L' for listing and 'U' for uploading"
    $option = Read-Host

    if ($option.ToUpper().StartsWith("L")) {
      Write-Host "`nListing found, supported files:"
      foreach ($file in $mediaFilesQ) {
        Write-Host " - $($file.FullName)"
      }
      Write-Host "`nPress 'U' to start the upload if this looks reasonable"
      $option = Read-Host
    }

    if ($option.ToUpper().StartsWith("U")) {
      Write-Host "Starting upload"

      $nrUploadedFiles = 0
      foreach ($file in $mediaFilesQ) {
        Write-Host "Uploading $($file.Name)"

        $cksum = (Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash
        if ($md5s -contains $cksum) {
          Write-Host "skipping, already uploaded"
          continue
        }

        if (uploadMediaFile $file) {
          $nrUploadedFiles++
        }
      }
      Write-Host "`nDone. $($nrUploadedFiles) files were uploaded."
    }
    else {
      Write-Host "Aborted."
    }
  }
  catch {
    Write-Host "$($MyInvocation.MyCommand.Name) failed. Exception: $($_.Exception.Message)"
  }
}

function uploadMediaFile {
  param(
    [System.IO.FileInfo]$file
  )

  try {
    $data = [System.IO.File]::ReadAllBytes($file.FullName)

    $headers = @{
      "User-Agent" = "ibroadcast-uploader/0.5"
    }

    $query = @{
      "user_id" = $userId
      "token" = $userToken
      "file_path" = $file.FullName
      "method" = $CLIENT
    }

    $httpClient = New-Object System.Net.Http.HttpClient

    $multipartContent = New-Object System.Net.Http.MultipartFormDataContent
    $multipartContent.Add([System.Net.Http.StringContent]::new($userId),"user_id")
    $multipartContent.Add([System.Net.Http.StringContent]::new($userToken),"token")
    $multipartContent.Add([System.Net.Http.StringContent]::new($file.FullName),"file_path")
    $multipartContent.Add([System.Net.Http.StringContent]::new($CLIENT),"method")
    $multipartContent.Add([System.Net.Http.StreamContent]::new([System.IO.MemoryStream]::new($data)),"file",$file.Name)

    $response = $httpClient.PostAsync("https://upload.ibroadcast.com",$multipartContent).result

    $responseContent = $response.Content.ReadAsStringAsync().result | ConvertFrom-Json

    if ($responseContent.result -eq $false) {
      Write-Host "File upload failed: $($responseContent.message)"
      return $false
    }

    Write-Host "File uploaded successfully: $($file.Name)"
    return $true
  }
  catch {
    Write-Host "Failed! Exception: $($_.Exception.Message)"
  }
  return $false
}


if ($loginToken -eq $null -or $loginToken -eq "") {

  Write-Host "Run this script in the parent directory of your music files."
  Write-Host "To acquire a login token, enable the 'Simple Uploaders' app by visiting https://ibroadcast.com, logging in to your account, and clicking the 'Apps' button in the side menu."
  Write-Host "Usage: $($MyInvocation.MyCommand.Name) <authentication token>"

} else {

    $SYNC_ENDPOINT = "https://upload.ibroadcast.com"
    $API_ENDPOINT = "https://api.ibroadcast.com/s/JSON/"

    $psVersion = $PSVersionTable.PSVersion
    $osVersion = [System.Environment]::OSVersion.Version
    $USER_AGENT = "Mozilla/5.0 (Windows NT; Windows NT $($osVersion.Major).$($osVersion.Minor); en-US) WindowsPowerShell/$($psVersion.Major).$($psVersion.Minor).$($psVersion.Build).$($psVersion.Revision)"
    $JSON_CONTENT_TYPE = "application/json"
    $URL_CONTENT_TYPE = "application/x-www-form-urlencoded"
    $CLIENT = "PowerShell Upload client"
    $VERSION = "1.0"

    $ScriptLocation = $MyInvocation.MyCommand.Definition
    $RootFolder = Split-Path -Parent -Path $ScriptLocation

    $userId = $null
    $userToken = $null
    $extensions = @()
    $md5s = @()
    $mediaFilesQ = @()

    Function Main {
        Login
        if ($script:userId -and $script:userToken) {
            Status
            GetMD5
            $script:mediaFilesQ = loadMediaFilesQ $RootFolder
            ExecuteOptions
        }else {
            $script:loginToken = Read-Host "Please enter a valid token or Leave blank to exit"
            if ($script:loginToken -or $script:loginToken -ne "") {
                Main
            }else{
                Exit
            }
        }
    }

    Main

}
