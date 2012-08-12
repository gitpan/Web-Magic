package Web::Magic::Spellbook::Feeds;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.009';

package Web::Magic;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized once void);
use utf8;

push our @SPELLBOOK => qw(Feeds);

our %HANDLER;
$HANDLER{$_} = 'to_feed'
	foreach qw/entries/;

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

1;
