use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic;
use Test::Exception;
use TestHttpServer;
use Test::More;

my $FN = __FILE__ . '.tmp';
plan tests => 2;

SKIP: {
	open FILE, '>', $FN
		or skip "Cannot write to temp file '$FN'.", 2;
	print FILE $FN;
	close FILE;
	
	my $jul1970 = 86400*183;
	utime $jul1970, $jul1970, $FN;
	
	my $magic = Web::Magic->new( baseuri('echo') )->save_as($FN);
	like "$magic", qr{If-Modified-Since}, "If-Modified-Since header sent";
	
	my $content = do { open my $fh, '<', $FN; local $/ = <$fh> };
	like $content, qr{^GET /echo HTTP}, "file saved";
	
	unlink $FN;
}