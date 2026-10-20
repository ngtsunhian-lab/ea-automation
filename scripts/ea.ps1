# ea.ps1 - Enterprise Architect COM Automation CLI
# Read/write a RUNNING EA instance via its COM Automation Interface.
# Works under both pwsh 7 and Windows PowerShell 5.1:
#   .\ea.ps1 -Command status
param(
  [Parameter(Mandatory=$true)] [string]$Command,
  [string]$Name = "",
  [string]$Type = "",
  [int]$PackageID = 0,
  [int]$ElementID = 0,
  [int]$DiagramID = 0,
  [int]$ClientID = 0,
  [int]$SupplierID = 0,
  [int]$X = -1,
  [int]$Y = -1,
  [int]$Width = 0,
  [int]$Height = 0,
  [string]$ConnectorType = "Dependency"
)

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Collections.Generic;
public class RotView {
  [DllImport("ole32.dll")] private static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable rot);
  public static List<object> GetObjects() {
    var list = new List<object>();
    IRunningObjectTable rot;
    GetRunningObjectTable(0, out rot);
    IEnumMoniker em;
    rot.EnumRunning(out em);
    var mon = new IMoniker[1];
    while (em.Next(1, mon, IntPtr.Zero) == 0) {
      try { object o; rot.GetObject(mon[0], out o); list.Add(o); } catch {}
    }
    return list;
  }
}
"@

function Out-Json($obj) {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  ConvertTo-Json -InputObject $obj -Depth 8
}
function Fail([string]$msg) {
  Out-Json @{ error = $msg }
  exit 1
}

# All EA Repository objects registered in the Running Object Table
function Get-AllRepos {
  $list = @()
  foreach ($o in [RotView]::GetObjects()) {
    try { $r = $o.Repository; if ($r) { $list += $r } } catch {}
  }
  return $list
}

# Pick the repo that owns the given $DiagramID / $PackageID (first match).
# With neither given, returns the first EA instance found.
function Select-Repo {
  foreach ($r in Get-AllRepos) {
    try {
      if ($DiagramID -gt 0) { if ($r.GetDiagramByID($DiagramID)) { return $r } }
      elseif ($PackageID -gt 0) { if ($r.GetPackageByID($PackageID)) { return $r } }
      else { return $r }
    } catch {}
  }
  return $null
}

function Walk-Packages($pkg) {
  $node = [ordered]@{ packageID = $pkg.PackageID; name = $pkg.Name; elements = @(); diagrams = @(); packages = @() }
  foreach ($e in $pkg.Elements) { $node.elements += @{ id = $e.ElementID; name = $e.Name; type = $e.Type } }
  foreach ($d in $pkg.Diagrams) { $node.diagrams += @{ id = $d.DiagramID; name = $d.Name } }
  foreach ($p in $pkg.Packages) { $node.packages += ,(Walk-Packages $p) }
  return $node
}

# ---------------- status ----------------
if ($Command -eq "status") {
  $instances = @()
  foreach ($r in Get-AllRepos) {
    try {
      $inst = [ordered]@{ project = ""; models = @() }
      try { $inst.project = [string]$r.ProjectName } catch {}
      foreach ($m in $r.Models) { $inst.models += ,(Walk-Packages $m) }
      $instances += ,$inst
    } catch {}
  }
  if ($instances.Count -eq 0) { Fail "No running EA instance with an open project found" }
  Out-Json @{ instances = $instances }
  exit 0
}

# ---------------- diagram ----------------
elseif ($Command -eq "diagram") {
  if ($DiagramID -le 0) { Fail "diagram requires -DiagramID" }
  $rep = Select-Repo
  if (-not $rep) { Fail "No EA instance has DiagramID $DiagramID" }
  $d = $rep.GetDiagramByID($DiagramID)
  $elements = @()
  foreach ($do in $d.DiagramObjects) {
    if ($do.ElementID -le 0) { continue }   # dangling diagram object (import artifact)
    try {
      $e = $rep.GetElementByID($do.ElementID)
      $elements += @{ id = $e.ElementID; name = $e.Name; type = $e.Type; stereotype = $e.Stereotype; x = $do.Left; y = (- $do.Top); w = ($do.Right - $do.Left); h = ($do.Top - $do.Bottom) }
    } catch {
      $elements += @{ id = $do.ElementID; name = ""; type = ""; error = "unresolvable element"; x = $do.Left; y = (- $do.Top); w = ($do.Right - $do.Left); h = ($do.Top - $do.Bottom) }
    }
  }
  $connectors = @()
  foreach ($dl in $d.DiagramLinks) {
    try {
      $c = $rep.GetConnectorByID($dl.ConnectorID)
      $cl = $rep.GetElementByID($c.ClientID)
      $su = $rep.GetElementByID($c.SupplierID)
      $connectors += @{ id = $c.ConnectorID; type = $c.Type; stereotype = $c.Stereotype; client = @{ id = $c.ClientID; name = $cl.Name }; supplier = @{ id = $c.SupplierID; name = $su.Name } }
    } catch {}
  }
  Out-Json @{ diagram = @{ id = $d.DiagramID; name = $d.Name; elements = $elements; connectors = $connectors } }
  exit 0
}

# ---------------- find ----------------
elseif ($Command -eq "find") {
  if (-not $Name) { Fail "find requires -Name (substring match)" }
  $hits = @()
  foreach ($r in Get-AllRepos) {
    foreach ($m in $r.Models) {
      $stack = New-Object System.Collections.ArrayList
      [void]$stack.Add($m)
      while ($stack.Count -gt 0) {
        $p = $stack[0]; [void]$stack.RemoveAt(0)
        foreach ($e in $p.Elements) {
          if ($e.Name -like "*$Name*") { $hits += @{ id = $e.ElementID; name = $e.Name; type = $e.Type; packageID = $p.PackageID; packageName = $p.Name } }
        }
        foreach ($cp in $p.Packages) { [void]$stack.Add($cp) }
      }
    }
  }
  Out-Json @{ matches = $hits }
  exit 0
}

# ---------------- element ----------------
elseif ($Command -eq "element") {
  if ($ElementID -le 0) { Fail "element requires -ElementID" }
  foreach ($r in Get-AllRepos) {
    try {
      $e = $r.GetElementByID($ElementID)
      if (-not $e) { continue }
      $attrs = @();  foreach ($a in $e.Attributes)  { $attrs += @{ name = $a.Name; type = $a.Type } }
      $ops = @();    foreach ($o in $e.Operations) { $ops += @{ name = $o.Name } }
      $conns = @()
      foreach ($c in $e.Connectors) {
        $cl = $r.GetElementByID($c.ClientID); $su = $r.GetElementByID($c.SupplierID)
        $conns += @{ id = $c.ConnectorID; type = $c.Type; client = @{ id = $c.ClientID; name = $cl.Name }; supplier = @{ id = $c.SupplierID; name = $su.Name } }
      }
      Out-Json @{ element = @{ id = $e.ElementID; name = $e.Name; type = $e.Type; stereotype = $e.Stereotype; notes = $e.Notes; packageID = $e.PackageID; attributes = $attrs; operations = $ops; connectors = $conns } }
      exit 0
    } catch {}
  }
  Fail "Element $ElementID not found in any running EA instance"
}

# ---------------- add-element ----------------
elseif ($Command -eq "add-element") {
  if (-not $Name -or $PackageID -le 0) { Fail "add-element requires -Name and -PackageID" }
  if (-not $Type) { $Type = "Component" }
  $rep = Select-Repo
  if (-not $rep) { Fail "No EA instance has PackageID $PackageID" }
  $pkg = $rep.GetPackageByID($PackageID)
  foreach ($e in $pkg.Elements) {
    if ($e.Name -eq $Name) {
      Out-Json @{ element = @{ id = $e.ElementID; name = $e.Name; type = $e.Type; packageID = $PackageID }; note = "already existed, nothing created" }
      exit 0
    }
  }
  $el = $pkg.Elements.AddNew($Name, $Type)
  if (-not $el) { Fail "Elements.AddNew returned null" }
  if (-not $el.Update()) { Fail ("Element.Update: " + $el.GetLastError()) }
  Out-Json @{ element = @{ id = $el.ElementID; name = $el.Name; type = $el.Type; packageID = $PackageID } }
  exit 0
}

# ---------------- place (add or move on diagram) ----------------
elseif ($Command -eq "place") {
  if ($ElementID -le 0 -or $DiagramID -le 0 -or $X -lt 0 -or $Y -lt 0 -or $Width -le 0 -or $Height -le 0) {
    Fail "place requires -ElementID -DiagramID -X -Y -Width -Height"
  }
  $rep = Select-Repo
  if (-not $rep) { Fail "No EA instance has DiagramID $DiagramID" }
  $d = $rep.GetDiagramByID($DiagramID)
  $found = $null
  foreach ($do in $d.DiagramObjects) { if ($do.ElementID -eq $ElementID) { $found = $do; break } }
  if ($found) {
    $found.Left = $X; $found.Top = $Y; $found.Right = $X + $Width; $found.Bottom = $Y + $Height
    if (-not $found.Update()) { Fail ("DiagramObject.Update: " + $found.GetLastError()) }
    $action = "moved"
  } else {
    $found = $d.DiagramObjects.AddNew("l=$X;r=$($X + $Width);t=$Y;b=$($Y + $Height)", "")
    $found.ElementID = $ElementID
    if (-not $found.Update()) { Fail ("DiagramObjects.AddNew: " + $found.GetLastError()) }
    $action = "placed"
  }
  $rep.ReloadDiagram($DiagramID) | Out-Null
  Out-Json @{ elementID = $ElementID; diagramID = $DiagramID; action = $action; x = $X; y = $Y; width = $Width; height = $Height }
  exit 0
}

# ---------------- connect ----------------
elseif ($Command -eq "connect") {
  if ($ClientID -le 0 -or $SupplierID -le 0) { Fail "connect requires -ClientID -SupplierID (-ConnectorType and -DiagramID optional)" }
  $rep = $null
  foreach ($r in Get-AllRepos) {
    try {
      $c1 = $r.GetElementByID($ClientID); $c2 = $r.GetElementByID($SupplierID)
      if ($c1 -and $c2) { $rep = $r; break }
    } catch {}
  }
  if (-not $rep) { Fail "No EA instance has both elements $ClientID and $SupplierID" }
  $client = $rep.GetElementByID($ClientID)
  $conn = $client.Connectors.AddNew("", $ConnectorType)
  if (-not $conn) { Fail "Connectors.AddNew returned null" }
  $conn.ClientID = $ClientID
  $conn.SupplierID = $SupplierID
  if (-not $conn.Update()) { Fail ("Connector.Update: " + $conn.GetLastError()) }
  $linkAdded = $false
  if ($DiagramID -gt 0) {
    $d = $rep.GetDiagramByID($DiagramID)
    if ($d) {
      $dl = $d.DiagramLinks.AddNew($conn.ConnectorID, "DiagramLink")
      if ($dl -and $dl.Update()) { $linkAdded = $true }
    }
  }
  if ($linkAdded) { $rep.ReloadDiagram($DiagramID) | Out-Null }
  Out-Json @{ connector = @{ id = $conn.ConnectorID; type = $ConnectorType; clientID = $ClientID; supplierID = $SupplierID }; shownOnDiagram = $linkAdded }
  exit 0
}

# ---------------- reload ----------------
elseif ($Command -eq "reload") {
  if ($DiagramID -le 0) { Fail "reload requires -DiagramID" }
  $rep = Select-Repo
  if (-not $rep) { Fail "No EA instance has DiagramID $DiagramID" }
  $rep.ReloadDiagram($DiagramID) | Out-Null
  Out-Json @{ reloaded = $DiagramID }
  exit 0
}

else { Fail "Unknown command '$Command'. Valid: status, diagram, find, element, add-element, place, connect, reload" }
