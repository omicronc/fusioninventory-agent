package FusionInventory::Agent::Task::Inventory::Solaris::Bios;

use strict;
use warnings;

use Config;

use FusionInventory::Agent::Tools;
use FusionInventory::Agent::Tools::Solaris;

sub isEnabled {
    return
        canRun('showrev') ||
        canRun('/usr/sbin/smbios');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    my $arch = $Config{Archname} =~ /^i86pc/ ? 'i386' : 'sparc';

    my ($bios, $hardware);

    if (getZone() eq 'global') {
        if (canRun('showrev')) {
            my $infos = _parseShowRev(logger => $logger);
            $bios->{SMODEL}        = $infos->{'Application architecture'};
            $bios->{SMANUFACTURER} = $infos->{'Hardware provider'};
        }

        if ($arch eq "i386") {
            my $infos = _parseSmbios(logger => $logger);

            my $biosInfos = $infos->{SMB_TYPE_BIOS};
            $bios->{BMANUFACTURER} = $biosInfos->{'Vendor'};
            $bios->{BVERSION}      = $biosInfos->{'Version String'};
            $bios->{BDATE}         = $biosInfos->{'Release Date'};

            my $systemInfos = $infos->{SMB_TYPE_SYSTEM};
            $bios->{SMANUFACTURER} = $systemInfos->{'Manufacturer'};
            $bios->{SMODEL}        = $systemInfos->{'Product'};
            $bios->{SKUNUMBER}     = $systemInfos->{'SKU Number'};
            $hardware->{UUID}      = $systemInfos->{'UUID'};

            my $motherboardInfos = $infos->{SMB_TYPE_BASEBOARD};
            $bios->{MMODEL}        = $motherboardInfos->{'Product'};
            $bios->{MSN}           = $motherboardInfos->{'Serial Number'};
            $bios->{MMANUFACTURER} = $motherboardInfos->{'Manufacturer'};
        } else {
            my $infos = _parsePrtconf(logger => $logger);
            $bios->{SMODEL} = $infos->{'banner-name'};
            $bios->{SMODEL} .= " ($infos->{name})" if $infos->{name};

            # looks like : "OBP 4.16.4 2004/12/18 05:18"
            #    with further informations sometime
            if ($infos->{version} =~ m{OBP\s+([\d|\.]+)\s+(\d+)/(\d+)/(\d+)}) {
                $bios->{BVERSION} = "OBP $1";
                $bios->{BDATE}    = "$2/$3/$4";
            } else {
                $bios->{BVERSION} = $infos->{version};
            }

            my $command = -x '/opt/SUNWsneep/bin/sneep' ?
                '/opt/SUNWsneep/bin/sneep' : 'sneep';

            $bios->{SSN} = getFirstLine(
                command => $command,
                logger  => $logger
            );
        }
    } else {
        my $infos = _parseShowRev(logger => $logger);
        $bios->{SMANUFACTURER} = $infos->{'Hardware provider'};
        $bios->{SMODEL}        = "Solaris Containers";
    }

    #On SPARC, get the UUID by using zoneadmin command (on a container or a global zone)
    if ($arch eq 'sparc') {
        # Get hardware UUID on SPARC
        # Note: zoneadmin list -p return line like "1:zone8:running:/:93f3f07e-3f28-c786-b52b-a3df3020dcdb:native:shared"
        # If test is done on a global zone, add " | grep -v global" to command to emulate as if we were on a local zone
        my $firstlinezoneadm = getFirstLine(command => '/usr/sbin/zoneadm list -p', logger => $logger);
        $logger->debug2("First line of zoneadm list -p is not global, so we can set the hardware uuid.");
        my ($zoneid, $zonename, $zonestatus, undef, $uuid) = split(/:/, $firstlinezoneadm);
        if ($uuid) {
            $hardware->{UUID} = $uuid;
        }
    }
    $inventory->setBios($bios);
    $inventory->setHardware($hardware);
}

sub _parseShowRev {
    my (%params) = (
        command => 'showrev',
        @_
    );

    my $handle = getFileHandle(%params);
    return unless $handle;

    my $infos;
    while (my $line = <$handle>) {
        next unless $line =~ /^ ([^:]+) : \s+ (\S+)/x;
        $infos->{$1} = $2;
    }
    close $handle;

    return $infos;
}

sub _parseSmbios {
    my (%params) = (
        command => '/usr/sbin/smbios',
        @_
    );

    my $handle = getFileHandle(%params);
    return unless $handle;

    my ($infos, $current);
    while (my $line = <$handle>) {
        if ($line =~ /^ \d+ \s+ \d+ \s+ (\S+)/x) {
            $current = $1;
            next;
        }

        if ($line =~ /^ \s* ([^:]+) : \s* (.+) $/x) {
            $infos->{$current}->{$1} = $2;
            next;
        }
    }
    close $handle;

    return $infos;
}

sub _parsePrtconf {
    my (%params) = (
        command => '/usr/sbin/prtconf -pv',
        @_
    );

    my $handle = getFileHandle(%params);
    return unless $handle;

    my $infos;
    while (my $line = <$handle>) {
        next unless $line =~ /^ \s* ([^:]+) : \s* ' (.+) '$/x;
        next if $infos->{$1};
        $infos->{$1} = $2;
    }
    close $handle;

    return $infos;
}

1;
