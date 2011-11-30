package Web::Magic;

use 5.010;
use common::sense;
use namespace::sweep; # namespace::autoclean breaks overloading
use utf8;

BEGIN {
	$Web::Magic::AUTHORITY = 'cpan:TOBYINK';
	$Web::Magic::VERSION   = '0.002';
}

use Acme::24 0.03                  qw//; 
use Carp 0                         qw/croak carp confess/;
use HTML::HTML5::Parser 0.100      qw//;
use HTML::HTML5::Writer 0.100      qw//;
use JSON::JOM 0.005                qw/from_json to_jom to_json/;
use JSON::JOM::Plugins::Dumper 0   qw//;
use JSON::JOM::Plugins::JsonPath 0 qw//;
use LWP::UserAgent 0               qw//;
use Object::Stash 0.002            qw/_stash/;
use PerlX::QuoteOperator 0         qw//;
use RDF::RDFa::Parser 1.096        qw//;
use RDF::Trine 0.135               qw//;
use Scalar::Util 0                 qw/blessed/;
use Sub::Name 0                    qw/subname/;
use UNIVERSAL::AUTHORITY 0         qw//;
use URI 0                          qw//;
use URI::Escape 0                  qw//;
use XML::LibXML 1.70               qw//;
use YAML::Any 0                    qw/Load Dump/;

use overload
	'%{}'  => \&to_hashref,
	'@{}'  => \&to_hashref,
	'""'   => \&content,
	;

my %F;
BEGIN {
	$F{$_} = 'to_dom'
		foreach qw/getElementsByTagName getElementsByTagNameNS
			getElementsByLocalName getElementsById documentElement
			cloneNode firstChild lastChild findnodes find findvalue
			exists childNodes attributes getNamespaces/;
	$F{$_} = 'to_hashref'
		foreach qw/findNodes/;
	$F{$_} = 'to_model'
		foreach qw/subjects predicates objects objects_for_predicate_list
			get_pattern get_statements count_statements get_sparql as_stream/;
	$F{$_} = 'to_feed'
		foreach qw/entries/;
	$F{$_} = 'uri'
		foreach qw/scheme authority path query host port/;
	$F{$_} = 'acme_24'
		foreach qw/random_jackbauer_fact/;
}

sub import
{
	my ($class, %args) = @_;
	
	my $caller = caller;
	my $code   = sub ($) { __PACKAGE__->new(@_); };
	
	if ($args{-quotelike})
	{
		$args{-quotelike} = [ $args{-quotelike} ]
			unless ref $args{-quotelike};
		
		my $ctx    = PerlX::QuoteOperator->new;
		$ctx->import(
			$_,
			{ -emulate => 'qq', -with => $code, },
			$caller,
			)
			foreach @{ $args{-quotelike} };
	}
	
	if ($args{-sub})
	{
		$args{-sub} = [ $args{-sub} ]
			unless ref $args{-sub};
		
		no strict 'refs';
		*{"$caller\::$_"} = subname "$caller\::$_", $code
			foreach @{ $args{-sub} };
	}
}

sub new
{
	my $class  = shift;
	
	my $method = 'GET';
	if ($_[0] =~ /^[A-Z][A-Z0-9]{0,19}$/)
	{
		$method = shift;
	}
	
	my ($u, %args) = @_;
	$u =~ s{(^\s*)|(\*$)}{}g;
	
	if (%args)
	{
		$u .= '?' . join '&', map { sprintf('%s=%s', $_, $args{$_}) } keys %args;
	}
	
	my $self = bless \$u, $class;
	$self->set_request_method($method);
	return $self;
}

sub CAN
{
	my ($starting_class, $func, $self, @arguments) = @_;
	
	if (defined (my $via = $F{$func}))
	{
		return sub { (shift)->$via()->$func(@_); };
	}
	elsif ($func =~ /^[A-Z][A-Z0-9]{0,19}$/)
	{
		return sub { (shift)->set_request_method($func, @_); };
	}
	elsif ($func =~ /^[A-Z]/ and $func =~ /[a-z]/)
	{
		return sub { (shift)->set_request_header($func, @_); };
	}
	return;
}

sub can
{
	my ($invocant, $method) = @_;
	return $invocant->SUPER::can($method) 
		 // __PACKAGE__->CAN($method, $invocant);
}

our $AUTOLOAD;
sub AUTOLOAD
{
	my ($method)   = ($AUTOLOAD =~ /::([^:]+)$/);
	my $ref = __PACKAGE__->CAN($method, @_);
	
	croak(sprintf q{Can't locate object method "%s" via package "%s"}, $method, __PACKAGE__)
		unless ref $ref;
	
	if (1) # if we ever start to vary autoloaded methods on a per-object basis,
	{      # need to turn this off.
		no strict 'refs';
		*{$method} = $ref;
	}
	
	goto &$ref;
}

sub set_request_method
{
	my ($self, @args) = @_;
	croak "Cannot set request method on already requested resource"
		if @args && $self->_already_requested;
	$self->_request_object->method(uc $args[0]);
	$self->set_request_body($args[1]) if exists $args[1];
	return $self;
}

sub set_request_body
{
	my ($self, $body) = @_;
	if ($self->_already_requested)
	{
		croak "Cannot set request body on already requested resource";
	}
	$self->_stash->{request_body} = $body;
}

sub set_request_header
{
	my ($self, @args) = @_;
	croak "Cannot set request header on already requested resource"
		if exists $args[1] && $self->_already_requested;
	$self->_request_object->header(@args);
	return $self;
}

sub user_agent
{
	my ($self) = @_;
	my $stash = $self->_stash;
	$stash->{user_agent} //= LWP::UserAgent->new(agent =>
		sprintf('%s/%s (%s) ',
			__PACKAGE__,
			__PACKAGE__->VERSION,
			__PACKAGE__->AUTHORITY,
			)
		);
	$stash->{user_agent};
}

sub _request_object
{
	my ($self) = @_;
	my $stash = $self->_stash;
	$stash->{request} //= HTTP::Request->new(GET => $$self);
	$stash->{request};
}

sub _already_requested
{
	my ($self) = @_;
	return exists $self->_stash->{response};
}

*is_requested = \&_already_requested;

sub do_request
{
	my ($self, %extra_headers) = @_;
	
	if ($self->is_cancelled)
	{
		croak "Need to perform HTTP request, but it is cancelled.";
	}
	
	unless ($self->_already_requested)
	{
		my $req = $self->_request_object;
		
		if (%extra_headers)
		{
			while (my ($h, $v) = each %extra_headers)
			{
				$req->header($h => $v) unless $req->header($h);
			}
		}
		
		if (defined (my $body = $self->_stash->{request_body}))
		{
			my $success;
			if (!ref $body)
			{
				$req->content($body);
				$success++;
			}
			elsif (blessed $body and $body->isa('RDF::Trine::Model'))
			{
				my $ser;
				given ( $req->content_type//'xml' )
				{
					when (/xml/)     { $ser = RDF::Trine::Serializer::RDFXML->new }
					when (/turtle/)  { $ser = RDF::Trine::Serializer::Turtle->new }
					when (/plain/)   { $ser = RDF::Trine::Serializer::NTriples->new }
					when (/json/)    { $ser = RDF::Trine::Serializer::RDFJSON->new }
				}
				if ($ser)
				{
					$req->content($ser->serialize_model_to_string($body));
					$req->content_type('application/rdf+xml')
						unless $req->content_type;
					$success++;
				}
			}
			elsif (blessed $body and $body->isa('XML::LibXML::Document'))
			{
				my $ser;
				given ( $req->content_type//'xml' )
				{
					when (/xml/)     { $ser = $body->toString }
					when (/html/)    { $ser = HTML::HTML5::Writer->new->document($body) }
				}
				if ($ser)
				{
					$req->content($ser);
					$req->content_type('application/xml')
						unless $req->content_type;
					$success++;
				}
			}
			elsif (ref $body and ($req->content_type//'') =~ /json/i)
			{
				$req->content(to_json($body));
				$success++;
			}
			elsif (ref $body and ($req->content_type//'') =~ /yaml/i)
			{
				$req->content(Dump $body);
				$success++;
			}
			elsif (ref $body eq 'HASH' and ($req->content_type//'www-form-urlencoded') =~ /www-form-urlencoded/i)
			{
				my $axwwfue = join '&', map { sprintf('%s=%s', $_, $body->{$_}) } keys %$body;
				$req->content($axwwfue);
				$success++;
			}
		}
		
		my $response = $self->user_agent->request($req);
		
		foreach my $assertion (@{ $self->_stash->{assert_response} // [] })
		{
			my ($name, $code) = @$assertion;
			croak "Response assertion '$name' failed" unless $code->($response, $self);
		}
		
		$self->_stash->{response} = $response;
	}
	
	return $self;
}

sub assert_response
{
	my ($self, $name, $code) = @_;
	push @{ $self->_stash->{assert_response} // [] }, [$name, $code];
	if ($self->_already_requested)
	{
		my $response = $self->_response_object;
		croak "Response assertion '$name' failed" unless $code->($response, $self);
	}
	return $self;
}

sub assert_success
{
	my ($self) = @_;
	return $self->assert_response(success => sub { (shift)->is_success });
}

sub has_response_assertions
{
	my ($self) = @_;
	scalar @{ $self->_stash->{assert_response} // [] };
}

sub _response_object
{
	my ($self, %extra_headers) = @_;
	$self->do_request(%extra_headers);
	$self->_stash->{response};
}

sub response
{
	my ($self, %extra_headers) = @_;
	my $response = $self->_response_object(%extra_headers);
	return $response;
}

sub to_hashref
{
	my ($self) = @_;
	my $stash = $self->_stash;
	
	unless (exists $stash->{hashref})
	{
		my $response = $self->response(Accept => 'application/json, application/yaml, text/yaml');
		
		if ($response->content_type =~ /json/i)
		{
			$stash->{hashref} = from_json($response->decoded_content);
		}
		elsif ($response->content_type =~ /yaml/i)
		{
			$stash->{hashref} = to_jom(Load($response->decoded_content));
		}
		else
		{
			croak "Can't treat this media type as a hashref: ".$response->content_type;
		}
	}
	
	return $stash->{hashref};
}

sub to_dom
{
	my ($self) = @_;
	my $stash = $self->_stash;
	
	unless (exists $stash->{dom})
	{
		my $response = $self->response(Accept => 'application/xml, text/xml, application/atom+xml, application/xhtml+xml, text/html');
		
		if ($response->content_type =~ m{^text/html}i)
		{
			$stash->{dom} = HTML::HTML5::Parser
				->new->parse_string($response->decoded_content);
		}
		elsif ($response->content_type =~ m{xml}i)
		{
			$stash->{dom} = XML::LibXML
				->new->parse_string($response->decoded_content);
		}
		else
		{
			croak "Can't treat this media type as a DOM: ".$response->content_type;
		}
	}
	
	return $stash->{dom};
}

sub to_model
{
	my ($self) = @_;
	my $stash = $self->_stash;
	
	unless (exists $stash->{model})
	{
		my $response = $self->response(Accept => 'application/rdf+xml, text/turtle, application/xhtml+xml;q=0.1');
		
		if (defined RDF::RDFa::Parser::Config->host_from_media_type($response->content_type))
		{
			$stash->{model} = RDF::RDFa::Parser
				->new_from_url($response)
				->graph;
		}
		else
		{
			my $model = RDF::Trine::Model->new;
			
			RDF::Trine::Parser
				->parser_by_media_type($response->content_type)
				->parse_into_model(
					($response->base//$$self),
					$response->decoded_content,
					$model,
					);
			$stash->{model} = $model;
		}
	}
	
	return $stash->{model};
}

sub to_feed
{
	my ($self) = @_;
	my $stash = $self->_stash;
	
	unless (exists $stash->{feed})
	{
		my $response = $self->response(Accept => 'application/atom+xml, application/rss+xml, application/rdf+xml;q=0.1');
		my $content  = $response->decoded_content;
		$stash->{feed} = XML::Feed->parse(\$content);
	}
	
	return $stash->{feed};
}

sub content
{
	my ($self) = @_;
	$self->response->decoded_content;
}

sub uri
{
	my ($self) = @_;
	return URI->new($$self);
}

sub cancel
{
	my ($self) = @_;
	croak "Tried to cancel an already submitted request" if $self->_already_requested;
	$self->_stash->{cancel_request}++;
	return $self;
}

sub acme_24
{
	return 'Acme::24';
}

sub is_cancelled
{
	my ($self) = @_;
	return $self->_stash->{cancel_request};
}

sub DESTROY
{
	my ($self) = @_;
	return if $self->is_cancelled;
	return if $self->_already_requested;
	if ($self->_request_object->method =~ m(^(GET|HEAD|OPTIONS|TRACE|SEARCH)$)i)
	{
		return unless $self->has_response_assertions;
	}
	$self->do_request;
}

'Just DWIM!';

__END__

=head1 NAME

Web::Magic - HTTP dwimmery

=head1 SYNOPSIS

 use Web::Magic;
 say Web::Magic->new('http://json-schema.org/card')->{description};

or

 use Web::Magic -sub => 'W'; 
 say W('http://json-schema.org/card')->{description};

=head1 DESCRIPTION

On the surface of it, Web::Magic appears to just perform HTTP requests,
but it's more than that. A URL blessed into the Web::Magic package can
be interacted with in all sorts of useful ways.

=head2 Constructor

=over

=item C<< new ([$method,] $uri [, %args]) >>

C<< $method >> is the HTTP method to use with the URI, such as 'GET',
'POST', 'PUT' or 'DELETE'. The HTTP method must be capitalised to
avoid it being interpreted by the constructor as a URI. It defaults to
'GET'.

The URI should be an HTTP or HTTPS URL. Other URI schemes may work
to varying degress of success.

The C<< %args >> hash is a convenience for constructing HTTP query
strings. Hash values should be scalars, or at least overload
stringification. The following are all equivalent...

 Web::Magic->new(GET => 'http://www.google.com/search', q => 'kittens');
 Web::Magic->new('http://www.google.com/search', q => 'kittens');
 Web::Magic->new(GET => 'http://www.google.com/search?q=kittens');
 Web::Magic->new('http://www.google.com/search?q=kittens');

=back

=head2 Export

You can import a sub to act as a shortcut for the constructor.

 use Web::Magic -sub => 'W';
 W(GET => 'http://www.google.com/search', q => 'kittens');
 W('http://www.google.com/search', q => 'kittens');
 W(GET => 'http://www.google.com/search?q=kittens');
 W('http://www.google.com/search?q=kittens');

There is experimental support for a quote-like operator similar to
C<< q() >> or C<< qq() >>:

 use Web::Magic -quotelike => 'qW';
 qW(http://www.google.com/search?q=kittens);

But it doesn't always behave as expected.
(See L<https://rt.cpan.org/Ticket/Display.html?id=72822>.)

=head2 Pre-Request Methods

Constructing a Web::Magic object doesn't actually perform a request
for the URI. Web::Magic defers requesting the URI until the last
possible moment. (Which in some cases will be when it slips out of
scope, or even not at all.)

Pre-request methods are those that can be called before the request
is made. Unless otherwise noted they will not themselves trigger the
request to be made. Unless otherwise noted, they return a reference
to the Web::Magic object itself, so can be chained:

  my $magic = Web::Magic
    ->new(GET => 'http://www.google.com/')
    ->User_Agent('MyBot/0.1')
    ->Accept('text/html');

The following methods are pre-request.

=over

=item C<< set_request_method($method, [$body]) >>

Sets the HTTP request method (e.g. 'GET' or 'POST'). You can optionally
set the HTTP request body at the same time.

As a shortcut, you can use the method name as an object method. That is,
the following are equivalent:

  $magic->set_request_method(POST => $body);
  $magic->POST($body);

Using the latter technique, methods need to conform to this regular
expression: C<< /^[A-Z][A-Z0-9]{0,19}$/ >>.

This will throw an error if called on a Web::Magic object that has already
been requested.

=item C<< set_request_header($header, $value) >>

Sets an HTTP request header (e.g. 'User-Agent').

As a shortcut, you can use the header name as an object method, substituting
hyphens for underscores. That is, the following are equivalent:

  $magic->set_request_header('User-Agent', 'MyBot/0.1');
  $magic->User_Agent('MyBot/0.1');

Using the latter technique, methods need to begin with a capital letter
and contain at least one lower-case letter. 

This will throw an error if called on a Web::Magic object that has already
been requested.

=item C<< set_request_body($body) >>

Sets the body for a POST, PUT or other request that needs a body.

C<< $body >> may be a string, but can be a hash or array reference,
an XML::LibXML::Document or an RDF::Trine::Model, in which case they'll
be serialised appropriately based on the Content-Type header of the
request.

  my $magic = W('http://www.example.com/document-submission')
    ->POST
    ->set_request_body($document_dom)
    ->Content_Type('text/html');

Yes, that's right. Even though the content-type is set *after* the
body, it is still serialised appropriately. This is because
serialisation is deferred until just before the request is made.

This will throw an error if called on a Web::Magic object that has already
been requested.

=item C<< cancel >>

This method may be called to show you do not intend for this object
to be requested. Attempting to request an object that has been cancelled
will throw an exception.

  my $magic = W('http://www.google.com/');
  $magic->cancel;
  $magic->do_request; # throws

Why is this needed? Because even if you don't explicitly call
C<< do_request >>, the request will be made implicitly in some cases.
C<< cancel >> allows you to avoid the implicit request.

This will throw an error if called on a Web::Magic object that has already
been requested.

=item C<< do_request >>

Actually performs the HTTP request. You rarely need to call this
method implicitly, as calling any Post-Request method will automatically
call C<do_request>.

C<do_request> will be called automatically (via C<DESTROY>) on any
Web::Magic object that gets destroyed (e.g. goes out of scope) unless
the request has been cancelled, or the request is unlikely to have had
side-effects (i.e. its method is 'GET', 'HEAD', 'OPTIONS', 'TRACE'
or 'SEARCH').

This will throw an error if called on a Web::Magic object that has
been cancelled.

=back

=head2 Post-Request Methods

The following methods can be called after a request has been made, and
will implicitly call C<do_request> if called on an object which has
not yet been requested.

These do not typically return a reference to the invocant Web::Magic
object, so cannot always easily be chained.

=over

=item C<< response >>

The response, as an L<HTTP::Response> object.

=item C<< content >>

The response body, as a string.

Web::Magic overloads stringification calling this method. Thus:

  print W('http://www.example.com/');

will print the body of 'http://www.example.com/'.

=item C<< to_hashref >>

Parses the response body as JSON or YAML (depending on Content-Type
header) and returns the result as a hashref (or arrayref).

Actually, technically it returns an L<JSON::JOM> object which can
be accessed as if it were a hashref or arrayref.

When a Web::Magic object is accessed as a hashref, this implicitly
calls C<to_hashref>. So the following are equivalent:

  W('http://example.com/data')->to_hashref->{people}[0]{name};
  W('http://example.com/data')->{people}[0]{name};

When C<to_hashref> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include JSON and YAML
unless the Accept header has already been set.

=item C<< to_dom >>

Parses the response body as XML or HTML (depending on Content-Type
header) and returns the result as an L<XML::LibXML::Document>.

When C<to_dom> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include XML and HTML
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_dom>: getElementsByTagName getElementsByTagNameNS
getElementsByLocalName getElementsById documentElement
cloneNode firstChild lastChild findnodes find findvalue
exists childNodes attributes getNamespaces. So, for example, the
following are equivalent:

  W('http://example.com/')->to_dom->getElementsByTagName('title');
  W('http://example.com/')->getElementsByTagName('title');

=item C<< to_model >>

Parses the response body as RDF/XML, Turtle, RDF/JSON or RDFa
(depending on Content-Type header) and returns the result as an
L<RDF::Trine::Model>.

When C<to_model> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include RDF/XML and Turtle
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_model>: subjects predicates objects objects_for_predicate_list
get_pattern get_statements count_statements get_sparql as_stream. So,
for example, the following are equivalent:

  W('http://example.com/')->to_model->get_pattern($pattern);
  W('http://example.com/')->get_pattern($pattern);

=item C<< to_feed >>

Parses the response body as Atom or RSS (depending on Content-Type
header) and returns the result as an L<XML::Feed>.

When C<to_feed> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include Atom and RSS
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_feed>: entries. So, for example, the following are equivalent:

  W('http://example.com/')->to_feed->entries;
  W('http://example.com/')->entries;

=back

=head2 Any Time Methods

These can be called either before or after the request, and do not
trigger the request to be made. They do not usually return the invocant
Web::Magic object, so are not usually suitable for chaning.

=over

=item C<< uri >>

Returns the original URI, as a L<URI> object.

Additionally, the following methods can be called which implicitly
call C<uri>: scheme authority path query host port. So, for example,
the following are equivalent:

  W('http://example.com/')->uri->host;
  W('http://example.com/')->host;

If you need a copy of the URI as a string, two methods are:

  my $magic = W('http://example.com/');
  my $str_1 = $magic->uri->as_string;
  my $str_2 = $$magic;

The former perhaps makes for easier to read code; the latter is maybe
slightly faster code.

=item C<< is_requested >>

Returns true if the invocant has already been requested.

=item C<< is_cancelled >>

Returns true if the invocant has been cancelled.

=item C<< assert_response($name, $coderef) >>

Checks an assertion about the HTTP response. Web::Magic will blithely
allow you to call to_hashref on a non-JSON/YAML response, or
getElementsByTagName on an HTTP error page. This may not be what you
want. C<assert_response> allows you to check things are as expected
before continuing, croaking otherwise.

C<< $coderef >> should be a subroutine that accepts an HTTP::Response,
and returns true if everything is OK, and false if something bad has
happened. C<< $name >> is just a label for the assertion, to provide a
more helpful error message if the assertion fails.

  print W('http://example.com/data.json')
    ->assert_response(correct_type => sub { (shift)->content_type =~ /json/i })
    ->{people}[0]{name};

An assertion can be made at any time. If made before the request, then
it is queued up for checking later. If the assertion is made after the
request, it is checked immediately.

This method returns the invocant, so may be chained.

=item C<< assert_success >>

A shortcut for:

  assert_response(success => sub { (shift)->is_success })

This checks the HTTP response has a 2XX HTTP status code.

=item C<< has_response_assertions >>

Returns true if the Web::Magic object has had any response
assertions made. (In fact, returns the number of such assertions.)

=item C<< user_agent >>

Returns the L<LWP::UserAgent> that will be used (or has been used)
to issue the request.

=item C<< acme_24 >>

Returns the string 'Acme::24'.

Additionally, the following methods can be called which implicitly
call C<acme_24>: random_jackbauer_fact. So, for example,
the following are equivalent:

  W('http://example.com/')->acme_24->random_jackbauer_fact;
  W('http://example.com/')->random_jackbauer_fact;

This method exists to emphasize the whimsical and experimental
status of the current release of Web::Magic. If Web::Magic ever
becomes ready for serious production use, expect the following
to evaluate to false:

  W('http://example.com/')->can('random_jackbauer_fact')

=begin private

=item C<< CAN >>

=item C<< can >>

=end private

=back

=head1 BUGS

Inumerable, almost certainly.

Have a go at enumerating them here:
L<http://rt.cpan.org/Dist/Display.html?Queue=Web-Magic>.

=head1 SEE ALSO

L<LWP::UserAgent>, L<URI>, L<HTTP::Request>, L<HTTP::Response>.

L<XML::LibXML>, L<JSON::JOM>, L<RDF::Trine>, L<XML::Feed>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2011 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

