use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use Test::Exception;
use Scalar::Util qw/refaddr/;
use TestHttpServer;

plan tests => 12;

my $json = W( baseuri('ex_json') );
isa_ok $json => 'Web::Magic';

ok(!$json->is_requested, "request is deferred");
is(refaddr($json->do_request), refaddr($json), 'do_request can be chained');
ok($json->is_requested, "request has now happened");

lives_and { is refaddr($json->assert_success), refaddr($json) }
	'assert_success';

lives_ok { $json->assert_response( type => sub { $_->content_type =~ /json/ } ) }
	'assert_response passing assertion';

throws_ok { $json->assert_response( type => sub { $_->content_type =~ /bison/ } ) }
	'Web::Magic::Exception::AssertionFailure',
	'assert_response failing assertion';
	
my $not_found;
lives_ok { $not_found = W( baseuri('not_found') )->assert_success }
	'assertion not checked before request';

throws_ok { $not_found->do_request }
	'Web::Magic::Exception::AssertionFailure',
	'assertion checked on request';

lives_ok { $not_found = W( baseuri('not_found') )->do_request }
	'requests for non-200-OK pages work fine';

like "$not_found", qr{<title.*>404</title>}, 'stringifies ok';

my $echo = W( baseuri('echo') );
like "$echo", qr{^ User-Agent: \s* Web::Magic / \d }xim, 'User-Agent header OK';
