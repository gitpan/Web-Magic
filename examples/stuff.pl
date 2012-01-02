use 5.010;
use lib "lib";
use Web::Magic -sub => 'W';

say Web::Magic->can('random_jackbauer_fact');

my $u = W q{ http://json-schema.org/card };
say $u->uri->authority;
#say $u->{description}; ## annoying - the JSON response is syntactically broken

say W(q{ http://json-schema.org/ })
	->getElementsByTagName('ul')
	->shift
	->toString;

say W(q{ http://www.cpantesters.org/distro/R/RDF-Query-Client.yaml })
	->[0]
	->dump;
	
say W(q{ http://json-schema.org/ });
say Web::Magic->random_jackbauer_fact;
say Web::Magic->random_jackbauer_factq;
