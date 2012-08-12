package Web::Magic::Spellbook::RDF;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.009';

package Web::Magic;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized once void);
use utf8;

push our @SPELLBOOK => qw(RDF);

our %HANDLER;
$HANDLER{$_} = 'to_model'
	foreach qw/subjects predicates objects objects_for_predicate_list
		get_pattern get_statements count_statements get_sparql as_stream/;

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
			$stash->{model} = $self->_rdfa_stuff->graph;
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

sub _rdfa_stuff
{
	my ($self) = @_;
	my $stash = $self->_stash;

	$self->__deferred_load(
		'RDF::RDFa::Parser'    => '1.096',
		);

	unless (exists $stash->{rdfa})
	{
		$stash->{rdfa} = RDF::RDFa::Parser->new_from_url($self->response);
		$stash->{rdfa}->consume;
	}
	
	return $stash->{rdfa};
}

sub opengraph
{
	my ($self) = @_;
	my $return;
	
	local $@ = undef;
	eval
	{
		my $rdfa = $self->_rdfa_stuff;
		foreach my $property ($rdfa->opengraph)
		{
			$return->{$property} = $rdfa->opengraph($property)
		}
		1;
	}
	or do
	{
		warn $@;
		return {};
	};
		
	$return;
}

1;

