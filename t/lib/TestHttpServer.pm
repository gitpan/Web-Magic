package main;

use Test::More;

eval { require Test::HTTP::Server; 1; }
        or plan skip_all => "Could not use Test::HTTP::Server: $@";
our $server  = Test::HTTP::Server->new();
our $baseuri = $::server->uri;
sub baseuri { join '', $baseuri, @_; }
#diag baseuri();

sub Test::HTTP::Server::Request::ex_json {$_[0]->{out_headers}{content_type}='application/json' and <<'DATA'}
{
	"name" : "Joe Bloggs" ,
	"mbox" : "joe@example.net" 
}
DATA

sub Test::HTTP::Server::Request::ex_slow
{
	my $self = shift;
	Test::More::diag "sleeping";
	#sleep 2;
	Test::More::diag "waking";
	Test::More::ok($::DELAY, 'DELAY');
	$self->{out_headers}{content_type}='text/plain';
	return <<'DATA'
Hello world!
DATA
}

sub Test::HTTP::Server::Request::ex_json_array {$_[0]->{out_headers}{content_type}='application/x-array+json' and <<'DATA'}
[
	{
		"name" : "Joe Bloggs" ,
		"mbox" : "joe@example.net" 
	},
	{
		"name" : "Alice Jones" ,
		"mbox" : "alice@example.net" 
	}
]
DATA

sub Test::HTTP::Server::Request::ex_yaml {$_[0]->{out_headers}{content_type}='text/x-yaml' and <<'DATA'}
---
invoice: 34843
date   : 2001-01-23
bill-to: &id001
    given  : Chris
    family : Dumars
    address:
        lines: |
            458 Walkman Dr.
            Suite #292
        city    : Royal Oak
        state   : MI
        postal  : 48046
ship-to: *id001
product:
    - sku         : BL394D
      quantity    : 4
      description : Basketball
      price       : 450.00
    - sku         : BL4438H
      quantity    : 1
      description : Super Hoop
      price       : 2392.00
tax  : 251.42
total: 4443.52
comments: >
    Late afternoon is best.
    Backup contact is Nancy
    Billsmer @ 338-4338.

DATA

sub Test::HTTP::Server::Request::ex_html {$_[0]->{out_headers}{content_type}='text/html' and <<'DATA'}
<title>Example</title>
<p>This is an <b>example</b>!
DATA

sub Test::HTTP::Server::Request::ex_weird {$_[0]->{out_headers}{content_type}='application/xml' and <<'DATA'}
<html xmlns="http://www.w3.org/1999/xhtml">
	<head>
		<title>Example</title>
	</head>
	<body>
		<br>This is an <b>example</b>!</br>
	</body>
</html>
DATA

sub Test::HTTP::Server::Request::ex_rdf {$_[0]->{out_headers}{content_type}='text/turtle' and <<'DATA'}
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
[] a foaf:Person;
	foaf:name "Joe Bloggs";
	foaf:mbox <mailto:joe@example.net>.
DATA

sub Test::HTTP::Server::Request::not_found {$_[0]->{out_code}='404 Not Found' and $_[0]->{out_headers}{content_type}='text/html' and <<'DATA'}
<title property=":error">404</title>
<p>Not found.</p>
DATA

1;
