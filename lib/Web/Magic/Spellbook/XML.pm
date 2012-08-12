package Web::Magic::Spellbook::XML;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.009';

package Web::Magic;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized once void);
use utf8;

push our @SPELLBOOK => qw(XML HTML);

our %HANDLER;
$HANDLER{$_} = 'to_dom'
	foreach qw/getElementsByTagName getElementsByTagNameNS
		getElementsByLocalName getElementsById documentElement
		cloneNode firstChild lastChild findnodes find findvalue
		exists childNodes attributes getNamespaces
		querySelector querySelectorAll/;

our %XPaths;
BEGIN {
	my $thingsWithSrc = '(local-name()="img" or local-name()="video" or local-name()="audio" or local-name()="source" or local-name()="script") and @src';
	%XPaths = (
		'~links'     => '//*[(local-name()="a" or local-name()="area" or local-name()="link") and @href]',
		'~images'    => '//*[local-name()="img" and @src]',
		'~resources' => "//*[($thingsWithSrc) or (local-name()=\"object\" and \@data)]",
		);
}

sub to_dom
{
	my ($self) = @_;
	my $stash = $self->_stash;

	$self->__deferred_load(
		'HTML::HTML5::Parser'        => '0.100',
		'HTML::HTML5::Writer'        => '0.100',
		'XML::LibXML'                => '1.94',
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
				->new->parse_string($self->response->decoded_content, 
					($self->response->base // $$self));
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
		
		$stash->{dom}->setURI( $self->response->base // $$self );
	}
	
	if (ref($stash->{dom}) eq 'XML::LibXML::Document'
	and UNIVERSAL::can('XML::LibXML::Augment', 'can')
	and XML::LibXML::Augment->can('rebless'))
	{
		XML::LibXML::Augment->rebless( $stash->{dom} );
	}
	
	return $stash->{dom};
}

sub findnodes
{
	my ($self, $xpath, @etc) = @_;
	
	if ($xpath =~ qr{^ ~ \w+ $}x and exists $XPaths{$xpath})
	{
		$xpath = $XPaths{$xpath};
	}
	
	return $self->to_dom->findnodes($xpath, @etc);
}

sub make_absolute_urls
{
	my ($self, $xpc, @xpaths) = @_;
	
	unless (@xpaths)
	{
		if ($self->header('Content-Type') =~ /html/i)
		{
			@xpaths = qw(
				//xhtml:*/@href
				//xhtml:*/@src
				//xhtml:*/@cite
				//xhtml:form/@action
				//xhtml:object/@data
				//xhtml:a/@ping
				//xhtml:img/@longdesc
				//xhtml:img/@lowsrc
				//xhtml:video/@poster
				);
		}
	}
	
	return $self unless @xpaths;
	
	my $dom; eval { $dom = $self->to_dom };
	return $self unless $dom;
	
	unless ($xpc)
	{
		$xpc = XML::LibXML::XPathContext->new;
		$xpc->registerNs(xhtml => NAMESPACE_XHTML)
			if $self->header('Content-Type') =~ /html/i;
	}
	
	$xpc->setContextNode($dom) unless $xpc->getContextNode;
	
	my @nodes = map { my @n = $xpc->findnodes($_); @n; } @xpaths;
	
	foreach my $node (@nodes)
	{
		my $base = $node->baseURI // $dom->URI;
		
		if ($node->isa('XML::LibXML::Attr'))
		{
			my $uri = URI->new_abs($node->getValue, $base);
			$node->setValue("$uri");
		}
		elsif ($node->isa('XML::LibXML::Text'))
		{
			my $uri = URI->new_abs($node->data, $base);
			$node->setData("$uri");
		}
	}
	
	return $self;
}

1;
