use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use TestHttpServer;

plan tests => 10;

my $json = W( baseuri('ex_json') );
my $json_array = W( baseuri('ex_json_array') );

is(ref $json->to_hashref, 'HASH');
is($json->to_hashref->{name}, 'Joe Bloggs', 'to_hashref works');
is($json->{name}, 'Joe Bloggs', 'hashref overload works');

is(ref $json_array->to_hashref, 'ARRAY', 'to_hashref actually returns an arrayref sometimes');
is($json_array->to_hashref->[0]{name}, 'Joe Bloggs', 'to_hashref works');
is($json_array->[0]{name}, 'Joe Bloggs', 'hashref overload works');
is($json_array->[1]{name}, 'Alice Jones', 'hashref overload works');

my $yaml = W( baseuri('ex_yaml') );
is(
	ref $yaml->to_hashref,
	'HASH',
	'YAML can be converted to a hashref');
is(
	($yaml->{'bill-to'}->findNodes("\$['family']"))[0],
	'Dumars',
	'JSON::JOM support',
	);
is(
	($yaml->json_findnodes("\$['ship-to']['family']"))[0],
	'Dumars',
	'json_findnodes works',
	);
