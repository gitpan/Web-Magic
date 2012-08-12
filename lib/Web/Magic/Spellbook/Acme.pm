package Web::Magic::Spellbook::Acme;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.009';

package Web::Magic;

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized once void);
use utf8;

push our @SPELLBOOK => qw(Acme);

our %HANDLER;
$HANDLER{$_} = 'acme_24'
	foreach qw/random_jackbauer_fact/;

sub acme_24
{
	my ($self) = @_;
	$self->__deferred_load('Acme::24' => '0.03');
	return 'Acme::24';
}

1;

