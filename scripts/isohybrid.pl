#!/usr/bin/perl
## -----------------------------------------------------------------------
##
##   Copyright 2002-2008 H. Peter Anvin - All Rights Reserved
##   Copyright 2009 Intel Corporation; author: H. Peter Anvin
##
##   This program is free software; you can redistribute it and/or modify
##   it under the terms of the GNU General Public License as published by
##   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
##   Boston MA 02111-1307, USA; either version 2 of the License, or
##   (at your option) any later version; incorporated herein by reference.
##
## -----------------------------------------------------------------------

#
# Post-process an ISO 9660 image generated with mkisofs/genisoimage
# to allow "hybrid booting" as a CD-ROM or as a hard disk.
#

use bytes;
use Fcntl;

# User-specifyable options
%opt = (
    # Fake geometry (zipdrive-style...)
    'h'      => 64,
    's'      => 32,
    # Partition number
    'entry'  => 1,
    # Partition offset
    'offset' => 0,
    # Partition type
    'type'   => 0x17,		# "Windows hidden IFS"
    # MBR ID
    'id'     => undef,
);

%valid_range = (
    'h'      => [1, 256],
    's'      => [1, 63],
    'entry'  => [1, 4],
    'offset' => [0, 64],
    'type'   => [0, 255],
    'id'     => [0, 0xffffffff],
    'hd0'    => [0, 2],
    'partok' => [0, 1],
);

# Boolean options just set other options
%bool_opt = (
    'nohd0'    => ['hd0', 0],
    'forcehd0' => ['hd0', 1],
    'ctrlhd0'  => ['hd0', 2],
    'nopartok' => ['partok', 0],
    'partok'   => ['partok', 1],
);

sub usage() {
    print STDERR "Usage: $0 [options] filename.iso\n",
    "Options:\n",
    "  -h          Number of default geometry heads\n",
    "  -s          Number of default geometry sectors\n",
    "  -entry      Specify partition entry number (1-4)\n",
    "  -offset     Specify partition offset (default 0)\n",
    "  -type       Specify partition type (default 0x17)\n",
    "  -id         Specify MBR ID (default random)\n",
    "  -forcehd0   Always assume we are loaded as disk ID 0\n",
    "  -ctrlhd0    Assume disk ID 0 if the Ctrl key is pressed\n",
    "  -partok     Allow booting from within a partition\n";
    exit 1;
}

# Parse a C-style integer (decimal/octal/hex)
sub doh($) {
    my($n) = @_;
    return ($n =~ /^0/) ? oct $n : $n+0;
}

sub get_random() {
    # Get a 32-bit random number
    my $rfd, $rnd;
    my $rid;

    if (open($rfd, "< /dev/urandom\0") && read($rfd, $rnd, 4) == 4) {
	$rid = unpack("V", $rnd);
    }

    close($rfd) if (defined($rfd));
    return $rid if (defined($rid));

    # This sucks but is better than nothing...
    return ($$+time()) & 0xffffffff;
}

sub get_hex_data() {
    my $mbr = '';
    my $line, $byte;
    while ( $line = <DATA> ) {
	chomp $line;
	last if ($line eq '*');
	foreach $byte ( split(/\s+/, $line) ) {
	    $mbr .= chr(hex($byte));
	}
    }
    return $mbr;
}

while ($ARGV[0] =~ /^\-(.*)$/) {
    $o = $1;
    shift @ARGV;
    if (defined($bool_opt{$o})) {
	($o, $v) = @{$bool_opt{$o}};
	$opt{$o} = $v;
    } elsif (exists($opt{$o})) {
	$opt{$o} = doh(shift @ARGV);
	if (defined($valid_range{$o})) {
	    ($l, $h) = @{$valid_range{$o}};
	    if ($opt{$o} < $l || $opt{$o} > $h) {
		die "$0: valid values for the -$o parameter are $l to $h\n";
	    }
	}
    } else {
	usage();
    }
}

($file) = @ARGV;

if (!defined($file)) {
    usage();
}

open(FILE, "+< $file\0") or die "$0: cannot open $file: $!\n";
binmode FILE;

#
# First, actually figure out where mkisofs hid isolinux.bin
#
seek(FILE, 17*2048, SEEK_SET) or die "$0: $file: $!\n";
read(FILE, $boot_record, 2048) == 2048 or die "$0: $file: read error\n";
($br_sign, $br_cat_offset) = unpack("a71V", $boot_record);
if ($br_sign ne ("\0CD001\1EL TORITO SPECIFICATION" . ("\0" x 41))) {
    die "$0: $file: no boot record found\n";
}
seek(FILE, $br_cat_offset*2048, SEEK_SET) or die "$0: $file: $!\n";
read(FILE, $boot_cat, 2048) == 2048 or die "$0: $file: read error\n";

# We must have a Validation Entry followed by a Default Entry...
# no fanciness allowed for the Hybrid mode [XXX: might relax this later]
@ve = unpack("v16", $boot_cat);
$cs = 0;
for ($i = 0; $i < 16; $i++) {
    $cs += $ve[$i];
}
if ($ve[0] != 0x0001 || $ve[15] != 0xaa55 || $cs & 0xffff) {
    die "$0: $file: invalid boot catalog\n";
}
($de_boot, $de_media, $de_seg, $de_sys, $de_mbz1, $de_count, 
 $de_lba, $de_mbz2) = unpack("CCvCCvVv", substr($boot_cat, 32, 32));
if ($de_boot != 0x88 || $de_media != 0 ||
    ($de_segment != 0 && $de_segment != 0x7c0) || $de_count != 4) {
    die "$0: $file: unexpected boot catalog parameters\n";
}

# Now $de_lba should contain the CD sector number for isolinux.bin
seek(FILE, $de_lba*2048+0x40, SEEK_SET) or die "$0: $file: $!\n";
read(FILE, $ibsig, 4);
if ($ibsig ne "\xfb\xc0\x78\x70") {
    die "$0: $file: bootloader does not have a isolinux.bin hybrid signature.".
        "Note that isolinux-debug.bin does not support hybrid booting.\n";
}

# Get the total size of the image
(@imgstat = stat(FILE)) or die "$0: $file: $!\n";
$imgsize = $imgstat[7];
if (!$imgsize) {
    die "$0: $file: cannot determine length of file\n";
}
# Target image size: round up to a multiple of $h*$s*512
$h = $opt{'h'};
$s = $opt{'s'};
$cylsize = $h*$s*512;
$frac = $imgsize % $cylsize;
$padding = ($frac > 0) ? $cylsize - $frac : 0;
$imgsize += $padding;
$c = int($imgsize/$cylsize);
if ($c > 1024) {
    print STDERR "Warning: more than 1024 cylinders ($c).\n";
    print STDERR "Not all BIOSes will be able to boot this device.\n";
    $cc = 1024;
} else {
    $cc = $c;
}

# Preserve id when run again
if (defined($opt{'id'})) {
    $id = pack("V", doh($opt{'id'}));
} else {
    seek(FILE, 440, SEEK_SET) or die "$0: $file: $!\n";
    read(FILE, $id, 4);
    if ($id eq "\x00\x00\x00\x00") {
	$id = pack("V", get_random());
    }
}

# Print the MBR and partition table
seek(FILE, 0, SEEK_SET) or die "$0: $file: $!\n";

for ($i = 0; $i <= $opt{'hd0'}+3*$opt{'partok'}; $i++) {
    $mbr = get_hex_data();
}
if ( length($mbr) > 432 ) {
    die "$0: Bad MBR code\n";
}

$mbr .= "\0" x (432 - length($mbr));

$mbr .= pack("VV", $de_lba*4, 0); 	# Offset 432: LBA of isolinux.bin
$mbr .= $id;				# Offset 440: MBR ID
$mbr .= "\0\0";				# Offset 446: actual partition table

# Print partition table
$offset  = $opt{'offset'};
$psize   = $c*$h*$s - $offset;
$bhead   = int($offset/$s) % $h;
$bsect   = ($offset % $s) + 1;
$bcyl    = int($offset/($h*$s));
$bsect  += ($bcyl & 0x300) >> 2;
$bcyl   &= 0xff;
$ehead   = $h-1;
$esect   = $s + ((($cc-1) & 0x300) >> 2);
$ecyl    = ($cc-1) & 0xff;
$fstype  = $opt{'type'};	# Partition type
$pentry  = $opt{'entry'};	# Partition slot

for ( $i = 1 ; $i <= 4 ; $i++ ) {
    if ( $i == $pentry ) {
	$mbr .= pack("CCCCCCCCVV", 0x80, $bhead, $bsect, $bcyl, $fstype,
		     $ehead, $esect, $ecyl, $offset, $psize);
    } else {
	$mbr .= "\0" x 16;
    }
}
$mbr .= "\x55\xaa";

print FILE $mbr;

# Pad the image to a fake cylinder boundary
seek(FILE, $imgstat[7], SEEK_SET) or die "$0: $file: $!\n";
if ($padding) {
    print FILE "\0" x $padding;
}

# Done...
close(FILE);

exit 0;
__END__
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 66 53
66 51 6 57 8e dd 8e c5 52 be 0 7c bf 0 6 b9 0 1 f3 a5 ea 4b 6 0 0 52 b4 41
bb aa 55 31 c9 30 f6 f9 cd 13 72 16 81 fb 55 aa 75 10 83 e1 1 74 b 66 c7 6
f1 6 b4 42 eb 15 eb 0 5a 51 b4 8 cd 13 83 e1 3f 5b 51 f b6 c6 40 50 f7 e1
53 52 50 bb 0 7c b9 4 0 66 a1 b0 7 e8 44 0 f 82 80 0 66 40 80 c7 2 e2 f2 66
81 3e 40 7c fb c0 78 70 75 9 fa bc ec 7b ea 44 7c 0 0 e8 83 0 69 73 6f 6c
69 6e 75 78 2e 62 69 6e 20 6d 69 73 73 69 6e 67 20 6f 72 20 63 6f 72 72 75
70 74 2e d a 66 60 66 31 d2 66 3 6 f8 7b 66 13 16 fc 7b 66 52 66 50 6 53 6a
1 6a 10 89 e6 66 f7 36 e8 7b c0 e4 6 88 e1 88 c5 92 f6 36 ee 7b 88 c6 8 e1
41 b8 1 2 8a 16 f2 7b cd 13 8d 64 10 66 61 c3 e8 1e 0 4f 70 65 72 61 74 69
6e 67 20 73 79 73 74 65 6d 20 6c 6f 61 64 20 65 72 72 6f 72 2e d a 5e ac b4
e 8a 3e 62 4 b3 7 cd 10 3c a 75 f1 cd 18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 
*
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 66 53
66 51 6 57 8e dd 8e c5 b2 80 52 be 0 7c bf 0 6 b9 0 1 f3 a5 ea 4d 6 0 0 52
b4 41 bb aa 55 31 c9 30 f6 f9 cd 13 72 16 81 fb 55 aa 75 10 83 e1 1 74 b 66
c7 6 f3 6 b4 42 eb 15 eb 0 5a 51 b4 8 cd 13 83 e1 3f 5b 51 f b6 c6 40 50 f7
e1 53 52 50 bb 0 7c b9 4 0 66 a1 b0 7 e8 44 0 f 82 80 0 66 40 80 c7 2 e2 f2
66 81 3e 40 7c fb c0 78 70 75 9 fa bc ec 7b ea 44 7c 0 0 e8 83 0 69 73 6f
6c 69 6e 75 78 2e 62 69 6e 20 6d 69 73 73 69 6e 67 20 6f 72 20 63 6f 72 72
75 70 74 2e d a 66 60 66 31 d2 66 3 6 f8 7b 66 13 16 fc 7b 66 52 66 50 6 53
6a 1 6a 10 89 e6 66 f7 36 e8 7b c0 e4 6 88 e1 88 c5 92 f6 36 ee 7b 88 c6 8
e1 41 b8 1 2 8a 16 f2 7b cd 13 8d 64 10 66 61 c3 e8 1e 0 4f 70 65 72 61 74
69 6e 67 20 73 79 73 74 65 6d 20 6c 6f 61 64 20 65 72 72 6f 72 2e d a 5e ac
b4 e 8a 3e 62 4 b3 7 cd 10 3c a 75 f1 cd 18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 
*
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 66 53
66 51 6 57 8e dd 8e c5 60 b4 2 cd 16 a8 4 61 74 2 b2 80 52 be 0 7c bf 0 6
b9 0 1 f3 a5 ea 57 6 0 0 52 b4 41 bb aa 55 31 c9 30 f6 f9 cd 13 72 16 81 fb
55 aa 75 10 83 e1 1 74 b 66 c7 6 fd 6 b4 42 eb 15 eb 0 5a 51 b4 8 cd 13 83
e1 3f 5b 51 f b6 c6 40 50 f7 e1 53 52 50 bb 0 7c b9 4 0 66 a1 b0 7 e8 44 0
f 82 80 0 66 40 80 c7 2 e2 f2 66 81 3e 40 7c fb c0 78 70 75 9 fa bc ec 7b
ea 44 7c 0 0 e8 83 0 69 73 6f 6c 69 6e 75 78 2e 62 69 6e 20 6d 69 73 73 69
6e 67 20 6f 72 20 63 6f 72 72 75 70 74 2e d a 66 60 66 31 d2 66 3 6 f8 7b
66 13 16 fc 7b 66 52 66 50 6 53 6a 1 6a 10 89 e6 66 f7 36 e8 7b c0 e4 6 88
e1 88 c5 92 f6 36 ee 7b 88 c6 8 e1 41 b8 1 2 8a 16 f2 7b cd 13 8d 64 10 66
61 c3 e8 1e 0 4f 70 65 72 61 74 69 6e 67 20 73 79 73 74 65 6d 20 6c 6f 61
64 20 65 72 72 6f 72 2e d a 5e ac b4 e 8a 3e 62 4 b3 7 cd 10 3c a 75 f1 cd
18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 
*
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 21 f6
74 26 f6 4 7f 75 21 38 4c 4 74 1c 66 3d 21 47 50 58 75 10 80 7c 4 ed 75 a
66 8b 4c 34 66 8b 5c 38 eb 4 66 8b 4c 8 66 53 66 51 6 57 8e dd 8e c5 52 be
0 7c bf 0 6 b9 0 1 f3 a5 ea 75 6 0 0 52 b4 41 bb aa 55 31 c9 30 f6 f9 cd 13
72 16 81 fb 55 aa 75 10 83 e1 1 74 b 66 c7 6 1b 7 b4 42 eb 15 eb 0 5a 51 b4
8 cd 13 83 e1 3f 5b 51 f b6 c6 40 50 f7 e1 53 52 50 bb 0 7c b9 4 0 66 a1 b0
7 e8 44 0 f 82 80 0 66 40 80 c7 2 e2 f2 66 81 3e 40 7c fb c0 78 70 75 9 fa
bc ec 7b ea 44 7c 0 0 e8 83 0 69 73 6f 6c 69 6e 75 78 2e 62 69 6e 20 6d 69
73 73 69 6e 67 20 6f 72 20 63 6f 72 72 75 70 74 2e d a 66 60 66 31 d2 66 3
6 f8 7b 66 13 16 fc 7b 66 52 66 50 6 53 6a 1 6a 10 89 e6 66 f7 36 e8 7b c0
e4 6 88 e1 88 c5 92 f6 36 ee 7b 88 c6 8 e1 41 b8 1 2 8a 16 f2 7b cd 13 8d
64 10 66 61 c3 e8 1e 0 4f 70 65 72 61 74 69 6e 67 20 73 79 73 74 65 6d 20
6c 6f 61 64 20 65 72 72 6f 72 2e d a 5e ac b4 e 8a 3e 62 4 b3 7 cd 10 3c a
75 f1 cd 18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 
*
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 21 f6
74 26 f6 4 7f 75 21 38 4c 4 74 1c 66 3d 21 47 50 58 75 10 80 7c 4 ed 75 a
66 8b 4c 34 66 8b 5c 38 eb 4 66 8b 4c 8 66 53 66 51 6 57 8e dd 8e c5 b2 80
52 be 0 7c bf 0 6 b9 0 1 f3 a5 ea 77 6 0 0 52 b4 41 bb aa 55 31 c9 30 f6 f9
cd 13 72 16 81 fb 55 aa 75 10 83 e1 1 74 b 66 c7 6 1d 7 b4 42 eb 15 eb 0 5a
51 b4 8 cd 13 83 e1 3f 5b 51 f b6 c6 40 50 f7 e1 53 52 50 bb 0 7c b9 4 0 66
a1 b0 7 e8 44 0 f 82 80 0 66 40 80 c7 2 e2 f2 66 81 3e 40 7c fb c0 78 70 75
9 fa bc ec 7b ea 44 7c 0 0 e8 83 0 69 73 6f 6c 69 6e 75 78 2e 62 69 6e 20
6d 69 73 73 69 6e 67 20 6f 72 20 63 6f 72 72 75 70 74 2e d a 66 60 66 31 d2
66 3 6 f8 7b 66 13 16 fc 7b 66 52 66 50 6 53 6a 1 6a 10 89 e6 66 f7 36 e8
7b c0 e4 6 88 e1 88 c5 92 f6 36 ee 7b 88 c6 8 e1 41 b8 1 2 8a 16 f2 7b cd
13 8d 64 10 66 61 c3 e8 1e 0 4f 70 65 72 61 74 69 6e 67 20 73 79 73 74 65
6d 20 6c 6f 61 64 20 65 72 72 6f 72 2e d a 5e ac b4 e 8a 3e 62 4 b3 7 cd 10
3c a 75 f1 cd 18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 
*
33 ed 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90 90
90 90 90 90 90 90 90 33 ed fa 8e d5 bc 0 7c fb fc 66 31 db 66 31 c9 21 f6
74 26 f6 4 7f 75 21 38 4c 4 74 1c 66 3d 21 47 50 58 75 10 80 7c 4 ed 75 a
66 8b 4c 34 66 8b 5c 38 eb 4 66 8b 4c 8 66 53 66 51 6 57 8e dd 8e c5 60 b4
2 cd 16 a8 4 61 74 2 b2 80 52 be 0 7c bf 0 6 b9 0 1 f3 a5 ea 81 6 0 0 52 b4
41 bb aa 55 31 c9 30 f6 f9 cd 13 72 16 81 fb 55 aa 75 10 83 e1 1 74 b 66 c7
6 27 7 b4 42 eb 15 eb 0 5a 51 b4 8 cd 13 83 e1 3f 5b 51 f b6 c6 40 50 f7 e1
53 52 50 bb 0 7c b9 4 0 66 a1 b0 7 e8 44 0 f 82 80 0 66 40 80 c7 2 e2 f2 66
81 3e 40 7c fb c0 78 70 75 9 fa bc ec 7b ea 44 7c 0 0 e8 83 0 69 73 6f 6c
69 6e 75 78 2e 62 69 6e 20 6d 69 73 73 69 6e 67 20 6f 72 20 63 6f 72 72 75
70 74 2e d a 66 60 66 31 d2 66 3 6 f8 7b 66 13 16 fc 7b 66 52 66 50 6 53 6a
1 6a 10 89 e6 66 f7 36 e8 7b c0 e4 6 88 e1 88 c5 92 f6 36 ee 7b 88 c6 8 e1
41 b8 1 2 8a 16 f2 7b cd 13 8d 64 10 66 61 c3 e8 1e 0 4f 70 65 72 61 74 69
6e 67 20 73 79 73 74 65 6d 20 6c 6f 61 64 20 65 72 72 6f 72 2e d a 5e ac b4
e 8a 3e 62 4 b3 7 cd 10 3c a 75 f1 cd 18 f4 eb fd 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 
*
