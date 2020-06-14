New-PSDrive -Name SE -PSProvider FileSystem -Root 'E:\Steam\steamapps\common\SpaceEngineers\Content\Data'

Function Get-XmlDocument ( [String]$Path )
{
    $Ret = New-Object System.Xml.XmlDocument
    $Ret.Load( (Get-Item $Path).OpenText() )
    Return $Ret
}

# ORES SECTION
$Ores = @{}
& {
    ForEach ( $PhysItem in (Get-XmlDocument SE:\PhysicalItems.sbc).Definitions.PhysicalItems.PhysicalItem )
    {
        If ( $PhysItem.Id.TypeId -ne "Ore" ) { Continue; }
        $TypeId = $PhysItem.Id.TypeId
        $SubtypeId = $PhysItem.Id.SubtypeId
        $Name = $TypeId + '.' + $SubtypeId
        
        [Double]$Mass = $PhysItem.Mass
        [Double]$Volume = $PhysItem.Volume
        $Ores[ $SubtypeId ] = New-Object PSObject -Property @{
            Name = $SubtypeId;
            FullName = $Name;
            Mass = $Mass;
            Volume = $Volume;
        }
    }
}

Function Get-Ore
{
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param
    (
        [Parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [String]
        $Name,
        
        [Parameter(Mandatory=$True,ParameterSetName="All")]
        [Switch]
        $All
    )
    
    Switch ( $PSCmdlet.ParameterSetName )
    {
        "Name"
        {
            If ( -not $Ores.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such ore ""{0}""" -f $Name)
            }
            Return $Ores[ $Name ]
        }
        
        "All"
        {
            Return $Ores.Values
        }
    }
}

# INGOTS SECTION
$Ingots = @{}
[String[]]$IngotsBlackList = ,"Stone"
& {
    ForEach ( $PhysItem in (Get-XmlDocument SE:\PhysicalItems.sbc).Definitions.PhysicalItems.PhysicalItem )
    {
        If ( $PhysItem.Id.TypeId -ne "Ingot" <#-or $IngotsBlackList -contains $PhysItem.Id.SubtypeId#> ) { Continue; }
        $TypeId = $PhysItem.Id.TypeId
        $SubtypeId = $PhysItem.Id.SubtypeId
        $Name = $TypeId + '.' + $SubtypeId
        
        [Double]$Mass = $PhysItem.Mass
        [Double]$Volume = $PhysItem.Volume
        $Ingots[ $SubtypeId ] = @{
            Name = $SubtypeId;
            FullName = $Name;
            Mass = $Mass;
            Volume = $Volume;
        }
    }
    ForEach ( $Blueprint in (Get-XmlDocument SE:\Blueprints.sbc).Definitions.Blueprints.Blueprint )
    {
        If ( $Blueprint.Id.SubtypeId -cmatch '^([A-Z][a-z]*)OreToIngot$' )
        {
            $Type = $Matches[1]
            
            If ( -not $Ingots.ContainsKey( $Type ) ) { Continue; }
            
            [Double]$Preq = $Blueprint.Prerequisites.Item.Amount
            If ( $Blueprint.Prerequisites.Item.SubtypeId -ne $Type )
            {
                Throw New-Object Exception ("Assertion failure: ""{0}"" expected, ""{1}"" got" -f $Type, $Blueprint.Prerequisites.Item.SubtypeId)
            }
            
            If ( $Blueprint.Result -ne $Null )
            {
                $ResultAmount = [Double]$Blueprint.Result.Amount
            }
            Else
            {
                ForEach ( $Child in $Blueprint.Results.ChildNodes )
                {
                    If ( $Child.SubtypeId -eq $Type )
                    {
                        $ResultAmount = [Double]$Child.Amount
                        Break;
                    }
                }
            }
            
            $RequiredOreAmount = $Preq / $ResultAmount
            $RequiredOreMass = (Get-Ore $Type).Mass * $RequiredOreAmount
            $RequiredOreVolume = (Get-Ore $Type).Volume * $RequiredOreAmount
            
            $Ingots[ $Type ][ "RequiredOreMass" ] = $RequiredOreMass
            $Ingots[ $Type ][ "RequiredOreVolume" ] = $RequiredOreVolume
        }
    }
    # Fix for gravel
    $Ingots[ "Stone" ].RequiredOreMass = 1.0
    $Ingots[ "Stone" ].RequiredOreVolume = 1.0

    $IngotsKeys = [String[]]$Ingots.Keys
    ForEach ( $Key in $IngotsKeys )
    {
        $Props = $Ingots[ $Key ]
        $Ingots[ $Key ] = New-Object PSObject -Property $Props
    }
}

Function Get-Ingot
{
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param
    (
        [Parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [String]
        $Name,
        
        [Parameter(Mandatory=$True,ParameterSetName="All")]
        [Switch]
        $All
    )
    
    Switch ( $PSCmdlet.ParameterSetName )
    {
        "Name"
        {
            If ( -not $Ingots.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such ingot ""{0}""" -f $Name)
            }
            Return $Ingots[ $Name ]
        }
        
        "All"
        {
            Return $Ingots.Values
        }
    }
}

# COMPONENTS SECTION
$Components = @{}
[String[]]$ComponentsBlackList = , "ZoneChip"
& {
    ForEach ( $File in Get-Item SE:\Components*.sbc )
    {
        ForEach ( $Comp in (Get-XmlDocument $File.FullName).Definitions.Components.Component )
        {
            $TypeId = $Comp.Id.TypeID
            $SubtypeId = $Comp.Id.SubtypeId
            $Name = $TypeId + '.' + $SubtypeId
            If ( $ComponentsBlackList -contains $SubtypeId ) { Continue; }
            
            [Double]$Mass = $Comp.Mass
            [Double]$Volume = $Comp.Volume
            
            $Components[ $SubtypeId ] = @{
                Name = $SubtypeId;
                FullName = $Name;
                Mass = $Mass;
                Volume = $Volume;
            }
        }
    }

    ForEach ( $Blueprint in (Get-XmlDocument SE:\Blueprints.sbc).Definitions.Blueprints.Blueprint )
    {
        $TypeId = $Blueprint.Id.TypeId
        $SubtypeId = $Blueprint.Id.SubtypeId
        If ( -not $Components.ContainsKey( $SubtypeId ) ) { Continue; }
        
        $ResAmount = [Double]$Blueprint.Result.Amount
        $Requirements = [Hashtable[]]@( & {
            ForEach ( $Req in $Blueprint.Prerequisites.ChildNodes )
            {
                If ( $Req.TypeId -ne "Ingot" ) { Throw New-Object Exception ("In blueprint ""{0}"", prerequisite for non-ingot ""{1}.{2}""" -f $SubtypeId, $Req.TypeId, $Req.SubtypeId) }
                @{
                    Amount = [Double]$Req.Amount;
                    Ingot = (Get-Ingot $Req.SubtypeId);
                }
            }
        })
        
        $Prerequisites = @{}
        [Double]$RequiredIngotsMass = 0.0
        [Double]$RequiredIngotsVolume = 0.0
        [Double]$RequiredOresMass = 0.0
        [Double]$RequiredOresVolume = 0.0
        $RequiredIngots = New-Object ([System.Collections.Generic.Dictionary[String,PSObject]]).FullName
        $RequiredOres = New-Object ([System.Collections.Generic.Dictionary[String,PSObject]]).FullName
        ForEach ( $Preq in ($Requirements | Sort-Object -Property @{Expression={$_.Ingot.Name};Ascending=$True;}) )
        {
            $Prerequisites[ $Preq.Ingot.Name ] = $Preq.Amount
            $IngotMass = $Preq.Amount * $Preq.Ingot.Mass
            $IngotVolume = $Preq.Amount * $Preq.Ingot.Volume
            $OreMass = $Preq.Amount * $Preq.Ingot.RequiredOreMass
            $OreVolume = $Preq.Amount * $Preq.Ingot.RequiredOreVolume
            $RequiredIngotsMass += $IngotMass
            $RequiredIngotsVolume += $IngotVolume
            $RequiredOresMass += $OreMass
            $RequiredOresVolume += $OreVolume
            $RequiredIngots.Add( $Preq.Ingot.Name, (New-Object PSObject -Property @{Mass = $IngotMass; Volume = $IngotVolume;}) )
            $RequiredOres.Add( $Preq.Ingot.Name, (New-Object PSObject -Property @{Mass = $OreMass; Volume = $OreVolume;}) )
        }
        $Components[ $SubtypeId ][ "RequiredIngotsMass" ] = $RequiredIngotsMass
        $Components[ $SubtypeId ][ "RequiredIngotsVolume" ] = $RequiredIngotsVolume
        $Components[ $SubtypeId ][ "RequiredIngots" ] = $RequiredIngots
        $Components[ $SubtypeId ][ "RequiredOresMass" ] = $RequiredOresMass
        $Components[ $SubtypeId ][ "RequiredOresVolume" ] = $RequiredOresVolume
        $Components[ $SubtypeId ][ "RequiredOres" ] = $RequiredOres
    }

    $ComponentsKeys = [String[]]$Components.Keys
    ForEach ( $Key in $ComponentsKeys )
    {
        $Props = $Components[ $Key ]
        $Components[ $Key ] = New-Object PSObject -Property $Props
    }
}

Function Get-Component
{
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param
    (
        [Parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [String]
        $Name,
        
        [Parameter(Mandatory=$True,ParameterSetName="All")]
        [Switch]
        $All
    )
    
    Switch ( $PSCmdlet.ParameterSetName )
    {
        "Name"
        {
            If ( -not $Components.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such component ""{0}""" -f $Name)
            }
            Return $Components[ $Name ]
        }
        
        "All"
        {
            Return $Components.Values
        }
    }
}

# BLOCKS SECTION

$Blocks = @{}

& { 
    ForEach ( $File in Get-Item SE:\CubeBlocks\CubeBlocks*.sbc )
    {
        ForEach ( $Def in (Get-XmlDocument $File.FullName).Definitions.CubeBlocks.Definition )
        {
            $TypeId = $Def.Id.TypeId
            $SubtypeId = $Def.Id.SubtypeId
            $Name = ($TypeId + '.' + $SubtypeId).Trim( '.' )
            $Size = $Def.CubeSize
            $IsAirTight = $Def.IsAirTight -eq "true"
            
            $Components = @{} # Key: component subtype string, Value: integer amount used
            ForEach ( $Comp in [System.Xml.XmlElement[]]@($Def.Components.Component) )
            {
                $Subtype = $Comp.Subtype
                $Amount = [Int32]($Comp.Count)
                If ( -not $Components.ContainsKey( $Subtype ) )
                {
                    $Components[ $Subtype ] = 0
                }
                $Components[ $Subtype ] += $Amount
            }
            
            [Double]$TotalMass = 0.0 # Inherently identical to RequiredComponentsMass
            [Double]$RequiredComponentsVolume = 0.0
            $Ingots = @{} # Key: ingot subtype string, value: float amount used
            ForEach ( $CompName in $Components.Keys )
            {
                $Comp = Get-Component $CompName
                $Amount = $Components[ $CompName ]
                $TotalMass += $Comp.Mass * $Amount
                $RequiredComponentsVolume += $Comp.Volume * $Amount
            }
        }
    }
}

Function Get-Block
{
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param
    (
        # Allows star expansion
        [Parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [String]
        $Name,
        
        [Parameter(Position=1)]
        [ValidateSet("*","Small","Large")]
        [String]
        $BlockSize = "*",
        
        [Parameter(Mandatory=$True,ParameterSetName="All")]
        [Switch]
        $All
    )
}

Export-ModuleMember Get-Ore, Get-Ingot, Get-Component, Get-Block