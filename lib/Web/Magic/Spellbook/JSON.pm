package Web::Magic::Spellbook::JSON;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.009';

package Web::Magic;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized once void);
use utf8;

push our @SPELLBOOK => qw(JSON YAML);

use JSON::JOM 0.501                qw/to_jom from_json to_json/;
use JSON::JOM::Plugins::Dumper 0   qw//;
use JSON::JOM::Plugins::JsonPath 0 qw//;
use YAML::Any 0                    qw/Load Dump/;

use overload
	'%{}'  => \&to_hashref,
	'@{}'  => \&to_hashref,
	;
	
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

sub json_findnodes
{
	my ($self, $path) = @_;
	return $self->to_hashref->findNodes($path);
}

1;
