use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use TestHttpServer;

plan tests => 5;

my $html = W( baseuri('ex_html') );
isa_ok($html->documentElement, 'XML::LibXML::Node');
is($html->querySelector('p > b')->toString, '<b>example</b>', 'querySelector works');

my $weird = W( baseuri('ex_weird') ); # has a non-empty <br> element, but sent as XML.
is($weird->querySelector('br > b')->toString, '<b>example</b>', 'querySelector works for XML');

my $not_found = W( baseuri('not_found') );
like(
	$not_found->querySelector('title')->toString, 
	qr{^  <title.*>404</title>  $}x,
	'404 pages can be HTML too',
	);

local $@ = undef;
eval { W( baseuri('ex_json') )->to_dom };
my $exception = $@;

isa_ok $exception, 'Web::Magic::Exception::BadReponseType',
	"attempting to parse JSON as a DOM throws exception which";