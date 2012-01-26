use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use Test::Exception;
use Scalar::Util qw/refaddr/;
use TestHttpServer;
use LWP::UserAgent;

plan tests => 14;

my $json = W( baseuri('ex_json') );
isa_ok($json->user_agent, 'LWP::UserAgent');

my $lwp  = LWP::UserAgent->new;

lives_and {
	$json->user_agent($lwp);
	is(refaddr($json->user_agent), refaddr($lwp));
	}
	'can set a user agent before request';

ok(!$json->is_requested);
$json->do_request;
ok($json->is_requested);

throws_ok {
	$json->user_agent($lwp);	
	}
	'Web::Magic::Exception::BadPhase',
	'cannot set a user agent after request';

ok(!defined Web::Magic->user_agent, 'No default global user agent.');
Web::Magic->user_agent( LWP::UserAgent->new(agent => 'MyFoo') );
ok(Web::Magic->user_agent, 'Can set global user agent.');

my $echo1 = W( baseuri('echo') );
my $echo2 = W( baseuri('echo') );
is(refaddr($echo1->user_agent), refaddr($Web::Magic::user_agent));
is(refaddr($echo2->user_agent), refaddr($Web::Magic::user_agent));

$echo2->user_agent( LWP::UserAgent->new(agent => 'MyBar') );
isnt(refaddr($echo2->user_agent), refaddr($Web::Magic::user_agent));

like($echo1, qr{ User-Agent: \s* MyFoo }ix);
like($echo2->set_user_agent(agent => 'MyBar/1.0'), qr{ User-Agent: \s* MyBar / 1\.0 }ix);
unlike($echo2, qr{ User-Agent: \s* MyFoo }ix);

Web::Magic->user_agent(undef);
ok !defined $Web::Magic::user_agent;
