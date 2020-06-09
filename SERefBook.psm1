New-PSDrive -Name SE -PSProvider FileSystem -Root 'E:\Steam\steamapps\common\SpaceEngineers\Content\Data'

Function Get-XmlDocument ( [String]$Path )
{
    $Ret = New-Object System.Xml.XmlDocument
    $Ret.Load( (Get-Item $Path).OpenText() )
    Return $Ret
}

# ORES SECTION
$Ores = @{}
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
ForEach ( $PhysItem in (Get-XmlDocument SE:\PhysicalItems.sbc).Definitions.PhysicalItems.PhysicalItem )
{
    If ( $PhysItem.Id.TypeId -ne "Ingot" -or $IngotsBlackList -contains $PhysItem.Id.SubtypeId ) { Continue; }
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
        [Double]$Res = $Blueprint.Result.Amount
        [Double]$Req = $Preq / $Res
        [Double]$OresMass = $Req * $Ores[ $Type ].Mass
        [Double]$OresVolume = $Req * $Ores[ $Type ].Volume
        
        $Ingots[ $Type ][ "RequiredOreMass" ] = $OresMass
        $Ingots[ $Type ][ "RequiredOreVolume" ] = $OresVolume
    }
}
$IngotsKeys = [String[]]$Ingots.Keys
ForEach ( $Key in $IngotsKeys )
{
    $Props = $Ingots[ $Key ]
    $Ingots[ $Key ] = New-Object PSObject -Property $Props
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

Export-ModuleMember Get-Ore, Get-Ingot