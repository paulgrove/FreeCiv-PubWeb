#
#===============================================================================
#
#         FILE:  00load.t
#
#  DESCRIPTION:  
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Gordon Irving (), <Gordon.irving@sophos.com>
#      COMPANY:  Sophos
#      VERSION:  1.0
#      CREATED:  18/01/10 22:26:35 GMT
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;

use Test::More tests => 1;                      # last test to print


use FindBin qw($Bin);
use Path::Class;
use lib dir($Bin,"..","lib")->cleanup->stringify;

use_ok 'FreeCiv';
