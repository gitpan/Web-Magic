use strict;

use Web::Magic;
use Test::Exception;
use Test::More tests => 7;

throws_ok {
	Web::Magic->new_from_data('text-plain', q{Hello}, q{ }, q{World});
	}
	'Web::Magic::Exception',
	'nonsense media type';

throws_ok {
	Web::Magic->new_from_data('text/plain');
	}
	'Web::Magic::Exception',
	'no data';

my $web;
lives_ok {
	$web = Web::Magic->new_from_data('text/plain', q{Hello}, q{ }, q{World});
	}
	'can instantiate with data';

ok $web->is_requested, 'object is already requested';

is "$web" => "Hello World",
	'response body correct';

is $web->header('Content-Type') => 'text/plain',
	'response Content-Type header correct';

is $web->header('Content-Length') => 11,
	'response Content-Length header correct';
