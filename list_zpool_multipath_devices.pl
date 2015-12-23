#!/usr/bin/perl

#
# 20151222 by Joe Adams, USGS
#          Conception and birth. Needed a quick tool to tie zpool
#          mulitpath devices to physical disk drives inside the
#          Dell MD3060e.
#
#          This script was written on and for:
#               CentOS Linux release 7.2.1511 (Core)
#               ZFS 0.6.5.3-1.el7.centos
#               Dell Storage Enclosure Management Software 1.3.0
#
#          Next time, try doing something with XML output from
#          "secli global topology".
#


#
# Globals
#

$debug = "";

$thisZpool = "sasc-zpool-1";

@zpoolDevices = "";
@multiPathMap = "";


# Print Header

print "\n\n     Lines missing a \"Status\" value are drives not actually in the Zpool.\n";
print     "     These are drives seen by Linux Multipath but not in use by ZFS.\n";
print     "     I ran out of time to perfect this script.\n";
print   "\n     Joe Adams - Dec. 22, 2015\n\n\n";

print `/usr/bin/date`;

print "\n     Zpool        Device   Slot   Status    Rev      SerialNum             WWN            ProductId     Vendor\n";


#
# Parse zpool status for mpath devices being used
#

@cmdOutput = `/usr/sbin/zpool status $thisZpool 2>&1`;

foreach my $line ( @cmdOutput ) {

	chomp( $line );

	print "thisLine = \"$line\"\n" if $debug;

	# example string =   mpathc  ONLINE       0     0     0

	if ( 2 == (  (  my $tmpDevice , my $tmpStatus ) = $line =~ /^\s+(mpath\w+)\s+(\w+)/ ) ) {

		print "\ntmpDevice= \"$tmpDevice\"\n" if $debug;
		print "tmpStatus= \"$tmpStatus\"\n\n" if $debug;

		$zpoolDevices{$thisZpool}{$tmpDevice}{'Status'} = $tmpStatus;
	}
}

#
# Pull multipath mapping
#

print "\n\n" if $debug;

@cmdOutput = `/usr/sbin/multipathd show maps 2>&1`;

foreach my $line ( @cmdOutput ) {

	chomp( $line );

	print "thisLine = \"$line\"\n" if $debug;

	# example string = mpathq dm-24 35000039538d14d88

	if ( 3 == ( my @tmpArray = split( /\s+/ , $line ) ) ) {

		print "\ntmpArray[0] = \"$tmpArray[0]\"\n" if $debug;
		print "tmpArray[1] = \"$tmpArray[1]\"\n" if $debug;
		print "tmpArray[2] = \"$tmpArray[2]\"\n\n" if $debug;

		if ( $tmpArray[0] ne 'name' ) {

			$zpoolDevices{$thisZpool}{$tmpArray[0]}{'dm'} = $tmpArray[1];
			$zpoolDevices{$thisZpool}{$tmpArray[0]}{'id'} = $tmpArray[2];

			print "zpoolDevices{$thisZpool}{$tmpArray[0]}{dm} = \"$zpoolDevices{$thisZpool}{$tmpArray[0]}{'dm'}\"\n" if $debug;
			print "zpoolDevices{$thisZpool}{$tmpArray[0]}{id} = \"$zpoolDevices{$thisZpool}{$tmpArray[0]}{'id'}\"\n\n" if $debug;
		}
	}
}


#
# Find device WWN from Linux devices
#

print "\n\n" if $debug;

foreach my $thisZpoolDevice ( sort keys $zpoolDevices{$thisZpool} ) {

	print "\nStart of foreach zpoolDevice\n\n" if $debug;

	# Get the sd device name

	print `/usr/bin/ls -lR /dev/disk/by-id/scsi-$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'id'} 2>&1` if $debug;

	# exampl string = lrwxrwxrwx 1 root root 10 Dec 21 17:06 /dev/disk/by-id/scsi-35000039538d13ccc -> ../../sdaj

	if ( 1 == (  (  my $tmpDevice ) = `/usr/bin/ls -lR /dev/disk/by-id/scsi-$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'id'} 2>&1` =~ /\.\.\/(\w+)$/ ) ) {

		print "tmpDevice = \"$tmpDevice\"\n" if $debug;

		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'sd'} = $tmpDevice;

	} else {  # I should not be here

		die "\n\n     Oops. Sorry. I give up. Im confused looking for the intermediate sd device for multipath device \"$thisZpoolDevice\". Let Joe know.\n\n";
	}

	# Get the WWN of a physical disk

	my $egrepString = "sas-0x.+$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'sd'}";

	print "egrepString = \"$egrepString\"\n" if $debug;

	print `/usr/bin/ls -lR /dev/disk/by-path 2>&1 | /usr/bin/egrep $egrepString 2>&1` if $debug;

	# exmaple string = lrwxrwxrwx 1 root root 10 Dec 21 17:06 pci-0000:1f:00.0-sas-0x5000039538d1363a-lun-0 -> ../../sdas

	if ( 1 == (  (  my $tmpWWN ) = `/usr/bin/ls -lR /dev/disk/by-path 2>&1 | /usr/bin/egrep $egrepString 2>&1` =~ /sas-0x(\w+)-lun/ ) ) {

		print "tmpWWN = \"$tmpWWN\"\n\n" if $debug;

		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'WWN'} = $tmpWWN;

	} else { # I should not be here

		die "\n\n     Oops. Sorry. I give up. Im confused looking for the WWN for multipath device \"$thisZpoolDevice\". Let Joe know.\n\n";
	}

	# Pull ProductId, Slot Number, Vendor, Serial, and Rev from secli info drive

	$cmdOutput = `/opt/dell/StorageEnclosureManagement/StorageEnclosureCLI/bin/secli info drive -d=$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'WWN'} 2>&1`; 

	print $cmdOutput if $debug;

	if ( 5 == ( ( $zpoolDevices{$thisZpool}{$thisZpoolDevice}{'ProductId'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Slot'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Vendor'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'SerialNum'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Rev'}
		  	) = $cmdOutput =~ /.+?ProductId: (\S+?)\s+.+?\s+Slot Number: (\d+)\s+.+?Vendor: (.+?)\s+.+?Serial: (.+?)\s+.+?Rev: (\S+)\s+/ms ) ) {

		print "ProductId = \"$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'ProductId'}\"\n" if $debug;
		print "Slot = \"$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Slot'}\"\n" if $debug;
		print "Vendor = \"$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Vendor'}\"\n" if $debug;
		print "SerialNum = \"$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'SerialNum'}\"\n" if $debug;
		print "Rev = \"$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Rev'}\"\n" if $debug;

	} else { # I should not be here.

		die "\n\n     Oops. Sorry. I give up. Im confused parsing the output of secli info drive for \"$thisZpoolDevice\". Let Joe know.\n\n";
	}


	# Print out results


	#print "     Zpool        Device   Slot   Status    Rev      SerialNum             WWN            ProductId     Vendor\n";

	printf( "  %s    %s    %2.2s    %s    %s    %s     %s     %s    %s\n",
		$thisZpool,
		$thisZpoolDevice,
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Slot'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Status'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Rev'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'SerialNum'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'WWN'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'ProductId'},
		$zpoolDevices{$thisZpool}{$thisZpoolDevice}{'Vendor'} );


	print "\n\nEnd of foreach zpoolDevice\n\n" if $debug;
}

print "\n\n";


