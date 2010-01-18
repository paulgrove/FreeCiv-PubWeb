#!/usr/bin/perl

use strict;
use warnings;

use Path::Class;
use Data::Dumper;

# find where we live
use FindBin qw($Bin);
# include our lib search path
use lib dir($Bin, "lib")->stringify;

use FreeCiv;

# create our test FreeCiv
my $fc = FreeCiv->new( {debug=>1} );

# expect a log on stdin
while (<>) {
	# parse the line
	$fc->_parse_log($_);
}

# dump the output
print Dumper $fc;
