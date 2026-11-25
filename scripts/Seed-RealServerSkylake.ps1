param(
  [Parameter(Mandatory = $true)]
  [string]$AccessToken,
  [string]$GraphqlUrl = 'https://api-vistay.fakebook.tech/graphqloffice',
  [string]$AccessCodeFile = 'D:\Vistay\.secrets\skylake-access-codes.json',
  [datetime]$BookingStartDate = [datetime]'2026-11-26',
  [switch]$SkipAccessCredentials
)

$ErrorActionPreference = 'Stop'
$seedVersion = '20261125-v1'

function Invoke-ViStayGraphql {
  param(
    [Parameter(Mandatory = $true)][string]$Query,
    [hashtable]$Variables = @{},
    [string]$OperationName
  )

  $body = @{ query = $Query; variables = $Variables }
  if ($OperationName) { $body.operationName = $OperationName }
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri $GraphqlUrl `
    -Headers @{ Authorization = "Bearer $AccessToken" } `
    -ContentType 'application/json' `
    -Body ($body | ConvertTo-Json -Depth 20 -Compress)
  if ($response.errors) {
    $messages = @($response.errors | ForEach-Object {
      $code = $_.extensions.code
      if ($code) { "$code`: $($_.message)" } else { $_.message }
    })
    $operationLabel = if ($OperationName) { $OperationName } else { 'unnamed-operation' }
    throw "GraphQL operation $operationLabel failed: $($messages -join '; ')"
  }
  return $response.data
}

function Get-Portfolio {
  return (Invoke-ViStayGraphql -OperationName 'SeedPortfolio' -Query @'
query SeedPortfolio {
  propertyPortfolio {
    branches { id code name }
    cities {
      id code name
      areas {
        id code name
        buildings {
          id code name address
          floors {
            id code name floorNumber
            units {
              id code unitNumber name operatingModel operationalStatus
              basePricePerNight currency branchId hostProfileId version
            }
          }
        }
      }
    }
  }
}
'@).propertyPortfolio
}

function New-Profile {
  param([ValidateSet('CUSTOMER', 'HOST')][string]$Type, [hashtable]$ProfileInput)
  if ($Type -eq 'CUSTOMER') {
    return (Invoke-ViStayGraphql -OperationName 'SeedCustomer' -Variables @{ input = $ProfileInput } -Query @'
mutation SeedCustomer($input: CreateCustomerProfileInput!) {
  createCustomerProfile(input: $input) {
    profileId accountId accountType displayName email contactPhone status referenceCode version
  }
}
'@).createCustomerProfile
  }
  return (Invoke-ViStayGraphql -OperationName 'SeedHost' -Variables @{ input = $ProfileInput } -Query @'
mutation SeedHost($input: CreateHostProfileInput!) {
  createHostProfile(input: $input) {
    profileId accountId accountType displayName email contactPhone status referenceCode version
  }
}
'@).createHostProfile
}

function Get-Directory {
  param([ValidateSet('CUSTOMER', 'HOST')][string]$Type, [string]$Search)
  return (Invoke-ViStayGraphql -OperationName 'SeedDirectory' -Variables @{ type = $Type; search = $Search } -Query @'
query SeedDirectory($type: AccountType!, $search: String) {
  userDirectory(accountType: $type, search: $search, first: 100) {
    nodes { profileId accountId accountType displayName email contactPhone status referenceCode }
    totalCount nextCursor
  }
}
'@).userDirectory
}

$unitCodes = @'
S1-0505
S1-0508
S1-0905
S1-1105
S1-1605
S1-1705
S1-1905
S1-2105
S1-2305
S1-2405
S1-2505A
S1-2705
S1-2809
S1-3105
S1-3505
S2-0610
S2-0715
S2-1008
S2-1110
S2-1111
S2-11A08
S2-11A11
S2-11A12
S2-1209
S2-1220
S2-15A12
S2-1510
S2-1511A
S2-1512
S2-1710
S2-1712
S2-1815
S2-1901
S2-2106
S2-2211A
S2-2411
S2-2512
S2-2710
S2-2712
S2-2916
S2-3010
S2-3210
S2-3301
S2-3316
S2-3411A
S2-3420
S2-3501
S2-3517
S2-3608
S2-3810
S2-3812
S2-3816
S2-3908
S3-0511
S3-0908
S3-1001
S3-1012
S3-1019
S3-11A11
S3-15A12
S3-1616
S3-1701
S3-1811
S3-1901
S3-2012
S3-2312
S3-2412
S3-2712
S3-3015
S3-3411
S3-3511
S3-3512
S3-3612
S3-3808A
S3-3906
S3-3918
'@ -split "`r?`n" | Where-Object { $_ }

if (-not (Test-Path -LiteralPath $AccessCodeFile)) {
  throw "Property access-code file is missing: $AccessCodeFile"
}
$accessCodes = Get-Content -Raw -LiteralPath $AccessCodeFile | ConvertFrom-Json
$missingAccessCodes = @($unitCodes | Where-Object { $_ -notin @($accessCodes.PSObject.Properties.Name) })
if ($missingAccessCodes.Count -gt 0) {
  throw "Access-code file is missing units: $($missingAccessCodes -join ', ')"
}

$unitSpecs = foreach ($code in $unitCodes) {
  $parts = $code.Split('-', 2)
  $tower = $parts[0]
  $suffix = $parts[1]
  if ($suffix.Length -gt 4 -and [char]::IsLetter($suffix[2])) {
    $floorCode = $suffix.Substring(0, 3)
    $unitNumber = $suffix.Substring(3)
  } else {
    $floorCode = $suffix.Substring(0, 2)
    $unitNumber = $suffix.Substring(2)
  }
  $floorNumber = [int]([regex]::Match($floorCode, '^\d+').Value)
  $model = switch ($tower) {
    'S1' { 'MANAGEMENT' }
    'S2' { 'LEASED_BY_VISTAY' }
    default { 'OWNED' }
  }
  $basePrice = switch ($tower) {
    'S1' { '1200000' }
    'S2' { '1400000' }
    default { '1600000' }
  }
  [pscustomobject]@{
    code = $code
    tower = $tower
    floorCode = $floorCode
    floorNumber = $floorNumber
    unitNumber = $unitNumber
    operatingModel = $model
    basePrice = $basePrice
  }
}

$viewer = (Invoke-ViStayGraphql -OperationName 'SeedViewer' -Query @'
query SeedViewer { viewer { accountId profileId displayName roles permissions authorizationVersion } }
'@).viewer
$requiredPermissions = @('property:create', 'property:update', 'contract:create', 'customer-profile:create', 'host-profile:create', 'booking:create')
$missingPermissions = @($requiredPermissions | Where-Object { $_ -notin @($viewer.permissions) })
if ($missingPermissions.Count -gt 0) {
  throw "Token lacks required permissions: $($missingPermissions -join ', ')"
}

$portfolio = Get-Portfolio
if (@($portfolio.branches).Count -eq 0) {
  $null = Invoke-ViStayGraphql -OperationName 'SeedBranch' -Variables @{ input = @{
    code = 'HN-CENTRAL'
    name = 'Ha Noi Central'
  } } -Query @'
mutation SeedBranch($input: CreateOperatingBranchInput!) { createOperatingBranch(input: $input) { id code name } }
'@
  $portfolio = Get-Portfolio
}
$branch = @($portfolio.branches | Where-Object { $_.code -match 'HN|HANOI' } | Select-Object -First 1)
if (-not $branch) { $branch = @($portfolio.branches)[0] }

$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
if (-not $city) {
  $city = (Invoke-ViStayGraphql -OperationName 'SeedCity' -Variables @{ input = @{ code = '01'; name = 'Ha Noi' } } -Query @'
mutation SeedCity($input: CreateCityInput!) { createCity(input: $input) { id code name } }
'@).createCity
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
if (-not $area) {
  $area = (Invoke-ViStayGraphql -OperationName 'SeedArea' -Variables @{ input = @{ cityId = $city.id; code = 'SKYLAKE'; name = 'Skylake' } } -Query @'
mutation SeedArea($input: CreateAreaInput!) { createArea(input: $input) { id cityId code name } }
'@).createArea
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
foreach ($tower in @('S1', 'S2', 'S3')) {
  if (-not @($area.buildings | Where-Object code -eq $tower | Select-Object -First 1)) {
    $null = Invoke-ViStayGraphql -OperationName 'SeedBuilding' -Variables @{ input = @{
      areaId = $area.id
      code = $tower
      name = "Skylake $tower"
      address = "Skylake $tower, Pham Hung, Nam Tu Liem, Ha Noi"
    } } -Query @'
mutation SeedBuilding($input: CreateBuildingInput!) { createBuilding(input: $input) { id areaId code name address } }
'@
  }
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
foreach ($tower in @('S1', 'S2', 'S3')) {
  $building = @($area.buildings | Where-Object code -eq $tower | Select-Object -First 1)
  $floors = @($unitSpecs | Where-Object tower -eq $tower | Sort-Object floorNumber, floorCode -Unique)
  foreach ($floor in $floors) {
    if (-not @($building.floors | Where-Object code -eq $floor.floorCode | Select-Object -First 1)) {
      $sortOrder = ($floor.floorNumber * 10) + $(if ($floor.floorCode -match 'A$') { 1 } else { 0 })
      $null = Invoke-ViStayGraphql -OperationName 'SeedFloor' -Variables @{ input = @{
        buildingId = $building.id
        code = $floor.floorCode
        name = "Tang $($floor.floorCode)"
        floorNumber = $floor.floorNumber
        sortOrder = $sortOrder
      } } -Query @'
mutation SeedFloor($input: CreateBuildingFloorInput!) { createBuildingFloor(input: $input) { id buildingId code name floorNumber } }
'@
    }
  }
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
foreach ($spec in $unitSpecs) {
  $building = @($area.buildings | Where-Object code -eq $spec.tower | Select-Object -First 1)
  $floor = @($building.floors | Where-Object code -eq $spec.floorCode | Select-Object -First 1)
  if (-not @($floor.units | Where-Object code -eq $spec.code | Select-Object -First 1)) {
    $null = Invoke-ViStayGraphql -OperationName 'SeedUnit' -Variables @{ input = @{
      floorId = $floor.id
      branchId = $branch.id
      code = $spec.code
      unitNumber = $spec.unitNumber
      name = $spec.code
      operatingModel = $spec.operatingModel
      areaSqm = '60'
      bedroomCount = 2
      bathroomCount = 1
      capacity = 4
      basePricePerNight = $spec.basePrice
      currency = 'VND'
    } } -Query @'
mutation SeedUnit($input: CreatePropertyUnitInput!) { createPropertyUnit(input: $input) { id code name branchId operatingModel version } }
'@
  }
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
$unitsForAccess = @($area.buildings | ForEach-Object { $_.floors } | ForEach-Object { $_.units } |
  Where-Object { $_.code -in $unitCodes })
if (-not $SkipAccessCredentials) {
  foreach ($unit in $unitsForAccess) {
    $credential = (Invoke-ViStayGraphql -OperationName 'SeedAccessCredentialStatus' -Variables @{
      propertyId = $unit.id
    } -Query @'
query SeedAccessCredentialStatus($propertyId: ID!) {
  propertyAccessCredential(propertyId: $propertyId) { propertyId configured keyVersion version }
}
'@).propertyAccessCredential
    if ($credential.configured) { continue }
    $null = Invoke-ViStayGraphql -OperationName 'SeedAccessCredential' -Variables @{ input = @{
      propertyId = $unit.id
      accessCode = $accessCodes.PSObject.Properties[$unit.code].Value
      expectedVersion = $credential.version
    } } -Query @'
mutation SeedAccessCredential($input: PropertyAccessCredentialInput!) {
  setPropertyAccessCredential(input: $input) { propertyId configured keyVersion version }
}
'@
  }
}

$hosts = @()
foreach ($tower in @('S1', 'S2', 'S3')) {
  $email = "skylake.owner.$($tower.ToLowerInvariant())@vistay.local"
  $existing = @(Get-Directory -Type HOST -Search $email).nodes | Where-Object email -eq $email | Select-Object -First 1
  if ($existing) { $hosts += $existing; continue }
  $hosts += New-Profile -Type HOST -ProfileInput @{
    fullName = "Chu nha Skylake $tower"
    email = $email
    contactPhone = "+84920010$($tower.Substring(1).PadLeft(2, '0'))"
    hostCode = "SKY-OWNER-$tower"
    address = "Skylake $tower, Pham Hung, Nam Tu Liem, Ha Noi"
    taxCode = "SKYLAKE-$tower"
    reason = 'Seed Skylake host profile on the real server'
    idempotencyKey = "skylake-host-$tower-$seedVersion"
  }
}

$customers = @()
for ($index = 1; $index -le 10; $index++) {
  $email = ('skylake.customer{0:D2}@vistay.local' -f $index)
  $existing = @(Get-Directory -Type CUSTOMER -Search $email).nodes | Where-Object email -eq $email | Select-Object -First 1
  if ($existing) { $customers += $existing; continue }
  $document = '{0:D12}' -f ([long]100100000000 + $index)
  $customers += New-Profile -Type CUSTOMER -ProfileInput @{
    fullName = ('Khach Skylake {0:D2}' -f $index)
    email = $email
    contactPhone = ('+84910010{0:D2}' -f $index)
    dateOfBirth = ([datetime]'1990-01-01').AddDays($index * 31).ToString('yyyy-MM-dd')
    nationalityCode = 'VN'
    documentType = 'CCCD'
    documentNumber = $document
    address = 'Ha Noi, Viet Nam'
    reason = 'Seed customer profile for real-server booking tests'
    idempotencyKey = ('skylake-customer-{0:D2}-{1}' -f $index, $seedVersion)
  }
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
$allUnits = @($area.buildings | ForEach-Object { $_.floors } | ForEach-Object { $_.units } | Where-Object { $_.code -in $unitCodes } | Sort-Object code)
$contracts = @((Invoke-ViStayGraphql -OperationName 'SeedContracts' -Query @'
query SeedContracts { ownerContracts { id contractNumber status version propertyTerms { propertyId operatingModel status } parties { hostProfileId primary } } }
'@).ownerContracts)

foreach ($unit in $allUnits) {
  $tower = $unit.code.Split('-', 2)[0]
  $host = @($hosts | Where-Object { $_.referenceCode -eq "SKY-OWNER-$tower" -or $_.email -eq "skylake.owner.$($tower.ToLowerInvariant())@vistay.local" } | Select-Object -First 1)
  if (-not $host) { throw "Host profile for $tower was not resolved." }
  $contractNumber = "SKY-$($unit.code)-2026"
  if (@($contracts | Where-Object contractNumber -eq $contractNumber | Select-Object -First 1)) { continue }
  $input = @{
    contractNumber = $contractNumber
    propertyId = $unit.id
    hostProfileId = $host.profileId
    operatingModel = $unit.operatingModel
    startDate = '2026-11-25'
    endDate = '2027-11-25'
    paymentPeriod = 'MONTH'
    paymentCycleCount = 1
    currency = 'VND'
    status = 'ACTIVE'
    notes = 'Skylake contract seeded through the real GraphQL API'
  }
  if ($unit.operatingModel -eq 'MANAGEMENT') { $input.managementFeePercent = '15' }
  if ($unit.operatingModel -eq 'LEASED_BY_VISTAY') { $input.fixedAmount = '18000000' }
  $null = Invoke-ViStayGraphql -OperationName 'SeedContract' -Variables @{ input = $input } -Query @'
mutation SeedContract($input: CreateOwnerContractInput!) {
  createOwnerContract(input: $input) { id contractNumber status version propertyTerms { propertyId operatingModel status } parties { hostProfileId primary } }
}
'@
}

$createdBookings = @()
for ($index = 0; $index -lt 20; $index++) {
  $unit = $allUnits[$index]
  $customer = $customers[$index % $customers.Count]
  $tower = $unit.code.Split('-', 2)[0]
  $host = @($hosts | Where-Object { $_.referenceCode -eq "SKY-OWNER-$tower" -or $_.email -eq "skylake.owner.$($tower.ToLowerInvariant())@vistay.local" } | Select-Object -First 1)
  $checkIn = $BookingStartDate.AddDays($index * 2)
  $checkOut = $checkIn.AddDays(2 + ($index % 3))
  $availability = (Invoke-ViStayGraphql -OperationName 'SeedAvailability' -Variables @{
    input = @{ propertyId = $unit.id; checkInDate = $checkIn.ToString('yyyy-MM-dd'); checkOutDate = $checkOut.ToString('yyyy-MM-dd') }
  } -Query @'
query SeedAvailability($input: PropertyAvailabilityInput!) { propertyAvailability(input: $input) { propertyId available overlaps { type status startDate endDateExclusive } } }
'@).propertyAvailability
  if (-not $availability.available) {
    throw "Unit $($unit.code) is not available from $($checkIn.ToString('yyyy-MM-dd')) to $($checkOut.ToString('yyyy-MM-dd'))."
  }
  $createdBookings += (Invoke-ViStayGraphql -OperationName 'SeedBooking' -Variables @{ input = @{
    idempotencyKey = ('skylake-booking-{0:D2}-{1}' -f ($index + 1), $seedVersion)
    propertyId = $unit.id
    propertyName = $unit.name
    hostProfileId = $host.profileId
    customerProfileId = $customer.profileId
    guestName = $customer.displayName
    guestPhone = $customer.contactPhone
    guestEmail = $customer.email
    checkInDate = $checkIn.ToString('yyyy-MM-dd')
    checkOutDate = $checkOut.ToString('yyyy-MM-dd')
    adults = 2
    children = $index % 2
    stayType = 'SHORT_TERM'
    unitPrice = $unit.basePricePerNight
    discountAmount = '0'
    feeAmount = '0'
    taxAmount = '0'
    currency = 'VND'
    notes = 'Skylake booking seeded through the real GraphQL API'
  } } -Query @'
mutation SeedBooking($input: CreateBookingInput!) { createBooking(input: $input) { id bookingCode propertyId customerId guestName status checkInDate checkOutDate totalAmount currency version } }
'@).createBooking
}

$portfolio = Get-Portfolio
$city = @($portfolio.cities | Where-Object code -eq '01' | Select-Object -First 1)
$area = @($city.areas | Where-Object code -eq 'SKYLAKE' | Select-Object -First 1)
$verifiedUnits = @($area.buildings | ForEach-Object { $_.floors } | ForEach-Object { $_.units } | Where-Object { $_.code -in $unitCodes })
$verifiedContracts = @((Invoke-ViStayGraphql -OperationName 'VerifyContracts' -Query @'
query VerifyContracts { ownerContracts { id contractNumber status propertyTerms { propertyId operatingModel status } parties { hostProfileId primary } } }
'@).ownerContracts | Where-Object { $_.contractNumber -like 'SKY-*-2026' })
$timeline = (Invoke-ViStayGraphql -OperationName 'VerifyTimeline' -Variables @{ input = @{
  propertyIds = @($verifiedUnits.id)
  fromDate = $BookingStartDate.ToString('yyyy-MM-dd')
  toDateExclusive = $BookingStartDate.AddDays(60).ToString('yyyy-MM-dd')
} } -Query @'
query VerifyTimeline($input: BookingTimelineInput!) { bookingTimeline(input: $input) { fromDate toDateExclusive truncated nodes { id bookingCode propertyId customerId status checkInDate checkOutDate totalAmount currency } } }
'@).bookingTimeline

$replay = (Invoke-ViStayGraphql -OperationName 'VerifyBookingReplay' -Variables @{ input = @{
  idempotencyKey = "skylake-booking-01-$seedVersion"
  propertyId = $allUnits[0].id
  propertyName = $allUnits[0].name
  hostProfileId = $hosts[0].profileId
  customerProfileId = $customers[0].profileId
  guestName = $customers[0].displayName
  guestPhone = $customers[0].contactPhone
  guestEmail = $customers[0].email
  checkInDate = $BookingStartDate.ToString('yyyy-MM-dd')
  checkOutDate = $BookingStartDate.AddDays(2).ToString('yyyy-MM-dd')
  adults = 2
  children = 0
  stayType = 'SHORT_TERM'
  unitPrice = $allUnits[0].basePricePerNight
  currency = 'VND'
  notes = 'Skylake booking seeded through the real GraphQL API'
} } -Query @'
mutation VerifyBookingReplay($input: CreateBookingInput!) { createBooking(input: $input) { id bookingCode } }
'@).createBooking

$firstBooking = $createdBookings | Select-Object -First 1
if ($replay.id -ne $firstBooking.id) { throw 'Booking idempotency replay returned a different resource.' }
if ($verifiedUnits.Count -ne $unitCodes.Count) { throw "Expected $($unitCodes.Count) Skylake units, found $($verifiedUnits.Count)." }
if ($verifiedContracts.Count -lt $unitCodes.Count) { throw "Expected at least $($unitCodes.Count) Skylake contracts, found $($verifiedContracts.Count)." }
if (@($createdBookings).Count -ne 20) { throw "Expected 20 booking results, found $(@($createdBookings).Count)." }

[pscustomobject]@{
  server = $GraphqlUrl
  actorAccountType = 'ADMIN'
  actorRoles = @($viewer.roles) -join ','
  branch = "$($branch.code) - $($branch.name)"
  city = $city.name
  area = $area.name
  buildings = @($area.buildings | Where-Object { $_.code -in @('S1', 'S2', 'S3') }).Count
  units = $verifiedUnits.Count
  hosts = $hosts.Count
  customers = $customers.Count
  contracts = $verifiedContracts.Count
  bookingMutationResults = @($createdBookings).Count
  timelineBookings = @($timeline.nodes).Count
  timelineTruncated = $timeline.truncated
  idempotencyReplayPassed = $true
  accessPasswordsSeeded = -not $SkipAccessCredentials
  accessPasswordStorage = if ($SkipAccessCredentials) {
    'Deferred because server Vault Transit is unavailable.'
  } else {
    'Vault Transit ciphertext only; GraphQL never returns raw access codes or ciphertext.'
  }
}
