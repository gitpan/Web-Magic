package Web::Magic;

use 5.010;
use common::sense;
use namespace::sweep; # namespace::autoclean breaks overloading
use Object::AUTHORITY;
use Object::Stash qw/_stash/;
use utf8;

BEGIN {
	$Web::Magic::AUTHORITY = 'cpan:TOBYINK';
	$Web::Magic::VERSION   = '0.005';
}

use JSON::JOM 0.005                qw/to_jom from_json to_json/;
use JSON::JOM::Plugins::Dumper 0   qw//;
use JSON::JOM::Plugins::JsonPath 0 qw//;
use LWP::UserAgent 0               qw//;
use PerlX::QuoteOperator 0.04      qw//;
use Scalar::Util 0                 qw/blessed/;
use Sub::Name 0                    qw/subname/;
use URI 0                          qw//;
use URI::Escape 0                  qw/uri_escape/;
use YAML::Any 0                    qw/Load Dump/;

use overload
	'%{}'  => \&to_hashref,
	'@{}'  => \&to_hashref,
	'""'   => \&content,
	;

our %Exceptions;

BEGIN
{
	%Exceptions = (
		'Web::Magic::Exception' => {
			description => 'a general Web::Magic error has occurred',
			},
		'Web::Magic::Exception::BadPhase' => {
			isa         => 'Web::Magic::Exception',
			description => 'a method has been called on a Web::Magic object '
							 .' which is in the wrong state to perform that method',
			},
		'Web::Magic::Exception::BadPhase::SetRequestMethod' => {
			isa         => 'Web::Magic::Exception::BadPhase',
			description => 'attempt to set request method for a request that '
							 . 'has already been performed',
			fields      => [qw/attempted_method used_method/],
			},
		'Web::Magic::Exception::BadPhase::SetRequestHeader' => {
			isa         => 'Web::Magic::Exception::BadPhase',
			description => 'attempt to set a request header for a request that '
							 . 'has already been performed',
			fields      => [qw/attempted_value used_value header/],
			},
		'Web::Magic::Exception::BadPhase::SetRequestBody' => {
			isa         => 'Web::Magic::Exception::BadPhase',
			description => 'attempt to set request body for a request that '
							 . 'has already been performed',
			fields      => [qw/attempted_body used_body/],
			},
		'Web::Magic::Exception::BadPhase::Cancel' => {
			isa         => 'Web::Magic::Exception::BadPhase',
			description => 'attempt to cancel a request that has already been '
							 . 'performed',
			},
		'Web::Magic::Exception::BadPhase::WillNotRequest' => {
			isa         => 'Web::Magic::Exception::BadPhase',
			description => 'attempt to perform a request that was explicitly '
							 . 'cancelled',
			fields      => [qw/cancellation/],
			},
		'Web::Magic::Exception::AssertionFailure' => {
			isa         => 'Web::Magic::Exception',
			description => 'an assertion failed',
			fields      => [qw/assertion_name assertion_coderef
									 http_request http_response/],
			},
		'Web::Magic::Exception::BadContent' => {
			isa         => 'Web::Magic::Exception',
			description => 'cannot coerce from a Perl object to HTTP message body',
			fields      => [qw/body/],
			},
		'Web::Magic::Exception::BadReponseType' => {
			isa         => 'Web::Magic::Exception',
			description => 'cannot coerce from an HTTP message body to a Perl object, '
			             . 'because is is of the wrong type',
			fields      => [qw/content_type/],
			},
		);
	
	require Exception::Class;
	Exception::Class->import(%Exceptions);
	
	sub __exception_documentation
	{
		foreach my $e (sort keys %Exceptions)
		{
			my $E = $Exceptions{ $e };
			printf "=head3 %s\n\n", $e;
			printf "B<Cause:> %s.\n\n", $E->{description};
			printf "B<Additional fields:> %s.\n\n",
				(join q{, }, @{$E->{fields}})
				if $E->{fields};
		}
	}
}

my %F;
BEGIN {
	$F{$_} = 'to_dom'
		foreach qw/getElementsByTagName getElementsByTagNameNS
			getElementsByLocalName getElementsById documentElement
			cloneNode firstChild lastChild findnodes find findvalue
			exists childNodes attributes getNamespaces
			querySelector querySelectorAll/;
	$F{$_} = 'to_hashref'
		foreach qw/findNodes/;
	$F{$_} = 'to_model'
		foreach qw/subjects predicates objects objects_for_predicate_list
			get_pattern get_statements count_statements get_sparql as_stream/;
	$F{$_} = 'to_feed'
		foreach qw/entries/;
	$F{$_} = 'response'
		foreach qw/headers/;
	$F{$_} = 'headers'
		foreach qw/header/;
	$F{$_} = 'uri'
		foreach qw/scheme authority path query host port/;
	$F{$_} = 'acme_24'
		foreach qw/random_jackbauer_fact/;
}

sub import
{
	my ($class, %args) = @_;
	
	my $caller = caller;
	
	if ($args{-quotelike})
	{
		my $code   = sub ($) { $class->new(@_); };
		
		$args{-quotelike} = [ $args{-quotelike} ]
			unless ref $args{-quotelike};
		
		my $ctx    = PerlX::QuoteOperator->new;
		$ctx->import(
			$_,
			{ -emulate => 'qq', -with => $code, -parser => 1},
			$caller,
			)
			foreach @{ $args{-quotelike} };
	}
	
	if ($args{-sub})
	{
		my $code   = sub ($;$%) { $class->new(@_); };
		
		$args{-sub} = [ $args{-sub} ]
			unless ref $args{-sub};
		
		no strict 'refs';
		*{"$caller\::$_"} = subname "$caller\::$_", $code
			foreach @{ $args{-sub} };
	}
}

sub AUTHORITY
{
	goto &Object::AUTHORITY::AUTHORITY;
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
		$u .= '?' . join '&',
			map { sprintf('%s=%s', uri_escape($_), uri_escape($args{$_})) }
			keys %args;
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
		return sub { warn "FUNC: $func"; (shift)->set_request_header($func, @_); };
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
	
	Web::Magic::Exception->throw(
		sprintf(q{Can't locate object method "%s" via package "%s"}, $method, __PACKAGE__)
		)
		unless ref $ref;
	
	if (1) # if we ever start to vary autoloaded methods on a per-object basis,
	{      # need to turn this off.
		no strict 'refs';
		*{$method} = subname $method => $ref;
	}
	
	goto &$ref;
}

sub __deferred_load
{
	my $self = shift;
	while (@_)
	{
		my $package = shift;
		my $version = shift;
		my $list    = (ref $_[0]) ? shift : [];

		# Normally I'd say "use Class::Load", but here we can trust the
		# strings $package and $version, because they are set locally.
		# Thus a string eval should be safe (and a little faster).

		next if UNIVERSAL::can($package, 'can');
		eval "use $package $version qw//;1" or die $@;
		$package->import(@$list);
	}
	$self;
}

sub set_request_method
{
	my ($self, @args) = @_;
	
	if ($self->is_requested)
	{
		Web::Magic::Exception::BadPhase::SetRequestMethod->throw(
			message =>
				"Cannot set request method on already requested resource\n",
			attempted_method => (uc $args[0] // 'GET'),
			used_method      => $self->_request_object->method,
			);
	}
	
	$self->_request_object->method(uc $args[0] // 'GET');
	$self->set_request_body($args[1]) if exists $args[1];
	return $self;
}

sub set_request_body
{
	my ($self, $body) = @_;
	
	if ($self->is_requested)
	{
		Web::Magic::Exception::BadPhase::SetRequestBody->throw(
			message =>
				"Cannot set request body on already requested resource\n",
			attempted_body   => $body,
			used_body        => $self->_request_object->body,
			);
	}

	$self->_stash->{request_body} = $body;
	return $self;
}

sub set_request_header
{
	my ($self, $h, $v) = @_;

	if ($self->is_requested)
	{
		Web::Magic::Exception::BadPhase::SetRequestHeader->throw(
			message =>
				"Cannot set request header '$h' on already requested resource\n",
			header           => $h,
			attempted_value  => $v,
			used_value       => $self->_request_object->header($h),
			);
	}

	$self->_request_object->header($h => $v);
	return $self;
}

sub _ua_string
{
	my $proto = shift;
	my $class = ref $proto // $proto;
	
	sprintf('%s/%s (%s) ',
		$class,
		$class->VERSION,
		$class->AUTHORITY,
		)
}

sub user_agent
{
	my ($self) = @_;
	my $stash = $self->_stash;
	$stash->{user_agent} //= LWP::UserAgent->new(agent => $self->_ua_string);
	$stash->{user_agent};
}

sub _request_object
{
	my ($self) = @_;
	my $stash = $self->_stash;
	$stash->{request} //= HTTP::Request->new(GET => $$self);
	$stash->{request};
}

sub _final_request_object
{
	my ($self, %extra_headers) = @_;
	
	my $req = $self->_request_object;
	return $req if $self->is_requested;

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
			$self->__deferred_load('RDF::Trine' => '0.135');
				
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
			$self->__deferred_load('XML::LibXML' => '1.70');
			
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
			my $axwwfue = join '&',
				map { sprintf('%s=%s', uri_escape($_), uri_escape($body->{$_})) }
				keys %$body;
			$req->content($axwwfue);
			$success++;
		}
		else
		{
			my $ref = ref $body;
			Web::Magic::Exception::BadContent->throw(
				message  => "Cannot coerce type '$ref' to HTTP request body\n",
				body     => $body,
				);
		}
	}
	
	return $req;
}

sub is_requested
{
	my ($self) = @_;
	return exists $self->_stash->{response};
}

sub _check_assertions
{
	my ($self, $response, @assertions) = @_;
	
	foreach my $assertion (@assertions)
	{
		my ($name, $code) = @$assertion;
		local $_ = $response;
		next if $code->($self);
		
		Web::Magic::Exception::AssertionFailure->throw(
			message           => "Assertion '$name' failed for <$$self>\n",
			assertion_name    => $name,
			assertion_coderef => $code,
			http_request      => $self->_request_object,
			http_response     => $response,
			);
	}

	return $self;
}

sub do_request
{
	my ($self, %extra_headers) = @_;
	
	if ($self->is_cancelled)
	{
		Web::Magic::Exception::BadPhase::WillNotRequest->throw(
			message      => "Need to perform HTTP request, but it is cancelled\n",
			cancellation => $self->is_cancelled,
			);
	}
	
	unless ($self->is_requested)
	{
		my $req      = $self->_final_request_object(%extra_headers);
		my $response = $self->user_agent->request($req);
		
		$self->_stash(response => $response);
		$self->_check_assertions($response, @{ $self->_stash->{assert_response} // [] });
	}
	
	return $self;
}

sub assert_response
{
	my ($self, $name, $code) = @_;
	
	$self->_stash->{assert_response} = [] unless defined $self->_stash->{assert_response};
	push @{ $self->_stash->{assert_response} }, [$name => $code];
	
	if ($self->is_requested)
	{
		return $self->_check_assertions($self->response, [$name => $code]);
	}
	
	return $self;
}

sub assert_success
{
	my ($self) = @_;
	return $self->assert_response(success => sub { $_->is_success });
}

sub has_response_assertions
{
	my ($self) = @_;
	scalar @{ $self->_stash->{assert_response} // [] };
}

sub response
{
	my ($self, %extra_headers) = @_;
	$self->do_request(%extra_headers);
	$self->_stash->{response};
}

sub _cancel_progress
{
	# no-op
}

sub to_hashref
{
	my ($self) = @_;
	my $stash = $self->_stash;

	unless (exists $stash->{hashref})
	{
		$self->do_request(Accept => 'application/json, application/yaml, text/yaml');
		
		if ($self->headers->content_type =~ /json/i)
		{
			$stash->{hashref} = from_json($self->response->decoded_content);
		}
		elsif ($self->headers->content_type =~ /yaml/i)
		{
			$stash->{hashref} = to_jom(Load($self->response->decoded_content));
		}
		else
		{
			$self->_cancel_progress;
			Web::Magic::Exception::BadReponseType->throw(
				message      => "Can't treat this media type as a hashref: "
				              . $self->headers->content_type . "\n",
				content_type => $self->headers->content_type,
				);
		}
	}
	
	return $stash->{hashref};
}

sub to_dom
{
	my ($self) = @_;
	my $stash = $self->_stash;

	$self->__deferred_load(
		'HTML::HTML5::Parser'        => '0.100',
		'HTML::HTML5::Writer'        => '0.100',
		'XML::LibXML'                => '1.70',
		'XML::LibXML::QuerySelector' => 0,
		);

	unless (exists $stash->{dom})
	{
		$self->do_request(Accept => 'application/xml, text/xml, application/atom+xml, application/xhtml+xml, text/html');
		
		if ($self->headers->content_type =~ m{^text/html}i)
		{
			$stash->{dom} = HTML::HTML5::Parser
				->new->parse_string($self->response->decoded_content);
		}
		elsif ($self->headers->content_type =~ m{xml}i)
		{
			$stash->{dom} = XML::LibXML
				->new->parse_string($self->response->decoded_content);
		}
		else
		{
			$self->_cancel_progress;
			Web::Magic::Exception::BadReponseType->throw(
				message      => "Can't treat this media type as a DOM: "
				              . $self->headers->content_type . "\n",
				content_type => $self->headers->content_type,
				);
		}
	}
	
	return $stash->{dom};
}

sub to_model
{
	my ($self) = @_;
	my $stash = $self->_stash;

	$self->__deferred_load(
		'RDF::RDFa::Parser'    => '1.096',
		'RDF::Trine'           => '0.135',
		);

	unless (exists $stash->{model})
	{
		$self->do_request(Accept => 'application/rdf+xml, text/turtle, application/xhtml+xml;q=0.1');
		
		if (defined RDF::RDFa::Parser::Config->host_from_media_type($self->headers->content_type))
		{
			$stash->{model} = RDF::RDFa::Parser
				->new_from_url($self->response)
				->graph;
		}
		else
		{
			my $model = RDF::Trine::Model->new;
			
			RDF::Trine::Parser
				->parser_by_media_type($self->headers->content_type)
				->parse_into_model(
					($self->response->base//$$self),
					$self->response->decoded_content,
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
	
	$self->__deferred_load('XML::Feed' => 0);
	
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
	
	Web::Magic::Exception::BadPhase::Cancel->throw(
		"Tried to cancel an already submitted request\n"
		)
		if $self->is_requested;
	
	$self->_stash->{cancel_request} = [ caller(0) ];
	return $self;
}

sub acme_24
{
	my ($self) = @_;
	$self->__deferred_load('Acme::24'   => '0.03');
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
	return if $self->is_requested;
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
'POST', 'PUT' or 'DELETE'. The HTTP method B<must> be capitalised to
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

Note that C<< %args >> always sets a URI query string, and does B<not>
set the request body, B<even in the case of the POST method>. To set
the request body, see the C<set_request_body> method.

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

This will throw a Web::Magic::Exception::BadPhase::SetRequestMethod exception
if called on a Web::Magic object that has already been requested.

=item C<< set_request_header($header, $value) >>

Sets an HTTP request header (e.g. 'User-Agent').

As a shortcut, you can use the header name as an object method, substituting
hyphens for underscores. That is, the following are equivalent:

  $magic->set_request_header('User-Agent', 'MyBot/0.1');
  $magic->User_Agent('MyBot/0.1');

Using the latter technique, methods need to begin with a capital letter
and contain at least one lower-case letter. 

This will throw a Web::Magic::Exception::BadPhase::SetRequestHeader exception
if called on a Web::Magic object that has already been requested.

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

This will throw a Web::Magic::Exception::BadPhase::SetRequestBody exception
if called on a Web::Magic object that has already been requested.

A Web::Magic::Exception::BadPhase::Cancel exception will be thrown if the
body can't be serialised, but not until the request is actually performed.

=item C<< cancel >>

This method may be called to show you do not intend for this object
to be requested. Attempting to request an object that has been cancelled
will throw a Web::Magic::Exception::BadPhase::Cancel exception.

  my $magic = W('http://www.google.com/');
  $magic->cancel;
  $magic->do_request; # throws

Why is this needed? Because even if you don't explicitly call
C<< do_request >>, the request will be made implicitly in some cases.
C<< cancel >> allows you to avoid the implicit request.

=item C<< do_request >>

Actually performs the HTTP request. You rarely need to call this
method explicitly, as calling any Post-Request method will automatically
call C<do_request>.

C<do_request> will be called automatically (via C<DESTROY>) on any
Web::Magic object that gets destroyed (e.g. goes out of scope) unless
the request has been cancelled, or the request is unlikely to have had
side-effects (i.e. its method is 'GET', 'HEAD', 'OPTIONS', 'TRACE'
or 'SEARCH').

This will throw a Web::Magic::Exception::BadPhase::WillNotRequest exception
if called on a Web::Magic object that has been cancelled.

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

The response body, as a string. This is a shortcut for:

  $magic->response->decoded_content

Web::Magic overloads stringification calling this method. Thus:

  print W('http://www.example.com/');

will print the body of 'http://www.example.com/'.

=item C<< headers >>

The response headers, as an HTTP::Headers object. This is a shortcut for:

  $magic->response->headers

=item C<< header($name) >>

A response header, as a string. This is a shortcut for:

  $magic->response->headers->header($name)

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

This will throw a Web::Magic::Exception::BadReponseType exception
if the HTTP response has a Content-Type that cannot be converted to
a hashref.

=item C<< to_dom >>

Parses the response body as XML or HTML (depending on Content-Type
header) and returns the result as an XML::LibXML::Document.

When C<to_dom> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include XML and HTML
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_dom> (see L<XML::LibXML::Document>):

=over

=item * C<getElementsByTagName>

=item * C<getElementsByTagNameNS>

=item * C<getElementsByLocalName>

=item * C<getElementsById>

=item * C<documentElement>

=item * C<cloneNode>

=item * C<firstChild>

=item * C<lastChild>

=item * C<findnodes>

=item * C<find>

=item * C<findvalue>

=item * C<exists>

=item * C<childNodes>

=item * C<attributes>

=item * C<getNamespaces>

=item * C<querySelector>

=item * C<querySelectorAll>

=back

So, for example, the following are equivalent:

  my @titles = W('http://example.com/')
    ->to_dom->getElementsByTagName('title');
  
  my @titles = W('http://example.com/')
    ->getElementsByTagName('title');

I'll just draw your attention to C<querySelector> and C<querySelectorAll>
which were mentioned in the previous list, but are hidden gems. See
L<XML::LibXML::QuerySelector> for further details.

This will throw a Web::Magic::Exception::BadReponseType exception
if the HTTP response has a Content-Type that cannot be converted to
a DOM.

=item C<< to_model >>

Parses the response body as RDF/XML, Turtle, RDF/JSON or RDFa
(depending on Content-Type header) and returns the result as an
RDF::Trine::Model.

When C<to_model> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include RDF/XML and Turtle
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_model> (see L<RDF::Trine::Model>):

=over

=item * C<subjects>

=item * C<predicates>

=item * C<objects>

=item * C<objects_for_predicate_list>

=item * C<get_pattern>

=item * C<get_statements>

=item * C<count_statements>

=item * C<get_sparql>

=item * C<as_stream>

=back

So, for example, the following are equivalent:

  W('http://example.com/')->to_model->get_pattern($pattern);
  W('http://example.com/')->get_pattern($pattern);

=item C<< to_feed >>

Parses the response body as Atom or RSS (depending on Content-Type
header) and returns the result as an XML::Feed.

When C<to_feed> is called on an unrequested Web::Magic object,
it implicitly sets the HTTP Accept header to include Atom and RSS
unless the Accept header has already been set.

Additionally, the following methods can be called which implicitly
call C<to_feed> (see L<XML::Feed>):

=over

=item * C<entries>

=back

So, for example, the following are equivalent:

  W('http://example.com/feed.atom')->to_feed->entries;
  W('http://example.com/feed.atom')->entries;

=back

=head2 Any Time Methods

These can be called either before or after the request, and do not
trigger the request to be made. They do not usually return the invocant
Web::Magic object, so are not usually suitable for chaning.

=over

=item C<< uri >>

Returns the original URI, as a URI object.

Additionally, the following methods can be called which implicitly
call C<uri> (see L<URI>):

=over

=item * C<scheme>

=item * C<authority>

=item * C<path>

=item * C<query>

=item * C<host>

=item * C<port>

=back

So, for example, the following are equivalent:

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
before continuing, throwing a Web::Magic::Exception::AssertionFailure
otherwise.

C<< $coderef >> should be a subroutine that returns true if everything
is OK, and false if something bad has happened. C<< $name >> is just a
label for the assertion, to provide a more helpful error message if the 
assertion fails.

 print W('http://example.com/data.json')
   ->assert_response(correct_type => sub { $_->content_type =~ /json/i })
   ->{people}[0]{name};

Your subroutine is called with the Web::Magic object as $_[0] (this
was changed between Web::Magic 0.003 and 0.004). Additionally, C<$_> is
set to the HTTP::Response object.

An assertion can be made at any time. If made before the request, then
it is queued up for checking later. If the assertion is made after the
request, it is checked immediately.

This method returns the invocant, so may be chained.

=item C<< assert_success >>

A shortcut for:

  assert_response(success => sub { $_->is_success })

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
call C<acme_24>:

=over

=item * C<random_jackbauer_fact>

=back

So, for example, the following are equivalent:

  W('http://example.com/')->acme_24->random_jackbauer_fact;
  W('http://example.com/')->random_jackbauer_fact;

This method exists to emphasize the whimsical and experimental
status of the current release of Web::Magic. If Web::Magic ever
becomes ready for serious production use, expect the following
to evaluate to false:

  W('http://example.com/')->can('random_jackbauer_fact')

=back

=head2 Private Methods

The following methods should not normally be used, but may be useful
for people wishing to subclass Web::Magic:

=over

=item * C<< _stash >>

A hashref for storing useful data.

=item * C<< _ua_string >>

User-Agent header string to use for HTTP requests.

=item * C<< _request_object >>

The (mutable) HTTP::Request object that can/will be used to issue the request.

=item * C<< _final_request_object(%default_headers) >>

Returns the HTTP::Request object that will be used to issue the request.
Sets C<< %default_headers >> as HTTP request headers only if they are not
already set. Serialises the request body from
C<< $self->_stash->{request_body} >>.

=item * C<< _check_assertions($reponse, @assertions) >>

Each assertion is a [name, coderef] arrayref. Checks each assertion against
the HTTP response, throwing exceptions as necessary.

=item * C<< _cancel_progress >>

A no-op in this implementation. This method is sometimes called just prior
to an exception being thrown. Thus, in an asynchronous implementation which
performs HTTP requests in a background thread, you can use this callback
to tidy up HTTP connections prior to the exception being thrown.

=back

=begin private

=item C<< AUTHORITY >>

=item C<< CAN >>

=item C<< can >>

=end private

=head2 Exceptions

Web::Magic's exceptions are subclasses of L<Exception::Class::Base> - the
documentation for that class lists several useful functions, such as:

 Web::Magic::Exception->Trace(1); # enable full stack traces

=head3 Web::Magic::Exception

B<Cause:> a general Web::Magic error has occurred.

=head3 Web::Magic::Exception::AssertionFailure

B<Cause:> an assertion failed.

B<Additional fields:> assertion_name, assertion_coderef, http_request, http_response.

=head3 Web::Magic::Exception::BadContent

B<Cause:> cannot coerce from a Perl object to HTTP message body.

B<Additional fields:> body.

=head3 Web::Magic::Exception::BadPhase

B<Cause:> a method has been called on a Web::Magic object  which is in the wrong state to perform that method.

=head3 Web::Magic::Exception::BadPhase::Cancel

B<Cause:> attempt to cancel a request that has already been performed.

=head3 Web::Magic::Exception::BadPhase::SetRequestBody

B<Cause:> attempt to set request body for a request that has already been performed.

B<Additional fields:> attempted_body, used_body.

=head3 Web::Magic::Exception::BadPhase::SetRequestHeader

B<Cause:> attempt to set a request header for a request that has already been performed.

B<Additional fields:> attempted_value, used_value, header.

=head3 Web::Magic::Exception::BadPhase::SetRequestMethod

B<Cause:> attempt to set request method for a request that has already been performed.

B<Additional fields:> attempted_method, used_method.

=head3 Web::Magic::Exception::BadPhase::WillNotRequest

B<Cause:> attempt to perform a request that was explicitly cancelled.

B<Additional fields:> cancellation.

=head3 Web::Magic::Exception::BadReponseType

B<Cause:> cannot coerce from an HTTP message body to a Perl object, because is is of the wrong type.

B<Additional fields:> content_type.

=head1 BUGS

Inumerable, almost certainly.

Have a go at enumerating them here:
L<http://rt.cpan.org/Dist/Display.html?Queue=Web-Magic>.

=head1 SEE ALSO

L<Web::Magic::Async>.

L<LWP::UserAgent>, L<URI>, L<HTTP::Request>, L<HTTP::Response>.

L<XML::LibXML>, L<JSON::JOM>, L<RDF::Trine>, L<XML::Feed>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2011-2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

