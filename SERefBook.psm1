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
        If ( $Mass -ne 1.0 ) { Throw New-Object Exception ("Assertion failure: ore ""{0}"" has non-unit mass ({1:F3}kg)" -f $SubtypeId, $Mass) }
        [Double]$Volume = $PhysItem.Volume
        $Ores[ $SubtypeId ] = New-Object PSObject -Property @{
            Name = $SubtypeId;
            FullName = $Name;
            #Mass = $Mass;
            Volume = $Volume;
            Density = 1.0/$Volume;
        }
    }
}

<# Ore object properties:
    Name : String
        Internal name for this particular ore, e.g. "Cobalt"
        
    FullName : String
        Complete qualified ID for this ore, e.g. "Ore.Cobalt"
    
    Volume : Double
        The specific volume of the ore, in Liters per Kilogram
    
    Density : Double
        The density of the ore, in Kilograms per Liter
#>
$_Ores = $Ores # Protection against scoping problems
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
            If ( -not $_Ores.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such ore ""{0}""" -f $Name)
            }
            Return $_Ores[ $Name ]
        }
        
        "All"
        {
            Return $_Ores.Values
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
        If ( $Mass -ne 1.0 ) { Throw New-Object Exception ("Assertion failure: ingot ""{0}"" has non-unit mass ({1:F3}kg)" -f $SubtypeId, $Mass) }
        [Double]$Volume = $PhysItem.Volume
        $Ingots[ $SubtypeId ] = @{
            Name = $SubtypeId;
            FullName = $Name;
            #Mass = $Mass;
            Volume = $Volume;
            Density = 1.0/$Volume;
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
            $RequiredOreVolume = (Get-Ore $Type).Volume * $RequiredOreAmount
            $RequiredOreVolumeRatio = $RequiredOreVolume / $Ingots[ $Type ].Volume
            
            $Ingots[ $Type ][ "RequiredOreMass" ] = $RequiredOreAmount
            $Ingots[ $Type ][ "RequiredOreVolume" ] = $RequiredOreVolume
            $Ingots[ $Type ][ "RequiredOreVolumeRatio" ] = $RequiredOreVolumeRatio
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

<# Ingot object properties:
    Name : String
        Internal name for this particular ingot, e.g. "Cobalt"
        
    FullName : String
        Complete qualified ID for this ingot, e.g. "Ingot.Cobalt"
    
    Volume : Double
        The specific volume of the ingot, in Liters per Kilogram
    
    Density : Double
        The density of the ingot, in Kilograms per Liter
    
    RequiredOreMass : Double
        With a stock refinery, the required mass in Kilograms of the corresponding ore which must be refined to produce 1kg of this ingot
    
    RequiredOreVolume : Double
        With a stock refinery, the required volume in Liters of the corresponding ore which must be refined to produce 1kg of this ingot
    
    RequiredOreVolumeRatio : Double
        With a stock refinery, the ratio of the Liters of corresponding ore required to produce 1L of this ingot
#>
$_Ingots = $Ingots # Protection against scoping problems
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
            If ( -not $_Ingots.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such ingot ""{0}""" -f $Name)
            }
            Return $_Ingots[ $Name ]
        }
        
        "All"
        {
            Return $_Ingots.Values
        }
    }
}

# COMPONENTS SECTION
$Script:Components = @{}
[String[]]$ComponentsBlackList = , "ZoneChip" # TODO: Need better way of handling zone chips
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

    ForEach ( $Blueprint in (Get-XmlDocument SE:\Blueprints.sbc).Definitions.Blueprints.Blueprint ) # TODO: Include economy blueprints?
    {
        If ( -not $Blueprint.Result ) { Continue; } # We're only looking for ones that produce a single output at the moment
        $TypeId = $Blueprint.Result.TypeId
        $SubtypeId = $Blueprint.Result.SubtypeId
        If ( $TypeId -ne "Component" -or -not $Components.ContainsKey( $SubtypeId ) ) { Continue; }
        
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
            $IngotMass = $Preq.Amount
            $IngotVolume = $Preq.Amount * $Preq.Ingot.Volume
            $OreMass = $Preq.Amount * $Preq.Ingot.RequiredOreMass
            $OreVolume = $Preq.Amount * $Preq.Ingot.RequiredOreVolume
            $RequiredIngotsMass += $IngotMass
            $RequiredIngotsVolume += $IngotVolume
            $RequiredOresMass += $OreMass
            $RequiredOresVolume += $OreVolume
            $RequiredIngots.Add( $Preq.Ingot.Name, (New-Object PSObject -Property @{Mass = $IngotMass; Volume = $IngotVolume; Definition = (Get-Ingot $Preq.Ingot.Name);}) )
            $RequiredOres.Add( $Preq.Ingot.Name, (New-Object PSObject -Property @{Mass = $OreMass; Volume = $OreVolume; Definition = (Get-Ore $Preq.Ingot.Name);}) )
        }
        $Components[ $SubtypeId ][ "RequiredIngotsMass" ] = $RequiredIngotsMass
        $Components[ $SubtypeId ][ "RequiredIngotsVolume" ] = $RequiredIngotsVolume
        # TODO: Figure out reliable way to ensure script runs on newer version of PS or .NET so we can cast from Dictionary to IReadOnlyDictionary
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

<# Component object properties:    
    Name : String
        Internal name for this particular component, e.g. "Girder"
        
    FullName : String
        Complete qualified ID for this component, e.g. "Component.Girder"
    
    Mass : Double
        Mass in Kilograms of 1 of this component
    
    Volume : Double
        Volume in Liters that 1 of this component takes up in an inventory
    
    RequiredIngots : Dictionary<Key,Value>
        Key : String
            Name of the ingot
        
        Value : Object
            Mass : Double
                Required mass in Kilograms (or number of) of ingots to make this component
            
            Volume : Double
                Required volume in Liters of ingots to make this component
            
            Definition : Object
                The ingot object, as returned by Get-Ingot
    
    RequiredIngotsMass : Double
        Total mass in Kilograms of all ingots required to make 1 of this component
    
    RequiredIngotsVolume : Double
        Total volume in Liters of all ingots required to make 1 of this component
    
    RequiredOres : Dictionary<Key,Value>
        Key : String
            Name of the ore
        
        Value : Object
            Mass : Double
                Required mass in Kilograms (or number of) of ore to make this component
            
            Volume : Double
                Required volume in Liters of ore to make this component
            
            Definition : Object
                The ore object, as returned by Get-Ore
            
    RequiredOresMass : Double
        Total mass in Kilograms of all ores required to make 1 of this component
    
    RequiredOresVolume : Double
        Total volume in Liters of all ores required to make 1 of this component
#>
$_Components = $Components # Protection against scoping problems
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
            If ( -not $_Components.ContainsKey( $Name ) )
            {
                Throw New-Object Exception ("No such component ""{0}""" -f $Name)
            }
            Return $_Components[ $Name ]
        }
        
        "All"
        {
            Return $_Components.Values
        }
    }
}

# BLOCKS SECTION

$Blocks = @{}
$CubeSizeScale = @{
    Small = 0.5;
    Large = 2.5;
}

& { 
    ForEach ( $File in Get-Item SE:\CubeBlocks\CubeBlocks*.sbc )
    {
        ForEach ( $Def in (Get-XmlDocument $File.FullName).Definitions.CubeBlocks.Definition )
        {
            # TODO: Special handling, try to eliminate later
            If ( @( $Def.Components.Component | %{ $_.Subtype } ) -contains "ZoneChip" ) { Continue; }
            
            $TypeId = $Def.Id.TypeId
            $SubtypeId = $Def.Id.SubtypeId
            $Name = ($TypeId + '.' + $SubtypeId).Trim( '.' )
            $Size = $Def.CubeSize
            $IsAirTight = $Def.IsAirTight -eq "true"
            
            $Components = @{} # Key: component subtype string, Value: integer number of components used
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
            
            # Calculate total components properties
            $RequiredComponents = New-Object ([System.Collections.Generic.Dictionary[String,PSObject]]).FullName
            ForEach ( $CompName in @($Components.Keys | Sort-Object) )
            {
                $Number = $Components[ $CompName ]
                $CompDef = Get-Component $CompName
                [Double]$CompMass = $Number * $CompDef.Mass
                [Double]$CompVolume = $Number * $CompDef.Volume
                $RequiredComponents.Add( $CompName, (New-Object PSObject -Property @{
                    Number = $Number;
                    Mass = $CompMass;
                    Volume = $CompVolume;
                    Definition = $CompDef;
                }) )
            }
            [Double]$RequiredComponentsMass = ($RequiredComponents.Values | Measure-Object -Sum -Property Mass).Sum
            [Double]$RequiredComponentsVolume = ($RequiredComponents.Values | Measure-Object -Sum -Property Volume).Sum
            
            # Calculate total ingots & ores properties
            $AmountsOfIngot = @{}
            ForEach ( $Component in $RequiredComponents.Values )
            {
                ForEach ( $Ingot in $Component.Definition.RequiredIngots.Values )
                {
                    $IngotName = $Ingot.Definition.Name
                    If ( -not $AmountsOfIngot.ContainsKey( $IngotName ) )
                    {
                        $AmountsOfIngot[ $IngotName ] = 0.0
                    }
                    $AmountsOfIngot[ $IngotName ] += $Component.Number * $Ingot.Mass;
                }
            }
            
            $RequiredIngots = New-Object ([System.Collections.Generic.Dictionary[String,PSObject]]).FullName
            $RequiredOres = New-Object ([System.Collections.Generic.Dictionary[String,PSObject]]).FullName
            ForEach ( $IngotName in @($AmountsOfIngot.Keys | Sort-Object) )
            {
                $IngotDef = Get-Ingot $IngotName
                $IngotMass = $AmountsOfIngot[ $IngotName ]
                $IngotVolume = $IngotMass * $IngotDef.Volume
                $OreMass = $IngotMass * $IngotDef.RequiredOreMass
                $OreVolume = $IngotMass * $IngotDef.RequiredOreVolume
                
                $RequiredIngots.Add( $IngotName, (New-Object PSObject -Property @{
                    Mass = $IngotMass;
                    Volume = $IngotVolume;
                    Definition = $IngotDef;
                }) )
                $RequiredOres.Add( $IngotName, (New-Object PSObject -Property @{
                    Mass = $OreMass;
                    Volume = $OreVolume;
                    Definition = (Get-Ore $IngotName);
                }) )
            }
            [Double]$RequiredIngotsMass = ($RequiredIngots.Values | Measure-Object -Sum -Property Mass).Sum
            [Double]$RequiredIngotsVolume = ($RequiredIngots.Values | Measure-Object -Sum -Property Volume).Sum
            [Double]$RequiredOresMass = ($RequiredOres.Values | Measure-Object -Sum -Property Mass).Sum
            [Double]$RequiredOresVolume = ($RequiredOres.Values | Measure-Object -Sum -Property Volume).Sum
            
            [Double]$BlockVolume = & {
                [Double]$Ret = 1.0
                [Double]$Scale = $CubeSizeScale[ $Size ]
                ForEach ( $Axis in "x", "y", "z" )
                {
                    [Double]$AxisSize = $Def.Size.$Axis
                    $Ret *= $AxisSize * $Scale
                }
                $Ret
            }
            
            $BlockObject = New-Object PSObject -Property @{
                TypeId = $TypeId;
                SubtypeId = $SubtypeId;
                Name = $Name;
                BlockSize = $Size;
                IsAirTight = $IsAirTight;
                
                # Not Mass, we're adding that as an AliasProperty later
                Volume = $BlockVolume;
                Density = $RequiredComponentsMass / $BlockVolume;
                
                RequiredComponents = $RequiredComponents;
                RequiredComponentsMass = $RequiredComponentsMass;
                RequiredComponentsVolume = $RequiredComponentsVolume;
                
                RequiredIngots = $RequiredIngots;
                RequiredIngotsMass = $RequiredIngotsMass;
                RequiredIngotsVolume = $RequiredIngotsVolume;
                
                RequiredOres = $RequiredOres;
                RequiredOresMass = $RequiredOresMass;
                RequiredOresVolume = $RequiredOresVolume;
            } | Add-Member -MemberType AliasProperty -Name Mass -Value RequiredComponentsMass -PassThru
            
            $Blocks[ $Name ] = $BlockObject
        } # End per-block
    } # End per-file
}

<# Block object properties:
    
#>
$_Blocks = $Blocks
Function Get-Block
{
    [CmdletBinding(DefaultParameterSetName="Name")]
    Param
    (
        # Allows star expansion
        [Parameter(Mandatory=$True,ParameterSetName="Name",Position=0)]
        [String]
        $Name,
        
        # Allows star expansion
        [Parameter(ParameterSetName="Ids")]
        [String]
        $TypeId = "*",
        
        # Allows star expansion
        [Parameter(ParameterSetName="Ids")]
        [String]
        $SubtypeId = "*",
        
        [ValidateSet("*","Small","Large")]
        [String]
        $BlockSize = "*",
        
        [Parameter(Mandatory=$True,ParameterSetName="All")]
        [Switch]
        $All
    )
    
    & { 
        Switch ( $PSCmdlet.ParameterSetName )
        {
            "Name"
            {
                $_Blocks.Values | Where-Object { $_.Name -like $Name }
            }
            
            "Ids"
            {
                $_Blocks.Values | Where-Object { $_.TypeId -like $TypeId -and $_.SubtypeId -like $SubtypeId }
            }
            
            "All"
            {
                $_Blocks.Values
            }
        } 
    } | Where-Object { $_.BlockSize -like $BlockSize } | Sort-Object -Property TypeId, BlockSize, SubtypeId
}

Export-ModuleMember Get-Ore, Get-Ingot, Get-Component, Get-Block