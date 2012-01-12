use strict;
use lib "lib";
use lib "t/lib";

use Web::Magic -sub => 'W';
use RDF::Trine;
use TestHttpServer;

plan tests => 2;

my $rdf = W( baseuri('ex_rdf') );
is($rdf->count_statements(
		undef,
		RDF::Trine::iri('http://xmlns.com/foaf/0.1/mbox'),
		undef,
		)
	, 1, 'found a foaf:mbox triple');
	
my $not_found = W( baseuri('not_found') );
is($not_found->count_statements(
		undef,
		RDF::Trine::iri('http://www.w3.org/1999/xhtml/vocab#error'),
		RDF::Trine::literal('404'),
		)
	, 1, 'RDFa works');
