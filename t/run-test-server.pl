#!/usr/bin/perl
use strict;
use lib "lib";
use lib "t/lib";

BEGIN {
	$ENV{PERL_WEB_MAGIC_VERBOSE} = 1;
}

use TestHttpServer;

print "Type 'exit' to finish...\n";
while (<>)
{
	exit if /exit/i;
}
