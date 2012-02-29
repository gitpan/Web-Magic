use strict;
use lib "lib";
use lib "t/lib";

use XML::LibXML;
use Web::Magic -sub => 'W';
use TestHttpServer;

plan skip_all => "this test is broken in XML::LibXML 1.91/1.92"
	if XML::LibXML->VERSION =~ m{^1\.9[12]$};

plan tests => 8;

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

my @links = W( baseuri('ex_links') )
	->assert_success
	->make_absolute_urls
	->querySelectorAll('a[href]');

is(scalar @links, 2, 'querySelectorAll');
like($links[0]->getAttribute('href'), qr{^http://}, 'make_absolute_urls (relative)');
is($links[1]->getAttribute('href'), 'http://link.example/absolute', 'make_absolute_urls (absolute)');