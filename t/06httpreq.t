use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use Test::Exception;
use Scalar::Util qw/refaddr/;
use TestHttpServer;
use LWP::UserAgent;

plan tests => 1;

my $http_request = HTTP::Request->new(
	'GET',
	baseuri('echo'),
	[ 'X-Monkey' => 'Killer Gorilla' ],
	);

my $web_magic = W( $http_request );

like
	$web_magic,
	qr{ (X-Monkey) \s* (:) \s* (Killer\sGorilla) }ix,
	'Can instantiate Web::Magic from HTTP::Request object.';